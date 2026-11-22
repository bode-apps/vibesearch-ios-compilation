// Journal VibeSearch : renvoie à l'appli les erreurs de l'extension (arrière-plan et fenêtre),
// pour les diagnostiquer sans ordinateur Mac. Ajouté devant les scripts de l'extension à la compilation.
;(() => {
  const api = typeof browser !== 'undefined' ? browser : typeof chrome !== 'undefined' ? chrome : null
  const lieu = typeof window === 'undefined' ? 'arrière-plan' : location.pathname.split('/').slice(-2).join('/')
  const texte = (x) => {
    if (x && (x.stack || x.message)) return ((x.name || 'Erreur') + ': ' + (x.message || '') + ' | ' + String(x.stack || '')).slice(0, 1500)
    if (x && typeof x === 'object') { try { return JSON.stringify(x).slice(0, 800) } catch (e) { return String(x) } }
    return String(x)
  }
  const envoyer = (message) => {
    try {
      const r = api && api.runtime && api.runtime.sendNativeMessage && api.runtime.sendNativeMessage('vibesearch', { command: 'vibeJournal', lieu, message: String(message).slice(0, 2000) })
      if (r && r.catch) r.catch(() => {})
    } catch (e) {}
  }
  self.addEventListener('error', (e) => envoyer('erreur : ' + (e.message || texte(e.error)) + ' @ ' + (e.filename || '').split('/').pop() + ':' + (e.lineno || '')))
  self.addEventListener('unhandledrejection', (e) => envoyer('rejet : ' + texte(e.reason)))
  const erreur = console.error.bind(console)
  console.error = (...a) => { envoyer('console : ' + a.map(texte).join(' ')); erreur(...a) }
  envoyer('démarré')
})();
