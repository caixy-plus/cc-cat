#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
xcodegen generate
xcodebuild \
  -project AppCat.xcodeproj \
  -scheme AppCat \
  -configuration Release \
  -derivedDataPath .release \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir -p dist
rm -rf dist/AppCat.app
ditto .release/Build/Products/Release/AppCat.app dist/AppCat.app
codesign --verify --deep --strict dist/AppCat.app 2>/dev/null || echo "(ad-hoc build, signature verification skipped)"
echo "Built dist/AppCat.app"
