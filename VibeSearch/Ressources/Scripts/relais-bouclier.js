// Monde isolé de VibeSearch : écoute les signalements du bouclier (évènements au nom secret)
// et les transmet à l'appli. La page ne voit ni cet écouteur ni le canal vers l'appli.
;(() => {
  const EVT = '__EVENEMENT__'
  const canal = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vibeBouclier
  if (!canal) return
  for (const k of ['canvas', 'webgl', 'audio', 'position']) {
    document.addEventListener(EVT + k, () => {
      try {
        canal.postMessage(k)
      } catch (e) {}
    })
  }
})()
