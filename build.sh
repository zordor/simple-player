#!/usr/bin/env bash
# Compila SimplePlayer (Release) y deja SimplePlayer.app en la raíz del proyecto.
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ Compilando SimplePlayer (Release)…"
xcodebuild -project SimplePlayer.xcodeproj \
           -scheme SimplePlayer \
           -configuration Release \
           -derivedDataPath build \
           build

echo "▶ Copiando .app a la raíz del proyecto…"
rm -rf SimplePlayer.app
cp -R build/Build/Products/Release/SimplePlayer.app ./SimplePlayer.app

echo "✓ Listo: $(pwd)/SimplePlayer.app"
echo "  Ábrela con doble clic o:  open ./SimplePlayer.app"
