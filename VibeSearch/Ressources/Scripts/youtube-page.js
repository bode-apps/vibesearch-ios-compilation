// YouTube, monde de la page (cadre principal) :
//  - lecture en arrière-plan / écran verrouillé : YouTube met la vidéo en pause quand la page
//    « devient cachée » ; on lui fait croire qu'elle reste visible (réglage __ARRIERE_PLAN__) ;
//  - sous-titres pour le résumé IA : lus depuis la liste des pistes du lecteur, sinon capturés
//    quand le lecteur les télécharge lui-même. Accès par une fonction au nom secret (__EVENEMENT__).
;(() => {
  if (!/(^|\.)youtube\.com$/.test(location.hostname)) return
  const SECRET = '__EVENEMENT__'

  if (__ARRIERE_PLAN__) {
    try {
      const proto = Document.prototype
      Object.defineProperty(proto, 'hidden', { get: () => false, configurable: true })
      Object.defineProperty(proto, 'visibilityState', { get: () => 'visible', configurable: true })
      Object.defineProperty(proto, 'webkitHidden', { get: () => false, configurable: true })
      Object.defineProperty(proto, 'webkitVisibilityState', { get: () => 'visible', configurable: true })
    } catch (e) {}
    for (const type of ['visibilitychange', 'webkitvisibilitychange', 'pagehide', 'blur']) {
      window.addEventListener(type, (e) => e.stopImmediatePropagation(), true)
      document.addEventListener(type, (e) => e.stopImmediatePropagation(), true)
    }
  }

  // Capture des sous-titres téléchargés par le lecteur (format json3 ou xml)
  let capture = ''
  const garder = (url, texte) => {
    if (typeof url === 'string' && url.includes('/api/timedtext') && texte && texte.length > 50) capture = texte
  }
  const origFetch = window.fetch
  window.fetch = function (entree, init) {
    const p = origFetch.apply(this, arguments)
    try {
      const url = typeof entree === 'string' ? entree : entree && entree.url
      if (url && url.includes('/api/timedtext')) p.then((r) => r.clone().text().then((t) => garder(url, t))).catch(() => {})
    } catch (e) {}
    return p
  }
  const origOpen = XMLHttpRequest.prototype.open
  XMLHttpRequest.prototype.open = function (m, url) {
    try {
      if (String(url).includes('/api/timedtext')) this.addEventListener('load', () => garder(String(url), this.responseText))
    } catch (e) {}
    return origOpen.apply(this, arguments)
  }

  const versSegments = (brut) => {
    if (!brut) return []
    try {
      const j = JSON.parse(brut)
      return (j.events || [])
        .filter((e) => e.segs)
        .map((e) => ({ t: Math.round((e.tStartMs || 0) / 1000), x: e.segs.map((s) => s.utf8).join('').replace(/\s+/g, ' ').trim() }))
        .filter((s) => s.x)
    } catch (e) {}
    const doc = new DOMParser().parseFromString(brut, 'text/xml')
    return [...doc.querySelectorAll('text, p')]
      .map((n) => ({ t: Math.round(parseFloat(n.getAttribute('start') || (parseInt(n.getAttribute('t') || '0') / 1000)) || 0), x: (n.textContent || '').replace(/\s+/g, ' ').trim() }))
      .filter((s) => s.x)
  }

  Object.defineProperty(window, SECRET + 'st', {
    enumerable: false,
    value: async () => {
      let titre = document.title.replace(/ - YouTube$/, '')
      let segments = []
      try {
        const lecteur = document.getElementById('movie_player')
        const reponse = (lecteur && lecteur.getPlayerResponse && lecteur.getPlayerResponse()) || window.ytInitialPlayerResponse
        if (reponse && reponse.videoDetails) titre = reponse.videoDetails.title || titre
        const pistes = (((reponse || {}).captions || {}).playerCaptionsTracklistRenderer || {}).captionTracks || []
        const piste = pistes.find((p) => /^fr/.test(p.languageCode)) || pistes.find((p) => !p.kind) || pistes[0]
        if (piste && piste.baseUrl) {
          const r = await origFetch(piste.baseUrl + '&fmt=json3', { credentials: 'include' })
          segments = versSegments(await r.text())
        }
      } catch (e) {}
      if (!segments.length) segments = versSegments(capture)
      return JSON.stringify({ titre, segments })
    }
  })
})()
