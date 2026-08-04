import CoreGraphics
import CoreText
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

// MARK: - PDF-Fixtures (echter Textlayer)

/// Ein Textstück auf einer erzeugten Beleg-Seite. Koordinaten in Punkten, Ursprung **unten links**
/// (PDF-Konvention), Seite A4.
struct PDFText {
    var text: String
    var x: CGFloat
    var y: CGFloat
    var groesse: CGFloat = 11

    init(_ text: String, x: CGFloat, y: CGFloat, groesse: CGFloat = 11) {
        self.text = text
        self.x = x
        self.y = y
        self.groesse = groesse
    }
}

/// Schreibt ein PDF mit **echtem Textlayer** (CoreText) ins Temp-Verzeichnis und liefert die URL.
///
/// Bewusst erzeugt statt eingecheckt: echte Belege dürfen nicht ins Repo (personenbezogen,
/// Open-Source-Repo), ein Binär-Fixture wäre zudem nicht nachvollziehbar. So steht das Layout als
/// Code da und prüft genau den Pfad, der digitale Rechnungen liest.
@discardableResult
func machePDF(_ stuecke: [PDFText], name: String = "beleg") -> URL {
    let seite = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kontor-pdf-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("\(name).pdf")
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var box = seite
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return url }
    ctx.beginPDFPage(nil)
    for stueck in stuecke {
        let font = CTFontCreateWithName("Helvetica" as CFString, stueck.groesse, nil)
        let attribute: [NSAttributedString.Key: Any] = [.font: font]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: stueck.text, attributes: attribute))
        ctx.textPosition = CGPoint(x: stueck.x, y: stueck.y)
        CTLineDraw(line, ctx)
    }
    ctx.endPDFPage()
    ctx.closePDF()
    return url
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
