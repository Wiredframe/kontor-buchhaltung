import Foundation
import SwiftData
@testable import Kontor

// MARK: - Geteilte Test-Infrastruktur
//
// Vorher stand der in-memory-Container **fünfmal wortgleich** in ImportTests, MCPServerTests,
// BackupTests, BelegBatchTests und DemodatenTests. Kam eine Entität dazu, musste man an fünf
// Stellen daran denken – und wer es vergaß, bekam einen Laufzeitfehler in einer Datei, die er
// gar nicht angefasst hatte.

/// In-memory-Container mit dem **vollständigen** Schema. Fasst den echten Store nie an.
///
/// Die Liste muss dem Container aus `KontorApp.macheContainer()` entsprechen – kommt dort eine
/// Entität dazu, gehört sie auch hierher.
func testContainer() throws -> ModelContainer {
    try ModelContainer(
        for: YearSettings.self, ExpenseEntry.self, Vorlage.self,
            Income.self, MonthlyTask.self,
            GroceryEntry.self, PurchaseEntry.self, TaxPayment.self,
            ZuordnungsRegel.self, ImportBuchung.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

/// Frischer `ModelContext` auf einem eigenen in-memory-Container.
func testKontext() throws -> ModelContext { ModelContext(try testContainer()) }

/// Beleg-Ablage für die Dauer eines Tests in ein Temp-Verzeichnis umbiegen.
///
/// Ohne das schreiben Tests, die `Belege.basis` auch nur **lesen**, in
/// `~/Library/Application Support/Belege` des Nutzers – die Property legt ihr Verzeichnis bei
/// jedem Zugriff an. Räumt am Ende wieder auf und stellt die Überschreibung zurück.
func mitTemporaerenBelegen<T>(_ block: (URL) throws -> T) rethrows -> T {
    let ordner = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kontor-belege-\(UUID().uuidString)", isDirectory: true)
    let vorher = Belege.basisUeberschreibung
    Belege.basisUeberschreibung = ordner
    defer {
        Belege.basisUeberschreibung = vorher
        try? FileManager.default.removeItem(at: ordner)
    }
    return try block(ordner)
}

/// Async-Variante von `mitTemporaerenBelegen`.
func mitTemporaerenBelegen<T>(_ block: (URL) async throws -> T) async rethrows -> T {
    let ordner = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kontor-belege-\(UUID().uuidString)", isDirectory: true)
    let vorher = Belege.basisUeberschreibung
    Belege.basisUeberschreibung = ordner
    defer {
        Belege.basisUeberschreibung = vorher
        try? FileManager.default.removeItem(at: ordner)
    }
    return try await block(ordner)
}
