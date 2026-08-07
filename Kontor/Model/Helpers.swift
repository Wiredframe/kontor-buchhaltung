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

    /// Als Euro-Betrag formatiert, z. B. „1.234,56 €".
    var euro: String {
        formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))
    }
}

// MARK: - Kalender / Datum

/// Einheitlicher Kalender für alle Datumsberechnungen (Perioden, Filter, Import).
/// Gregorianisch, lokale Zeitzone – Hauptsache überall derselbe.
let appKalender: Calendar = {
    var kalender = Calendar(identifier: .gregorian)
    kalender.timeZone = .current
    return kalender
}()

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
