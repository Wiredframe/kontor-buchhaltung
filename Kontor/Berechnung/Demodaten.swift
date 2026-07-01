import Foundation
import SwiftData

/// Synthetische Demodaten einer **fiktiven** Persona: *Lena Brandt*, freiberufliche
/// UI/UX-Designerin in Berlin (KSK-versichert, EÜR, Soll-Versteuerung). Beim ersten Start
/// optional einspielbar, damit man Kontor mit realistisch wirkenden – aber frei erfundenen –
/// Daten erkunden kann. **Greift nur einen leeren Store auf** und fasst nie bestehende Daten an.
enum Demodaten {
    static let jahr = 2026
    private static let monate = 1...6   // Jan–Jun befüllt (laufendes Halbjahr)

    @MainActor
    static func einspielen(_ ctx: ModelContext) {
        guard istLeer(ctx) else { return }   // Sicherheitsnetz: nie in einen befüllten Store

        jahresEinstellungen(ctx)
        einnahmen(ctx)
        betrieblicheAusgaben(ctx)
        privateAusgaben(ctx)
        lebensmittelUndEinkaeufe(ctx)
        zahlungen(ctx)
        aufgaben(ctx)
        try? ctx.save()
    }

    /// Ist der Store komplett leer? (Nur dann ist die Demodaten-Auswahl überhaupt sinnvoll.)
    @MainActor
    static func istLeer(_ ctx: ModelContext) -> Bool {
        func leer<T: PersistentModel>(_: T.Type) -> Bool {
            ((try? ctx.fetchCount(FetchDescriptor<T>())) ?? 0) == 0
        }
        return leer(YearSettings.self) && leer(Income.self) && leer(ExpenseEntry.self)
            && leer(GroceryEntry.self) && leer(PurchaseEntry.self) && leer(TaxPayment.self)
            && leer(MonthlyTask.self) && leer(Vorlage.self)
    }

    // MARK: - Bausteine

    @MainActor
    private static func jahresEinstellungen(_ ctx: ModelContext) {
        let s = YearSettings(jahr: jahr, ustvaRhythmus: .vierteljaehrlich, estPauschalSatz: dez("0.15"))
        // KSK ab Januar: RV 230 / KV 130 / PV 60 = 420 €/Monat; JAE 36.000 (nur Info). Erbt vorwärts.
        s.setzeKSKBetrag(monat: 1, .rv, dez("230.00"))
        s.setzeKSKBetrag(monat: 1, .kv, dez("130.00"))
        s.setzeKSKBetrag(monat: 1, .pv, dez("60.00"))
        s.setzeJAE(monat: 1, dez("36000"))
        ctx.insert(s)
    }

    @MainActor
    private static func einnahmen(_ ctx: ModelContext) {
        // (RN-Nr, Kunde, Netto, Rechnungsmonat/-tag, Zahl-Monat/-tag oder nil = offen)
        let rechnungen: [(String, String, String, Int, Int, (Int, Int)?)] = [
            ("2026-001", "Nordstern Studio GmbH",  "3200.00", 1, 30, (2, 12)),
            ("2026-002", "Kranzler Digital GmbH",  "2800.00", 2, 27, (3, 11)),
            ("2026-003", "Studio Ostkreuz GmbH",   "4100.00", 3, 31, (4, 14)),
            ("2026-004", "Nordstern Studio GmbH",  "3600.00", 4, 30, (5, 13)),
            ("2026-005", "Hafenstadt Media GmbH",  "3000.00", 5, 29, (6, 11)),
            ("2026-006", "Kranzler Digital GmbH",  "3400.00", 6, 26, nil),
        ]
        for (nr, kunde, netto, rm, rt, zahl) in rechnungen {
            let n = dez(netto)
            let income = Income(kunde: kunde, rnNetto: n, ust: Steuer.ust(ausNetto: n),
                                rechnungsdatum: tag(jahr, rm, rt),
                                zahlungsdatum: zahl.map { tag(jahr, $0.0, $0.1) },
                                status: zahl == nil ? .offen : .bezahlt,
                                rechnungsnummer: nr)
            ctx.insert(income)
        }
        // Ermäßigter Satz 7 %: Einräumung von Nutzungsrechten (z. B. Editorial-Illustration).
        let ill = dez("1500.00")
        ctx.insert(Income(kunde: "Feldpost Magazin GmbH", rnNetto: ill, ust: Steuer.ust(ausNetto: ill, satz: .satz7),
                          rechnungsdatum: tag(jahr, 4, 18), zahlungsdatum: tag(jahr, 5, 6),
                          status: .bezahlt, rechnungsnummer: "2026-007", satz: .satz7))
        // Mischrechnung: Reinzeichnung/Beratung 19 % + Nutzungsrechte 7 % auf einer Rechnung.
        let mischG = dez("2000.00"), mischN = dez("900.00")
        ctx.insert(Income(kunde: "Studio Ostkreuz GmbH", rnNetto: mischG, ust: Steuer.ust(ausNetto: mischG, satz: .satz19),
                          rechnungsdatum: tag(jahr, 5, 22), zahlungsdatum: tag(jahr, 6, 9),
                          status: .bezahlt, rechnungsnummer: "2026-008", satz: .satz19,
                          rnNetto2: mischN, ust2: Steuer.ust(ausNetto: mischN, satz: .satz7), satz2: .satz7))
    }

    @MainActor
    private static func betrieblicheAusgaben(_ ctx: ModelContext) {
        // Wiederkehrende SaaS/Fixkosten je Monat (betrieblich → EÜR/VSt).
        // (Bezeichnung, Anbieter, Brutto, VSt, Steuerart, Art, Buchungstag)
        let wiederkehrend: [(String, String, String, String, Steuerart, AusgabeArt, Int)] = [
            ("Figma Professional", "Figma",      "18.00", "0.00",  .reverseCharge, .subscription, 3),
            ("Adobe Creative Cloud", "Adobe",    "71.40", "11.40", .inland19,      .subscription, 3),
            ("GitHub Team", "GitHub",            "8.00",  "0.00",  .reverseCharge, .subscription, 4),
            ("Anthropic Claude", "Anthropic",    "18.00", "0.00",  .reverseCharge, .subscription, 5),
            ("Coworking-Platz", "Spreewerk Coworking", "178.50", "28.50", .inland19, .fixkosten,  1),
        ]
        for m in monate {
            for (bez, anb, brutto, vst, art, kind, t) in wiederkehrend {
                ctx.insert(ExpenseEntry(datum: tag(jahr, m, t), bezeichnung: bez, anbieter: anb,
                                        brutto: dez(brutto), vst: dez(vst), steuerart: art,
                                        betrieblich: true, art: kind))
            }
        }
        // Einmalige Anschaffung (Sofortabzug): Laptop im März, netto 1.200,00.
        ctx.insert(ExpenseEntry(datum: tag(jahr, 3, 14), bezeichnung: "MacBook Air", anbieter: "Apple",
                                brutto: dez("1428.00"), vst: dez("228.00"), steuerart: .inland19,
                                betrieblich: true, art: .betriebsausgabe))
        // Einmalige 7-%-Betriebsausgabe (ermäßigt): Fachbuch im April, netto 40,00 (VSt 2,80).
        ctx.insert(ExpenseEntry(datum: tag(jahr, 4, 9), bezeichnung: "Fachbuch Typografie", anbieter: "Buchhandlung",
                                brutto: dez("42.80"), vst: dez("2.80"), steuerart: .inland7,
                                betrieblich: true, art: .betriebsausgabe))
    }

    @MainActor
    private static func privateAusgaben(_ ctx: ModelContext) {
        // Private Fixkosten/Subscriptions (betrieblich=false, vst=0): nur Liquidität, nie EÜR/VSt.
        let wiederkehrend: [(String, String, String, AusgabeArt, Int)] = [
            ("Miete Wohnung", "Hausverwaltung Spree", "1150.00", .fixkosten,    1),
            ("Strom", "Stromversorger Berlin",        "78.00",   .fixkosten,    1),
            ("Mobilfunk", "Mobilfunk Berlin",         "39.00",   .fixkosten,   15),
            ("Netflix", "Netflix",                    "13.99",   .subscription, 8),
            ("Spotify", "Spotify",                    "10.99",   .subscription, 8),
        ]
        for m in monate {
            for (bez, anb, brutto, art, t) in wiederkehrend {
                ctx.insert(ExpenseEntry(datum: tag(jahr, m, t), bezeichnung: bez, anbieter: anb,
                                        brutto: dez(brutto), vst: 0, steuerart: .steuerfrei,
                                        betrieblich: false, art: art))
            }
        }
    }

    @MainActor
    private static func lebensmittelUndEinkaeufe(_ ctx: ModelContext) {
        // Lebensmittel ~ wöchentlich, wechselnde Orte/Beträge.
        let lm: [(Int, Int, String, String)] = [
            (1, 9, "52.30", "Biomarkt Nord"), (1, 23, "47.85", "Supermarkt"),
            (2, 6, "61.40", "Wochenmarkt"),   (2, 20, "44.10", "Biomarkt Nord"),
            (3, 6, "55.90", "Supermarkt"),    (3, 21, "49.20", "Biomarkt Nord"),
            (4, 4, "58.75", "Wochenmarkt"),   (4, 18, "46.30", "Supermarkt"),
            (5, 8, "53.10", "Biomarkt Nord"), (5, 22, "50.45", "Supermarkt"),
            (6, 5, "57.60", "Wochenmarkt"),   (6, 19, "48.90", "Biomarkt Nord"),
        ]
        for (m, t, betrag, ort) in lm {
            ctx.insert(GroceryEntry(datum: tag(jahr, m, t), betrag: dez(betrag), ort: ort))
        }
        // Einkäufe / Anschaffungen (privat).
        let ek: [(Int, Int, String, String)] = [
            (2, 8, "Schreibtischlampe", "49.90"),
            (3, 20, "Notizbücher & Stifte", "23.40"),
            (5, 5, "Kopfhörer", "129.00"),
        ]
        for (m, t, bez, preis) in ek {
            ctx.insert(PurchaseEntry(datum: tag(jahr, m, t), bezeichnung: bez, preis: dez(preis)))
        }
    }

    @MainActor
    private static func zahlungen(_ ctx: ModelContext) {
        // KSK-Ist-Abbuchungen (Vorsorge-Ledger), Anfang jedes Monats.
        for m in 1...5 {
            ctx.insert(TaxPayment(kind: .ksk, jahr: jahr, faellig: tag(jahr, m, 1),
                                  betrag: dez("420.00"), bezahlt: true, bezahltAm: tag(jahr, m, 1),
                                  bemerkung: "KSK-Beitrag"))
        }
        // USt-Vorauszahlung Q1 (im Mai gezahlt).
        ctx.insert(TaxPayment(kind: .ustVz, jahr: jahr, faellig: tag(jahr, 5, 10),
                              betrag: dez("1571.30"), bezahlt: true, bezahltAm: tag(jahr, 5, 8),
                              bemerkung: "USt-VA Q1 2026"))
    }

    @MainActor
    private static func aufgaben(_ ctx: ModelContext) {
        ctx.insert(MonthlyTask(titel: "UStVA einreichen", monat: tag(jahr, 7, 10),
                               intervall: .quartalsweise, faelligTag: 10, quartalsMonate: [1, 4, 7, 10]))
        ctx.insert(MonthlyTask(titel: "Belege ablegen & prüfen", monat: tag(jahr, 6, 30),
                               intervall: .monatlich, faelligTag: 30))
        ctx.insert(MonthlyTask(titel: "EÜR vorbereiten", monat: tag(jahr, 12, 31),
                               intervall: .jaehrlich, faelligTag: 31, quartalsMonate: [12]))
    }
}
