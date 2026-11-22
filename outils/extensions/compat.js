// VibeSearch : petites différences entre les API d'extension de Chrome et celles de WebKit.
;(() => {
  for (const api of [typeof chrome !== 'undefined' ? chrome : null, typeof browser !== 'undefined' ? browser : null]) {
    if (!api) continue
    // chrome.scripting.ExecutionWorld (constantes Chrome) absent de WebKit : sans lui, Bitwarden
    // plantait avant même d'injecter son script de remplissage dans la page.
    try {
      if (api.scripting && !api.scripting.ExecutionWorld) {
        Object.defineProperty(api.scripting, 'ExecutionWorld', { value: Object.freeze({ ISOLATED: 'ISOLATED', MAIN: 'MAIN' }), configurable: true })
      }
    } catch (e) {}
  }
})();
