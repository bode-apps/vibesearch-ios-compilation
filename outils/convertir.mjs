// Conversion des listes de filtrage (syntaxe Adblock Plus / EasyList) vers les
// « content rule lists » de WebKit (format JSON compris par WKContentRuleListStore).
//
// WebKit compile ces règles en automate une seule fois : le blocage ne coûte ensuite
// presque rien (aucun JavaScript, aucun aller-retour vers l'appli). C'est la voie
// la plus rapide et la plus économe en batterie sur iPhone.
//
// Contraintes WebKit respectées ici :
//  - url-filter : sous-ensemble d'expressions régulières (., *, +, ?, [..], [^..], (..), ^, $),
//    pas d'alternance « | », pas de quantificateur {n}, ASCII uniquement ;
//  - if-domain / unless-domain : minuscules, « *exemple.fr » = domaine et sous-domaines,
//    jamais les deux dans la même règle ;
//  - « ignore-previous-rules » n'annule que les règles placées AVANT : l'ordre compte.

const TYPES = {
  script: 'script',
  image: 'image',
  stylesheet: 'style-sheet',
  font: 'font',
  media: 'media',
  xmlhttprequest: 'raw',
  xhr: 'raw',
  websocket: 'raw',
  ping: 'raw',
  other: 'raw',
  subdocument: 'document',
  frame: 'document',
  popup: 'popup',
  css: 'style-sheet'
}

const TYPES_RESSOURCES = ['image', 'style-sheet', 'script', 'font', 'raw', 'svg-document', 'media']

// Options sans effet pour nous (ignorées sans risque)
const OPTIONS_NEUTRES = new Set(['important', 'match-case', 'all', 'third-party', '3p', '~third-party', '1p', 'first-party', '~first-party'])
// Options qu'on ne sait pas rendre fidèlement : la règle est abandonnée (mieux vaut ne
// rien bloquer que casser un site).
const OPTIONS_REFUSEES = /^(~?(object|object-subrequest|webrtc|genericblock|inline-script|inline-font)|csp|redirect|redirect-rule|removeparam|queryprune|rewrite|header|replace|permissions|denyallow|to|method|urltransform|uritransform|empty|mp4|cname|ipaddress|strict1p|strict3p|sitekey|urlskip|reason)(=|$)/

/** Échappe un texte pour l'expression régulière WebKit. */
function echapper(s) {
  return s.replace(/[.+?()[\]{}\\$|]/g, (c) => '\\' + c)
}

/** Motif ABP (sans options) → url-filter WebKit, ou null si impossible. */
export function motifVersRegex(motif) {
  let p = motif
  if (!p) return '.*'
  if (/[^\x20-\x7e]/.test(p)) return null
  let debut = ''
  let fin = ''
  let dansHote = false
  if (p.startsWith('||')) {
    p = p.slice(2)
    // nom d'hôte en minuscules (WebKit compare les adresses déjà normalisées)
    p = p.replace(/^[^/^*:|]+/, (h) => h.toLowerCase())
    dansHote = true
    // « ||exemple.fr^ » : le domaine et tous ses sous-domaines, quel que soit le protocole
    debut = '^[^:]+://+([^:/]+\\.)?'
    // Si le motif commence par un nom d'hôte suivi de « ^ » ou de « / », on ancre la fin de l'hôte
  } else if (p.startsWith('|')) {
    p = p.slice(1)
    debut = '^'
  }
  if (p.endsWith('|')) {
    p = p.slice(0, -1)
    fin = '$'
  }
  if (!p) return null
  // Le séparateur « ^ » final (ou suivi uniquement de « * ») devient optionnel en fin d'adresse :
  // WebKit n'a pas d'alternance, on accepte donc tout séparateur ou rien.
  const morceaux = []
  for (let i = 0; i < p.length; i++) {
    const c = p[i]
    if (c === '*') {
      dansHote = false
      if (morceaux[morceaux.length - 1] !== '.*') morceaux.push('.*')
    } else if (c === '^' && dansHote) {
      // fin du nom d'hôte : dans une adresse normalisée il est toujours suivi de « : » ou « / »
      dansHote = false
      morceaux.push('[:/]')
    } else if (c === '^') {
      const reste = p.slice(i + 1).replace(/\*/g, '')
      if (reste === '' && !fin) {
        // fin de motif : séparateur ou fin d'adresse → on se contente de « rien d'autre de
        // lettre/chiffre » de manière optionnelle (léger excès de blocage, comme les autres bloqueurs)
        morceaux.push('([^-_.%A-Za-z0-9].*)?$')
        break
      }
      morceaux.push('[^-_.%A-Za-z0-9]')
    } else {
      if (c === '/' || c === ':') dansHote = false
      morceaux.push(echapper(c))
    }
  }
  // Nettoyage : un « .* » en tête ou en queue est inutile (et ralentit la compilation)
  while (morceaux[0] === '.*' && !debut) morceaux.shift()
  while (morceaux[morceaux.length - 1] === '.*' && !fin) morceaux.pop()
  const r = debut + morceaux.join('') + fin
  if (r === '' || r === '^') return '.*'
  // Garde-fous : motifs trop généraux ou trop coûteux
  if (r.length > 500) return null
  if ((r.match(/\.\*/g) ?? []).length > 6) return null
  return r
}

/** « a.fr|~b.fr » → { si: [...], sauf: [...] } au format WebKit. */
function domaines(liste) {
  const si = []
  const sauf = []
  for (let d of liste.split(/[|,]/)) {
    d = d.trim().toLowerCase()
    if (!d) continue
    const neg = d.startsWith('~')
    if (neg) d = d.slice(1)
    // Domaines génériques (« exemple.* ») et non ASCII : WebKit ne sait pas les décrire
    if (d.endsWith('.*') || /[^a-z0-9.-]/.test(d)) return null
    ;(neg ? sauf : si).push('*' + d)
  }
  return { si, sauf }
}

/** Analyse une règle réseau. Renvoie une règle WebKit, ou null si on l'abandonne. */
export function regleReseau(ligne) {
  let texte = ligne
  const exception = texte.startsWith('@@')
  if (exception) texte = texte.slice(2)
  // Expression régulière brute (/…/) : syntaxe trop riche pour WebKit
  if (texte.startsWith('/') && /\/(\$|$)/.test(texte.slice(1))) return null
  let options = []
  const dollar = texte.lastIndexOf('$')
  if (dollar >= 0 && /^~?[a-z0-9-]+(=|,|$)/i.test(texte.slice(dollar + 1))) {
    options = texte.slice(dollar + 1).split(',')
    texte = texte.slice(0, dollar)
  }
  const trigger = {}
  const types = new Set()
  const typesExclus = new Set()
  let documentEntier = false
  let masquage = false
  let sousCadre = false
  for (const brut of options) {
    const o = brut.toLowerCase()
    if (OPTIONS_REFUSEES.test(o)) return null
    if (o === 'third-party' || o === '3p' || o === '~first-party' || o === '~1p') trigger['load-type'] = ['third-party']
    else if (o === '~third-party' || o === '~3p' || o === 'first-party' || o === '1p') trigger['load-type'] = ['first-party']
    else if (o === 'match-case') trigger['url-filter-is-case-sensitive'] = true
    else if (o.startsWith('domain=') || o.startsWith('from=')) {
      const d = domaines(o.slice(o.indexOf('=') + 1))
      if (!d) return null
      // WebKit n'accepte pas if-domain et unless-domain ensemble : une règle qui mélange les deux
      // (« a.com|~b.a.com ») ne peut pas être rendue fidèlement → abandonnée
      if (d.si.length && d.sauf.length) return null
      if (d.si.length) trigger['if-domain'] = d.si
      else if (d.sauf.length) trigger['unless-domain'] = d.sauf
    } else if (o === 'document' || o === 'doc') {
      if (exception) documentEntier = true
      else types.add('document')
    } else if (o === 'elemhide' || o === 'ehide') {
      if (!exception) return null
      masquage = 'tout'
    } else if (o === 'generichide' || o === 'ghide') {
      if (!exception) return null
      masquage = 'generique'
    } else if (o === 'specifichide' || o === 'shide') {
      return null
    } else if (o === 'subdocument' || o === 'frame') {
      types.add('document')
      sousCadre = true
    } else if (o === 'popup') types.add('popup')
    else if (o.startsWith('~') && TYPES[o.slice(1)]) typesExclus.add(TYPES[o.slice(1)])
    else if (TYPES[o]) types.add(TYPES[o])
    else if (OPTIONS_NEUTRES.has(o)) continue
    else return null // option inconnue : prudence
  }
  // Sans type précisé, une règle ABP vise les ressources de la page, pas la page elle-même :
  // on exclut « document » (sinon page blanche) et « popup ».
  if (!exception && !types.size) for (const t of TYPES_RESSOURCES) if (!typesExclus.has(t)) types.add(t)
  if (exception && typesExclus.size && !types.size) for (const t of TYPES_RESSOURCES) if (!typesExclus.has(t)) types.add(t)
  // « document » obtenu par $subdocument : seulement dans les cadres, jamais la page principale
  if (sousCadre && !documentEntier) trigger['load-context'] = ['child-frame']
  if (sousCadre && types.size > 1) return null // mélange cadre + autres types : impossible en une règle
  const filtre = motifVersRegex(texte)
  if (!filtre) return null
  trigger['url-filter'] = filtre
  if (types.size) trigger['resource-type'] = [...types].sort()
  if (exception && (documentEntier || masquage)) {
    // Exception pour tout un site : on l'exprime en « if-domain » quand le motif est un domaine simple
    const m = /^\|\|([a-z0-9.-]+)\^?$/i.exec(texte)
    if (m && !trigger['if-domain'] && !trigger['unless-domain']) {
      return { exception: true, portee: documentEntier ? 'site' : masquage === 'generique' ? 'generique' : 'masquage', regle: { trigger: { 'url-filter': '.*', 'if-domain': ['*' + m[1].toLowerCase()] }, action: { type: 'ignore-previous-rules' } } }
    }
    return null
  }
  // Une règle de blocage sans motif ni restriction bloquerait tout le web : refusée
  if (!exception && filtre === '.*' && !trigger['if-domain']) return null
  return { exception, regle: { trigger, action: { type: exception ? 'ignore-previous-rules' : 'block' } } }
}

// Pseudo-classes propres à uBlock / AdGuard / ABP : WebKit ne les connaît pas
const CSS_EXOTIQUE = /:(-abp-|has-text|contains|xpath|upward|style|remove|matches-css|matches-path|matches-attr|matches-media|min-text-length|watch-attr|others|nth-ancestor|if|if-not|properties|matches-property|shadow)|\[-ext-|:-ext-/

/** Sélecteur CSS acceptable pour css-display-none ? */
export function selecteurValide(s) {
  if (!s || s.length > 400) return false
  if (/[^\x20-\x7e]/.test(s)) return false
  if (CSS_EXOTIQUE.test(s)) return false
  if (/^\s*[+>~]/.test(s) || /[{}]/.test(s)) return false
  // Parenthèses et crochets équilibrés (sinon le groupe entier serait rejeté par le moteur CSS)
  let p = 0
  let c = 0
  for (const ch of s) {
    if (ch === '(') p++
    else if (ch === ')') p--
    else if (ch === '[') c++
    else if (ch === ']') c--
    if (p < 0 || c < 0) return false
  }
  if (p || c) return false
  // Guillemets appariés
  if (((s.match(/"/g) ?? []).length & 1) || ((s.match(/'/g) ?? []).length & 1)) return false
  return true
}

/**
 * Convertit le texte d'une liste en règles WebKit, dans l'ordre qui garantit le bon
 * fonctionnement des exceptions :
 *   1. masquage générique, 2. masquage par site, 3. exceptions « elemhide » (n'annulent que 1–2),
 *   4. blocages réseau, 5. exceptions réseau et sites entiers autorisés.
 */
export function convertirListe(texte, { tailleGroupe = 400 } = {}) {
  const generiques = []
  const parSite = [] // { sel, si: [...], sauf: [...] }
  const exceptionsSel = new Map() // sélecteur → Set de domaines où il ne faut PAS masquer
  const exceptionsTotales = new Set() // « #@#sel » : sélecteur désactivé partout
  const exceptionsGeneriques = [] // $generichide : n'annule que le masquage générique
  const exceptionsMasquage = [] // $elemhide : annule tout le masquage
  const blocages = []
  const exceptions = []
  const desactivees = new Set() // $badfilter
  const stats = { lignes: 0, reseau: 0, cosmetique: 0, abandon: 0 }

  const lignes = texte.split(/\r?\n/)
  for (const l of lignes) {
    const m = /^(.*)\$badfilter$/.exec(l.trim()) ?? /^(.*),badfilter$/.exec(l.trim())
    if (m) desactivees.add(m[1])
  }
  for (const brut of lignes) {
    const ligne = brut.trim()
    if (!ligne || ligne.startsWith('!') || ligne.startsWith('[')) continue
    stats.lignes++
    if (desactivees.has(ligne) || /(\$|,)badfilter$/.test(ligne)) continue
    // Règles cosmétiques
    const cos = /^([^#]*?)(##|#@#|#\?#|#\$#|#@\$#|#@\?#|#%#|#@%#|\$\$|#\+js)(.*)$/.exec(ligne)
    if (cos && !ligne.startsWith('@@') && !ligne.startsWith('|') && /^[a-z0-9.*,~_-]*$/i.test(cos[1])) {
      const [, doms, sep, sel] = cos
      if (sep === '#@#') {
        if (!doms) {
          exceptionsTotales.add(sel)
        } else {
          const d = domaines(doms)
          if (d) {
            if (!exceptionsSel.has(sel)) exceptionsSel.set(sel, new Set())
            for (const x of d.si) exceptionsSel.get(sel).add(x)
          }
        }
        continue
      }
      if (sep !== '##' || !selecteurValide(sel) || sel.startsWith('+js(')) {
        stats.abandon++
        continue
      }
      if (!doms) {
        generiques.push(sel)
      } else {
        const d = domaines(doms)
        if (!d) {
          stats.abandon++
          continue
        }
        parSite.push({ sel, si: d.si, sauf: d.sauf })
      }
      stats.cosmetique++
      continue
    }
    if (/#[@$?%]?#/.test(ligne) && !ligne.includes('$')) {
      stats.abandon++
      continue
    }
    const r = regleReseau(ligne)
    if (!r) {
      stats.abandon++
      continue
    }
    stats.reseau++
    if (r.portee === 'masquage') exceptionsMasquage.push(r.regle)
    else if (r.portee === 'generique') exceptionsGeneriques.push(r.regle)
    else if (r.exception) exceptions.push(r.regle)
    else blocages.push(r.regle)
  }

  // Masquage regroupé par condition de domaine identique (moins de règles = compilation plus rapide)
  const groupes = new Map() // clé de condition → { condition, sels }
  const ajouter = (genre, liste, sel) => {
    const cle = genre + ':' + liste.join(',')
    if (!groupes.has(cle)) groupes.set(cle, { genre, liste, sels: [] })
    groupes.get(cle).sels.push(sel)
  }
  const regles = []
  const sansException = []
  for (const sel of new Set(generiques)) {
    if (exceptionsTotales.has(sel)) continue
    const ex = exceptionsSel.get(sel)
    // « site#@#.pub » : le masquage générique de .pub continue partout SAUF sur ce site
    if (ex && ex.size) ajouter('sauf', [...ex].sort(), sel)
    else sansException.push(sel)
  }
  for (let i = 0; i < sansException.length; i += tailleGroupe) {
    regles.push({ trigger: { 'url-filter': '.*' }, action: { type: 'css-display-none', selector: sansException.slice(i, i + tailleGroupe).join(', ') } })
  }
  const pousserGroupes = () => {
    for (const { genre, liste, sels } of groupes.values()) {
      for (let i = 0; i < sels.length; i += tailleGroupe) {
        const trigger = { 'url-filter': '.*' }
        trigger[genre === 'si' ? 'if-domain' : 'unless-domain'] = liste
        regles.push({ trigger, action: { type: 'css-display-none', selector: sels.slice(i, i + tailleGroupe).join(', ') } })
      }
    }
    groupes.clear()
  }
  pousserGroupes()
  // $generichide n'annule que ce qui précède : le masquage générique
  regles.push(...exceptionsGeneriques)
  for (const { sel, si, sauf } of parSite) {
    if (exceptionsTotales.has(sel)) continue
    const ex = exceptionsSel.get(sel) ?? new Set()
    if (si.length) {
      const restants = si.filter((d) => !ex.has(d))
      if (restants.length) ajouter('si', restants.sort(), sel)
    } else {
      ajouter('sauf', [...new Set([...sauf, ...ex])].sort(), sel)
    }
  }
  pousserGroupes()
  regles.push(...exceptionsMasquage, ...dedoublonner(blocages), ...dedoublonner(exceptions))
  return { regles, stats }
}
function dedoublonner(regles) {
  const vu = new Set()
  return regles.filter((r) => {
    const k = JSON.stringify(r)
    if (vu.has(k)) return false
    vu.add(k)
    return true
  })
}

/** Découpe en morceaux sous la limite WebKit (150 000 règles par liste), exceptions recopiées à la fin de chaque morceau. */
export function decouper(regles, max = 140000) {
  if (regles.length <= max) return [regles]
  const exceptions = regles.filter((r) => r.action.type === 'ignore-previous-rules')
  const autres = regles.filter((r) => r.action.type !== 'ignore-previous-rules')
  const place = max - exceptions.length
  if (place < 1000) throw new Error('trop d’exceptions pour découper la liste')
  const morceaux = []
  for (let i = 0; i < autres.length; i += place) morceaux.push([...autres.slice(i, i + place), ...exceptions])
  return morceaux
}
