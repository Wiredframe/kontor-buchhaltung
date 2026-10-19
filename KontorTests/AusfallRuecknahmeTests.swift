import Foundation
import Testing

@testable import Kontor

/// §17 Abs. 2 Nr. 1 Satz 2 UStG: Wird eine uneinbringliche Forderung nach der Berichtigung doch
/// bezahlt, wird im **Zahlungszeitraum** erneut berichtigt. Der Ausfallzeitraum bleibt, wie er
/// angemeldet wurde.
struct AusfallRuecknahmeTests {

    /// Rechnung Q1 (1.000 € + 190 €), Ausfall Q2, doch bezahlt Q3.
    private var posten: EinnahmePosten {
        EinnahmePosten(
            rnNetto: dez("1000"), ust: dez("190"), rechnungsdatum: tag(2026, 2, 10),
            zahlungsdatum: tag(2026, 8, 3), status: .bezahlt, ausfalldatum: tag(2026, 5, 15))
    }

    @Test func faktorJePeriode() {
        #expect(posten.ausfallFaktor(in: Periode.quartal(2026, 1)) == 0)
        #expect(posten.ausfallFaktor(in: Periode.quartal(2026, 2)) == 1)
        #expect(posten.ausfallFaktor(in: Periode.quartal(2026, 3)) == -1)
        // Ausfall und Zahlung im selben Jahr heben sich auf.
        #expect(posten.ausfallFaktor(in: Periode.jahr(2026)) == 0)
        // Offen mit Altlast-Datum zählt nie als Ausfall.
        var offen = posten
        offen.status = .offen
        #expect(offen.ausfallFaktor(in: Periode.quartal(2026, 2)) == 0)
        // Noch ausgefallen: keine Rücknahme, auch wenn ein Zahlungsdatum herumsteht.
        var aus = posten
        aus.status = .ausgefallen
        #expect(aus.ausfallFaktor(in: Periode.quartal(2026, 3)) == 0)
    }

    /// Lag die Zahlung **vor** dem Ausfall, war der Ausfall ein Irrtum – keine Rücknahme.
    @Test func zahlungVorDemAusfallNimmtNichtsZurueck() {
        var p = posten
        p.zahlungsdatum = tag(2026, 3, 15)
        #expect(p.ausfallFaktor(in: Periode.quartal(2026, 1)) == 0)
        #expect(p.ausfallFaktor(in: Periode.quartal(2026, 2)) == 1)
    }

    @Test func ustvaNimmtDieMinderungImZahlungsquartalZurueck() {
        let e = [posten]
        let q1 = Steuer.ustva(einnahmen: e, ausgaben: [], periode: Periode.quartal(2026, 1))
        let q2 = Steuer.ustva(einnahmen: e, ausgaben: [], periode: Periode.quartal(2026, 2))
        let q3 = Steuer.ustva(einnahmen: e, ausgaben: [], periode: Periode.quartal(2026, 3))
        #expect(q1.kz81 == dez("1000") && q1.zahllast == dez("190"))
        #expect(q2.kz81 == dez("-1000") && q2.zahllast == dez("-190"))
        #expect(q2.korrektur17 == dez("-190"))
        #expect(q3.kz81 == dez("1000") && q3.zahllast == dez("190"))
        #expect(q3.korrektur17 == dez("190"))
    }

    @Test func kz21UndZMNehmenEbenfallsZurueck() {
        let eu = EinnahmePosten(
            rnNetto: dez("2000"), ust: 0, umsatzart: .euReverseCharge, rechnungsdatum: tag(2026, 2, 10),
            zahlungsdatum: tag(2026, 8, 3), status: .bezahlt, ausfalldatum: tag(2026, 5, 15))
        #expect(Steuer.ustva(einnahmen: [eu], ausgaben: [], periode: Periode.quartal(2026, 2)).kz21 == dez("-2000"))
        #expect(Steuer.ustva(einnahmen: [eu], ausgaben: [], periode: Periode.quartal(2026, 3)).kz21 == dez("2000"))

        let zm = ZMPosten(
            kunde: "Studio Wien", ustIdNr: "ATU12345678", netto: dez("2000"), rechnungsdatum: tag(2026, 2, 10),
            status: .bezahlt, ausfalldatum: tag(2026, 5, 15), zahlungsdatum: tag(2026, 8, 3))
        #expect(Steuer.zm([zm], in: Periode.quartal(2026, 2)).summe == dez("-2000"))
        #expect(Steuer.zm([zm], in: Periode.quartal(2026, 3)).summe == dez("2000"))
    }

    /// Die im Ausfallmonat aufgelöste ESt-Rücklage wird im Zahlungsmonat wieder gebildet, der
    /// Gewinn sinkt im Ausfallmonat und steigt im Zahlungsmonat um das Netto.
    @Test func monatsauswertungBildetRuecklageWiederUndKorrigiertGewinn() {
        let e = [posten]
        let ksk: (Int, Int) -> Decimal = { _, _ in 0 }
        let satz: (Int, Int) -> Decimal = { _, _ in dez("0.15") }
        func monat(_ m: Int) -> MonatsAuswertung {
            Steuer.monatsauswertung(
                monat: m, jahr: 2026, einnahmen: e, ausgaben: [], kskFuer: ksk, fixkostenPrivat: 0,
                pauschalSatz: satz)
        }
        #expect(monat(2).est == dez("150"))
        #expect(monat(2).betrieblicherGewinn == dez("1000"))
        #expect(monat(5).estKorrektur == dez("-150"))
        #expect(monat(5).betrieblicherGewinn == dez("-1000"))
        #expect(monat(5).ustKorrektur == dez("-190"))
        #expect(monat(8).estKorrektur == dez("150"))
        #expect(monat(8).betrieblicherGewinn == dez("1000"))
        #expect(monat(8).ustKorrektur == dez("190"))
        let jahr = Steuer.estRuecklageJahr(
            jahr: 2026, einnahmen: e, ausgaben: [], kskFuer: ksk, pauschalSatz: satz)
        #expect(jahr == dez("150"))
    }

    /// Ohne Zahlung bleibt alles wie bisher: Ausfall mindert Gewinn im Ausfallmonat.
    @Test func ausfallOhneZahlungMindertDenMonatsgewinn() {
        var aus = posten
        aus.status = .ausgefallen
        aus.zahlungsdatum = nil
        let a = Steuer.monatsauswertung(
            monat: 5, jahr: 2026, einnahmen: [aus], ausgaben: [], kskFuer: { _, _ in 0 }, fixkostenPrivat: 0,
            pauschalSatz: { _, _ in dez("0.15") })
        #expect(a.ausfallNetto == dez("1000"))
        #expect(a.betrieblicherGewinn == dez("-1000"))
        #expect(a.nachSteuer == dez("-850"))  // −1000 − (−150 Auflösung)
    }

    @Test func bezahltNachAusfallBehaeltDasAusfalldatum() throws {
        let rechnung = Income(
            kunde: "Agentur Nord", rnNetto: dez("1000"), ust: dez("190"), rechnungsdatum: tag(2026, 2, 10))
        rechnung.setze(status: .ausgefallen)
        let ausfall = try #require(rechnung.ausfalldatum)
        rechnung.setze(status: .bezahlt)
        #expect(rechnung.ausfalldatum == ausfall)
        #expect(rechnung.zahlungsdatum != nil)
        #expect(rechnung.nachAusfallBezahlt)

        // Über den Picker: Status ist schon überschrieben, `vorher` trägt den alten.
        let zweite = Income(
            kunde: "Agentur Süd", rnNetto: dez("500"), ust: dez("95"), rechnungsdatum: tag(2026, 2, 10))
        zweite.setze(status: .ausgefallen)
        zweite.status = .bezahlt
        zweite.setze(status: .bezahlt, vorher: .ausgefallen)
        #expect(zweite.ausfalldatum != nil)

        // Offen räumt beides ab, ein späteres „bezahlt" ist dann ein normaler Zahlungseingang.
        rechnung.setze(status: .offen)
        rechnung.setze(status: .bezahlt)
        #expect(rechnung.ausfalldatum == nil)
        #expect(!rechnung.nachAusfallBezahlt)
    }
}
