#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RadMan"
DISPLAY_NAME="RadMan - Radtel 950-Pro Radio Manager"
PRODUCT_NAME="HorizonRFMac"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ICON_PATH="$DIST_DIR/AppIcon.icns"
CACHE_HOME="$ROOT_DIR/.tmp-home"
MODULE_CACHE="$CACHE_HOME/.cache/clang/ModuleCache"
SWIFTPM_CACHE="$ROOT_DIR/.swiftpm-cache"
SWIFTPM_CONFIG="$ROOT_DIR/.swiftpm-config"
SWIFTPM_SECURITY="$ROOT_DIR/.swiftpm-security"

mkdir -p "$MODULE_CACHE" "$SWIFTPM_CACHE" "$SWIFTPM_CONFIG" "$SWIFTPM_SECURITY"
export HOME="$CACHE_HOME"
export XDG_CACHE_HOME="$CACHE_HOME/.cache"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"

echo "Building $APP_NAME with Swift Package Manager..."
swift build \
  --disable-sandbox \
  -c release \
  --package-path "$ROOT_DIR" \
  --cache-path "$SWIFTPM_CACHE" \
  --config-path "$SWIFTPM_CONFIG" \
  --security-path "$SWIFTPM_SECURITY" \
  --product "$PRODUCT_NAME"

EXECUTABLE_PATH="$(find "$ROOT_DIR/.build" -type f -perm -111 -name "$PRODUCT_NAME" | head -n 1)"
if [[ -z "$EXECUTABLE_PATH" ]]; then
  echo "Could not find the built executable for $PRODUCT_NAME." >&2
  exit 1
fi

"$ROOT_DIR/scripts/build-app-icon.sh" "$ICON_PATH"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>RadMan</string>
    <key>CFBundleDisplayName</key>
    <string>RadMan - Radtel 950-Pro Radio Manager</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.radman.rt950pro</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>RadMan</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Created app bundle at $APP_DIR"
echo "Next step: run scripts/make-dmg.sh to wrap it in a disk image."
