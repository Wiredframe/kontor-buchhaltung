import Foundation
import SwiftData

/// JSON-Backup/Export aller Daten (einfacher Anfang – ein Snapshot, ohne Relationen).
enum Backup {

    // MARK: - DTOs

    struct Snapshot: Codable {
        var exportiertAm: Date
        var jahre: [YearSettingsDTO]
        var ausgaben: [AusgabeDTO]
        var einnahmen: [EinnahmeDTO]
        var aufgaben: [AufgabeDTO]
        var lebensmittel: [LebensmittelDTO]
        var anschaffungen: [AnschaffungDTO]
        var steuern: [SteuerDTO]
        var zuordnungsRegeln: [ZuordnungsRegelDTO]? = nil   // Import-Lernregeln (optional → alte Backups bleiben lesbar)
        var vorlagen: [VorlageDTO]? = nil                   // Fixkosten/Subscription-Vorlagen (optional)
        var importBuchungen: [ImportBuchungDTO]? = nil      // Import-Gedächtnis (optional)
        // Hinweis: Felder `regeln`/`fixkosten` (abgelöste Alt-Modelle) sind entfallen; sie in
        // sehr alten Backups werden beim Import ignoriert (Migration ist abgeschlossen).
    }

    /// Gedächtnis der schon verarbeiteten Bankbewegungen. Gehört ins Backup, weil sonst nach
    /// einem Restore jede Bewegung wieder als „neu" gilt → derselbe Kontoauszug erzeugt Dubletten.
    struct ImportBuchungDTO: Codable {
        var schluessel: String
        var buchungstag: Date
        var betrag: Decimal
        var gegenpartei: String
        var kategorie: ImportKategorie
        var betrieblich: Bool
        var erstellt: Date
    }

    struct VorlageDTO: Codable {
        var bezeichnung, anbieter: String
        var betragBrutto: Decimal
        var steuerart: Steuerart
        var betrieblich: Bool
        var art: AusgabeArt
        var umlagefaehig: Bool
    }

    struct ZuordnungsRegelDTO: Codable {
        var schluessel: String
        var kategorie: ImportKategorie
        var betrieblich: Bool
        var steuerart: Steuerart
        var steuerKind: SteuerKind? = nil   // optional → alte Backups bleiben lesbar
        var aktualisiert: Date
    }

    struct YearSettingsDTO: Codable {
        var jahr: Int
        var ustvaRhythmus: UStVARhythmus
        var dauerfristverlaengerung: Bool
        var versteuerung: Versteuerung
        var estPauschalSatz: Decimal
        // Später ergänzt → optional, damit ältere Backups ohne diesen Schlüssel weiter dekodieren.
        var grundfreibetrag: Decimal? = nil
        // Alle Monats-Dictionaries sind **optional** → auch sehr alte Backups (die einen oder
        // mehrere dieser später ergänzten Schlüssel nicht enthalten) bleiben restore-bar; ein
        // fehlender Schlüssel wird beim Import zu `[:]` (kein Decoding-Crash).
        var estSatzProMonat: [String: Decimal]? = nil
        var abschlussProMonat: [String: Date]? = nil
        var kskJAEProMonat: [String: Decimal]? = nil
        var kskRVProMonat: [String: Decimal]? = nil
        var kskKVProMonat: [String: Decimal]? = nil
        var kskPVProMonat: [String: Decimal]? = nil
        var snapshotProMonat: [String: Data]? = nil
    }
    struct AusgabeDTO: Codable {
        var datum: Date
        var bezeichnung, anbieter: String
        var brutto, vst: Decimal
        var steuerart: Steuerart
        var betrieblich: Bool
        var umlagefaehig: Bool? = nil
        var belegPfad: String? = nil
        var art: AusgabeArt? = nil   // optional → ältere Backups bleiben lesbar
        var rechnungsnummer: String? = nil
        var zahlungsdatum: Date? = nil
    }
    struct EinnahmeDTO: Codable {
        var kunde: String
        var rnNetto, ust: Decimal
        var rechnungsdatum: Date
        var zahlungsdatum, ausfalldatum: Date?
        var status: InvoiceStatus
        var rechnungsnummer: String?
        var belegPfad: String? = nil
        // USt-Satz + Mischrechnungs-Bucket. Optional, damit ältere Backups (ohne diese Keys)
        // weiterhin dekodieren; beim Import mit 19 % bzw. 0 gedeutet.
        var satz: UStSatz? = nil
        var rnNetto2: Decimal? = nil
        var ust2: Decimal? = nil
        var satz2: UStSatz? = nil
    }
    struct AufgabeDTO: Codable {
        var titel: String
        var monat: Date
        var erledigt: Bool
        // optional → Backups aus der Zeit vor der Wiederhol-Mechanik bleiben restore-bar:
        var intervall: TaskIntervall? = nil
        var faelligTag: Int? = nil
        var quartalsMonate: [Int]? = nil
    }
    struct LebensmittelDTO: Codable {
        var datum: Date
        var betrag: Decimal
        var ort: String
    }
    struct AnschaffungDTO: Codable {
        var datum: Date
        var bezeichnung: String
        var preis: Decimal
        var belegPfad: String? = nil
    }
    struct SteuerDTO: Codable {
        var kind: SteuerKind
        var jahr: Int
        var faellig: Date
        var betrag: Decimal
        var bezahlt: Bool
        var bezahltAm: Date?
        var bemerkung: String
    }

    // MARK: - Snapshot & Encode

    static func snapshot(_ context: ModelContext) throws -> Snapshot {
        Snapshot(
            exportiertAm: Date(),
            jahre: try context.fetch(FetchDescriptor<YearSettings>()).map {
                YearSettingsDTO(jahr: $0.jahr, ustvaRhythmus: $0.ustvaRhythmus,
                    dauerfristverlaengerung: $0.dauerfristverlaengerung, versteuerung: $0.versteuerung,
                    estPauschalSatz: $0.estPauschalSatz, grundfreibetrag: $0.grundfreibetrag,
                    estSatzProMonat: $0.estSatzProMonat, abschlussProMonat: $0.abschlussProMonat,
                    kskJAEProMonat: $0.kskJAEProMonat,
                    kskRVProMonat: $0.kskRVProMonat, kskKVProMonat: $0.kskKVProMonat,
                    kskPVProMonat: $0.kskPVProMonat,
                    snapshotProMonat: $0.snapshotProMonat) },
            ausgaben: try context.fetch(FetchDescriptor<ExpenseEntry>()).map {
                AusgabeDTO(datum: $0.datum, bezeichnung: $0.bezeichnung, anbieter: $0.anbieter,
                    brutto: $0.brutto, vst: $0.vst, steuerart: $0.steuerart,
                    betrieblich: $0.betrieblich,
                    umlagefaehig: $0.umlagefaehig, belegPfad: $0.belegPfad, art: $0.art,
                    rechnungsnummer: $0.rechnungsnummer, zahlungsdatum: $0.zahlungsdatum) },
            einnahmen: try context.fetch(FetchDescriptor<Income>()).map {
                EinnahmeDTO(kunde: $0.kunde, rnNetto: $0.rnNetto, ust: $0.ust,
                    rechnungsdatum: $0.rechnungsdatum, zahlungsdatum: $0.zahlungsdatum,
                    ausfalldatum: $0.ausfalldatum, status: $0.status, rechnungsnummer: $0.rechnungsnummer,
                    belegPfad: $0.belegPfad,
                    satz: $0.satz, rnNetto2: $0.rnNetto2, ust2: $0.ust2, satz2: $0.satz2) },
            aufgaben: try context.fetch(FetchDescriptor<MonthlyTask>()).map {
                AufgabeDTO(titel: $0.titel, monat: $0.monat, erledigt: $0.erledigt,
                    intervall: $0.intervall, faelligTag: $0.faelligTag, quartalsMonate: $0.quartalsMonate) },
            lebensmittel: try context.fetch(FetchDescriptor<GroceryEntry>()).map {
                LebensmittelDTO(datum: $0.datum, betrag: $0.betrag, ort: $0.ort) },
            anschaffungen: try context.fetch(FetchDescriptor<PurchaseEntry>()).map {
                AnschaffungDTO(datum: $0.datum, bezeichnung: $0.bezeichnung, preis: $0.preis, belegPfad: $0.belegPfad) },
            steuern: try context.fetch(FetchDescriptor<TaxPayment>()).map {
                SteuerDTO(kind: $0.kind, jahr: $0.jahr, faellig: $0.faellig, betrag: $0.betrag,
                    bezahlt: $0.bezahlt, bezahltAm: $0.bezahltAm, bemerkung: $0.bemerkung) },
            zuordnungsRegeln: try context.fetch(FetchDescriptor<ZuordnungsRegel>()).map {
                ZuordnungsRegelDTO(schluessel: $0.schluessel, kategorie: $0.kategorie,
                    betrieblich: $0.betrieblich, steuerart: $0.steuerart, steuerKind: $0.steuerKind,
                    aktualisiert: $0.aktualisiert) },
            vorlagen: try context.fetch(FetchDescriptor<Vorlage>()).map {
                VorlageDTO(bezeichnung: $0.bezeichnung, anbieter: $0.anbieter, betragBrutto: $0.betragBrutto,
                    steuerart: $0.steuerart, betrieblich: $0.betrieblich, art: $0.art, umlagefaehig: $0.umlagefaehig) },
            importBuchungen: try context.fetch(FetchDescriptor<ImportBuchung>()).map {
                ImportBuchungDTO(schluessel: $0.schluessel, buchungstag: $0.buchungstag, betrag: $0.betrag,
                    gegenpartei: $0.gegenpartei, kategorie: $0.kategorie, betrieblich: $0.betrieblich,
                    erstellt: $0.erstellt) }
        )
    }

    enum Fehler: LocalizedError {
        case ungueltigesJSON
        var errorDescription: String? {
            switch self {
            case .ungueltigesJSON:
                "Das Backup enthält einen ungültigen Zahlenwert und wäre nicht wieder einlesbar. "
                + "Es wurde deshalb nicht geschrieben."
            }
        }
    }

    static func exportData(_ context: ModelContext) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot(context))
        // Letzte Verteidigungslinie: `JSONEncoder` wirft bei `Decimal.nan` nicht, sondern
        // schreibt literales `NaN` – ungültiges JSON, das beim Restore niemand mehr liest.
        // Lieber hier laut scheitern als ein Schein-Backup, das erst im Ernstfall auffliegt.
        guard istGueltigesJSON(data) else { throw Fehler.ungueltigesJSON }
        return data
    }

    // MARK: - Automatische Backups

    /// Test-Seam: Backup-Ordner umbiegen – analog zu `Belege.basisUeberschreibung`.
    ///
    /// Ohne ihn schreiben Tests, die `KISicherung` auslösen (jeder MCP-Schreibpfad), echte
    /// JSON-Backups nach `~/Library/Application Support/Backups/KI-Backups` – in den Ordner des
    /// Nutzers, bei jedem Lauf eine Datei. Im Produktivbetrieb immer `nil`.
    static var ordnerUeberschreibung: URL?

    /// Ordner für automatische Backups im App-Daten-Bereich (Application Support/Backups).
    static func backupOrdner() -> URL? {
        let basis: URL
        if let u = ordnerUeberschreibung {
            basis = u
        } else {
            guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true) else { return nil }
            basis = dir
        }
        let ordner = basis.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner
    }

    /// Tägliches Auto-Backup (höchstens eins pro Kalendertag); behält die letzten `behalteTage`.
    @MainActor
    static func autoSichern(_ context: ModelContext, behalteTage: Int = 14) {
        guard let ordner = backupOrdner() else { return }
        // Leere/Übergangs-Zustände (frischer Store vor einem Restore) NICHT sichern – sonst würde
        // ein leeres Backup das Sicherheitsnetz des Tages belegen und echte Daten verdecken.
        let leererStore = ((try? context.fetchCount(FetchDescriptor<YearSettings>())) ?? 0) == 0
            && ((try? context.fetchCount(FetchDescriptor<ExpenseEntry>())) ?? 0) == 0
            && ((try? context.fetchCount(FetchDescriptor<Income>())) ?? 0) == 0
        if leererStore { return }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let datei = ordner.appendingPathComponent("Auto-\(df.string(from: Date())).json")
        // Heute schon gesichert? Nur dann überspringen, wenn das vorhandene Backup nicht leer war
        // (ein früheres, leer geschriebenes Tages-Backup darf durch echte Daten ersetzt werden).
        if FileManager.default.fileExists(atPath: datei.path), !darfErsetztWerden(datei) { return }
        guard let data = try? exportData(context) else { return }
        // Erst wenn das heutige Backup wirklich auf der Platte liegt, dürfen alte weichen –
        // sonst dünnt ein fehlgeschlagener Write den Bestand aus, ohne Neues zu schaffen.
        do { try data.write(to: datei) } catch { return }
        let alle = (try? FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("Auto-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        for f in alle.dropLast(behalteTage) { try? FileManager.default.removeItem(at: f) }
    }

    // MARK: - Komplett-Backup (Daten + Belege als Ordner)

    /// Vollständiges Backup als Ordner: `kontor.json` + Kopie aller Belege.
    /// Der Aufrufer hält den Security-Scope der user-gewählten Ziel-URL.
    ///
    /// Schreibt **erst vollständig daneben und tauscht dann**. Vorher wurde das Ziel gelöscht,
    /// bevor das neue Backup stand: Ein zweiter Export am selben Tag vernichtete damit das
    /// vorhandene gute Backup, und scheiterte der neue (Platte voll), waren beide weg.
    static func exportiereKomplett(_ context: ModelContext, nach ziel: URL) throws {
        let fm = FileManager.default
        let temp = ziel.deletingLastPathComponent()
            .appendingPathComponent(".\(ziel.lastPathComponent).unvollstaendig", isDirectory: true)
        if fm.fileExists(atPath: temp.path) { try fm.removeItem(at: temp) }
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        do {
            try exportData(context).write(to: temp.appendingPathComponent("kontor.json"))
            let quelle = Belege.basis
            if fm.fileExists(atPath: quelle.path) {
                // Bewusst nicht `try?`: Ein Backup ohne Belege darf sich nicht als
                // „gespeichert, inkl. Belege" melden.
                try fm.copyItem(at: quelle, to: temp.appendingPathComponent("Belege", isDirectory: true))
            }
        } catch {
            try? fm.removeItem(at: temp)   // Halbfertiges nicht liegen lassen
            throw error
        }
        if fm.fileExists(atPath: ziel.path) { try fm.removeItem(at: ziel) }
        try fm.moveItem(at: temp, to: ziel)
    }

    /// Liest ein Komplett-Backup (Ordner): kopiert die Belege zurück und importiert die Daten.
    /// Der Aufrufer hält den Security-Scope der user-gewählten Quell-URL.
    @discardableResult
    static func importiereKomplett(_ context: ModelContext, von quelle: URL) throws -> (neu: Int, uebersprungen: Int) {
        let belege = quelle.appendingPathComponent("Belege", isDirectory: true)
        if FileManager.default.fileExists(atPath: belege.path) {
            kopiereBelege(von: belege, nach: Belege.basis)
        }
        let json = try Data(contentsOf: quelle.appendingPathComponent("kontor.json"))
        return try importData(json, in: context)
    }

    /// Kopiert Beleg-Dateien rekursiv; vorhandene Ziele bleiben unangetastet.
    private static func kopiereBelege(von quelle: URL, nach ziel: URL) {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: quelle, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        let basis = quelle.path.hasSuffix("/") ? quelle.path : quelle.path + "/"
        for case let datei as URL in en {
            guard (try? datei.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let zielDatei = ziel.appendingPathComponent(datei.path.replacingOccurrences(of: basis, with: ""))
            guard !fm.fileExists(atPath: zielDatei.path) else { continue }
            try? fm.createDirectory(at: zielDatei.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: datei, to: zielDatei)
        }
    }

    // MARK: - Import (ohne Überschreiben; Dedup je Entität)

    @discardableResult
    static func importData(_ data: Data, in context: ModelContext) throws -> (neu: Int, uebersprungen: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snap = try decoder.decode(Snapshot.self, from: data)
        var neu = 0, skip = 0

        let bestehendeJahre = try context.fetch(FetchDescriptor<YearSettings>())
        let jahrNach = Dictionary(bestehendeJahre.map { ($0.jahr, $0) }, uniquingKeysWith: { a, _ in a })
        for d in snap.jahre {
            if let vorhanden = jahrNach[d.jahr] {
                // Jahr existiert schon: Skalare bleiben unangetastet, aber die **Monats-
                // Dictionaries** (KSK/ESt/JAE/Abschluss/Snapshot) additiv mergen – nur fehlende
                // Monats-Schlüssel auffüllen, nie überschreiben. So bringt ein Restore die später
                // dazugekommenen KSK/ESt-Monatswerte zurück, ohne aktuelle Eingaben zu zerstören.
                if mergeMonatsdicts(d, in: vorhanden) { neu += 1 } else { skip += 1 }
                continue
            }
            context.insert(YearSettings(jahr: d.jahr, ustvaRhythmus: d.ustvaRhythmus,
                dauerfristverlaengerung: d.dauerfristverlaengerung, versteuerung: d.versteuerung,
                estPauschalSatz: d.estPauschalSatz, grundfreibetrag: d.grundfreibetrag,
                estSatzProMonat: d.estSatzProMonat ?? [:], abschlussProMonat: d.abschlussProMonat ?? [:],
                kskJAEProMonat: d.kskJAEProMonat ?? [:],
                kskRVProMonat: d.kskRVProMonat ?? [:],
                kskKVProMonat: d.kskKVProMonat ?? [:],
                kskPVProMonat: d.kskPVProMonat ?? [:],
                snapshotProMonat: d.snapshotProMonat ?? [:])); neu += 1
        }

        var ausgabeBestand = zaehleKeys(try context.fetch(FetchDescriptor<ExpenseEntry>()).map { posKey($0.datum, $0.bezeichnung, $0.brutto) })
        for d in snap.ausgaben {
            let k = posKey(d.datum, d.bezeichnung, d.brutto)
            if verbrauche(k, &ausgabeBestand) { skip += 1; continue }
            context.insert(ExpenseEntry(datum: d.datum, bezeichnung: d.bezeichnung, anbieter: d.anbieter,
                brutto: d.brutto, vst: d.vst, steuerart: d.steuerart,
                betrieblich: d.betrieblich, umlagefaehig: d.umlagefaehig ?? false,
                belegPfad: d.belegPfad, art: d.art,
                rechnungsnummer: d.rechnungsnummer, zahlungsdatum: d.zahlungsdatum)); neu += 1
        }
        var vorlageKeys = Set(try context.fetch(FetchDescriptor<Vorlage>()).map { $0.bezeichnung.lowercased() + "|" + $0.art.rawValue })
        for d in snap.vorlagen ?? [] {
            let k = d.bezeichnung.lowercased() + "|" + d.art.rawValue
            if vorlageKeys.contains(k) { skip += 1; continue }
            vorlageKeys.insert(k)
            context.insert(Vorlage(bezeichnung: d.bezeichnung, anbieter: d.anbieter, betragBrutto: d.betragBrutto,
                steuerart: d.steuerart, betrieblich: d.betrieblich, art: d.art, umlagefaehig: d.umlagefaehig)); neu += 1
        }

        let bestehendeEinnahmen = try context.fetch(FetchDescriptor<Income>())
        // Die Rechnungsnummer ist der natürliche Schlüssel, wenn sie da ist – das Set muss
        // deshalb **in** der Schleife mitwachsen, sonst rutschen zwei Backup-Einträge mit
        // derselben Nummer beide durch (die Sperre griffe nur gegen den Bestand).
        var rnNummern = Set(bestehendeEinnahmen.compactMap { $0.rechnungsnummer })
        var einBestand = zaehleKeys(bestehendeEinnahmen.filter { $0.rechnungsnummer == nil }
            .map { posKey($0.rechnungsdatum, $0.kunde, $0.rnNetto) })
        for d in snap.einnahmen {
            if let nr = d.rechnungsnummer {
                if rnNummern.contains(nr) { skip += 1; continue }
                rnNummern.insert(nr)
            } else {
                let k = posKey(d.rechnungsdatum, d.kunde, d.rnNetto)
                if verbrauche(k, &einBestand) { skip += 1; continue }
            }
            context.insert(Income(kunde: d.kunde, rnNetto: d.rnNetto, ust: d.ust, rechnungsdatum: d.rechnungsdatum,
                zahlungsdatum: d.zahlungsdatum, status: d.status, ausfalldatum: d.ausfalldatum,
                rechnungsnummer: d.rechnungsnummer, belegPfad: d.belegPfad,
                satz: d.satz, rnNetto2: d.rnNetto2 ?? 0, ust2: d.ust2 ?? 0, satz2: d.satz2)); neu += 1
        }

        var taskKeys = Set(try context.fetch(FetchDescriptor<MonthlyTask>()).map { $0.titel.lowercased() + "|" + String(Int($0.monat.timeIntervalSince1970)) })
        for d in snap.aufgaben {
            let k = d.titel.lowercased() + "|" + String(Int(d.monat.timeIntervalSince1970))
            if taskKeys.contains(k) { skip += 1; continue }
            taskKeys.insert(k)
            context.insert(MonthlyTask(titel: d.titel, monat: d.monat, erledigt: d.erledigt,
                intervall: d.intervall ?? .einmalig, faelligTag: d.faelligTag ?? 1,
                quartalsMonate: d.quartalsMonate ?? [])); neu += 1
        }

        var lmBestand = zaehleKeys(try context.fetch(FetchDescriptor<GroceryEntry>()).map { posKey($0.datum, $0.ort, $0.betrag) })
        for d in snap.lebensmittel {
            let k = posKey(d.datum, d.ort, d.betrag)
            if verbrauche(k, &lmBestand) { skip += 1; continue }
            context.insert(GroceryEntry(datum: d.datum, betrag: d.betrag, ort: d.ort)); neu += 1
        }

        var anBestand = zaehleKeys(try context.fetch(FetchDescriptor<PurchaseEntry>()).map { posKey($0.datum, $0.bezeichnung, $0.preis) })
        for d in snap.anschaffungen {
            let k = posKey(d.datum, d.bezeichnung, d.preis)
            if verbrauche(k, &anBestand) { skip += 1; continue }
            context.insert(PurchaseEntry(datum: d.datum, bezeichnung: d.bezeichnung, preis: d.preis, belegPfad: d.belegPfad)); neu += 1
        }

        // Schlüssel inkl. Betrag: sonst kollidierten Zahlung & Erstattung gleicher Art am selben
        // Fälligkeitstag (negativer Betrag) → eine würde beim Restore verschluckt.
        var steuerBestand = zaehleKeys(try context.fetch(FetchDescriptor<TaxPayment>()).map { "\($0.kind.rawValue)|\(Int($0.faellig.timeIntervalSince1970))|\($0.betrag)" })
        for d in snap.steuern {
            let k = "\(d.kind.rawValue)|\(Int(d.faellig.timeIntervalSince1970))|\(d.betrag)"
            if verbrauche(k, &steuerBestand) { skip += 1; continue }
            context.insert(TaxPayment(kind: d.kind, jahr: d.jahr, faellig: d.faellig, betrag: d.betrag,
                bezahlt: d.bezahlt, bezahltAm: d.bezahltAm, bemerkung: d.bemerkung)); neu += 1
        }

        var zuordnungKeys = Set(try context.fetch(FetchDescriptor<ZuordnungsRegel>()).map(\.schluessel))
        for d in snap.zuordnungsRegeln ?? [] {
            if zuordnungKeys.contains(d.schluessel) { skip += 1; continue }
            zuordnungKeys.insert(d.schluessel)
            context.insert(ZuordnungsRegel(schluessel: d.schluessel, kategorie: d.kategorie,
                betrieblich: d.betrieblich, steuerart: d.steuerart, steuerKind: d.steuerKind ?? .ustVz,
                aktualisiert: d.aktualisiert)); neu += 1
        }

        var importKeys = Set(try context.fetch(FetchDescriptor<ImportBuchung>()).map(\.schluessel))
        for d in snap.importBuchungen ?? [] {
            if importKeys.contains(d.schluessel) { skip += 1; continue }
            importKeys.insert(d.schluessel)
            context.insert(ImportBuchung(schluessel: d.schluessel, buchungstag: d.buchungstag,
                betrag: d.betrag, gegenpartei: d.gegenpartei, kategorie: d.kategorie,
                betrieblich: d.betrieblich, erstellt: d.erstellt)); neu += 1
        }

        try context.save()
        return (neu, skip)
    }

    private static func posKey(_ d: Date, _ s: String, _ w: Decimal) -> String {
        "\(Int(d.timeIntervalSince1970))|\(s.lowercased())|\(w)"
    }

    // MARK: - Dedup als Multimenge
    //
    // Der Dedup-Schlüssel (Datum, Name, Betrag) ist **nicht** eindeutig: zwei reale Vorgänge
    // können ihn sich teilen (zweimal am selben Tag im selben Laden über denselben Betrag).
    // Mit Mengen-Semantik verlöre der Restore den zweiten stillschweigend. Deshalb wird
    // gezählt statt nur „gesehen": jeder Backup-Eintrag verbraucht höchstens einen
    // vorhandenen Treffer; darüber hinaus wird eingefügt. Das hält den Re-Import idempotent
    // (Bestand deckt alles ab → alles verbraucht → nichts neu) und ergänzt bei Teil-Bestand
    // genau die fehlenden.

    private static func zaehleKeys(_ keys: [String]) -> [String: Int] {
        keys.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// Verbraucht einen vorhandenen Treffer für `k`. `true` = war schon da (überspringen),
    /// `false` = im Bestand nicht (mehr) gedeckt → einfügen.
    private static func verbrauche(_ k: String, _ bestand: inout [String: Int]) -> Bool {
        guard let n = bestand[k], n > 0 else { return false }
        bestand[k] = n - 1
        return true
    }

    /// Darf das vorhandene Tages-Backup durch ein neues ersetzt werden?
    ///
    /// Ja, wenn es **leer** ist (weder Jahre noch Ausgaben noch Einnahmen – z. B. das frühere
    /// Sicherheitsnetz eines frischen Stores) **oder unlesbar/korrupt**: Eine kaputte Datei ist
    /// als Sicherung wertlos, sie durch eine gute zu ersetzen ist immer die bessere Wahl.
    /// (Vorher hieß „unlesbar" hier `false` = „nicht leer, Finger weg" – ein einziges korruptes
    /// Tages-Backup blockierte damit die Sicherung dieses Tages dauerhaft und lautlos.)
    private static func darfErsetztWerden(_ datei: URL) -> Bool {
        guard let data = try? Data(contentsOf: datei) else { return true }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(Snapshot.self, from: data) else { return true }
        return snap.jahre.isEmpty && snap.ausgaben.isEmpty && snap.einnahmen.isEmpty
    }

    /// Füllt fehlende Monats-Schlüssel eines bestehenden `YearSettings` aus dem Backup auf
    /// (nie überschreiben). Liefert `true`, wenn dabei mindestens ein Wert ergänzt wurde.
    private static func mergeMonatsdicts(_ d: YearSettingsDTO, in ziel: YearSettings) -> Bool {
        var geaendert = false
        func merge<V>(_ quelle: [String: V], _ ziel: inout [String: V]) {
            for (k, v) in quelle where ziel[k] == nil { ziel[k] = v; geaendert = true }
        }
        merge(d.estSatzProMonat ?? [:], &ziel.estSatzProMonat)
        merge(d.abschlussProMonat ?? [:], &ziel.abschlussProMonat)
        merge(d.kskJAEProMonat ?? [:], &ziel.kskJAEProMonat)
        merge(d.kskRVProMonat ?? [:], &ziel.kskRVProMonat)
        merge(d.kskKVProMonat ?? [:], &ziel.kskKVProMonat)
        merge(d.kskPVProMonat ?? [:], &ziel.kskPVProMonat)
        merge(d.snapshotProMonat ?? [:], &ziel.snapshotProMonat)
        return geaendert
    }
}
