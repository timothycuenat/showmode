#!/bin/bash
# Compile ShowMode en Release (Apple Silicon et Intel) et produit dist/ShowMode-macOS.pkg et .zip.
# Sans MACOS_APP_SIGN_ID, l'app est signée localement et macOS demandera une validation à l'ouverture.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcodebuild -project ShowMode.xcodeproj -scheme ShowMode -configuration Release \
    -derivedDataPath "$WORK/build" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="${MACOS_APP_SIGN_ID:--}" build >/dev/null

APP="$WORK/build/Build/Products/Release/ShowMode.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ROOT="$WORK/root/Applications"
mkdir -p "$ROOT" dist
ditto "$APP" "$ROOT/ShowMode.app"

# Installe toujours dans /Applications, même si une autre copie existe sur le Mac.
pkgbuild --analyze --root "$WORK/root" "$WORK/components.plist" >/dev/null
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$WORK/components.plist"
pkgbuild --root "$WORK/root" --component-plist "$WORK/components.plist" --install-location / \
    --identifier com.showmode.ShowMode.pkg --version "$VERSION" "$WORK/ShowMode.pkg" >/dev/null
productbuild --package "$WORK/ShowMode.pkg" "dist/ShowMode-macOS.pkg" >/dev/null
ditto -c -k --keepParent "$APP" "dist/ShowMode-macOS.zip"

echo "ShowMode $VERSION : dist/ShowMode-macOS.pkg, dist/ShowMode-macOS.zip"
