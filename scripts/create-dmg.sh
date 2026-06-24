#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
VERSION="${1:?usage: create-dmg.sh <version>}"
APP="dist/AppCat.app"
BACKGROUND="assets/dmg-background.png"

if [ ! -d "$APP" ]; then
  echo "Missing $APP — run scripts/build-release.sh first" >&2
  exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/AppCat.app"

OUT="dist/AppCat-v${VERSION}.dmg"
rm -f "$OUT"

# create-dmg returns non-zero on some benign warnings; verify the output exists afterwards.
if [ -f "$BACKGROUND" ]; then
  create-dmg \
    --volname "AppCat" \
    --background "$BACKGROUND" \
    --window-pos 200 120 \
    --window-size 660 474 \
    --icon-size 96 \
    --icon "AppCat.app" 170 150 \
    --app-drop-link 490 150 \
    --hide-extension "AppCat.app" \
    --no-internet-enable \
    "$OUT" \
    "$STAGING" || true
else
  create-dmg \
    --volname "AppCat" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 96 \
    --icon "AppCat.app" 180 200 \
    --app-drop-link 480 200 \
    --hide-extension "AppCat.app" \
    --no-internet-enable \
    "$OUT" \
    "$STAGING" || true
fi

if [ ! -f "$OUT" ]; then
  echo "ERROR: $OUT was not created" >&2
  exit 1
fi

hdiutil verify "$OUT" >/dev/null 2>&1 || true
echo "Built $OUT"
ls -lh "$OUT"
