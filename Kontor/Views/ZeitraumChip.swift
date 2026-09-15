import SwiftUI

/// Der Zeitraum-Umschalter aller Module: `‹ September 2026 ⌄ ›`.
///
/// Ersetzt die frühere `ZeitraumLeiste` aus Segmenten (Alle/Jahr/Monat), Jahr-Picker,
/// Monats-Picker und „Aktueller Monat"-Knopf durch **ein** Element. Zwei Gründe:
///
/// 1. **Er gehört in die Fenster-Toolbar.** Steuerelemente im Content-Bereich addieren ihre
///    Breite in die Mindestbreite des Fensters – bei der alten Leiste gut 420 pt, was zusammen
///    mit Seitenleiste, Tabelle und Inspector die Fensterbreite über den Bildschirm hinaus trieb
///    und auf macOS 26/27 zum Absturz führte (siehe CLAUDE.md). Toolbar-Items tun das nicht;
///    reicht der Platz nicht, schiebt AppKit sie selbst ins »-Überlaufmenü.
/// 2. **Die Pfeile ersetzen jeden Kalender.** Sie schieben in der Granularität des aktuellen
///    Modus, also im Quartals-Modus quartalsweise. Damit ist auch ein weit zurückliegender
///    Zeitraum erreichbar, ohne dass das Menü ein Datumsraster braucht.
struct ZeitraumChip: View {
    @Binding var filter: Zeitfilter
    /// Welche Granularitäten dieses Modul anbietet.
    var umfang: Zeitfilter.Umfang = .voll

    var body: some View {
        HStack(spacing: 2) {
            pfeil("chevron.left", hilfe: "Einen Zeitraum zurück") { filter.zurueck() }

            Menu(filter.beschriftung) { eintraege }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 6)
                .help("Zeitraum wählen")

            pfeil("chevron.right", hilfe: "Einen Zeitraum vor") { filter.vor() }
        }
        .padding(.horizontal, 4)
        // Hält den geteilten Zeitraum in dem, was dieses Modul auswerten kann. Ohne das zeigte
        // die Kopfzeile nach einem Modulwechsel „Q3 2026" an, während die Seite längst je Monat
        // rechnet.
        .onAppear { filter.begrenzeAuf(umfang) }
    }

    /// Ein Pfeil-Knopf. Die Klickfläche ist bewusst größer als das Symbol: Ein nacktes Chevron
    /// ist nur wenige Punkte breit und damit unangenehm zu treffen – und die beiden Pfeile sind
    /// die Bedienelemente, die hier am häufigsten benutzt werden.
    private func pfeil(_ symbol: String, hilfe: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol).font(.body.weight(.medium))
        }
        .buttonStyle(PfeilStil())
        .disabled(filter.modus == .alle)
        .help(hilfe)
    }

    @ViewBuilder private var eintraege: some View {
        if Zeitfilter.erlaubt(.monat, in: umfang) {
            Section {
                wahl("Dieser Monat", .dieserMonat())
                wahl("Letzter Monat", .letzterMonat())
            }
        }
        if Zeitfilter.erlaubt(.quartal, in: umfang) {
            Section {
                wahl("Dieses Quartal", .diesesQuartal())
                wahl("Letztes Quartal", .letztesQuartal())
            }
        }
        Section {
            wahl("Dieses Jahr", .diesesJahr())
            wahl("Letztes Jahr", .letztesJahr())
        }
        if Zeitfilter.erlaubt(.alle, in: umfang) {
            Section {
                wahl("Gesamt", .gesamt)
            }
        }
    }

    /// Ein Menüeintrag. Der aktive Zeitraum bekommt ein Häkchen, damit der Chip den Zustand
    /// zeigt und nicht nur ein Sprungbrett ist.
    private func wahl(_ titel: String, _ ziel: Zeitfilter) -> some View {
        Button {
            filter = ziel
        } label: {
            if istAktiv(ziel) {
                Label(titel, systemImage: "checkmark")
            } else {
                Text(titel)
            }
        }
    }

    /// Gleicht nur die Felder ab, die den Zeitraum ausmachen: Im Jahres-Modus ist der Monat
    /// bedeutungslos und darf das Häkchen nicht verhindern.
    private func istAktiv(_ ziel: Zeitfilter) -> Bool {
        guard filter.modus == ziel.modus else { return false }
        switch filter.modus {
        case .alle: return true
        case .jahr: return filter.jahr == ziel.jahr
        case .quartal: return filter.jahr == ziel.jahr && filter.quartal == ziel.quartal
        case .monat: return filter.jahr == ziel.jahr && filter.monat == ziel.monat
        }
    }
}

/// Knopf-Stil der beiden Pfeile: rundes Feld, das beim Überfahren und beim Drücken sichtbar
/// wird – so wie man es von den Zeitraum-Umschaltern anderer Mac-Apps kennt.
///
/// `.borderless` allein reicht dafür nicht: Der Stil zeigt weder Hover noch einen Druckzustand,
/// und ein Chevron ohne jede Rückmeldung wirkt wie Dekoration statt wie ein Knopf.
private struct PfeilStil: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Koerper(configuration: configuration)
    }

    /// Eigene View, weil `makeBody` kein `@State` halten kann – der Hover-Zustand gehört aber
    /// zu jedem Knopf einzeln.
    private struct Koerper: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var aktiv
        @State private var zeigerDarueber = false

        var body: some View {
            configuration.label
                .frame(width: 24, height: 24)
                .foregroundStyle(aktiv ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .background(Circle().fill(.primary.opacity(deckkraft)))
                .contentShape(Circle())
                .onHover { zeigerDarueber = $0 }
                .animation(.easeOut(duration: 0.12), value: zeigerDarueber)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }

        private var deckkraft: Double {
            guard aktiv else { return 0 }
            if configuration.isPressed { return 0.16 }
            return zeigerDarueber ? 0.08 : 0
        }
    }
}
