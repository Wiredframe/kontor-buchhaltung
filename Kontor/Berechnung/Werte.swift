import Foundation

// MARK: - Reine Werttypen für die Berechnungs-Schicht
//
// Die Engine arbeitet bewusst auf einfachen Structs (nicht auf @Model), damit
// sie ohne SwiftData testbar bleibt. Die @Model-Klassen liefern Konverter.

struct AusgabePosten: Hashable {
    var brutto: Decimal
    var vst: Decimal
    var steuerart: Steuerart
    var kategorie: Kategorie
    var betrieblich: Bool
    var datum: Date

    var netto: Decimal { brutto - vst }
}

struct EinnahmePosten: Hashable {
    var rnNetto: Decimal
    var ust: Decimal
    var rechnungsdatum: Date
    var zahlungsdatum: Date?
    var status: InvoiceStatus
    var ausfalldatum: Date?

    var brutto: Decimal { rnNetto + ust }
}

/// Eingefrorener Monatsstand: alle Beträge eines Monats, gespeichert beim Abschließen.
/// Ein abgeschlossener Monat zeigt diesen Snapshot statt der Live-Berechnung – die Zahlen
/// bleiben fix, egal was danach an KSK/ESt o. Ä. geändert wird (bis zum Entsperren).
struct MonatsSnapshot: Codable, Hashable {
    var rn, ust, vst, ustKorrektur, ksk, est, estKorrektur: Decimal
    var betriebsausgabenNetto, umlagefaehig, privatFix, privatVariabel: Decimal
}

// MARK: - Konverter aus den @Model-Klassen

extension ExpenseEntry {
    var posten: AusgabePosten {
        AusgabePosten(brutto: brutto, vst: vst, steuerart: steuerart,
                      kategorie: kategorie, betrieblich: betrieblich, datum: datum)
    }
}

extension Income {
    var posten: EinnahmePosten {
        EinnahmePosten(rnNetto: rnNetto, ust: ust, rechnungsdatum: rechnungsdatum,
                       zahlungsdatum: zahlungsdatum, status: status, ausfalldatum: ausfalldatum)
    }
}

// MARK: - UStVA-Ergebnis

/// Kennzahlen einer Umsatzsteuer-Voranmeldung für eine Periode – benannt wie im
/// ELSTER-Formular, damit die Werte direkt übertragbar sind.
struct UStVAErgebnis: Hashable {
    var kz81: Decimal    // KZ 81: Bemessungsgrundlage (netto) der zu 19 % steuerpflichtigen Umsätze
    var ust81: Decimal   // darauf entfallende USt 19 % (im Formular automatisch berechnet)
    var kz66: Decimal    // KZ 66: abziehbare Vorsteuer aus Rechnungen anderer Unternehmer (Inland)
    var kz84: Decimal    // KZ 84: §13b Reverse-Charge – Netto-Bemessung der bezogenen Leistungen
    var kz85: Decimal    // KZ 85: §13b – darauf geschuldete USt
    var kz67: Decimal    // KZ 67: Vorsteuer aus §13b-Leistungen (= KZ 85, zugleich abziehbar)
    var korrektur17: Decimal  // §17-Korrektur (negativ) aus Forderungsausfällen

    /// USt-Vorauszahlung (KZ 83) = USt 19 % + §13b-USt − Vorsteuer Inland − §13b-Vorsteuer (+ §17).
    /// §13b ist cash-neutral (KZ 85 = KZ 67 heben sich auf).
    var zahllast: Decimal { ust81 + kz85 - kz66 - kz67 + korrektur17 }
}
