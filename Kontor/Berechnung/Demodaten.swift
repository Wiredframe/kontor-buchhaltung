import Foundation
import SwiftData

/// Synthetische Demodaten einer **fiktiven** Persona: *Lena Brandt*, freiberufliche
/// UI/UX-Designerin in Berlin (KSK-versichert, EÜR, Soll-Versteuerung). Beim ersten Start
/// optional einspielbar, damit man Kontor mit realistisch wirkenden – aber frei erfundenen –
/// Daten erkunden kann. **Greift nur einen leeren Store auf** und fasst nie bestehende Daten an.
///
/// Die Daten sind **relativ zum Startzeitpunkt**: befüllt werden der **aktuelle Monat** und der
/// **Vormonat** (so wirkt die Demo immer aktuell, egal wann sie gestartet wird). Alle Tagesangaben
/// bleiben ≤ 28, damit `tag(_:_:_:)` in jedem Monat ein gültiges Datum liefert.
enum Demodaten {
    typealias MonatRef = (jahr: Int, monat: Int)

    @MainActor
    static func einspielen(_ ctx: ModelContext) {
        guard istLeer(ctx) else { return }  // Sicherheitsnetz: nie in einen befüllten Store

        let heute = Date()
        let aktuell = monatVon(heute)
        let vor = monatVon(appKalender.date(byAdding: .month, value: -1, to: heute) ?? heute)
        let paar = [vor, aktuell]

        jahresEinstellungen(ctx, jahre: Set(paar.map(\.jahr)))
        einnahmen(ctx, vor: vor, aktuell: aktuell)
        betrieblicheAusgaben(ctx, paar: paar, vor: vor, aktuell: aktuell)
        privateAusgaben(ctx, paar: paar)
        lebensmittelUndEinkaeufe(ctx, vor: vor, aktuell: aktuell)
        zahlungen(ctx, paar: paar)
        aufgaben(ctx, aktuell: aktuell)
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

    private static func monatVon(_ d: Date) -> MonatRef {
        let c = appKalender.dateComponents([.year, .month], from: d)
        return (c.year ?? 2026, c.month ?? 1)
    }

    // MARK: - Bausteine

    @MainActor
    private static func jahresEinstellungen(_ ctx: ModelContext, jahre: Set<Int>) {
        // KSK ab Januar: RV 230 / KV 130 / PV 60 = 420 €/Monat; JAE 36.000 (nur Info). Erbt vorwärts.
        // Bei Monatspaaren über einen Jahreswechsel (Dez→Jan) je Jahr eigene Einstellungen.
        for j in jahre {
            let s = YearSettings(jahr: j, ustvaRhythmus: .vierteljaehrlich, estPauschalSatz: dez("0.15"))
            s.setzeKSKBetrag(monat: 1, .rv, dez("230.00"))
            s.setzeKSKBetrag(monat: 1, .kv, dez("130.00"))
            s.setzeKSKBetrag(monat: 1, .pv, dez("60.00"))
            s.setzeJAE(monat: 1, dez("36000"))
            ctx.insert(s)
        }
    }

    @MainActor
    private static func einnahmen(_ ctx: ModelContext, vor: MonatRef, aktuell: MonatRef) {
        func rn(_ n: Int) -> String { String(format: "%04d-%03d", aktuell.jahr, n) }

        // Vormonat: bezahlte Rechnung (Zufluss erst im aktuellen Monat).
        let a = dez("3200.00")
        ctx.insert(
            Income(
                kunde: "Nordstern Studio GmbH", rnNetto: a, ust: Steuer.ust(ausNetto: a),
                rechnungsdatum: tag(vor.jahr, vor.monat, 26), zahlungsdatum: tag(aktuell.jahr, aktuell.monat, 12),
                status: .bezahlt, rechnungsnummer: rn(1)))
        // Vormonat: ermäßigter Satz 7 % (Einräumung von Nutzungsrechten), bezahlt.
        let ill = dez("1500.00")
        ctx.insert(
            Income(
                kunde: "Feldpost Magazin GmbH", rnNetto: ill, ust: Steuer.ust(ausNetto: ill, satz: .satz7),
                rechnungsdatum: tag(vor.jahr, vor.monat, 18), zahlungsdatum: tag(aktuell.jahr, aktuell.monat, 6),
                status: .bezahlt, rechnungsnummer: rn(2), satz: .satz7))
        // Aktueller Monat: Mischrechnung 19 % + 7 % auf einer Rechnung, noch offen.
        let g = dez("2000.00")
        let n = dez("900.00")
        ctx.insert(
            Income(
                kunde: "Studio Ostkreuz GmbH", rnNetto: g, ust: Steuer.ust(ausNetto: g, satz: .satz19),
                rechnungsdatum: tag(aktuell.jahr, aktuell.monat, 8), zahlungsdatum: nil,
                status: .offen, rechnungsnummer: rn(3), satz: .satz19,
                rnNetto2: n, ust2: Steuer.ust(ausNetto: n, satz: .satz7), satz2: .satz7))
        // Aktueller Monat: weitere Rechnung, noch offen.
        let b = dez("3400.00")
        ctx.insert(
            Income(
                kunde: "Kranzler Digital GmbH", rnNetto: b, ust: Steuer.ust(ausNetto: b),
                rechnungsdatum: tag(aktuell.jahr, aktuell.monat, 22), zahlungsdatum: nil,
                status: .offen, rechnungsnummer: rn(4)))
    }

    @MainActor
    private static func betrieblicheAusgaben(_ ctx: ModelContext, paar: [MonatRef], vor: MonatRef, aktuell: MonatRef) {
        // Wiederkehrende SaaS/Fixkosten je Monat (betrieblich → EÜR/VSt). Tage ≤ 28.
        // (Bezeichnung, Anbieter, Brutto, VSt, Steuerart, Art, Buchungstag)
        let wiederkehrend: [(String, String, String, String, Steuerart, AusgabeArt, Int)] = [
            ("Figma Professional", "Figma", "18.00", "0.00", .reverseCharge, .subscription, 3),
            ("Adobe Creative Cloud", "Adobe", "71.40", "11.40", .inland19, .subscription, 3),
            ("GitHub Team", "GitHub", "8.00", "0.00", .reverseCharge, .subscription, 4),
            ("Anthropic Claude", "Anthropic", "18.00", "0.00", .reverseCharge, .subscription, 5),
            ("Coworking-Platz", "Spreewerk Coworking", "178.50", "28.50", .inland19, .fixkosten, 1),
        ]
        for (j, m) in paar {
            for (bez, anb, brutto, vst, art, kind, t) in wiederkehrend {
                ctx.insert(
                    ExpenseEntry(
                        datum: tag(j, m, t), bezeichnung: bez, anbieter: anb,
                        brutto: dez(brutto), vst: dez(vst), steuerart: art,
                        betrieblich: true, art: kind))
            }
        }
        // Einmalige Anschaffung (Sofortabzug): Laptop im Vormonat, netto 1.200,00.
        ctx.insert(
            ExpenseEntry(
                datum: tag(vor.jahr, vor.monat, 14), bezeichnung: "MacBook Air", anbieter: "Apple",
                brutto: dez("1428.00"), vst: dez("228.00"), steuerart: .inland19,
                betrieblich: true, art: .betriebsausgabe))
        // Einmalige 7-%-Betriebsausgabe (ermäßigt): Fachbuch im aktuellen Monat, netto 40,00 (VSt 2,80).
        ctx.insert(
            ExpenseEntry(
                datum: tag(aktuell.jahr, aktuell.monat, 9), bezeichnung: "Fachbuch Typografie",
                anbieter: "Buchhandlung",
                brutto: dez("42.80"), vst: dez("2.80"), steuerart: .inland7,
                betrieblich: true, art: .betriebsausgabe))
    }

    @MainActor
    private static func privateAusgaben(_ ctx: ModelContext, paar: [MonatRef]) {
        // Private Fixkosten/Subscriptions (betrieblich=false, vst=0): nur Liquidität, nie EÜR/VSt.
        let wiederkehrend: [(String, String, String, AusgabeArt, Int)] = [
            ("Miete Wohnung", "Hausverwaltung Spree", "1150.00", .fixkosten, 1),
            ("Strom", "Stromversorger Berlin", "78.00", .fixkosten, 1),
            ("Mobilfunk", "Mobilfunk Berlin", "39.00", .fixkosten, 15),
            ("Netflix", "Netflix", "13.99", .subscription, 8),
            ("Spotify", "Spotify", "10.99", .subscription, 8),
        ]
        for (j, m) in paar {
            for (bez, anb, brutto, art, t) in wiederkehrend {
                ctx.insert(
                    ExpenseEntry(
                        datum: tag(j, m, t), bezeichnung: bez, anbieter: anb,
                        brutto: dez(brutto), vst: 0, steuerart: .steuerfrei,
                        betrieblich: false, art: art))
            }
        }
    }

    @MainActor
    private static func lebensmittelUndEinkaeufe(_ ctx: ModelContext, vor: MonatRef, aktuell: MonatRef) {
        // Lebensmittel ~ zweiwöchentlich, wechselnde Orte/Beträge – je Monat zwei Einträge.
        let orte = ["Biomarkt Nord", "Supermarkt", "Wochenmarkt"]
        let betraege = ["52.30", "47.85", "61.40", "44.10"]
        for (i, mr) in [vor, aktuell].enumerated() {
            ctx.insert(
                GroceryEntry(datum: tag(mr.jahr, mr.monat, 9), betrag: dez(betraege[i * 2]), ort: orte[i % orte.count]))
            ctx.insert(
                GroceryEntry(
                    datum: tag(mr.jahr, mr.monat, 23), betrag: dez(betraege[i * 2 + 1]),
                    ort: orte[(i + 1) % orte.count]))
        }
        // Eine private Anschaffung im Vormonat.
        ctx.insert(
            PurchaseEntry(datum: tag(vor.jahr, vor.monat, 8), bezeichnung: "Schreibtischlampe", preis: dez("49.90")))
    }

    @MainActor
    private static func zahlungen(_ ctx: ModelContext, paar: [MonatRef]) {
        // KSK-Ist-Abbuchungen (Vorsorge-Ledger), Anfang jedes Monats.
        for (j, m) in paar {
            ctx.insert(
                TaxPayment(
                    kind: .ksk, jahr: j, faellig: tag(j, m, 1),
                    betrag: dez("420.00"), bezahlt: true, bezahltAm: tag(j, m, 1),
                    bemerkung: "KSK-Beitrag"))
        }
    }

    @MainActor
    private static func aufgaben(_ ctx: ModelContext, aktuell: MonatRef) {
        ctx.insert(
            MonthlyTask(
                titel: "UStVA einreichen", monat: tag(aktuell.jahr, aktuell.monat, 10),
                intervall: .quartalsweise, faelligTag: 10, quartalsMonate: [1, 4, 7, 10]))
        ctx.insert(
            MonthlyTask(
                titel: "Belege ablegen & prüfen", monat: tag(aktuell.jahr, aktuell.monat, 28),
                intervall: .monatlich, faelligTag: 28))
        ctx.insert(
            MonthlyTask(
                titel: "EÜR vorbereiten", monat: tag(aktuell.jahr, 12, 28),
                intervall: .jaehrlich, faelligTag: 28, quartalsMonate: [12]))
    }
}
