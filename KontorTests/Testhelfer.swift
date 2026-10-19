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
///
/// **Ein Test nach dem anderen** (`OrdnerSperre`): Beide Überschreibungen sind globale Zustände,
/// und Swift Testing lässt Tests parallel laufen. Ohne Sperre bog ein zweiter Test die Ablage
/// mitten im ersten um oder stellte sie beim Aufräumen auf `nil` zurück –
/// `belegPfadBleibtImOrdner` schlug dadurch sporadisch fehl, und im ungünstigen Fall landete eine
/// Datei doch im echten Ordner. Deshalb gibt es den Helfer nur noch asynchron.
///
/// `@MainActor`, weil `KISicherung` dort läuft: Umbiegen und ein synchroner Block laufen dann ohne
/// Unterbrechung, kein anderer MCP-Test schreibt dazwischen sein Sitzungs-Backup in den Temp-Ordner.
@MainActor
func mitTemporaerenBelegen<T>(_ block: (URL) async throws -> T) async rethrows -> T {
    await OrdnerSperre.shared.betreten()
    let ordner = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kontor-test-\(UUID().uuidString)", isDirectory: true)
    let belegeVorher = Belege.basisUeberschreibung
    let backupVorher = Backup.ordnerUeberschreibung
    Belege.basisUeberschreibung = ordner.appendingPathComponent("Belege", isDirectory: true)
    Backup.ordnerUeberschreibung = ordner
    func aufraeumen() async {
        Belege.basisUeberschreibung = belegeVorher
        Backup.ordnerUeberschreibung = backupVorher
        try? FileManager.default.removeItem(at: ordner)
        await OrdnerSperre.shared.verlassen()
    }
    do {
        let ergebnis = try await block(Belege.basis)
        await aufraeumen()
        return ergebnis
    } catch {
        await aufraeumen()
        throw error
    }
}

/// Wechselseitiger Ausschluss über `await` hinweg (ein `NSLock` darf nicht über eine
/// Unterbrechung gehalten werden). Wer verlässt, reicht die Sperre direkt an den nächsten weiter.
actor OrdnerSperre {
    static let shared = OrdnerSperre()
    private var belegt = false
    private var wartende: [CheckedContinuation<Void, Never>] = []

    func betreten() async {
        guard belegt else {
            belegt = true
            return
        }
        await withCheckedContinuation { wartende.append($0) }
    }

    func verlassen() {
        if wartende.isEmpty { belegt = false } else { wartende.removeFirst().resume() }
    }
}
