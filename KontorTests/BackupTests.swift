import Testing
import Foundation
import SwiftData
@testable import Kontor

struct BackupTests {

    /// Kleines, in sich geschlossenes Test-Fixture: je Entität wenige, bekannte Datensätze –
    /// reicht für Export/Import/Roundtrip.
    private func befuelle(_ ctx: ModelContext) {
        ctx.insert(YearSettings(jahr: 2026, estPauschalSatz: dez("0.15")))
        ctx.insert(Vorlage(bezeichnung: "Figma", anbieter: "Figma", betragBrutto: dez("35.00"),
                           steuerart: .reverseCharge, betrieblich: true, art: .subscription))
        ctx.insert(Vorlage(bezeichnung: "Miete", betragBrutto: dez("725.00"),
                           steuerart: .steuerfrei, betrieblich: false, art: .fixkosten))
        ctx.insert(ExpenseEntry(datum: tag(2026, 1, 5), bezeichnung: "Figma", anbieter: "Figma",
                                brutto: dez("35.00"), vst: dez("0"), steuerart: .reverseCharge, art: .subscription))
        ctx.insert(ExpenseEntry(datum: tag(2026, 1, 5), bezeichnung: "ChatGPT", anbieter: "OpenAI",
                                brutto: dez("7.99"), vst: dez("1.27"), steuerart: .inland19))
        ctx.insert(Income(kunde: "Kunde A", rnNetto: dez("1000"), ust: dez("190"),
                          rechnungsdatum: tag(2026, 1, 10), status: .offen, rechnungsnummer: "2026-001"))
        ctx.insert(Income(kunde: "Kunde B", rnNetto: dez("500"), ust: dez("95"),
                          rechnungsdatum: tag(2026, 2, 10), status: .bezahlt, rechnungsnummer: "2026-002"))
        ctx.insert(MonthlyTask(titel: "Miete überweisen", monat: tag(2026, 1, 1), intervall: .monatlich))
        ctx.insert(GroceryEntry(datum: tag(2026, 1, 7), betrag: dez("50.00"), ort: "Rewe"))
        ctx.insert(PurchaseEntry(datum: tag(2026, 1, 8), bezeichnung: "Amazon", preis: dez("45.77")))
        ctx.insert(TaxPayment(kind: .ustVz, jahr: 2026, faellig: tag(2026, 4, 10), betrag: dez("100")))
    }

    /// Geteilt: siehe Testhelfer.swift (das Schema stand hier 5x wortgleich).
    private func container() throws -> ModelContainer { try testContainer() }

    @Test func exportEnthaeltAlleDatenUndIstDekodierbar() throws {
        let ctx = ModelContext(try container())
        befuelle(ctx)
        ctx.insert(ZuordnungsRegel(schluessel: "test haendler", kategorie: .lebensmittel, betrieblich: false))
        try ctx.save()

        let data = try Backup.exportData(ctx)
        #expect(!data.isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snap = try decoder.decode(Backup.Snapshot.self, from: data)

        #expect(snap.jahre.count == 1)
        #expect(snap.vorlagen?.count == 2)
        #expect(snap.ausgaben.count == 2)
        #expect(snap.einnahmen.count == 2)
        #expect(snap.aufgaben.count == 1)
        #expect(snap.anschaffungen.count == 1)
        #expect(snap.lebensmittel.count == 1)
        #expect(snap.jahre.first?.estPauschalSatz == dez("0.15"))
        #expect(snap.zuordnungsRegeln?.count == 1)        // Import-Lernregel wird mitgesichert
    }

    private func kontext() throws -> ModelContext { ModelContext(try container()) }

    private func zaehle(_ ctx: ModelContext) throws -> [Int] {
        [try ctx.fetchCount(FetchDescriptor<YearSettings>()),
         try ctx.fetchCount(FetchDescriptor<Vorlage>()),
         try ctx.fetchCount(FetchDescriptor<ExpenseEntry>()),
         try ctx.fetchCount(FetchDescriptor<Income>()),
         try ctx.fetchCount(FetchDescriptor<MonthlyTask>()),
         try ctx.fetchCount(FetchDescriptor<GroceryEntry>()),
         try ctx.fetchCount(FetchDescriptor<PurchaseEntry>()),
         try ctx.fetchCount(FetchDescriptor<TaxPayment>()),
         try ctx.fetchCount(FetchDescriptor<ZuordnungsRegel>())]
    }

    @Test func roundtripExportImport() throws {
        let quelle = try kontext()
        befuelle(quelle)
        quelle.insert(ZuordnungsRegel(schluessel: "test haendler", kategorie: .lebensmittel, betrieblich: false))
        quelle.insert(ZuordnungsRegel(schluessel: "finanzamt", kategorie: .steuer, betrieblich: false, steuerKind: .estVz))
        try quelle.save()
        let data = try Backup.exportData(quelle)

        let ziel = try kontext()
        let r = try Backup.importData(data, in: ziel)
        #expect(r.uebersprungen == 0)
        #expect(try zaehle(quelle) == zaehle(ziel))   // identische Datenbestände

        let r2 = try Backup.importData(data, in: ziel) // erneuter Import dedupliziert
        #expect(r2.neu == 0)
        #expect(try zaehle(quelle) == zaehle(ziel))

        // erweiterte Felder bleiben erhalten
        #expect(try ziel.fetch(FetchDescriptor<Vorlage>()).contains { $0.art == .fixkosten })
        #expect(try ziel.fetch(FetchDescriptor<ZuordnungsRegel>()).contains { $0.steuerKind == .estVz })
    }

    /// Regression: Ein NaN-Betrag darf kein stilles Schein-Backup erzeugen.
    ///
    /// `JSONEncoder` wirft bei `Decimal.nan` nicht, sondern schreibt literales `NaN` – also
    /// syntaktisch kaputtes JSON. Ohne Wächter meldete der Export „gespeichert", die Datei
    /// läge da, und erst der Restore (im Ernstfall) liefe auf: nicht dekodierbar.
    @Test func exportMitNaNBetragWirftStattEinScheinBackupZuSchreiben() throws {
        let ctx = try kontext()
        ctx.insert(ExpenseEntry(datum: tag(2026, 1, 5), bezeichnung: "Kaputt", anbieter: "X",
                                brutto: Decimal(1) / Decimal(0), vst: 0, steuerart: .steuerfrei))
        try ctx.save()
        #expect(throws: Backup.Fehler.self) { try Backup.exportData(ctx) }
    }

    /// Der Wächter darf gültige Daten nicht behindern.
    @Test func exportMitNormalenBetraegenBleibtGueltigesJSON() throws {
        let ctx = try kontext()
        befuelle(ctx)
        try ctx.save()
        #expect(istGueltigesJSON(try Backup.exportData(ctx)))
    }

    /// Ein Encode-Fehler darf einen bereits eingefrorenen Monat nicht wegräumen.
    /// (`dict[key] = try?` hätte den Schlüssel gelöscht → Monat rechnet still wieder live.)
    @Test func setzeSnapshotZerstoertBestehendenStandNichtBeiFehler() {
        let y = YearSettings(jahr: 2026, estPauschalSatz: dez("0.15"))
        let gut = MonatsSnapshot(rn: dez("1000"), ust: dez("190"), vst: 0, ustKorrektur: 0, ksk: 0,
                                 est: dez("150"), estKorrektur: 0, betriebsausgabenNetto: 0,
                                 umlagefaehig: 0, privatFix: 0, privatVariabel: 0)
        #expect(y.setzeSnapshot(monat: 5, gut) == true)
        #expect(y.snapshot(monat: 5)?.rn == dez("1000"))

        var kaputt = gut
        kaputt.rn = Decimal(1) / Decimal(0)          // NaN
        #expect(y.setzeSnapshot(monat: 5, kaputt) == false)
        #expect(y.snapshot(monat: 5)?.rn == dez("1000"))   // alter Stand unangetastet
    }

    /// Ein gescheiterter Komplett-Export darf das vorhandene Backup nicht vernichten.
    /// Vorher wurde das Ziel gelöscht, bevor das neue geschrieben war.
    @Test func gescheiterterKomplettExportLaesstAltesBackupStehen() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kontor-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let ziel = tmp.appendingPathComponent("Kontor-Backup-2026-07-15")

        let ctx = try kontext()
        befuelle(ctx)
        try ctx.save()
        try Backup.exportiereKomplett(ctx, nach: ziel)
        let ersteJSON = try Data(contentsOf: ziel.appendingPathComponent("kontor.json"))
        #expect(!ersteJSON.isEmpty)

        // Zweiter Export auf dasselbe Ziel, der scheitern MUSS (NaN):
        ctx.insert(ExpenseEntry(datum: tag(2026, 1, 5), bezeichnung: "Kaputt", anbieter: "X",
                                brutto: Decimal(1) / Decimal(0), vst: 0, steuerart: .steuerfrei))
        try ctx.save()
        #expect(throws: (any Error).self) { try Backup.exportiereKomplett(ctx, nach: ziel) }

        // Das gute Backup von vorhin muss unversehrt dastehen.
        let nachher = try Data(contentsOf: ziel.appendingPathComponent("kontor.json"))
        #expect(nachher == ersteJSON)
        // Und kein halbfertiger Temp-Ordner bleibt liegen.
        let reste = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
        #expect(reste == ["Kontor-Backup-2026-07-15"])
    }

    /// Regression: Echte Doppel-Vorgänge dürfen beim Restore nicht verschluckt werden.
    /// Der Dedup-Schlüssel ist (Datum, Name, Betrag) – zwei reale Einkäufe am selben Tag,
    /// im selben Laden, über denselben Betrag teilen ihn sich. Mit Mengen-Semantik landete
    /// nur einer davon im Restore, der zweite war unwiederbringlich weg.
    @Test func roundtripBewahrtEchteDoppelvorgaenge() throws {
        let quelle = try kontext()
        quelle.insert(GroceryEntry(datum: tag(2026, 1, 7), betrag: dez("12.50"), ort: "Rewe"))
        quelle.insert(GroceryEntry(datum: tag(2026, 1, 7), betrag: dez("12.50"), ort: "Rewe"))
        quelle.insert(PurchaseEntry(datum: tag(2026, 1, 8), bezeichnung: "Kabel", preis: dez("9.99")))
        quelle.insert(PurchaseEntry(datum: tag(2026, 1, 8), bezeichnung: "Kabel", preis: dez("9.99")))
        quelle.insert(ExpenseEntry(datum: tag(2026, 1, 9), bezeichnung: "Taxi", anbieter: "Uber",
                                   brutto: dez("23.80"), vst: dez("3.80"), steuerart: .inland19))
        quelle.insert(ExpenseEntry(datum: tag(2026, 1, 9), bezeichnung: "Taxi", anbieter: "Uber",
                                   brutto: dez("23.80"), vst: dez("3.80"), steuerart: .inland19))
        try quelle.save()
        let data = try Backup.exportData(quelle)

        let ziel = try kontext()
        try Backup.importData(data, in: ziel)
        #expect(try ziel.fetchCount(FetchDescriptor<GroceryEntry>()) == 2)
        #expect(try ziel.fetchCount(FetchDescriptor<PurchaseEntry>()) == 2)
        #expect(try ziel.fetchCount(FetchDescriptor<ExpenseEntry>()) == 2)

        // Re-Import bleibt trotzdem idempotent – nicht plötzlich vier.
        let r2 = try Backup.importData(data, in: ziel)
        #expect(r2.neu == 0)
        #expect(try ziel.fetchCount(FetchDescriptor<GroceryEntry>()) == 2)
        #expect(try ziel.fetchCount(FetchDescriptor<PurchaseEntry>()) == 2)
        #expect(try ziel.fetchCount(FetchDescriptor<ExpenseEntry>()) == 2)
    }

    /// Teil-Bestand: Ist einer der beiden Vorgänge schon da, ergänzt der Import genau den
    /// fehlenden – nicht beide (Dublette) und nicht keinen (Verlust).
    @Test func importErgaenztNurDenFehlendenDoppelvorgang() throws {
        let quelle = try kontext()
        quelle.insert(GroceryEntry(datum: tag(2026, 1, 7), betrag: dez("12.50"), ort: "Rewe"))
        quelle.insert(GroceryEntry(datum: tag(2026, 1, 7), betrag: dez("12.50"), ort: "Rewe"))
        try quelle.save()
        let data = try Backup.exportData(quelle)

        let ziel = try kontext()
        ziel.insert(GroceryEntry(datum: tag(2026, 1, 7), betrag: dez("12.50"), ort: "Rewe"))
        try ziel.save()
        let r = try Backup.importData(data, in: ziel)
        #expect(r.neu == 1 && r.uebersprungen == 1)
        #expect(try ziel.fetchCount(FetchDescriptor<GroceryEntry>()) == 2)
    }

    /// Regression: Zwei Backup-Einträge mit **derselben** Rechnungsnummer dürfen nicht beide
    /// importiert werden. `rnNummern` wurde einmal vor der Schleife gebildet und darin nie
    /// ergänzt – die Rechnungsnummer-Sperre griff deshalb nur gegen den Bestand, nicht
    /// innerhalb des Backups.
    @Test func importLaesstRechnungsnummerNichtDoppeltDurch() throws {
        let json = """
        {
          "exportiertAm": "2026-07-15T10:00:00Z",
          "jahre": [], "ausgaben": [], "aufgaben": [], "lebensmittel": [], "anschaffungen": [], "steuern": [],
          "einnahmen": [
            {"kunde": "Kunde A", "rnNetto": 1000, "ust": 190, "rechnungsdatum": "2026-01-10T00:00:00Z",
             "status": "offen", "rechnungsnummer": "2026-001"},
            {"kunde": "Kunde A anders geschrieben", "rnNetto": 1000, "ust": 190,
             "rechnungsdatum": "2026-01-11T00:00:00Z", "status": "offen", "rechnungsnummer": "2026-001"}
          ]
        }
        """.data(using: .utf8)!
        let ctx = try kontext()
        let r = try Backup.importData(json, in: ctx)
        #expect(r.neu == 1 && r.uebersprungen == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<Income>()) == 1)
    }

    /// Regression: Ein einzelner unbekannter Enum-Wert darf nicht den **ganzen** Restore kippen.
    /// Realistischer Fall: Backup einer neueren App-Version in eine ältere zurückspielen.
    /// Unbekanntes wird auf den jeweils neutralen Wert gedeutet, statt zu werfen.
    @Test func backupMitUnbekanntenEnumWertenBleibtImportierbar() throws {
        let json = """
        {
          "exportiertAm": "2026-07-15T10:00:00Z",
          "jahre": [],
          "ausgaben": [{"datum": "2026-01-05T00:00:00Z", "bezeichnung": "Neuartig", "anbieter": "X",
                        "brutto": 119, "vst": 19, "steuerart": "inland19", "betrieblich": true,
                        "art": "gibtEsNochNicht"}],
          "einnahmen": [{"kunde": "Kunde A", "rnNetto": 1000, "ust": 190,
                         "rechnungsdatum": "2026-01-10T00:00:00Z", "status": "irgendwasNeues"}],
          "aufgaben": [{"titel": "Neu", "monat": "2026-01-01T00:00:00Z", "erledigt": false,
                        "intervall": "alleZweiWochen"}],
          "lebensmittel": [], "anschaffungen": [],
          "steuern": [{"kind": "gewerbesteuer", "jahr": 2026, "faellig": "2026-04-10T00:00:00Z",
                       "betrag": 100, "bezahlt": false, "bemerkung": ""}],
          "zuordnungsRegeln": [{"schluessel": "neuer haendler", "kategorie": "kryptowaehrung",
                                "betrieblich": false, "steuerart": "inland19",
                                "aktualisiert": "2026-01-01T00:00:00Z"}]
        }
        """.data(using: .utf8)!

        let ctx = try kontext()
        let r = try Backup.importData(json, in: ctx)     // darf nicht werfen
        #expect(r.neu == 5)

        // Jeder unbekannte Wert landet auf dem neutralen Default – kein Datensatz geht verloren.
        #expect(try #require(ctx.fetch(FetchDescriptor<ExpenseEntry>()).first).artEffektiv == .betriebsausgabe)
        #expect(try #require(ctx.fetch(FetchDescriptor<Income>()).first).status == .offen)
        #expect(try #require(ctx.fetch(FetchDescriptor<MonthlyTask>()).first).intervall == .einmalig)
        #expect(try #require(ctx.fetch(FetchDescriptor<TaxPayment>()).first).kind == .sonstige)
        // Unbekannte Triage-Kategorie → ignorieren: die Regel bucht nichts, statt etwas zu erfinden.
        let regel = try #require(ctx.fetch(FetchDescriptor<ZuordnungsRegel>()).first)
        #expect(regel.kategorie == .ignorieren)
        #expect(regel.kategorie.bucht(betrieblich: false) == false)
    }

    /// Regression: Das Import-Gedächtnis (`ImportBuchung`) muss mitgesichert werden.
    /// Fehlt es im Backup, ist nach einem Restore nicht mehr bekannt, welche Bankbewegungen
    /// schon verarbeitet wurden – derselbe Kontoauszug schlägt dann alles erneut als „neu"
    /// vor und erzeugt Dubletten.
    @Test func roundtripBewahrtImportGedaechtnis() throws {
        let quelle = try kontext()
        befuelle(quelle)
        quelle.insert(ImportBuchung(schluessel: "2026-01-05|-35.00|figma", buchungstag: tag(2026, 1, 5),
                                    betrag: dez("-35.00"), gegenpartei: "FIGMA/San Francisco/US",
                                    kategorie: .subscription, betrieblich: true))
        quelle.insert(ImportBuchung(schluessel: "2026-01-07|-50.00|rewe", buchungstag: tag(2026, 1, 7),
                                    betrag: dez("-50.00"), gegenpartei: "REWE Berlin",
                                    kategorie: .lebensmittel, betrieblich: false))
        try quelle.save()
        let data = try Backup.exportData(quelle)

        let snap = try {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            return try d.decode(Backup.Snapshot.self, from: data)
        }()
        #expect(snap.importBuchungen?.count == 2)

        let ziel = try kontext()
        try Backup.importData(data, in: ziel)
        let wieder = try ziel.fetch(FetchDescriptor<ImportBuchung>())
        #expect(wieder.count == 2)
        // Der Dedup-Schlüssel ist das Einzige, worauf schonVerarbeitet() schaut – er muss stimmen.
        #expect(Set(wieder.map(\.schluessel)) == ["2026-01-05|-35.00|figma", "2026-01-07|-50.00|rewe"])
        let figma = try #require(wieder.first { $0.schluessel.contains("figma") })
        #expect(figma.kategorie == .subscription)
        #expect(figma.betrieblich == true)
        #expect(figma.betrag == dez("-35.00"))

        // Erneuter Import darf nicht duplizieren (schluessel ist @Attribute(.unique)).
        try Backup.importData(data, in: ziel)
        #expect(try ziel.fetchCount(FetchDescriptor<ImportBuchung>()) == 2)
    }

    /// USt-Satz + Mischrechnungs-Bucket überstehen Export→Import verlustfrei.
    @Test func roundtripBewahrtUStSatzUndMischrechnung() throws {
        let quelle = try kontext()
        quelle.insert(Income(kunde: "Misch", rnNetto: dez("2000"), ust: dez("380"),
                             rechnungsdatum: tag(2026, 3, 1), status: .offen, rechnungsnummer: "M-1",
                             satz: .satz19, rnNetto2: dez("900"), ust2: dez("63"), satz2: .satz7))
        quelle.insert(Income(kunde: "Nur7", rnNetto: dez("1000"), ust: dez("70"),
                             rechnungsdatum: tag(2026, 3, 2), status: .offen, rechnungsnummer: "M-2", satz: .satz7))
        try quelle.save()

        let ziel = try kontext()
        _ = try Backup.importData(try Backup.exportData(quelle), in: ziel)
        let alle = try ziel.fetch(FetchDescriptor<Income>())
        let misch = try #require(alle.first { $0.kunde == "Misch" })
        #expect(misch.satzEffektiv == .satz19)
        #expect(misch.satz2 == .satz7 && misch.rnNetto2 == dez("900") && misch.ust2 == dez("63"))
        #expect(misch.brutto == dez("3343"))
        let nur7 = try #require(alle.first { $0.kunde == "Nur7" })
        #expect(nur7.satzEffektiv == .satz7 && !nur7.hatZweitenSatz)
    }

    /// Ausgaben-Steuerart „Inland 7 %" übersteht Export→Import (String-rawValue, kein DTO-Feld nötig).
    @Test func roundtripBewahrtInland7Ausgabe() throws {
        let quelle = try kontext()
        quelle.insert(ExpenseEntry(datum: tag(2026, 4, 9), bezeichnung: "Fachbuch", anbieter: "X",
                                   brutto: dez("42.80"), vst: dez("2.80"), steuerart: .inland7, betrieblich: true))
        try quelle.save()
        let ziel = try kontext()
        _ = try Backup.importData(try Backup.exportData(quelle), in: ziel)
        let a = try #require(try ziel.fetch(FetchDescriptor<ExpenseEntry>()).first { $0.bezeichnung == "Fachbuch" })
        #expect(a.steuerart == .inland7 && a.vst == dez("2.80") && a.netto == dez("40.00"))
    }

    /// Bug-Fix: ein bestehendes Jahr darf beim Import nicht komplett übersprungen werden –
    /// die später dazugekommenen KSK/ESt-Monatswerte müssen additiv zurückkommen, ohne
    /// bereits vorhandene Monate zu überschreiben.
    @Test func importMergtKSKundESTInBestehendesJahr() throws {
        let quelle = try kontext()
        let ys = YearSettings(jahr: 2026, estPauschalSatz: dez("0.15"))
        ys.setzeKSKBetrag(monat: 1, .rv, dez("232.5"))
        ys.setzeKSKBetrag(monat: 1, .kv, dez("213.13"))
        ys.estSatzProMonat["6"] = dez("0.16")
        quelle.insert(ys)
        try quelle.save()
        let data = try Backup.exportData(quelle)

        // Ziel hat das Jahr schon, aber ohne KSK/ESt-Monatswerte (wie nach Datenverlust).
        let ziel = try kontext()
        let leer = YearSettings(jahr: 2026, estPauschalSatz: dez("0.15"))
        leer.estSatzProMonat["1"] = dez("0.19")   // bestehender Monat bleibt unangetastet
        ziel.insert(leer)
        try ziel.save()

        let r = try Backup.importData(data, in: ziel)
        #expect(r.neu == 1)   // gemergt = als „neu/ergänzt" gezählt
        let nachher = try #require(try ziel.fetch(FetchDescriptor<YearSettings>()).first)
        #expect(nachher.kskTeile(monat: 1).rv == dez("232.5"))
        #expect(nachher.kskTeile(monat: 1).kv == dez("213.13"))
        #expect(nachher.estSatzProMonat["6"] == dez("0.16"))
        #expect(nachher.estSatzProMonat["1"] == dez("0.19"))   // nicht überschrieben
        #expect(try ziel.fetchCount(FetchDescriptor<YearSettings>()) == 1)   // kein Dublikat-Jahr
    }

    @Test func artNachtragKlassifiziert() throws {
        let ctx = try kontext()
        // Altbestand ohne art:
        ctx.insert(ExpenseEntry(datum: tag(2026, 1, 1), bezeichnung: "Strom", anbieter: "",
                                brutto: dez("80"), vst: dez("0"), steuerart: .steuerfrei, betrieblich: false))
        ctx.insert(ExpenseEntry(datum: tag(2026, 1, 2), bezeichnung: "Disney+", anbieter: "Disney+",
                                brutto: dez("9"), vst: dez("0"), steuerart: .steuerfrei, betrieblich: false))
        ctx.insert(ExpenseEntry(datum: tag(2026, 1, 3), bezeichnung: "Figma", anbieter: "Figma",
                                brutto: dez("35"), vst: dez("0"), steuerart: .reverseCharge, betrieblich: true))
        ctx.insert(ExpenseEntry(datum: tag(2026, 1, 4), bezeichnung: "Drucker", anbieter: "Brother",
                                brutto: dez("120"), vst: dez("19.16"), steuerart: .inland19, betrieblich: true))
        // bereits gesetzte art bleibt erhalten:
        ctx.insert(ExpenseEntry(datum: tag(2026, 1, 5), bezeichnung: "Miete", anbieter: "",
                                brutto: dez("725"), vst: dez("0"), steuerart: .steuerfrei, betrieblich: false, art: .fixkosten))
        try ctx.save()

        ArtNachtrag.nachtragen(ctx)
        let alle = try ctx.fetch(FetchDescriptor<ExpenseEntry>())
        func art(_ b: String) -> AusgabeArt? { alle.first { $0.bezeichnung == b }?.art }
        #expect(art("Strom") == .fixkosten)            // privat, kein Abo
        #expect(art("Disney+") == .subscription)       // Streaming-Name
        #expect(art("Figma") == .subscription)         // betriebliches Abo (SaaS-Name)
        #expect(art("Drucker") == .betriebsausgabe)    // betrieblich, kein Abo
        #expect(art("Miete") == .fixkosten)            // unverändert

        // Idempotent: zweiter Lauf ändert nichts mehr.
        ArtNachtrag.nachtragen(ctx)
        #expect(try ctx.fetch(FetchDescriptor<ExpenseEntry>()).allSatisfy { $0.art != nil })
    }

    /// Zahlung und Erstattung gleicher Art am selben Fälligkeitstag (positiv + negativ) dürfen
    /// beim Roundtrip nicht kollidieren (Dedup-Key enthält den Betrag).
    @Test func negativeSteuerzahlungUeberlebtRoundtrip() throws {
        let quelle = try kontext()
        quelle.insert(TaxPayment(kind: .ustVz, jahr: 2026, faellig: tag(2026, 4, 10), betrag: dez("200"), bezahlt: true))
        quelle.insert(TaxPayment(kind: .ustVz, jahr: 2026, faellig: tag(2026, 4, 10), betrag: dez("-50"), bezahlt: true))
        try quelle.save()
        let data = try Backup.exportData(quelle)

        let ziel = try kontext()
        try Backup.importData(data, in: ziel)
        let zahlungen = try ziel.fetch(FetchDescriptor<TaxPayment>())
        #expect(zahlungen.count == 2)
        #expect(zahlungen.contains { $0.betrag == dez("200") })
        #expect(zahlungen.contains { $0.betrag == dez("-50") })
    }

    /// Der lokale Grundfreibetrag-Override rundet über Export/Import (neues Jahr → Insert-Zweig).
    @Test func grundfreibetragRoundTrip() throws {
        let quelle = try kontext()
        quelle.insert(YearSettings(jahr: 2026, estPauschalSatz: dez("0.15"), grundfreibetrag: dez("24696")))
        try quelle.save()
        let data = try Backup.exportData(quelle)

        let ziel = try kontext()
        try Backup.importData(data, in: ziel)
        let ys = try #require(try ziel.fetch(FetchDescriptor<YearSettings>()).first)
        #expect(ys.grundfreibetrag == dez("24696"))
    }

    /// Vorwärtskompatibilität: ein **altes** Backup-Schema (ohne KSK/ESt-Monatsdicts, ohne
    /// Vorlagen/Regeln, Ausgabe ohne `art`/`umlagefaehig`) muss ohne Crash importierbar sein.
    @Test func importAltesSchemaOhneNeueFelder() throws {
        let json = """
        {"exportiertAm":"2026-01-01T00:00:00Z",
         "jahre":[{"jahr":2024,"ustvaRhythmus":"vierteljaehrlich","dauerfristverlaengerung":false,"versteuerung":"soll","estPauschalSatz":0.15}],
         "ausgaben":[{"datum":"2024-03-01T00:00:00Z","bezeichnung":"Domain","anbieter":"X","brutto":11.9,"vst":1.9,"steuerart":"inland19","kategorie":"laufend","betrieblich":true}],
         "einnahmen":[],"aufgaben":[],"lebensmittel":[],"anschaffungen":[],"steuern":[]}
        """
        let ziel = try kontext()
        let r = try Backup.importData(Data(json.utf8), in: ziel)
        #expect(r.neu == 2)   // 1 Jahr + 1 Ausgabe
        let ys = try #require(try ziel.fetch(FetchDescriptor<YearSettings>()).first)
        #expect(ys.jahr == 2024)
        #expect(ys.kskRVProMonat.isEmpty)   // fehlende KSK-Dicts → leer (kein Crash)
        let aus = try #require(try ziel.fetch(FetchDescriptor<ExpenseEntry>()).first)
        #expect(aus.art == nil)             // fehlendes `art` → Altbestand
        #expect(aus.umlagefaehig == false)  // fehlend → Default
    }

    @Test func komplettBackupOrdnerRoundtrip() throws {
        let quelle = try kontext()
        befuelle(quelle)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("KontorTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        try Backup.exportiereKomplett(quelle, nach: temp)
        #expect(FileManager.default.fileExists(atPath: temp.appendingPathComponent("kontor.json").path))

        let ziel = try kontext()
        let r = try Backup.importiereKomplett(ziel, von: temp)
        #expect(r.neu > 0)
        #expect(try zaehle(quelle) == zaehle(ziel))   // alle Entitäten wiederhergestellt
    }
}
