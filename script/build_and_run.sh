#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
if (( $# > 1 )); then
  echo "usage: $0 [--build-only|--verify|--debug|--logs|--telemetry]" >&2
  exit 2
fi

APP_NAME="CharacterHostDemo"
BUNDLE_ID="local.characterkit.CharacterHostDemo"
MIN_SYSTEM_VERSION="13.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/Tools/HostDemo"
BUILD_ROOT="$ROOT_DIR/.build/native-demo"
SWIFT_BUILD_PATH="$BUILD_ROOT/swiftpm"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_EXECUTABLE="$APP_CONTENTS/MacOS/$APP_NAME"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

case "$MODE" in
  run|--build-only|--verify|--debug|--logs|--telemetry) ;;
  *)
    echo "usage: $0 [--build-only|--verify|--debug|--logs|--telemetry]" >&2
    exit 2
    ;;
esac

# Building a new bundle must not close a running demo. Relaunch modes stop only
# the executable belonging to this checkout, rather than every matching process name.
if [[ "$MODE" != "--build-only" ]]; then
  while IFS= read -r CHARACTERKIT_APP_PID; do
    CHARACTERKIT_APP_PATH="$(/bin/ps -p "$CHARACTERKIT_APP_PID" -o comm= 2>/dev/null || true)"
    if [[ "$CHARACTERKIT_APP_PATH" == "$APP_EXECUTABLE" ]]; then
      /bin/kill "$CHARACTERKIT_APP_PID" 2>/dev/null || true
    fi
  done < <(/usr/bin/pgrep -x "$APP_NAME" || true)
fi
mkdir -p "$BUILD_ROOT"
/usr/bin/xcrun swift build \
  --package-path "$PACKAGE_DIR" \
  --build-path "$SWIFT_BUILD_PATH" \
  --product "$APP_NAME" \
  --configuration debug

BIN_DIR="$(/usr/bin/xcrun swift build \
  --package-path "$PACKAGE_DIR" \
  --build-path "$SWIFT_BUILD_PATH" \
  --configuration debug \
  --show-bin-path)"
BUILD_EXECUTABLE="$BIN_DIR/$APP_NAME"
if [[ ! -x "$BUILD_EXECUTABLE" ]]; then
  echo "Built executable not found: $BUILD_EXECUTABLE" >&2
  exit 1
fi

case "$APP_BUNDLE" in
  "$BUILD_ROOT"/*.app) ;;
  *) echo "Refusing to stage outside the local build directory: $APP_BUNDLE" >&2; exit 1 ;;
esac
/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$APP_CONTENTS/MacOS" "$APP_RESOURCES"
/bin/cp "$BUILD_EXECUTABLE" "$APP_EXECUTABLE"
/bin/chmod 755 "$APP_EXECUTABLE"

shopt -s nullglob
RESOURCE_BUNDLES=("$BIN_DIR"/*.bundle)
for RESOURCE_BUNDLE in "${RESOURCE_BUNDLES[@]}"; do
  [[ -d "$RESOURCE_BUNDLE" ]] || continue
  /usr/bin/ditto "$RESOURCE_BUNDLE" "$APP_RESOURCES/$(basename "$RESOURCE_BUNDLE")"
done
if [[ ! -d "$APP_RESOURCES/CharacterKit_ReactiveCharacterKit.bundle" ]]; then
  echo "CharacterKit SwiftPM resource bundle was not found in $BIN_DIR" >&2
  exit 1
fi

cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Built app bundle: $APP_BUNDLE"
if [[ "$MODE" == "--build-only" ]]; then
  exit 0
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --verify)
    open_app
    /bin/sleep 1
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null
    echo "Verified running process: $APP_NAME"
    ;;
  --debug)
    open_app
    /bin/sleep 1
    APP_PID="$(/usr/bin/pgrep -x "$APP_NAME" | /usr/bin/head -n 1)"
    exec /usr/bin/lldb -p "$APP_PID"
    ;;
  --logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
esac
