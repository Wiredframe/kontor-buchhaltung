#!/usr/bin/env bash
#
# format-check.sh — Gate für swift-format (Apple). Prüft Formatierung + leichte
# statische Regeln gegen .swift-format, ändert NICHTS (nur lint).
#
# Gegatet wird nur der Auslieferungscode Kontor/. KontorTests/ wird mitformatiert
# (siehe Formatier-Befehl unten), aber NICHT lint-gegatet: Tests dürfen pragmatisch
# bleiben (force try in Fixtures, lange Erklär-Kommentare) ohne jeden Commit zu blocken.
#
# swift-format kommt aus der Xcode-Toolchain (xcrun), kein brew nötig. Fehlt es
# (z. B. Xcode-Command-Line-Tools ohne Toolchain), wird der Check mit Warnung
# übersprungen statt den Commit zu blockieren.
#
# Formatieren (schreibt in place):  xcrun swift-format format -i -r Kontor KontorTests
#
# Nutzung:  ./scripts/format-check.sh   (Exit 0 = sauber, 1 = Treffer)
#
set -euo pipefail
cd "$(dirname "$0")/.."

if ! xcrun --find swift-format >/dev/null 2>&1; then
  echo "⚠ Format-Check übersprungen: swift-format nicht in der Toolchain gefunden."
  echo "  (Xcode installieren/auswählen; format-check bleibt dann aktiv.)"
  exit 0
fi

if xcrun swift-format lint --strict --parallel --recursive Kontor; then
  echo "✓ Format-Check: swift-format sauber (Kontor/)."
else
  echo
  echo "✗ Format-Check: swift-format meldet Abweichungen (siehe oben)."
  echo "→ Automatisch beheben: xcrun swift-format format -i -r Kontor KontorTests"
  exit 1
fi
