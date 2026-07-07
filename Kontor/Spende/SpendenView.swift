#if APPSTORE
import SwiftUI
import StoreKit

/// „Unterstütze die Entwicklung“ – freiwilliges Trinkgeld über Apple.
/// Wird als Sheet gezeigt (nur App-Store-Variante).
struct SpendenView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SpendenStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "heart.fill")
                .font(.system(size: 42))
                .foregroundStyle(Stil.privat)
                .padding(.top, 6)

            Text("Kontor unterstützen")
                .font(.title2.bold())

            Text("Kontor ist kostenlos und quelloffen – und bleibt es. Wenn dir die App den Buchhaltungs-Alltag leichter macht, freue ich mich riesig über ein kleines Trinkgeld. Es schaltet nichts frei; es ist einfach ein Dankeschön, das die Weiterentwicklung trägt.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if store.hatGespendet {
                Label("Du hast Kontor schon unterstützt – tausend Dank!", systemImage: "checkmark.seal.fill")
                    .font(.callout)
                    .foregroundStyle(Stil.gewinn)
            }

            Button {
                Task { await store.spenden() }
            } label: {
                HStack(spacing: 8) {
                    if store.laeuft { ProgressView().controlSize(.small) }
                    Text(kaufTitel)
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Stil.privat)
            .disabled(store.produkt == nil || store.laeuft)

            if let fehler = store.letzterFehler {
                Text(fehler)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Text("Die Zahlung läuft über deinen Apple-Account. Danke, dass du ein unabhängiges, werbefreies Projekt möglich machst.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)

            Button("Schließen") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .padding(.top, 2)
        }
        .padding(28)
        .frame(width: 380)
        .task {
            if store.produkt == nil { await store.ladeProdukt() }
        }
    }

    /// Beschriftung des Kauf-Buttons je nach Zustand (mit lokalisiertem Preis, wenn geladen).
    private var kaufTitel: String {
        if store.laeuft { return "Wird verarbeitet …" }
        let preis = store.preisText
        if preis.isEmpty { return "Mit einem Trinkgeld unterstützen" }
        return store.hatGespendet ? "Nochmal \(preis) geben" : "Mit \(preis) unterstützen"
    }
}
#endif
