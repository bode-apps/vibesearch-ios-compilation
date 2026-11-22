// Passerelle Orion → VibeSearch : Orion est le navigateur par défaut d'iOS (choix permis gratuitement),
// et chaque page qu'il ouvre est aussitôt envoyée à VibeSearch. Orion ne garde qu'un onglet vide.
// Pause possible depuis le bouton de l'extension (pour utiliser Orion lui-même quelques minutes).
;(() => {
  if (window !== window.top) return
  const api = typeof browser !== 'undefined' ? browser : typeof chrome !== 'undefined' ? chrome : null
  const envoyer = () => {
    try { window.stop() } catch (e) {}
    location.href = 'vibesearch:' + encodeURI(location.href)
  }
  const lire = () =>
    new Promise((ok) => {
      try {
        const r = api.storage.local.get({ actif: true, pause: 0 }, (c) => ok(c || { actif: true, pause: 0 }))
        if (r && typeof r.then === 'function') r.then(ok, () => ok({ actif: true, pause: 0 }))
      } catch (e) {
        ok({ actif: true, pause: 0 }) // stockage indisponible : passerelle active par défaut
      }
    })
  // Sans réponse du stockage en 800 ms : on envoie quand même (rien ne doit rester dans Orion)
  let fait = false
  const decider = (c) => {
    if (fait) return
    fait = true
    if (c.actif !== false && Date.now() >= (c.pause || 0)) envoyer()
  }
  if (!api || !api.storage) return envoyer()
  lire().then(decider)
  setTimeout(() => decider({ actif: true, pause: 0 }), 300)
})()