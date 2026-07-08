#!/bin/bash
# Compila Recarga y ensambla build/Recarga.app
# Uso: ./build.sh [debug|release] [test|run|install]
#
# Notas de esta máquina (igual que Dicta):
# - swiftc directo (el SwiftPM de los Command Line Tools está roto) y SDK 15.5
#   explícito (el compilador 6.1.2 no soporta el SDK 26.2 instalado).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/Recarga.app"

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [ ! -d "$SDK" ]; then
  SDK="$(xcrun --sdk macosx --show-sdk-path)"
fi

OPT="-O"
if [ "$CONFIG" = "debug" ]; then
  OPT="-Onone -g"
fi

mkdir -p build
swiftc $OPT \
  -sdk "$SDK" \
  -target arm64-apple-macosx14.0 \
  -swift-version 5 \
  -parse-as-library \
  -o build/Recarga-bin \
  $(find Sources -name '*.swift')

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv build/Recarga-bin "$APP/Contents/MacOS/Recarga"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Resources/recipes.json "$APP/Contents/Resources/recipes.json"
cp Support/garmin_helper.py "$APP/Contents/Resources/garmin_helper.py"

codesign --force --sign - "$APP"
echo "✓ Bundle listo: $APP"

case "${2:-}" in
  test)
    "$APP/Contents/MacOS/Recarga" --selftest
    ;;
  run)
    open "$APP"
    ;;
  install)
    pkill -x Recarga 2>/dev/null || true
    sleep 0.3
    rm -rf /Applications/Recarga.app
    ditto "$APP" /Applications/Recarga.app
    echo "✓ Instalado en /Applications/Recarga.app"
    ;;
esac
