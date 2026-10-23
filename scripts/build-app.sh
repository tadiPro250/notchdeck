#!/usr/bin/env bash
# Builds NotchDeck.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/NotchDeck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/NotchDeck" "$APP/Contents/MacOS/NotchDeck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature: enough to run locally and to keep the Automation permission between launches.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x NotchDeck 2>/dev/null || true
    rm -rf /Applications/NotchDeck.app
    cp -R "$APP" /Applications/
    open /Applications/NotchDeck.app
    echo "Installed to /Applications and launched"
fi
