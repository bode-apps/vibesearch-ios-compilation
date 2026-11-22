// Tests du convertisseur de listes (node --test)
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { motifVersRegex, regleReseau, convertirListe, selecteurValide, decouper } from '../outils/convertir.mjs'

/** Vérifie qu'une regex WebKit se comporte comme prévu (la syntaxe WebKit est un sous-ensemble de JS). */
function correspond(regex, url) {
  return new RegExp(regex).test(url)
}

test('||domaine^ : domaine et sous-domaines, pas les faux amis', () => {
  const r = motifVersRegex('||pub.example.com^')
  assert.ok(correspond(r, 'https://pub.example.com/x.js'))
  assert.ok(correspond(r, 'http://a.pub.example.com:8080/'))
  assert.ok(!correspond(r, 'https://notpub.example.com/'))
  assert.ok(!correspond(r, 'https://pub.example.com.evil.fr/'))
  assert.ok(!correspond(r, 'https://site.fr/?u=pub.example.com'))
})

test('pas d’alternance ni d’accolades dans les regex produites', () => {
  for (const m of ['||a.fr^', '/ads/*', '|https://x.fr/pub^', '&ad_type=', '||b.com/pub/*/banner^', '-300x250.']) {
    const r = motifVersRegex(m)
    assert.ok(r && !r.includes('|') && !/[{}]/.test(r), `${m} → ${r}`)
  }
})

test('séparateur et joker', () => {
  const r = motifVersRegex('/banner/*/img^')
  assert.ok(correspond(r, 'https://a.fr/banner/123/img?x=1'))
  assert.ok(correspond(r, 'https://a.fr/banner/123/img'))
  assert.ok(!correspond(r, 'https://a.fr/banner/123/imgx'))
})

test('options : tiers, types, domaines', () => {
  const r = regleReseau('||track.fr^$script,third-party,domain=a.fr|b.fr')
  assert.deepEqual(r.regle.trigger['load-type'], ['third-party'])
  assert.deepEqual(r.regle.trigger['resource-type'], ['script'])
  assert.deepEqual(r.regle.trigger['if-domain'], ['*a.fr', '*b.fr'])
  assert.equal(r.regle.action.type, 'block')
})

test('options non gérées → règle abandonnée', () => {
  assert.equal(regleReseau('||x.fr^$redirect=noopjs'), null)
  assert.equal(regleReseau('||x.fr^$csp=script-src none'), null)
  assert.equal(regleReseau('/^https?:\\/\\/[a-z]+\\.fr\\//'), null)
  assert.equal(regleReseau('*$script'), null) // bloquerait tout le web
})

test('exceptions de site entier', () => {
  const r = regleReseau('@@||banque.fr^$document')
  assert.equal(r.regle.action.type, 'ignore-previous-rules')
  assert.deepEqual(r.regle.trigger['if-domain'], ['*banque.fr'])
})

test('sélecteurs exotiques refusés', () => {
  assert.ok(selecteurValide('.ad-banner'))
  assert.ok(selecteurValide('div[id^="google_ads"]'))
  assert.ok(!selecteurValide('div:has-text(Sponsorisé)'))
  assert.ok(!selecteurValide('.a:-abp-contains(x)'))
  assert.ok(!selecteurValide('div[class="x]'))
})

test('ordre : cosmétique, puis blocages, puis exceptions', () => {
  const { regles } = convertirListe(['##.pub', 'site.fr##.encart', '||ads.fr^', '@@||ads.fr/ok.js', '@@||site.fr^$elemhide', 'site.fr#@#.encart'].join('\n'))
  const types = regles.map((r) => r.action.type)
  assert.deepEqual(types, ['css-display-none', 'ignore-previous-rules', 'block', 'ignore-previous-rules'])
})

test('« site#@#sel » annule le masquage générique sur ce site seulement', () => {
  const { regles } = convertirListe(['##.pub', '##.banniere', 'exemple.fr#@#.pub'].join('\n'))
  const pub = regles.find((r) => r.action.selector === '.pub')
  assert.deepEqual(pub.trigger['unless-domain'], ['*exemple.fr'])
  const autre = regles.find((r) => r.action.selector === '.banniere')
  assert.equal(autre.trigger['unless-domain'], undefined)
})

test('« #@#sel » sans domaine désactive le sélecteur partout', () => {
  const { regles } = convertirListe(['##.pub', 'a.fr##.pub', '#@#.pub'].join('\n'))
  assert.equal(regles.filter((r) => r.action.type === 'css-display-none').length, 0)
})

test('domaines mêlant inclusions et exclusions : règle abandonnée', () => {
  assert.equal(regleReseau('||x.fr^$domain=a.com|~b.a.com'), null)
})

test('règle sans type : jamais la page principale', () => {
  const r = regleReseau('/adv/banner.')
  assert.ok(!r.regle.trigger['resource-type'].includes('document'))
  assert.ok(!r.regle.trigger['resource-type'].includes('popup'))
})

test('$subdocument : seulement dans les cadres', () => {
  const r = regleReseau('||pub.fr^$subdocument')
  assert.deepEqual(r.regle.trigger['resource-type'], ['document'])
  assert.deepEqual(r.regle.trigger['load-context'], ['child-frame'])
})

test('$generichide n’annule que le masquage générique', () => {
  const { regles } = convertirListe(['##.pub', 'site.fr##.encart', '@@||site.fr^$generichide'].join('\n'))
  const types = regles.map((r) => r.action.type + (r.action.selector ?? ''))
  assert.deepEqual(types, ['css-display-none.pub', 'ignore-previous-rules', 'css-display-none.encart'])
})

test('découpage avec exceptions recopiées', () => {
  const regles = [...Array(10)].map(() => ({ trigger: { 'url-filter': 'a' }, action: { type: 'block' } }))
  regles.push({ trigger: { 'url-filter': 'b' }, action: { type: 'ignore-previous-rules' } })
  assert.throws(() => decouper(regles, 5))
})
