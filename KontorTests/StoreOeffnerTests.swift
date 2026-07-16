import Testing
import Foundation
import SwiftData
@testable import Kontor

/// Der einzige Pfad, der die produktive Nutzer-Datenbank wegbenennen kann – und er war
/// komplett ungetestet.
///
/// Alle Tests arbeiten auf einer eigenen Store-Datei im Temp-Verzeichnis; der echte Store
/// wird nie angefasst (`datei: nil` = Produktivpfad kommt hier nicht vor).
struct StoreOeffnerTests {

    private func tempOrdner() throws -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kontor-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func defekteStoreDatei(in ordner: URL) throws -> URL {
        let datei = ordner.appendingPathComponent("default.store")
        // Kein SQLite, sondern Müll → das Öffnen scheitert dauerhaft.
        try Data("das ist kein SQLite-Store".utf8).write(to: datei)
        return datei
    }

    @Test func gesunderStoreWirdNormalGeoeffnet() throws {
        let ordner = try tempOrdner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let (c, zustand) = StoreOeffner.oeffne(datei: ordner.appendingPathComponent("default.store"), pause: 0)
        #expect(zustand == .normal)
        // Der Container ist benutzbar.
        let ctx = ModelContext(c)
        ctx.insert(YearSettings(jahr: 2026, estPauschalSatz: dez("0.15")))
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<YearSettings>()) == 1)
    }

    /// Ein dauerhaft kaputter Store wird beiseitegelegt – und die App startet trotzdem.
    @Test func kaputterStoreWirdBeiseitegelegtUndDatenBleibenLiegen() throws {
        let ordner = try tempOrdner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let datei = try defekteStoreDatei(in: ordner)
        let inhaltVorher = try Data(contentsOf: datei)

        let (_, zustand) = StoreOeffner.oeffne(datei: datei, pause: 0)
        #expect(zustand == .beiseitegelegt)

        // **Nichts gelöscht**: Die alten Bytes liegen unter .defekt-<stamp> weiterhin da.
        let reste = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
            .filter { $0.contains(".defekt-") }
        #expect(reste.count == 1)
        let gerettet = try Data(contentsOf: ordner.appendingPathComponent(reste[0]))
        #expect(gerettet == inhaltVorher)
    }

    /// Regression: Ein **transienter** Fehler darf die Buchhaltung nicht wegräumen.
    ///
    /// Vorher genügte ein einziger `throw` aus `macheContainer()` – egal ob inkompatible
    /// Migration oder nur ein Datei-Lock der noch laufenden Instanz –, und der Store wanderte
    /// nach `.defekt-*`; der Nutzer stand vor einer leeren App. Hier wird der transiente Fall
    /// nachgestellt: Beim ersten Versuch liegt Müll im Weg, während der Pause verschwindet er.
    @Test func transienterFehlerRaeumtDenStoreNichtWeg() async throws {
        let ordner = try tempOrdner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let datei = try defekteStoreDatei(in: ordner)

        // „Behebt sich von selbst": während der Pause wird die kaputte Datei weggeräumt.
        let raeumer = Task.detached {
            try? await Task.sleep(nanoseconds: 100_000_000)
            try? FileManager.default.removeItem(at: datei)
        }
        let (_, zustand) = StoreOeffner.oeffne(datei: datei, pause: 1.0)
        _ = await raeumer.result

        #expect(zustand == .normal)     // zweiter Versuch klappt → kein Beiseitelegen
        let reste = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
            .filter { $0.contains(".defekt-") }
        #expect(reste.isEmpty)          // die Buchhaltung blieb, wo sie war
    }

    /// Regression: Lässt sich der kaputte Store **nicht verschieben**, stand hier früher ein
    /// `fatalError` – der zweite Öffnungsversuch traf denselben Store und die App stürzte bei
    /// **jedem** Start ab. Der Nutzer kam nie wieder an seine Daten. Jetzt: in-memory, die App
    /// geht auf und kann es erklären.
    @Test func nichtVerschiebbarerStoreFuehrtNichtInDenCrashLoop() throws {
        let ordner = try tempOrdner()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ordner.path)
            try? FileManager.default.removeItem(at: ordner)
        }
        let datei = try defekteStoreDatei(in: ordner)
        // Verzeichnis nur lesbar → moveItem scheitert.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ordner.path)

        let (c, zustand) = StoreOeffner.oeffne(datei: datei, pause: 0)
        #expect(zustand == .nurImSpeicher)
        // Und der Container ist benutzbar – die App startet.
        let ctx = ModelContext(c)
        ctx.insert(YearSettings(jahr: 2026, estPauschalSatz: dez("0.15")))
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<YearSettings>()) == 1)
    }

    /// `beiseitelegen` nimmt alle drei SQLite-Dateien mit (Store, WAL, SHM).
    @Test func beiseitelegenNimmtWalUndShmMit() throws {
        let ordner = try tempOrdner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let datei = ordner.appendingPathComponent("default.store")
        for suffix in ["", "-wal", "-shm"] {
            try Data("x".utf8).write(to: URL(fileURLWithPath: datei.path + suffix))
        }
        #expect(StoreOeffner.beiseitelegen(datei: datei))
        let dateien = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
        #expect(dateien.count == 3)
        #expect(dateien.allSatisfy { $0.contains(".defekt-") })
    }

    /// Kein Store da? Dann gibt es nichts beiseitezulegen – und das ist kein Fehler.
    @Test func beiseitelegenOhneStoreIstKeinFehler() throws {
        let ordner = try tempOrdner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        #expect(StoreOeffner.beiseitelegen(datei: ordner.appendingPathComponent("default.store")))
    }
}
