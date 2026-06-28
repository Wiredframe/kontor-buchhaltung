import SwiftUI

/// Erst-Start-Auswahl: mit leerer Datenbank beginnen oder mit synthetischen Demodaten
/// (fiktive Persona *Lena Brandt*, UI/UX-Designerin in Berlin). Wird nur angezeigt, wenn der
/// Store komplett leer ist und die Auswahl noch nicht getroffen wurde.
struct OnboardingView: View {
    let aufDemodaten: () -> Void
    let aufLeer: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "tray.full")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Willkommen bei Kontor")
                    .font(.title.bold())
                Text("Lokale Buchhaltung für Freiberufler – KSK, EÜR, Soll-Versteuerung.\nWomit möchtest du starten?")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            HStack(spacing: 16) {
                wahlKarte(symbol: "doc",
                          titel: "Leer starten",
                          text: "Beginne mit einer leeren Datenbank und erfasse alles selbst.",
                          aktion: aufLeer)
                wahlKarte(symbol: "wand.and.stars",
                          titel: "Mit Demodaten",
                          text: "Beispiel einer UI/UX-Designerin in Berlin – zum risikofreien Ausprobieren.",
                          hervorgehoben: true,
                          aktion: aufDemodaten)
            }

            Text("Demodaten sind frei erfunden und lassen sich jederzeit wieder löschen.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 560)
    }

    private func wahlKarte(symbol: String, titel: String, text: String,
                           hervorgehoben: Bool = false, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(hervorgehoben ? AnyShapeStyle(Stil.markenVerlauf) : AnyShapeStyle(.secondary))
                Text(titel).font(.headline)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(16)
            .karte()
        }
        .buttonStyle(.plain)
    }
}
