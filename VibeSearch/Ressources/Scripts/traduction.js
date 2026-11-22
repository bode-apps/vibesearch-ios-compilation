// Traduction de page (monde isolé) : outils appelés par l'appli.
//  vibeTraduction.collecter(max) → [{ i, t }] textes visibles à traduire
//  vibeTraduction.appliquer({ i: texte }) → remplace les textes
//  vibeTraduction.restaurer() → remet l'original
;(() => {
  if (window.vibeTraduction) return
  const noeuds = []
  const originaux = new Map()
  const IGNORER = /^(SCRIPT|STYLE|NOSCRIPT|CODE|PRE|TEXTAREA|INPUT|SELECT|SVG|MATH|KBD|SAMP|VAR)$/
  let suivant = 0
  window.vibeTraduction = {
    collecter(max) {
      const sortie = []
      const marcheur = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {
        acceptNode(n) {
          const p = n.parentElement
          if (!p || IGNORER.test(p.tagName) || p.closest('[translate=no], .notranslate, [contenteditable=true]')) return NodeFilter.FILTER_REJECT
          const t = n.textContent
          if (!t || t.trim().length < 2 || !/\p{L}/u.test(t)) return NodeFilter.FILTER_REJECT
          if (originaux.has(n)) return NodeFilter.FILTER_REJECT
          return NodeFilter.FILTER_ACCEPT
        }
      })
      let n
      while ((n = marcheur.nextNode()) && sortie.length < max) {
        const i = suivant++
        noeuds[i] = n
        originaux.set(n, n.textContent)
        sortie.push({ i, t: n.textContent.trim().slice(0, 2000) })
      }
      return JSON.stringify(sortie)
    },
    appliquer(traductions) {
      for (const [i, t] of Object.entries(traductions)) {
        const n = noeuds[+i]
        if (!n || typeof t !== 'string') continue
        // On garde les espaces autour du texte d'origine (mise en page)
        const o = originaux.get(n) || ''
        const avant = /^\s*/.exec(o)[0]
        const apres = /\s*$/.exec(o)[0]
        n.textContent = avant + t + apres
      }
      document.documentElement.setAttribute('data-vibe-traduit', '1')
      return true
    },
    restaurer() {
      for (const [n, t] of originaux) n.textContent = t
      originaux.clear()
      noeuds.length = 0
      document.documentElement.removeAttribute('data-vibe-traduit')
      return true
    }
  }
})()
