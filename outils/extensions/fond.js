// VibeSearch : fait tourner l'arrière-plan d'une extension prévu pour un « service worker »
// (interdit par WebKit dans les applis sans autorisation spéciale d'Apple) dans une page
// d'arrière-plan classique, comme Firefox. Les morceaux webpack chargés d'avance par le
// manifeste sont rejoués quand le code demande importScripts().
;(() => {
  if (typeof self.importScripts === 'function') return
  const cle = 'webpackChunk_bitwarden_browser'
  const gardes = []
  const tableau = self[cle] = self[cle] || []
  tableau.push = function (...entrees) {
    for (const e of entrees) gardes.push([e[0].slice(), e[1], e[2]])
    return Array.prototype.push.apply(this, entrees)
  }
  self.importScripts = function (...adresses) {
    for (const a of adresses) {
      const id = String(a).split('/').pop().split('.')[0]
      const e = gardes.find((g) => g[0].map(String).includes(id))
      if (!e) throw new Error('importScripts indisponible dans la page d\'arrière-plan : ' + a)
      self[cle].push([e[0].slice(), e[1], e[2]])
    }
  }
})();
