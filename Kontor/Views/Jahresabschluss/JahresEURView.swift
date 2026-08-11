import SwiftUI

/// Jahresabschluss → EÜR: die Gewinnermittlung. Einnahmen (Zufluss) − betriebliche Ausgaben
/// (netto) = Gewinn.
struct JahresEURView: View {
    @Environment(Zeitkontext.self) private var zeit
    @Environment(Navigation.self) private var nav

    var body: some View {
        JahresSeite(titel: "EÜR") { w in
            // Kein „öffnen" im Panel-Kopf: die EÜR mischt Einnahmen und Ausgaben, ein einzelner
            // Link sprang nur in die Ausgaben und führte auf der Einnahmenseite in die Irre.
            // Stattdessen unten je ein eigener Link pro Seite der Rechnung.
            Panel(titel: "Einnahmenüberschussrechnung (EÜR)") {
                VStack(spacing: 2) {
                    Kartenzeile(
                        label: "Betriebseinnahmen (Zufluss, netto)", wert: w.a.einnahmenBezahlt,
                        icon: "eurosign.circle")
                    Kartenzeile(
                        label: "Betriebsausgaben (netto)", wert: w.a.ausgabenNetto, icon: "creditcard",
                        minus: true)
                    Summenzeile(label: "Gewinn (EÜR)", wert: w.a.gewinn)
                    Text("Einnahmen nach Zahlungseingang (Zufluss), betriebliche Ausgaben netto.")
                        .erklaerung()
                    Divider().padding(.vertical, 6)
                    HStack(spacing: 16) {
                        Button("Einnahmen \(String(w.jahr)) öffnen") {
                            nav.zeigeEinnahmenJahr(jahr: w.jahr, zeit: zeit)
                        }
                        Button("Betriebsausgaben \(String(w.jahr)) öffnen") {
                            nav.zeigeAusgabenJahr(jahr: w.jahr, betrieblich: true, zeit: zeit)
                        }
                        Spacer(minLength: 0)
                    }
                    .buttonStyle(.link)
                    .padding(.vertical, 2)
                }
            }

            Panel(
                titel: "Vorsteuer im Jahr",
                // Der Link folgt der Wirkung, nicht der Herkunft: die Vorsteuer mindert die
                // USt-Zahllast, deshalb landet man bei den Steuerzahlungen im Ledger – wie von
                // der Umsatz- und der Einkommensteuer-Seite aus. **Ohne** Sparte: Steuerzeilen
                // zeigt die Tabelle nur bei Sparte „Alle", sonst bliebe sie leer.
                aktion: { nav.zeigeAusgabenJahr(jahr: w.jahr, art: .steuern, zeit: zeit) }
            ) {
                VStack(spacing: 2) {
                    Kartenzeile(
                        label: "Abziehbare Vorsteuer (betrieblich)", wert: w.a.vstGesamt, icon: "percent")
                    Text(
                        "Nur zur Einordnung: Die Vorsteuer mindert die USt-Zahllast, nicht den Gewinn – die EÜR rechnet deshalb mit Netto-Beträgen."
                    )
                    .erklaerung()
                }
            }
        }
    }
}
