#!/usr/bin/env bash
# Publica una nueva versión: sube MARKETING_VERSION, compila, etiqueta y crea la GitHub Release
# con el zip de la app. La app instalada se actualizará sola desde esa release.
#
#   ./release.sh 1.1 "Notas de la versión"
set -euo pipefail
cd "$(dirname "$0")"

VER="${1:?Uso: ./release.sh <version> [notas]   ej: ./release.sh 1.1 \"Arreglos\"}"
NOTES="${2:-Mejoras y correcciones.}"

echo "▶ Subiendo versión a $VER en el proyecto…"
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VER;/g" SimplePlayer.xcodeproj/project.pbxproj

echo "▶ Compilando…"
./build.sh

echo "▶ Empaquetando…"
rm -f /tmp/SimplePlayer.zip
ditto -c -k --sequesterRsrc --keepParent SimplePlayer.app /tmp/SimplePlayer.zip

echo "▶ Commit + tag + push…"
git add -A
git commit -m "Release v$VER" || echo "  (sin cambios que commitear)"
git tag "v$VER"
git push origin main
git push origin "v$VER"

echo "▶ Creando GitHub Release v$VER con el binario…"
gh release create "v$VER" /tmp/SimplePlayer.zip --title "v$VER" --notes "$NOTES"

echo "✓ Publicado v$VER — las apps instaladas lo ofrecerán al arrancar."
