#!/usr/bin/env bash
#
# pii-check.sh — Gate gegen versehentlich eingecheckte Personendaten.
#
# Durchsucht alle von Git getrackten Dateien (außer diesem Skript selbst) nach
# bekannten Klartext-Markern echter Personen-/Finanzdaten des Betreibers. Muss
# **leer** sein, bevor das Repo öffentlich gemacht wird (siehe Phase 6 / Historie-Gate).
#
# Nutzung:  ./scripts/pii-check.sh        (Exit 0 = sauber, 1 = Treffer)
# CI:       als Schritt einbinden; ein Treffer bricht den Build ab.
#
set -euo pipefail
cd "$(dirname "$0")/.."

# Bekannte Marker (case-insensitiv). Bewusst spezifisch, um Fehlalarme zu vermeiden.
# Hinweis: "wiredframe" (Bundle-ID de.wiredframe.Kontor / GitHub-Org) ist KEIN PII und
# absichtlich nicht gelistet – nur die persönliche E-Mail-Adresse.
PATTERNS=(
  'ulf'
  'schuster'
  'penzberg'
  'sindelsdorf'
  'weilheim schongau'
  'datamints'
  'k(ue|ü)chenatlas'
  'ideenm(u|ü)hle'
  'toscolano'
  'asfinag'
  'petermichl'
  'migross'
  'accounts@wiredframe\.de'
  'DE08703510300000195651'                 # echte Konto-IBAN
  'DE16E0100000020245'                     # echte Gläubiger-IDs …
  'DE94ZZZ00000561653'
  'DE24ZZZ00000561652'
  'DE31ZZZ00000001836'
  'DE41EON00000129793'
  'DE95ZZZ00000053646'
  'DE93ZZZ00000078611'
  'DE3000100000001272'
)

# Zu einer Alternation zusammensetzen.
JOINED=$(IFS='|'; echo "${PATTERNS[*]}")

# Sanktionierte Ausnahme: die bewusste Urheber-/Copyright-Nennung im README ist
# öffentliche Attribution (vom Betreiber selbst gesetzt, „Update author name"),
# KEIN versehentliches Leak – und landet nicht im App-Bundle. Nur GENAU diese
# Zeile wird durchgelassen; alle übrigen Marker (Adresse, IBANs, Gläubiger-IDs,
# Mandanten, E-Mail) schlagen weiterhin hart an.
ALLOWLIST='Urheber \(Ulf Schuster\)'

# In allen getrackten Dateien suchen, dieses Skript ausnehmen; sanktionierte Zeile filtern.
git grep -nIiE "$JOINED" -- ':!scripts/pii-check.sh' 2>/dev/null | grep -vE "$ALLOWLIST" > /tmp/pii-hits.$$ || true
if [ -s /tmp/pii-hits.$$ ]; then
  echo "✗ PII-Check: mögliche Personendaten gefunden:"
  echo
  cat /tmp/pii-hits.$$
  rm -f /tmp/pii-hits.$$
  echo
  echo "→ Bitte durch synthetische Werte ersetzen, bevor das Repo öffentlich wird."
  exit 1
fi
rm -f /tmp/pii-hits.$$
echo "✓ PII-Check: keine bekannten Personendaten-Marker (außer sanktionierter Urheber-Nennung)."
