# Kontor

> **Strukturvorlage für die Landingpage.** Reihenfolge = Lesefluss der Seite (oben plakativ → unten
> detailliert). Blockzitate mit 🎯 nennen das Ziel des Abschnitts, 📸 markieren Visuals/Screenshots,
> 🔘 markieren Call-to-Action-Buttons. Copy ist als Entwurf gedacht – kürzbar, schärfbar, deins.

---

## 0 · Hero

> 🎯 In 3 Sekunden klar machen: *Was ist das, für wen, und warum anders.* Ein Versprechen, kein Feature.

# Buchhaltung, die rechnet wie dein Steuerberater – und schweigt wie ein Tresor.

### Kontor ist die Buchhaltungs-App für Freiberufler, die Steuern ernst nimmt und die Cloud verweigert.
EÜR, Umsatzsteuer-Voranmeldung, KSK, Rücklagen – alles korrekt, alles lokal auf deinem Mac. Keine Server, keine Abos, keine Datenreise.

🔘 **Kontor für macOS laden** &nbsp;&nbsp; 🔘 *Funktionen ansehen*

> 📸 Hero-Shot: Dashboard mit Gewinn-Trend, dezent, viel Weißraum. Macht Lust, nicht Angst.

---

## 1 · Der Schmerz

> 🎯 Den Nerv treffen, bevor wir verkaufen. Der Leser soll denken „genau das nervt mich".

**Tabellenkalkulation am Quartalsende. Steuer-Tools, die alles können – nur nicht *deinen* Fall. Cloud-Dienste, die deine Umsätze auf fremden Servern parken.**

Wenn du Freiberufler bist, KSK-versichert, deine EÜR selber machst und quartalsweise eine UStVA abgibst, dann kennst du das:

- Die USt richtet sich nach dem **Rechnungsdatum**, dein Gewinn nach dem **Zahlungseingang** – dieselbe Rechnung, zwei Wahrheiten. Kein Tool denkt das mit.
- **Reverse-Charge**, **Forderungsausfall**, **KSK-Beitrag**, **ESt-Rücklage** – lauter Sonderfälle, die Standard-Software entweder ignoriert oder hinter 200 Buchungskonten versteckt.
- Und am Ende tippst du die Zahlen doch wieder von Hand ins ELSTER-Formular.

> Kontor ist für den einen Menschen gebaut, den die großen Tools vergessen: **dich.**

---

## 2 · Die drei Versprechen

> 🎯 Die komplette Positionierung auf drei Karten. Jede Karte = ein Grund zu bleiben.

### 🧮 Rechnet steuerlich richtig
Nicht „auch Buchhaltung", sondern **deine** Buchhaltung: Soll-Versteuerung, Zuflussprinzip, §13b, §17, §32a, KSK. Die Logik ist in eine getestete Engine gegossen – geprüft gegen echte Vorjahreswerte.

### 🔒 Bleibt bei dir
**Local-first, offline, Sandbox an.** Deine Umsätze verlassen den Mac nicht. Kein Konto, kein Login, kein Tracking. Backup liegt als Datei in deinem Ordner – nicht in fremder Hand.

### ✨ Fühlt sich leicht an
Native macOS-App in SwiftUI. Schnell, ruhig, aufgeräumt. Inline bearbeiten, ein Klick zum Duplizieren, ein Klick zum Abschluss. Buchhaltung, die sich nicht wie Strafe anfühlt.

> 📸 Drei nebeneinander liegende Cards mit je einem Icon. Reduziert.

---

## 3 · Das Herzstück: zwei Kalender, eine Wahrheit

> 🎯 Das *eine* Feature, das Kontor von allem abhebt – ausführlich, weil es das Vertrauen begründet.

Die meisten Tools führen **ein** Datum pro Rechnung. Das ist der Geburtsfehler.

Kontor trennt sauber, was das Finanzamt trennt:

| | maßgebliches Datum | wofür |
|---|---|---|
| **Umsatzsteuer / UStVA** | Rechnungsdatum (**Soll**) | wann die USt entsteht |
| **Gewinn / Einkommensteuer (EÜR)** | Zahlungsdatum (**Zufluss**) | wann das Geld wirklich da ist |

**Dieselbe Rechnung wirkt in unterschiedlichen Perioden** – im Februar in der UStVA, im April im Gewinn, wenn der Kunde zahlt. Kontor hält beide Sichten gleichzeitig korrekt. Du musst nie wählen, welche Wahrheit gerade gilt.

> Das ist kein Schalter in den Einstellungen. Das ist das Fundament.

---

## 4 · Was Kontor besonders macht

> 🎯 Die USP-Galerie. Jeder Block: fettes Versprechen + ein, zwei Sätze. Scanbar.

### Künstlersozialkasse, endlich mitgedacht
KSK-Beitragssätze mit Historie (gültig-ab, JAE, KV/RV/PV). Der Beitragssatz ist die **Soll-Quelle** für alle berechneten KSK-Beträge in Monat, Jahr und Rücklage. Du pflegst den Bescheid, Kontor rechnet den Rest.

### UStVA zum Abtippen – formular-getreu nach ELSTER
Keine kryptischen Summen, sondern exakt die Kennzahlen, die im Formular stehen: **KZ 81** (Bemessung), **KZ 66** (Vorsteuer Inland), **KZ 84/85** (§13b), **KZ 67**, **KZ 83** (Zahllast). Mit Klartext-Label und Erklärung je Zeile. Voranmeldung wird Abschreiben.

### Reverse-Charge, das wirklich stimmt
Auslands-Tools (Figma, ChatGPT & Co.) nach §13b: USt in KZ 84/85, zugleich als Vorsteuer abziehbar → **cash-neutral**. Aber der Netto-Betrag bleibt eine echte Betriebsausgabe in der EÜR. Genau so, wie es das Gesetz will – nicht „ungefähr".

### Rücklagen, die du verstehst
ESt-Rücklage pauschal `(RN − KSK) × Satz` **oder** als §32a-Tarifschätzung – umschaltbar. Der Satz ist **monatlich** justierbar, ohne bereits abgeschlossene Monate anzufassen. Du steuerst deine Rücklage agil, statt einmal im Jahr zu erschrecken.

### Forderungsausfall nach §17
Wird eine Rechnung uneinbringlich, korrigiert Kontor die USt **und** löst die ESt-Rücklage auf – im richtigen Monat, abgeschlossene Perioden bleiben unberührt.

### „Frei verfügbar" – die Zahl, die zählt
Der Monatsabschluss rechnet als Wasserfall vom Brutto über Steuerrücklage, KSK, ESt **und** private Fixkosten bis zur einzigen Zahl, die dich nachts beruhigt: **was wirklich dir gehört.**

### Frag deine Buchhaltung (KI-Zugriff über MCP)
> 🎯 Das „Wow" für die moderne Zielgruppe. Klein halten, aber prominent zeigen.

Kontor bringt einen **lokalen MCP-Server** mit. Schalt ihn ein, verbinde Claude – und frag in normaler Sprache: *„Wie hoch ist mein EÜR-Gewinn 2026?", „Zeig mir alle offenen Rechnungen", „UStVA Q2?".* Lesen über **alle** Module, sparsames Schreiben inklusive – und das alles **nur lokal auf 127.0.0.1**, Token-geschützt, mit automatischem Backup vor jedem Schreibzugriff. Deine KI sieht deine Zahlen, das Internet nie.

> 📸 Split-Screen: links Kontor, rechts ein Chat „Wie hoch ist meine Zahllast für Q1?" → fertige Zahl.

---

## 5 · Alles an Bord

> 🎯 Der Vollständigkeits-Beweis. Als Raster/Akkordeon. Zeigt: das ist kein Prototyp, das ist fertig.

**Auswertungen in drei Zeithorizonten**
- **Monatsabschluss** – Gewinn-Rechnung, Rücklagenkonto, Erwartete Ausgaben aus Vorlagen, „Monat abschließen".
- **UStVA** – pro Quartal oder Monat, formular-getreu.
- **Jahresabschluss (EÜR)** – Einnahmen nach Zufluss, Ausgaben nach Kategorie, Gewinn, Vorsteuer, Steuerlast, KSK-Jahr, ESt-Abgleich.

**Stammdaten, die mitdenken**
- **Einnahmen** – Ausgangsrechnungen mit Status (offen/bezahlt/ausgefallen), der das Zahlungsdatum führt.
- **Betriebsausgaben** – brutto/VSt/netto, Steuerart, Kategorie, umlagefähig.
- **Subscriptions & Vorlagen** – wiederkehrende Regeln erzeugen die erwarteten Monatsausgaben.
- **Fixkosten** – privat (Liquidität) und betrieblich (EÜR) getrennt.
- **KSK** – Beitragshistorie, mit Komfort „Gesamtbetrag → KV/RV/PV aufteilen".
- **Zahlungen** – Ledger aller tatsächlichen Zahlungen (Ist), Erstattungen als Negativbetrag.

**Arbeitsfläche**
- **Kontoauszug-Import** – Sparkasse-CSV (CAMT) einlesen, jede Buchung per Karten-Triage zuordnen. Kontor **lernt** Händler & Gläubiger und schlägt beim nächsten Mal vor. Idempotent: kein Doppelimport.
- **Aufgaben** – einmalig, monatlich, quartalsweise, jährlich. Reminders-Logik: abgehakt → die nächste Fälligkeit erscheint von selbst.

**Privat**
- **Lebensmittel** & **Anschaffungen** mit optionalen Budgets, sauber getrennt vom Betrieblichen.

**Belege & Sicherheit**
- PDF/Bild per Drag-&-Drop, Inline-Vorschau, **OCR** (Vision) für Belegdaten.
- **Beleg-Export als ZIP** pro Jahr – für Steuerberater oder Betriebsprüfung.
- Tägliches Auto-Backup, Komplett-Backup mit Belegen, JSON-Export/-Import (dedupliziert).

> 📸 Sidebar-Screenshot mit allen Modulen – zeigt die Breite auf einen Blick.

---

## 6 · Die Feinheiten

> 🎯 Hier verliebt man sich. Lauter kleine Dinge, die zeigen: hier hat jemand mit Liebe gebaut.
> Bewusst als lange, befriedigende Liste – „und es kann auch das noch".

- **Inspector statt Sheet.** Bearbeiten passiert in einem ruhigen Flyout neben der Tabelle, live gebunden – kein Modal, das dich aus dem Kontext reißt.
- **Ein Klick, fertig.** „Duplizieren (heute)", „bezahlt → heutiges Datum", Inline-„+" direkt in der Tabelle.
- **Jede Zahl ist kopierbar.** Klick auf einen Wert legt ihn in die Zwischenablage – fürs ELSTER-Formular oder die Mail an den Berater.
- **Soll und Ist sauseinandergehalten.** KSK-Beitragssatz = Soll, die echte Abbuchung = Ist im Zahlungs-Ledger. Keine stille Vermischung.
- **„Keine Buchung ohne Beleg."** Das Zahlungs-Ledger ist reines Ist und wird primär aus dem Kontoauszug gespeist.
- **Datierte Sätze, die Geschichte respektieren.** ESt-Satz ab Februar 15 %? Kein Problem – ältere Monate bleiben, wie sie waren.
- **USt-Vorauszahlung im Januar?** Kontor weiß, dass die zum **Vorjahr** gehört (Fälligkeitsfenster, mit/ohne Dauerfristverlängerung) und ordnet sie automatisch richtig zu.
- **Geteilter Zeitraum.** Wechselst du das Modul, bleibt der gewählte Monat/das Jahr erhalten. Das Dashboard zeigt trotzdem immer „heute".
- **Abschluss-Sidebars.** Der Monatsabschluss zeigt die fälligen Monatsaufgaben, der Jahresabschluss die jährlichen – ganze Zeile klickt ab.
- **Geld ist `Decimal`, nie `Double`.** Cent-genau, keine Rundungsgespenster. Klingt nach Detail, ist Vertrauen.
- **Zurückhaltendes Design.** Neutrale graue Icons, Farbe nur dort, wo sie etwas bedeutet – in Summen und roten Negativwerten. Ruhe statt Ampel-Chaos.
- **Geprüft gegen echte Zahlen.** Die Berechnungs-Engine läuft gegen Golden-Werte aus realen Vorjahren – nicht „sollte stimmen", sondern *stimmt*.

---

## 7 · Für wen Kontor gemacht ist

> 🎯 Selbstselektion. Wer sich hier wiedererkennt, klickt. Wer nicht, ist nicht die Zielgruppe – auch gut.

**Kontor ist für dich, wenn du …**
- als **Freiberufler:in** arbeitest (Designer:in, Entwickler:in, Texter:in, Foto, …),
- deine **EÜR** selbst machst und **quartalsweise UStVA** abgibst,
- **KSK-versichert** bist oder es bald wirst,
- deine Zahlen lieber **auf dem eigenen Gerät** hast als in der Cloud,
- und eine App willst, die *deinen* Fall kann – nicht 90 % von jedermanns Fall.

**Kontor ist (noch) nicht für dich, wenn** du eine GmbH mit doppelter Buchführung, Lohnabrechnung für Angestellte oder Multi-User-Teams brauchst.

---

## 8 · Technik & Vertrauen

> 🎯 Die rationale Rückversicherung für alle, die emotional schon überzeugt sind. Stichpunkte reichen.

- **100 % lokal.** SwiftUI + SwiftData, native macOS-App. Kein Netzwerk, keine Telemetrie, App-Sandbox aktiv.
- **Deine Daten gehören dir.** Alles liegt im App-Container deines Macs. Backups sind klartextlesbare JSON-Dateien in deinem Ordner.
- **Korrektheit ist getestet.** Die Steuerlogik steckt in reinen, geprüften Berechnungs-Bausteinen – verifiziert gegen echte Vorjahreswerte.
- **Optionaler KI-Zugriff – ebenfalls lokal.** Der MCP-Server lauscht nur auf `127.0.0.1`, ist Token-geschützt und sichert vor jedem Schreibzugriff automatisch.
- **Keine Abo-Falle.** *(Modell hier einsetzen: Einmalkauf / faire Lizenz – Entscheidung offen.)*

> ⚠️ Pflicht-Disclaimer im Footer: „Kontor ersetzt keine Steuerberatung. Berechnungen sind Schätzungen."

---

## 9 · Häufige Fragen

> 🎯 Letzte Einwände abräumen. Echte Fragen, ehrliche Antworten.

**Brauche ich ein Konto oder Internet?**
Nein. Kontor läuft komplett offline. Du brauchst kein Konto, keinen Login.

**Wo liegen meine Daten?**
Ausschließlich auf deinem Mac, im sandboxed App-Container. Backups schreibst du als Datei, wohin du willst.

**Kann ich meine Bankumsätze importieren?**
Ja – den CSV-CAMT-Export deiner Sparkasse. Du ordnest jede Buchung selbst zu, Kontor lernt mit und schlägt künftig vor.

**Macht Kontor meine UStVA fertig?**
Es liefert dir alle ELSTER-Kennzahlen formular-getreu zum Übertragen. *(ELSTER-Direktversand: Roadmap.)*

**Und die KI – sieht die meine Daten?**
Nur wenn du den MCP-Server einschaltest, und auch dann nur lokal. Nichts geht ins Internet.

**Funktioniert das mit meinem Steuerberater?**
Ja: Beleg-Export als ZIP pro Jahr und JSON-Export für alles Übrige.

---

## 10 · Schluss-CTA

> 🎯 Der eine klare nächste Schritt. Wiederholt das Kernversprechen in einem Satz.

# Deine Zahlen. Dein Mac. Deine Ruhe.

### Kontor macht die Buchhaltung, die Freiberufler wirklich haben – korrekt, lokal, leicht.

🔘 **Jetzt für macOS laden** &nbsp;&nbsp; 🔘 *Alle Funktionen im Detail*

---

> 📑 **Footer:** Impressum · Datenschutz · Systemvoraussetzungen (macOS 15+) · „Kontor ersetzt keine
> Steuerberatung." · © Wiredframe

---

## Anhang · Bausteine für die Umsetzung (nicht für die Seite)

> 🎯 Werkzeugkasten beim Bauen – Headlines, Microcopy, Bildideen.

**Alternative Headlines (Hero, A/B-Testing):**
- „Die Buchhaltung, die deinen Steuerfall kennt."
- „EÜR, UStVA, KSK – richtig gerechnet, lokal gespeichert."
- „Buchhaltung für einen. Gemacht für dich."
- „Endlich eine Buchhaltung, die Soll und Zufluss auseinanderhält."

**Microcopy-Bausteine:**
- Vertrauen: „Bleibt auf deinem Mac." · „Kein Konto. Kein Abo. Keine Cloud."
- Kompetenz: „Formular-getreu nach ELSTER." · „Geprüft gegen echte Vorjahreswerte."
- Leichtigkeit: „Ein Klick zum Abschluss." · „Jede Zahl kopierbar."

**Empfohlene Visuals (Reihenfolge der Seite):**
1. Dashboard (Hero) · 2. Die Zwei-Kalender-Tabelle (Abschnitt 3) · 3. UStVA-Ansicht mit KZ-Badges ·
4. Monatsabschluss-Wasserfall „Frei verfügbar" · 5. Kontoauszug-Triage · 6. KI-Chat-Split-Screen ·
7. Sidebar mit allen Modulen.

**Tonalität:** sachlich-selbstbewusst, kein Hype-Sprech. Kurze Sätze. Deutsche Steuerbegriffe korrekt
verwenden – die Zielgruppe erkennt Halbwissen sofort und Präzision schafft Vertrauen.
