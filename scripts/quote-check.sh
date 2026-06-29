#!/usr/bin/env bash
#
# quote-check.sh — Gate gegen typografische Anführungszeichen als String-Delimiter.
#
# Swift-Strings MÜSSEN mit ASCII " (U+0022) begrenzt werden. Werden stattdessen
# typografische Quotes “ (U+201C) / ” (U+201D) als Begrenzer verwendet, bricht der
# Build mit einem kryptischen Lexer-Fehler — ein wiederkehrender Auto-PR-Fehler.
#
# Erkennung: U+201D (”) kommt in diesem Codebase NIE legitim als Inhalt vor (deutsche
# Anführungszeichen sind „…“ = U+201E/U+201C). Jeder Treffer ist daher ein verirrtes
# Delimiter-Quote. (Die zweite Variante „+" mit ASCII-" statt U+201C fängt der Compiler
# als Syntaxfehler ab — dafür braucht es keinen Grep.)
#
# Nutzung:  ./scripts/quote-check.sh        (Exit 0 = sauber, 1 = Treffer)
#
set -euo pipefail
cd "$(dirname "$0")/.."

# U+201D (”) in getrackten Swift-Dateien suchen.
if git grep -nI $'”' -- '*.swift' > /tmp/quote-hits.$$ 2>/dev/null; then
  echo "✗ Quote-Check: typografisches ” (U+201D) in Swift-Code gefunden —"
  echo "  vermutlich als String-Delimiter statt ASCII \". Das bricht den Build:"
  echo
  cat /tmp/quote-hits.$$
  rm -f /tmp/quote-hits.$$
  echo
  echo "→ Delimiter auf ASCII \" setzen; deutsche Quotes nur als Inhalt („…“ = U+201E/U+201C)."
  exit 1
fi
rm -f /tmp/quote-hits.$$
echo "✓ Quote-Check: keine typografischen Quotes als String-Delimiter."
