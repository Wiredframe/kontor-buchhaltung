#!/usr/bin/env bash
#
# release.sh — Kontor signiert (Developer ID) bauen, notarisieren und das Ticket anheften.
#
# Voraussetzungen (einmalig):
#   1. „Developer ID Application"-Zertifikat im Schlüsselbund (Apple Developer Program).
#   2. Notary-Zugang als Keychain-Profil hinterlegen:
#        xcrun notarytool store-credentials kontor-notary \
#          --apple-id "DEINE_APPLE_ID" --team-id "DEINE_TEAM_ID" \
#          --password "APP-SPEZIFISCHES-PASSWORT"
#
# Aufruf:
#   TEAM_ID=ABCDE12345 NOTARY_PROFILE=kontor-notary ./scripts/release.sh
#
# Ergebnis: build-release/Kontor.app (signiert + notarisiert + gestapelt) und Kontor.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEAM_ID:?Bitte TEAM_ID setzen (Developer Team ID)}"
: "${NOTARY_PROFILE:=kontor-notary}"

OUT="build-release"
ARCHIVE="$OUT/Kontor.xcarchive"
APP="$OUT/Kontor.app"
ZIP="$OUT/Kontor.zip"

echo "▸ 1/6  PII-Check (kein Release mit eingecheckten Personendaten)"
./scripts/pii-check.sh

echo "▸ 2/6  Tests"
xcodebuild test -scheme Kontor -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  | tail -1

echo "▸ 3/6  Archive (Developer ID, Hardened Runtime)"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild archive \
  -scheme Kontor \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Developer ID Application"

echo "▸ 4/6  Export (Developer ID)"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT"

echo "▸ 5/6  Notarisieren (notarytool submit --wait)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ 6/6  Ticket anheften & ZIP neu packen"
xcrun stapler staple "$APP"
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
xcrun stapler validate "$APP"

echo "✓ Fertig: $APP (notarisiert) und $ZIP"
