// Résultats d'une page de moteur de recherche (monde isolé, à la demande) pour la réponse IA.
// Méthode générique (Google mobile ou ordinateur, Bing, DuckDuckGo, Brave, Startpage…) : les liens
// sortants de la zone des résultats qui portent un titre, avec le texte du bloc qui les entoure.
// Renvoie du JSON : { requete, resultats: [{ titre, url, extrait }] } (8 au plus).
;(() => {
  const u = new URL(location.href)
  const requete = u.searchParams.get('q') || u.searchParams.get('query') || u.searchParams.get('p') || ''
  const texte = (e) => ((e && (e.innerText || e.textContent)) || '').replace(/\s+/g, ' ').trim()
  const moteur = /(^|\.)(google\.[a-z.]+|gstatic\.com|googleusercontent\.com|bing\.com|microsoft\.com|msn\.com|duckduckgo\.com|startpage\.com|brave\.com|yahoo\.com|qwant\.com)$/
  const nettoyer = (href) => {
    try {
      const h = new URL(href, location.href)
      // Liens enveloppés par le moteur (Google /url?q=…, DuckDuckGo uddg=…, Bing ck/a?u=…)
      if (/google\./.test(h.hostname) && h.pathname === '/url') return h.searchParams.get('q') || h.searchParams.get('url') || ''
      if (/duckduckgo\.com$/.test(h.hostname) && h.searchParams.get('uddg')) return h.searchParams.get('uddg')
      return h.href
    } catch (e) {
      return ''
    }
  }
  const zone =
    document.querySelector('#rso, #search, #b_results, #links, .react-results--main, #results, [data-testid=mainline], main') || document.body
  const vus = new Set()
  const resultats = []
  for (const a of zone.querySelectorAll('a[href]')) {
    if (resultats.length >= 8) break
    const href = nettoyer(a.getAttribute('href') || '')
    if (!/^https?:/.test(href)) continue
    let cible
    try {
      cible = new URL(href)
    } catch (e) {
      continue
    }
    // Google (2026) : liens opaques « /goto?url=… » vers le site ; on les garde (ils mènent au bon endroit)
    const opaque = /google\./.test(cible.hostname) && cible.pathname === '/goto'
    if (!opaque && moteur.test(cible.hostname)) continue
    const titreEl = a.querySelector('h3, h2, [role=heading], [aria-level]')
    const titre = texte(titreEl) || texte(a)
    // Lien de résultat = un titre, ou un texte assez long (pas les petits liens de navigation)
    if (titre.length < 8 || (!titreEl && titre.length < 25)) continue
    const cle = opaque ? cible.href : cible.hostname + cible.pathname
    if (vus.has(cle)) continue
    vus.add(cle)
    // Bloc du résultat : on remonte jusqu'à trouver le texte de présentation
    let bloc = a
    for (let i = 0; i < 6 && bloc.parentElement && bloc.parentElement !== zone; i++) {
      bloc = bloc.parentElement
      if (texte(bloc).length > titre.length + 80) break
    }
    // Adresse affichée par le moteur (« fr.wikipedia.org › wiki ») : la vraie source d'un lien opaque
    const affichee = texte(a.querySelector('cite') || bloc.querySelector('cite'))
    let extrait = texte(bloc).replace(titre, '')
    if (affichee) extrait = extrait.replace(affichee, '')
    extrait = (affichee ? '(' + affichee + ') ' : '') + extrait.trim()
    resultats.push({ titre: titre.slice(0, 200), url: cible.href, extrait: extrait.slice(0, 500) })
  }
  return JSON.stringify({ requete, resultats })
})()
