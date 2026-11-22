// Mode sombre forcé (monde isolé, cadre principal) : seulement si la page est claire.
// Les sites qui ont déjà un thème sombre le montrent d'eux-mêmes (l'appli est en sombre).
;(() => {
  const style = document.createElement('style')
  // Fond sombre immédiat pour éviter l'éclair blanc pendant le chargement
  style.textContent = 'html{background:#111 !important}'
  ;(document.head || document.documentElement).appendChild(style)

  const luminance = (c) => {
    const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?/.exec(c || '')
    if (!m || (m[4] !== undefined && parseFloat(m[4]) < 0.1)) return null
    return (0.2126 * m[1] + 0.7152 * m[2] + 0.0722 * m[3]) / 255
  }
  const appliquer = () => {
    const fonds = [document.body, document.documentElement].map((e) => e && luminance(getComputedStyle(e).backgroundColor)).filter((l) => l !== null)
    const clair = fonds.length ? fonds[0] > 0.6 : true
    if (!clair) {
      style.textContent = ''
      return
    }
    style.textContent = `
      html { filter: invert(0.9) hue-rotate(180deg) !important; background: #fff !important; }
      img, video, picture, canvas, iframe, embed, object, svg image, [style*="background-image"] {
        filter: invert(1) hue-rotate(180deg) !important;
      }`
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', appliquer, { once: true })
  else appliquer()
})()
