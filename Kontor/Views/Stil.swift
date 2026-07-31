import SwiftUI

/// Gemeinsame Stil-Ebene: Karten-Optik (Elevation statt Outline) und Signalfarben. Bewusst
/// ohne Marken-Verlauf und ohne Modul-Farbskala: Farbe steht nur für echte Aussagen
/// (positiv/negativ), alles andere ist neutral (`.primary`/`.secondary`) bzw. der System-Akzent.
enum Stil {
    static let eckRadius: CGFloat = 16

    /// Signalfarbe „positiv" (Erstattung/Gutschrift, positive Differenz).
    static let positiv = Color.green
    /// Signalfarbe „negativ" (negatives Ergebnis, Budget-Überzug).
    static let negativ = Color.red
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
