# Kontor: Wie ich als Product Owner eine Steuer-App shippte (und die KI tippte)

*Die Kurzfassung einer Heldenreise — ein Designer, eine KI und das Finanzamt.*

## Das Geständnis

Den Code habe ich nicht geschrieben. Ich bin UI-Designer, kein Swift-Entwickler — den
Quelltext von „Kontor", meiner lokalen Buchhaltungs-App für macOS, hat mein
KI-Pair-Programmer getippt (Claude Code, im Terminal, Schritt für Schritt). Und
trotzdem gehört diese App mir, denn ich war ihr **Product Owner**. Ich habe mein
ganzes Leben mit Software zu tun, ich denke in Systemen, und ich bin ehrgeizig und
pedantisch genug, um ein Problem so lange präzise zu zerlegen, bis es lösbar wird. Mir
gehörten das *Was* und das *Warum*: Ich habe spezifiziert, entschieden, geprüft und
verantwortet. Die KI hatte die Finger auf der Tastatur; die Urteile lagen bei mir. In
unter drei Wochen und rund 127 Commits wurde daraus eine echte, verschiffte App —
bewacht von 226 grünen Tests.

## Die alte Welt

Jahrelang machte ich meine komplette Buchhaltung in Obsidian, mit `math.js`-Rechen­blöcken.
Charmant, bastelig, komplett meins — bis Quartalsabschluss, Soll-Versteuerung,
Reverse-Charge, Künstlersozialkasse und Forderungsausfälle mein schönes Notizbuch in
ein Kartenhaus verwandelten, bei dem ich vor jedem Umbau die Luft anhielt. Ich benutze
außerdem zwei wunderbare Apps des Entwicklers **Timo Partl** — **WorkingHours** für die
Zeiterfassung und **SubTotal** für die Rechnungen. Was fehlte, war das dritte Werkzeug:
der Ort, an dem alles zum Monats-, Quartals- und Jahresabschluss zusammenläuft. Kontor
wurde es — kein Ersatz für Timos Apps, sondern die Ergänzung, die aus zweien ein Dream
Team macht. (Beweis, dass das keine nachträgliche Romantik ist: Die ersten Versionen
hatten sogar eigene Importer für meine Alt-Daten aus Obsidian *und* SubTotal. Sie
flogen raus, sobald die Migration durch war — man baut die Räuberleiter ab, sobald man
über der Mauer ist.)

## Das Herzstück: zwei Kalender für eine Rechnung

Die unscheinbare Superkraft der App, die kaum jemand von außen erraten würde: Dieselbe
Rechnung lebt in **zwei Kalendern gleichzeitig**. Meine Umsatzsteuer zählt nach **Soll**
— fällig, wenn ich die Rechnung *schreibe*. Mein Gewinn zählt nach dem **Zuflussprinzip**
— erst, wenn das Geld *landet*. Rechnung im Dezember geschrieben, im Januar bezahlt?
Umsatzsteuer ins vierte Quartal, Gewinn ins Folgejahr. Eine Rechnung, zwei Perioden, zwei
Wirkungen. Wer das nicht sauber trennt, rechnet zwangsläufig falsch — und merkt es
womöglich nie.

Und dann füllt die App die Umsatzsteuer-Voranmeldung **formulargetreu nach den echten
ELSTER-Kennzahlen** aus (KZ 81/86 für die Bemessung, KZ 66 Vorsteuer, KZ 83 Zahllast) und
rundet auf den Cent so wie ELSTER selbst. Zwei Sonderfälle machen mir dabei besondere
Freude: **Reverse-Charge (§13b)**, die cash-neutrale Auslandsausgabe — ich schulde dem
Finanzamt die Steuer auf ein US-Tool wie Figma und ziehe sie im selben Atemzug als
Vorsteuer wieder ab; unterm Strich null, aber der Nettobetrag bleibt eine echte,
gewinnmindernde Betriebsausgabe. Und der **Forderungsausfall (§17)**: Zahlt ein Kunde
nie, hole ich mir die vorgestreckte Umsatzsteuer zurück — nur hat das ELSTER-Formular gar
kein Feld dafür, also muss die Korrektur unsichtbar die Bemessungsgrundlage mindern statt
als eigene Zeile aufzutauchen. Ehrlich zur Herkunft: Die Steuerregeln habe ich nicht
erfunden, die kommen aus meinem Alltag als KSK-Freelancer und lagen vorab in einer
ausführlichen Spezifikation. Neu und selbst gebaut ist ihre Übersetzung in eine stur
getestete Rechenmaschine — geprüft gegen eine frei erfundene Demo-Persona (eine fiktive
Berliner Designerin), damit garantiert keine echten Finanzdaten im offenen Quellcode
landen; ein eigener PII-Wächter schlägt Alarm, falls es doch jemand versucht.

## Der Kontoauszug, der dazulernt

Der naheliegende Traum: Ich werfe der KI meinen Kontoauszug hin, sie ordnet alles
automatisch zu. Wir haben es gebaut — und wieder verworfen. Das betragsbasierte Raten
machte aus einer 14-€-Apotheke schon mal zuversichtlich ein „neues Handy". Also
umgedreht: Kontor rät **nichts** vollautomatisch. Ich triagiere jede Bankbewegung selbst
per Karte, und die App **lernt pro Händler** mit — „Figma" einmal als betriebliche
Reverse-Charge-Ausgabe gebucht, und sie schlägt es beim nächsten Mal von selbst vor. Nur
aktives Buchen lehrt; wer überspringt, bringt der App bewusst nichts bei. Ein winziger,
nicht-personenbezogener Satz Startregeln ist dabei (verbreitete Tools: Figma, Anthropic,
OpenAI, GitHub → Reverse-Charge; Adobe mit deutscher Steuer → Inland 19 %). Lädt man
denselben Auszug versehentlich zweimal, entstehen keine Dubletten — die App merkt sich
jede schon verarbeitete Zeile. Und der abwesende Held: Das automatische Konto-Matching
ist bis heute bewusst *nicht* wieder eingebaut. Manchmal ist die beste KI-Funktion die, die man weglässt.

## Die Monster

Meine Boss-Kämpfe sahen selten gefährlich aus. Die gefährlichen sahen *richtig* aus.

**Die typografischen Anführungszeichen.** Die hübschen, geschwungenen „…" statt der
geraden `"` als Textbegrenzer im Code — und der Swift-Build bricht, mit kryptischem
Fehler. Im Diff sehen beide identisch aus; man starrt auf zwei gleiche Zeilen, eine ist
Gift. Der Fix war kein Code, sondern ein Wachhund: ein winziges Skript, das vor jedem
Commit nach dem einen Zeichen sucht, das im Swift-Code *nie* legitim vorkommt.

**Das OCR-Biest.** Kontor liest Belege. Die Texterkennung liefert Apple (on-device, kein
Cloud-Upload) — aber aus einem Haufen schwebender Wortfetzen wieder „das ist der
Nettobetrag" zu machen, war Handarbeit: rechtsbündige Beträge den Labels zuordnen,
englische Datumsformate (Figmas „June 4, 2025"), deutsche Tausenderpunkte. Der fieseste
Kopf war unsichtbar: Das Rendern der PDF-Seiten lief über einen geteilten Zeichenapparat
des Systems, der nur auf dem Haupt-Thread erlaubt ist — Kontor rief ihn aber aus dem
Hintergrund, und die Stapelverarbeitung ließ mehrere Belege *gleichzeitig* rendern. Zwei
Arbeiter, eine Staffelei, Umsturz — ein sporadischer, schwer reproduzierbarer Absturz.
Fix: Jeder Render-Vorgang bekommt seine eigene Staffelei; ein neuer Test fährt bewusst
acht Renderings parallel und abseits des Haupt-Threads.

**„Sieht richtig aus, ist es aber nicht."** Mein gefürchtetstes Monster: die plausible
falsche Zahl. Meine Kernzahl „Frei verfügbar" war an drei Stellen unabhängig
ausgerechnet — und die falsche Variante nutzte ausgerechnet der KI-Server. Er meldete
**2.233 €**, der Monatsabschluss **1.043 €**; die Differenz von 1.190 € war exakt eine
Betriebsausgabe, die die falsche Formel schlicht vergessen hatte. Der Fix hat einen
Namen wie eine Moral: „Der Gewinn-Waterfall hat *eine* Quelle." Dazu ein Import-Parser,
der aus englischem „1332.80" lautlos 133.280 machte, und eine vierteljährliche Aufgabe,
die sich beim Abhaken *täglich* neu klonte. Die Lehre über allem: Der Feind ist nicht der
Fehler, der schreit, sondern die Doppelung, die flüstert. Jede Zahl braucht genau eine
Quelle.

**Der Daten-Drache.** In dieser Datenbank liegen meine *echten* Finanzdaten. Ein
übereifriger Notfall-Pfad hätte sie bei jedem harmlosen Schluckauf — einer kurz
gesperrten Datei etwa — beiseitegeschoben und die App leer neu gestartet. Der Fix: erst
ein zweiter, ruhiger Versuch; und wenn wirklich alles scheitert, wird die alte Datenbank
nur **verschoben, nie gelöscht**. Ob eine in Minuten von der KI gebaute Notfall-Reparatur
bei einem Schluckauf gleich die Schatzkammer ausräumt — das ist keine Coder-Frage,
sondern eine Product-Owner-Frage. Und die konnte mir niemand abnehmen.

## Raus in die Welt

Kontor ist kostenlos und quelloffen — nicht aus Heiligkeit, sondern aus sehr deutscher
Logik: Ich bin KSK-versichert, und Software gewerblich zu *verkaufen* könnte diesen
Status gefährden. Verschenken darf ich sie. Vertrieb über GitHub und Homebrew, samt
kleinem Gatekeeper-Tanz beim ersten Start (bewusst nicht teuer notariell beglaubigt).
Der App-Store-Drache hatte mehrere Leben: eingereicht → **zweifach abgelehnt** (der
optionale lokale KI-Server verstieß gegen Regel 2.4.5, meine freiwillige Spende gegen die
In-App-Kauf-Pflicht 3.1.1) → komplett abgesagt → drei Tage später als schlanke, KI-server-
und spendenlose Nur-Deutschland-Variante wieder eingereicht, mit wiederhergestelltem
Alt-Eintrag, damit die Nutzerdaten nahtlos weiterleben. Und die Pointe, die für diese
Geschichte fast zu perfekt ist: An einem Punkt habe ich die **komplette Git-Historie neu
aufgesetzt, um „Claude" als Mitautor aus jedem einzelnen Commit zu entfernen** — nicht
aus Scham, sondern damit das Repository sauber unter *meinem* Namen steht, als der, der
die Verantwortung trägt. Der Ghostwriter, der sich mit eigener Hand aus dem Abspann
streicht.

## Was bleibt

Drei Wahrheiten nehme ich mit. **Der eigentliche Feind ist die Doppelung, nicht der
Fehler** — fast jeder böse Bug kam daher, dass dieselbe Wahrheit an zwei Orten lebte und
auseinanderdriftete. **Klein für *einen* Fall schlägt groß für alle** — Kontor kann keine
Bilanzierung und keine Kleinunternehmerregelung, es kann genau meine Steuersituation, und
deshalb kann es sie richtig. Und **„frag nach"** ist die wertvollste Regel im Vertrag mit
einer KI: Wo die Maschine bei Unsicherheit stehenblieb, wurde es gut; wo sie plausibel
weiterriet, wurde es ein Boss-Kampf.

Die ehrlichste Erkenntnis über die ganze Konstellation: Die KI hat den Code getippt, den
ich selbst nicht getippt hätte — enorm, und ich werde es nicht kleinreden. Aber sie hat
mir nichts von der Verantwortung abgenommen. Sie hätte mir bereitwillig drei subtil
verschiedene Versionen derselben Zahl hingeschrieben und alle für korrekt gehalten, bis
ich, als Product Owner mit dem pedantischen Blick, das Gefühl hatte: *Das kann nicht
stimmen.* Dieses Gefühl hat kein Compiler und keine KI — nur der Mensch, der die Zahl am
Monatsende ans Finanzamt schickt. Kontor ist heute mein drittes Werkzeug neben
WorkingHours und SubTotal: mein Dream Team. Eines davon habe ich verantwortet,
spezifiziert, geprüft, durchgeboxt. Den Code tippte eine KI; das Produkt gehört mir. Und
das, stellt sich heraus, ist auch eine Art, eine App zu bauen.

---

*Kein Steuerberatungs-Ersatz — alle Berechnungen sind vereinfachte Schätzungen und gehören
vor der Abgabe eigenständig geprüft. Danke an Timo Partl für WorkingHours und SubTotal, die
zwei Drittel meines Dream Teams, die ich nicht selbst bauen musste.*
