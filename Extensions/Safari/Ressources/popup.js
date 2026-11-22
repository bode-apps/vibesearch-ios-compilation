// Fenêtre de l'extension Safari : réglages enregistrés dans le stockage de l'extension.
const api = typeof browser !== 'undefined' ? browser : chrome
const actif = document.getElementById('actif')
const modes = [...document.querySelectorAll('input[name=mode]')]

api.storage.local.get({ actif: true, mode: 'tout' }).then((c) => {
  actif.checked = c.actif
  for (const m of modes) m.checked = m.value === c.mode
})
actif.addEventListener('change', () => api.storage.local.set({ actif: actif.checked }))
for (const m of modes) m.addEventListener('change', () => api.storage.local.set({ mode: m.value }))
document.getElementById('pause').addEventListener('click', () => {
  api.storage.local.set({ pause: Date.now() + 10 * 60 * 1000 }).then(() => window.close())
})
document.getElementById('ici').addEventListener('click', async () => {
  const [onglet] = await api.tabs.query({ active: true, currentWindow: true })
  if (onglet && onglet.url) await api.tabs.update(onglet.id, { url: 'vibesearch:' + encodeURI(onglet.url) })
  window.close()
})
