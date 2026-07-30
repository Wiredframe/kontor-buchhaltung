#!/usr/bin/env bash
#
# coverage.sh — Testabdeckung messen und pro Datei ausweisen.
#
# Bewusst NICHT in den Git-Hooks (zu langsam fürs Committen). Gedacht für den
# wöchentlichen QA-Sweep: blinde Flecken sichtbar machen, Abdeckungs-Regressionen
# früh sehen. Fokus auf die Rechen-/Server-Schicht (Kontor/Berechnung, Kontor/Server),
# wo die Geschäftslogik sitzt.
#
# Nutzung:  ./scripts/coverage.sh            (volle Datei-Tabelle, Schwerpunkt Engine)
#           ./scripts/coverage.sh --all      (alle Dateien, unsortiert nach xccov)
#
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE="$(mktemp -d)/Kontor.xcresult"
trap 'rm -rf "$(dirname "$BUNDLE")"' EXIT

echo "▸ Tests mit Coverage (das dauert)…"
xcodebuild test -scheme Kontor -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -enableCodeCoverage YES \
  -resultBundlePath "$BUNDLE" -quiet

echo
echo "▸ Abdeckung pro Datei (xccov)"
REPORT="$(xcrun xccov view --report "$BUNDLE")"

if [ "${1:-}" = "--all" ]; then
  echo "$REPORT"
  exit 0
fi

# Schwerpunkt: Engine- und Server-Dateien mit ihrer Prozentzahl, aufsteigend
# sortiert (die schwächste Abdeckung zuerst = die interessanteste Lücke).
# Achtung: der absolute Pfad enthält ein Leerzeichen ("Claude Code"), daher wird
# der Modul-Pfad und die Prozentzahl gezielt per Regex extrahiert (kein Spalten-Split).
echo "  (Kontor/Berechnung + Kontor/Server, schwächste zuerst)"
echo "$REPORT" \
  | grep -E '\.swift ' \
  | grep -E 'Berechnung/|Server/' \
  | while IFS= read -r zeile; do
      name=$(printf '%s\n' "$zeile" | grep -oE '(Berechnung|Server)/[A-Za-z0-9_]+\.swift' | head -1)
      pct=$(printf '%s\n' "$zeile" | grep -oE '[0-9]+\.[0-9]+%' | head -1)
      [ -n "$name" ] && printf '%8s  %s\n' "$pct" "$name"
    done \
  | sort -n \
  || echo "  (keine passenden Dateien im Report gefunden — ggf. --all nutzen)"

echo
echo "▸ Gesamtabdeckung"
echo "$REPORT" | grep -iE 'Kontor\.app|\.xctest' | head -3 | sed -E 's/  +/  /g'
