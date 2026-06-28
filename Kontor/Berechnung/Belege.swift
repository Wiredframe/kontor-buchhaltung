import Foundation

/// Ablage und Export von Belegen (PDF/Bild) im App-Container: Belege/<Jahr>/<Datei>.
/// `ExpenseEntry.belegPfad` speichert den relativen Pfad (z. B. "2026/rechnung.pdf").
enum Belege {
    static var basis: URL {
        let appSup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSup.appendingPathComponent("Belege", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(fuer relativ: String) -> URL {
        let ziel = basis.appendingPathComponent(relativ).standardizedFileURL
        // Defense-in-Depth: niemals aus dem Belege-Ordner ausbrechen (../, absolute Pfade).
        // `belegPfad` ist app-generiert; der Guard verhindert dennoch jede Traversal.
        guard ziel.path.hasPrefix(basis.standardizedFileURL.path + "/") else {
            return basis.appendingPathComponent(".ungueltig")
        }
        return ziel
    }

    static func existiert(_ relativ: String?) -> Bool {
        guard let relativ, !relativ.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: url(fuer: relativ).path)
    }

    /// Legt rohe Bytes (z. B. aus einem MCP-Base64-Upload) als Beleg unter Belege/<jahr>/<dateiname>
    /// ab und gibt den relativen Pfad zurück. Dedupliziert den Dateinamen wie `speichere(_:jahr:)`
    /// und entfernt Pfadanteile aus dem übergebenen Namen (kein Ausbruch aus dem Belege-Ordner).
    @discardableResult
    static func speichere(daten: Data, dateiname: String, jahr: Int) throws -> String {
        let ordner = basis.appendingPathComponent(String(jahr), isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)

        let bereinigt = (dateiname as NSString).lastPathComponent
        let sicher = bereinigt.isEmpty ? "beleg.pdf" : bereinigt
        let name = (sicher as NSString).deletingPathExtension
        let ext = (sicher as NSString).pathExtension
        var ziel = ordner.appendingPathComponent(sicher)
        var i = 1
        while FileManager.default.fileExists(atPath: ziel.path) {
            ziel = ordner.appendingPathComponent(ext.isEmpty ? "\(name)-\(i)" : "\(name)-\(i).\(ext)")
            i += 1
        }
        try daten.write(to: ziel, options: .atomic)
        return "\(jahr)/\(ziel.lastPathComponent)"
    }

    /// Kopiert eine Quelldatei nach Belege/<jahr>/ und gibt den relativen Pfad zurück.
    @discardableResult
    static func speichere(_ quelle: URL, jahr: Int) -> String? {
        let scoped = quelle.startAccessingSecurityScopedResource()
        defer { if scoped { quelle.stopAccessingSecurityScopedResource() } }

        let ordner = basis.appendingPathComponent(String(jahr), isDirectory: true)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)

        let name = quelle.deletingPathExtension().lastPathComponent
        let ext = quelle.pathExtension
        var ziel = ordner.appendingPathComponent(quelle.lastPathComponent)
        var i = 1
        while FileManager.default.fileExists(atPath: ziel.path) {
            ziel = ordner.appendingPathComponent(ext.isEmpty ? "\(name)-\(i)" : "\(name)-\(i).\(ext)")
            i += 1
        }
        do { try FileManager.default.copyItem(at: quelle, to: ziel) } catch { return nil }
        return "\(jahr)/\(ziel.lastPathComponent)"
    }

    /// Bündelt die angegebenen Belege als ZIP an der Zielposition (für den Jahresabschluss).
    static func exportiereAlsZip(pfade: [String], nach ziel: URL) throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Belege-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        for p in pfade {
            guard !p.contains("..") else { continue }   // keine Traversal in die ZIP-Struktur
            let src = url(fuer: p)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            // Unterordner (Jahr) im ZIP erhalten
            let unter = temp.appendingPathComponent((p as NSString).deletingLastPathComponent, isDirectory: true)
            try? FileManager.default.createDirectory(at: unter, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: src, to: temp.appendingPathComponent(p))
        }

        var koordFehler: NSError?
        var schreibFehler: Error?
        NSFileCoordinator().coordinate(readingItemAt: temp, options: .forUploading, error: &koordFehler) { zipURL in
            do {
                if FileManager.default.fileExists(atPath: ziel.path) {
                    try FileManager.default.removeItem(at: ziel)
                }
                try FileManager.default.copyItem(at: zipURL, to: ziel)
            } catch { schreibFehler = error }
        }
        if let koordFehler { throw koordFehler }
        if let schreibFehler { throw schreibFehler }
    }
}
