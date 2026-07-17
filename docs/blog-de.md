# Kontor, oder: Wie ich eine Buchhaltungs-App baute, ohne selbst eine Zeile Code zu schreiben

*Ein Making-of in Boss-Kämpfen. Ich entscheide als Product Owner, die KI tippt, das Finanzamt schaut zu.*

---

## Prolog: Das Geständnis

Fangen wir mit der unbequemen Wahrheit an, weil sie sonst die ganze Zeit zwischen
den Zeilen mitläuft: **Den Code dieser App habe ich nicht geschrieben.** Ich bin
UI-Designer, kein Swift-Entwickler — den Quelltext von „Kontor", meiner lokalen
Buchhaltungs-App für macOS, hat mein KI-Pair-Programmer getippt: Claude Code, im
Terminal, Schritt für Schritt.

Und jetzt die zweite, genauso wahre Hälfte, damit hier kein schiefes Bild entsteht:
Ich habe mein ganzes Leben mit Software zu tun, ich denke in Systemen, und ich bin
ehrgeizig und pedantisch genug, um die Geduld aufzubringen, ein kleinteiliges Problem
so lange präzise zu beschreiben, bis es lösbar wird. Man könnte mich den Regisseur
des Ganzen nennen — vielleicht. Aber viel genauer trifft es ein anderes Wort:
**Product Owner.** Mir gehörten das *Was* und das *Warum*. Ich habe spezifiziert,
entschieden, geprüft und verantwortet. Die KI hatte die Finger auf der Tastatur; die
Richtung, die Urteile und das Geradestehen lagen bei mir.

Und weil das für manche nach Schummeln klingt: Es war der ehrlichste, lehrreichste
Monat meines Berufslebens. Ich habe mehr über Umsatzsteuer, nebenläufiges Rendern und
die Tücken von Fließkommazahlen gelernt als in zehn Jahren davor — nicht, weil ich es
tippte, sondern weil ich jede einzelne Entscheidung tragen musste.

Das hier ist die Geschichte davon. Sie hat einen Ursprung, ein Herzstück, ein
paar richtig fiese Monster und ein überraschend zähes Finale beim App-Store-Drachen.
Also: Rüstung an.

---

## Kapitel 1: Die gewöhnliche Welt (in der ich mit Mathe-Blöcken buchhielt)

Jahrelang habe ich meine komplette Freelancer-Buchhaltung in **Obsidian** gemacht.
Nicht in einer App, nicht in DATEV, nicht in Excel — in Obsidian, mit
**`math.js`-Codeblöcken**. Für alle, die das nicht kennen: Man schreibt in ein
Notizdokument kleine Rechenformeln, und das Programm zeigt einem das Ergebnis an.
Meine Umsatzsteuer-Voranmeldung war im Grunde ein sehr gut kommentiertes
Notizbuch, das sich selbst ausrechnete.

Und wisst ihr was? **Es war großartig.** Bastelig, charmant, komplett meins. Ich
verstand jede Zahl, weil ich jede Formel selbst hingeschrieben hatte. Aber
irgendwann war es einfach nicht mehr genug. Quartalsabschluss, Jahresabschluss,
Soll-Versteuerung, Reverse-Charge, Künstlersozialkasse, Forderungsausfälle — die
Formeln wurden länger, die Sonderfälle mehr, und mein schönes Notizbuch wurde zu
einem Kartenhaus, bei dem ich vor jedem Umbau die Luft anhielt.

Wichtig für den Rest der Geschichte: Ich stehe mit dieser App nicht allein da. Ich
benutze zwei wunderbare Programme des Entwicklers **Timo Partl** —
**WorkingHours** für die Zeiterfassung und **SubTotal** für die Rechnungen. Die
beiden machen ihren Job seit Jahren tadellos. Was mir fehlte, war das dritte
Werkzeug: der Ort, an dem all das zusammenläuft und sich in einen Monats-,
Quartals- und Jahresabschluss verwandelt. Kontor sollte dieses dritte Werkzeug
werden. Kein Ersatz für Timos Apps — die Ergänzung, die aus zweien ein **Dream
Team** macht.

(Kleiner Beweis, dass das keine nachträgliche Romantik ist: Die allerersten
Versionen von Kontor hatten sogar eigene Einmal-Importer, um meine Alt-Daten aus
Obsidian *und* aus SubTotal zu übernehmen. Als die Migration durch war, sind die
Importer wieder rausgeflogen — sie hatten ihren Zweck erfüllt. Man baut die
Räuberleiter ab, sobald man über der Mauer ist.)

---

## Kapitel 2: Die Spielregeln (die ich der KI in den Vertrag schrieb)

Bevor auch nur eine Zeile Code entstand, haben wir die Weltgesetze festgelegt.
Nicht aus übertriebener Disziplin — eher aus Pedanterie, und die war hier ein Segen.
Denn ich hatte früh gemerkt: Eine KI ist ein unfassbar schneller, unfassbar
fleißiger Praktikant, der **exakt das** tut,
was man sagt — und manchmal auch das, was man *nicht* gesagt, aber gemeint hat, und
dann ist es falsch. Also brauchte es klare Regeln. Ein paar davon:

- **Die Datenbank ist die Wahrheit, nicht die Views.** Alle Rechnerei passiert in
  kleinen, langweiligen, testbaren Bausteinen — nie im bunten Teil, den man sieht.
  (Für Entwickler: Engine in reinen Structs, Views bleiben dumm. Für alle anderen:
  Das Gehirn steckt nicht in der Fassade.)
- **Geld ist immer `Decimal`, niemals `Double`.** Klingt nach Erbsenzählerei, ist
  aber der Unterschied zwischen „19,99 €" und „19,989999998 €". Fließkommazahlen
  lügen bei Geld. Immer.
- Und die wichtigste, die ich fett und in Großbuchstaben in die Projektregeln
  geschrieben habe: **Bei Steuerlogik niemals still annehmen — nachfragen.** Wenn
  die KI nicht sicher war, ob ein Sonderfall so oder so gehört, durfte sie nicht
  raten. Sie musste stehenbleiben und fragen. Diese eine Regel hat mir vermutlich
  drei Boss-Kämpfe erspart (und, Spoiler, das Fehlen genau dieser Haltung an
  anderen Stellen hat mir die übrigen eingebrockt).

So sah unsere Arbeitsteilung aus: Ich spezifizierte ein Verhalten präzise — oder ich
beschrieb hartnäckig ein komisches Gefühl, bis wir es dingfest gemacht hatten —, die
KI baute es, wir bauten und testeten, dann ein sauberer Commit — und weiter. Über **rund 127 solcher Commits in nicht einmal drei Wochen.**

---

## Kapitel 3: Das Herzstück — zwei Kalender für ein und dieselbe Rechnung

Wenn diese App eine Superkraft hat, dann ist es diese, und sie ist so unscheinbar,
dass sie kaum jemand von außen erraten würde. Bereit? Hier kommt sie:

> **Dieselbe Rechnung lebt in zwei verschiedenen Kalendern gleichzeitig.**

Klingt nach Zen-Kalauer, ist aber knallharte deutsche Steuerrealität. Ich versteuere
nach **Soll**, das heißt: Meine Umsatzsteuer wird in dem Moment fällig, in dem ich
die Rechnung *schreibe* — nicht, wenn das Geld kommt. Mein **Gewinn** dagegen zählt
nach dem **Zuflussprinzip**: Der zählt erst, wenn das Geld tatsächlich auf dem Konto
*landet*.

Übersetzt: Schreibe ich eine Rechnung am 20. Dezember, und der Kunde zahlt am
10. Januar, dann fällt die **Umsatzsteuer ins vierte Quartal** (Rechnungsdatum),
aber der **Gewinn ins Folgejahr** (Zahlungsdatum). Eine Rechnung, zwei Perioden,
zwei völlig verschiedene Wirkungen. Wer das in einer App nicht sauber trennt,
rechnet zwangsläufig irgendwo falsch — und merkt es womöglich nie.

Genau das ist im Kern von Kontor eine bewusste architektonische Trennung: Die
Umsatzsteuer-Engine filtert nach Rechnungsdatum, die Gewinn-Engine nach
Zahlungsdatum. Das steht so, in dürren, testbaren Funktionen, in `Steuerrechner.swift`.
Es ist die Entscheidung, auf der alles andere ruht.

Und weil ich schon mal beim Angeben bin — hier wird es für einen Designer erst
richtig absurd: Die App füllt die **Umsatzsteuer-Voranmeldung formulargetreu nach
den echten ELSTER-Kennzahlen** aus. KZ 81 (Netto-Bemessung 19 %), KZ 86 (die 7 %),
KZ 66 (Vorsteuer), KZ 83 (Zahllast) — mit Kennzahl-Badge und Klartext-Erklärung pro
Zeile, damit ich beim Abtippen ins echte Formular nichts verwechsle. Ein
UI-Designer, der eine Engine verantwortet, die auf den Cent genau so rundet wie
ELSTER selbst. Das musste ich zwischendurch laut aussprechen, um es zu glauben.

Zwei Sonderfälle, die mir besonders viel Freude machen, weil sie so schön das
Steuerrecht in Software gießen:

- **Reverse-Charge (§13b), die Zaubertrick-Ausgabe.** Wenn ich ein Tool aus dem
  Ausland kaufe — Figma, sagen wir — schulde *ich* dem deutschen Finanzamt die
  Umsatzsteuer darauf, darf sie mir aber im selben Atemzug als Vorsteuer wieder
  abziehen. Netto passiert also cash-mäßig **null** (KZ 84 und KZ 85 heben sich
  auf). Aber — und das ist der Clou — der Nettobetrag bleibt trotzdem eine echte,
  gewinnmindernde Betriebsausgabe. Die App muss beides gleichzeitig können: die
  Steuer neutralisieren *und* die Ausgabe zählen.
- **Der Forderungsausfall (§17), das traurige Gegenstück.** Zahlt ein Kunde nie,
  hole ich mir die Umsatzsteuer zurück, die ich brav vorgestreckt hatte — im Quartal
  des Ausfalls. Fies dabei: Das ELSTER-Formular hat gar kein Feld für „§17". Die
  Korrektur muss also unsichtbar die Bemessungsgrundlage (KZ 81/86) *mindern*, nicht
  als eigene Zeile auftauchen. Sonst würde die Erstattung beim Übertragen ins echte
  Formular einfach verschwinden. Das haben wir tatsächlich erst falsch gebaut und
  später geradegezogen — dazu kommen wir im Monster-Kapitel.

**Ehrlich zur Herkunft:** Die Steuerregeln habe ich nicht erfunden — die kommen aus
der echten Welt, aus meinem Alltag als KSK-versicherter Freelancer, und ich hatte
sie vorab in einer ausführlichen Spezifikation aufgeschrieben. Was hier neu und
selbst gebaut ist, ist die *Übersetzung* dieser Regeln in eine kleine, stur
getestete Rechenmaschine — geprüft gegen frei erfundene Beispieldaten (eine fiktive
Berliner Designerin namens Lena Brandt, dazu später mehr), damit garantiert keine
echten Finanzdaten im offenen Quellcode landen. Am Ende wachten über all das
**226 grüne Tests.**

---

## Kapitel 4: Der Kontoauszug, der dazulernt (und der Irrweg davor)

Das zweite Signatur-Feature ist der **Kontoauszug-Import** — und seine
Entstehungsgeschichte ist selbst eine kleine Lehrstunde in „was sich gut anhört, ist
noch lange nicht gut".

Der naheliegende Traum war: Ich werfe der KI meinen Kontoauszug hin, sie ordnet
jede Buchung automatisch zu. Wir haben das sogar gebaut — über einen kleinen Server,
der die App für eine externe KI ansprechbar macht. Das Ergebnis war… lehrreich. Das
betragsbasierte Zuordnen riet nämlich fröhlich daneben: Eine Apotheken-Zahlung über
14 € wurde da schon mal zuversichtlich als „neues Handy" verbucht. Nah dran an
komisch, weit weg von brauchbar.

Also: umgedreht. Kontor rät heute **nichts** vollautomatisch. Stattdessen bekomme
ich jede Bankbewegung als **Karte** vorgelegt und entscheide selbst: Einnahme?
Betriebsausgabe? Privat? KSK-Beitrag? Steuerzahlung? Erstattung? Das Entscheidende:
Die App **lernt mit jeder Zuordnung**. Ordne ich „Figma" einmal als betriebliche
Reverse-Charge-Ausgabe ein, merkt sie sich das (pro Händler eine gelernte Regel) und
schlägt es beim nächsten Mal von selbst vor. Nur aktives Buchen lehrt — wer eine
Karte überspringt, bringt der App bewusst nichts bei. Beim erneuten Einlesen
desselben Auszugs entstehen keine Dubletten, weil sich die App jede schon verarbeitete
Zeile merkt.

Ein Detail, das ich mag, weil es die Grenze zwischen „von der Stange" und
„selbst gebaut" so schön zeigt: Die App bringt einen winzigen, **nicht
personenbezogenen** Satz Startregeln mit — verbreitete Werkzeuge, die viele
Freiberufler nutzen. Figma, Anthropic, OpenAI, GitHub, Vercel, Notion landen als
Auslands-SaaS automatisch auf „Reverse-Charge", Adobe (deutsche Umsatzsteuer) auf
„Inland 19 %", die Künstlersozialkasse auf „Vorsorge". Reine Anschubvorschläge, alles
überschreibbar — den Rest lernt die App über *meine* echten Bewegungen selbst.

Und der abwesende Held dieser Geschichte: Das automatische Konto-Matching ist bis
heute **bewusst nicht** wieder eingebaut. Manchmal ist die beste KI-Funktion die,
die man weglässt.

---

## Kapitel 5: Die Monster

Jetzt zum Teil, für den ihr eigentlich gekommen seid. Jede App hat ihre Boss-Kämpfe.
Meine waren selten die, die man erwartet — die richtig gefährlichen Monster sahen nie
gefährlich aus. Sie sahen *richtig* aus.

### Boss 1: Der Formwandler „ und " (der den Build lautlos frisst)

Fangen wir harmlos an. Es gibt in der Typografie schöne, geschwungene
Anführungszeichen — „diese" — und es gibt die geraden, technischen `"`. Für einen
Designer ist der Unterschied eine Frage der Ehre. Für einen Swift-Compiler ist er
eine Frage von Leben und Tod: Umschließt man einen Text im Code mit den *hübschen*
Anführungszeichen statt den geraden, **bricht der Build** — mit einer kryptischen
Fehlermeldung, die einem nichts verrät.

Das Perfide: Diese falschen Zeichen schlichen sich immer wieder ein, oft über
automatische Verbesserungsvorschläge, und im Diff sehen sie **exakt gleich** aus.
Man starrt auf zwei identische Zeilen und eine davon ist Gift. Der Fix war am Ende
kein Code, sondern eine **Waffe gegen das Monster**: ein winziges Prüfskript
(`quote-check.sh`), das vor jedem Commit den ganzen Code nach dem einen typografischen
Zeichen durchsucht, das im Swift-Quelltext *nie* legitim vorkommt. Findet es eines,
schlägt es Alarm, bevor der Compiler es kryptisch tut. Manchmal besiegt man einen
Formwandler nicht, indem man ihn erschlägt, sondern indem man einen Wachhund
aufstellt, der ihn riecht.

*(Augenzwinkern an die Devs: Ja, ein Linter-Regelchen. Aber es hat mehr rote Builds
verhindert als mir lieb ist, es zuzugeben.)*

### Boss 2: Das OCR-Biest (das Belege lesen sollte und dabei fast den Prozess sprengte)

Kontor kann Belege lesen. Ich ziehe eine PDF-Rechnung auf ein Feld, und die App
zieht sich Datum, Betrag, Umsatzsteuer und Anbieter selbst heraus. Die reine
Texterkennung dafür liefert Apple (die Vision-Technologie, on-device, kein
Cloud-Upload — das war mir wichtig). Aber Texterkennung gibt einem nur einen
**Haufen Wörter mit Koordinaten** zurück, keine Bedeutung. „3.145,00" ist für die
Maschine erstmal nur eine Zahl, die irgendwo rechts oben schwebt. Ist das der
Nettobetrag? Die Stundenzahl? Die Rechnungsnummer?

Diesen Teil — aus schwebenden Wortfetzen wieder echte Rechnungsfelder zu machen —
haben wir selbst gebaut, und er war ein Biest mit vielen Köpfen:

- **Rechtsbündige Beträge.** Die Texterkennung liefert „Summe netto" und „3.145,00 €"
  als zwei unabhängige Fetzen in unbestimmter Reihenfolge. Die App muss aus den
  Positionen die echten *Lesezeilen* rekonstruieren — Fetzen auf gleicher Höhe
  gruppieren, links nach rechts sortieren — damit der Betrag wieder neben seinem Wort
  landet.
- **Englische Auslandsrechnungen.** Figma schreibt „June 4, 2025", ich brauche den
  4. Juni. Deutsche Tausenderpunkte, englische Dezimalpunkte, exotische Leerzeichen
  aus PDF-Layouts — alles muss dieselbe Zahl ergeben.
- Und der fieseste Kopf von allen, **der unsichtbare**.

Dieser letzte verdient seinen eigenen Absatz, weil er mein Lieblingsmonster ist. Um
eine PDF-Seite für die Texterkennung vorzubereiten, muss man sie zu einem Bild
rendern. Der ursprüngliche Weg dafür nutzte einen bequemen Standard-Mechanismus von
Apple (`NSImage.lockFocus`) — der aber, und das steht im Kleingedruckten,
**denselben geteilten Zeichentisch des ganzen Programms** benutzt und deshalb nur auf
dem Haupt-Thread erlaubt ist. Kontor rief ihn aber aus dem Hintergrund auf, und die
Stapelverarbeitung ließ **mehrere Belege gleichzeitig** rendern. Bildlich: Zwei
Arbeiter greifen im selben Sekundenbruchteil nach derselben Staffelei — und reißen
sie um. Ein sporadischer, schwer reproduzierbarer Absturz, die schlimmste Sorte.

Der Fix (Commit „PDF-Rendering ohne AppKit — lockFocus lief off-main und parallel"):
Jeder Render-Vorgang bekommt seine **eigene Staffelei** (einen eigenen
Grafik-Kontext, reines CoreGraphics, komplett ohne den geteilten Apparat). Und zum
ersten Mal überhaupt bekam dieser Pfad Tests — einer davon fährt bewusst **acht
Renderings gleichzeitig und abseits des Haupt-Threads**, also genau das Szenario, das
vorher krachte. Das Monster ist nicht nur tot, es liegt in einer Falle, die zuschnappt,
falls es zurückkommt.

### Boss 3: Der Formwandler II — „sieht richtig aus, ist es aber nicht"

Und jetzt der große Endgegner der Mitte, das Monster, vor dem ich bis heute den
meisten Respekt habe: **die plausible falsche Zahl.** Ein Absturz ist ehrlich. Er
schreit. Aber eine Zahl, die einfach nur *falsch* ist und dabei völlig
vertrauenswürdig aussieht — die kann monatelang mit dir am Tisch sitzen.

Am 16. Juli war großer Aufräumtag, und es kam ein ganzes Rudel davon aus den Ecken:

- **Der Gewinn, der zwei verschiedene Wahrheiten hatte.** Meine Kernzahl „Frei
  verfügbar" — was am Monatsende wirklich mir gehört — war an **drei Stellen
  unabhängig** ausgerechnet: im Monatsabschluss, im Dashboard (beide korrekt) und
  tief in der Engine (falsch). Ausgerechnet die falsche Variante nutzte der
  KI-Server. Im geprüften Beispiel meldete er **2.233 €**, der Monatsabschluss aber
  **1.043 €**. Differenz: 1.190 € — exakt der Bruttobetrag einer Betriebsausgabe, die
  die falsche Formel schlicht vergessen hatte (und die Vorsteuer sogar noch
  *dazuaddierte*). Der Fix hat einen Namen, der wie eine Moral klingt: **„Der
  Gewinn-Waterfall hat *eine* Quelle."** Ab da lesen alle drei dieselbe Zahl.
- **Der Parser, der aus 1.332,80 mal eben 133.280 machte.** Der Kontoauszug-Import
  entfernte Punkte bedingungslos als Tausendertrenner. Ein englisch formatierter
  Betrag „1332.80" wurde damit hundertfach zu groß — lautlos, ohne Warnung. Der neue
  Grundsatz: **Der Parser rät nicht mehr, er weist ab und meldet es.** Was nicht
  sauber ins deutsche Format passt, wird zurückgewiesen, statt geraten. Gleiches beim
  Datum: Vorher rollte „32.13.26" klammheimlich auf den 1. Februar 2027 weiter — und
  die Buchung landete im falschen Monat, also in der falschen Umsatzsteuer-Periode.
  Jetzt fliegt so ein Datum raus, der echte Schalttag bleibt gültig.
- **Die Aufgabe, die sich täglich klonte.** Eine vierteljährliche Erinnerung, die
  sich beim Abhaken versehentlich *jeden Tag* neu erzeugte, weil in einem Randfall die
  nächste Fälligkeit auf „morgen" durchfiel statt auf „in drei Monaten". Klingt
  niedlich, wäre im Alltag der reinste Benachrichtigungs-Terror.

Die gemeinsame Moral dieses Bosskampfs — und ehrlich gesagt der ganzen App —
schreibe ich mir über den Schreibtisch: **Der eigentliche Feind ist nicht der
Fehler, der schreit. Es ist die Doppelung, die flüstert.** Jede Zahl braucht genau
*eine* Quelle. Sobald dieselbe Wahrheit an zwei Orten lebt, driften die beiden
irgendwann auseinander — und du glaubst der falschen, weil sie so schön ordentlich
aussieht.

### Boss 4: Der Drache über der Schatzkammer (meine echten Daten)

Der letzte Kampf war der mit dem höchsten Einsatz, denn in dieser Datenbank liegen
**meine echten Finanzdaten**. Kein Demo-Spielzeug. Verliere ich die, verliere ich
Jahre Buchhaltung.

Zwei Drachen bewachten diese Schatzkammer — und beide waren gefährlich, weil sie sich
als hilfreich tarnten:

- **Die Migrations-Falle.** SwiftData, Apples Datenbank-Technik, migriert eine sich
  ändernde Datenstruktur normalerweise brav. Aber bei einer bestimmten Art neuer
  Felder (Aufzählungstypen) crasht die App beim Öffnen der *alten* Datenbank, wenn man
  das Feld nicht als „darf auch leer sein" deklariert. Einmal übersehen — und die App
  startet gar nicht mehr. Diese Lektion steht heute in den Projektregeln und in einem
  eigenen Merkzettel, weil sie so leicht und so teuer zu übersehen ist.
- **Der übereifrige Wächter.** Es gab genau einen Pfad im Code, der die produktive
  Datenbank beiseiteschieben und leer neu starten durfte — als Notfallmaßnahme bei
  kaputter Migration. Das Problem: Er reagierte auf **jeden** Fehler gleich, auch auf
  harmlose, vorübergehende (etwa wenn kurz noch eine andere Instanz die Datei
  sperrte). Ein einziger solcher Moment hätte gereicht, und ich hätte vor einer leeren
  App gestanden. Der Fix: Erst ein zweiter, ruhiger Versuch, bevor überhaupt etwas
  angefasst wird. Und wenn wirklich alles scheitert, wird die alte Datenbank nur
  **verschoben, nie gelöscht** — und die App fällt in einen reinen Merk-Modus, statt
  sich in einer Absturzschleife zu verbeißen. Über allem steht die
  unverhandelbare Projektregel: **Den echten Datenspeicher niemals löschen.**

An dieser Stelle wurde mir am deutlichsten klar, was diese ganze Konstellation
bedeutet. Eine KI baut dir in Minuten eine Notfall-Reparatur — aber *ob* diese
Reparatur bei einem harmlosen Schluckauf gleich die Schatzkammer ausräumt, das musst
**du** wollen oder eben verbieten. Das ist keine Coder-Frage, sondern eine
Product-Owner-Frage — eine Haltungsfrage. Und die konnte mir niemand abnehmen.

---

## Kapitel 6: Der Weg nach draußen (und der Drache, der Apple hieß)

Eine App zu bauen ist das eine. Sie in die Welt zu lassen, das andere — und hier
warteten die zähesten Wendepunkte.

**Zuerst die Grundsatzentscheidung: Kontor ist kostenlos und quelloffen.** Nicht aus
Heiligkeit, sondern aus einer sehr banalen, sehr deutschen Logik: Ich bin
KSK-versichert, und Software gewerblich zu *verkaufen* könnte diesen Status
gefährden. Verschenken darf ich sie. Also verschenke ich sie — unter einer Lizenz,
die das Forken und Anpassen für jeden erlaubt (baut euch mit KI euren eigenen Fork!),
nur den Weiterverkauf nicht. Wer mag, kann freiwillig etwas spenden, ganz ohne
Gegenleistung.

**Der Vertriebsweg** wurde GitHub plus Homebrew. Weil die App bewusst nicht teuer bei
Apple notariell beglaubigt ist, begrüßt macOS jeden ersten Start mit der freundlichen
Unterstellung, ich hätte womöglich Schadsoftware gebaut. Also gehört zu jeder
Anleitung der kleine Gatekeeper-Tanz („Rechtsklick → Öffnen"). Nicht elegant, aber
ehrlich.

Und dann war da der **App-Store-Drache**, und der hatte mehrere Leben. Erster
Anlauf: eingereicht. **Abgelehnt** — gleich zweifach. Einmal, weil die App diesen
optionalen lokalen KI-Server mitbrachte (Apples Regel 2.4.5), einmal, weil meine
freiwillige Spende an Apples verpflichtender In-App-Kauf-Regel für digitale
Trinkgelder scheiterte (3.1.1). Also: **App Store komplett abgesagt**, den ganzen
Store-Kram wieder aus dem Code geworfen. Ende der Geschichte, dachte ich.

War es aber nicht. Drei Tage später kam der Drache zurück, und diesmal habe ich ihn
mit einer schlankeren Klinge geschlagen: eine **eigene, abgespeckte
App-Store-Variante** — ohne KI-Server, ohne Spendenknopf, kostenlos, nur für
Deutschland. Sauber getrennt per Compiler-Schalter, damit die frei verteilte Version
weiter alles kann. Der bürokratische Endgegner-Move dabei: Ich musste nicht einmal
einen neuen Store-Eintrag anlegen, sondern den **alten, bereits abgelehnten Eintrag
wiederherstellen** — ein gut verstecktes Menü ganz unten in den App-Informationen —
damit die bestehenden Nutzerdaten nahtlos im selben Container weiterleben. Eingereicht,
Version 2.0. Warten auf Prüfung.

Bleibt der Wendepunkt, der für diese Geschichte fast zu perfekt ist. Erinnert ihr
euch an mein Geständnis vom Anfang — dass eine KI diesen Code geschrieben hat? An
einem Punkt habe ich die **komplette Git-Historie neu aufgesetzt, um „Claude" als
Mitautor sauber aus jedem einzelnen Commit zu entfernen.** Nicht aus Scham — die
Zusammenarbeit ist ja der Kern dieses ganzen Textes — sondern weil ich wollte, dass
das Repository sauber unter *meinem* Namen steht, als der, der Verantwortung trägt.
Der Ghostwriter, der sich mit der eigenen Hand aus dem Abspann streicht. Wenn das
keine Pointe für eine Heldenreise über Mensch und Maschine ist, weiß ich auch nicht.

---

## Kapitel 7: Was ich mit nach Hause bringe

Am Ende jeder Heldenreise steht das Elixier — die Sache, die man mitbringt. Meine ist
kein Code. Es sind ein paar Wahrheiten, die ich vorher nicht so scharf gesehen habe:

**Der eigentliche Feind ist die Doppelung, nicht der Fehler.** Fast jeder böse Bug in
Kontor kam daher, dass dieselbe Wahrheit an zwei Orten lebte und die beiden
auseinanderdrifteten. Eine Zahl, eine Quelle. Das gilt in Software wie im Leben.

**Klein für *einen* Fall schlägt groß für alle.** Kontor kann keine Bilanzierung,
keine Kleinunternehmerregelung, keine Ist-Versteuerung. Es kann **genau meine
Steuersituation** — und deshalb kann es sie richtig. Ich habe aufgehört, mich dafür
zu entschuldigen.

**„Frag nach" ist die wertvollste Regel im Vertrag mit einer KI.** Überall dort, wo
die Maschine bei Unsicherheit stehenblieb und fragte, wurde es gut. Überall dort, wo
sie plausibel weiterriet — der doppelte Gewinn, der hundertfache Betrag, das
weitergerollte Datum — wurde es ein Boss-Kampf.

Und die ehrlichste Erkenntnis über die ganze Konstellation, weil ihr sie verdient
habt: Die KI hat den Swift-Code getippt, den ich selbst nicht getippt hätte — und
dadurch existiert eine echte, getestete, ausgelieferte macOS-App, deren Steuer-Engine
auf den Cent stimmt. Das ist enorm, und ich werde es nicht kleinreden. Aber die App
ist nicht aus dem Nichts gefallen, und die KI hat mir **nichts** von der Verantwortung
abgenommen. Sie hätte mir bereitwillig drei subtil verschiedene Versionen derselben
Zahl hingeschrieben und alle drei für korrekt gehalten — bis ich, als Product Owner
mit dem pedantischen Blick, das Gefühl hatte: *Das kann nicht stimmen.* Dieses Gefühl
war am Ende mein wertvollstes Werkzeug. Kein Compiler hat es, keine KI hat es. Nur der
Mensch, der die Zahl am Monatsende ans Finanzamt schickt — und dafür geradesteht.

Kontor ist heute mein drittes Werkzeug, neben **WorkingHours** und **SubTotal** von
Timo Partl. Zusammen sind sie mein Dream Team. Und eines davon habe ich selbst
verantwortet — spezifiziert, geformt, geprüft, durchgeboxt. Den Code tippte eine KI;
das Produkt gehört mir. Es stellt sich heraus: Genau das ist auch eine Art, eine App
zu bauen — und vielleicht die, die am meisten mit Haltung zu tun hat.

---

## Steckbrief (für alle, die Zahlen mögen)

- **Was:** Kontor — lokale, offline-first Buchhaltungs-App für macOS, gebaut für
  genau *eine* Steuersituation (Freiberufler, KSK, EÜR, Soll-Versteuerung,
  vierteljährliche UStVA).
- **Wer:** Ulf Schuster — UI-Designer und Product Owner der App. Spezifikation,
  Entscheidungen, Prüfung und Verantwortung von mir; den Swift-Code tippte der
  KI-Pair-Programmer (Claude Code).
- **Wie lange:** ~127 Commits in unter drei Wochen bis Version 2.0, danach der lange
  Distributions-Endkampf.
- **Womit:** SwiftUI + SwiftData, alles lokal, keine Telemetrie. ~12 Oberflächen-
  Module, 10 Datenmodell-Klassen, eine reine Rechen-Engine, **226 grüne Tests.**
- **Fremdteile ehrlich benannt:** Texterkennung von Apple (Vision), Datenbank und
  Oberfläche von Apple (SwiftData/SwiftUI), der KI-Server spricht ein offenes
  Protokoll (MCP). **Selbst gebaut:** die zwei-Kalender-Steuerlogik, die
  ELSTER-Formeln, die Geometrie-Extraktion aus Belegen, der lernende Import.
- **Preis:** kostenlos, quelloffen (source-available), Spenden freiwillig.

> **Kein Steuerberatungs-Ersatz.** Alle Berechnungen sind vereinfachte Schätzungen.
> Kontor ersetzt weder Steuerberater:in noch Steuererklärung — die Zahlen gehören
> vor der Abgabe eigenständig geprüft.

*Danke an Timo Partl für WorkingHours und SubTotal — die zwei Drittel meines Dream
Teams, die ich nicht selbst bauen musste.*
