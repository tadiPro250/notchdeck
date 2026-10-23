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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The system Now Playing bridge: a dylib loaded by Apple's /usr/bin/perl (see Helpers/).
clang -dynamiclib -fobjc-arc -O2 -framework Foundation -framework AppKit \
    -o "$APP/Contents/Resources/MediaRemoteBridge.dylib" Helpers/MediaRemoteBridge.m
cp Helpers/mediaremote.pl "$APP/Contents/Resources/mediaremote.pl"
# Sign with the stable local identity when it exists (scripts/make-signing-identity.sh), so
# Accessibility and Automation grants survive rebuilds. Ad-hoc signing works but loses them.
IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk '/"NotchDeck Local"/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP/Contents/Resources/MediaRemoteBridge.dylib"
codesign --force --sign "${IDENTITY:--}" "$APP"
[[ -z "$IDENTITY" ]] && echo "Note: ad-hoc signed; run scripts/make-signing-identity.sh to keep permissions across rebuilds"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x NotchDeck 2>/dev/null || true
    rm -rf /Applications/NotchDeck.app
    cp -R "$APP" /Applications/
    open /Applications/NotchDeck.app
    echo "Installed to /Applications and launched"
fi
