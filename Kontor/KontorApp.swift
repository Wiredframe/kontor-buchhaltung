import Foundation
import SwiftData
import SwiftUI

/// Einstiegspunkt der App.
@main
struct KontorApp: App {
    let container: ModelContainer
    let mcp: MCPServer

    init() {
        // Öffnen + Fehlerbehandlung liegen in `StoreOeffner` – herausgelöst, weil das der
        // einzige Pfad ist, der die produktive Nutzer-DB wegbenennen kann, und er hier
        // ungetestet war.
        #if DEBUG
        // Dev-/Test-Build (Xcode ⌘R, xcodebuild): NIE die produktive `default.store` des Nutzers
        // anfassen. Eigener Store in „Application Support/KontorDev/", getrennte Belege, kein
        // Auto-Backup (überschriebe sonst das echte Tages-Backup mit Dev-Daten). Dieser Zweig ist
        // in Release **wegkompiliert** → brew-/App-Store-Build bleibt am Produktivpfad (unten).
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let devDir = appSupport.appendingPathComponent("KontorDev", isDirectory: true)
        try? FileManager.default.createDirectory(at: devDir, withIntermediateDirectories: true)
        Belege.basisUeberschreibung = devDir.appendingPathComponent("Belege", isDirectory: true)
        let (c, _) = StoreOeffner.oeffne(datei: devDir.appendingPathComponent("dev.store"))
        container = c
        c.mainContext.autosaveEnabled = true
        ZuordnungsRegel.seedeStartRegeln(c.mainContext)
        ArtNachtrag.nachtragen(c.mainContext)
        // Leeren Dev-Store mit synthetischen Demodaten füllen, damit die Screens Inhalt zeigen.
        if Demodaten.istLeer(c.mainContext) { Demodaten.einspielen(c.mainContext) }
        print("Kontor[DEBUG]: isolierter Dev-Store \(devDir.appendingPathComponent("dev.store").path)")
        #else
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
            Backup.autoSichern(c.mainContext)  // tägliches Sicherheitsnetz
        case .beiseitegelegt, .nurImSpeicher:
            // Kein Auto-Backup auf einem Ersatz-Store: Das überschriebe das Sicherheitsnetz des
            // Tages mit leeren Daten. Die UI meldet den Zustand.
            UserDefaults.standard.set(true, forKey: "storeWiederhergestellt")
            UserDefaults.standard.set(zustand == .nurImSpeicher, forKey: "storeNurImSpeicher")
        }
        #endif
        // Lokaler MCP-Server (für externe KI-Clients wie Claude Code): nur auf Wunsch,
        // standardmäßig aus. Nur Loopback (127.0.0.1), Token-geschützt. In allen Builds
        // enthalten (auch App Store); der Nutzer schaltet ihn in den Einstellungen frei.
        mcp = MCPServer(container: container)
        if UserDefaults.standard.bool(forKey: "mcpAktiv") { mcp.starten() }
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
