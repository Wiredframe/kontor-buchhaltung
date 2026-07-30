import Foundation
import SwiftData
import Testing

@testable import Kontor

// MARK: - KISicherung: Sitzungs-Backup vor KI-Schreibzugriffen

/// `KISicherung` legt einmal pro MCP-Session vor dem ersten Schreibzugriff ein JSON-Backup an.
/// Zuvor nur indirekt ueber die MCP-Schreibpfade beruehrt (~81 % Abdeckung); hier direkt.
///
/// `@MainActor` (die API ist MainActor-isoliert) und die synchronen Bloecke halten den
/// Sitzungs-Zustand `gesichertInSitzung` waehrend jeder Testsequenz atomar – so stoert die
/// geteilte statische Variable die Datei-Zaehlung nicht.
///
/// Achtung Sekunden-Aufloesung: der Dateiname traegt `HHmmss`, zwei Backups in derselben Sekunde
/// haetten denselben Namen. Die Tests zaehlen deshalb nicht hoch, sondern loeschen zwischendurch
/// und pruefen, ob wieder gesichert wird (deterministisch, unabhaengig vom Sekundentakt).
@MainActor
struct KISicherungTests {

    private func kiBackupOrdner() -> URL? {
        Backup.backupOrdner()?.appendingPathComponent("KI-Backups", isDirectory: true)
    }

    private func kiBackupAnzahl() -> Int {
        guard let ordner = kiBackupOrdner() else { return 0 }
        let inhalt = (try? FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)) ?? []
        return inhalt.filter { $0.pathExtension == "json" }.count
    }

    private func loescheKiBackups() {
        guard let ordner = kiBackupOrdner() else { return }
        let inhalt = (try? FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)) ?? []
        for datei in inhalt where datei.pathExtension == "json" {
            try? FileManager.default.removeItem(at: datei)
        }
    }

    @Test func legtSitzungsBackupAn() throws {
        try mitTemporaerenBelegen { _ in
            let ctx = try testKontext()
            KISicherung.neueSitzung()
            #expect(kiBackupAnzahl() == 0)
            try KISicherung.sichereVorSchreibzugriff(ctx)
            #expect(kiBackupAnzahl() == 1)  // genau ein Backup liegt jetzt auf der Platte
        }
    }

    /// Der zweite Aufruf derselben Sitzung darf NICHT erneut sichern. Beweis ohne
    /// Sekunden-Kollision: Backup loeschen, erneut sichern – es bleibt geloescht.
    @Test func sichertNurEinmalProSitzung() throws {
        try mitTemporaerenBelegen { _ in
            let ctx = try testKontext()
            KISicherung.neueSitzung()
            try KISicherung.sichereVorSchreibzugriff(ctx)
            #expect(kiBackupAnzahl() == 1)

            loescheKiBackups()
            #expect(kiBackupAnzahl() == 0)
            try KISicherung.sichereVorSchreibzugriff(ctx)  // gleiche Sitzung -> no-op
            #expect(kiBackupAnzahl() == 0)  // nichts neu gesichert
        }
    }

    /// `neueSitzung()` scharft das Sicherheitsnetz wieder: nach dem Loeschen sichert der
    /// naechste Schreibzugriff erneut.
    @Test func neueSitzungBewirktErneutesSichern() throws {
        try mitTemporaerenBelegen { _ in
            let ctx = try testKontext()
            KISicherung.neueSitzung()
            try KISicherung.sichereVorSchreibzugriff(ctx)
            loescheKiBackups()
            #expect(kiBackupAnzahl() == 0)

            KISicherung.neueSitzung()  // neue Session -> naechster Schreibzugriff sichert wieder
            try KISicherung.sichereVorSchreibzugriff(ctx)
            #expect(kiBackupAnzahl() == 1)
        }
    }
}
