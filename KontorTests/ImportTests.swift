import Testing
import Foundation
import SwiftData
@testable import Kontor

@MainActor
struct ImportTests {
    /// Geteilt: siehe Testhelfer.swift (das Schema stand hier 5x wortgleich).
    private func container() throws -> ModelContainer { try testContainer() }

    /// Bankbuchung-Fabrik für die Tests.
    private func buchung(_ betrag: String, text: String = "KARTENZAHLUNG", name: String = "Test Haendler",
                         zweck: String = "", glaeubiger: String = "", kundenref: String = "", monat: Int = 6, am tagNr: Int = 10) -> Bankbuchung {
        Bankbuchung(buchungstag: tag(2026, monat, tagNr), betrag: dez(betrag), buchungstext: text, verwendungszweck: zweck,
                    gegenpartei: name, iban: "", glaeubigerID: glaeubiger, mandatsreferenz: "", kundenreferenz: kundenref, waehrung: "EUR")
    }

    // MARK: - Vorschlag

    @Test func vorschlagAusGelernterRegel() throws {
        let c = try container()
        c.mainContext.insert(ZuordnungsRegel(schluessel: "biomarkt nord", kategorie: .lebensmittel, betrieblich: false))
        try c.mainContext.save()
        let regeln = try c.mainContext.fetch(FetchDescriptor<ZuordnungsRegel>())
        let z = ImportVorschlag.fuer(buchung("-12,34", name: "BIOMARKT NORD/Berlin/DE"), regeln: regeln)
        #expect(z.kategorie == .lebensmittel)
        #expect(z.betrieblich == false)
    }

    @Test func vorschlagHeuristiken() {
        #expect(ImportVorschlag.fuer(buchung("-100", text: "ÜBERTRAG (ÜBERWEISUNG)"), regeln: []).kategorie == .ignorieren)
        #expect(ImportVorschlag.fuer(buchung("3168,38", text: "GUTSCHRIFT ÜBERWEISUNG"), regeln: []).kategorie == .einnahme)
        let unbekannt = ImportVorschlag.fuer(buchung("-55,84", name: "DROGERIE NORD"), regeln: [])
        #expect(unbekannt.kategorie == .anschaffung && unbekannt.betrieblich == false)
    }

    // MARK: - Anwenden

    @Test func betriebsausgabeAngelegtMitAutoVSt() throws {
        let c = try container()
        let b = buchung("-119,00", name: "FIGMA/San Francisco/US")
        let nachricht = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .betriebsausgabe, betrieblich: true, steuerart: .inland19),
                                                     aktion: .neu, c.mainContext)
        #expect(nachricht == "Ausgabe angelegt")
        let ausgaben = try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>())
        #expect(ausgaben.count == 1)
        #expect(ausgaben.first?.brutto == dez("119"))
        #expect(ausgaben.first?.vst == dez("19"))           // 119 inland19 → 19,00 (Server rechnet)
        #expect(ausgaben.first?.betrieblich == true)
        #expect(ImportAnwendung.schonVerarbeitet(b, c.mainContext))   // protokolliert
    }

    /// Regression: „private Betriebsausgabe" darf nicht entstehen. Selbst wenn die Zuordnung
    /// (z. B. durch einen stehengebliebenen UI-Zustand) betrieblich:false trägt, muss die
    /// gebuchte Betriebsausgabe betrieblich sein – inkl. korrekter VSt und gelernter Regel.
    @Test func betriebsausgabeNieAlsPrivatGebucht() throws {
        let c = try container()
        let b = buchung("-119,00", name: "FIGMA/San Francisco/US", glaeubiger: "DE00ZZZFIGMA")
        _ = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .betriebsausgabe, betrieblich: false, steuerart: .inland19),
                                         aktion: .neu, c.mainContext)
        let e = try #require(try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>()).first)
        #expect(e.betrieblich == true)                       // korrigiert: keine private Betriebsausgabe
        #expect(e.vst == dez("19"))                          // betrieblich → VSt wird gezogen (nicht 0)
        // die gelernte Regel darf den Fehler nicht verewigen
        let regel = try #require(try c.mainContext.fetch(FetchDescriptor<ZuordnungsRegel>()).first { $0.kategorie == .betriebsausgabe })
        #expect(regel.betrieblich == true)
    }

    @Test func vorschlagNormalisiertFehlerhafteRegel() throws {
        let c = try container()
        // Eine (aus der alten Buggy-Version) fehlerhaft gelernte Regel: Betriebsausgabe + privat.
        c.mainContext.insert(ZuordnungsRegel(schluessel: "gl:DE00ZZZFIGMA", kategorie: .betriebsausgabe, betrieblich: false))
        try c.mainContext.save()
        let regeln = try c.mainContext.fetch(FetchDescriptor<ZuordnungsRegel>())
        let z = ImportVorschlag.fuer(buchung("-119,00", name: "FIGMA/San Francisco/US", glaeubiger: "DE00ZZZFIGMA"), regeln: regeln)
        #expect(z.kategorie == .betriebsausgabe && z.betrieblich == true)   // Vorschlag ist normalisiert
    }

    /// Regression: Die Invariante „eine Betriebsausgabe ist immer betrieblich" gehört an den
    /// **Import** (`Zuordnung.normalisiert`) – nicht in einen Nachtrag, der beim App-Start
    /// über den ganzen Bestand läuft. Der frühere `PrivatBetriebsausgabeNachtrag` tat genau
    /// das und überschrieb dabei auch neue, absichtlich private Einträge samt erfundener
    /// Vorsteuer; der Nutzer konnte seine Eingabe nicht halten. Er ist entfernt – dieser Test
    /// pinnt, dass der Import die Invariante trotzdem selbst durchsetzt.
    @Test func importErzwingtBetrieblichOhneNachtrag() throws {
        let c = try container()
        let b = buchung("-119,00", name: "ADOBE/Dublin/IE", glaeubiger: "DE00ZZZADOBE")
        _ = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .betriebsausgabe, betrieblich: false,
                                                      steuerart: .inland19),
                                         aktion: .neu, c.mainContext)
        let e = try #require(try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>()).first)
        #expect(e.betrieblich == true)      // vom Import normalisiert, nicht von einem Nachtrag
        #expect(e.vst == dez("19"))
    }

    /// Eine bewusst privat gestellte Ausgabe muss privat bleiben – auch mit `art:.betriebsausgabe`
    /// (die Art steuert nur die Ansicht, `betrieblich` die EÜR). Genau das kippte der Nachtrag
    /// bei jedem Start zurück.
    @Test func privatGestellteAusgabeBleibtPrivat() throws {
        let c = try container()
        c.mainContext.insert(ExpenseEntry(datum: tag(2026, 6, 1), bezeichnung: "Sneaker", anbieter: "Shop",
                                          brutto: dez("119"), vst: 0, steuerart: .inland19,
                                          betrieblich: false, art: .betriebsausgabe))
        try c.mainContext.save()
        let e = try #require(try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>()).first)
        #expect(e.betrieblich == false)
        #expect(e.vst == 0)
        // …und sie bleibt aus EÜR und Vorsteuer draußen.
        let p = [e.posten]
        #expect(Steuer.euerGewinn(einnahmen: [], ausgaben: p, jahr: 2026) == 0)
        #expect(Steuer.vorsteuer(p, in: Periode.quartal(2026, 2)) == 0)
    }

    @Test func privateFixkostenAlsBuchung() throws {
        let c = try container()
        let b = buchung("-725,00", name: "Hausverwaltung Spree")
        let nachricht = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .fixkosten, betrieblich: false),
                                                     aktion: .neu, c.mainContext)
        #expect(nachricht == "Ausgabe angelegt")
        let ausgaben = try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>())
        #expect(ausgaben.count == 1)
        let e = ausgaben[0]
        #expect(e.artEffektiv == .fixkosten && e.betrieblich == false && e.vst == 0)   // privat: Liquidität, keine VSt/EÜR
        #expect(ImportAnwendung.schonVerarbeitet(b, c.mainContext))
    }

    @Test func lerntAusEntscheidung() throws {
        let c = try container()
        let b1 = buchung("-12,34", name: "BIOMARKT NORD/Berlin/DE", kundenref: "REF1")
        _ = try ImportAnwendung.anwenden(b1, Zuordnung(kategorie: .lebensmittel, betrieblich: false), aktion: .neu, c.mainContext)
        // Neue ALDI-Buchung (anderer Tag/Ref) → Vorschlag kommt jetzt aus der gelernten Regel.
        let regeln = try c.mainContext.fetch(FetchDescriptor<ZuordnungsRegel>())
        let z = ImportVorschlag.fuer(buchung("-9,99", name: "BIOMARKT NORD/Berlin/DE", kundenref: "REF2", am: 20), regeln: regeln)
        #expect(z.kategorie == .lebensmittel)
    }

    @Test func einnahmeMatchUndBezahlt() throws {
        let c = try container()
        c.mainContext.insert(Income(kunde: "Kunde X", rnNetto: dez("100"), ust: dez("19"),
                                    rechnungsdatum: tag(2026, 6, 1), status: .offen))
        try c.mainContext.save()
        let b = buchung("119,00", text: "GUTSCHRIFT ÜBERWEISUNG", name: "Kunde X", am: 15)
        let z = Zuordnung(kategorie: .einnahme, betrieblich: true)
        let ziel = ImportAnwendung.ziel(b, z, c.mainContext)
        #expect(ziel != nil)                                  // offene Rechnung über Betrag gefunden
        let nachricht = try ImportAnwendung.anwenden(b, z, aktion: .ueberschreiben(ziel!), c.mainContext)
        #expect(nachricht == "Zahlung zugeordnet")
        let inc = try #require(try c.mainContext.fetch(FetchDescriptor<Income>()).first)
        #expect(inc.status == .bezahlt)
        #expect(inc.zahlungsdatum == tag(2026, 6, 15))        // Zahldatum = Buchungsdatum
    }

    @Test func dubletteWirdGefunden() throws {
        let c = try container()
        // Schon gebuchte Ausgabe – dieselbe Bankzeile darf sie als Ziel erkennen (überschreiben/überspringen).
        c.mainContext.insert(ExpenseEntry(datum: tag(2026, 6, 10), bezeichnung: "Figma", anbieter: "Figma",
                                          brutto: dez("35"), vst: 0, steuerart: .reverseCharge))
        try c.mainContext.save()
        let b = buchung("-35,00", name: "FIGMA/San Francisco/US", am: 12)   // 2 Tage Differenz ≤ Toleranz
        let ziel = ImportAnwendung.ziel(b, Zuordnung(kategorie: .betriebsausgabe, betrieblich: true, steuerart: .reverseCharge), c.mainContext)
        #expect(ziel != nil)
    }

    @Test func ausgabeMatchUeberRechnungsnummer() throws {
        let c = try container()
        // Per PDF erfasste Ausgabe mit Rechnungsnummer, Zahlung kommt erst Wochen später.
        c.mainContext.insert(ExpenseEntry(datum: tag(2026, 6, 1), bezeichnung: "Adobe", anbieter: "Adobe",
                                          brutto: dez("119"), vst: dez("19"), steuerart: .inland19,
                                          rechnungsnummer: "RE-2026-0042"))
        try c.mainContext.save()
        let b = buchung("-119,00", name: "ADOBE/Dublin/IE", zweck: "Rechnung RE-2026-0042 Danke", am: 20) // 19 Tage später
        let z = Zuordnung(kategorie: .betriebsausgabe, betrieblich: true, steuerart: .inland19)
        let ziel = ImportAnwendung.ziel(b, z, c.mainContext)
        #expect(ziel != nil)                                  // über RN gefunden, trotz Datumsabstand > 5 Tage
        _ = try ImportAnwendung.anwenden(b, z, aktion: .ueberschreiben(ziel!), c.mainContext)
        #expect(try c.mainContext.fetchCount(FetchDescriptor<ExpenseEntry>()) == 1)   // keine Dublette
        let e = try #require(try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>()).first)
        #expect(e.zahlungsdatum == tag(2026, 6, 20))          // Zahltag festgehalten
    }

    @Test func ausgabeMatchEngesFenster() throws {
        let c = try container()
        c.mainContext.insert(ExpenseEntry(datum: tag(2026, 6, 1), bezeichnung: "Hosting", anbieter: "Hosting",
                                          brutto: dez("50"), vst: 0, steuerart: .reverseCharge))
        try c.mainContext.save()
        let z = Zuordnung(kategorie: .betriebsausgabe, betrieblich: true, steuerart: .reverseCharge)
        // 4 Tage Abstand → innerhalb des engen Fensters (5 Tage)
        #expect(ImportAnwendung.ziel(buchung("-50,00", name: "HOSTING", am: 5), z, c.mainContext) != nil)
        // 19 Tage Abstand und keine RN → kein Treffer (früher matchte das 30-Tage-Fenster fälschlich)
        #expect(ImportAnwendung.ziel(buchung("-50,00", name: "HOSTING", am: 20), z, c.mainContext) == nil)
    }

    /// Regression: die monatlich gleiche Miete darf im Folgemonat NICHT den Vormonatseintrag
    /// als „Ziel" finden – sonst würde „Überschreiben" die Vormonats-Ausgabe in den neuen Monat
    /// verschieben und der Vormonat verlöre sie.
    @Test func wiederkehrendeMieteUeberschreibtVormonatNicht() throws {
        let c = try container()
        let z = Zuordnung(kategorie: .fixkosten, betrieblich: false)
        let juni = buchung("-1200,00", name: "Hausverwaltung Meier", monat: 6, am: 1)
        #expect(ImportAnwendung.ziel(juni, z, c.mainContext) == nil)          // noch nichts vorhanden
        _ = try ImportAnwendung.anwenden(juni, z, aktion: .neu, c.mainContext)
        // Juli-Miete: gleicher Betrag, ~30 Tage später → darf den Juni-Eintrag NICHT treffen
        let juli = buchung("-1200,00", name: "Hausverwaltung Meier", monat: 7, am: 1)
        #expect(ImportAnwendung.ziel(juli, z, c.mainContext) == nil)          // Kern-Regression
        _ = try ImportAnwendung.anwenden(juli, z, aktion: .neu, c.mainContext)
        let ausgaben = try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>())
        #expect(ausgaben.count == 2)                                          // beide Monate bleiben getrennt
        #expect(ausgaben.contains { $0.datum == tag(2026, 6, 1) })
        #expect(ausgaben.contains { $0.datum == tag(2026, 7, 1) })
    }

    @Test func ueberspringenLegtNichtsAn() throws {
        let c = try container()
        let b = buchung("-3,00", name: "Parkhaus City")
        _ = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .anschaffung, betrieblich: false), aktion: .ueberspringen, c.mainContext)
        #expect(try c.mainContext.fetchCount(FetchDescriptor<PurchaseEntry>()) == 0)
        #expect(ImportAnwendung.schonVerarbeitet(b, c.mainContext))   // trotzdem als erledigt gemerkt
    }

    @Test func ueberspringenLerntKeineRegel() throws {
        let c = try container()
        let b = buchung("-7,00", name: "Unbekannt XY")
        _ = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .anschaffung, betrieblich: false), aktion: .ueberspringen, c.mainContext)
        #expect(try c.mainContext.fetchCount(FetchDescriptor<ZuordnungsRegel>()) == 0)   // Skip lehrt nicht …
        #expect(ImportAnwendung.schonVerarbeitet(b, c.mainContext))                       // … wird aber protokolliert
    }

    // MARK: - Start-Regeln (generischer SaaS-Seed)

    @Test func startRegelnSeedIdempotentUndVorschlag() throws {
        let c = try container()
        ZuordnungsRegel.seedeStartRegeln(c.mainContext)
        let n1 = try c.mainContext.fetchCount(FetchDescriptor<ZuordnungsRegel>())
        #expect(n1 == ZuordnungsRegel.startRegeln.count)
        ZuordnungsRegel.seedeStartRegeln(c.mainContext)             // erneut → keine Duplikate
        #expect(try c.mainContext.fetchCount(FetchDescriptor<ZuordnungsRegel>()) == n1)

        let regeln = try c.mainContext.fetch(FetchDescriptor<ZuordnungsRegel>())
        // KSK-Beitrag → Vorsorge-Zahlung
        #expect(ImportVorschlag.fuer(buchung("-420,00", name: "Kuenstlersozialkasse"), regeln: regeln).kategorie == .ksk)
        // Auslands-SaaS → Betriebsausgabe, Reverse-Charge
        let figma = ImportVorschlag.fuer(buchung("-35,00", name: "FIGMA/760 Market Street/US"), regeln: regeln)
        #expect(figma.kategorie == .betriebsausgabe && figma.betrieblich && figma.steuerart == .reverseCharge)
        let anthropic = ImportVorschlag.fuer(buchung("-18,00", name: "ANTHROPIC. CLAUDE SUB/San Francisco/US"), regeln: regeln)
        #expect(anthropic.kategorie == .betriebsausgabe && anthropic.betrieblich && anthropic.steuerart == .reverseCharge)
    }

    // MARK: - KSK / Steuern

    @Test func kskBuchungWirdAlsZahlungGebucht() throws {
        let c = try container()
        // KSK-Abbuchung wird als Ist-Zahlung gebucht (Betrag = Beleg); Soll bleibt der Beitragssatz.
        let b = buchung("-420.00", name: "Kuenstlersozialkasse", am: 1)
        let nachricht = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .ksk, betrieblich: false), aktion: .neu, c.mainContext)
        #expect(nachricht == "KSK-Zahlung angelegt")
        #expect(try c.mainContext.fetchCount(FetchDescriptor<ExpenseEntry>()) == 0)   // keine EÜR-Buchung
        let t = try #require(try c.mainContext.fetch(FetchDescriptor<TaxPayment>()).first)
        #expect(t.kind == .ksk && t.bezahlt && t.betrag == dez("420.00") && t.jahr == 2026)
        #expect(ImportAnwendung.schonVerarbeitet(b, c.mainContext))                   // protokolliert
    }

    @Test func steuererstattungAlsNegativeZahlung() throws {
        let c = try container()
        // Eingang vom Finanzamt (positiv) → Steuererstattung = negativer TaxPayment.
        let b = buchung("305.77", text: "GUTSCHRIFT", name: "Finanzamt Berlin", am: 12)
        let nachricht = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .steuererstattung, betrieblich: false, steuerKind: .ustVz),
                                                     aktion: .neu, c.mainContext)
        #expect(nachricht == "Steuererstattung angelegt")
        let t = try #require(try c.mainContext.fetch(FetchDescriptor<TaxPayment>()).first)
        #expect(t.kind == .ustVz && t.betrag == dez("-305.77") && t.bezahlt && t.jahr == 2026)
    }

    @Test func finanzamtVorschlagRichtungsabhaengig() throws {
        let c = try container()
        // Die Finanzamt-Regel deckt beide Richtungen ab – egal, welche zuletzt gelernt wurde.
        c.mainContext.insert(ZuordnungsRegel(schluessel: "finanzamt berlin", kategorie: .steuer,
                                             betrieblich: false, steuerart: .inland19, steuerKind: .ustVz))
        try c.mainContext.save()
        var regeln = try c.mainContext.fetch(FetchDescriptor<ZuordnungsRegel>())
        #expect(ImportVorschlag.fuer(buchung("-980.00", name: "Finanzamt Berlin"), regeln: regeln).kategorie == .steuer)         // Ausgang → Zahlung
        #expect(ImportVorschlag.fuer(buchung("305.77", name: "Finanzamt Berlin"), regeln: regeln).kategorie == .steuererstattung) // Eingang → Erstattung

        // Auch wenn die Regel als Erstattung gelernt wurde, bleibt ein Ausgang eine Zahlung.
        regeln[0].kategorie = .steuererstattung
        #expect(ImportVorschlag.fuer(buchung("-980.00", name: "Finanzamt Berlin"), regeln: regeln).kategorie == .steuer)
        #expect(ImportVorschlag.fuer(buchung("305.77", name: "Finanzamt Berlin"), regeln: regeln).kategorie == .steuererstattung)
    }

    @Test func steuerzahlungFuelltGeplantenTermin() throws {
        let c = try container()
        c.mainContext.insert(TaxPayment(kind: .estVz, jahr: 2026, faellig: tag(2026, 6, 10)))  // geplant, ohne Betrag
        try c.mainContext.save()
        let b = buchung("-1500,00", name: "Finanzamt Berlin", am: 10)
        let z = Zuordnung(kategorie: .steuer, betrieblich: false, steuerKind: .estVz)
        let ziel = ImportAnwendung.ziel(b, z, c.mainContext)
        #expect(ziel != nil)                                    // offener Termin gefunden
        let nachricht = try ImportAnwendung.anwenden(b, z, aktion: .ueberschreiben(ziel!), c.mainContext)
        #expect(nachricht == "Steuerzahlung zugeordnet")
        let t = try #require(try c.mainContext.fetch(FetchDescriptor<TaxPayment>()).first)
        #expect(t.bezahlt && t.betrag == dez("1500") && t.bezahltAm == tag(2026, 6, 10))
        #expect(try c.mainContext.fetchCount(FetchDescriptor<TaxPayment>()) == 1)   // kein Duplikat
    }

    @Test func steuerzahlungNeuOhneTermin() throws {
        let c = try container()
        let b = buchung("-980,00", name: "Finanzamt Berlin", am: 10)
        _ = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .steuer, betrieblich: false, steuerKind: .ustVz),
                                         aktion: .neu, c.mainContext)
        let t = try #require(try c.mainContext.fetch(FetchDescriptor<TaxPayment>()).first)
        #expect(t.kind == .ustVz && t.bezahlt && t.betrag == dez("980") && t.jahr == 2026)
    }

    @Test func lerntSteuerKind() throws {
        let c = try container()
        let b = buchung("-980,00", name: "Finanzamt Berlin", glaeubiger: "DEFA123", am: 10)
        _ = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .steuer, betrieblich: false, steuerKind: .estVz),
                                         aktion: .neu, c.mainContext)
        let regeln = try c.mainContext.fetch(FetchDescriptor<ZuordnungsRegel>())
        let z = ImportVorschlag.fuer(buchung("-1200,00", name: "Finanzamt Berlin", glaeubiger: "DEFA123", am: 20), regeln: regeln)
        #expect(z.kategorie == .steuer && z.steuerKind == .estVz)
    }

    @Test func reTriageIgnoriertDannKsk() throws {
        let c = try container()
        let b = buchung("-420.00", name: "Kuenstlersozialkasse", kundenref: "KSKREF", am: 1)
        _ = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .ignorieren, betrieblich: false), aktion: .neu, c.mainContext)
        // … dieselbe Buchung später als KSK neu zuordnen (Re-Triage)
        _ = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .ksk, betrieblich: false), aktion: .neu, c.mainContext)
        #expect(try c.mainContext.fetchCount(FetchDescriptor<ImportBuchung>()) == 1)     // gleiche Buchung, kein Duplikat
        #expect(try c.mainContext.fetch(FetchDescriptor<ImportBuchung>()).first?.kategorie == .ksk)  // Protokoll aktualisiert
    }

    @Test func erstattungAlsNegativeAnschaffung() throws {
        let c = try container()
        let b = buchung("45.00", text: "GUTSCHRIFT", name: "Amazon Retoure", am: 12)   // Eingang (positiv)
        let nachricht = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .erstattung, betrieblich: false), aktion: .neu, c.mainContext)
        #expect(nachricht == "Gutschrift angelegt")
        let p = try #require(try c.mainContext.fetch(FetchDescriptor<PurchaseEntry>()).first)
        #expect(p.preis == dez("-45"))                  // negativ → mindert die Einkäufe-Summe
        #expect(p.bezeichnung.hasPrefix("Erstattung"))
    }

    @Test func ustVzImJanuarZaehltZumVorjahr() throws {
        let c = try container()
        let b = buchung("-1200.00", name: "Finanzamt Berlin", monat: 1, am: 12)   // Januar 2026
        _ = try ImportAnwendung.anwenden(b, Zuordnung(kategorie: .steuer, betrieblich: false, steuerKind: .ustVz),
                                         aktion: .neu, c.mainContext)
        let t = try #require(try c.mainContext.fetch(FetchDescriptor<TaxPayment>()).first)
        #expect(t.kind == .ustVz && t.jahr == 2025)     // Jan 2026 USt-VZ → Q4 2025
        #expect(t.bezahltAm == tag(2026, 1, 12))        // tatsächliches Zahldatum bleibt
        #expect(t.bemerkung == "USt-VA Q4 2025")
    }
}
