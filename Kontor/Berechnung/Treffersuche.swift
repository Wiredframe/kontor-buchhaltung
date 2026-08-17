import Foundation

// MARK: - Gemeinsames Scoring für Zuordnungen
//
// Vorher entschied eine harte Kaskade mit `first(where:)` auf unsortierten Listen: der erste
// Datensatz, der ein einzelnes Kriterium erfüllte, gewann – auch wenn ein anderer in allen
// übrigen Merkmalen besser passte. Der Anbietername, das stärkste unabhängige Signal, wurde gar
// nicht angesehen.
//
// Hier werden die Signale stattdessen **gewichtet und aufsummiert**, und der Aufrufer bekommt
// eine sortierte Liste samt Begründung. Zwei Regeln bleiben aus der Kaskade erhalten, weil sie
// sich bewährt haben:
//
// 1. **Ohne Betrags- oder Nummernsignal kein Kandidat.** Name und Datum allein reichen nie.
// 2. **Das Datumsfenster ist Ausschluss, nicht nur Abzug.** Sonst fände die monatlich gleiche
//    Miete oder Subscription den Vormonatseintrag, und „Überschreiben" verschöbe eine echte
//    Buchung in den falschen Monat.
//
// Die Asymmetrie dahinter: ein falsches Überschreiben zerstört Daten, ein verpasster Treffer
// legt nur eine löschbare Dublette an. Im Zweifel also lieber kein Vorschlag.
//
// **Die Nummer ist ein starkes Signal, aber kein Freibrief.** Sie darf das enge Datumsfenster
// weiten (eine vorab per PDF erfasste Rechnung wird Wochen später abgebucht), nicht aber beide
// Filter gleichzeitig abschalten. Genau das ging einmal schief: eine Belegerkennung hatte aus
// einer Tabellen-Kopfzeile die Spaltenüberschrift „Kunden-Nr" als Rechnungsnummer gespeichert.
// Der Schlüssel „KUNDENNR" steckt in jedem SEPA-Verwendungszweck, der „Kunden-Nr." schreibt –
// eine Stromabschlags-Lastschrift traf damit eine dreiviertel Jahr alte Rechnung über den
// sechzehnfachen Betrag und überschrieb sie. Daher drei Leitplanken um den Nummerntreffer:
// ein Schlüssel ohne Ziffern ist keine Nummer (`nummernSchluessel`), das geweitete Fenster ist
// endlich (`fensterTageNummer`), und ohne bestätigenden Betrag muss die Größenordnung stimmen
// (`nummerBetragsToleranz`).

/// Punktzahl eines Kandidaten samt der Signale, die dazu geführt haben.
struct Trefferbewertung: Equatable {
    var punkte: Int
    var gruende: [String]
    /// Stützt ein **Betragssignal** den Treffer (exakt oder in Fremdwährungs-Toleranz)? Ein
    /// Treffer allein aus der Rechnungsnummer ist plausibel genug fürs Menü, aber nicht dafür,
    /// ihn ungefragt als Überschreib-Ziel vorzuwählen.
    var betragBestaetigt: Bool = false

    /// Für die Anzeige in der Import-Karte („Rechnungsnummer, Betrag exakt, 2 Tage").
    var begruendung: String { gruende.joined(separator: ", ") }
}

/// Merkmale eines vorhandenen Datensatzes (Ausgabe, Einnahme, Einkauf …), gegen den geprüft wird.
struct Trefferkandidat {
    var betrag: Decimal
    var datum: Date
    var name: String = ""
    var nummer: String?
    /// Originalbetrag einer Fremdwährungsrechnung (0 = keine).
    var fremdBetrag: Decimal = 0
    var fremdwaehrung: String?
    /// Zusatzpunkte des Aufrufers, z. B. „Rechnung noch offen".
    var bonus: Int = 0
    var bonusGrund: String?

    var istFremdwaehrung: Bool { fremdwaehrung != nil && fremdBetrag != 0 }
}

/// Merkmale der Bankbewegung, zu der ein Datensatz gesucht wird (Beträge immer positiv).
struct Treffersuchbild {
    var betrag: Decimal
    var datum: Date
    var name: String = ""
    /// Verwendungszweck – hier wird nach der Rechnungsnummer gesucht.
    var text: String = ""
    /// Aus dem Verwendungszweck gelesener Fremdwährungsbetrag (0 = keiner).
    var fremdBetrag: Decimal = 0
    var fremdwaehrung: String?
}

enum Treffersuche {

    // MARK: Gewichte (bewusst fix und an einer Stelle)

    static let punkteNummer = 60
    static let punkteFremdbetrag = 55
    static let punkteBetragExakt = 40
    static let punkteBetragToleranz = 30  // abzüglich Abweichung, siehe `bewerte`
    static let punkteNameGleich = 25
    static let punkteNameEnthalten = 15
    static let punkteDatumNah = 15  // bis 3 Tage
    static let punkteDatumFenster = 8

    /// Unterhalb dieser Punktzahl wird nichts vorgeschlagen, sondern neu angelegt.
    static let mindestpunkte = 30

    /// Standard-Datumsfenster für Ausgaben (bewusst eng, siehe Kopfkommentar).
    static let fensterTage = 5
    /// Fenster für Fremdwährungs-Einträge: zwischen Rechnung und Abbuchung liegen dort
    /// regelmäßig ein bis zwei Wochen.
    static let fensterTageFremd = 14
    /// Fenster, auf das ein **Nummerntreffer** das enge Fenster weitet. Eine vorab per PDF
    /// erfasste Rechnung wird Wochen bis Monate später abgebucht – aber nie ein Dreivierteljahr.
    /// Vorher hob die Nummer das Fenster **unbegrenzt** auf; das war der Weg, auf dem ein
    /// Zufallstreffer eine Buchung aus einer ganz anderen Periode überschrieb.
    static let fensterTageNummer = 180
    /// Zulässige Betragsabweichung bei Fremdwährung (Kurs plus Auslandsentgelt).
    static let toleranzFremd = dez("0.05")
    /// Wie weit der Betrag höchstens abweichen darf, wenn **nur** die Nummer trifft. Rechnung und
    /// Abbuchung differieren allenfalls um Gebühren oder eine Teilzahlung – ein Sprung um ein
    /// Vielfaches ist kein Zahlungsvorgang, sondern eine Kollision im Verwendungszweck.
    static let nummerBetragsToleranz = dez("0.5")

    // MARK: Bausteine

    /// Wie viele Ziffern ein Nummern-Schlüssel mindestens tragen muss, um als Rechnungsnummer
    /// durchzugehen.
    static let mindestZiffern = 4

    /// Alphanumerisch normalisierter Nummern-Schlüssel; `nil`, wenn er zu unspezifisch ist.
    ///
    /// Reine Ziffernfolgen brauchen 5 Stellen: vierstellige Nummern treffen in einem
    /// Verwendungszweck mit Datum und Betrag praktisch zufällig. Nummern mit Buchstaben sind
    /// spezifisch genug ab 4 Zeichen.
    ///
    /// **Und immer mindestens vier Ziffern.** Eine „Rechnungsnummer" ohne eine einzige Ziffer ist
    /// keine, sondern ein von der Belegerkennung eingefangenes Label – „Kunden-Nr", „Rechnung",
    /// „Invoice No". Als Schlüssel gelesen (`KUNDENNR`) trifft so etwas jeden Verwendungszweck,
    /// der dasselbe Wort führt, und riss damit die beiden Schutzfilter der Bewertung ein.
    static func nummernSchluessel(_ s: String?) -> String? {
        guard let s else { return nil }
        let key = s.uppercased().filter { $0.isLetter || $0.isNumber }
        guard !key.isEmpty, key.filter(\.isNumber).count >= mindestZiffern else { return nil }
        let hatBuchstaben = key.contains(where: \.isLetter)
        return key.count >= (hatBuchstaben ? 4 : 5) ? key : nil
    }

    /// Nummer auf ihre Ziffern normiert; `nil` unterhalb der Mindestlänge (zu unspezifisch).
    /// Gemeinsame Quelle für den Bank-Abgleich und die Beleg-Dubletten-Erkennung, damit beide
    /// dieselbe Vorstellung davon haben, wann zwei Nummern „dieselbe" sind.
    static func zifferSchluessel(_ s: String?, mindestens: Int = 4) -> String? {
        guard let s else { return nil }
        let d = s.filter(\.isNumber)
        return d.count >= mindestens ? d : nil
    }

    /// Trifft die Nummer des Kandidaten im Text (Verwendungszweck)?
    ///
    /// Verglichen wird alphanumerisch normalisiert, damit „RE-2026-0042" auch als
    /// „RE 2026 0042" oder „RE20260042" gefunden wird. Zusätzlich der reine Ziffernvergleich,
    /// weil Banken Trennzeichen und Präfixe gern verschlucken.
    static func nummerTrifft(_ nummer: String?, in text: String) -> Bool {
        guard let key = nummernSchluessel(nummer) else { return false }
        let hay = text.uppercased().filter { $0.isLetter || $0.isNumber }
        if hay.contains(key) { return true }
        let ziffern = key.filter(\.isNumber)
        guard ziffern.count >= 5 else { return false }
        return text.filter(\.isNumber).contains(ziffern)
    }

    /// Namensvergleich über dieselbe Normalisierung wie der Import-Lernschlüssel
    /// („FIGMA/San Francisco/US" und „Figma" sind derselbe Anbieter).
    static func nameSignal(_ a: String, _ b: String) -> (punkte: Int, grund: String)? {
        let x = Bankimport.normalisiere(a)
        let y = Bankimport.normalisiere(b)
        guard !x.isEmpty, !y.isEmpty else { return nil }
        if x == y { return (punkteNameGleich, "Anbieter") }
        if x.contains(y) || y.contains(x) { return (punkteNameEnthalten, "Anbieter ähnlich") }
        return nil
    }

    /// Relative Abweichung zweier Beträge (0…1); `nil`, wenn kein sinnvoller Bezug besteht.
    static func abweichung(_ a: Decimal, _ b: Decimal) -> Decimal? {
        guard b != 0, !a.isNaN, !b.isNaN else { return nil }
        return abs(a - b) / abs(b)
    }

    // MARK: Bewertung

    /// Bewertet einen Kandidaten. `nil` = kommt nicht in Frage.
    ///
    /// `nummerBrauchtBetrag` schaltet die Größenordnungs-Prüfung für den reinen Nummerntreffer.
    /// Sie gehört dorthin, wo ein Treffer den Datensatz **überschreibt** (Ausgaben). Bei
    /// Einnahmen wird nur „bezahlt" gesetzt, nichts zerstört – und eine Anzahlung weicht dort
    /// legitim weit vom Rechnungsbetrag ab.
    static func bewerte(
        _ k: Trefferkandidat, gegen s: Treffersuchbild, fensterTage: Int = fensterTage,
        nummerBrauchtBetrag: Bool = true
    ) -> Trefferbewertung? {
        var punkte = 0
        var gruende: [String] = []

        let nummerTrifft = nummerTrifft(k.nummer, in: s.text)
        if nummerTrifft {
            punkte += punkteNummer
            gruende.append("Rechnungsnummer")
        }

        // Betragssignal: exakt, oder – nur bei Fremdwährung – innerhalb der Toleranz.
        var hatBetragssignal = false
        if k.fremdBetrag != 0, s.fremdBetrag != 0, k.fremdBetrag == s.fremdBetrag,
            k.fremdwaehrung?.uppercased() == s.fremdwaehrung?.uppercased()
        {
            punkte += punkteFremdbetrag
            gruende.append("Betrag in \(s.fremdwaehrung ?? "Fremdwährung") exakt")
            hatBetragssignal = true
        }
        if k.betrag == s.betrag {
            punkte += punkteBetragExakt
            gruende.append("Betrag exakt")
            hatBetragssignal = true
        } else if k.istFremdwaehrung, let ab = abweichung(k.betrag, s.betrag), ab <= toleranzFremd {
            let prozent = (ab * 100).gerundet(1)
            punkte += max(0, punkteBetragToleranz - Int(truncating: (prozent * 2) as NSDecimalNumber))
            gruende.append("Betrag ±\(prozent.beschreibung) %")
            hatBetragssignal = true
        }
        guard hatBetragssignal || nummerTrifft else { return nil }

        // Trägt **nur** die Nummer den Treffer, muss wenigstens die Größenordnung stimmen: sonst
        // zieht eine Ziffern-/Wortkollision im Verwendungszweck eine völlig fremde Rechnung heran.
        if nummerTrifft, !hatBetragssignal, nummerBrauchtBetrag {
            guard let ab = abweichung(k.betrag, s.betrag), ab <= nummerBetragsToleranz else { return nil }
        }

        // Datumsfenster: harter Ausschluss. Die Nummer **weitet** es (Vorab-Erfassung per PDF),
        // hebt es aber nicht auf – unbegrenzt war es der Weg in die falsche Periode.
        let tage = abs(k.datum.timeIntervalSince(s.datum)) / 86_400
        let eigenesFenster = k.istFremdwaehrung ? max(fensterTage, fensterTageFremd) : fensterTage
        let imFenster = tage <= Double(eigenesFenster)
        guard imFenster || (nummerTrifft && tage <= Double(fensterTageNummer)) else { return nil }
        if imFenster {
            let gerundet = Int(tage.rounded())
            punkte += tage <= 3 ? punkteDatumNah : punkteDatumFenster
            gruende.append(gerundet == 0 ? "gleicher Tag" : "\(gerundet) Tage")
        }

        if let name = nameSignal(k.name, s.name) {
            punkte += name.punkte
            gruende.append(name.grund)
        }
        if k.bonus != 0 {
            punkte += k.bonus
            if let grund = k.bonusGrund { gruende.append(grund) }
        }

        guard punkte >= mindestpunkte else { return nil }
        return Trefferbewertung(punkte: punkte, gruende: gruende, betragBestaetigt: hatBetragssignal)
    }

    /// Die besten Kandidaten aus einer Liste, absteigend nach Punkten. Bei Gleichstand gewinnt
    /// der datumsnächste – das macht die Auswahl unabhängig von der Reihenfolge der Liste
    /// (SwiftData liefert sie unsortiert).
    static func beste<T>(
        _ liste: [T], gegen s: Treffersuchbild, fensterTage: Int = fensterTage,
        nummerBrauchtBetrag: Bool = true, maximal: Int = 3, merkmale: (T) -> Trefferkandidat
    ) -> [(kandidat: T, bewertung: Trefferbewertung)] {
        liste
            .compactMap { element -> (T, Trefferkandidat, Trefferbewertung)? in
                let k = merkmale(element)
                guard
                    let b = bewerte(
                        k, gegen: s, fensterTage: fensterTage, nummerBrauchtBetrag: nummerBrauchtBetrag)
                else { return nil }
                return (element, k, b)
            }
            .sorted { links, rechts in
                if links.2.punkte != rechts.2.punkte { return links.2.punkte > rechts.2.punkte }
                return abs(links.1.datum.timeIntervalSince(s.datum))
                    < abs(rechts.1.datum.timeIntervalSince(s.datum))
            }
            .prefix(maximal)
            .map { (kandidat: $0.0, bewertung: $0.2) }
    }
}

extension Decimal {
    /// Kompakte Darstellung ohne Währungszeichen für Begründungstexte („1,2").
    var beschreibung: String {
        formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "de_DE")))
    }

    /// Vier Nachkommastellen – für Umrechnungskurse, wo zwei nicht genügen.
    var beschreibungGenau: String {
        formatted(.number.precision(.fractionLength(2...4)).locale(Locale(identifier: "de_DE")))
    }
}
