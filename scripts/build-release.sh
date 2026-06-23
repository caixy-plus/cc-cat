#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
xcodegen generate
xcodebuild \
  -project SwiftUninstall.xcodeproj \
  -scheme SwiftUninstall \
  -configuration Release \
  -derivedDataPath .release \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  build

mkdir -p dist
rm -rf dist/SwiftUninstall.app dist/应用卸载器.app
ditto .release/Build/Products/Release/SwiftUninstall.app dist/应用卸载器.app
codesign --verify --deep --strict dist/应用卸载器.app
echo "Built dist/应用卸载器.app"
