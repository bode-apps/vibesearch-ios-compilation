#!/bin/bash
# Prépare une extension compilée pour VibeSearch :
#  - arrière-plan « service worker » → page d'arrière-plan (WebKit refuse les service workers aux applis)
#  - journal VibeSearch des erreurs (arrière-plan + fenêtre de l'extension)
set -e
D="$1"
[ -f "$D/manifest.json" ] || { echo "Pas d'extension dans $D"; exit 0; }
O="$(cd "$(dirname "$0")" && pwd)"
cp "$O/journal.js" "$D/vibe-journal.js"
cp "$O/fond.js" "$D/vibe-fond.js"
cp "$O/compat.js" "$D/vibe-compat.js"
python3 - "$D" <<'PY'
import json, os, sys, glob
d = sys.argv[1]
p = os.path.join(d, 'manifest.json')
m = json.load(open(p, encoding='utf-8'))
bg = m.get('background', {})
sw = bg.get('service_worker')
if sw:
    morceaux = sorted(os.path.basename(f) for f in glob.glob(os.path.join(d, '*.' + sw)) if os.path.basename(f) != sw)
    m['background'] = {'scripts': ['vibe-journal.js', 'vibe-compat.js', 'vibe-fond.js'] + morceaux + [sw], 'persistent': False}
elif 'scripts' in bg:
    bg['scripts'] = ['vibe-journal.js', 'vibe-compat.js'] + [s for s in bg['scripts'] if s not in ('vibe-journal.js', 'vibe-compat.js')]
json.dump(m, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('Arrière-plan :', json.dumps(m.get('background')))
# Pages de l'extension : journal en premier script
for h in ('popup/index.html', 'notification/bar.html'):
    f = os.path.join(d, h)
    if not os.path.exists(f): continue
    base = os.path.relpath(d, os.path.dirname(f)).replace(os.sep, '/')
    s = open(f, encoding='utf-8').read()
    if 'vibe-journal.js' not in s:
        s = s.replace('<head>', '<head><script src="%s/vibe-journal.js"></script><script src="%s/vibe-compat.js"></script>' % (base, base), 1)
    open(f, 'w', encoding='utf-8').write(s)
PY
# chrome.scripting.ExecutionWorld (constantes de Chrome) n'existe pas dans WebKit et son objet
# ne se complète pas : on écrit directement les valeurs dans le code de l'extension.
find "$D" -name '*.js' -type f -exec sed -i.vibe   -e 's/chrome\.scripting\.ExecutionWorld\.ISOLATED/"ISOLATED"/g'   -e 's/chrome\.scripting\.ExecutionWorld\.MAIN/"MAIN"/g' {} +
find "$D" -name '*.vibe' -type f -delete
echo "ExecutionWorld restant : $(grep -rl 'scripting\.ExecutionWorld\.' "$D" --include='*.js' | wc -l | tr -d ' ') fichier(s)"
echo "Extension préparée : $D"
