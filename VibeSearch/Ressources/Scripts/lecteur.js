// Mode lecture (monde isolé, à la demande) : trouve le corps de l'article et le renvoie en HTML
// épuré (titres, paragraphes, listes, citations, images, liens). Renvoie du JSON.
;(() => {
  const absolu = (u) => {
    try {
      return new URL(u, location.href).href
    } catch (e) {
      return ''
    }
  }
  // Racine : l'élément qui contient le plus de texte en paragraphes (méthode « Readability » simplifiée)
  const scores = new Map()
  for (const p of document.querySelectorAll('p, pre, blockquote')) {
    const n = (p.textContent || '').trim().length
    if (n < 40) continue
    let e = p.parentElement
    for (let i = 0; e && i < 3; i++, e = e.parentElement) scores.set(e, (scores.get(e) || 0) + n / (i + 1))
  }
  let racine = document.querySelector('article') || document.querySelector('[role=main], main')
  let meilleur = 0
  for (const [e, s] of scores) if (s > meilleur) (meilleur = s), (racine = e)
  if (!racine) racine = document.body

  const GARDER = { P: 'p', H1: 'h2', H2: 'h2', H3: 'h3', H4: 'h4', H5: 'h4', UL: 'ul', OL: 'ol', LI: 'li', BLOCKQUOTE: 'blockquote', PRE: 'pre', FIGURE: 'figure', FIGCAPTION: 'figcaption', STRONG: 'strong', B: 'strong', EM: 'em', I: 'em', CODE: 'code', BR: 'br', TABLE: 'table', TR: 'tr', TD: 'td', TH: 'th', TBODY: 'tbody' }
  const IGNORER = /^(SCRIPT|STYLE|NOSCRIPT|NAV|FOOTER|ASIDE|FORM|BUTTON|IFRAME|SVG|HEADER|INPUT|SELECT|TEXTAREA)$/
  const bruit = /(share|social|comment|related|promo|newsletter|sidebar|advert|cookie|subscribe|paywall|outbrain|taboola)/i
  const echapper = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  const html = (n) => {
    if (n.nodeType === 3) return echapper(n.textContent)
    if (n.nodeType !== 1 || IGNORER.test(n.tagName)) return ''
    if (bruit.test((n.className && n.className.baseVal === undefined ? n.className : '') + ' ' + (n.id || ''))) return ''
    if (n.tagName === 'IMG') {
      const src = absolu(n.currentSrc || n.src || n.getAttribute('data-src') || '')
      return src && (n.naturalWidth || 200) >= 120 ? `<img src="${echapper(src)}" alt="">` : ''
    }
    if (n.tagName === 'A') {
      const href = absolu(n.getAttribute('href') || '')
      const contenu = [...n.childNodes].map(html).join('')
      return /^https?:/.test(href) ? `<a href="${echapper(href)}">${contenu}</a>` : contenu
    }
    const contenu = [...n.childNodes].map(html).join('')
    const tag = GARDER[n.tagName]
    if (!tag) return contenu
    if (tag === 'br') return '<br>'
    if (!contenu.trim() && tag !== 'figure') return ''
    return `<${tag}>${contenu}</${tag}>`
  }
  const titre = (document.querySelector('h1') || {}).textContent || document.title
  const corps = html(racine)
  const site = location.hostname.replace(/^www\./, '')
  return JSON.stringify({ titre: (titre || '').trim(), site, adresse: location.href, html: corps.slice(0, 400000) })
})()
