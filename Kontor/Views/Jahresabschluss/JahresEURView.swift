import SwiftUI

/// Jahresabschluss → EÜR: die Gewinnermittlung. Einnahmen (Zufluss) − betriebliche Ausgaben
/// (netto) = Gewinn.
struct JahresEURView: View {
    @Environment(Zeitkontext.self) private var zeit
    @Environment(Navigation.self) private var nav

    var body: some View {
        JahresSeite(titel: "EÜR") { w in
            Panel(
                titel: "Einnahmenüberschussrechnung (EÜR)",
                aktion: { nav.zeigeAusgabenJahr(jahr: w.jahr, betrieblich: true, zeit: zeit) }
            ) {
                VStack(spacing: 2) {
                    Kartenzeile(
                        label: "Betriebseinnahmen (Zufluss, netto)", wert: w.a.einnahmenBezahlt,
                        icon: "eurosign.circle")
                    Kartenzeile(
                        label: "Betriebsausgaben (netto)", wert: w.a.ausgabenNetto, icon: "creditcard",
                        minus: true)
                    Summenzeile(label: "Gewinn (EÜR)", wert: w.a.gewinn)
                    Text(
                        "Einnahmen nach Zahlungseingang (Zufluss), betriebliche Ausgaben netto. Klick öffnet die betrieblichen Ausgaben des Jahres."
                    )
                    .erklaerung()
                }
            }

            Panel(titel: "Vorsteuer im Jahr") {
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
