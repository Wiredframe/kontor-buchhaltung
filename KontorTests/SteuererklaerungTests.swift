import Foundation
import SwiftData
import Testing

@testable import Kontor

/// USt-Jahreserklärung, Anlage EÜR (Bruttomethode) und Vorprüfung – synthetisch nachrechenbar.
struct SteuererklaerungTests {

    private func einnahme(_ netto: String, _ ust: String, _ r: Date, bezahlt: Date?) -> EinnahmePosten {
        EinnahmePosten(
            rnNetto: dez(netto), ust: dez(ust), rechnungsdatum: r, zahlungsdatum: bezahlt,
            status: bezahlt == nil ? .offen : .bezahlt, ausfalldatum: nil)
    }
    private func ustZahlung(_ betrag: String, steuerjahr: Int, faellig: Date, am: Date) -> SteuerzahlungPosten {
        SteuerzahlungPosten(
            kind: .ustVz, jahr: steuerjahr, faellig: faellig, betrag: dez(betrag), bezahlt: true, bezahltAm: am)
    }

    /// Jahreserklärung rechnet §13b aus der gekürzten Jahres-Bemessung, die Voranmeldungen je
    /// Quartal mit Cent – daher der Cent-Unterschied.
    @Test func ustJahreserklaerungKuerztJahresbemessung() {
        let rc = [1, 4, 7, 10].map {
            AusgabePosten(
                brutto: dez("10.90"), vst: 0, steuerart: .reverseCharge, betrieblich: true, datum: tag(2026, $0, 3))
        }
        let ein = [einnahme("1000.50", "190.10", tag(2026, 2, 1), bezahlt: tag(2026, 2, 20))]
        let zahlungen = [ustZahlung("190.00", steuerjahr: 2026, faellig: tag(2026, 4, 10), am: tag(2026, 4, 9))]
        let u = Steuer.ustJahreserklaerung(jahr: 2026, einnahmen: ein, ausgaben: rc, zahlungen: zahlungen)
        #expect(u.bemessung19 == dez("1000") && u.ust19 == dez("190"))
        #expect(u.rcBemessung == dez("43"))  // 4 × 10,90 = 43,60 → 43
        #expect(u.rcUSt == dez("8.17"))  // 43 × 19 %
        #expect(u.steuer == dez("190"))
        #expect(u.nochZuZahlen == 0)
        // Die vier Voranmeldungen: KZ 85 je 2,07 – die §13b-Steuer mit Cent je Quartal.
        let kz85 = (1...4).reduce(Decimal(0)) {
            $0 + Steuer.ustva(einnahmen: [], ausgaben: rc, periode: .quartal(2026, $1)).kz85
        }
        #expect(kz85 == dez("8.28"))
    }

    @Test func abflussJahrMitZehnTageRegel() {
        // Q4 2025 am 08.01.2026 gezahlt, fällig 10.01. → zählt 2025.
        #expect(
            Steuer.abflussJahr(ustZahlung("100", steuerjahr: 2025, faellig: tag(2026, 1, 10), am: tag(2026, 1, 8)))
                == 2025)
        // Erst am 14.01. gezahlt → 2026.
        #expect(
            Steuer.abflussJahr(ustZahlung("100", steuerjahr: 2025, faellig: tag(2026, 1, 10), am: tag(2026, 1, 14)))
                == 2026)
        // Mit Dauerfrist fällig 10.02. → nicht um den Jahreswechsel fällig → 2026. Die Fälligkeit
        // kommt aus den Einstellungen, nicht aus `faellig` (der Import setzt dort den Buchungstag).
        let dauerfrist: Steuer.UStEinstellungen = { _ in (.vierteljaehrlich, true) }
        #expect(
            Steuer.abflussJahr(
                ustZahlung("100", steuerjahr: 2025, faellig: tag(2026, 1, 8), am: tag(2026, 1, 8)),
                einstellungen: dauerfrist) == 2026)
        // Monatlich mit Dauerfrist: im Januar ist die November-VA fällig (10.01.) → Vorjahr.
        #expect(
            Steuer.abflussJahr(
                ustZahlung("100", steuerjahr: 2025, faellig: tag(2026, 1, 8), am: tag(2026, 1, 8)),
                einstellungen: { _ in (.monatlich, true) }) == 2025)
    }

    @Test func euerBruttomethode() {
        let ein = [
            einnahme("1000", "190", tag(2026, 3, 1), bezahlt: tag(2026, 3, 15)),
            einnahme("500", "95", tag(2026, 12, 1), bezahlt: nil),  // offen → fehlt
        ]
        let aus = [
            AusgabePosten(
                brutto: dez("119"), vst: dez("19"), steuerart: .inland19, betrieblich: true, datum: tag(2026, 5, 2)),
            AusgabePosten(
                brutto: dez("2499"), vst: dez("399"), steuerart: .inland19, betrieblich: true, datum: tag(2026, 10, 14),
                nutzungsdauer: 7),
            AusgabePosten(
                brutto: dez("50"), vst: 0, steuerart: .steuerfrei, betrieblich: false, datum: tag(2026, 5, 2)),
        ]
        let zahlungen = [
            ustZahlung("171", steuerjahr: 2026, faellig: tag(2026, 4, 10), am: tag(2026, 4, 10)),
            ustZahlung("80", steuerjahr: 2025, faellig: tag(2026, 1, 10), am: tag(2026, 1, 9)),  // zählt 2025
            ustZahlung("-30", steuerjahr: 2025, faellig: tag(2026, 6, 1), am: tag(2026, 6, 5)),  // Erstattung
        ]
        let e = Steuer.euerErklaerung(jahr: 2026, einnahmen: ein, ausgaben: aus, zahlungen: zahlungen)
        #expect(e.einnahmenNetto == dez("1000") && e.ustVereinnahmt == dez("190") && e.ustErstattet == dez("30"))
        #expect(e.ausgabenNetto == dez("100") && e.afa == dez("75"))
        #expect(e.vorsteuerGezahlt == dez("418"))
        #expect(e.ustGezahlt == dez("171"))
        #expect(e.gewinn == dez("1220") - dez("764"))
    }

    @MainActor @Test func vorpruefungMeldetLuecken() async throws {
        try await mitTemporaerenBelegen { _ in
            let offen = Income(
                kunde: "Agentur Nord", rnNetto: dez("500"), ust: dez("95"), rechnungsdatum: tag(2026, 11, 3))
            let quer = ExpenseEntry(
                datum: tag(2026, 12, 20), bezeichnung: "Drucker", anbieter: "", brutto: dez("595"), vst: dez("95"),
                steuerart: .inland19, art: .betriebsausgabe, zahlungsdatum: tag(2027, 1, 14))
            let gross = ExpenseEntry(
                datum: tag(2026, 6, 1), bezeichnung: "Kamera", anbieter: "", brutto: dez("2499"), vst: dez("399"),
                steuerart: .inland19, art: .betriebsausgabe)
            let punkte = Steuer.vorpruefung(
                jahr: 2026, einnahmen: [offen], ausgaben: [quer, gross], zahlungen: [], hatJahresEinstellungen: true,
                letzteBankbuchung: tag(2026, 9, 30), ustVoranmeldungen: dez("12"), kskSoll: 0)
            let texte = punkte.map(\.text)
            #expect(texte.contains { $0.hasPrefix("Kontoauszug nur bis 30.09.2026") })
            #expect(texte.contains { $0.hasPrefix("Rechnungen des Jahres noch nicht bezahlt") })
            #expect(texte.contains { $0.hasPrefix("Belegdatum und Zahlung in verschiedenen Jahren") })
            #expect(texte.contains { $0.hasPrefix("Anschaffungen über 800 € netto ohne Abschreibung") })
            #expect(texte.contains { $0.hasPrefix("2 betriebliche Ausgaben ohne hinterlegten Beleg") })
            #expect(texte.contains { $0.hasPrefix("USt-Vorauszahlungen") })
            #expect(punkte.filter(\.warnung).count == 3)
        }
    }
}
