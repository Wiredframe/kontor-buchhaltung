import SwiftUI
import SwiftData
import Foundation

/// Einstiegspunkt der App.
@main
struct KontorApp: App {
    let container: ModelContainer
    #if !APPSTORE
    let mcp: MCPServer
    #endif

    init() {
        // Öffnen + Fehlerbehandlung liegen in `StoreOeffner` – herausgelöst, weil das der
        // einzige Pfad ist, der die produktive Nutzer-DB wegbenennen kann, und er hier
        // ungetestet war.
        let (c, zustand) = StoreOeffner.oeffne()
        container = c
        // Autosave: Inspektor-Edits werden sofort gesichert → andere Views (Übersicht,
        // Monatsabschluss) rechnen live, ohne manuellen Anstoß.
        c.mainContext.autosaveEnabled = true
        // Vorschlags-Startregeln für den Kontoauszug-Import (idempotent, auch für bestehende DBs).
        ZuordnungsRegel.seedeStartRegeln(c.mainContext)
        // Altbestand ohne `art` nachtragen (Fixkosten/Subscriptions sichtbar machen; idempotent).
        ArtNachtrag.nachtragen(c.mainContext)
        switch zustand {
        case .normal:
            Backup.autoSichern(c.mainContext)   // tägliches Sicherheitsnetz
        case .beiseitegelegt, .nurImSpeicher:
            // Kein Auto-Backup auf einem Ersatz-Store: Das überschriebe das Sicherheitsnetz des
            // Tages mit leeren Daten. Die UI meldet den Zustand.
            UserDefaults.standard.set(true, forKey: "storeWiederhergestellt")
            UserDefaults.standard.set(zustand == .nurImSpeicher, forKey: "storeNurImSpeicher")
        }
        #if !APPSTORE
        // Lokaler MCP-Server (für externe KI-Clients wie Claude Code) – nur auf Wunsch.
        // Im App-Store-Build (`APPSTORE`) komplett ausgeschlossen (Guideline 2.4.5).
        mcp = MCPServer(container: c)
        if UserDefaults.standard.bool(forKey: "mcpAktiv") { mcp.starten() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1100, height: 720)
        .modelContainer(container)
        #if !APPSTORE
        .environment(mcp)
        #endif
    }
}
