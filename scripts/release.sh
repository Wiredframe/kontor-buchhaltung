#!/usr/bin/env bash
#
# release.sh — Kontor als kostenloses, AD-HOC signiertes Release bauen (KEINE Notarisierung).
#
# Warum ad-hoc: Ohne (kostenpflichtiges) Apple-Developer-Programm wird nicht notarisiert.
# Apple Silicon verlangt aber MINDESTENS eine ad-hoc-Signatur, sonst startet die App gar nicht.
# Beim ersten Start entfernt der Nutzer die Gatekeeper-Quarantäne (siehe README → Installation).
#
# Aufruf:   ./scripts/release.sh
# Ergebnis: build-release/Kontor.app (ad-hoc signiert) + Kontor-<version>.zip + SHA256 für den Cask.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="build-release"
DERIVED="$OUT/dd"
ENTITLEMENTS="Kontor/Kontor.entitlements"
APP="$OUT/Kontor.app"

echo "▸ 1/5  PII-Check (kein Release mit eingecheckten Personendaten)"
./scripts/pii-check.sh

echo "▸ 2/5  Tests"
xcodebuild test -scheme Kontor -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -quiet

echo "▸ 3/5  Build (Release, unsigniert)"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild build -scheme Kontor -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO -quiet
cp -R "$DERIVED/Build/Products/Release/Kontor.app" "$APP"

echo "▸ 4/5  Ad-hoc signieren (inkl. Sandbox-Entitlements)"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "▸ 5/5  ZIP packen + SHA256"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$OUT/Kontor-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

cat <<EOF

✓ Fertig (NICHT notarisiert, ad-hoc signiert)
   App    : $APP
   ZIP    : $ZIP
   Version: $VERSION
   SHA256 : $SHA

Nächste Schritte:
   1) Release veröffentlichen (ZIP anhängen):
        gh release create v$VERSION "$ZIP" \\
          --title "Kontor $VERSION" \\
          --notes "Kontor $VERSION – kostenlos & quelloffen. Installation siehe README (nicht notarisiert)."
   2) Homebrew-Cask aktualisieren (Wiredframe/homebrew-kontor → Casks/kontor.rb):
        version "$VERSION"
        sha256 "$SHA"
EOF
