import SwiftUI

/// Gemeinsame Stil-Ebene: bewusst schlank. Native macOS-Container (GroupBox/Form) tragen die
/// Optik; hier liegen nur die zwei Signalfarben und ein dezenter Karten-Modifier. Kein
/// Marken-Verlauf, keine Modul-Farbskala – Farbe steht nur für echte Aussagen (positiv/negativ),
/// alles andere ist neutral (`.primary`/`.secondary`) bzw. der System-Akzent.
enum Stil {
    /// Eckradius für den `.karte()`-Modifier (nah an nativen gruppierten Flächen).
    static let eckRadius: CGFloat = 10

    /// Signalfarbe „positiv" (Erstattung/Gutschrift, positive Differenz).
    static let positiv = Color.green
    /// Signalfarbe „negativ" (negatives Ergebnis, Budget-Überzug).
    static let negativ = Color.red
}

extension View {
    /// Dezente, dark-mode-sichere Kartenfläche: native Systemfläche + Haarlinie, **kein**
    /// hartkodierter Schatten. Für die wenigen Stellen, die eine abgesetzte Fläche ohne
    /// GroupBox-Label brauchen (Beleg-/Import-Zeilen, Onboarding-Kacheln).
    func karte(_ radius: CGFloat = Stil.eckRadius) -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.separator, lineWidth: 0.5))
    }
}

/// Gruppierter Inhaltsblock mit Titel – native `GroupBox`. Optionaler „öffnen"-Querlink rechts
/// im Kopf (z. B. in die Ausgaben-View). Signatur bleibt `Panel("Titel") { … }`, damit die
/// Auswertungs-Screens die native Gruppierung ohne Umbau bekommen.
struct Panel<Inhalt: View>: View {
    let titel: String
    var aktion: (() -> Void)? = nil
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        GroupBox {
            inhalt()
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text(titel)
                if let aktion {
                    Spacer()
                    Button("öffnen", action: aktion).buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
