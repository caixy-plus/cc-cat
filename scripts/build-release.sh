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
  build

mkdir -p dist
rm -rf dist/AppCat.app
ditto .release/Build/Products/Release/AppCat.app dist/AppCat.app
codesign --verify --deep --strict dist/AppCat.app
echo "Built dist/AppCat.app"
