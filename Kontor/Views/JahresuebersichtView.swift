import SwiftData
import SwiftUI

/// Jahresabschluss – **Übersicht**: die vier Kernzahlen des Jahres, der Gewinn-Verlauf über die
/// Monate und die Einstiege in die vier Detail-Bereiche.
///
/// Die Details (EÜR, Einkommensteuer, Umsatzsteuer, Vorsorge) liegen seit dem Umbau auf eigenen
/// Unterseiten. Vorher stand alles auf einer Seite: vier Kennzahlen, EÜR, drei Soll/Ist-Paare und
/// die sonstigen Zahlungen – eine Wand aus Zahlen, in der man nichts wiederfand.
struct JahresuebersichtView: View {
    @Environment(Zeitkontext.self) private var zeit
    @Environment(Navigation.self) private var nav
    @Query private var jahre: [YearSettings]

    var body: some View {
        JahresSeite(titel: "Jahresabschluss", kopfRechts: { BelegeExportButton() }) { w in
            // Kernzahlen auf einen Blick – Detail in den Bereichen darunter.
            AbschlussHero([
                .init(titel: "Gewinn (EÜR)", wert: w.a.gewinn),
                .init(titel: "ESt-Rücklage", wert: w.estRuecklage),
                .init(titel: "USt-Zahllast", wert: w.ustJahr),
                .init(titel: "KSK (Vorsorge)", wert: w.kskGesamt),
            ])

            Text(
                "Der Gewinn stammt aus der EÜR (Zuflussprinzip), daraus leiten sich ESt und USt als Schätzungen ab. Jeder Bereich zeigt **oben die Schätzung, darunter das tatsächlich Gezahlte**. Vorlage für die Erklärung, keine finale Erklärung."
            )
            .erklaerung()

            GewinnChartKarte(
                jahr: jahrBindung, jahrWaehler: false, metriken: [.gewinn],
                reihe: Monatsreihe.jahr(
                    w.jahr, einnahmen: w.einP, ausgaben: w.ausP,
                    kskFuer: { jahre.ksk(jahr: $0, monat: $1) },
                    satzFuer: { jahre.estSatz(jahr: $0, monat: $1) }))

            bereiche
        }
    }

    /// Das Chart hängt am Zeitkontext-Jahr – der Wähler steht schon in der Kopfleiste,
    /// deshalb blendet die Karte ihren eigenen aus.
    private var jahrBindung: Binding<Int> {
        @Bindable var zeit = zeit
        return $zeit.filter.jahr
    }

    // MARK: Einstiege in die Detail-Bereiche

    private var bereiche: some View {
        let karten: [(titel: String, beschreibung: String, icon: String, modul: Modul)] = [
            ("EÜR", "Betriebseinnahmen, Betriebsausgaben, Gewinn.", "function", .jahresEUR),
            (
                "Einkommensteuer", "Rücklage, voraussichtliche ESt, Bescheid und Vorauszahlungen.",
                "percent", .jahresESt
            ),
            ("Umsatzsteuer", "Zahllast je Voranmeldung und tatsächlich gezahlt.", "building.columns", .jahresUSt),
            ("Vorsorge (KSK)", "KV, RV, PV im Jahr: Soll gegen Abbuchungen.", "cross.case", .jahresVorsorge),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Bereiche").font(.title3).fontWeight(.semibold).padding(.horizontal, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(Array(karten.enumerated()), id: \.offset) { _, k in
                    Button {
                        nav.modul = k.modul
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: k.icon).foregroundStyle(.white).font(.callout)
                                    .frame(width: 30, height: 30).background(Color.accentColor, in: Circle())
                                Text(k.titel).font(.headline).foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            Text(k.beschreibung).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .karte()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
