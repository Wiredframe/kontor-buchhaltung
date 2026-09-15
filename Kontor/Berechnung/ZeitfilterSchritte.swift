import Foundation

// MARK: - Periodenschritte

extension Zeitfilter {
    /// Laufende Monatsnummer seit dem Jahr 0 – die Rechengrundlage der Schritte.
    private var monatsindex: Int { jahr * 12 + (monat - 1) }

    private mutating func setzeMonatsindex(_ i: Int) {
        let j = Int((Double(i) / 12).rounded(.down))
        jahr = j
        monat = i - j * 12 + 1
    }

    /// Eine Periode weiter (in der Granularität des aktuellen Modus).
    mutating func vor() { verschiebe(um: 1) }
    /// Eine Periode zurück.
    mutating func zurueck() { verschiebe(um: -1) }

    /// Die Schritte rechnen bewusst in **ganzen Zahlen** statt mit Datumsmathematik: Der
    /// Jahreswechsel ist damit eine Division, und weder Sommerzeit noch Schaltjahre können
    /// hineinfunken. `Periode` baut daraus anschließend den Zeitraum.
    private mutating func verschiebe(um n: Int) {
        switch modus {
        case .alle: break  // Gesamt hat keine Nachbarperiode
        case .jahr: jahr += n
        case .quartal: setzeMonatsindex(monatsindex + n * 3)
        case .monat: setzeMonatsindex(monatsindex + n)
        }
    }

    /// Beschriftung des aktuellen Zeitraums, z. B. „September 2026", „Q3 2026", „2026", „Gesamt".
    var beschriftung: String {
        switch modus {
        case .alle: "Gesamt"
        case .jahr: String(jahr)
        case .quartal: "Q\(quartal) \(String(jahr))"
        case .monat: "\(monatsName(monat)) \(String(jahr))"
        }
    }
}

// MARK: - Schnellwahl

extension Zeitfilter {
    /// `heute` ist injizierbar, damit sich die Presets über den Jahreswechsel testen lassen.
    private static func teile(_ heute: Date) -> (jahr: Int, monat: Int) {
        let k = appKalender.dateComponents([.year, .month], from: heute)
        return (k.year ?? 2000, k.month ?? 1)
    }

    static func dieserMonat(heute: Date = Date()) -> Zeitfilter {
        let t = teile(heute)
        return Zeitfilter(modus: .monat, jahr: t.jahr, monat: t.monat)
    }

    static func letzterMonat(heute: Date = Date()) -> Zeitfilter {
        var f = dieserMonat(heute: heute)
        f.zurueck()
        return f
    }

    static func diesesQuartal(heute: Date = Date()) -> Zeitfilter {
        let t = teile(heute)
        var f = Zeitfilter(modus: .quartal, jahr: t.jahr, monat: t.monat)
        f.quartal = (t.monat - 1) / 3 + 1  // auf den Quartalsanfang rücken
        return f
    }

    static func letztesQuartal(heute: Date = Date()) -> Zeitfilter {
        var f = diesesQuartal(heute: heute)
        f.zurueck()
        return f
    }

    static func diesesJahr(heute: Date = Date()) -> Zeitfilter {
        Zeitfilter(modus: .jahr, jahr: teile(heute).jahr, monat: teile(heute).monat)
    }

    static func letztesJahr(heute: Date = Date()) -> Zeitfilter {
        var f = diesesJahr(heute: heute)
        f.zurueck()
        return f
    }

    static var gesamt: Zeitfilter { Zeitfilter(modus: .alle) }
}

// MARK: - Umfang

extension Zeitfilter {
    /// Welche Granularitäten ein Screen überhaupt anbietet.
    ///
    /// Der Zeitraum ist modulübergreifend geteilt, aber nicht jedes Modul kann mit jeder
    /// Granularität etwas anfangen: Der Monatsabschluss rechnet je Monat oder Jahr, die
    /// Jahresabschluss-Seiten ausschließlich je Jahr. Der `ZeitraumChip` normalisiert den
    /// geteilten Filter beim Erscheinen darauf – sonst behauptet die Kopfzeile einen Zeitraum,
    /// nach dem die Seite gar nicht rechnet.
    /// - `voll`: Monat, Quartal, Jahr, Gesamt (Tabellen)
    /// - `monatJahr`: Monat oder Jahr (Monatsabschluss)
    /// - `monatQuartal`: Monat oder Quartal (UStVA – eine Voranmeldung gilt je Monat oder
    ///   Quartal, ein Jahreszeitraum ergibt dort keinen Sinn)
    /// - `nurJahr`: nur Jahr (Jahresabschluss)
    enum Umfang { case voll, monatJahr, monatQuartal, nurJahr }

    /// Klemmt den Modus in den erlaubten Umfang. Passt er schon, bleibt alles unverändert.
    mutating func begrenzeAuf(_ umfang: Umfang) {
        switch umfang {
        case .voll:
            break
        case .monatJahr:
            // Quartal → dessen erster Monat (`monat` trägt ihn bereits), Gesamt → Jahr.
            if modus == .quartal { modus = .monat }
            if modus == .alle { modus = .jahr }
        case .monatQuartal:
            // Jahr und Gesamt fallen auf den Monat zurueck, der ohnehin gesetzt ist.
            if modus == .jahr || modus == .alle { modus = .monat }
        case .nurJahr:
            if modus != .jahr { modus = .jahr }
        }
    }

    /// Bietet dieser Umfang den Modus an?
    static func erlaubt(_ modus: Modus, in umfang: Umfang) -> Bool {
        switch umfang {
        case .voll: true
        case .monatJahr: modus == .monat || modus == .jahr
        case .monatQuartal: modus == .monat || modus == .quartal
        case .nurJahr: modus == .jahr
        }
    }
}
