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

/// Kurzschreibweise für ein Datum (Tagesanfang).
func tag(_ jahr: Int, _ monat: Int, _ tag: Int) -> Date {
    appKalender.date(from: DateComponents(year: jahr, month: monat, day: tag))!
}
