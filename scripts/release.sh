#!/usr/bin/env bash
# Packages NotchDeck for sharing: build/NotchDeck-<version>.zip and .dmg.
#
# Without an Apple Developer ID the app is signed with the local "NotchDeck Local" identity (or
# ad hoc), so on another Mac it opens with right-click → Open (or Privacy & Security → Open Anyway).
# With a Developer ID, set DEVELOPER_ID="Developer ID Application: Name (TEAMID)" and NOTARY_PROFILE
# (from `xcrun notarytool store-credentials`, which needs Xcode) and this script signs with the
# hardened runtime, notarizes and staples.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
APP=build/NotchDeck.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP/Contents/Resources/MediaRemoteBridge.dylib"
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
fi

ZIP="build/NotchDeck-$VERSION.zip"
DMG="build/NotchDeck-$VERSION.dmg"
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "NotchDeck $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "Built $ZIP and $DMG"
echo "Publish them as a GitHub release tagged v$VERSION; Settings → About checks that repository for updates."
