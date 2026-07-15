import Foundation
import SwiftData
@testable import Kontor

// MARK: - Geteilte Test-Infrastruktur
//
// Vorher stand der in-memory-Container **fünfmal wortgleich** in ImportTests, MCPServerTests,
// BackupTests, BelegBatchTests und DemodatenTests. Kam eine Entität dazu, musste man an fünf
// Stellen daran denken – und wer es vergaß, bekam einen Laufzeitfehler in einer Datei, die er
// gar nicht angefasst hatte.

/// Lenkt Beleg- und Backup-Ablage **des gesamten Testlaufs** ins Temp-Verzeichnis.
///
/// Tests dürfen nie in `~/Library/Application Support` des Nutzers schreiben. Zwei Pfade tun das
/// sonst von allein:
/// - `Belege.basis` legt sein Verzeichnis bei **jedem Zugriff** an – Lesen genügt.
/// - `KISicherung` schreibt bei **jedem** MCP-Schreibzugriff ein echtes JSON-Backup nach
///   `Backups/KI-Backups`. Ein Testlauf hinterließ dort dutzendweise Dateien.
///
/// Wird aus `testContainer()` und den Suite-`init()`s angestoßen; die eigentliche Umleitung
/// passiert einmalig beim ersten Zugriff.
enum TestAblage {
    private static let einmal: Void = {
        let wurzel = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kontor-testlauf-\(UUID().uuidString)", isDirectory: true)
        Belege.basisUeberschreibung = wurzel.appendingPathComponent("Belege", isDirectory: true)
        Backup.ordnerUeberschreibung = wurzel
    }()

    static func aktiviere() { _ = einmal }
}

/// In-memory-Container mit dem **vollständigen** Schema. Fasst den echten Store nie an.
///
/// Die Liste muss dem Container aus `KontorApp.macheContainer()` entsprechen – kommt dort eine
/// Entität dazu, gehört sie auch hierher.
func testContainer() throws -> ModelContainer {
    TestAblage.aktiviere()
    return try ModelContainer(
        for: YearSettings.self, ExpenseEntry.self, Vorlage.self,
            Income.self, MonthlyTask.self,
            GroceryEntry.self, PurchaseEntry.self, TaxPayment.self,
            ZuordnungsRegel.self, ImportBuchung.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

/// Frischer `ModelContext` auf einem eigenen in-memory-Container.
func testKontext() throws -> ModelContext { ModelContext(try testContainer()) }

/// Beleg-Ablage **und** Backup-Ordner für die Dauer eines Tests in ein Temp-Verzeichnis biegen.
///
/// Ohne das schreiben Tests in den echten Ordner des Nutzers:
/// - `Belege.basis` legt sein Verzeichnis bei jedem Zugriff an – **Lesen genügt**.
/// - `KISicherung` (jeder MCP-Schreibpfad) legt ein echtes JSON-Backup unter
///   `Application Support/Backups/KI-Backups` ab – pro Testlauf eine Datei.
///
/// Räumt am Ende auf und stellt beide Überschreibungen zurück.
private func mitTempPfaden<T>(_ block: (URL) throws -> T) rethrows -> T {
    let ordner = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kontor-test-\(UUID().uuidString)", isDirectory: true)
    let belegeVorher = Belege.basisUeberschreibung
    let backupVorher = Backup.ordnerUeberschreibung
    Belege.basisUeberschreibung = ordner.appendingPathComponent("Belege", isDirectory: true)
    Backup.ordnerUeberschreibung = ordner
    defer {
        Belege.basisUeberschreibung = belegeVorher
        Backup.ordnerUeberschreibung = backupVorher
        try? FileManager.default.removeItem(at: ordner)
    }
    return try block(Belege.basis)
}

func mitTemporaerenBelegen<T>(_ block: (URL) throws -> T) rethrows -> T {
    try mitTempPfaden(block)
}

/// Async-Variante von `mitTemporaerenBelegen`.
func mitTemporaerenBelegen<T>(_ block: (URL) async throws -> T) async rethrows -> T {
    let ordner = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kontor-test-\(UUID().uuidString)", isDirectory: true)
    let belegeVorher = Belege.basisUeberschreibung
    let backupVorher = Backup.ordnerUeberschreibung
    Belege.basisUeberschreibung = ordner.appendingPathComponent("Belege", isDirectory: true)
    Backup.ordnerUeberschreibung = ordner
    defer {
        Belege.basisUeberschreibung = belegeVorher
        Backup.ordnerUeberschreibung = backupVorher
        try? FileManager.default.removeItem(at: ordner)
    }
    return try await block(Belege.basis)
}
