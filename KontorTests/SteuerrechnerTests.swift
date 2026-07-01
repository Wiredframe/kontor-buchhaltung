import Testing
import Foundation
@testable import Kontor

// MARK: - USt / Vorsteuer-Vorschlag

struct UStTests {
    /// USt = RN × 19 % über mehrere Monate (synthetische Beträge inkl. eines Rundungsfalls).
    @Test func ustAusNettoAlleMonate() {
        #expect(Steuer.ust(ausNetto: dez("1000.00")) == dez("190.00"))
        #expect(Steuer.ust(ausNetto: dez("2500.00")) == dez("475.00"))
        #expect(Steuer.ust(ausNetto: dez("3200.00")) == dez("608.00"))
        #expect(Steuer.ust(ausNetto: dez("1234.50")) == dez("234.56"))   // 234,555 → kaufmännisch auf
        #expect(Steuer.ust(ausNetto: dez("4000.00")) == dez("760.00"))
        #expect(Steuer.ust(ausNetto: dez("5263.16")) == dez("1000.00"))
    }

    @Test func vorsteuerVorschlag() {
        #expect(Steuer.vorsteuerVorschlag(brutto: dez("7.99"),  steuerart: .inland19) == dez("1.28"))
        #expect(Steuer.vorsteuerVorschlag(brutto: dez("12.99"), steuerart: .inland19) == dez("2.07"))
        #expect(Steuer.vorsteuerVorschlag(brutto: dez("35.00"), steuerart: .reverseCharge) == 0)
        #expect(Steuer.vorsteuerVorschlag(brutto: dez("9.99"),  steuerart: .steuerfrei) == 0)
    }

    /// USt-VZ-Zahlung im Jan/Feb zählt fürs Vorjahr – abhängig von Rhythmus & Dauerfristverlängerung.
    @Test func ustVzZuordnungNachEinstellungen() {
        // vierteljährlich, ohne Dauerfrist: Januar → Q4 Vorjahr; Februar → laufendes Jahr.
        let jan = Steuer.ustVzZuordnung(zahlMonat: 1, zahlJahr: 2026, rhythmus: .vierteljaehrlich, dauerfrist: false)
        #expect(jan.jahr == 2025 && jan.notiz == "USt-VA Q4 2025")
        #expect(Steuer.ustVzZuordnung(zahlMonat: 2, zahlJahr: 2026, rhythmus: .vierteljaehrlich, dauerfrist: false).jahr == 2026)
        // mit Dauerfristverlängerung: Februar → Q4 Vorjahr.
        #expect(Steuer.ustVzZuordnung(zahlMonat: 2, zahlJahr: 2026, rhythmus: .vierteljaehrlich, dauerfrist: true).jahr == 2025)
        // monatlich: Januar → Dezember Vorjahr.
        let monJan = Steuer.ustVzZuordnung(zahlMonat: 1, zahlJahr: 2026, rhythmus: .monatlich, dauerfrist: false)
        #expect(monJan.jahr == 2025 && monJan.notiz == "USt-VA Dez 2025")
        // monatlich, März (außerhalb des Fälligkeitsfensters) → laufendes Jahr.
        #expect(Steuer.ustVzZuordnung(zahlMonat: 3, zahlJahr: 2026, rhythmus: .monatlich, dauerfrist: false).jahr == 2026)
        // April → laufendes Jahr (Q1).
        #expect(Steuer.ustVzZuordnung(zahlMonat: 4, zahlJahr: 2026, rhythmus: .vierteljaehrlich, dauerfrist: false).jahr == 2026)
    }
}

// MARK: - Vorsteuer & Reverse-Charge je Quartal (Quelle: „Betriebsausgaben")

struct UStVATests {
    /// Synthetische Q1-Ausgaben (Mix aus Reverse-Charge & Inland 19 %, inkl. einer Hardware-
    /// Anschaffung im März). Summen: VSt 205,20 · RC-Netto 58,00 · RC-USt 11,02.
    static func q1Ausgaben2026() -> [AusgabePosten] {
        func a(_ m: Int, _ tg: Int, _ brutto: String, _ vst: String, _ art: Steuerart) -> AusgabePosten {
            AusgabePosten(brutto: dez(brutto), vst: dez(vst), steuerart: art, betrieblich: true, datum: tag(2026, m, tg))
        }
        return [
            // Januar
            a(1, 5, "18.00", "0.00", .reverseCharge),   // Auslands-SaaS
            a(1, 6, "23.80", "3.80", .inland19),        // Inland 19 % → netto 20,00
            // Februar
            a(2, 5, "20.00", "0.00", .reverseCharge),
            a(2, 11, "71.40", "11.40", .inland19),      // netto 60,00
            // März (inkl. Hardware-Anschaffung)
            a(3, 1, "20.00", "0.00", .reverseCharge),
            a(3, 24, "1190.00", "190.00", .inland19),  // netto 1000,00
        ]
    }

    let q1 = Periode.quartal(2026, 1)

    @Test func vorsteuerQ1() {
        #expect(Steuer.vorsteuer(Self.q1Ausgaben2026(), in: q1) == dez("205.20"))
    }

    @Test func reverseChargeQ1() {
        #expect(Steuer.reverseChargeNetto(Self.q1Ausgaben2026(), in: q1) == dez("58.00"))
        #expect(Steuer.reverseChargeUSt(Self.q1Ausgaben2026(), in: q1) == dez("11.02"))
    }

    @Test func anschaffungNettoHardware() {
        let hardware = AusgabePosten(brutto: dez("1190.00"), vst: dez("190.00"),
                                     steuerart: .inland19,
                                     betrieblich: true, datum: tag(2026, 3, 24))
        #expect(hardware.netto == dez("1000.00"))
    }

    @Test func ustSollNurNachRechnungsdatum() {
        let rechnungen = [
            EinnahmePosten(rnNetto: dez("1000"), ust: dez("190"), rechnungsdatum: tag(2026, 3, 31),
                           zahlungsdatum: nil, status: .offen, ausfalldatum: nil),
            EinnahmePosten(rnNetto: dez("1000"), ust: dez("190"), rechnungsdatum: tag(2026, 4, 1),
                           zahlungsdatum: nil, status: .offen, ausfalldatum: nil),
        ]
        #expect(Steuer.ustSoll(rechnungen, in: Periode.quartal(2026, 1)) == dez("190"))
        #expect(Steuer.ustSoll(rechnungen, in: Periode.quartal(2026, 2)) == dez("190"))
    }

    @Test func formularKennzahlen() {
        let rechnungen = [
            EinnahmePosten(rnNetto: dez("1000"), ust: dez("190"), rechnungsdatum: tag(2026, 2, 10),
                           zahlungsdatum: nil, status: .offen, ausfalldatum: nil),
            // steuerfrei (USt 0) → bleibt aus KZ 81 heraus
            EinnahmePosten(rnNetto: dez("500"), ust: dez("0"), rechnungsdatum: tag(2026, 2, 12),
                           zahlungsdatum: nil, status: .offen, ausfalldatum: nil),
        ]
        let e = Steuer.ustva(einnahmen: rechnungen, ausgaben: Self.q1Ausgaben2026(), periode: q1)
        #expect(e.kz81 == dez("1000"))    // Bemessungsgrundlage netto (nur 19 %)
        #expect(e.ust81 == dez("190"))    // darauf entfallende USt 19 %
        #expect(e.kz66 == dez("205.20"))  // Vorsteuer Inland
        #expect(e.kz84 == dez("58.00"))   // §13b Netto
        #expect(e.kz85 == dez("11.02"))   // §13b USt (geschuldet)
        #expect(e.kz67 == dez("11.02"))   // = KZ 85, als Vorsteuer abziehbar
        // Zahllast = 190 + 11,02 − 205,20 − 11,02 = −15,20 (Vorsteuer-Überhang dank Hardware)
        #expect(e.zahllast == dez("-15.20"))
    }
}

// MARK: - Jahres-Aggregate (Σ einmal pro Render für die Auswertungs-Views)

struct JahresAggregatTests {
    static let einnahmen = [
        EinnahmePosten(rnNetto: dez("4000.00"), ust: dez("760.00"), rechnungsdatum: tag(2026, 3, 15),
                       zahlungsdatum: nil, status: .offen, ausfalldatum: nil),
    ]

    /// estRuecklageJahr summiert nur Monate mit Umsatz (übrige rn=0 → est=0).
    @Test func estRuecklageJahrNurMonateMitUmsatz() {
        let est = Steuer.estRuecklageJahr(
            jahr: 2026, einnahmen: Self.einnahmen, ausgaben: [], kskFuer: { _ in dez("420.00") },
            pauschalSatz: { _, _ in dez("0.15") })
        #expect(est == dez("537.00"))   // nur März: (4000 − 420) × 15 %
    }

    /// ustZahllastJahr summiert die vier Quartale (hier trägt nur Q1).
    @Test func ustZahllastJahrSummiertQuartale() {
        let ust = Steuer.ustZahllastJahr(jahr: 2026, einnahmen: Self.einnahmen, ausgaben: [])
        #expect(ust == dez("760.00"))   // nur Q1: ust81 ohne Vorsteuer/RC
    }
}

// MARK: - §17 Forderungsausfall

struct AusfallTests {
    @Test func korrekturImQuartalDesAusfalls() {
        let r = EinnahmePosten(rnNetto: dez("5000"), ust: dez("950"),
                               rechnungsdatum: tag(2025, 11, 10), zahlungsdatum: nil,
                               status: .ausgefallen, ausfalldatum: tag(2026, 2, 15))
        // USt war im Quartal der Rechnung (Q4 2025) geschuldet …
        #expect(Steuer.ustSoll([r], in: Periode.quartal(2025, 4)) == dez("950"))
        // … und wird im Quartal des Ausfalls (Q1 2026) per §17 korrigiert.
        #expect(Steuer.ustKorrekturAusfall([r], in: Periode.quartal(2026, 1)) == dez("-950"))
        #expect(Steuer.ustKorrekturAusfall([r], in: Periode.quartal(2025, 4)) == 0)
    }
}

// MARK: - ESt pauschal

struct ESTPauschalTests {
    /// Formel-Arithmetik `(Basis − KSK) × Satz`. Die Basis ist im Live-Modus der betriebliche
    /// Gewinn; hier mit synthetischen Beispielwerten geprüft (inkl. Rundungsverhalten, 15 %).
    @Test func pauschalSaubereMonate() {
        #expect(Steuer.estPauschal(basis: dez("2000.00"), ksk: dez("420.00"), satz: dez("0.15")) == dez("237.00"))
        #expect(Steuer.estPauschal(basis: dez("3000.00"), ksk: dez("420.00"), satz: dez("0.15")) == dez("387.00"))
        #expect(Steuer.estPauschal(basis: dez("1234.50"), ksk: dez("420.00"), satz: dez("0.15")) == dez("122.18")) // 122,175 → auf
        #expect(Steuer.estPauschal(basis: dez("2400.00"), ksk: dez("500.00"), satz: dez("0.15")) == dez("285.00"))
        #expect(Steuer.estPauschal(basis: dez("5000.00"), ksk: dez("500.00"), satz: dez("0.15")) == dez("675.00"))
    }

    /// 19 %: Formel-Beispiel `(1234,50 − 500) × 19 % = 139,555 → 139,56` (Rundung kaufmännisch).
    @Test func pauschal19Prozent() {
        #expect(Steuer.estPauschal(basis: dez("1234.50"), ksk: dez("500.00"), satz: dez("0.19")) == dez("139.56"))
    }

    @Test func nieNegativ() {
        #expect(Steuer.estPauschal(basis: dez("300"), ksk: dez("500"), satz: dez("0.15")) == 0)
    }
}

// MARK: - EÜR-Gewinn (Zuflussprinzip)

struct EUERTests {
    @Test func gewinnNachZuflussUndNurBetrieblich() {
        let einnahmen = [
            // bezahlt in 2026 → zählt
            EinnahmePosten(rnNetto: dez("2400"), ust: dez("456"), rechnungsdatum: tag(2026, 5, 5),
                           zahlungsdatum: tag(2026, 5, 28), status: .bezahlt, ausfalldatum: nil),
            // offen (kein Zahlungseingang) → zählt nicht
            EinnahmePosten(rnNetto: dez("1000"), ust: dez("190"), rechnungsdatum: tag(2026, 6, 2),
                           zahlungsdatum: nil, status: .offen, ausfalldatum: nil),
            // 2025 gestellt, aber 2026 bezahlt → zählt 2026 (Zufluss)
            EinnahmePosten(rnNetto: dez("500"), ust: dez("95"), rechnungsdatum: tag(2025, 12, 10),
                           zahlungsdatum: tag(2026, 1, 15), status: .bezahlt, ausfalldatum: nil),
        ]
        let ausgaben = [
            AusgabePosten(brutto: dez("119"), vst: dez("19"), steuerart: .inland19,
                          betrieblich: true, datum: tag(2026, 3, 1)),   // netto 100, betrieblich → zählt
            AusgabePosten(brutto: dez("50"), vst: dez("0"), steuerart: .steuerfrei,
                          betrieblich: false, datum: tag(2026, 3, 1)),  // privat → zählt nicht
        ]
        // (2400 + 500) − 100 = 2800
        #expect(Steuer.euerGewinn(einnahmen: einnahmen, ausgaben: ausgaben, jahr: 2026) == dez("2800"))
    }
}

// MARK: - Monatsrücklage & Verfügbar (Formel gegen die sauberen Blatt-Monate)

struct RuecklageTests {
    /// Verifiziert die Rücklage-/Verfügbar-Formeln mit synthetischen Beispielmonaten
    /// (USt, VSt, KSK, ESt, Fixkosten, Brutto). Rücklage = USt−VSt+KSK+ESt+Fix;
    /// Verfügbar = Brutto − (USt−VSt+KSK+ESt) − Fix.
    @Test func ruecklageUndVerfuegbarMaerzBisJuni() {
        struct M { let ust, vst, ksk, est, fix, brutto, ruecklage, verfuegbar: Decimal }
        let monate: [M] = [
            M(ust: dez("800"),  vst: dez("200"), ksk: dez("420"), est: dez("600"), fix: dez("900"), brutto: dez("5000"), ruecklage: dez("2520"), verfuegbar: dez("2480")),
            M(ust: dez("600"),  vst: dez("100"), ksk: dez("420"), est: dez("400"), fix: dez("900"), brutto: dez("4000"), ruecklage: dez("2220"), verfuegbar: dez("1780")),
            M(ust: dez("475"),  vst: dez("50"),  ksk: dez("500"), est: dez("300"), fix: dez("900"), brutto: dez("3000"), ruecklage: dez("2125"), verfuegbar: dez("875")),
            M(ust: dez("1000"), vst: dez("50"),  ksk: dez("500"), est: dez("800"), fix: dez("900"), brutto: dez("6500"), ruecklage: dez("3150"), verfuegbar: dez("3350")),
        ]
        for m in monate {
            let steuer = Steuer.steuerRuecklage(ust: m.ust, vorsteuer: m.vst, ustKorrektur: 0, ksk: m.ksk, estAnteil: m.est)
            let gesamt = steuer + m.fix
            #expect(gesamt == m.ruecklage)
            #expect(Steuer.verfuegbar(brutto: m.brutto, steuerRuecklage: steuer, fixkosten: m.fix) == m.verfuegbar)
        }
    }

    /// §17-Forderungsausfall mindert die Monatsrücklage im Monat des Ausfalldatums
    /// (die früher zurückgelegte USt wird via §17 wieder frei).
    @Test func ausfallMindertMonatsruecklage() {
        let ausfall = tag(2026, 8, 15)
        let einnahmen = [EinnahmePosten(rnNetto: dez("1000"), ust: dez("190"),
            rechnungsdatum: tag(2026, 5, 10), zahlungsdatum: nil,
            status: .ausgefallen, ausfalldatum: ausfall)]
        let a = Steuer.monatsauswertung(monat: 8, jahr: 2026, einnahmen: einnahmen, ausgaben: [], kskMonat: 0,
            fixkostenPrivat: 0, pauschalSatz: { _, _ in dez("0.15") })
        #expect(a.ustKorrektur == dez("-190"))          // §17-USt zurück
        #expect(a.estKorrektur == dez("-150"))          // ESt-Rücklage auflösen: 1000 × 15 %
        #expect(a.steuerRuecklage == dez("-340"))       // (−190) + 0 + (0 − 150)
    }

    /// ESt-Ausfall-Korrektur nimmt den Satz des Rechnungsmonats (nicht des Ausfallmonats).
    @Test func estAusfallNimmtRechnungsmonatsSatz() {
        let einnahmen = [EinnahmePosten(rnNetto: dez("1000"), ust: 0, rechnungsdatum: tag(2026, 3, 10),
            zahlungsdatum: nil, status: .ausgefallen, ausfalldatum: tag(2026, 9, 20))]
        // März 19 %, sonst 15 % → Auflösung im September muss mit 19 % rechnen.
        let satz: (Int, Int) -> Decimal = { _, m in m == 3 ? dez("0.19") : dez("0.15") }
        let a = Steuer.monatsauswertung(monat: 9, jahr: 2026, einnahmen: einnahmen, ausgaben: [], kskMonat: 0,
            fixkostenPrivat: 0, pauschalSatz: satz)
        #expect(a.estKorrektur == dez("-190"))          // 1000 × 19 % (März), nicht 15 %
    }
}

// MARK: - Mehrere USt-Sätze (7 %/19 %) + Mischrechnungen

struct MehrsatzTests {
    private func e(_ netto: String, _ ust: String, _ satz: UStSatz, _ status: InvoiceStatus = .offen,
                   ausfall: Date? = nil, rechnung: Date = tag(2026, 2, 10)) -> EinnahmePosten {
        EinnahmePosten(rnNetto: dez(netto), ust: dez(ust), satz: satz, rechnungsdatum: rechnung,
                       zahlungsdatum: nil, status: status, ausfalldatum: ausfall)
    }
    private let q1 = Periode.quartal(2026, 1)

    @Test func ustAusNettoErmaessigt() {
        #expect(Steuer.ust(ausNetto: dez("1000.00"), satz: .satz7) == dez("70.00"))
        #expect(Steuer.ust(ausNetto: dez("1234.50"), satz: .satz7) == dez("86.42"))  // 86,415 → auf
        #expect(Steuer.ust(ausNetto: dez("1000.00")) == dez("190.00"))               // Default 19 %
    }

    @Test func reine7ProzentRechnung() {
        let x = Steuer.ustva(einnahmen: [e("1000", "70", .satz7)], ausgaben: [], periode: q1)
        #expect(x.kz81 == 0 && x.ust81 == 0)
        #expect(x.kz86 == dez("1000") && x.ust86 == dez("70"))
        #expect(x.zahllast == dez("70"))
    }

    @Test func kz81UndKz86Gemeinsam() {
        let r = [e("1000", "190", .satz19), e("500", "35", .satz7, rechnung: tag(2026, 3, 5))]
        let x = Steuer.ustva(einnahmen: r, ausgaben: [], periode: q1)
        #expect(x.kz81 == dez("1000") && x.ust81 == dez("190"))
        #expect(x.kz86 == dez("500") && x.ust86 == dez("35"))
        #expect(x.zahllast == dez("225"))   // 190 + 35
    }

    @Test func mischrechnungTraegtInBeideSaetze() {
        let inc = Income(kunde: "X", rnNetto: dez("2000"), ust: dez("380"), rechnungsdatum: tag(2026, 2, 10),
                         status: .offen, satz: .satz19, rnNetto2: dez("900"), ust2: dez("63"), satz2: .satz7)
        let x = Steuer.ustva(einnahmen: inc.postenListe, ausgaben: [], periode: q1)
        #expect(x.kz81 == dez("2000") && x.ust81 == dez("380"))
        #expect(x.kz86 == dez("900") && x.ust86 == dez("63"))
        #expect(x.zahllast == dez("443"))
    }

    /// §17-Ausfall einer 7-%-Rechnung korrigiert genau die 7-%-USt (self-correcting je Posten).
    @Test func ausfallEiner7ProzentRechnung() {
        let r = [e("1000", "70", .satz7, .ausgefallen, ausfall: tag(2026, 2, 15), rechnung: tag(2025, 11, 10))]
        #expect(Steuer.ustKorrekturAusfall(r, in: q1) == dez("-70"))
    }

    /// ELSTER-Zeilenrundung: erst Netto je Satz summieren, dann einmal runden
    /// (3 × 10,10 € → 30,30 × 7 % = 2,121 → 2,12; nicht 3 × 0,71 = 2,13).
    @Test func zeilenrundungJeSatz() {
        let r = (1...3).map { _ in e("10.10", "0.71", .satz7) }
        let x = Steuer.ustva(einnahmen: r, ausgaben: [], periode: q1)
        #expect(x.kz86 == dez("30.30"))
        #expect(x.ust86 == dez("2.12"))
    }
}
