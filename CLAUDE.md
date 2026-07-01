# Kontor — Buchhaltungs-App (macOS, SwiftUI)

Lokale, offline Buchhaltungs-App für einen Freiberufler (Designer, KSK-versichert,
EÜR, **Soll-Versteuerung**, quartalsweise UStVA). Löst den bisher in Obsidian
erledigten Monats-/Quartals-/Jahresabschluss ab. **Die App-DB (SwiftData) ist die
Quelle der Wahrheit**, nicht mehr die Markdown-Dateien.

## Verbindliche Spezifikation (im Obsidian-Vault)
Diese drei Dateien sind die Spezifikation – bei Widersprüchen **nachfragen**, keine
stillen Annahmen bei Steuer-/Berechnungslogik:
- `~/Vault/Wiredframe/Buchhaltung/App-Konzept Buchhaltung.md` (Gesamtkonzept)
- `~/Vault/Wiredframe/Buchhaltung/Claude-Code-Brief.md` (Phase-1-Scope, Datenmodell, Formeln)
- `~/Vault/Wiredframe/Buchhaltung/Claude-Code-Prompt.md` (Arbeitsweise, Entwicklungsplan)

## Tech & Konventionen
- SwiftUI + **SwiftData** (lokale DB), `NavigationSplitView`. Ziel **macOS 15.0+**.
- Kein Netzwerk, local-first, **App-Sandbox an** (`Kontor/Kontor.entitlements`).
- Geld immer als **`Decimal`**, nie `Double`.
- Leichtes MVVM: Views + `@Model` + **kleine, rein testbare Berechnungs-Structs**
  (keine Rechenlogik in Views).
- Tests mit **Swift Testing** (`import Testing`, `@Test`, `#expect`).
- Swift-Sprachmodus aktuell **5.0** (bewusst, um Concurrency-Reibung zu vermeiden;
  später auf 6 hebbar).
- **String-Delimiter IMMER ASCII `"` (U+0022) — NIE typografische `“` `”` (U+201C/U+201D).**
  Typografische Quotes als String-Begrenzer brechen den Swift-Build (häufiger Auto-PR-Fehler).
  Deutsche Anführungszeichen `„…“` (U+201E/U+201C) **nur als Inhalt** in Strings/Kommentaren,
  nie als Delimiter. Achtung Falle: `„+“` heißt U+201E `+` U+201C — das **schließende** Zeichen
  ist `“` (U+201C), **kein** ASCII-`"`; schreibt man dort ein ASCII-`"`, endet der String
  vorzeitig. Gegenprobe vor dem Commit: **`scripts/quote-check.sh`** (Exit ≠ 0 = Treffer) bzw.
  direkt `rg '”' --glob '*.swift' Kontor KontorTests` — darf **nichts** liefern (U+201D `”`
  kommt im Code nie legitim vor und ist damit der zuverlässige Indikator für ein als Delimiter
  verirrtes typografisches Quote).
- Pro Schritt: bauen + testen, dann ein klarer Commit.

## Build & Test (CLI)
```bash
cd "~/Projekte/Claude Code/Kontor"
# Bauen (ohne Signatur – fürs reine Kompilieren/Verifizieren):
xcodebuild build -scheme Kontor -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
# Tests:
xcodebuild test  -scheme Kontor -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```
In Xcode einfach `Kontor.xcodeproj` öffnen und ⌘R / ⌘U. Beim ersten Run ggf.
einmalig ein Signing-Team wählen (oder „Sign to Run Locally").

## Projektstruktur
- **File-System-Synchronized Groups**: neue `.swift`-Dateien einfach in `Kontor/`
  (App) bzw. `KontorTests/` (Tests) ablegen – **kein** Eintrag in `project.pbxproj`
  nötig, Xcode zieht sie automatisch.
- `Kontor/` App-Code · `KontorTests/` Tests · geteiltes Scheme `Kontor`.

## Steuer-/Berechnungslogik (Kernentscheidungen)
- **Zwei Stichtagslogiken getrennt:** USt/UStVA = **Soll** (nach *Rechnungsdatum*);
  Gewinn/ESt (EÜR) = **Zuflussprinzip** (nach *Zahlungsdatum*). Dieselbe Rechnung
  wirkt in unterschiedlichen Perioden.
- **Privat ≠ betrieblich:** nur Betriebliches geht in EÜR/VSt. Private Fixkosten =
  nur Liquiditäts-/„Gehalt"-Planung, getrennt ausweisen.
- **Wiederkehrende Kosten = datierte Buchungen + Vorlagen (KEINE Wiederhol-/Gültigkeitsmechanik):**
  Fixkosten und Subscriptions sind **datierte `ExpenseEntry`** (`art` = `fixkosten`/`subscription`),
  genau wie Betriebsausgaben – es zählt nur das **Datum** des Eintrags. **Ein gemeinsames Modul
  „Ausgaben"** (`AusgabenView`) zeigt **alle** `ExpenseEntry` mit Filtern **Art** (Betriebsausgabe/
  Fixkosten/Subscription), **Sparte** (privat/betrieblich) und **Monat**; „+", „Vormonat duplizieren"
  (nur Wiederkehrendes), Beleg-Drop/OCR. Rechts wahlweise der Eintrags-Editor oder eine
  **Vorlagen-Sidebar** (`Vorlage`: Bezeichnung/Anbieter/Betrag/Steuerart/betrieblich/`art`; **kein**
  Datum/Gültigkeit/aktiv) zum **Einfügen** in den gewählten Monat. (Frühere getrennte Module
  „Betriebsausgaben" + „Fixkosten & Subscriptions" sind hier vereint.)
  Es gibt **kein** `gueltigVon`/`gueltigBis`/`aktiv`/`istSubscription`/Versionierung und **keine
  Materialisierung/„erwartet"** mehr. **EÜR/USt** zählen die betrieblichen Buchungen (wie alle
  `ExpenseEntry`, Zuflussprinzip); **private** Buchungen speisen nur die Liquidität (`frei`,
  `Array<ExpenseEntry>.wiederkehrendBrutto(jahr:monat:betrieblich:)`), nie EÜR/USt/ESt.
  Die früheren Alt-Modelle `FixedCost`/`RecurringRule` (samt `ExpenseEntry.rule`) und das
  funktionslose `ExpenseEntry.status`/`ExpenseStatus` sind **vollständig entfernt** (per
  SwiftData-Lightweight-Migration gegen eine Kopie des Produktiv-Stores verifiziert). Die
  einmaligen Migrationen `MonatskostenMigration`/`AusgabenReklassifizierung` (Obsidian-/SubTotal-
  Umzug abgeschlossen) sind ebenfalls weg.
- **VSt je Ausgabe:** `reverseCharge`/`steuerfrei` → 0; `inland19` → `brutto − brutto/1.19`,
  `inland7` → `brutto − brutto/1.07`. `netto = brutto − vst`. Ausgabenseitig ist der Satz nur ein
  **Eingabe-Helfer** für die Vorsteuer (KZ 66 summiert satzunabhängig, EÜR nutzt Netto) – deshalb
  **kein** Mischbeleg-/Bucket-Modell wie bei Einnahmen; ein Mischbeleg wird über die tatsächliche VSt
  erfasst (Feld editierbar). `Steuerart.ziehtVorsteuer` = beide Inland-Sätze (steuert das „aus Brutto"-Feld).
- **Reverse-Charge (§13b, Auslands-Tools):** USt 19 % in **KZ 84 (netto) / KZ 85 (USt)**,
  zugleich als Vorsteuer abziehbar → USt-Saldo 0. **Aber:** der Netto-Betrag bleibt eine
  abziehbare Betriebsausgabe in der EÜR (z. B. Figma 35 € = echte Ausgabe).
- **KSK & ESt = Monatswerte (im Monatsabschluss gepflegt, erben vom Vormonat):** KSK je Monat als
  **drei Beträge KV/RV/PV** (Bescheid-Reihenfolge RV, KV, PV) `YearSettings.kskRVProMonat/kskKVProMonat/
  kskPVProMonat`, `ksk(monat:)` = Summe. **JAE (`kskJAEProMonat`) nur informativ – keine
  Berechnungsgrundlage.** Jeder Zweig (und JAE) **erbt einzeln** vom Vormonat. ESt-Satz je Monat
  (`estSatzProMonat`). Keine globale Einstellung, **keine `KSKEntry`-Sätze-Tabelle/KSK-Modul mehr**.
  Bearbeitung im Monatsabschluss-Sidebar-Tab „Werte" (JAE-Info + drei Betragsfelder, Summe automatisch).
- **EÜR-Gewinn (Jahr)** = Σ `Income.rnNetto` mit *Zahlungsdatum* im Jahr
  − Σ betriebliche `ExpenseEntry.netto` im Jahr.
- **ESt-Rücklage – ENTSCHIEDEN:** **ausschließlich pauschal `(Gewinn − KSK) × Satz`**, Basis =
  **betrieblicher Gewinn** (RN − betriebliche Ausgaben netto); KSK ist als Vorsorgeaufwand
  (Sonderausgabe) abziehbar – beim KSK-Versicherten praktisch in voller Höhe (RV bis weit unter
  dem Altersvorsorge-Höchstbetrag; Basis-KV/PV ohne wirksamen Deckel). Bewusst grobe, eher
  konservative Rücklage (kein exakter §32a-Tarif). Satz **effektiv-datiert** (19 % Jan 2026,
  **ab Feb 2026 15 %**), je Monat überschreibbar/vererbt (`estSatzProMonat`).
  Der frühere **§32a-Tarifschätzer ist entfernt**
  (`EStReserveModus`, `Tarifzone`, `estReserveModus`/`tarifZonen`/`grundfreibetrag`): die
  Monats-Hochrechnung (`monatsGewinn × 12`) war bei unterjährigem/unregelmäßigem Datenstand
  unzuverlässig – §32a-Progression braucht das ganze Jahres-zvE. Pauschal ist der einzige Modus.
- **Steuerrücklage (Monat)** = `(USt − VSt) + KSK + ESt-Anteil`. „Gehalt"/Liquidität
  separat = Σ private wiederkehrende Buchungen (`ExpenseEntry.wiederkehrendBrutto(...betrieblich:false)`).
- **Forderungsausfall** (`InvoiceStatus.ausgefallen`): USt-Korrektur **§17 UStG** im
  Quartal des Ausfalls.

## Datenquellen & Verifikation (für Tests)
Die Unit-Tests prüfen die **Formeln** der Engine gegen **synthetische Fixtures** (durchgängige
Demo-Persona – UI/UX-Designerin in Berlin, KSK/EÜR/Soll; siehe `Demodaten` und die Tests).
**Keine echten Personen-/Finanzdaten im Repo** – so bleibt der Code Open-Source-tauglich.

Prüfgrößen (synthetisch, exemplarisch):
- **UStVA Q1:** Vorsteuer Inland (KZ66), RC-Netto (KZ84), RC-USt (KZ85), Zahllast (KZ83) –
  inkl. eines Vorsteuer-Überhangs (Hardware-Anschaffung) und mehrerer Rundungsfälle.
- **EÜR:** Zufluss-Gewinn = Σ bezahlter Netto-Einnahmen − Σ betrieblicher Netto-Ausgaben im Jahr.
- **Monatsrücklage/Verfügbar, ESt pauschal, §17-Forderungsausfall, USt-VZ-Zuordnung** je mit
  eigenen, leicht nachrechenbaren Beispielwerten.
- **KSK je Monat als KV/RV/PV** (Bescheid-Reihenfolge RV/KV/PV), Summe = Monatsbeitrag;
  JAE nur informativ.

> Hinweis: Der Betreiber kann die Engine zusätzlich **lokal** gegen seine Echtdaten abgleichen –
> diese Werte liegen bewusst **nicht** im Repo.

## Weitere Architektur-Hinweise
- **Tabellen-UX:** alle Tabellen mit `.inspector()`-Flyout (Live-`@Bindable`,
  kein Sheet), Inline-„+", sortierbaren Headern, Jahr/Monat-Filter (Ausgaben/Einnahmen).
  In-Tabellen-Status-Toggle, „Duplizieren (heute)", „bezahlt → heutiges Datum".
- **Entitäten:** `GroceryEntry` (Lebensmittel, wöchentlich, Budget 50 €),
  `PurchaseEntry` (Bestellungen/Anschaffungen, Budget 80 €); `Income.rechnungsnummer`;
  `ExpenseEntry.umlagefaehig`.
- **Module:** Sidebar-Gruppe „Privat" (Privat-Übersicht, Lebensmittel, Anschaffungen).
- **Monatsabschluss:** Gewinn-Waterfall (echter Gewinn nach betrieblichen UND privaten
  Ausgaben → „Frei verfügbar"), Umlage-Summe, Jahresansicht (Monate vergleichbar),
  Querlinks via `Navigation`-Objekt (`@Observable` in Environment).
- **Einstellungen:** Jahr-Auswahl + Anlegen für Vergangenheit.
- **UStVA:** In-View-Umschalter monatlich/quartalsweise; **Default = `YearSettings.ustvaRhythmus`** des
  gewählten Jahres (manuell weiter umschaltbar). USt-VA ist **pro Jahr** konfigurierbar (Rhythmus +
  Dauerfristverlängerung) – das muss an allen zeitkritischen Stellen greifen (Import-Zuordnung, View-Default).
- **Imports:** Einziger Import ist der **Kontoauszug-Import** (Sparkasse CSV-CAMT V8, siehe unten).
  Die früheren Einmal-Migrations-Importer `SubTotalImport` (`.st`/gzip-SQLite) und `ObsidianImport`
  (`Betriebsausgaben.md`) wurden **entfernt** – die Migration aus Obsidian/SubTotal ist abgeschlossen,
  laufende Daten kommen über den Kontoauszug-Import bzw. die manuelle Erfassung.
- **Tests:** laufen rein in-memory (`isStoredInMemoryOnly`) – fassen den echten Store nie an.
- **Persistenz / NIE den Store löschen:** Der On-Disk-Store ist die produktive Nutzerdatenbank.
  App löscht beim Bauen/Starten nichts. **Den Store NICHT per `rm` löschen** (`~/Library/Containers/
  de.wiredframe.Kontor/...default.store*`) – das wischt die manuell erfassten Daten des Nutzers.
  Schemaänderungen additiv halten (Felder mit Defaults → lightweight migration). **Neu hinzugefügte
  Enum-Felder MÜSSEN optional sein** (`SteuerKind?`): bei Nicht-Optional wird der Default in
  bestehenden Stores nicht materialisiert → `Optional<Any>`-Cast-Crash beim Öffnen. **Kein
  automatischer Seed, kein In-App-Reset.** Einzig beim **leeren Erststart** bietet das Onboarding
  optionale **Demodaten** an (`Demodaten`, fiktive Persona – greift nur einen leeren Store auf).
  Sonst kommen Daten über manuelle Erfassung, den Kontoauszug-Import und den JSON-Backup-Import
  (dedupliziert, ohne Überschreiben) herein. Ein neues `YearSettings` legt der Nutzer bei Bedarf an.

## Architektur & Module
- **Module:** Übersicht (Dashboard, Start) · Monatsabschluss · Kontoauszug · Aufgaben ·
  Ausgaben (Betriebsausgaben + Fixkosten + Subscriptions + Vorsorge + Steuern) · Einnahmen ·
  UStVA · Jahresabschluss · Privat-Übersicht · Lebensmittel · Anschaffungen · Einstellungen.
- **Ausgaben-Ledger = ein gemeinsames Modul für ALLE Abflüsse:** Die `AusgabenView` zeigt
  `ExpenseEntry` **und** `TaxPayment` in **einer** Tabelle über einen Anzeige-Zeilentyp
  (`LedgerZeile`), gefiltert nach **Art** (Betriebsausgabe/Fixkosten/Subscription/**Vorsorge**=KSK/
  **Steuern**=Rest), **Sparte** und **Monat**. **`TaxPayment` bleibt das Datenmodell** (kind/
  Steuerjahr/Fälligkeit, **KSK Soll/Ist**, Import-Matching, Jahresabschluss-Gruppierung **unverändert**);
  Vorsorge/Steuern werden nur **mit angezeigt/bearbeitet** (kein eigenes „Zahlungen"-Modul mehr, `ZahlungInspektor`
  lebt in `AusgabenView`). **Keine „bezahlt"-Spalte** im Ledger (Aufbereitung im Jahresabschluss); negativer
  `betrag` = Erstattung (rot). **Steuern & Vorsorge gehen NICHT in die EÜR.** Gespeist primär aus dem
  Kontoauszug-Import; manuell korrigierbar. KSK: Monats-KSK-Wert = **Soll** (Rücklage), `TaxPayment`(`.ksk`)
  = **Ist**. Der **Zahlungen-Block im Jahresabschluss bleibt read-only** (nach Art gruppiert); Termine
  liegen in **Aufgaben**.
- **Auswertungen = 3 Zeithorizonte** (konsolidiert): **Monatsabschluss** (Monat – inkl. der früheren
  „Steuer & Rücklagen": RN/USt/VSt/KSK/ESt-Kacheln, KSK mit „anpassen"-Link, Fixkosten/Subscriptions-Panel),
  **UStVA** (Quartal), **Jahresabschluss** (Jahr – frühere „Jahresübersicht (EÜR)" + „Steuern & Abgaben":
  EÜR-Gewinn, Steuerlast ESt+USt, KSK-Jahr KV/RV/PV, ESt-Abgleich, Zahlungen/Termine). „Steuer & Rücklagen"
  und „Steuern & Abgaben" gibt es nicht mehr.
- **UStVA formular-getreu (zum Ausfüllen):** `UStVAErgebnis` ist nach den ELSTER-Kennzahlen benannt –
  **KZ 81 = Netto-Bemessungsgrundlage 19 %** (nicht die Steuer!), `ust81` = die daraus errechnete USt 19 %,
  **KZ 86 = Netto-Bemessung 7 %** (ermäßigt), `ust86` = USt 7 % (beide im Formular automatisch), **KZ 66**
  Vorsteuer Inland, **KZ 84/85** §13b Netto/USt (immer 19 %), **KZ 67** = KZ 85 als abziehbare Vorsteuer
  (§13b cash-neutral). `zahllast` (KZ 83) = `ust81 + ust86 + kz85 − kz66 − kz67 + §17`. View gruppiert wie
  das Formular (Umsätze → Vorsteuer → Zahllast) mit KZ-Badge, Klartext-Label, Erklärung je Zeile +
  „Hinweise zum Ausfüllen" (Soll/Reverse-Charge/Steuersätze).
  `Steuer.umsatzNetto(_:satz:in:)` liefert je Satz die Netto-Bemessung (Σ rnNetto mit USt≠0, Soll); die
  USt je Satz wird **ELSTER-konform** als `Netto-Summe × Satz` einmal gerundet (nicht je Beleg vorgerundet).
  **Ausgangsseitig 19 % und 7 % (inkl. Mischrechnungen)** – `Income.satz`/`satz2` (`UStSatz`, optional →
  Migrations-sicher, nil = 19 %) + zweiter Bucket `rnNetto2/ust2`; `Income.postenListe` liefert ein bis zwei
  `EinnahmePosten` je Satz-Bucket, sodass die Engine je Satz getrennt rechnet (KZ 81/86, §17) ohne Sonderfall.
  Steuerfreie Umsätze (USt=0) bleiben aus KZ 81/86; kein 0 %/steuerfreier Ausgang, kein Kleinunternehmer.
- **Aufgaben (eine View, Reminders-Logik):** `MonthlyTask` trägt die Wiederkehrung selbst
  (`intervall` einmalig/monatlich/quartalsweise/**jährlich**, `faelligTag`, `quartalsMonate`; jährlich
  nutzt `quartalsMonate` = ein Monat) – kein separates Vorlagen-Entity/-View mehr. Beim Abhaken erzeugt
  `TaskVorlagen.nachAbschluss` die nächste fällige Instanz (Dedup über Titel+Intervall); Hinzufügen/
  Bearbeiten im Inspektor. Seed legt die Checkliste als wiederkehrende Aufgaben an. **Fälligkeit der
  laufenden Instanz** wird im Inspektor als **Monat&Jahr** (monatlich/jährlich) bzw. **Quartal&Jahr**
  (quartalsweise) gewählt und in `monat` gespeichert; Abhaken schreibt via `nachAbschluss` die nächste
  Instanz fort (Reminders-Stil, je Periode eine Instanz). **Abschluss-Sidebars:** Monatsabschluss zeigt
  rechts die **monatlichen** Aufgaben des gewählten Monats, Jahresabschluss die **jährlichen** des
  gewählten Jahres (klick-freundlich, ganze Zeile hakt ab; Filter über `monat`) – die Aufgaben-Liste
  selbst bleibt unter „Aufgaben".
- **Kontoauszug-Import (Modul „Kontoauszug"):** In-App-Import des Sparkasse-**CSV-CAMT-V8**-Exports
  (ISO-8859-1, `;`-Quotes, dt. Beträge). Der Nutzer ordnet **jede Bankbewegung selbst** zu (Triage),
  KI macht hier nichts mehr. Schichten (alle in `Berechnung/`, rein getestet): `Bankimport` (Parser →
  `Bankbuchung`), `ImportVorschlag` (Vorschlag aus gelernter Regel + Heuristik: eigener Übertrag →
  ignorieren, Eingang → Einnahme, sonst privat), `ImportAnwendung` (erzeugt/aktualisiert `GroceryEntry`/
  `PurchaseEntry`/`ExpenseEntry`, **Steuerzahlung** (`TaxPayment`, Art wählbar, matcht fälligkeitsnächsten
  offenen Termin; **USt-VZ-Zahlung im Fälligkeitsfenster → Vorjahr** via `Steuer.ustVzZuordnung` aus den
  **Vorjahres-`YearSettings`** (Jan ohne / Feb mit Dauerfrist; Q4 bzw. Dez je Rhythmus), Notiz gesetzt,
  Zahldatum bleibt) bzw. matcht
  `Income`-Zahlung; **KSK** bucht eine Ist-`TaxPayment`(kind `.ksk`, Betrag = Abbuchung; Soll bleibt
  der Monatswert); **Steuererstattung** (Finanzamt-Eingang) → **negativer** `TaxPayment` (eigene
  Kategorie `.steuererstattung`; bei gelernter `.steuer`-Regel + Eingang automatisch vorgeschlagen);
  **Erstattung/Gutschrift** (Online-Bestellung) → negative `PurchaseEntry` (mindert Einkäufe, ohne
  Verknüpfung zur Originalbestellung); **Fixkosten/Subscriptions setzen `ExpenseEntry.art` aus der
  Triage** und buchen **auch privat** (private = `betrieblich:false`, `vst:0`, nur Liquidität);
  Betriebsausgaben/betriebliche → EÜR. Auto-VSt via `Steuer.vorsteuerVorschlag`;
  Dubletten-/Einnahmen-Ziel → Button „Überschreiben").
  **Lernen:** `ZuordnungsRegel` (Schlüssel = Gläubiger-ID bzw. normalisierter Händlername → Kategorie/
  betrieblich/Steuerart/Steuer-Art; Upsert beim Buchen, **Skip lernt nicht**; ein kleiner, **nicht-
  personenbezogener** Start-Regel-Satz (verbreitete SaaS-Tools + KSK) wird per `seedeStartRegeln`
  idempotent beim App-Start angelegt; im JSON-Backup enthalten). **Idempotenz:**
  `ImportBuchung` (Dedup über stabilen Bank-Schlüssel → schon Importiertes wird ausgeblendet).
  UI: `ImportView` (Karten-Triage, Sidebar-Gruppe Arbeitsfläche). `ImportKategorie` = Triage-Enum (inkl. `ksk`/`steuer`/`steuererstattung`/`erstattung`). **Re-Triage / erneuter Import:** dieselbe CSV erneut
  laden (CSV nötig). „Erledigte zeigen" ist **immer** verfügbar, sobald Zeilen geladen sind (auch wenn
  *alle* schon importiert sind); pro Zeile „Neu zuordnen" oder Bulk **„Alle erneut zuordnen"** öffnet
  erledigte Buchungen wieder. Erneutes Buchen trifft über `ImportAnwendung.ziel` den bestehenden
  Datensatz (Überschreiben) → **keine Dubletten**. Ein komplett importierter Auszug zeigt die Zeilen
  direkt (Toggle vorausgewählt).
- **KSK & ESt = Monatswert-Modell (KSK-Modul/`KSKEntry`-Sätze-Tabelle ENTFERNT):** KSK & ESt-Satz
  werden **pro Monat im Monatsabschluss** gepflegt (Sidebar-Tab **„Werte"**) und **erben automatisch
  vom Vormonat** (rückwärts; `kskTeile(monat:)`/`estSatz(monat:)`). KSK je Monat als **drei Beträge
  KV/RV/PV** (Bescheid-Reihenfolge RV, KV, PV) `kskRVProMonat/kskKVProMonat/kskPVProMonat`, direkt
  eingetragen, Summe = Monatsbeitrag. **JAE (`kskJAEProMonat`) nur informativ – keine
  Berechnungsgrundlage.** Jeder Zweig (und JAE) **erbt einzeln** vom Vormonat. Jahresabschluss
  „KSK nach Versicherung" = **exakte Summe** der je Monat hinterlegten KV/RV/PV. **Soll/Ist:** der
  Monatswert ist das Soll (Rücklage); die
  tatsächlichen Abbuchungen liegen als `TaxPayment`(`.ksk`) im Zahlungen-Ledger (Kontoauszug-Import
  bucht sie). Es gibt **keine globale KSK-/ESt-Einstellung** mehr (Einstellungen verweisen nur darauf).
- **Monat einfrieren beim Abschließen:** „Monat abschließen" speichert den aktuellen Stand als
  `MonatsSnapshot` (`YearSettings.snapshotProMonat`, JSON je Monat) – der Monat zeigt dann **fixe**
  Zahlen statt Live-Rechnung (egal was an KSK/ESt geändert wird) und der Werte-Editor ist gesperrt.
  „Entsperren" löscht den Snapshot → wieder live & editierbar. Snapshot ist im Backup enthalten.
- **MCP-Server (optional, `Kontor/Server/`):** lokaler MCP für externe KI-Clients (Claude Code), einschaltbar
  unter Einstellungen → „KI-Zugriff (MCP)". `MCPServer` = Transport (`NWListener` Loopback `127.0.0.1:8787`,
  Bearer-Token in der **Keychain** (`Schlusselbund`), Request-Cap + Timeout, konstantzeitiger Token-Vergleich,
  Minimal-HTTP-Parser); `MCPProtokoll` = JSON-RPC-Dispatch
  (`initialize`/`ping`/`tools/*`/`resources/*`); `KontorMCP` = Tools+Resources+Engine-Formatter; `KISicherung` =
  Backup vor dem ersten Schreibzugriff je Session (Ordner „KI-Backups"). Entitlement `network.server` nur
  hierfür. **Tokensparend by design:** 8 grobe Tools (`kontor_uebersicht`/`eur`/`ustva`/`monat` Aggregate +
  `kontor_liste` liest **alle Module** — typ: einnahmen|offene_rechnungen|ausgaben|subscriptions|fixkosten|
  zahlungen|aufgaben|lebensmittel|einkaeufe; `kontor_anlegen`/`kontor_aktualisieren`/`kontor_loeschen`
  **schreiben spiegelbildlich alle Module** mit demselben typ-Vokabular). Ändern/Löschen adressieren über eine
  opake `id` = base64(PersistentIdentifier), die `kontor_liste` nur mit `mit_id=true` mitliefert (Lese-Pfad
  bleibt schlank). Dazu Resources (`kontor://uebersicht`,
  `…/eur/{jahr}`, `…/ustva/{jahr}/{quartal}`, `…/monat/{jahr}/{monat}`); **Antworten = fertige Engine-Zahlen
  (`Steuer`/`Auswertung`) bzw. dichte CSV (`;`-getrennt, Punkt-Dezimal), keine Rohzeilen-Dumps.** Der
  **Kontoabgleich gehört bewusst NICHT ins MCP** (betragsbasiertes Matching war fehleranfällig) – das macht
  der lernende In-App-CSV-Import. Tests: `KontorTests/MCPServerTests.swift`.
- **UI-Stil (bewusst zurückhaltend):** `Stil.swift` (`.karte()`-Elevation, `Panel`),
  `Kennzahl` (große Werte). **Icons neutral grau** (`Kennzahl`, `Kartenzeile`); **Card-Titel ohne Icons**
  (`Panel` rendert nur den Titel – nimmt bewusst kein Symbol/Akzent mehr). Semantische Farbe nur in **Summen-/
  Ergebniszeilen** (`Summenzeile`) und bei roten Negativwerten. Geteilte Card-Zeilen `Kartenzeile`/
  `Summenzeile` (klick-kopierbar) + `AufgabenInspektorListe` in `Komponenten.swift`. Dashboard ohne Hero/
  Schnellzugriff. Plakativer Zwei-Werte-Hero `AbschlussHero` (geteilt, klick-kopierbar) in
  **Monatsabschluss** (`Stil.markenVerlauf` Blau→Violett: Betrieblicher Gewinn / Frei verfügbar) **und**
  **Jahresabschluss** (`Stil.jahresVerlauf` warmes Grasgrün→Tannengrün, in der Gewinn-Hue: Gewinn EÜR /
  Steuerlast) – die abweichende
  Verlauf-Farbe unterscheidet die beiden Abschluss-Screens auf einen Blick (`Stil.heroNegativ` = Rotton
  für negative Hero-Werte).
- **Datenhinweise:** Laufende Rechnungen werden manuell erfasst bzw. über den Kontoauszug-Import
  zugeordnet. KSK-Historie erst ab 2025 hinterlegt (2024 ohne KSK in den Auswertungen).
- **Verifiziert gegen synthetische Fixtures:** UStVA-Kennzahlen (KZ66/84/85/83), EÜR-Gewinn,
  Monatsrücklage und ESt pauschal werden in den Unit-Tests gegen nachrechenbare Demo-Werte
  geprüft (keine Echtdaten im Repo; optionaler lokaler Echtdaten-Abgleich beim Betreiber).
