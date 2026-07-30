#!/usr/bin/env bash
#
# install-hooks.sh — Lokale Git-Hooks einrichten (bewusst kein CI).
#
# .git/hooks/ liegt nicht im Repo, daher richtet dieser Installer die Hooks lokal ein.
# Idempotent: schreibt nur Hooks mit unserem Marker und überschreibt beim erneuten Lauf
# ausschließlich diese (fremde/eigene Hooks ohne Marker bleiben unangetastet).
#
#   pre-commit -> ./scripts/qa.sh --fast   (Sekunden: quote/pii/format)
#   pre-push   -> ./scripts/qa.sh --full   (zusätzlich Build + Tests)
#
# Notausgang im Einzelfall: git commit --no-verify  bzw.  git push --no-verify
#
# Nutzung:  ./scripts/install-hooks.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

MARKER="# KONTOR-QA-HOOK (verwaltet von scripts/install-hooks.sh)"
HOOKDIR="$(git rev-parse --git-path hooks)"
mkdir -p "$HOOKDIR"

installiere() {
  local name="$1" befehl="$2" gitcmd="$3"
  local ziel="$HOOKDIR/$name"

  if [ -f "$ziel" ] && ! grep -qF "$MARKER" "$ziel"; then
    echo "⚠ $name existiert bereits und stammt nicht von uns — übersprungen."
    echo "  Bitte manuell zusammenführen: $befehl"
    return
  fi

  cat > "$ziel" <<HOOK
#!/usr/bin/env bash
$MARKER
set -euo pipefail
cd "\$(git rev-parse --show-toplevel)"
if ! $befehl; then
  echo
  echo "✗ $name abgebrochen: QA-Gate hat angeschlagen."
  echo "  Notausgang im Einzelfall: git $gitcmd --no-verify"
  exit 1
fi
HOOK
  chmod +x "$ziel"
  echo "✓ $name installiert -> $befehl"
}

installiere "pre-commit" "./scripts/qa.sh --fast" "commit"
installiere "pre-push"   "./scripts/qa.sh --full" "push"

echo
echo "Fertig. Die Hooks greifen ab dem nächsten Commit/Push."
echo "Notausgang im Einzelfall: --no-verify an git commit/push anhängen."
