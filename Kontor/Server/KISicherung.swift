import Foundation
import SwiftData

/// Sicherheitsnetz für KI-Schreibzugriffe: legt **einmal pro MCP-Session** vor dem
/// ersten schreibenden Tool-Aufruf ein JSON-Backup an (Ordner „KI-Backups" neben den
/// Auto-Backups). So lässt sich jede vom externen Client ausgelöste Änderung zurückrollen.
enum KISicherung {
    private static var gesichertInSitzung = false

    /// `initialize` ruft das auf → die nächste Schreiboperation sichert erneut.
    static func neueSitzung() { gesichertInSitzung = false }

    @MainActor
    static func sichereVorSchreibzugriff(_ context: ModelContext) {
        guard !gesichertInSitzung else { return }
        gesichertInSitzung = true
        guard let basis = Backup.backupOrdner() else { return }
        let ordner = basis.appendingPathComponent("KI-Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmmss"
        let ziel = ordner.appendingPathComponent("ki-backup-\(df.string(from: Date())).json")
        if let data = try? Backup.exportData(context) { try? data.write(to: ziel) }
    }
}
