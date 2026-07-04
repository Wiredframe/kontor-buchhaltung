# Kontor

Lokale, offline-first Buchhaltungs-App für macOS – zugeschnitten auf einen
freiberuflichen UI-Designer (KSK-versichert, EÜR, Soll-Versteuerung,
vierteljährliche UStVA). SwiftUI + SwiftData, alle Daten bleiben auf dem Gerät.

[![Download](https://img.shields.io/badge/Download-macOS-2563eb?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Wiredframe/Kontor/releases) [![Website](https://img.shields.io/badge/Website-Landingpage-7c3aed?style=for-the-badge&logo=safari&logoColor=white)](https://wiredframe.github.io/kontor-landingpage/) [![Spenden](https://img.shields.io/badge/Spenden-Stripe-e11d48?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://wiredframe.github.io/kontor-landingpage/#spenden) [![Lizenz](https://img.shields.io/badge/Lizenz-PolyForm_Perimeter-64748b?style=for-the-badge)](LICENSE)

**macOS 15+** · SwiftUI + SwiftData · Bundle-ID `de.wiredframe.Kontor` · keine Telemetrie

**[Website & Download → wiredframe.github.io/kontor-landingpage](https://wiredframe.github.io/kontor-landingpage/)**

---

## Installation

Kontor ist **kostenlos & quelloffen**. Fertige Builds gibt es unter
[Releases](https://github.com/Wiredframe/Kontor/releases) – **macOS 15+**.

> Die App ist **nicht notariell signiert** (bewusst, ohne kostenpflichtiges Apple-Developer-Programm).
> Beim ersten Start meldet macOS deshalb sinngemäß „… kann nicht geöffnet werden, Apple kann sie
> nicht auf Schadsoftware prüfen". Das ist erwartbar – so startest du sie trotzdem:

1. `Kontor.zip` aus den Releases laden, entpacken und **`Kontor.app` nach „Programme"** ziehen.
2. **Rechtsklick** (Ctrl-Klick) auf `Kontor.app` → **„Öffnen"** → im Dialog erneut **„Öffnen"**.
3. Blockt macOS weiterhin (v. a. macOS 15 Sequoia): **Systemeinstellungen → Datenschutz &
   Sicherheit** → ganz unten bei „Kontor wurde blockiert …" auf **„Dennoch öffnen"** klicken.
4. Notfalls im **Terminal** die Quarantäne-Markierung entfernen, danach normal öffnen:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Kontor.app
   ```

Ab dem ersten erfolgreichen Start öffnet Kontor ganz normal. Wer dem Binary nicht traut, baut es
selbst (siehe [Build & Entwicklung](#build--entwicklung)) – der Quelltext liegt offen.

### Per Homebrew

```bash
brew tap wiredframe/kontor
brew trust --cask wiredframe/kontor/kontor
brew install --cask --no-quarantine kontor
```

`brew trust` ist seit **Homebrew 6** für Fremd-Taps Pflicht (ein Cask darf Code ausführen).
`--no-quarantine` überspringt den Gatekeeper-Block, weil Kontor nicht notariell signiert ist – sonst
müsstest du die App beim ersten Start manuell freigeben (siehe oben).

---

## Leitprinzipien (Rechen-/Steuerlogik)

Diese Regeln sind in der Engine fest verdrahtet und sollten bei Änderungen
bewusst beachtet werden:

- **USt / UStVA = Soll-Versteuerung** – maßgeblich ist das **Rechnungsdatum**.
- **Gewinn / ESt = Zuflussprinzip (EÜR)** – maßgeblich ist das **Zahlungsdatum**.
- **Geld immer `Decimal`**, nie `Double` (Konstanten über `dez("…")`).
- **Reverse-Charge (§13b)** ist cash-neutral (USt in KZ 84/85, zugleich Vorsteuer).
- **Forderungsausfall**: §17-USt-Korrektur **und** ESt-Rücklagen-Auflösung jeweils
  im Monat des Ausfalldatums; abgeschlossene Monate bleiben unverändert.
- **privat ≠ betrieblich** – getrennt erfasst und ausgewertet.
- **Local-first**, App-Sandbox aktiv.

---

## Funktionen

**Arbeitsfläche**
- **Übersicht (Dashboard):** Betrieblicher Gewinn, Frei verfügbar, Steuerrücklage;
  KPIs (offene Rechnungen, USt-Zahllast, Umsatz, nächste Frist); Gewinn-Trend-Chart;
  automatische Insights.
- **Kontoauszug:** In-App-Import des Sparkasse-CSV-CAMT-Exports. Jede Bankbewegung wird
  per Karten-Triage selbst zugeordnet (Einnahme, Betriebsausgabe, privat, KSK, Steuer,
  Steuererstattung …); die App **lernt** je Gläubiger/Händler die Zuordnung und schlägt
  sie beim nächsten Mal vor. Auto-Vorsteuer, idempotent (kein Doppelimport), bereits
  importierte Auszüge lassen sich erneut durchgehen („Neu zuordnen").
- **Aufgaben:** einmalig / monatlich / quartalsweise / jährlich (Reminders-Logik – beim
  Abhaken einer wiederkehrenden Aufgabe erscheint automatisch die nächste fällige).
  Monats- und Jahresabschluss zeigen die fälligen Aufgaben als Sidebar.

**Stammdaten**
- **Einnahmen:** Ausgangsrechnungen (Kunde, netto/USt/brutto, Rechnungs-/Zahlungsdatum,
  Status offen/bezahlt/ausgefallen, sortierbare Rechnungsnummer). Der Status führt
  Zahlungs- und Ausfalldatum automatisch. Beleg per OCR-Drop.
- **Ausgaben (gemeinsamer Ledger):** **ein** Modul für **alle** Abflüsse – Betriebsausgaben,
  Fixkosten, Subscriptions sowie Vorsorge (KSK) und Steuern (`TaxPayment`), gefiltert nach
  Art · Sparte · Monat. Pro Ausgabe brutto/VSt/netto, Steuerart (Inland 19 %, Reverse-Charge
  §13b, steuerfrei), Kategorie (laufend/jährlich/Anschaffung), umlagefähig; privat (Liquidität)
  vs. betrieblich (EÜR) getrennt. Wiederkehrende Kosten als **datierte Buchungen** – rechts
  wahlweise der Eintrags-Editor oder die **Vorlagen-Sidebar** (Vorlage per Klick in den Monat
  buchen) bzw. „Vormonat duplizieren". Vorsorge/Steuern bilden den **Ist**-Ledger (negativer
  Betrag = Erstattung), primär aus dem Kontoauszug-Import. KSK steht damit doppelt: **Soll**
  (Monatswert, im Monatsabschluss unter „Werte" gepflegt) und **Ist** (Abbuchung im Ledger).

**Auswertungen** (drei Zeithorizonte)
- **Monatsabschluss:** Monats- und Jahresansicht; Gewinn-Rechnung und Rücklagenkonto
  (USt-Zahllast, Vorsteuer, KSK, ESt) inkl. §17- und ESt-Ausfall-Korrektur; **KSK-Beträge
  und ESt-Satz pro Monat** in der Sidebar „Werte" pflegbar (erben vom Vormonat);
  „Monat abschließen" friert den Stand als Snapshot ein.
- **UStVA:** formular-getreu nach ELSTER-Kennzahlen – KZ 81 (Netto-Bemessung) → USt 19 % **und
  KZ 86 → USt 7 %** (inkl. Mischrechnungen), KZ 66 (Vorsteuer Inland), KZ 84/85 (§13b), KZ 67,
  §17-Korrektur, Zahllast KZ 83. Quartal oder Monat, gruppiert wie das Formular mit KZ-Badge und
  Erklärung je Zeile.
- **Jahresabschluss (EÜR):** Einnahmen (Zufluss), Ausgaben nach Kategorie, Gewinn,
  Vorsteuer; Steuerlast ESt+USt, KSK-Jahr, ESt-Abgleich, read-only Zahlungsblock;
  **Beleg-Export als ZIP** pro Jahr.

**Privat**
- Privat-Übersicht (Fixkosten, Subscriptions, Lebensmittel, Anschaffungen pro Monat),
  Lebensmittel- und Anschaffungs-Tracking mit optionalen Budgets.

**Übergreifend**
- **Erster Start:** Auswahl zwischen **leerer Datenbank** und **synthetischen Demodaten**
  (frei erfundene Persona einer UI/UX-Designerin) – zum risikofreien Ausprobieren, jederzeit löschbar.
- **Belege:** PDF/Bild per Drag-&-Drop oder Dialog anhängen, Inline-Vorschau im Inspektor
  (Klick öffnet die macOS-Vorschau). Ablage im App-Container unter `Belege/<Jahr>/`.
- **Geteilter Zeitraum:** gewähltes Jahr/Monat bleibt beim Wechsel zwischen Bereichen
  erhalten (Dashboard zeigt stets „heute").
- **Backup:** tägliches Auto-Backup (JSON, letzte 14 Tage), manueller Export/Import
  (dedupliziert, ohne Überschreiben) sowie Komplett-Backup samt Belegen.
- **KI-Zugriff (MCP, optional):** schlanker lokaler MCP-Server (HTTP/JSON-RPC auf
  `127.0.0.1`, Bearer-Token, nur Loopback) für externe Clients wie Claude Code –
  einschaltbar unter Einstellungen → KI-Zugriff. **Tokensparend** ausgelegt: wenige
  grobe Tools, Antworten sind fertige Engine-Zahlen bzw. dichte CSV statt Rohzeilen.
  Lesen deckt **alle Module** ab: Aggregate (`kontor_uebersicht`/`eur`/`ustva`/`monat`)
  + ein generisches `kontor_liste` (typ: einnahmen, offene_rechnungen, ausgaben,
  fixkosten, subscriptions, vorlagen, ksk, zahlungen, aufgaben, lebensmittel, einkaeufe) +
  Resources `kontor://…`. **Schreiben spiegelbildlich über alle Module** (selten nötig):
  `kontor_anlegen`/`kontor_aktualisieren`/`kontor_loeschen` mit demselben `typ`-Vokabular;
  Ändern/Löschen adressieren über eine `id`, die `kontor_liste` nur mit `mit_id=true`
  mitliefert (Lese-Pfad bleibt schlank). Vor dem ersten Schreibzugriff je Sitzung wird
  automatisch ein Backup angelegt. Den Kontoabgleich übernimmt **nicht** das MCP, sondern
  der In-App-CSV-Import.

---

## Architektur

Aufbau & Entscheidungen: [ARCHITEKTUR.md](ARCHITEKTUR.md) (Schichten, Datenmodell, Diagramme)

SwiftUI + SwiftData, klar geschichtet:

| Ordner             | Inhalt |
|--------------------|--------|
| `Kontor/Model`     | `@Model`-Entitäten, Enums, Helfer |
| `Kontor/Berechnung`| Reine, testbare Engine: `Steuer`, `Auswertung`, `Periode`, `Werte`, `TaskVorlagen`, `Bankimport`, `Import` (Triage/Apply/Lernregeln), `Backup`, `Belege`, `BelegOCR` |
| `Kontor/Views`     | SwiftUI-Views + wiederverwendbare Komponenten/Stil |
| `Kontor/Server`    | Optionaler lokaler MCP-Server: `MCPServer` (Transport), `MCPProtokoll` (JSON-RPC), `KontorMCP` (Tools/Resources), `KISicherung` |
| `KontorTests`      | Swift-Testing-Suite (Engine-Golden-Tests, Modell, Backup, OCR, MCP) |

Die Engine rechnet auf einfachen Werttypen (z. B. `AusgabePosten`), nicht auf
`@Model`-Objekten – dadurch ist sie ohne SwiftData testbar.

> Das `.xcodeproj` nutzt `PBXFileSystemSynchronizedRootGroup`: **neue `.swift`-Dateien
> im Projektordner werden automatisch in den Build aufgenommen** – kein manuelles
> Eintragen in die `project.pbxproj` nötig.

---

## Build & Entwicklung

**Voraussetzungen:** Xcode mit macOS-15-SDK.

**In Xcode:** Projekt öffnen, Scheme `Kontor`, `⌘R`.

**Per CLI:**

```bash
cd "…/Kontor"

# Tests (schnell, ohne Signing)
xcodebuild test -scheme Kontor -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Release-/Debug-Build MIT Signing (App liegt danach in DerivedData/…/Build/Products/Debug/Kontor.app)
xcodebuild -scheme Kontor -configuration Debug -destination 'platform=macOS' build
```

**Veröffentlichung (Developer ID + Notarisierung):** Für die Weitergabe außerhalb des App
Stores wird die App mit *Developer ID* signiert (Hardened Runtime ist aktiv), per
`notarytool` notarisiert und das Ticket angeheftet. Vor jedem Release prüft
`scripts/pii-check.sh`, dass keine echten Personendaten eingecheckt sind.

**Datenbank-Migration:** Neue, additive Properties an `@Model`-Klassen (mit Default)
migriert SwiftData automatisch beim Start. Schlägt das Öffnen fehl, legt die App den
defekten Store beiseite und startet leer (Wiederherstellung über JSON-Backup).

---

## Datenablage

Alles im sandboxed App-Container:

```
~/Library/Containers/de.wiredframe.Kontor/Data/Library/Application Support/
├── default.store            # SwiftData-Datenbank
├── Belege/<Jahr>/           # angehängte PDFs/Bilder
└── Backups/                 # tägliche Auto-Backups (JSON)
```

---

## Datenschutz & Sicherheit

Kontor ist **local-first**: alle Daten bleiben im sandboxed App-Container, es gibt **keine
Telemetrie** und keinen Netzwerkverkehr außer dem **optionalen** MCP-Server, der ausschließlich
auf `127.0.0.1` (Loopback) lauscht und Token-geschützt ist. Details und Meldewege siehe
[SECURITY.md](SECURITY.md).

## Geltungsbereich & Haftungsausschluss

Kontor ist bewusst für **eine** Steuersituation gebaut – nicht für den allgemeinen Fall.
Die Engine trifft **fest verdrahtete Annahmen**:

- **Soll-Versteuerung** (USt nach Rechnungsdatum) – **keine** Ist-Versteuerung.
- **EÜR** (Einnahmen-Überschuss-Rechnung) – keine Bilanzierung.
- **KSK-versichert** – KV/RV/PV als monatliche Beiträge; ESt-Rücklage als grobe Pauschale.
- **Ausgangsseitig 19 % und 7 % USt** (inkl. Mischrechnungen mit beiden Sätzen auf einer Rechnung) –
  **kein** Kleinunternehmer (§19), keine steuerfreien Ausgangsumsätze (außer USt = 0).
- **Eingangsseitig 19 % und 7 % Vorsteuer**, Reverse-Charge (§13b, cash-neutral) sowie steuerfrei.
- **Quartals- oder Monats-UStVA**, optional mit Dauerfristverlängerung.

Wer anders besteuert wird, kann Kontor nutzen, sollte die Zahlen aber besonders kritisch prüfen.

> **Keine Steuerberatung.** Alle Berechnungen sind vereinfachte Schätzungen und ersetzen
> weder Steuerberater:in noch Steuererklärung. Die Nutzung erfolgt auf eigene Verantwortung;
> für die Richtigkeit der Zahlen wird **keine Gewähr** übernommen. Prüfe alle Werte
> eigenständig, bevor du sie gegenüber dem Finanzamt verwendest.

---

## Lizenz

**Source-available**, **nicht** OSI-„Open-Source": [PolyForm Perimeter 1.0.0](LICENSE).
Du darfst Kontor **forken, anpassen und für jeden Zweck nutzen – auch geschäftlich** (z. B. dir
mit Claude Code einen maßgeschneiderten Fork bauen). Du darfst es nur **nicht verkaufen** oder
als konkurrierendes Ersatzprodukt an andere weitergeben (auch nicht kostenlos). Der kommerzielle
Verkauf von Kontor liegt beim Urheber (Ulf Schuster). Freiwillige
**[💛 Spenden](https://wiredframe.github.io/kontor-landingpage/#spenden)** (ohne Gegenleistung)
sind jederzeit willkommen.

---

*Keine Steuerberatung – siehe Haftungsausschluss oben. Berechnungen sind vereinfachte
Schätzungen und ersetzen keine Steuererklärung.*
