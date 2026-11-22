// Bouclier de VibeSearch (monde de la page, chaque page et chaque cadre, avant les scripts du site).
//  - empreinte : bruit léger et STABLE par site (Canvas, OffscreenCanvas, WebGL, Audio) ;
//  - position : toujours refusée, sans fenêtre de permission.
// Discrétion : aucune variable globale, aucun canal visible par la page. Les fonctions remplacées
// gardent leur nom et un toString() « [native code] » identique à l'original.
// Les signalements passent par des évènements au nom secret (__EVENEMENT__), écoutés dans le
// monde isolé de VibeSearch. __GRAINE__ est tirée par session (une autre pour le mode Fantôme).
;(() => {
  const EVT = '__EVENEMENT__'
  const envoyer = EventTarget.prototype.dispatchEvent
  const Evenement = Event
  const doc = document
  const vus = new Set()
  const signaler = (k) => {
    if (vus.has(k)) return
    vus.add(k)
    try {
      envoyer.call(doc, new Evenement(EVT + k))
    } catch (e) {}
  }

  // Graine par site : même bruit pour toutes les pages d'un site pendant la session
  let graine = __GRAINE__ >>> 0
  for (const c of location.hostname) graine = Math.imul(graine ^ c.charCodeAt(0), 2654435761) >>> 0
  const alea = (i) => {
    let x = (graine ^ Math.imul(i + 1, 0x9e3779b1)) >>> 0
    x ^= x >>> 16
    x = Math.imul(x, 0x7feb352d) >>> 0
    x ^= x >>> 15
    return x
  }

  // toString() des fonctions remplacées = celui de l'original (et toString lui-même reste « natif »)
  const originaux = new WeakMap()
  const toStringOrig = Function.prototype.toString
  const toStringNouveau = new Proxy(toStringOrig, {
    apply: (t, self, args) => Reflect.apply(t, originaux.get(self) || self, args)
  })
  originaux.set(toStringNouveau, toStringOrig)
  try {
    Object.defineProperty(Function.prototype, 'toString', { value: toStringNouveau, configurable: true, writable: true })
  } catch (e) {}

  const enrober = (obj, nom, apres) => {
    const orig = obj && obj[nom]
    if (typeof orig !== 'function') return
    const p = new Proxy(orig, { apply: (t, self, args) => apres(t, self, args) })
    originaux.set(p, orig)
    try {
      Object.defineProperty(obj, nom, { value: p, configurable: true, writable: true })
    } catch (e) {}
  }

  // --- Canvas : quelques pixels décalés d'une unité, toujours les mêmes pour un site donné
  const bruiter = (data) => {
    if (!data || data.length < 16) return
    const n = Math.min(24, Math.max(4, (data.length / 4096) | 0))
    for (let i = 0; i < n; i++) {
      const p = (alea(i) % (data.length >> 2)) << 2
      data[p] ^= 1
      data[p + 1] ^= alea(i + 99) & 1
    }
  }
  const origGetImageData = CanvasRenderingContext2D.prototype.getImageData
  const copieBruitee = (canvas) => {
    try {
      const w = canvas.width
      const h = canvas.height
      if (!w || !h || w * h > 4e6) return null
      const c = doc.createElement('canvas')
      c.width = w
      c.height = h
      const ctx = c.getContext('2d')
      ctx.drawImage(canvas, 0, 0)
      const img = Reflect.apply(origGetImageData, ctx, [0, 0, w, h])
      bruiter(img.data)
      ctx.putImageData(img, 0, 0)
      return c
    } catch (e) {
      return null
    }
  }
  const lecturePixels = (t, self, args) => {
    const img = Reflect.apply(t, self, args)
    signaler('canvas')
    bruiter(img.data)
    return img
  }
  enrober(CanvasRenderingContext2D.prototype, 'getImageData', lecturePixels)
  if (window.OffscreenCanvasRenderingContext2D) enrober(OffscreenCanvasRenderingContext2D.prototype, 'getImageData', lecturePixels)
  for (const nom of ['toDataURL', 'toBlob']) {
    enrober(HTMLCanvasElement.prototype, nom, (t, self, args) => {
      signaler('canvas')
      return Reflect.apply(t, copieBruitee(self) || self, args)
    })
  }
  if (window.OffscreenCanvas) {
    enrober(OffscreenCanvas.prototype, 'convertToBlob', (t, self, args) => {
      signaler('canvas')
      try {
        const ctx = self.getContext('2d')
        if (ctx) {
          const img = Reflect.apply(origGetImageData, ctx, [0, 0, self.width, self.height])
          bruiter(img.data)
          ctx.putImageData(img, 0, 0)
        }
      } catch (e) {}
      return Reflect.apply(t, self, args)
    })
  }

  // --- WebGL : lecture des pixels bruitée
  for (const proto of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
    if (!proto) continue
    enrober(proto.prototype, 'readPixels', (t, self, args) => {
      const r = Reflect.apply(t, self, args)
      signaler('webgl')
      const tab = args[6]
      if (tab && tab.length) bruiter(tab)
      return r
    })
  }

  // --- Audio : variation infime (inaudible) des données analysées
  if (window.AudioBuffer) {
    const marques = new WeakSet()
    const bruiterAudio = (d) => {
      if (!d || marques.has(d)) return
      for (let i = 0; i < d.length; i += 97) d[i] += ((alea(i) % 1000) - 500) * 1e-9
      marques.add(d)
    }
    enrober(AudioBuffer.prototype, 'getChannelData', (t, self, args) => {
      const d = Reflect.apply(t, self, args)
      signaler('audio')
      bruiterAudio(d)
      return d
    })
    enrober(AudioBuffer.prototype, 'copyFromChannel', (t, self, args) => {
      const r = Reflect.apply(t, self, args)
      signaler('audio')
      const dest = args[0]
      if (dest && dest.length) for (let i = 0; i < dest.length; i += 97) dest[i] += ((alea(i) % 1000) - 500) * 1e-9
      return r
    })
  }

  // --- Position : refus immédiat, sans fenêtre de permission (méthodes du prototype, comme l'original)
  if (window.Geolocation) {
    const refus = (erreur) => {
      if (typeof erreur === 'function') {
        setTimeout(() => erreur({ code: 1, message: 'User denied Geolocation', PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 }), 0)
      }
    }
    enrober(Geolocation.prototype, 'getCurrentPosition', (t, self, args) => {
      signaler('position')
      refus(args[1])
    })
    enrober(Geolocation.prototype, 'watchPosition', (t, self, args) => {
      signaler('position')
      refus(args[1])
      return 0
    })
  }
})()
