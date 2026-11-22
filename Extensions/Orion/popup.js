// Réglages de la passerelle (stockage de l'extension).
const api = typeof browser !== 'undefined' ? browser : chrome
const actif = document.getElementById('actif')
const etat = document.getElementById('etat')
const afficher = (c) => {
  actif.checked = c.actif !== false
  const reste = Math.ceil(((c.pause || 0) - Date.now()) / 60000)
  etat.textContent = reste > 0 ? `En pause encore ${reste} min.` : 'Chaque page ouverte dans Orion part dans VibeSearch.'
}
const lire = () => new Promise((ok) => {
  const r = api.storage.local.get({ actif: true, pause: 0 }, ok)
  if (r && r.then) r.then(ok)
})
lire().then(afficher)
actif.addEventListener('change', () => api.storage.local.set({ actif: actif.checked }))
document.getElementById('pause').addEventListener('click', () => {
  const pause = Date.now() + 10 * 60 * 1000
  api.storage.local.set({ pause })
  afficher({ actif: actif.checked, pause })
})