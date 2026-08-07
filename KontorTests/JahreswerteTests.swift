import Foundation
import Testing

@testable import Kontor

// MARK: - Jahres-Aggregate des Jahresabschlusses
//
// Die Werte sind bewusst klein und von Hand nachrechenbar. Basisjahr ist **2024** (ein
// abgeschlossenes Jahr), damit die KSK-Jahressumme über alle zwölf Monate läuft und nicht
// vom Testzeitpunkt abhängt; für den „bis zum laufenden Monat"-Zweig gibt es einen eigenen
// Test mit explizitem `heute`.

struct JahreswerteTests {

    /// Eine bezahlte Rechnung im März (netto 10.000 €) und eine Betriebsausgabe im Mai
    /// (brutto 1.190 €, VSt 190 € → netto 1.000 €).
    private static func fixtures() -> (ein: [Income], aus: [ExpenseEntry]) {
        let ein = [
            Income(
                kunde: "Beispiel GmbH", rnNetto: dez("10000.00"), ust: dez("1900.00"),
                rechnungsdatum: tag(2024, 3, 10), zahlungsdatum: tag(2024, 3, 20), status: .bezahlt)
        ]
        let aus = [
            ExpenseEntry(
                datum: tag(2024, 5, 5), bezeichnung: "Notebook", anbieter: "Händler",
                brutto: dez("1190.00"), vst: dez("190.00"), steuerart: .inland19, betrieblich: true)
        ]
        return (ein, aus)
    }

    /// KSK 2024: RV 100 · KV 60 · PV 20 je Monat (nur Januar gesetzt, die Folgemonate erben).
    private static func settings2024() -> YearSettings {
        YearSettings(
            jahr: 2024, ustvaRhythmus: .vierteljaehrlich, estPauschalSatz: dez("0.15"),
            kskRVProMonat: ["1": dez("100.00")], kskKVProMonat: ["1": dez("60.00")],
            kskPVProMonat: ["1": dez("20.00")])
    }

    @Test func gewinnUndRuecklageAusFixenPosten() {
        let f = Self.fixtures()
        let w = Jahreswerte.bauen(
            jahr: 2024, einnahmen: f.ein, ausgaben: f.aus, zahlungen: [],
            jahre: [Self.settings2024()], heute: tag(2026, 8, 7))

        #expect(w.a.einnahmenBezahlt == dez("10000.00"))
        #expect(w.a.ausgabenNetto == dez("1000.00"))
        #expect(w.a.gewinn == dez("9000.00"))
        #expect(w.a.vstGesamt == dez("190.00"))

        // KSK: 12 × (100 + 60 + 20) = 2.160 €, aufgeteilt nach Zweig.
        #expect(w.ksk.rv == dez("1200.00"))
        #expect(w.ksk.kv == dez("720.00"))
        #expect(w.ksk.pv == dez("240.00"))
        #expect(w.kskGesamt == dez("2160.00"))

        // ESt-Rücklage: nur der März trägt (RN 10.000 − 0 Ausgaben − KSK 180) × 15 % = 1.473 €.
        // Der Mai ist mit −1.000 € Gewinn negativ und wird durch max(0, …) auf 0 gekappt.
        #expect(w.estRuecklage == dez("1473.00"))

        // Voraussichtliche ESt (jahresbasiert): (9.000 − 11.784 − 2.160) < 0 → 0 €.
        #expect(w.grundfreibetrag == Decimal(11784))
        #expect(w.estVoraussichtlich == 0)

        // USt: nur Q1 trägt (1.900 USt − 190 VSt fällt in Q2) → Q1 1.900, Q2 −190.
        #expect(w.ustPerioden.count == 4)
        #expect(w.ustPerioden[0] == UStPeriodenwert(label: "Q1", betrag: dez("1900.00")))
        #expect(w.ustPerioden[1] == UStPeriodenwert(label: "Q2", betrag: dez("-190.00")))
        #expect(w.ustJahr == dez("1710.00"))
        #expect(w.steuerlast == dez("3183.00"))  // 1.473 ESt + 1.710 USt
        #expect(!w.istAktuellesJahr && w.hatJahresEinstellungen)
    }

    /// Im laufenden Jahr summiert die KSK nur bis zum aktuellen Monat, in einem künftigen gar nicht.
    @Test func kskJahrLaeuftNurBisZumLaufendenMonat() {
        let s = Self.settings2024()
        // „Heute" ist der 7. Mai 2024 → fünf Monate à 180 € = 900 €.
        let laufend = Jahreswerte.bauen(
            jahr: 2024, einnahmen: [], ausgaben: [], zahlungen: [], jahre: [s], heute: tag(2024, 5, 7))
        #expect(laufend.kskGesamt == dez("900.00"))
        #expect(laufend.istAktuellesJahr)

        // Abgeschlossenes Jahr → volle zwölf Monate.
        let vergangen = Jahreswerte.bauen(
            jahr: 2024, einnahmen: [], ausgaben: [], zahlungen: [], jahre: [s], heute: tag(2025, 1, 1))
        #expect(vergangen.kskGesamt == dez("2160.00"))

        // Künftiges Jahr → noch nichts angefallen.
        let kuenftig = Jahreswerte.bauen(
            jahr: 2024, einnahmen: [], ausgaben: [], zahlungen: [], jahre: [s], heute: tag(2023, 6, 1))
        #expect(kuenftig.kskGesamt == 0)
    }

    @Test func zahlungenWerdenNachArtGruppiert() {
        let z = [
            TaxPayment(kind: .estVz, jahr: 2024, faellig: tag(2024, 3, 10), betrag: dez("500.00"), bezahlt: true),
            TaxPayment(kind: .estBescheid, jahr: 2024, faellig: tag(2024, 9, 1), betrag: dez("200.00"), bezahlt: true),
            TaxPayment(kind: .ustVz, jahr: 2024, faellig: tag(2024, 4, 10), betrag: dez("900.00"), bezahlt: true),
            TaxPayment(kind: .ksk, jahr: 2024, faellig: tag(2024, 1, 5), betrag: dez("180.00"), bezahlt: true),
            // Erstattung (negativ) unter „sonstige" – muss sauber mitzählen, nicht wegfallen.
            TaxPayment(kind: .sonstige, jahr: 2024, faellig: tag(2024, 7, 1), betrag: dez("-40.00"), bezahlt: true),
            // Fremdes Jahr → gehört nicht in die Jahresliste.
            TaxPayment(kind: .estVz, jahr: 2025, faellig: tag(2025, 3, 10), betrag: dez("999.00"), bezahlt: true),
        ]
        let w = Jahreswerte.bauen(
            jahr: 2024, einnahmen: [], ausgaben: [], zahlungen: z, jahre: [], heute: tag(2026, 8, 7))

        #expect(w.zahlungen.count == 5)
        #expect(w.estGezahlt.count == 2)  // estVz + estBescheid
        #expect(w.estVzBezahlt == dez("500.00"))  // nur die Vorauszahlung
        #expect(w.ustGezahlt.count == 1)
        #expect(w.kskGezahlt.count == 1)
        #expect(w.sonstigeGezahlt.count == 1)
        #expect(w.bezahltGesamt == dez("1740.00"))  // 500 + 200 + 900 + 180 − 40
        // Sortiert nach Anzeigedatum (hier: Fälligkeit).
        #expect(w.zahlungen.first?.kind == .ksk)
    }

    /// Ohne `YearSettings` des Jahres bleibt die KSK bei 0 und der gesetzliche Grundfreibetrag gilt.
    @Test func ohneYearSettingsKeineKSKUndStandardGrundfreibetrag() {
        let f = Self.fixtures()
        // Nur ein **fremdes** Jahr ist hinterlegt – dessen KSK darf nicht durchschlagen.
        let fremd = YearSettings(jahr: 2025, estPauschalSatz: dez("0.15"), kskRVProMonat: ["1": dez("999.00")])
        let w = Jahreswerte.bauen(
            jahr: 2024, einnahmen: f.ein, ausgaben: f.aus, zahlungen: [], jahre: [fremd],
            heute: tag(2026, 8, 7))

        #expect(!w.hatJahresEinstellungen)
        #expect(w.kskGesamt == 0)
        #expect(w.grundfreibetrag == Steuer.grundfreibetragStandard(jahr: 2024))
        // Ohne KSK trägt der März (10.000 − 0) × 15 % = 1.500 €.
        #expect(w.estRuecklage == dez("1500.00"))
    }

    /// Der Rhythmus des Jahres steuert die Zahl der Perioden; die Jahressumme bleibt gleich.
    @Test func ustPeriodenFolgenDemRhythmus() {
        let f = Self.fixtures()
        let quartal = Jahreswerte.bauen(
            jahr: 2024, einnahmen: f.ein, ausgaben: f.aus, zahlungen: [],
            jahre: [YearSettings(jahr: 2024, ustvaRhythmus: .vierteljaehrlich, estPauschalSatz: dez("0.15"))],
            heute: tag(2026, 8, 7))
        let monat = Jahreswerte.bauen(
            jahr: 2024, einnahmen: f.ein, ausgaben: f.aus, zahlungen: [],
            jahre: [YearSettings(jahr: 2024, ustvaRhythmus: .monatlich, estPauschalSatz: dez("0.15"))],
            heute: tag(2026, 8, 7))

        #expect(quartal.ustPerioden.count == 4 && quartal.ustRhythmus == .vierteljaehrlich)
        #expect(monat.ustPerioden.count == 12 && monat.ustRhythmus == .monatlich)
        #expect(quartal.ustJahr == monat.ustJahr)
        #expect(monat.ustPerioden[2].betrag == dez("1900.00"))  // März trägt die USt
        #expect(monat.ustPerioden[4].betrag == dez("-190.00"))  // Mai die Vorsteuer
    }

    /// Die einmal gemappten Posten liegen im Ergebnis – Aufrufer sollen nicht neu mappen müssen.
    @Test func postenWerdenMitgeliefert() {
        let f = Self.fixtures()
        let w = Jahreswerte.bauen(
            jahr: 2024, einnahmen: f.ein, ausgaben: f.aus, zahlungen: [], jahre: [], heute: tag(2026, 8, 7))
        #expect(w.einP.count == 1)
        #expect(w.ausP.count == 1)
    }
}
