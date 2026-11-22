// Télécharge les listes de filtrage et les convertit pour WebKit.
// Usage : node outils/listes.mjs [--cache <dossier>]   (sortie : VibeSearch/Ressources/Generees/)
// Lancé par la compilation sur GitHub : chaque version de l'appli embarque des listes fraîches.
import { mkdir, writeFile, readFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { convertirListe, decouper } from './convertir.mjs'

const RACINE = join(dirname(fileURLToPath(import.meta.url)), '..')
const SORTIE = join(RACINE, 'VibeSearch', 'Ressources', 'Generees')

// id → source. « pubs » et « traqueurs » sont activables séparément dans les réglages.
// Une entrée peut fusionner plusieurs sources : les exceptions de l'une s'appliquent alors à l'autre
// (WebKit n'applique « ignore-previous-rules » qu'à l'intérieur d'une même liste compilée).
const LISTES = [
  {
    id: 'pubs',
    nom: 'EasyList + Liste FR',
    sources: ['https://easylist.to/easylist/easylist.txt', 'https://easylist-downloads.adblockplus.org/liste_fr.txt']
  },
  { id: 'traqueurs', nom: 'EasyPrivacy', sources: ['https://easylist.to/easylist/easyprivacy.txt'] }
]

const args = process.argv.slice(2)
const cache = args.includes('--cache') ? args[args.indexOf('--cache') + 1] : null

async function texteDe(adresse) {
  const liste = { nom: adresse.split('/').pop(), url: adresse }
  const local = cache && join(cache, liste.url.split('/').pop())
  if (local && existsSync(local)) return readFile(local, 'utf8')
  for (let essai = 1; essai <= 4; essai++) {
    try {
      const r = await fetch(liste.url, { headers: { 'user-agent': 'VibeSearch-iOS-build' } })
      if (!r.ok) throw new Error(`HTTP ${r.status}`)
      const t = await r.text()
      if (t.length < 10000) throw new Error('liste trop courte')
      return t
    } catch (e) {
      console.warn(`${liste.nom} : essai ${essai} raté (${e.message})`)
      await new Promise((ok) => setTimeout(ok, 2000 * essai))
    }
  }
  throw new Error(`impossible de télécharger ${liste.nom}`)
}

await mkdir(SORTIE, { recursive: true })
const manifeste = { genere: new Date().toISOString(), listes: [] }
for (const liste of LISTES) {
  const textes = []
  for (const s of liste.sources) textes.push(await texteDe(s))
  const { regles, stats } = convertirListe(textes.join('\n'))
  const morceaux = decouper(regles)
  morceaux.forEach((m, i) => {
    const id = morceaux.length > 1 ? `${liste.id}-${i + 1}` : liste.id
    manifeste.listes.push({ id, groupe: liste.id.startsWith('pubs') ? 'pubs' : 'traqueurs', nom: liste.nom, regles: m.length })
  })
  for (let i = 0; i < morceaux.length; i++) {
    const id = morceaux.length > 1 ? `${liste.id}-${i + 1}` : liste.id
    await writeFile(join(SORTIE, `regles-${id}.json`), JSON.stringify(morceaux[i]))
  }
  console.log(`${liste.nom} : ${regles.length} règles WebKit (${stats.reseau} réseau, ${stats.cosmetique} cosmétiques, ${stats.abandon} abandonnées sur ${stats.lignes})`)
}
// Empreinte de version : l'appli recompile ses listes seulement quand elle change
manifeste.version = manifeste.genere
await writeFile(join(SORTIE, 'listes.json'), JSON.stringify(manifeste, null, 1))
