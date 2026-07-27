# Daily Repo Dev — Log

## 2026-07-27
- Gebaut: CI-Workflow für Quote-/PII-Guard-Skripte → PR (siehe Branch `daily/ci-guard-checks`)
- Notiz: Repo hat aktuell **keine** GitHub-Actions-Workflows (`.github/` enthielt nur
  `FUNDING.yml`) und **kein macOS/Xcode-Toolchain** in dieser Umgebung — echte
  `xcodebuild build`/`test`-Läufe waren hier nicht ausführbar. Heutiger Beitrag daher
  bewusst auf reine Bash-Gates beschränkt (laufen ohne Xcode, lokal verifiziert:
  beide Skripte exit 0 auf dem aktuellen Stand).
- Verworfen (für später): Swift-Testlücken/kleine Bugfixes in `Kontor/Berechnung/*`
  (z. B. `Periode`/`Werte`) — dafür bräuchte ein zukünftiger Lauf entweder eine
  macOS-Umgebung oder müsste die Änderung sehr konservativ ohne Build-Verifikation
  vornehmen; heute nicht riskiert.
- Idee für morgen: einen echten macOS-CI-Job (`xcodebuild test -scheme Kontor
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`) auf `macos-latest`-Runnern
  ergänzen, sobald das in einer Umgebung mit Xcode verifiziert werden kann.
