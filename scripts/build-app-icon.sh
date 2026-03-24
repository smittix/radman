#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/dist/AppIcon.icns}"
PREVIEW_PATH="$ROOT_DIR/dist/RadManIcon.png"
WORK_DIR="$(mktemp -d "$ROOT_DIR/.radman-icon.XXXXXX")"
BASE_PNG="$WORK_DIR/radman-base.png"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$(dirname "$OUTPUT_PATH")" "$ICONSET_DIR"

python3 "$ROOT_DIR/scripts/generate-radman-icon.py" "$BASE_PNG"
cp "$BASE_PNG" "$PREVIEW_PATH"

build_icon() {
  local size="$1"
  local name="$2"
  sips -z "$size" "$size" "$BASE_PNG" --out "$ICONSET_DIR/$name" >/dev/null
}

build_icon 16 "icon_16x16.png"
build_icon 32 "icon_16x16@2x.png"
build_icon 32 "icon_32x32.png"
build_icon 64 "icon_32x32@2x.png"
build_icon 128 "icon_128x128.png"
build_icon 256 "icon_128x128@2x.png"
build_icon 256 "icon_256x256.png"
build_icon 512 "icon_256x256@2x.png"
build_icon 512 "icon_512x512.png"
sips -z 1024 1024 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

python3 "$ROOT_DIR/scripts/build-icns.py" "$ICONSET_DIR" "$OUTPUT_PATH"
echo "Created app icon at $OUTPUT_PATH"
echo "Created preview icon at $PREVIEW_PATH"
