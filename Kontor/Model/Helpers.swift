import Foundation

// MARK: - Decimal

/// Decimal exakt aus einem String erzeugen (Punkt als Dezimaltrenner).
///
/// Wichtig: `Decimal(12.99)` ginge über `Double` und wäre ungenau – deshalb
/// für alle Geld-/Tarif-Konstanten immer diese Funktion verwenden.
func dez(_ string: String) -> Decimal {
    guard let wert = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
        fatalError("Ungültige Decimal-Konstante: \(string)")
    }
    return wert
}

/// Ist `data` syntaktisch gültiges JSON?
///
/// Nötig als Wächter, weil `JSONEncoder` bei `Decimal.nan` **nicht wirft**, sondern literales
/// `NaN` ins JSON schreibt (`{"brutto":NaN}`) – syntaktisch kaputt, kein Decoder liest es je
/// wieder. Ein einziger NaN-Wert macht so ein ganzes Backup lautlos wertlos: Der Export meldet
/// Erfolg, die Datei liegt da, und erst beim Restore (also im Ernstfall) fällt es auf.
///
/// NaN entsteht bei `Decimal` still: Eine Division durch 0 trappt nicht, sie liefert NaN.
/// (`Decimal(string: "nan")` dagegen liefert `nil` – von dort droht nichts.)
func istGueltigesJSON(_ data: Data) -> Bool {
    (try? JSONSerialization.jsonObject(with: data)) != nil
}

extension Decimal {
    /// Kaufmännisch gerundet (Standard: 2 Nachkommastellen, halbe auf).
    func gerundet(_ stellen: Int = 2, _ modus: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var ergebnis = Decimal()
        var wert = self
        NSDecimalRound(&ergebnis, &wert, stellen, modus)
        return ergebnis
    }

    /// Auf **volle Euro Richtung Null** gekürzt – die Form, in der ELSTER Bemessungsgrundlagen
    /// entgegennimmt (Cent-Beträge bleiben dort unberücksichtigt, zugunsten des Unternehmers).
    ///
    /// Richtung **Null**, nicht Richtung minus unendlich: Bei einer negativen Bemessungsgrundlage
    /// (KZ 21 nach einer §17-Berichtigung) soll die Kürzung die Cents weglassen, nicht den Betrag
    /// vergrößern. `-4.000,75 €` wird zu `-4.000 €`, nicht zu `-4.001 €`.
    ///
    /// Foundations `.down` ist echtes `floor` und erledigt nur den positiven Fall; für negative
    /// Werte ist `.up` das Gegenstück Richtung Null.
    var volleEuro: Decimal { gerundet(0, self < 0 ? .up : .down) }

    /// Als Euro-Betrag formatiert, z. B. „1.234,56 €".
    ///
    /// Das Format ist **einmal** aufgebaut (`euroFormat`), nicht je Aufruf: `.currency(code:)`
    /// samt `Locale` kostet bei jedem Zugriff, und eine einzige Tabellenzeile ruft `euro` drei-
    /// bis viermal auf (Betrag, VSt, Netto). Bei ein paar hundert Zeilen summiert sich das.
    var euro: String { formatted(euroFormat) }
}

/// Einheitliches Euro-Format für die ganze App: de_DE, Währungscode EUR.
///
/// Bewusst eine Konstante statt einer Berechnung je Aufruf – siehe `Decimal.euro`. Das Ergebnis
/// ist Zeichen für Zeichen dasselbe wie vorher (`GeldformatTests`).
let euroFormat = Decimal.FormatStyle.Currency(code: "EUR", locale: Locale(identifier: "de_DE"))

// MARK: - Kalender / Datum

/// Einheitlicher Kalender für alle Datumsberechnungen (Perioden, Filter, Import).
/// Gregorianisch, lokale Zeitzone – Hauptsache überall derselbe.
let appKalender: Calendar = {
    var kalender = Calendar(identifier: .gregorian)
    kalender.timeZone = .current
    return kalender
}()

// MARK: - Monatsnamen

// Beide Symbol-Listen einmal aufgebaut: ein `DateFormatter` je Aufruf wäre in Chart-Achsen und
// Tabellenzellen spürbar.

private let _deMonthSymbols: [String] = {
    let df = DateFormatter()
    df.locale = Locale(identifier: "de_DE")
    return df.monthSymbols ?? []
}()

private let _deShortMonthSymbols: [String] = {
    let df = DateFormatter()
    df.locale = Locale(identifier: "de_DE")
    return df.shortMonthSymbols ?? []
}()

/// Ausgeschriebener Monatsname (z. B. „September"), de_DE.
func monatsName(_ monat: Int) -> String {
    guard monat >= 1, monat <= _deMonthSymbols.count else { return "\(monat)" }
    return _deMonthSymbols[monat - 1]
}

/// Kurzer Monatsname (z. B. „Jan"), de_DE – für Chart-Achsen und kompakte Tabellen.
func kurzMonat(_ monat: Int) -> String {
    guard monat >= 1, monat <= _deShortMonthSymbols.count else { return "\(monat)" }
    return _deShortMonthSymbols[monat - 1]
}

/// Jahr auf einen sicher darstellbaren Bereich klemmen.
///
/// Die gregorianische Datumskonstruktion liefert erst bei absurden Jahren `nil`
/// (empirisch z. B. 999999 oder Int.min); reale Buchungsdaten liegen weit darin.
/// Das Klemmen macht `tag(...)` total (nie `nil`), statt bei einem korrupten
/// Jahreswert die App per Force-Unwrap abstürzen zu lassen.
private func klemmeJahr(_ jahr: Int) -> Int { min(max(jahr, 1), 9999) }

/// Kurzschreibweise für ein Datum (Tagesanfang). Robust: crasht nie, auch nicht
/// bei extremen/korrupten Jahreswerten (siehe `klemmeJahr`).
func tag(_ jahr: Int, _ monat: Int, _ tag: Int) -> Date {
    let j = klemmeJahr(jahr)
    if let d = appKalender.date(from: DateComponents(year: j, month: monat, day: tag)) {
        return d
    }
    // Praktisch unerreichbar (geklemmtes Jahr + gängiger Monat), aber ohne Force-Unwrap:
    // deterministischer Rückfall auf den Jahresanfang statt Absturz.
    return appKalender.date(from: DateComponents(year: j, month: 1, day: 1))
        ?? Date(timeIntervalSinceReferenceDate: 0)
}

/// `datum` um `anzahl` Monate verschieben. An einem gültigen Ausgangsdatum scheitert
/// das praktisch nie; bei theoretischem `nil` bleibt das Datum unverändert (kein Crash).
func monateNach(_ datum: Date, _ anzahl: Int) -> Date {
    appKalender.date(byAdding: .month, value: anzahl, to: datum) ?? datum
}

/// Liegt Monat `m` im Jahr `jahr` noch in der Zukunft (nach dem laufenden Monat)?
/// `heute` ist Parameter, damit rein rechnende Aufrufer (z. B. `Monatsreihe`) testbar bleiben.
func istZukunftsmonat(_ m: Int, jahr: Int, heute: Date = Date()) -> Bool {
    let hJ = appKalender.component(.year, from: heute)
    let hM = appKalender.component(.month, from: heute)
    return jahr > hJ || (jahr == hJ && m > hM)
}
