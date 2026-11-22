// Extraction du texte lisible de la page pour l'IA (appelé à la demande, monde isolé).
// Renvoie { titre, adresse, texte } ; le texte est limité pour maîtriser le coût.
;(() => {
  const LIMITE = 120000
  const racine = document.querySelector('article, main, [role=main]') || document.body
  if (!racine) return JSON.stringify({ titre: document.title, adresse: location.href, texte: '' })
  const ignorer = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'SVG', 'NAV', 'FOOTER', 'IFRAME', 'TEMPLATE', 'FORM', 'ASIDE'])
  const morceaux = []
  let total = 0
  const parcourir = (n) => {
    if (total > LIMITE) return
    if (n.nodeType === 3) {
      const t = n.textContent.replace(/\s+/g, ' ').trim()
      if (t) {
        morceaux.push(t)
        total += t.length + 1
      }
      return
    }
    if (n.nodeType !== 1 || ignorer.has(n.tagName)) return
    const st = n.checkVisibility ? n.checkVisibility() : true
    if (!st) return
    const bloc = /^(P|DIV|LI|H[1-6]|TR|BR|SECTION|ARTICLE|BLOCKQUOTE|PRE)$/.test(n.tagName)
    for (const e of n.childNodes) parcourir(e)
    if (bloc) morceaux.push('\n')
  }
  parcourir(racine)
  // Si la zone « article » est trop pauvre, on reprend toute la page
  let texte = morceaux.join(' ').replace(/ *\n[ \n]*/g, '\n').trim()
  if (texte.length < 400 && racine !== document.body) texte = document.body.innerText || texte
  return JSON.stringify({ titre: document.title, adresse: location.href, texte: texte.slice(0, LIMITE) })
})()
