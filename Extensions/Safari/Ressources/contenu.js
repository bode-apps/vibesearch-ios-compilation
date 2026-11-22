// Extension Safari de VibeSearch : remplace le « navigateur par défaut » (réservé par Apple aux
// comptes développeur payants). Deux modes, choisis dans la fenêtre de l'extension :
//  - « tout » : toute page ouverte dans Safari bascule dans VibeSearch ;
//  - « liens » : seuls les liens touchés dans Safari s'ouvrent dans VibeSearch.
;(() => {
  const ouvrir = (adresse) => {
    location.href = 'vibesearch:' + encodeURI(adresse)
  }
  const api = typeof browser !== 'undefined' ? browser : chrome
  api.storage.local.get({ actif: true, mode: 'tout', pause: 0 }).then((c) => {
    if (!c.actif || Date.now() < c.pause) return
    if (c.mode === 'tout') {
      // Pas de boucle : la page n'est pas chargée, Safari passe la main à VibeSearch
      window.stop()
      ouvrir(location.href)
      return
    }
    document.addEventListener(
      'click',
      (e) => {
        if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey) return
        const a = e.target && e.target.closest && e.target.closest('a[href]')
        if (!a) return
        const u = new URL(a.href, location.href)
        if (!/^https?:$/.test(u.protocol)) return
        if (u.origin === location.origin && u.pathname === location.pathname && u.hash) return // ancre sur la même page
        e.preventDefault()
        e.stopPropagation()
        ouvrir(u.href)
      },
      true
    )
  })
})()
