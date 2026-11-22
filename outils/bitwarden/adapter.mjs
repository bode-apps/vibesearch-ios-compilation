// Petite adaptation du code officiel de Bitwarden (version Safari, manifeste v3) pour le moteur
// d'extensions de WebKit dans VibeSearch : sans document « offscreen » (propre à Chrome), le
// stockage de secours de Bitwarden échouait. Il devient inerte (Bitwarden garde son stockage
// principal, chrome.storage). Aucune autre modification : c'est le vrai Bitwarden.
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const racine = process.argv[2] || '.'
const fichier = join(racine, 'apps/browser/src/platform/storage/offscreen-storage.service.ts')
let s = readFileSync(fichier, 'utf8')
const garde = 'if (typeof chrome === "undefined" || typeof chrome.offscreen === "undefined") { return null as any; }'
let n = 0
s = s.replace(/(async (get|has|save|remove)<?[^(]*\([^)]*\)[^{]*\{)/g, (m) => { n++; return m + '\n    ' + garde })
if (n !== 4) {
  console.error(`adapter.mjs : ${n} méthodes adaptées au lieu de 4 — le code de Bitwarden a changé`)
  process.exit(1)
}
writeFileSync(fichier, s)
console.log('offscreen-storage.service.ts adapté (4 méthodes)')
