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

🔘 **Kontor für macOS – 19,99 € (Einmalkauf)** &nbsp;&nbsp; 🔘 *Funktionen ansehen*

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
Nicht „auch Buchhaltung", sondern **deine** Buchhaltung: Soll-Versteuerung, Zuflussprinzip, §13b, §17, KSK, pauschale ESt-Rücklage. Die Logik steckt in einer getesteten Engine – Schritt für Schritt gegen nachrechenbare Werte geprüft.

### 🔒 Bleibt bei dir
**Local-first, offline, Sandbox an.** Deine Umsätze verlassen den Mac nicht. Kein Konto, kein Login, kein Tracking. Backup liegt als Datei in deinem Ordner – nicht in fremder Hand.

### ✨ Fühlt sich leicht an
Native macOS-App in SwiftUI. Schnell, ruhig, aufgeräumt. Inline bearbeiten, ein Klick zum Duplizieren, ein Klick zum Abschluss. Buchhaltung, die sich nicht wie Strafe anfühlt.

> 📸 Drei nebeneinander liegende Cards mit je einem Icon. Reduziert.

---

## 3 · Das Herzstück: Was bleibt wirklich dir?

> 🎯 Die eine Frage, die jeden Freiberufler nachts umtreibt – und die Kontor als Erstes beantwortet.

Auf dem Konto liegen 6.000 €. Aber wie viel davon gehört wirklich **dir**?

Genau das rechnet Kontor – Monat für Monat als **Wasserfall** vom Brutto bis zur einzigen Zahl, die zählt:

```
Umsatz (brutto)
−  Umsatzsteuer-Zahllast
+  Vorsteuer-Erstattung
−  KSK-Beitrag
-  Betriebsausgaben
−  Einkommensteuer-Rücklage
−  private Fixkosten
=  Frei verfügbar
```

Keine Schätzung aus dem Bauch, keine böse Überraschung am Quartalsende. Kontor kennt deine Soll-USt, deine KSK, deinen ESt-Satz und deine Rücklagen – und zeigt dir **schwarz auf weiß, was am Monatsende übrig bleibt.**

> Der Unterschied zwischen *„ich hab Geld auf dem Konto"* und *„ich weiß, was mir gehört."*

> 📸 Der „Frei verfügbar"-Wasserfall im Monatsabschluss – Brutto oben, die grüne Zahl ganz unten.

---

## 4 · Was Kontor besonders macht

> 🎯 Die USP-Galerie. Jeder Block: fettes Versprechen + ein, zwei Sätze. Scanbar.

### Künstlersozialkasse, endlich mitgedacht
KSK je Monat als drei Beträge **KV / RV / PV** (in der Reihenfolge deines Bescheids). Direkt im Monatsabschluss gepflegt und **automatisch vom Vormonat geerbt** – einmal eintragen, gilt fort. Der Monatswert ist die **Soll-Quelle** für Rücklage und Jahres-KSK; die tatsächliche Abbuchung liegt als **Ist** im Zahlungs-Ledger. (JAE nur als Info, keine Rechengröße.)

### UStVA zum Abtippen – formular-getreu nach ELSTER
Keine kryptischen Summen, sondern exakt die Kennzahlen, die im Formular stehen: **KZ 81** (Bemessung), **KZ 66** (Vorsteuer Inland), **KZ 84/85** (§13b), **KZ 67**, **KZ 83** (Zahllast). Mit Klartext-Label und Erklärung je Zeile. Voranmeldung wird Abschreiben.

### Reverse-Charge, das wirklich stimmt
Auslands-Tools (Figma, ChatGPT & Co.) nach §13b: USt in KZ 84/85, zugleich als Vorsteuer abziehbar → **cash-neutral**. Aber der Netto-Betrag bleibt eine echte Betriebsausgabe in der EÜR. Genau so, wie es das Gesetz will – nicht „ungefähr".

### Rücklagen, die du verstehst
ESt-Rücklage **pauschal** `(Gewinn − KSK) × Satz` – bewusst grob und eher konservativ, KSK als Vorsorgeaufwand abgezogen. Der Satz ist **monatlich** justierbar (z. B. ab Februar 15 %), ohne bereits abgeschlossene Monate anzufassen. Du steuerst deine Rücklage agil, statt einmal im Jahr zu erschrecken.

### Forderungsausfall nach §17
Wird eine Rechnung uneinbringlich, korrigiert Kontor die USt **und** löst die ESt-Rücklage auf – im richtigen Monat, abgeschlossene Perioden bleiben unberührt.

### Frag deine Buchhaltung (KI-Zugriff über MCP)
> 🎯 Das „Wow" für die moderne Zielgruppe. Klein halten, aber prominent zeigen.

Kontor bringt einen **lokalen MCP-Server** mit. Schalt ihn ein, verbinde Claude – und frag in normaler Sprache: *„Wie hoch ist mein EÜR-Gewinn 2026?", „Zeig mir alle offenen Rechnungen", „UStVA Q2?".* Lesen über **alle** Module, sparsames Schreiben inklusive – und das alles **nur lokal auf 127.0.0.1**, Token in der Keychain, mit automatischem Backup vor dem ersten Schreibzugriff. Deine KI sieht deine Zahlen, das Internet nie.

> 📸 Split-Screen: links Kontor, rechts ein Chat „Wie hoch ist meine Zahllast für Q1?" → fertige Zahl.

---

## 5 · Alles an Bord

> 🎯 Der Vollständigkeits-Beweis. Als Raster/Akkordeon. Zeigt: das ist kein Prototyp, das ist fertig.

**Auswertungen in drei Zeithorizonten**
- **Monatsabschluss** – Gewinn-Wasserfall, Rücklagenkonto (USt, Vorsteuer, KSK, ESt) inkl. §17-Korrektur; KSK-Beträge und ESt-Satz pro Monat im Tab „Werte"; „Monat abschließen" friert den Stand als Snapshot ein.
- **UStVA** – pro Quartal oder Monat, formular-getreu nach ELSTER.
- **Jahresabschluss (EÜR)** – Einnahmen nach Zufluss, Ausgaben nach Kategorie, Gewinn, Vorsteuer, Steuerlast, KSK-Jahr (KV/RV/PV), ESt-Abgleich.

**Erfassen**
- **Einnahmen** – Ausgangsrechnungen mit Status (offen/bezahlt/ausgefallen), der Zahlungs- und Ausfalldatum automatisch führt.
- **Ausgaben – ein Ledger für *alle* Abflüsse.** Betriebsausgaben, Fixkosten, Subscriptions sowie **Vorsorge (KSK)** und **Steuern** in **einer** Tabelle, gefiltert nach **Art · Sparte · Monat**. Pro Posten brutto/VSt/netto, Steuerart (Inland 19 %, Reverse-Charge §13b, steuerfrei), umlagefähig. Wiederkehrendes als **datierte Buchungen** – rechts wahlweise der Editor oder die **Vorlagen-Sidebar** (Vorlage per Klick in den gewählten Monat buchen) bzw. „Vormonat duplizieren". Privat (nur Liquidität) und betrieblich (EÜR) sauber getrennt.

**Arbeitsfläche**
- **Kontoauszug-Import** – Sparkasse-CSV (CAMT) einlesen, jede Buchung per Karten-Triage zuordnen. Kontor **lernt** Händler & Gläubiger und schlägt beim nächsten Mal vor. Idempotent: kein Doppelimport, jederzeit neu zuordenbar.
- **Aufgaben** – einmalig, monatlich, quartalsweise, jährlich. Reminders-Logik: abgehakt → die nächste Fälligkeit erscheint von selbst.

**Privat**
- **Privat-Übersicht**, **Lebensmittel** & **Anschaffungen** mit optionalen Budgets, sauber getrennt vom Betrieblichen.

**Belege & Sicherheit**
- PDF/Bild per Drag-&-Drop, Inline-Vorschau, **OCR** (Apple Vision) für Belegdaten.
- **Beleg-Export als ZIP** pro Jahr – für Steuerberater oder Betriebsprüfung.
- Tägliches Auto-Backup, Komplett-Backup mit Belegen, JSON-Export/-Import (dedupliziert).

**Sanfter Einstieg**
- Beim ersten Start wählst du: **leer beginnen** oder mit **Demodaten** (fiktive Persona) ausprobieren – risikofrei, jederzeit löschbar.

> 📸 Sidebar-Screenshot mit allen Modulen – zeigt die Breite auf einen Blick.

---

## 6 · Die Feinheiten

> 🎯 Hier verliebt man sich. Lauter kleine Dinge, die zeigen: hier hat jemand mit Liebe gebaut.
> Bewusst als lange, befriedigende Liste – „und es kann auch das noch".

- **Inspector statt Sheet.** Bearbeiten passiert in einem ruhigen Flyout neben der Tabelle, live gebunden – kein Modal, das dich aus dem Kontext reißt.
- **Ein Klick, fertig.** „Duplizieren (heute)", „bezahlt → heutiges Datum", Inline-„+" direkt in der Tabelle.
- **Jede Zahl ist kopierbar.** Klick auf einen Wert legt ihn in die Zwischenablage – fürs ELSTER-Formular oder die Mail an den Berater.
- **Soll und Ist sauber auseinandergehalten.** KSK-Monatswert = Soll, die echte Abbuchung = Ist im Zahlungs-Ledger. Keine stille Vermischung.
- **Datierte Sätze, die Geschichte respektieren.** ESt-Satz ab Februar 15 %? Kein Problem – ältere Monate bleiben, wie sie waren; KSK-Werte erben einzeln vom Vormonat.
- **USt-Vorauszahlung im Januar?** Kontor weiß, dass die zum **Vorjahr** gehört (Fälligkeitsfenster, mit/ohne Dauerfristverlängerung) und ordnet sie automatisch richtig zu.
- **Geteilter Zeitraum.** Wechselst du das Modul, bleibt der gewählte Monat/das Jahr erhalten. Das Dashboard zeigt trotzdem immer „heute".
- **Abschluss-Sidebars.** Der Monatsabschluss zeigt die fälligen Monatsaufgaben, der Jahresabschluss die jährlichen – ganze Zeile klickt ab.
- **Geld ist `Decimal`, nie `Double`.** Cent-genau, keine Rundungsgespenster. Klingt nach Detail, ist Vertrauen.
- **Zurückhaltendes Design.** Neutrale graue Icons, Farbe nur dort, wo sie etwas bedeutet – in Summen und roten Negativwerten. Ruhe statt Ampel-Chaos.
- **Geprüft, nicht gehofft.** Die Berechnungs-Engine läuft gegen nachrechenbare Demo-Werte (synthetische Fixtures) – Soll/Zufluss, §13b-Rundung, §17, Rücklagen. Stimmt, statt „sollte stimmen".

---

## 7 · Für wen Kontor gemacht ist

> 🎯 Selbstselektion. Wer sich hier wiedererkennt, klickt. Wer nicht, ist nicht die Zielgruppe – auch gut.

**Kontor ist für dich, wenn du …**
- als **Freiberufler:in** arbeitest (Designer:in, Entwickler:in, Texter:in, Foto, …),
- deine **EÜR** selbst machst und **quartalsweise UStVA** abgibst,
- **KSK-versichert** bist oder es bald wirst,
- deine Zahlen lieber **auf dem eigenen Gerät** hast als in der Cloud,
- und eine App willst, die *deinen* Fall kann – nicht 90 % von jedermanns Fall.

**Kontor ist (noch) nicht für dich, wenn** du Ist-Versteuerung oder Kleinunternehmer (§19) brauchst, ausgangsseitig 7 % USt verrechnest, oder eine GmbH mit doppelter Buchführung, Lohnabrechnung und Multi-User-Teams führst.

---

## 8 · Technik & Vertrauen

> 🎯 Die rationale Rückversicherung für alle, die emotional schon überzeugt sind. Stichpunkte reichen.

- **100 % lokal.** SwiftUI + SwiftData, native macOS-App. Kein Netzwerk, keine Telemetrie, App-Sandbox aktiv.
- **Deine Daten gehören dir.** Alles liegt im App-Container deines Macs. Backups sind klartextlesbare JSON-Dateien in deinem Ordner.
- **Korrektheit ist getestet.** Die Steuerlogik steckt in reinen, geprüften Berechnungs-Bausteinen – verifiziert gegen nachrechenbare Demo-Werte.
- **Optionaler KI-Zugriff – ebenfalls lokal.** Der MCP-Server lauscht nur auf `127.0.0.1`, ist Token-geschützt (Keychain) und sichert vor dem ersten Schreibzugriff automatisch.
- **Quelltext offen.** Kontor ist source-available auf GitHub (PolyForm Perimeter) – prüf den Code, vertrau nicht nur dem Versprechen.
- **Kein Abo.** Einmalkauf statt Abo-Falle (siehe Preis).

> ⚠️ Pflicht-Disclaimer im Footer: „Kontor ersetzt keine Steuerberatung. Berechnungen sind Schätzungen."

---

## 9 · Preis

> 🎯 Eine klare, faire Entscheidung. Zwei Wege nebeneinander – kaufen oder selbst bauen. Kein Abo, keine Tricks.

> 📸 Zwei gleich große Cards nebeneinander. Links die Standard-Wahl (hervorgehoben), rechts die Advanced-Wahl.

<table>
<tr>
<td width="50%" valign="top">

### 💳 Einmalkauf
# 19,99 €
**einmalig – kein Abo**

Die fertige, signierte & notarisierte App für deinen Mac. Alle Funktionen, keine Cloud, keine Folgekosten.

- Voller Funktionsumfang
- Lokal & offline, App-Sandbox
- Optionaler KI-Zugriff (MCP)

🔘 **Für macOS kaufen – 19,99 €**

</td>
<td width="50%" valign="top">

### 🛠️ Selbst bauen · Spendenbasiert
# Dein Fork
**für Advanced User**

Der Quelltext ist offen. Bau dir mit Xcode oder Claude Code deinen **eigenen, privaten Fork** und schneide Kontor exakt auf dich zu.

- Forken, anpassen, selbst bauen – frei
- Nur für **dich**, kein Weiterverkauf
- Wenn dir Kontor hilft: **freue ich mich über eine Spende** ☕

🔘 *Quellcode auf GitHub* &nbsp; 🔘 *Spenden*

</td>
</tr>
</table>

> Beide Wege sind ausdrücklich erlaubt. Was **nicht** geht: Kontor (oder einen Fork) als Konkurrenzprodukt
> verkaufen – dafür gibt es die Lizenz [PolyForm Perimeter](LICENSE).

---

## 10 · Häufige Fragen

> 🎯 Letzte Einwände abräumen. Echte Fragen, ehrliche Antworten.

**Brauche ich ein Konto oder Internet?**
Nein. Kontor läuft komplett offline. Du brauchst kein Konto, keinen Login.

**Wo liegen meine Daten?**
Ausschließlich auf deinem Mac, im sandboxed App-Container. Backups schreibst du als Datei, wohin du willst.

**Einmalkauf oder Abo?**
Einmalkauf: 19,99 €, fertig. Kein Abo, keine Folgekosten. Wer mag und es kann, baut sich stattdessen einen eigenen Fork und gibt freiwillig eine Spende.

**Kann ich meine Bankumsätze importieren?**
Ja – den CSV-CAMT-Export deiner Sparkasse. Du ordnest jede Buchung selbst zu, Kontor lernt mit und schlägt künftig vor.

**Macht Kontor meine UStVA fertig?**
Es liefert dir alle ELSTER-Kennzahlen formular-getreu zum Übertragen. *(ELSTER-Direktversand: Roadmap.)*

**Und die KI – sieht die meine Daten?**
Nur wenn du den MCP-Server einschaltest, und auch dann nur lokal. Nichts geht ins Internet.

**Darf ich Kontor anpassen / forken?**
Ja, für dich selbst – ausdrücklich erwünscht. Du darfst deinen Fork nur nicht verkaufen oder als konkurrierendes Produkt weitergeben.

**Funktioniert das mit meinem Steuerberater?**
Ja: Beleg-Export als ZIP pro Jahr und JSON-Export für alles Übrige.

---

## 11 · Schluss-CTA

> 🎯 Der eine klare nächste Schritt. Wiederholt das Kernversprechen in einem Satz.

# Deine Zahlen. Dein Mac. Deine Ruhe.

### Kontor macht die Buchhaltung, die Freiberufler wirklich haben – korrekt, lokal, leicht.

🔘 **Für macOS kaufen – 19,99 €** &nbsp;&nbsp; 🔘 *Quellcode auf GitHub*

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
- Kompetenz: „Formular-getreu nach ELSTER." · „Cent-genau mit `Decimal`."
- Leichtigkeit: „Ein Klick zum Abschluss." · „Jede Zahl kopierbar."

**Empfohlene Visuals (Reihenfolge der Seite):**
1. Dashboard (Hero) · 2. „Frei verfügbar"-Wasserfall im Monatsabschluss (Abschnitt 3) ·
3. UStVA-Ansicht mit KZ-Badges · 4. Kontoauszug-Triage · 5. KI-Chat-Split-Screen ·
6. Sidebar mit allen Modulen · 7. Preis-Cards (Einmalkauf / Fork).

**Tonalität:** sachlich-selbstbewusst, kein Hype-Sprech. Kurze Sätze. Deutsche Steuerbegriffe korrekt
verwenden – die Zielgruppe erkennt Halbwissen sofort und Präzision schafft Vertrauen.
