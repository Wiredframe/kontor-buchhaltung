import SwiftUI

/// Gemeinsame Stil-Ebene: Akzentfarben, Marken-Verlauf, Karten-Optik (Elevation
/// statt Outline), wiederverwendbare Bausteine – für ein konsistentes, plakatives UI.
enum Stil {
    static let eckRadius: CGFloat = 16

    /// Marken-Verlauf (Blau→Violett) – Hero des Monatsabschlusses.
    static let markenVerlauf = LinearGradient(
        colors: [Color(red: 0.34, green: 0.66, blue: 0.97),
                 Color(red: 0.43, green: 0.22, blue: 0.87)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Eigener Verlauf (warmes Grasgrün→Tannengrün, in der Hue der Gewinn-Farbe) – Hero des
    /// Jahresabschlusses, bewusst andere Farbe als der Monats-Hero, damit die beiden
    /// Abschluss-Screens auf einen Blick unterscheidbar sind.
    static let jahresVerlauf = LinearGradient(
        colors: [Color(red: 0.30, green: 0.74, blue: 0.38),
                 Color(red: 0.10, green: 0.48, blue: 0.26)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Wertfarbe für negative Hero-Kennzahlen (zarter Rotton auf dem Verlauf).
    static let heroNegativ = Color(red: 1, green: 0.82, blue: 0.82)

    // Semantische Akzente
    static let einnahmen = Color.blue
    static let ausgaben  = Color.orange
    static let steuer    = Color.purple
    static let gewinn    = Color.green
    static let ksk       = Color.teal
    static let umlage    = Color.indigo
    static let privat    = Color.pink
}

extension View {
    /// Elevierte Karten-Fläche (heller Grund + weicher Schatten, kein Rahmen).
    func karte(_ radius: CGFloat = Stil.eckRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        )
    }
}

/// Gruppierter Inhaltsblock mit Titel als elevierte Karte (ersetzt GroupBox).
struct Panel<Inhalt: View>: View {
    let titel: String
    /// Optionaler „öffnen"-Querlink rechts im Kopf (z. B. in die Ausgaben-View).
    var aktion: (() -> Void)? = nil
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(titel).font(.headline)
                if let aktion {
                    Spacer()
                    Button("öffnen", action: aktion).buttonStyle(.link)
                }
            }
            inhalt()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .karte()
    }
}
