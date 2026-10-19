import Foundation
import Testing

@testable import Kontor

struct KSKAssistentTests {

    private let einnahmen = (1...9).map {
        EinnahmePosten(
            rnNetto: dez("3000"), ust: dez("570"), rechnungsdatum: tag(2026, $0, 1), zahlungsdatum: tag(2026, $0, 20),
            status: .bezahlt, ausfalldatum: nil)
    }

    /// Am 19. Oktober zählen Januar bis September: 27.000 € → 36.000 € aufs Jahr.
    @Test func hochrechnungAusAbgeschlossenenMonaten() throws {
        let s = YearSettings(jahr: 2026, estPauschalSatz: dez("0.15"))
        s.setzeJAE(monat: 1, dez("24000"))
        let k = try #require(
            Steuer.kskSchaetzung(jahr: 2026, einnahmen: einnahmen, ausgaben: [], settings: s, heute: tag(2026, 10, 19)))
        #expect(k.monate == 9 && k.gewinnBisher == dez("27000") && k.hochrechnung == dez("36000"))
        #expect(k.gemeldet == dez("24000") && k.abweichung == dez("12000") && k.deutlich)
    }

    @Test func abgelaufenesUndKuenftigesJahr() throws {
        let k = try #require(
            Steuer.kskSchaetzung(jahr: 2026, einnahmen: einnahmen, ausgaben: [], settings: nil, heute: tag(2027, 2, 1)))
        #expect(k.monate == 12 && k.hochrechnung == dez("27000") && k.gemeldet == 0 && !k.deutlich)
        #expect(
            Steuer.kskSchaetzung(jahr: 2026, einnahmen: einnahmen, ausgaben: [], settings: nil, heute: tag(2026, 1, 15))
                == nil)
        #expect(
            Steuer.kskSchaetzung(jahr: 2027, einnahmen: einnahmen, ausgaben: [], settings: nil, heute: tag(2026, 6, 1))
                == nil)
    }
}
