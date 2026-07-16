import Foundation
import SwiftData

/// Öffnet den SwiftData-Store – und entscheidet, was passiert, wenn das scheitert.
///
/// Herausgelöst aus `KontorApp.init`, weil das der **einzige** Pfad im Projekt ist, der die
/// produktive Nutzer-Datenbank wegbenennen kann – und er war komplett ungetestet.
///
/// Die Leitlinie ist CLAUDE.md: „Der On-Disk-Store ist die produktive Nutzerdatenbank."
/// Ihn beiseitezulegen ist die **teuerste** mögliche Reaktion – der Nutzer startet vor einer
/// leeren App. Das darf erst passieren, wenn wirklich nichts anderes mehr geht.
enum StoreOeffner {

    enum Zustand: Equatable {
        /// Normalfall: Store geöffnet.
        case normal
        /// Store war nicht lesbar; er liegt unangetastet als `.defekt-<stamp>` daneben,
        /// die App startet mit frischer DB.
        case beiseitegelegt
        /// Store weder lesbar **noch** verschiebbar. Letzter Ausweg: nur im Speicher.
        case nurImSpeicher
    }

    /// Schema der App. Muss mit `testContainer()` in den Tests übereinstimmen.
    private static func container(datei: URL?) throws -> ModelContainer {
        let typen: [any PersistentModel.Type] = [
            YearSettings.self, ExpenseEntry.self, Vorlage.self,
            Income.self, MonthlyTask.self,
            GroceryEntry.self, PurchaseEntry.self, TaxPayment.self,
            ZuordnungsRegel.self, ImportBuchung.self,
        ]
        let schema = Schema(typen)
        // **Produktivpfad bleibt implizit**: ohne Konfiguration nimmt SwiftData seinen Default
        // (`Application Support/default.store`). Nur Tests geben eine Datei vor – hier eine
        // eigene URL zu konstruieren wäre das Risiko nicht wert, die App auf einen anderen
        // Store zeigen zu lassen.
        if let datei {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(url: datei))
        }
        return try ModelContainer(for: schema)
    }

    /// Öffnet den Store. `datei == nil` = Produktivpfad (SwiftData-Default).
    ///
    /// - `pause`: Wartezeit vor dem zweiten Versuch. Ein Öffnen scheitert nicht nur bei einer
    ///   inkompatiblen Migration, sondern auch **transient**: Datei-Lock einer noch laufenden
    ///   Instanz, kurzer Sandbox-/Platten-Hänger. Vorher genügte ein einziger solcher Fehler,
    ///   um die Buchhaltung wegzuräumen – ohne zweiten Versuch.
    static func oeffne(datei: URL? = nil, pause: TimeInterval = 0.5) -> (container: ModelContainer, zustand: Zustand) {
        if let c = try? container(datei: datei) { return (c, .normal) }

        // Zweiter Versuch nach kurzer Pause – deckt genau die transienten Fälle ab.
        if pause > 0 { Thread.sleep(forTimeInterval: pause) }
        if let c = try? container(datei: datei) { return (c, .normal) }

        // Erst jetzt beiseitelegen. Die Dateien werden **verschoben, nie gelöscht**: Die Daten
        // liegen danach als `.defekt-<stamp>` weiterhin auf der Platte.
        let verschoben = beiseitelegen(datei: datei)
        if verschoben, let c = try? container(datei: datei) { return (c, .beiseitegelegt) }

        // Ließ sich der Store nicht verschieben, träfe jeder weitere Versuch denselben kaputten
        // Store. Früher stand hier ein `fatalError` – das ergab einen **Crash-Loop bei jedem
        // Start**, und der Nutzer kam nie wieder an seine Daten. Lieber eine App, die aufgeht
        // und es erklären kann.
        if let c = try? nurImSpeicher() { return (c, .nurImSpeicher) }
        // In-memory schlägt praktisch nie fehl; wenn doch, ist wirklich Schluss.
        fatalError("ModelContainer auch im Speicher nicht erstellbar.")
    }

    private static func nurImSpeicher() throws -> ModelContainer {
        try ModelContainer(for: Schema([
            YearSettings.self, ExpenseEntry.self, Vorlage.self,
            Income.self, MonthlyTask.self,
            GroceryEntry.self, PurchaseEntry.self, TaxPayment.self,
            ZuordnungsRegel.self, ImportBuchung.self,
        ]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Verschiebt `default.store{,-wal,-shm}` nach `.defekt-<stamp>`. Liefert `true`, wenn danach
    /// kein Store mehr im Weg liegt.
    @discardableResult
    static func beiseitelegen(datei: URL?) -> Bool {
        let fm = FileManager.default
        let ziel: URL
        if let datei {
            ziel = datei
        } else {
            guard let dir = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: false) else { return false }
            ziel = dir.appendingPathComponent("default.store")
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = df.string(from: Date())

        var alleWeg = true
        for suffix in ["", "-wal", "-shm"] {
            let f = URL(fileURLWithPath: ziel.path + suffix)
            guard fm.fileExists(atPath: f.path) else { continue }
            let neu = URL(fileURLWithPath: ziel.path + suffix + ".defekt-\(stamp)")
            do { try fm.moveItem(at: f, to: neu) } catch { alleWeg = false }
        }
        return alleWeg
    }
}
