import Testing
import Foundation
import SwiftData
@testable import Kontor

/// Tests für den MCP-Server: JSON-RPC-Dispatch, tokensparende Engine-Antworten,
/// CSV-Listen und die beiden Schreib-Tools. Läuft rein in-memory.
@MainActor
struct MCPServerTests {

    private func container() throws -> ModelContainer {
        let c = try ModelContainer(
            for: YearSettings.self, ExpenseEntry.self, Vorlage.self,
                Income.self, MonthlyTask.self,
                GroceryEntry.self, PurchaseEntry.self, TaxPayment.self,
                ZuordnungsRegel.self, ImportBuchung.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return c
    }

    /// Minimaldaten: 1 bezahlte Einnahme (Feb 2026), 1 betriebliche Ausgabe (Feb 2026), YearSettings 2026.
    private func seed(_ c: ModelContainer) throws {
        let ctx = c.mainContext
        ctx.insert(YearSettings(jahr: 2026, estPauschalSatz: dez("0.15")))
        ctx.insert(Income(kunde: "Testkunde", rnNetto: dez("1000"), ust: dez("190"),
                          rechnungsdatum: tag(2026, 2, 15), zahlungsdatum: tag(2026, 2, 20),
                          status: .bezahlt, rechnungsnummer: "R-1"))
        ctx.insert(ExpenseEntry(datum: tag(2026, 2, 10), bezeichnung: "Hosting", anbieter: "Netcup",
                                brutto: dez("119"), vst: dez("19"), steuerart: .inland19))
        try ctx.save()
    }

    /// JSON-RPC-Aufruf → geparste Antwort.
    private func ruf(_ c: ModelContainer, _ methode: String, _ params: [String: Any] = [:]) async -> [String: Any] {
        var msg: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": methode]
        if !params.isEmpty { msg["params"] = params }
        let data = try! JSONSerialization.data(withJSONObject: msg)
        let antwort = await MCPProtokoll.verarbeite(data, container: c)!
        return (try! JSONSerialization.jsonObject(with: antwort)) as! [String: Any]
    }

    /// Text aus einem tools/call- bzw. resources/read-Ergebnis.
    private func toolText(_ antwort: [String: Any]) -> String {
        let r = antwort["result"] as! [String: Any]
        let content = r["content"] as! [[String: Any]]
        return content[0]["text"] as! String
    }

    // MARK: - Protokoll

    @Test func initializeUndToolsListe() async throws {
        let c = try container(); try seed(c)
        let init0 = await ruf(c, "initialize")
        let info = (init0["result"] as! [String: Any])["serverInfo"] as! [String: Any]
        #expect(info["name"] as? String == "Kontor")

        let liste = await ruf(c, "tools/list")
        let tools = (liste["result"] as! [String: Any])["tools"] as! [[String: Any]]
        #expect(tools.count == 9)
        let namen = Set(tools.compactMap { $0["name"] as? String })
        #expect(namen.contains("kontor_uebersicht"))
        #expect(namen.contains("kontor_anlegen"))
        #expect(namen.contains("kontor_aktualisieren"))
        #expect(namen.contains("kontor_loeschen"))
        #expect(namen.contains("kontor_beleg"))
    }

    // MARK: - Lesen (Engine-Zahlen)

    @Test func eurEngineZahlen() async throws {
        let c = try container(); try seed(c)
        let text = toolText(await ruf(c, "tools/call",
            ["name": "kontor_eur", "arguments": ["jahr": 2026]]))
        // Einnahmen netto 1000, Betriebsausgaben netto 100 ⇒ Gewinn 900.
        #expect(text.contains("Einnahmen (bezahlt, netto):  1000.00"))
        #expect(text.contains("Betriebsausgaben (netto):    100.00"))
        #expect(text.contains("Gewinn:                      900.00"))
    }

    @Test func ustvaZahllast() async throws {
        let c = try container(); try seed(c)
        let text = toolText(await ruf(c, "tools/call",
            ["name": "kontor_ustva", "arguments": ["jahr": 2026, "quartal": 1]]))
        // KZ81 1000, USt 190, KZ66 19 ⇒ Zahllast 171.
        #expect(text.contains("KZ81 (Netto 19 %):           1000.00"))
        #expect(text.contains("KZ86 (Netto 7 %):"))
        #expect(text.contains("KZ66 (Vorsteuer Inland):     19.00"))
        #expect(text.contains("Zahllast (KZ83):             171.00"))
    }

    @Test func listeEinnahmenAlsCSV() async throws {
        let c = try container(); try seed(c)
        let text = toolText(await ruf(c, "tools/call",
            ["name": "kontor_liste", "arguments": ["typ": "einnahmen", "jahr": 2026]]))
        let zeilen = text.split(separator: "\n")
        #expect(zeilen.first == "datum;rechnungsnummer;kunde;netto;ust;satz;netto2;ust2;satz2;brutto;status;zahlungsdatum;beleg")
        #expect(text.contains("2026-02-15;R-1;Testkunde;1000.00;190.00;satz19;0.00;0.00;;1190.00;bezahlt;2026-02-20"))
    }

    @Test func listeStammdatenUndPrivat() async throws {
        let c = try container(); try seed(c)
        let ctx = c.mainContext
        ctx.insert(ExpenseEntry(datum: tag(2026, 2, 1), bezeichnung: "Miete Büro", anbieter: "",
                                brutto: dez("600"), vst: 0, steuerart: .steuerfrei, betrieblich: true, art: .fixkosten))
        ctx.insert(GroceryEntry(datum: tag(2026, 2, 3), betrag: dez("42.50"), ort: "Aldi"))
        ctx.insert(PurchaseEntry(datum: tag(2026, 2, 8), bezeichnung: "Tastatur", preis: dez("89.00")))
        ctx.insert(MonthlyTask(titel: "UStVA Q1", monat: tag(2026, 2, 10), intervall: .quartalsweise))
        try ctx.save()

        let fix = toolText(await ruf(c, "tools/call", ["name": "kontor_liste", "arguments": ["typ": "fixkosten", "jahr": 2026]]))
        #expect(fix.contains("datum;bezeichnung;anbieter;brutto;vst;netto;steuerart;betrieblich;beleg"))
        #expect(fix.contains("2026-02-01;Miete Büro;;600.00"))

        let lm = toolText(await ruf(c, "tools/call", ["name": "kontor_liste", "arguments": ["typ": "lebensmittel", "jahr": 2026]]))
        #expect(lm.contains("2026-02-03;Aldi;42.50"))

        let ek = toolText(await ruf(c, "tools/call", ["name": "kontor_liste", "arguments": ["typ": "einkaeufe", "jahr": 2026]]))
        #expect(ek.contains("2026-02-08;Tastatur;89.00"))

        let auf = toolText(await ruf(c, "tools/call", ["name": "kontor_liste", "arguments": ["typ": "aufgaben", "jahr": 2026, "monat": 2]]))
        #expect(auf.contains("2026-02-10;UStVA Q1;quartalsweise;nein;1"))
    }

    @Test func listeKskMonatswerte() async throws {
        let c = try container(); try seed(c)
        let s = try c.mainContext.fetch(FetchDescriptor<YearSettings>()).first { $0.jahr == 2026 }!
        s.setzeKSKBetrag(monat: 2, .rv, dez("230.00"))
        s.setzeKSKBetrag(monat: 2, .kv, dez("130.00"))
        s.setzeKSKBetrag(monat: 2, .pv, dez("60.00"))
        s.setzeJAE(monat: 2, dez("36000"))
        try c.mainContext.save()

        let ksk = toolText(await ruf(c, "tools/call", ["name": "kontor_liste", "arguments": ["typ": "ksk", "jahr": 2026, "monat": 2]]))
        #expect(ksk.contains("jahr;monat;kv;rv;pv;jae;summe"))
        #expect(ksk.contains("2026;2;130.00;230.00;60.00;36000.00;420.00"))
    }

    @Test func unbekannterTypMeldetFehler() async throws {
        let c = try container(); try seed(c)
        let antwort = await ruf(c, "tools/call", ["name": "kontor_liste", "arguments": ["typ": "quatsch"]])
        let r = antwort["result"] as! [String: Any]
        #expect(r["isError"] as? Bool == true)
    }

    // MARK: - Resources

    @Test func ressourceEur() async throws {
        let c = try container(); try seed(c)
        let antwort = await ruf(c, "resources/read", ["uri": "kontor://eur/2026"])
        let contents = (antwort["result"] as! [String: Any])["contents"] as! [[String: Any]]
        let text = contents[0]["text"] as! String
        #expect(text.contains("EÜR 2026"))
        #expect(text.contains("Gewinn:                      900.00"))
    }

    // MARK: - Schreiben (generisch)

    @Test func anlegenAusgabeMitAutoVorsteuer() async throws {
        let c = try container(); try seed(c)
        let text = toolText(await ruf(c, "tools/call", ["name": "kontor_anlegen", "arguments": [
            "typ": "ausgaben",
            "felder": ["datum": "2026-03-01", "bezeichnung": "Domain", "brutto": "11.90", "steuerart": "inland19"],
        ]]))
        #expect(text.contains("Angelegt (ausgaben)"))
        let neu = try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>()).first { $0.bezeichnung == "Domain" }
        #expect(neu?.vst == dez("1.90"))   // 11.90 − 11.90/1.19
        #expect(neu?.netto == dez("10.00"))
        #expect(neu?.artEffektiv == .betriebsausgabe)
    }

    @Test func anlegenAusgabe7ProzentAutoVorsteuer() async throws {
        let c = try container(); try seed(c)
        _ = await ruf(c, "tools/call", ["name": "kontor_anlegen", "arguments": [
            "typ": "ausgaben",
            "felder": ["datum": "2026-04-09", "bezeichnung": "Fachbuch", "brutto": "42.80", "steuerart": "inland7"],
        ]])
        let neu = try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>()).first { $0.bezeichnung == "Fachbuch" }
        #expect(neu?.steuerart == .inland7)
        #expect(neu?.vst == dez("2.80") && neu?.netto == dez("40.00"))   // 42,80 − 42,80/1,07
    }

    @Test func anlegenEinnahmeMitSatzUndMischung() async throws {
        let c = try container(); try seed(c)
        _ = await ruf(c, "tools/call", ["name": "kontor_anlegen", "arguments": [
            "typ": "einnahmen",
            "felder": ["kunde": "Illu", "rnNetto": "1000", "ust": "70", "rechnungsdatum": "2026-03-01",
                       "satz": "satz7", "rnNetto2": "500", "ust2": "95", "satz2": "satz19"],
        ]])
        let inc = try c.mainContext.fetch(FetchDescriptor<Income>()).first { $0.kunde == "Illu" }
        #expect(inc?.satzEffektiv == .satz7)
        #expect(inc?.satz2 == .satz19 && inc?.rnNetto2 == dez("500") && inc?.ust2 == dez("95"))
        #expect(inc?.brutto == dez("1665"))   // 1000+70 + 500+95
    }

    @Test func anlegenInAllenModulen() async throws {
        let c = try container(); try seed(c)
        let faelle: [(String, [String: Any], () throws -> Bool)] = [
            ("subscriptions", ["bezeichnung": "Figma", "betrag": "15", "datum": "2026-01-15", "steuerart": "reverseCharge"],
             { try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>()).contains { $0.bezeichnung == "Figma" && $0.artEffektiv == .subscription } }),
            ("fixkosten", ["bezeichnung": "Internet", "betrag": "40", "datum": "2026-01-01", "betrieblich": true],
             { try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>()).contains { $0.bezeichnung == "Internet" && $0.artEffektiv == .fixkosten } }),
            ("vorlagen", ["bezeichnung": "Strom", "betrag": "60"],
             { try c.mainContext.fetch(FetchDescriptor<Vorlage>()).contains { $0.bezeichnung == "Strom" } }),
            ("zahlungen", ["kind": "ustVz", "jahr": 2026, "faellig": "2026-04-10", "betrag": "171", "bezahlt": true],
             { try c.mainContext.fetch(FetchDescriptor<TaxPayment>()).contains { $0.kind == .ustVz && $0.betrag == dez("171") } }),
            ("aufgaben", ["titel": "Beleg ablegen", "monat": "2026-06-01", "intervall": "monatlich"],
             { try c.mainContext.fetch(FetchDescriptor<MonthlyTask>()).contains { $0.titel == "Beleg ablegen" } }),
            ("lebensmittel", ["datum": "2026-06-10", "betrag": "23.45", "ort": "Rewe"],
             { try c.mainContext.fetch(FetchDescriptor<GroceryEntry>()).contains { $0.ort == "Rewe" } }),
            ("einkaeufe", ["datum": "2026-06-11", "bezeichnung": "Maus", "preis": "29"],
             { try c.mainContext.fetch(FetchDescriptor<PurchaseEntry>()).contains { $0.bezeichnung == "Maus" } }),
        ]
        for (typ, felder, pruefung) in faelle {
            let antwort = await ruf(c, "tools/call", ["name": "kontor_anlegen", "arguments": ["typ": typ, "felder": felder]])
            #expect((antwort["result"] as! [String: Any])["isError"] as? Bool == false, "anlegen \(typ)")
            #expect(try pruefung(), "Datensatz \(typ) nicht gefunden")
        }
    }

    @Test func aktualisierenUndLoeschenUeberId() async throws {
        let c = try container(); try seed(c)
        // Offene Rechnung anlegen, id via mit_id holen, auf bezahlt setzen, dann löschen.
        c.mainContext.insert(Income(kunde: "Offen GmbH", rnNetto: dez("500"), ust: dez("95"),
                                    rechnungsdatum: tag(2026, 4, 1), status: .offen, rechnungsnummer: "R-OFFEN"))
        try c.mainContext.save()

        let csvText = toolText(await ruf(c, "tools/call",
            ["name": "kontor_liste", "arguments": ["typ": "offene_rechnungen", "mit_id": true]]))
        let kopf = csvText.split(separator: "\n").first!.split(separator: ";")
        #expect(kopf.last == "id")
        let zeile = csvText.split(separator: "\n").first { $0.contains("R-OFFEN") }!
        let id = String(zeile.split(separator: ";").last!)

        let upd = await ruf(c, "tools/call", ["name": "kontor_aktualisieren", "arguments": [
            "typ": "einnahmen", "id": id, "felder": ["status": "bezahlt", "zahlungsdatum": "2026-05-15"],
        ]])
        #expect((upd["result"] as! [String: Any])["isError"] as? Bool == false)
        let rechnung = try c.mainContext.fetch(FetchDescriptor<Income>()).first { $0.rechnungsnummer == "R-OFFEN" }
        #expect(rechnung?.status == .bezahlt)
        #expect(rechnung?.zahlungsdatum == tag(2026, 5, 15))

        let del = await ruf(c, "tools/call", ["name": "kontor_loeschen", "arguments": ["typ": "einnahmen", "id": id]])
        #expect((del["result"] as! [String: Any])["isError"] as? Bool == false)
        #expect(try c.mainContext.fetch(FetchDescriptor<Income>()).contains { $0.rechnungsnummer == "R-OFFEN" } == false)
    }

    @Test func anlegenOhnePflichtfeldMeldetFehler() async throws {
        let c = try container(); try seed(c)
        let antwort = await ruf(c, "tools/call", ["name": "kontor_anlegen",
                                                  "arguments": ["typ": "ausgaben", "felder": ["bezeichnung": "Ohne Betrag"]]])
        #expect((antwort["result"] as! [String: Any])["isError"] as? Bool == true)
    }

    @Test func aktualisierenUngueltigeId() async throws {
        let c = try container(); try seed(c)
        let antwort = await ruf(c, "tools/call", ["name": "kontor_aktualisieren",
                                                  "arguments": ["typ": "einnahmen", "id": "kaputt", "felder": ["kunde": "X"]]])
        #expect((antwort["result"] as! [String: Any])["isError"] as? Bool == true)
    }

    // MARK: - Beleg anhängen

    /// id eines Datensatzes über kontor_liste (mit_id=true) holen – Zeile per Suchtext, id = letzte Spalte.
    private func idAusListe(_ c: ModelContainer, typ: String, enthaelt: String) async -> String {
        let csvText = toolText(await ruf(c, "tools/call",
            ["name": "kontor_liste", "arguments": ["typ": typ, "mit_id": true]]))
        let zeile = csvText.split(separator: "\n").first { $0.contains(enthaelt) }!
        return String(zeile.split(separator: ";").last!)
    }

    @Test func belegAnhaengenUndEntfernen() async throws {
        let c = try container(); try seed(c)
        let id = await idAusListe(c, typ: "ausgaben", enthaelt: "Hosting")

        // PDF (Base64) anhängen.
        let pdf = Data("%PDF-1.4\nKontor-Testbeleg\n%%EOF".utf8)
        let antwort = await ruf(c, "tools/call", ["name": "kontor_beleg", "arguments": [
            "typ": "ausgaben", "id": id, "dateiname": "RE-Test.pdf",
            "inhalt_base64": pdf.base64EncodedString(),
        ]])
        #expect((antwort["result"] as! [String: Any])["isError"] as? Bool == false)

        let eintrag = try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>()).first { $0.bezeichnung == "Hosting" }!
        let pfad = try #require(eintrag.belegPfad)
        #expect(pfad.hasPrefix("2026/"))
        #expect(pfad.hasSuffix(".pdf"))

        // Datei liegt physisch im Belege-Ordner und hat den richtigen Inhalt – danach aufräumen.
        let url = Belege.url(fuer: pfad)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect((try? Data(contentsOf: url)) == pdf)

        // beleg-Spalte der Ausgabenliste zeigt den Pfad.
        let liste = toolText(await ruf(c, "tools/call", ["name": "kontor_liste", "arguments": ["typ": "ausgaben", "jahr": 2026]]))
        #expect(liste.split(separator: "\n").first == "datum;bezeichnung;anbieter;brutto;vst;netto;steuerart;betrieblich;beleg")
        #expect(liste.contains(pfad))

        // entfernen=true löst den Verweis (Datei darf bleiben).
        let entf = await ruf(c, "tools/call", ["name": "kontor_beleg", "arguments": [
            "typ": "ausgaben", "id": id, "entfernen": true,
        ]])
        #expect((entf["result"] as! [String: Any])["isError"] as? Bool == false)
        #expect(eintrag.belegPfad == nil)
    }

    @Test func belegOhneInhaltUndFalscherTypMeldenFehler() async throws {
        let c = try container(); try seed(c)
        let id = await idAusListe(c, typ: "ausgaben", enthaelt: "Hosting")

        // Kein inhalt_base64 und kein entfernen → Fehler.
        let ohneInhalt = await ruf(c, "tools/call", ["name": "kontor_beleg", "arguments": ["typ": "ausgaben", "id": id]])
        #expect((ohneInhalt["result"] as! [String: Any])["isError"] as? Bool == true)

        // Modul ohne Beleg (lebensmittel) → Fehler.
        let falscherTyp = await ruf(c, "tools/call", ["name": "kontor_beleg", "arguments": [
            "typ": "lebensmittel", "id": id, "inhalt_base64": Data("x".utf8).base64EncodedString(),
        ]])
        #expect((falscherTyp["result"] as! [String: Any])["isError"] as? Bool == true)
    }
}
