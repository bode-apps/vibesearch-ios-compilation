// YouTube dans VibeSearch (monde isolé, cadre principal, youtube.com uniquement) :
//  - pubs vidéo : coupées et avancées jusqu'à la fin, bouton « Passer » cliqué tout seul ;
//  - sponsors et intros sautés grâce à la base communautaire SponsorBlock (demandée par l'appli,
//    qui n'envoie que 4 caractères de l'empreinte de l'identifiant de la vidéo) ;
//  - bulle « Revenir » pour annuler un saut.
;(() => {
  if (!/(^|\.)youtube\.com$/.test(location.hostname) || window.__vibeYoutube) return
  window.__vibeYoutube = true
  const canal = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vibeYoutube
  if (!canal) return

  const sansPubs = window.__vibeSansPubs === true
  // Encarts publicitaires statiques (accueil, résultats, sous la vidéo)
  if (sansPubs) {
  const style = document.createElement('style')
  style.textContent = [
    'ytd-ad-slot-renderer', 'ytm-promoted-sparkles-web-renderer', 'ad-slot-renderer', 'ytm-companion-ad-renderer',
    '#player-ads', 'ytd-promoted-sparkles-web-renderer', 'ytd-in-feed-ad-layout-renderer', 'ytm-promoted-video-renderer',
    '.ytd-merch-shelf-renderer', 'ytm-ad-slot-renderer', 'ytd-banner-promo-renderer', 'ytm-statement-banner-style-type-compact'
  ].join(',') + '{display:none!important}'
  ;(document.head || document.documentElement).appendChild(style)
  }

  let idVideo = ''
  let segments = []
  const annules = new Set()

  const idDepuisAdresse = () => {
    const u = new URL(location.href)
    if (u.pathname === '/watch') return u.searchParams.get('v') || ''
    const m = /^\/(shorts|live|embed)\/([\w-]{11})/.exec(u.pathname)
    return m ? m[2] : ''
  }

  const bulle = (texte, action) => {
    let b = document.getElementById('vibe-bulle')
    if (!b) {
      b = document.createElement('div')
      b.id = 'vibe-bulle'
      b.style.cssText = 'position:fixed;left:50%;bottom:84px;transform:translateX(-50%);z-index:2147483647;display:flex;gap:10px;align-items:center;padding:9px 14px;border-radius:999px;background:rgba(17,15,46,.92);color:#eeebff;font:600 14px -apple-system,system-ui;box-shadow:0 0 0 1px rgba(124,108,255,.5),0 0 18px rgba(124,108,255,.45);transition:opacity .3s'
      document.documentElement.appendChild(b)
    }
    b.textContent = texte
    if (action) {
      const bt = document.createElement('button')
      bt.textContent = 'Revenir'
      bt.style.cssText = 'border:0;border-radius:999px;padding:4px 10px;background:linear-gradient(135deg,#38bdf8,#7c6cff,#a855f7);color:#fff;font:600 13px -apple-system,system-ui'
      bt.onclick = (e) => {
        e.stopPropagation()
        action()
        b.style.opacity = '0'
      }
      b.appendChild(bt)
    }
    b.style.opacity = '1'
    clearTimeout(b.__t)
    b.__t = setTimeout(() => (b.style.opacity = '0'), 5000)
  }

  const chargerSegments = async (id) => {
    segments = []
    annules.clear()
    try {
      const rep = await canal.postMessage({ type: 'segments', id })
      if (id === idVideo && Array.isArray(rep)) segments = rep
    } catch (e) {}
  }

  const NOMS = { sponsor: 'Sponsor passé', intro: 'Intro passée' }

  const surTemps = (v) => {
    if (!segments.length || !v || v.paused) return
    const t = v.currentTime
    for (const s of segments) {
      if (annules.has(s.uuid)) continue
      if (t >= s.debut && t < s.fin - 0.4) {
        const depart = t
        v.currentTime = s.fin
        bulle(NOMS[s.categorie] || 'Passage sauté', () => {
          annules.add(s.uuid)
          v.currentTime = Math.max(0, depart - 0.5)
        })
        break
      }
    }
  }

  let videoSuivie = null
  const surveiller = () => {
    // Changement de vidéo (YouTube navigue sans recharger la page)
    const id = idDepuisAdresse()
    if (id !== idVideo) {
      idVideo = id
      if (id) chargerSegments(id)
      else segments = []
    }
    const lecteur = document.querySelector('.html5-video-player')
    const v = (lecteur && lecteur.querySelector('video')) || document.querySelector('video')
    if (v && v !== videoSuivie) {
      videoSuivie = v
      v.addEventListener('timeupdate', () => surTemps(v))
    }
    // Pub en cours : muette, avancée à la fin, bouton « Passer » cliqué
    if (sansPubs && lecteur && lecteur.classList.contains('ad-showing') && v) {
      v.muted = true
      if (isFinite(v.duration) && v.duration > 0) v.currentTime = v.duration
      for (const b of document.querySelectorAll('.ytp-ad-skip-button,.ytp-ad-skip-button-modern,.ytp-skip-ad-button,.ytp-ad-skip-button-container button')) b.click()
      lecteur.__vibeMuet = true
    } else if (lecteur && lecteur.__vibeMuet && v) {
      lecteur.__vibeMuet = false
      v.muted = false
    }
  }
  setInterval(surveiller, 400)
  window.addEventListener('yt-navigate-finish', surveiller)
  window.addEventListener('popstate', surveiller)
})()
