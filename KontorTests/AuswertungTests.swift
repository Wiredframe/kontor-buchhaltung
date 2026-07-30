import Foundation
import Testing

@testable import Kontor

// MARK: - Auswertung: Monats-Waterfall + Jahres-EUR (privat vs. betrieblich, Zufluss)

/// `MonatsAuswertung`/`JahresAuswertung` sind die eine Quelle fuer Gewinn-Waterfall und
/// EUR-Uebersicht (frueher dreifach unabhaengig codiert). Hier direkt geprueft: die
/// abgeleiteten Kennzahlen und die Aggregation ueber `Steuer.monatsauswertung`/`jahresauswertung`.
struct AuswertungTests {

    // MARK: MonatsAuswertung: abgeleitete Kennzahlen (reine Rechnung, kein Store)

    @Test func monatsWaterfallKennzahlen() {
        let a = MonatsAuswertung(
            rn: dez("1000.00"), ust: dez("190.00"), vst: dez("50.00"), ustKorrektur: 0,
            ksk: dez("200.00"), est: dez("100.00"), estKorrektur: 0,
            betriebsausgabenNetto: dez("300.00"),
            fixkostenPrivat: dez("400.00"), privatVariabel: dez("150.00"))

        #expect(a.brutto == dez("1190.00"))  // rn + ust
        #expect(a.ustZahllast == dez("140.00"))  // 190 − 50 + 0
        #expect(a.steuerRuecklage == dez("440.00"))  // 140 + 200 + 100 + 0
        #expect(a.betrieblicherGewinn == dez("700.00"))  // 1000 − 300
        #expect(a.nachSteuer == dez("400.00"))  // 700 − 200 − 100 − 0
        #expect(a.privatGesamt == dez("550.00"))  // 400 + 150
        #expect(a.verfuegbar == dez("-150.00"))  // 400 − 550 (bewusst negativ moeglich)
    }

    @Test func monatsWaterfallMitAusfallKorrekturen() {
        // §17-USt-Auffall (negativ) und ESt-Aufloesung (negativ) fliessen in Zahllast/Ruecklage.
        let a = MonatsAuswertung(
            rn: dez("1000.00"), ust: dez("190.00"), vst: dez("40.00"), ustKorrektur: dez("-19.00"),
            ksk: dez("100.00"), est: dez("80.00"), estKorrektur: dez("-30.00"),
            betriebsausgabenNetto: dez("200.00"),
            fixkostenPrivat: 0, privatVariabel: 0)

        #expect(a.ustZahllast == dez("131.00"))  // 190 − 40 − 19
        #expect(a.steuerRuecklage == dez("281.00"))  // 131 + 100 + 80 − 30
        #expect(a.nachSteuer == dez("650.00"))  // (1000−200) − 100 − 80 + 30
        #expect(a.verfuegbar == dez("650.00"))  // keine privaten Kosten
    }

    // MARK: JahresAuswertung: Gewinn = Einnahmen(Zufluss) − betriebliche Ausgaben(netto)

    @Test func jahresGewinn() {
        let j = JahresAuswertung(
            einnahmenBezahlt: dez("5000.00"), ausgabenNetto: dez("1200.00"), vstGesamt: dez("228.00"))
        #expect(j.gewinn == dez("3800.00"))
    }

    /// Zufluss + privat/betrieblich: nur bezahlte Einnahmen im Jahr und nur betriebliche
    /// Ausgaben im Jahr zaehlen. Private Ausgaben und eine im Folgejahr bezahlte Rechnung
    /// bleiben komplett draussen.
    @Test func jahresauswertungFiltertZuflussUndPrivat() {
        func ein(_ netto: String, _ ust: String, rechnung: Date, zahlung: Date?) -> EinnahmePosten {
            EinnahmePosten(
                rnNetto: dez(netto), ust: dez(ust), rechnungsdatum: rechnung,
                zahlungsdatum: zahlung, status: zahlung == nil ? .offen : .bezahlt)
        }
        func aus(_ brutto: String, _ vst: String, betrieblich: Bool, datum: Date) -> AusgabePosten {
            AusgabePosten(
                brutto: dez(brutto), vst: dez(vst), steuerart: betrieblich ? .inland19 : .steuerfrei,
                betrieblich: betrieblich, datum: datum)
        }

        let einnahmen = [
            ein("1000.00", "190.00", rechnung: tag(2026, 1, 10), zahlung: tag(2026, 2, 1)),  // zaehlt
            ein("2000.00", "380.00", rechnung: tag(2026, 6, 1), zahlung: nil),  // offen -> zaehlt NICHT
            ein("500.00", "95.00", rechnung: tag(2026, 12, 20), zahlung: tag(2027, 1, 5)),  // Zufluss 2027 -> NICHT
            ein("300.00", "57.00", rechnung: tag(2025, 12, 1), zahlung: tag(2026, 1, 3)),  // Zufluss 2026 -> zaehlt
        ]
        let ausgaben = [
            aus("119.00", "19.00", betrieblich: true, datum: tag(2026, 3, 1)),  // netto 100 -> zaehlt
            aus("238.00", "38.00", betrieblich: true, datum: tag(2026, 9, 9)),  // netto 200 -> zaehlt
            aus("500.00", "0.00", betrieblich: false, datum: tag(2026, 4, 4)),  // privat -> NICHT
            aus("119.00", "19.00", betrieblich: true, datum: tag(2025, 11, 1)),  // Vorjahr -> NICHT
        ]

        let j = Steuer.jahresauswertung(jahr: 2026, einnahmen: einnahmen, ausgaben: ausgaben)
        #expect(j.einnahmenBezahlt == dez("1300.00"))  // 1000 + 300
        #expect(j.ausgabenNetto == dez("300.00"))  // 100 + 200
        #expect(j.vstGesamt == dez("57.00"))  // 19 + 38
        #expect(j.gewinn == dez("1000.00"))  // 1300 − 300
    }

    // MARK: Steuer.monatsauswertung: Aggregation aus Posten + Monatswert-Closures

    @Test func monatsauswertungAggregiertPostenUndKsk() {
        let einnahmen = [
            EinnahmePosten(
                rnNetto: dez("1000.00"), ust: dez("190.00"), rechnungsdatum: tag(2026, 5, 3),
                zahlungsdatum: tag(2026, 5, 20), status: .bezahlt)
        ]
        let ausgaben = [
            AusgabePosten(
                brutto: dez("119.00"), vst: dez("19.00"), steuerart: .inland19, betrieblich: true,
                datum: tag(2026, 5, 10)),  // netto 100, betrieblich
            AusgabePosten(
                brutto: dez("50.00"), vst: 0, steuerart: .steuerfrei, betrieblich: false,
                datum: tag(2026, 5, 12)),  // privat -> nicht in betriebsausgabenNetto
        ]
        let a = Steuer.monatsauswertung(
            monat: 5, jahr: 2026, einnahmen: einnahmen, ausgaben: ausgaben,
            kskFuer: { _, _ in dez("250.00") },
            fixkostenPrivat: dez("400.00"),
            privatVariabel: dez("60.00"),
            pauschalSatz: { _, _ in dez("0.15") })

        #expect(a.rn == dez("1000.00"))
        #expect(a.ust == dez("190.00"))
        #expect(a.vst == dez("19.00"))
        #expect(a.betriebsausgabenNetto == dez("100.00"))  // privat bleibt draussen
        #expect(a.ksk == dez("250.00"))
        #expect(a.fixkostenPrivat == dez("400.00"))
        #expect(a.privatVariabel == dez("60.00"))
        // ESt pauschal: (betrieblicher Gewinn 900 − KSK 250) × 15 % = 97,50
        #expect(a.est == dez("97.50"))
    }
}
