# Qualitätssicherung (QA)

Kontor sichert Qualität **lokal und schnell** (bewusst ohne CI/GitHub Actions). Drei Ebenen,
eine Wahrheit: `scripts/qa.sh`.

## Einmalige Einrichtung

```bash
./scripts/install-hooks.sh   # richtet die lokalen Git-Hooks ein (pre-commit + pre-push)
```

Die Hooks liegen nicht im Repo, daher muss der Installer einmal je Arbeitskopie laufen.
swift-format kommt aus der Xcode-Toolchain (`xcrun swift-format`), es ist kein `brew` nötig.

## Ebene 1: automatisch bei jedem Commit/Push

- **pre-commit** → `./scripts/qa.sh --fast` (Sekunden): Quote-Check, PII-Check, Format-Check.
  Kein Build/Test, damit Committen schnell bleibt.
- **pre-push** → `./scripts/qa.sh --full`: zusätzlich Build + alle Unit-Tests.

Notausgang im Einzelfall: `git commit --no-verify` bzw. `git push --no-verify`.

## Ebene 2: vor jedem Release

`scripts/release.sh` und `scripts/release-appstore.sh` rufen `./scripts/qa.sh --fast` plus die
Tests auf. Ein Release mit angeschlagenem Gate bricht ab.

## Ebene 3: wöchentlicher QA-Sweep (manuell, ca. 15 min)

1. `./scripts/coverage.sh` ansehen — Abdeckung pro Datei (Schwerpunkt `Kontor/Berechnung` +
   `Kontor/Server`, schwächste zuerst). Blinde Flecken und Regressionen früh erkennen.
2. `/code-review` auf den Wochendiff (Korrektheit + Vereinfachung).
3. `/security-review` auf die sicherheitsrelevanten Flächen: MCP-Server (`Kontor/Server/`),
   Kontoauszug-Import-Parser (`Berechnung/Bankimport.swift`), JSON-Backup (`Berechnung/Backup.swift`).

## Die Skripte im Überblick

| Skript | Zweck |
|---|---|
| `scripts/qa.sh --fast\|--full` | Sammelbefehl (Gates, optional Build+Test) |
| `scripts/install-hooks.sh` | Git-Hooks lokal einrichten (idempotent) |
| `scripts/quote-check.sh` | typografische Quotes als String-Delimiter (Build-Bruch) |
| `scripts/pii-check.sh` | eingecheckte Personendaten |
| `scripts/format-check.sh` | swift-format lint (gatet `Kontor/`, `.swift-format`) |
| `scripts/coverage.sh` | Testabdeckung pro Datei (xccov) |

**Format automatisch beheben:** `xcrun swift-format format -i -r Kontor KontorTests`.

## Konventionen (Kurzform, Details in CLAUDE.md)

- Formatierung gegatet nur für `Kontor/` (Auslieferungscode). `KontorTests/` wird mitformatiert,
  aber nicht lint-gegatet: Tests dürfen pragmatisch bleiben (force try in Fixtures, lange
  Erklär-Kommentare).
- Neue Tests: Swift Testing (`@Test`, deutsche Namen ohne `test`-Präfix), in-memory über
  `testContainer()`/`testKontext()`, `mitTemporaerenBelegen { }` sobald `Belege.basis` gelesen wird.
- Nach neuen Tests die `@Test`-Gesamtzahl gegenprüfen (xcodebuild kann neue Tests still
  übergehen), im Zweifel `xcodebuild clean test`.
