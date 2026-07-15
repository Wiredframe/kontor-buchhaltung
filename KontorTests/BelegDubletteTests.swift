import Testing
import Foundation
@testable import Kontor

/// Regression: Der Betrag ist bei der Betrag/Datum-Suche das einzige Identitätsmerkmal –
/// und 0 sagt gar nichts. Er entsteht bei fehlgeschlagener OCR und bei jeder frisch per „+"
/// angelegten Leerzeile. Ohne Guard matchte ein 0-Euro-Entwurf den erstbesten anderen
/// 0-Euro-Eintrag, und „Zusammenführen" verschmolz unabhängige Belege.
struct BelegDubletteNullbetragTests {
    private struct Eintrag { var rn: String?; var brutto: Decimal; var datum: Date }

    private let bestand = [
        Eintrag(rn: nil, brutto: 0, datum: tag(2026, 6, 10)),          // Leerzeile aus „+"
        Eintrag(rn: nil, brutto: dez("238"), datum: tag(2026, 6, 11)),
    ]

    private func finde(_ brutto: Decimal, _ datum: Date, rn: String? = nil) -> Eintrag? {
        BelegDublette.finde(rechnungsnummer: rn, brutto: brutto, datum: datum, in: bestand,
                            rechnungsnummerVon: { $0.rn }, bruttoVon: { $0.brutto }, datumVon: { $0.datum })
    }

    @Test func nullBetragMatchtNichtDieLeerzeile() {
        #expect(finde(0, tag(2026, 6, 12)) == nil)
    }

    @Test func nanBetragMatchtNichts() {
        #expect(finde(Decimal(1) / Decimal(0), tag(2026, 6, 12)) == nil)
    }

    /// Gegenprobe: Ein echter Betrag findet seine Dublette weiterhin.
    @Test func echterBetragFindetDieDublette() throws {
        let t = try #require(finde(dez("238"), tag(2026, 6, 12)))
        #expect(t.brutto == dez("238"))
    }

    /// Die Rechnungsnummer bleibt der stärkere Treffer – auch bei Betrag 0.
    @Test func rechnungsnummerGreiftAuchOhneBetrag() throws {
        let liste = [Eintrag(rn: "RE-2026-0815", brutto: 0, datum: tag(2026, 6, 10))]
        let t = BelegDublette.finde(rechnungsnummer: "2026-0815", brutto: 0, datum: tag(2026, 6, 12),
                                    in: liste, rechnungsnummerVon: { $0.rn },
                                    bruttoVon: { $0.brutto }, datumVon: { $0.datum })
        #expect(t != nil)
    }
}

struct BelegDubletteTests {
    /// Minimaler Eintrag, um die reine Logik ohne SwiftData zu prüfen.
    private struct Eintrag {
        var rn: String?
        var brutto: Decimal
        var datum: Date
    }

    private func finde(rechnungsnummer: String?, brutto: Decimal, datum: Date,
                       in liste: [Eintrag], toleranzTage: Int = 14) -> Eintrag? {
        BelegDublette.finde(rechnungsnummer: rechnungsnummer, brutto: brutto, datum: datum,
                            in: liste, toleranzTage: toleranzTage,
                            rechnungsnummerVon: { $0.rn }, bruttoVon: { $0.brutto }, datumVon: { $0.datum })
    }

    @Test func trefferUeberRechnungsnummer() {
        let liste = [Eintrag(rn: "INV-1234", brutto: dez("50"), datum: tag(2026, 1, 1))]
        // Betrag/Datum weichen ab – die Rechnungsnummer entscheidet trotzdem.
        let t = finde(rechnungsnummer: "Rechnung 1234", brutto: dez("999"), datum: tag(2026, 12, 31), in: liste)
        #expect(t != nil)
    }

    @Test func kurzeRechnungsnummerWirdIgnoriert() {
        let liste = [Eintrag(rn: "12", brutto: dez("50"), datum: tag(2026, 6, 10))]
        // < 4 Ziffern → keine RN-Übereinstimmung; Betrag/Datum greifen.
        #expect(finde(rechnungsnummer: "12", brutto: dez("999"), datum: tag(2026, 6, 10), in: liste) == nil)
        #expect(finde(rechnungsnummer: "12", brutto: dez("50"), datum: tag(2026, 6, 12), in: liste) != nil)
    }

    @Test func trefferUeberBetragImFenster() {
        let liste = [Eintrag(rn: nil, brutto: dez("119"), datum: tag(2026, 6, 1))]
        #expect(finde(rechnungsnummer: nil, brutto: dez("119"), datum: tag(2026, 6, 10), in: liste) != nil)   // 9 Tage
        #expect(finde(rechnungsnummer: nil, brutto: dez("119"), datum: tag(2026, 7, 1), in: liste) == nil)    // 30 Tage > 14
        #expect(finde(rechnungsnummer: nil, brutto: dez("120"), datum: tag(2026, 6, 1), in: liste) == nil)    // Betrag ≠
    }
}
