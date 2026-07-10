import SwiftUI
import SwiftData
import Foundation

/// Einstiegspunkt der App.
@main
struct KontorApp: App {
    let container: ModelContainer
    let mcp: MCPServer

    init() {
        var wiederhergestellt = false
        let c: ModelContainer
        do {
            c = try Self.macheContainer()
        } catch {
            // Store ließ sich nicht öffnen (z. B. inkompatible Änderung): defektes File
            // beiseitelegen und mit frischer DB starten, statt abzustürzen.
            Self.storeBeiseitelegen()
            wiederhergestellt = true
            do { c = try Self.macheContainer() }
            catch { fatalError("ModelContainer auch nach Reset nicht erstellbar: \(error)") }
        }
        container = c
        // Autosave: Inspektor-Edits werden sofort gesichert → andere Views (Übersicht,
        // Monatsabschluss) rechnen live, ohne manuellen Anstoß.
        c.mainContext.autosaveEnabled = true
        // Vorschlags-Startregeln für den Kontoauszug-Import (idempotent, auch für bestehende DBs).
        ZuordnungsRegel.seedeStartRegeln(c.mainContext)
        // Altbestand ohne `art` nachtragen (Fixkosten/Subscriptions sichtbar machen; idempotent).
        ArtNachtrag.nachtragen(c.mainContext)
        // Alt-Bug reparieren: privat gebuchte Betriebsausgaben → betrieblich + VSt neu (idempotent).
        PrivatBetriebsausgabeNachtrag.nachtragen(c.mainContext)
        if wiederhergestellt {
            UserDefaults.standard.set(true, forKey: "storeWiederhergestellt")
        } else {
            Backup.autoSichern(c.mainContext)   // tägliches Sicherheitsnetz
        }
        // Lokaler MCP-Server (für externe KI-Clients wie Claude Code) – nur auf Wunsch.
        mcp = MCPServer(container: c)
        if UserDefaults.standard.bool(forKey: "mcpAktiv") { mcp.starten() }
    }

    private static func macheContainer() throws -> ModelContainer {
        try ModelContainer(
            for: YearSettings.self, ExpenseEntry.self, Vorlage.self,
                Income.self, MonthlyTask.self,
                GroceryEntry.self, PurchaseEntry.self, TaxPayment.self,
                ZuordnungsRegel.self, ImportBuchung.self)
    }

    private static func storeBeiseitelegen() {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: false) else { return }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = df.string(from: Date())
        for s in ["", "-wal", "-shm"] {
            let f = dir.appendingPathComponent("default.store\(s)")
            if FileManager.default.fileExists(atPath: f.path) {
                try? FileManager.default.moveItem(at: f, to: dir.appendingPathComponent("default.store\(s).defekt-\(stamp)"))
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1100, height: 720)
        .modelContainer(container)
        .environment(mcp)
    }
}
