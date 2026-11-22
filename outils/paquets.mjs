// Assemble les scripts JavaScript embarqués dans l'appli (sortie : VibeSearch/Ressources/Generees/).
//  - consentement-page.js : moteur autoconsent (DuckDuckGo, MPL-2.0) injecté dans les pages,
//    dans un « monde » JavaScript isolé : la page ne le voit pas et ne peut pas le perturber ;
//  - consentement-regles.js : le « fond » d'autoconsent (règles compactes + filtre par adresse),
//    chargé UNE fois dans un JSContext natif. Les pages ne reçoivent que les règles utiles.
import { build } from 'esbuild'
import { mkdir } from 'node:fs/promises'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const RACINE = join(dirname(fileURLToPath(import.meta.url)), '..')
const SORTIE = join(RACINE, 'VibeSearch', 'Ressources', 'Generees')
await mkdir(SORTIE, { recursive: true })

const commun = { bundle: true, minify: true, legalComments: 'none', target: ['safari16'], logLevel: 'warning' }

await build({
  ...commun,
  format: 'iife',
  stdin: {
    resolveDir: RACINE,
    contents: `
import AutoConsent from '@duckduckgo/autoconsent'
;(() => {
  if (!/^https?:$/.test(location.protocol)) return
  const canal = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vibeConsent
  if (!canal) return
  const mainFrame = window === window.top
  let consent = null
  const envoyer = async (msg) => {
    try {
      if (msg.type === 'report') return // télémétrie interne d'autoconsent : inutile
      let rep = await canal.postMessage(Object.assign({}, msg, { url: location.href, mainFrame }))
      if (typeof rep === 'string') rep = JSON.parse(rep)
      if (rep && consent) await consent.receiveMessageCallback(rep)
    } catch (e) { /* navigation en cours : on ignore */ }
  }
  consent = new AutoConsent(envoyer)
})()
`
  },
  outfile: join(SORTIE, 'consentement-page.js')
})

await build({
  ...commun,
  format: 'iife',
  stdin: {
    resolveDir: RACINE,
    contents: `
import { filterCompactRules } from '@duckduckgo/autoconsent'
import regles from '@duckduckgo/autoconsent/rules/compact-rules.json'
globalThis.vibeRegles = (url, mainFrame) => JSON.stringify(filterCompactRules(regles, { url, mainFrame }))
`
  },
  outfile: join(SORTIE, 'consentement-regles.js')
})
console.log('Scripts autoconsent assemblés')
