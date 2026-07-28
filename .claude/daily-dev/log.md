# Daily Repo Dev Log

## 2026-07-28
- Gebaut: Quote-Check in beiden Release-Skripten ergänzt → PR (siehe Branch `claude/pensive-hypatia-fcxeqj`)
- Notiz: `scripts/release.sh` und `scripts/release-appstore.sh` liefen bisher nur mit `pii-check.sh`
  vor Tests/Build, nicht mit `scripts/quote-check.sh`. Laut `CLAUDE.md` sind typografische
  Anführungszeichen als String-Delimiter ein "häufiger Auto-PR-Fehler", der den Swift-Build
  bricht — der Quote-Check fängt das jetzt vor dem (langsamen) Test+Build-Schritt ab, analog
  zum bereits vorhandenen PII-Gate.
- Kontext: PR #1 (`claude/pensive-hypatia-xw2vpi`, "ci: Quote-/PII-Guard-Skripte als GitHub-
  Actions-Check") war zu Beginn dieses Laufs bereits offen und ungemergt — führt beide Guards
  in CI aus. Dieser Fix ergänzt das lokale Release-Tooling (kein Überschneidung mit der CI-Datei).
- Verworfen (für später): eigener macOS-Build/Test-Workflow in GitHub Actions (xcodebuild auf
  `macos-latest`) — sinnvoll, aber erst nachdem PR #1 gemerged ist, um Konflikte in
  `.github/workflows/` zu vermeiden. Auch: Swift-Quellcode-Änderungen wurden bewusst
  vermieden, da in dieser (Linux-)Umgebung kein Swift-Toolchain zur Build-Verifikation
  verfügbar ist (`swift`/`xcodebuild` fehlen) — Kandidaten wurden auf reines
  Bash/Doku-Tooling beschränkt, das sich hier tatsächlich verifizieren lässt.
