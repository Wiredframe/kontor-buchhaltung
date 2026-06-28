import Foundation

/// Ein halboffenes Zeitintervall `[von, bis)` (bis exklusive).
struct Periode: Hashable {
    var von: Date
    var bis: Date

    func enthaelt(_ datum: Date) -> Bool {
        datum >= von && datum < bis
    }
}

extension Periode {
    static func monat(_ jahr: Int, _ monat: Int) -> Periode {
        let von = tag(jahr, monat, 1)
        let bis = appKalender.date(byAdding: .month, value: 1, to: von)!
        return Periode(von: von, bis: bis)
    }

    /// Quartal `q` (1…4).
    static func quartal(_ jahr: Int, _ q: Int) -> Periode {
        let von = tag(jahr, (q - 1) * 3 + 1, 1)
        let bis = appKalender.date(byAdding: .month, value: 3, to: von)!
        return Periode(von: von, bis: bis)
    }

    static func jahr(_ jahr: Int) -> Periode {
        Periode(von: tag(jahr, 1, 1), bis: tag(jahr + 1, 1, 1))
    }
}
