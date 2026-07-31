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
    /// Einheitliche Farbe für Erklär-/Hinweistexte: etwas mehr Kontrast als `.secondary`,
    /// aber gedämpft (nicht `.primary`). Zentral, damit alle Erklärungen gleich lesbar sind.
    static let erklaerungFarbe = Color.primary.opacity(0.62)
}

extension View {
    /// Flache, leicht graue Gruppen-Fläche im Settings-Stil: **kein Schatten, kein Rahmen** –
    /// allein der graue Grund hebt die Gruppe vom (helleren) Seitenhintergrund ab
    /// (native macOS-Apps wie Einstellungen/Mail setzen auf gruppierte Flächen ohne Elevation).
    func karte(_ radius: CGFloat = Stil.eckRadius) -> some View {
        background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: radius))
    }

    /// Hellerer Seitenhintergrund, auf dem die grauen `.karte()`-Gruppen abheben (Settings-Prinzip:
    /// Inhaltsfläche hell, gruppierte Karten etwas dunkler/abgesetzt).
    func seitenGrund() -> some View {
        background(Color(nsColor: .controlBackgroundColor))
    }

    /// Inspector-/rechte-Sidebar-Hintergrund, an die globale Einstellung „Seitenleiste
    /// undurchsichtig" gekoppelt: opak (kein Durchscheinen des Inhalts) oder System-Vibrancy.
    func inspektorGrund() -> some View {
        modifier(InspektorGrund())
    }

    /// Einheitlicher Erklär-/Hinweistext unter Abschluss-Karten: klein, **linksbündig**,
    /// mehrzeilig und mit etwas mehr Kontrast als `.secondary` (aber gedämpft, nicht `.primary`).
    func erklaerung() -> some View {
        font(.caption)
            .foregroundStyle(Stil.erklaerungFarbe)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct InspektorGrund: ViewModifier {
    @AppStorage("sidebarOpak") private var sidebarOpak = false
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(sidebarOpak ? Color(nsColor: .windowBackgroundColor) : Color.clear)
    }
}

/// Gruppierter Inhaltsblock im Shortcuts-Stil: **Titel steht (etwas größer) über** der grauen
/// Gruppen-Karte, nicht in ihr. Optionaler „öffnen"-Querlink rechts im Kopf.
struct Panel<Inhalt: View>: View {
    let titel: String
    var aktion: (() -> Void)? = nil
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(titel).font(.title3).fontWeight(.semibold)
                if let aktion {
                    Spacer()
                    Button("öffnen", action: aktion).buttonStyle(.link)
                }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                inhalt()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .karte()
        }
    }
}
