import SwiftUI

/// Gemeinsame Stil-Ebene: Karten-Optik (Elevation statt Outline) und Signalfarben. Bewusst
/// ohne Marken-Verlauf und ohne Modul-Farbskala: Farbe steht nur für echte Aussagen
/// (positiv/negativ), alles andere ist neutral (`.primary`/`.secondary`) bzw. der System-Akzent.
enum Stil {
    static let eckRadius: CGFloat = 12

    /// Signalfarbe „positiv" (Erstattung/Gutschrift, positive Differenz).
    static let positiv = Color.green
    /// Signalfarbe „negativ" (negatives Ergebnis, Budget-Überzug).
    static let negativ = Color.red
}

extension View {
    /// Flache, leicht graue Gruppen-Fläche im Settings-Stil: **kein Schatten**, dezent grauer
    /// Grund + Haarlinie, damit sich die Gruppe klar vom (helleren) Seitenhintergrund abhebt
    /// (native macOS-Apps wie Einstellungen/Mail setzen auf gruppierte Flächen ohne Elevation).
    func karte(_ radius: CGFloat = Stil.eckRadius) -> some View {
        background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    /// Hellerer Seitenhintergrund, auf dem die grauen `.karte()`-Gruppen abheben (Settings-Prinzip:
    /// Inhaltsfläche hell, gruppierte Karten etwas dunkler/abgesetzt).
    func seitenGrund() -> some View {
        background(Color(nsColor: .controlBackgroundColor))
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
