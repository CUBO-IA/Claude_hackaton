#!/usr/bin/env bash
# Build the FMC130 Assistant Linux AppImage from the openpets fork.
# Usage: ./build-appimage.sh [--skip-install]
# Output: Claude_hackaton/dist/FMC130-Assistant-<version>-linux-x86_64.AppImage
set -euo pipefail

HACKATON_DIR="$(cd "$(dirname "$0")" && pwd)"
FORK_DIR="$HACKATON_DIR/fmc130-assistant"
DESKTOP_DIR="$FORK_DIR/apps/desktop"
OUT_DIR="$HACKATON_DIR/dist"

if [[ ! -d "$DESKTOP_DIR" ]]; then
  echo "error: no se encontró $DESKTOP_DIR" >&2
  exit 1
fi

cd "$DESKTOP_DIR"

if [[ "${1:-}" != "--skip-install" ]]; then
  echo "[1/5] Instalando dependencias del workspace (pnpm install)…"
  pnpm install --frozen-lockfile
else
  echo "[1/5] Instalación omitida (--skip-install)."
fi

echo "[2/5] Compilando paquetes del workspace y la app…"
pnpm --filter @open-pets/desktop... build

echo "[3/5] Compilando el paquete de escritorio…"
pnpm build

echo "[4/5] Limpiando salida de empaquetado…"
node scripts/clean-package-output.cjs

echo "[5/5] Empaquetando AppImage (x64)…"
pnpm exec electron-builder --linux AppImage --x64 --publish never

mkdir -p "$OUT_DIR"
cp -f dist-electron/FMC130-Assistant-*-linux-x86_64.AppImage "$OUT_DIR/"
echo "Listo: $OUT_DIR/FMC130-Assistant-*-linux-x86_64.AppImage"
