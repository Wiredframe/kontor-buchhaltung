#!/usr/bin/env bash
#
# qa.sh — Ein Sammelbefehl für die Qualitätssicherung. Eine Wahrheit für Hooks,
# Release-Skripte und die manuelle Gegenprobe.
#
# Zwei Stufen:
#   --fast   (Sekunden, für pre-commit): quote-check, pii-check, format-check.
#            KEIN Build/Test, damit jeder Commit schnell bleibt.
#   --full   (für pre-push und Release): zusätzlich Build + Tests.
#
# Nutzung:  ./scripts/qa.sh --fast
#           ./scripts/qa.sh --full
#
# Exit 0 = sauber, ungleich 0 = ein Gate hat angeschlagen.
#
set -euo pipefail
cd "$(dirname "$0")/.."

MODUS="${1:-}"
if [ "$MODUS" != "--fast" ] && [ "$MODUS" != "--full" ]; then
  echo "Nutzung: $0 --fast | --full" >&2
  exit 2
fi

echo "▸ QA ($MODUS)"

echo "▸ Quote-Check"
./scripts/quote-check.sh

echo "▸ PII-Check"
./scripts/pii-check.sh

# format-check.sh kommt in Phase 2 dazu. Fehlt es (frischer Checkout, alter Stand),
# wird der Schritt übersprungen statt den ganzen Lauf zu brechen.
if [ -x ./scripts/format-check.sh ]; then
  echo "▸ Format-Check"
  ./scripts/format-check.sh
else
  echo "▸ Format-Check übersprungen (scripts/format-check.sh nicht vorhanden)"
fi

if [ "$MODUS" = "--full" ]; then
  echo "▸ Tests (Build + Unit)"
  xcodebuild test -scheme Kontor -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO -quiet
fi

echo "✓ QA ($MODUS) sauber."
