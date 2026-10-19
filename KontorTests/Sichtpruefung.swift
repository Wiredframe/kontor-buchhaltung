import AppKit
import SwiftData
import SwiftUI
import Testing

@testable import Kontor

/// Sichtprüfung ohne Bildschirmaufnahme: rendert Module der App mit Demodaten offscreen als PNG.
///
/// Läuft nur mit `TEST_RUNNER_KONTOR_SICHT=<Ordner>` (xcodebuild reicht Variablen nur mit dem
/// Präfix `TEST_RUNNER_` an den Testprozess durch), sonst überspringt er sich. Gedacht für den
/// Fall, dass `screencapture` keine Freigabe hat. Je Modul entsteht `<Ordner>/<modul>.png`;
/// `TEST_RUNNER_KONTOR_SICHT_MODULE` wählt Module (Komma-getrennt, rawValue von `Modul`).
@MainActor
struct Sichtpruefung {

    @Test func moduleAlsBild() async throws {
        guard let ziel = ProcessInfo.processInfo.environment["KONTOR_SICHT"], !ziel.isEmpty else { return }
        let ordner = URL(fileURLWithPath: ziel, isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let module =
            (ProcessInfo.processInfo.environment["KONTOR_SICHT_MODULE"] ?? "")
            .split(separator: ",").compactMap { Modul(rawValue: String($0)) }

        try await mitTemporaerenBelegen { _ in
            let c = try testContainer()
            Demodaten.einspielen(c.mainContext)
            for modul in module.isEmpty ? [Modul.dashboard] : module {
                UserDefaults.standard.set(modul.rawValue, forKey: "startModul")
                let fenster = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
                    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                fenster.contentView = NSHostingView(
                    rootView: ContentView().modelContainer(c).environment(MCPServer(container: c)))
                fenster.orderBack(nil)
                for _ in 0..<15 { try await Task.sleep(for: .milliseconds(100)) }
                let ansicht = try #require(fenster.contentView)
                let rep = try #require(ansicht.bitmapImageRepForCachingDisplay(in: ansicht.bounds))
                ansicht.cacheDisplay(in: ansicht.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                try png.write(to: ordner.appendingPathComponent("\(modul.rawValue).png"))
                fenster.orderOut(nil)
            }
            UserDefaults.standard.removeObject(forKey: "startModul")
        }
    }
}
