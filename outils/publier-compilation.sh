#!/bin/bash
# Copie propre du code vers le dépôt PUBLIC de compilation (bode-apps/vibesearch-ios-compilation) :
# minutes GitHub illimitées pour les dépôts publics. Sans l'historique, sans les notes,
# l'adresse du serveur relais remplacée (remise à la compilation depuis un secret du dépôt).
set -e
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${DEST:-$SRC/../VibeSearch-iOS-compilation}"
cd "$SRC"
REV=$(git rev-parse --short HEAD)
[ -d "$DEST/.git" ] || git clone -q https://github.com/bode-apps/vibesearch-ios-compilation.git "$DEST"
cd "$DEST"
git rm -rq --ignore-unmatch . >/dev/null 2>&1 || true
(cd "$SRC" && git archive HEAD) | tar -x -C "$DEST"
rm -f AI_HANDOFF.md INSTALLER-SUR-IPHONE.md
sed -i 's/137\.74\.93\.58/__HOTE_RELAIS__/g' VibeSearch/Sources/Discussion.swift
if grep -rIl "137\.74\.93\.58" . --exclude-dir=.git; then echo "Adresse du serveur encore présente : arrêt"; exit 1; fi
printf '# VibeSearch iPhone — compilation\n\nDépôt de compilation (GitHub Actions) du navigateur VibeSearch pour iPhone. Usage personnel.\n' > README.md
git add -A
git -c core.autocrlf=false commit -qm "Compilation $REV" || { echo "Rien de nouveau"; exit 0; }
git push -q origin HEAD:main
echo "Publié : $REV"
