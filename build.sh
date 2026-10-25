#!/bin/bash
# Builds "Divvy Native.app" into ./build.
#   ./build.sh            build only
#   ./build.sh install    build, copy to $INSTALL_DIR (default /Applications) and launch
#   ./build.sh test       run the logic tests in Tests/
set -euo pipefail
cd "$(dirname "$0")"

SWIFTC=(swiftc -swift-version 5 -target arm64-apple-macos14.0
  -framework AppKit -framework Carbon -framework ApplicationServices -framework ServiceManagement)
APP_SOURCES=$(ls Sources/*.swift | grep -v '/main.swift$')

if [[ "${1:-}" == "test" ]]; then
  mkdir -p build
  "${SWIFTC[@]}" $APP_SOURCES Tests/main.swift -o build/tests
  ./build/tests
  exit
fi

APP="build/Divvy Native.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

"${SWIFTC[@]}" -O Sources/*.swift -o "$APP/Contents/MacOS/Divvy"

if [[ ! -f Resources/AppIcon.icns ]]; then
  swift tools/make-icon.swift Resources/AppIcon.icns
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier com.ivan.divvy-native "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  DEST="${INSTALL_DIR:-/Applications}"
  pkill -f "Divvy Native.app/Contents/MacOS/Divvy" 2>/dev/null || true
  mkdir -p "$DEST"
  rm -rf "$DEST/Divvy Native.app"
  cp -R "$APP" "$DEST/"
  open "$DEST/Divvy Native.app"
  echo "Installed to $DEST/Divvy Native.app"
fi
