import Foundation
import Testing

@testable import Kontor

/// AfA (§7 Abs. 1 EStG) und Abflussprinzip (§11 Abs. 2 EStG) – synthetische Werte zum Nachrechnen.
struct AbschreibungTests {

    /// Kamera 2.100 € netto (2.499 € brutto), gekauft im Oktober 2026, sieben Jahre: 25 €/Monat.
    private var kamera: AusgabePosten {
        AusgabePosten(
            brutto: dez("2499"), vst: dez("399"), steuerart: .inland19, betrieblich: true,
            datum: tag(2026, 10, 14), nutzungsdauer: 7, bezeichnung: "Kamera")
    }

    @Test func linearUndMonatsgenauAbDemKaufmonat() {
        #expect(kamera.afa(in: Periode.monat(2026, 9)) == 0)
        #expect(kamera.afa(in: Periode.monat(2026, 10)) == dez("25"))
        #expect(kamera.afa(in: Periode.jahr(2026)) == dez("75"))  // Okt–Dez
        #expect(kamera.afa(in: Periode.jahr(2027)) == dez("300"))
        #expect(kamera.afa(in: Periode.jahr(2033)) == dez("225"))  // Jan–Sep, dann fertig
        #expect(kamera.afa(in: Periode.jahr(2034)) == 0)
        let summe = (2026...2034).reduce(Decimal(0)) { $0 + kamera.afa(in: Periode.jahr($1)) }
        #expect(summe == kamera.netto)
    }

    /// Krumme Beträge: kumuliert gerundet, die Raten addieren sich exakt zum Netto.
    @Test func ratenSummierenSichExaktZumNetto() {
        let stuhl = AusgabePosten(
            brutto: dez("1000"), vst: dez("159.66"), steuerart: .inland19, betrieblich: true,
            datum: tag(2026, 3, 1), nutzungsdauer: 13)
        let monate = (0..<(13 * 12 + 2)).map { stuhl.afa(in: Periode.monat(2026 + ($0 + 2) / 12, ($0 + 2) % 12 + 1)) }
        #expect(monate.reduce(0, +) == stuhl.netto)
        #expect(monate.allSatisfy { $0 >= 0 })
    }

    /// Gewinn, ESt-Rücklage und EÜR zählen nur die AfA, die Vorsteuer zählt voll beim Kauf.
    @Test func vorsteuerVollGewinnNurAfA() {
        let a = [kamera]
        let okt = Steuer.monatsauswertung(
            monat: 10, jahr: 2026, einnahmen: [], ausgaben: a, kskFuer: { _, _ in 0 }, fixkostenPrivat: 0,
            pauschalSatz: { _, _ in dez("0.15") })
        #expect(okt.vst == dez("399"))
        #expect(okt.betriebsausgabenNetto == dez("25"))
        #expect(Steuer.ustva(einnahmen: [], ausgaben: a, periode: Periode.quartal(2026, 4)).kz66 == dez("399"))
        let jahr = Steuer.jahresauswertung(jahr: 2026, einnahmen: [], ausgaben: a)
        #expect(jahr.ausgabenNetto == dez("75") && jahr.afa == dez("75") && jahr.vstGesamt == dez("399"))
        #expect(Steuer.euerGewinn(einnahmen: [], ausgaben: a, jahr: 2026) == dez("-75"))
    }

    @Test func anlagenverzeichnis() {
        let fertig = AusgabePosten(
            brutto: dez("1190"), vst: dez("190"), steuerart: .inland19, betrieblich: true,
            datum: tag(2020, 1, 1), nutzungsdauer: 3, bezeichnung: "Alt")
        let privat = AusgabePosten(
            brutto: dez("1190"), vst: 0, steuerart: .inland19, betrieblich: false, datum: tag(2026, 1, 1),
            nutzungsdauer: 3)
        #expect(Steuer.anlagen([kamera, fertig, privat], jahr: 2025).isEmpty)
        let j26 = Steuer.anlagen([kamera, fertig, privat], jahr: 2026)
        #expect(j26.count == 1)
        #expect(j26[0].zugang && j26[0].afa == dez("75") && j26[0].buchwertEnde == dez("2025"))
        let j27 = Steuer.anlagen([kamera], jahr: 2027)
        #expect(!j27[0].zugang && j27[0].buchwertAnfang == dez("2025") && j27[0].buchwertEnde == dez("1725"))
    }

    /// Belegdatum Dezember, bezahlt im Januar: Vorsteuer und Monatsgewinn im Dezember, EÜR im Folgejahr.
    @Test func euerZaehltNachAbfluss() {
        let drucker = AusgabePosten(
            brutto: dez("595"), vst: dez("95"), steuerart: .inland19, betrieblich: true,
            datum: tag(2025, 12, 8), zahlungsdatum: tag(2026, 1, 14))
        #expect(Steuer.jahresauswertung(jahr: 2025, einnahmen: [], ausgaben: [drucker]).ausgabenNetto == 0)
        #expect(Steuer.jahresauswertung(jahr: 2025, einnahmen: [], ausgaben: [drucker]).vstGesamt == dez("95"))
        #expect(Steuer.jahresauswertung(jahr: 2026, einnahmen: [], ausgaben: [drucker]).ausgabenNetto == dez("500"))
        let dez25 = Steuer.monatsauswertung(
            monat: 12, jahr: 2025, einnahmen: [], ausgaben: [drucker], kskFuer: { _, _ in 0 }, fixkostenPrivat: 0,
            pauschalSatz: { _, _ in dez("0.15") })
        #expect(dez25.betriebsausgabenNetto == dez("500"))
    }

    /// Zehn-Tage-Regel: wiederkehrende Ausgabe Ende Dezember fällig, Anfang Januar bezahlt → Vorjahr.
    @Test func zehnTageRegelFuerWiederkehrendes() {
        var miete = AusgabePosten(
            brutto: dez("300"), vst: 0, steuerart: .steuerfrei, betrieblich: true,
            datum: tag(2025, 12, 30), zahlungsdatum: tag(2026, 1, 5), wiederkehrend: true)
        #expect(Steuer.jahresauswertung(jahr: 2025, einnahmen: [], ausgaben: [miete]).ausgabenNetto == dez("300"))
        // Außerhalb der zehn Tage gilt wieder der Abfluss.
        miete.zahlungsdatum = tag(2026, 1, 12)
        #expect(Steuer.jahresauswertung(jahr: 2026, einnahmen: [], ausgaben: [miete]).ausgabenNetto == dez("300"))
        // Einmalige Ausgaben fallen nicht unter die Regel.
        miete.zahlungsdatum = tag(2026, 1, 5)
        miete.wiederkehrend = false
        #expect(Steuer.jahresauswertung(jahr: 2026, einnahmen: [], ausgaben: [miete]).ausgabenNetto == dez("300"))
    }

    /// Nutzungsdauer wirkt nur bei betrieblichen Betriebsausgaben; angeboten erst über 800 € netto.
    @Test func nutzungsdauerNurFuerBetrieblicheAnschaffungen() {
        let e = ExpenseEntry(
            datum: tag(2026, 5, 1), bezeichnung: "Monitorarm", anbieter: "", brutto: dez("1190"), vst: dez("190"),
            steuerart: .inland19, art: .betriebsausgabe, nutzungsdauer: 5)
        #expect(e.nutzungsdauerEffektiv == 5 && e.kannAbgeschriebenWerden)
        e.betrieblich = false
        #expect(e.nutzungsdauerEffektiv == 0 && !e.posten.istAnlagegut)
        e.betrieblich = true
        e.art = .subscription
        #expect(e.nutzungsdauerEffektiv == 0)
        e.art = .betriebsausgabe
        e.brutto = dez("952")  // 800 € netto: GWG, Sofortabzug
        #expect(!e.kannAbgeschriebenWerden)
    }
}
