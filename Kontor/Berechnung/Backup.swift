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
        // Hinweis: Felder `regeln`/`fixkosten` (abgelöste Alt-Modelle) sind entfallen; sie in
        // sehr alten Backups werden beim Import ignoriert (Migration ist abgeschlossen).
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
        var kategorie: Kategorie
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
                    estPauschalSatz: $0.estPauschalSatz,
                    estSatzProMonat: $0.estSatzProMonat, abschlussProMonat: $0.abschlussProMonat,
                    kskJAEProMonat: $0.kskJAEProMonat,
                    kskRVProMonat: $0.kskRVProMonat, kskKVProMonat: $0.kskKVProMonat,
                    kskPVProMonat: $0.kskPVProMonat,
                    snapshotProMonat: $0.snapshotProMonat) },
            ausgaben: try context.fetch(FetchDescriptor<ExpenseEntry>()).map {
                AusgabeDTO(datum: $0.datum, bezeichnung: $0.bezeichnung, anbieter: $0.anbieter,
                    brutto: $0.brutto, vst: $0.vst, steuerart: $0.steuerart, kategorie: $0.kategorie,
                    betrieblich: $0.betrieblich,
                    umlagefaehig: $0.umlagefaehig, belegPfad: $0.belegPfad, art: $0.art,
                    rechnungsnummer: $0.rechnungsnummer, zahlungsdatum: $0.zahlungsdatum) },
            einnahmen: try context.fetch(FetchDescriptor<Income>()).map {
                EinnahmeDTO(kunde: $0.kunde, rnNetto: $0.rnNetto, ust: $0.ust,
                    rechnungsdatum: $0.rechnungsdatum, zahlungsdatum: $0.zahlungsdatum,
                    ausfalldatum: $0.ausfalldatum, status: $0.status, rechnungsnummer: $0.rechnungsnummer,
                    belegPfad: $0.belegPfad) },
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
                    steuerart: $0.steuerart, betrieblich: $0.betrieblich, art: $0.art, umlagefaehig: $0.umlagefaehig) }
        )
    }

    static func exportData(_ context: ModelContext) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot(context))
    }

    // MARK: - Automatische Backups

    /// Ordner für automatische Backups im App-Daten-Bereich (Application Support/Backups).
    static func backupOrdner() -> URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true) else { return nil }
        let ordner = dir.appendingPathComponent("Backups", isDirectory: true)
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
        if FileManager.default.fileExists(atPath: datei.path), !istLeeresBackup(datei) { return }
        guard let data = try? exportData(context) else { return }
        try? data.write(to: datei)
        let alle = (try? FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("Auto-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        for f in alle.dropLast(behalteTage) { try? FileManager.default.removeItem(at: f) }
    }

    // MARK: - Komplett-Backup (Daten + Belege als Ordner)

    /// Vollständiges Backup als Ordner: `kontor.json` + Kopie aller Belege.
    /// Der Aufrufer hält den Security-Scope der user-gewählten Ziel-URL.
    static func exportiereKomplett(_ context: ModelContext, nach ziel: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: ziel.path) { try fm.removeItem(at: ziel) }
        try fm.createDirectory(at: ziel, withIntermediateDirectories: true)
        try exportData(context).write(to: ziel.appendingPathComponent("kontor.json"))
        let quelle = Belege.basis
        if fm.fileExists(atPath: quelle.path) {
            try? fm.copyItem(at: quelle, to: ziel.appendingPathComponent("Belege", isDirectory: true))
        }
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
                estPauschalSatz: d.estPauschalSatz,
                estSatzProMonat: d.estSatzProMonat ?? [:], abschlussProMonat: d.abschlussProMonat ?? [:],
                kskJAEProMonat: d.kskJAEProMonat ?? [:],
                kskRVProMonat: d.kskRVProMonat ?? [:],
                kskKVProMonat: d.kskKVProMonat ?? [:],
                kskPVProMonat: d.kskPVProMonat ?? [:],
                snapshotProMonat: d.snapshotProMonat ?? [:])); neu += 1
        }

        var ausgabeKeys = Set(try context.fetch(FetchDescriptor<ExpenseEntry>()).map { posKey($0.datum, $0.bezeichnung, $0.brutto) })
        for d in snap.ausgaben {
            let k = posKey(d.datum, d.bezeichnung, d.brutto)
            if ausgabeKeys.contains(k) { skip += 1; continue }
            ausgabeKeys.insert(k)
            context.insert(ExpenseEntry(datum: d.datum, bezeichnung: d.bezeichnung, anbieter: d.anbieter,
                brutto: d.brutto, vst: d.vst, steuerart: d.steuerart, kategorie: d.kategorie,
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

        let rnNummern = Set(try context.fetch(FetchDescriptor<Income>()).compactMap { $0.rechnungsnummer })
        var einKeys = Set(try context.fetch(FetchDescriptor<Income>()).map { posKey($0.rechnungsdatum, $0.kunde, $0.rnNetto) })
        for d in snap.einnahmen {
            if let nr = d.rechnungsnummer, rnNummern.contains(nr) { skip += 1; continue }
            let k = posKey(d.rechnungsdatum, d.kunde, d.rnNetto)
            if d.rechnungsnummer == nil, einKeys.contains(k) { skip += 1; continue }
            einKeys.insert(k)
            context.insert(Income(kunde: d.kunde, rnNetto: d.rnNetto, ust: d.ust, rechnungsdatum: d.rechnungsdatum,
                zahlungsdatum: d.zahlungsdatum, status: d.status, ausfalldatum: d.ausfalldatum,
                rechnungsnummer: d.rechnungsnummer, belegPfad: d.belegPfad)); neu += 1
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

        var lmKeys = Set(try context.fetch(FetchDescriptor<GroceryEntry>()).map { posKey($0.datum, $0.ort, $0.betrag) })
        for d in snap.lebensmittel {
            let k = posKey(d.datum, d.ort, d.betrag)
            if lmKeys.contains(k) { skip += 1; continue }
            lmKeys.insert(k)
            context.insert(GroceryEntry(datum: d.datum, betrag: d.betrag, ort: d.ort)); neu += 1
        }

        var anKeys = Set(try context.fetch(FetchDescriptor<PurchaseEntry>()).map { posKey($0.datum, $0.bezeichnung, $0.preis) })
        for d in snap.anschaffungen {
            let k = posKey(d.datum, d.bezeichnung, d.preis)
            if anKeys.contains(k) { skip += 1; continue }
            anKeys.insert(k)
            context.insert(PurchaseEntry(datum: d.datum, bezeichnung: d.bezeichnung, preis: d.preis, belegPfad: d.belegPfad)); neu += 1
        }

        // Schlüssel inkl. Betrag: sonst kollidierten Zahlung & Erstattung gleicher Art am selben
        // Fälligkeitstag (negativer Betrag) → eine würde beim Restore verschluckt.
        var steuerKeys = Set(try context.fetch(FetchDescriptor<TaxPayment>()).map { "\($0.kind.rawValue)|\(Int($0.faellig.timeIntervalSince1970))|\($0.betrag)" })
        for d in snap.steuern {
            let k = "\(d.kind.rawValue)|\(Int(d.faellig.timeIntervalSince1970))|\(d.betrag)"
            if steuerKeys.contains(k) { skip += 1; continue }
            steuerKeys.insert(k)
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

        try context.save()
        return (neu, skip)
    }

    private static func posKey(_ d: Date, _ s: String, _ w: Decimal) -> String {
        "\(Int(d.timeIntervalSince1970))|\(s.lowercased())|\(w)"
    }

    /// Ein Tages-Backup gilt als „leer", wenn es weder Jahre noch Ausgaben noch Einnahmen enthält
    /// (z. B. das frühere Sicherheitsnetz eines frischen Stores) – ein solches darf ersetzt werden.
    private static func istLeeresBackup(_ datei: URL) -> Bool {
        guard let data = try? Data(contentsOf: datei) else { return false }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(Snapshot.self, from: data) else { return false }
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
