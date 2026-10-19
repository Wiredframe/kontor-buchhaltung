import SwiftUI

/// Jahresabschluss → EÜR: die Gewinnermittlung. Einnahmen (Zufluss) − betriebliche Ausgaben
/// (netto, Abfluss, Anlagegüter als AfA) = Gewinn. Darunter das Anlagenverzeichnis.
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
                    if w.a.afa != 0 {
                        Kartenzeile(
                            label: "darin Abschreibungen (AfA)", wert: w.a.afa, icon: "chart.line.downtrend.xyaxis")
                    }
                    Summenzeile(label: "Gewinn (EÜR)", wert: w.a.gewinn)
                    Text(
                        "Einnahmen nach Zahlungseingang (Zufluss), betriebliche Ausgaben netto nach Zahlung (Abfluss). Anlagegüter gehen mit ihrer Abschreibung ein, nicht mit dem Kaufpreis."
                    )
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

            let anlagen = Steuer.anlagen(w.ausP, jahr: w.jahr)
            if !anlagen.isEmpty { AnlagenverzeichnisKarte(anlagen: anlagen) }

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

/// Anlagenverzeichnis (Anlage AVEÜR): je Anlagegut Anschaffung, Buchwert zu Beginn, AfA des
/// Jahres und Restbuchwert. Klick auf einen Betrag kopiert ihn.
struct AnlagenverzeichnisKarte: View {
    let anlagen: [Anlagegut]

    var body: some View {
        Panel(titel: "Anlagenverzeichnis") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(anlagen, id: \.self) { a in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.bezeichnung.isEmpty ? "Anlagegut" : a.bezeichnung).fontWeight(.medium)
                        Text(
                            "angeschafft \(a.angeschafft.deutsch()) · \(a.kosten.euro) · \(a.nutzungsdauer) Jahre"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        if a.zugang {
                            Kartenzeile(label: "Zugang", wert: a.kosten, icon: "plus.circle")
                        } else {
                            Kartenzeile(label: "Buchwert zu Jahresbeginn", wert: a.buchwertAnfang, icon: "shippingbox")
                        }
                        Kartenzeile(label: "AfA", wert: a.afa, icon: "chart.line.downtrend.xyaxis", minus: true)
                        Kartenzeile(label: "Buchwert zum Jahresende", wert: a.buchwertEnde, icon: "shippingbox.fill")
                    }
                    if a != anlagen.last { Divider() }
                }
                Summenzeile(label: "AfA gesamt", wert: anlagen.reduce(Decimal(0)) { $0 + $1.afa })
                Text(
                    "Linear und monatsgenau ab dem Kaufmonat (§7 Abs. 1 EStG). Die Vorsteuer zählt voll beim Kauf. Diese Werte gehören in die Anlage AVEÜR."
                )
                .erklaerung()
            }
        }
    }
}
