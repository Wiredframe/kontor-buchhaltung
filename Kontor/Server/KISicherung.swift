#if !APPSTORE
import Foundation
import SwiftData

/// Sicherheitsnetz für KI-Schreibzugriffe: legt **einmal pro MCP-Session** vor dem
/// ersten schreibenden Tool-Aufruf ein JSON-Backup an (Ordner „KI-Backups" neben den
/// Auto-Backups). So lässt sich jede vom externen Client ausgelöste Änderung zurückrollen.
enum KISicherung {
    private static var gesichertInSitzung = false

    /// `initialize` ruft das auf → die nächste Schreiboperation sichert erneut.
    static func neueSitzung() { gesichertInSitzung = false }

    /// Legt das Sitzungs-Backup an. Wirft, wenn das nicht gelingt – der Aufrufer bricht den
    /// Schreibzugriff dann ab.
    ///
    /// Das Flag wird **erst nach** dem erfolgreichen Write gesetzt. Vorher stand es vor allen
    /// Fehlerpfaden: Schlug irgendetwas fehl (kein Backup-Ordner, Platte voll), galt die
    /// Sitzung trotzdem als gesichert, es wurde nie erneut versucht – und die Schreibzugriffe
    /// liefen weiter durch. Das Sicherheitsnetz war für die ganze Sitzung weg, ohne dass
    /// Nutzer oder Client etwas davon merkten.
    @MainActor
    static func sichereVorSchreibzugriff(_ context: ModelContext) throws {
        guard !gesichertInSitzung else { return }
        guard let basis = Backup.backupOrdner() else {
            throw MCPFehler("Kein Backup-Ordner verfügbar – Schreibzugriff abgebrochen, "
                          + "um ohne Sicherung nichts zu verändern.")
        }
        let ordner = basis.appendingPathComponent("KI-Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmmss"
        let ziel = ordner.appendingPathComponent("ki-backup-\(df.string(from: Date())).json")
        try Backup.exportData(context).write(to: ziel)
        gesichertInSitzung = true   // erst jetzt: das Backup liegt wirklich auf der Platte
    }
}

#endif
