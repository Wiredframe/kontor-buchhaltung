import Foundation
import Testing

@testable import Kontor

// MARK: - Monatsreihe für den Trend-Chart

struct MonatsreiheTests {

    /// März: Rechnung netto 10.000 € (Soll). Mai: Betriebsausgabe netto 1.000 €.
    private static func posten() -> (ein: [EinnahmePosten], aus: [AusgabePosten]) {
        let ein = [
            EinnahmePosten(
                rnNetto: dez("10000.00"), ust: dez("1900.00"), satz: .satz19,
                rechnungsdatum: tag(2024, 3, 10), zahlungsdatum: tag(2024, 3, 20),
                status: .bezahlt, ausfalldatum: nil)
        ]
        let aus = [
            AusgabePosten(
                brutto: dez("1190.00"), vst: dez("190.00"), steuerart: .inland19,
                betrieblich: true, datum: tag(2024, 5, 5))
        ]
        return (ein, aus)
    }

    private static func reihe(
        jahr: Int = 2024, heute: Date = tag(2026, 8, 7),
        privat: Bool = false
    ) -> [Monatsreihe.Punkt] {
        let p = posten()
        return Monatsreihe.jahr(
            jahr, einnahmen: p.ein, ausgaben: p.aus,
            kskFuer: { _, _ in dez("180.00") }, satzFuer: { _, _ in dez("0.15") },
            fixkostenPrivat: privat ? { _ in dez("500.00") } : nil,
            privatVariabel: privat ? { _ in dez("300.00") } : nil,
            heute: heute)
    }

    @Test func vergangenesJahrHatZwoelfPunkte() {
        let r = Self.reihe()
        #expect(r.count == 12)
        #expect(r.map(\.monat) == Array(1...12))
    }

    /// Im laufenden Jahr bricht die Reihe nach dem aktuellen Monat ab – keine 0-Balken für
    /// noch nicht gelebte Monate.
    @Test func zukunftsmonateFehlen() {
        let r = Self.reihe(jahr: 2026, heute: tag(2026, 8, 7))
        #expect(r.count == 8)
        #expect(r.last?.monat == 8)
        // Ein komplett künftiges Jahr liefert gar keine Punkte.
        #expect(Self.reihe(jahr: 2027, heute: tag(2026, 8, 7)).isEmpty)
    }

    /// Jeder Punkt entspricht exakt dem, was `Steuer.monatsauswertung` für den Monat liefert –
    /// die Reihe rechnet bewusst nichts eigenes.
    @Test func gewinnEntsprichtMonatsauswertung() {
        let p = Self.posten()
        for punkt in Self.reihe() {
            let a = Steuer.monatsauswertung(
                monat: punkt.monat, jahr: 2024, einnahmen: p.ein, ausgaben: p.aus,
                kskFuer: { _, _ in dez("180.00") }, fixkostenPrivat: 0,
                pauschalSatz: { _, _ in dez("0.15") })
            #expect(punkt.rn == a.rn)
            #expect(punkt.gewinn == a.betrieblicherGewinn)
            #expect(punkt.steuerRuecklage == a.steuerRuecklage)
        }
        let r = Self.reihe()
        #expect(r[2].gewinn == dez("10000.00"))  // März: nur Umsatz
        #expect(r[4].gewinn == dez("-1000.00"))  // Mai: nur die Ausgabe
    }

    /// Ohne Privatdaten bleibt `frei` nil – ein Wert ohne Privatkosten wäre still viel zu hoch.
    /// Die Steuerrücklage hängt dagegen nicht an Privatkosten und ist immer gesetzt.
    @Test func ohnePrivatdatenBleibtFreiNil() {
        let ohne = Self.reihe()
        #expect(ohne.allSatisfy { $0.frei == nil })
        #expect(ohne[2].steuerRuecklage != 0)  // März trägt USt + KSK + ESt

        let mit = Self.reihe(privat: true)
        #expect(mit.allSatisfy { $0.frei != nil })
        // März: Gewinn 10.000 − KSK 180 − ESt 1.473 = 8.347, minus 500 Fixkosten + 300 variabel.
        #expect(mit[2].frei == dez("7547.00"))
        // Die Rücklage ist in beiden Varianten identisch (USt 1.900 + KSK 180 + ESt 1.473).
        #expect(mit[2].steuerRuecklage == ohne[2].steuerRuecklage)
        #expect(mit[2].steuerRuecklage == dez("3553.00"))
    }
}
