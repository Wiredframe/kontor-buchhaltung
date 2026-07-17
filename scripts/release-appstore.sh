#!/usr/bin/env bash
#
# release-appstore.sh — Kontor als Mac-App-Store-Build archivieren.
#
# Unterschied zum normalen `release.sh` (GitHub/Homebrew, ad-hoc signiert):
#   * Compiler-Flag APPSTORE  -> schliesst per `#if !APPSTORE` den MCP-Server
#     (Rejection Guideline 2.4.5, network.server) UND jeden Spendenaufruf
#     (Guideline 3.1.1) vollstaendig aus.
#   * Entitlements OHNE network.server: Kontor/Kontor-AppStore.entitlements.
#   * Ergebnis ist ein .xcarchive + ein hochladbares .pkg -- KEIN ad-hoc-ZIP.
#
# Der Upload zu App Store Connect passiert bewusst NICHT hier: er braucht ein
# "Apple Distribution"-Zertifikat + ASC-Zugang. Am einfachsten per Xcode:
#   Xcode -> Window -> Organizer -> Kontor.xcarchive -> "Distribute App" -> App Store Connect
# oder per CLI mit einem ASC-API-Key (.p8):
#   xcrun altool --upload-app -f build-appstore/export/*.pkg -t macos \
#     --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
#
# Aufruf:   ./scripts/release-appstore.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="build-appstore"
ARCHIVE="$OUT/Kontor.xcarchive"
EXPORT="$OUT/export"
TEAM="7RN999S858"
ENTITLEMENTS="Kontor/Kontor-AppStore.entitlements"

echo "* 1/4  PII-Check (kein Build mit eingecheckten Personendaten)"
./scripts/pii-check.sh

echo "* 2/4  Tests (Normal-Build, MCP vorhanden)"
xcodebuild test -scheme Kontor -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -quiet

echo "* 3/4  Archiv (APPSTORE-Flag, ohne MCP/Spende, App-Store-Entitlements)"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild archive \
  -scheme Kontor -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) APPSTORE' \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates

echo "* 4/4  Export fuer App Store Connect (.pkg)"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM</string>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -allowProvisioningUpdates

cat <<EOF

Fertig. Archiv + Export erstellt.
   Archiv : $ARCHIVE
   Export : $EXPORT  (enthaelt das .pkg fuer den Upload)

Upload nach App Store Connect (eine Variante waehlen):
   * Xcode -> Window -> Organizer -> Kontor.xcarchive -> "Distribute App" -> App Store Connect
   * xcrun altool --upload-app -f "$EXPORT"/*.pkg -t macos \\
       --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
EOF
