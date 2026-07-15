import Foundation

/// Reine, testbare Dubletten-Erkennung für die Beleg-Erfassung.
///
/// Findet zu einem neuen Beleg-Entwurf einen bereits erfassten Eintrag, damit der
/// Batch-Dialog vor versehentlichem Doppel-Anlegen warnen kann. Bewusst generisch über
/// Wert-Projektionen (wie `ImportAnwendung.nahestes`), damit die Logik ohne SwiftData testbar
/// bleibt – die Aufrufseite reicht die Felder von `Income`/`ExpenseEntry` durch.
enum BelegDublette {

    /// Treffer = zuerst über die Rechnungsnummer (Ziffern-Vergleich, ab 4 Ziffern),
    /// sonst über Brutto-Betrag innerhalb eines Datumsfensters.
    static func finde<T>(
        rechnungsnummer: String?,
        brutto: Decimal,
        datum: Date,
        in liste: [T],
        toleranzTage: Int = 14,
        rechnungsnummerVon: (T) -> String? = { _ in nil },
        bruttoVon: (T) -> Decimal,
        datumVon: (T) -> Date
    ) -> T? {
        if let treffer = perRechnungsnummer(rechnungsnummer, in: liste, rechnungsnummerVon: rechnungsnummerVon) {
            return treffer
        }
        return perBetragDatum(brutto, datum, in: liste, toleranzTage: toleranzTage,
                              betragVon: bruttoVon, datumVon: datumVon)
    }

    // MARK: - Bausteine

    /// Normiert eine Rechnungsnummer auf ihre Ziffern; nil bei < 4 Ziffern (zu unspezifisch).
    static func ziffern(_ s: String?) -> String? {
        guard let s else { return nil }
        let d = s.filter(\.isNumber)
        return d.count >= 4 ? d : nil
    }

    static func perRechnungsnummer<T>(_ rn: String?, in liste: [T],
                                      rechnungsnummerVon: (T) -> String?) -> T? {
        guard let neu = ziffern(rn) else { return nil }
        return liste.first { ziffern(rechnungsnummerVon($0)) == neu }
    }

    static func perBetragDatum<T>(_ betrag: Decimal, _ datum: Date, in liste: [T],
                                  toleranzTage: Int,
                                  betragVon: (T) -> Decimal, datumVon: (T) -> Date) -> T? {
        // **0 ist kein Indiz.** Der Betrag ist hier das einzige Identitätsmerkmal – und 0 entsteht
        // gleich auf zwei Wegen ohne jede Aussage: bei fehlgeschlagener OCR (Betrag nicht erkannt)
        // und bei jeder frisch per „+" angelegten Leerzeile. Ohne diesen Guard matchte ein
        // 0-Euro-Entwurf den erstbesten anderen 0-Euro-Eintrag im Fenster, und „Zusammenführen"
        // verschmolz zwei völlig unabhängige Belege. Ein NaN-Betrag ist aus demselben Grund raus
        // (NaN == NaN ist ohnehin false, der Guard macht die Absicht explizit).
        guard betrag != 0, !betrag.isNaN else { return nil }
        return liste.first {
            betragVon($0) == betrag
                && abs(datumVon($0).timeIntervalSince(datum)) <= Double(toleranzTage) * 86_400
        }
    }
}
