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

    /// Der Zeitraum **so, wie dieses Modul ihn sieht**.
    ///
    /// Der `Zeitfilter` ist modulübergreifend geteilt, aber nicht jedes Modul kann mit jeder
    /// Granularität rechnen. Statt den geteilten Zustand beim Erscheinen zurechtzubiegen,
    /// normalisiert der Chip ihn **nur für sich**: Beschriftung und Pfeile arbeiten auf dieser
    /// Kopie, geschrieben wird erst, wenn jemand wirklich klickt.
    ///
    /// **Das ist keine Kosmetik, sondern der Grund für einen Absturz gewesen.** Vorher stand
    /// hier ein `onAppear`, das `begrenzeAuf(umfang)` auf dem Binding aufrief. `begrenzeAuf` ist
    /// `mutating` und löst über ein `@Binding` auch dann einen Schreibvorgang aus, wenn sich
    /// nichts ändert – und eine Zustandsänderung mitten im Aufbau eines Modulwechsels zerreißt
    /// den AttributeGraph (`AG::precondition_failure` aus der Sidebar-Outline, reproduzierbar
    /// beim Wechsel in ein schmales Fenster). Rein lesend gibt es das Problem nicht.
    private var sicht: Zeitfilter {
        var f = filter
        f.begrenzeAuf(umfang)
        return f
    }

    var body: some View {
        HStack(spacing: 2) {
            pfeil("chevron.left", hilfe: "Einen Zeitraum zurück") { schiebe { $0.zurueck() } }

            // Eigenes Label statt `Menu(titel)`: nur so lässt sich der Abstand zum Chevron
            // setzen und dem Text eine **Mindestbreite** geben. Ohne die wandern die beiden
            // Pfeile bei jedem Wechsel der Beschriftung („September 2026" gegen „Q3 2026")
            // ein Stück – man zielt dann jedes Mal woandershin.
            Menu {
                eintraege
            } label: {
                HStack(spacing: 7) {
                    Text(sicht.beschriftung)
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
                .frame(minWidth: 118)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 4)
            .help("Zeitraum wählen")

            pfeil("chevron.right", hilfe: "Einen Zeitraum vor") { schiebe { $0.vor() } }
        }
        .padding(.horizontal, 4)
    }

    /// Verschiebt den Zeitraum. Arbeitet auf `sicht`, damit ein Pfeilklick in einem Modul mit
    /// eingeschränktem Umfang die richtige Schrittweite nimmt (und dabei den geteilten Filter
    /// gleich mit normalisiert – hier ist das erlaubt, es ist eine Nutzeraktion).
    private func schiebe(_ schritt: (inout Zeitfilter) -> Void) {
        var f = sicht
        schritt(&f)
        filter = f
    }

    /// Ein Pfeil-Knopf. Die Klickfläche ist bewusst größer als das Symbol: Ein nacktes Chevron
    /// ist nur wenige Punkte breit und damit unangenehm zu treffen – und die beiden Pfeile sind
    /// die Bedienelemente, die hier am häufigsten benutzt werden.
    private func pfeil(_ symbol: String, hilfe: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol).font(.title3.weight(.medium))
        }
        .buttonStyle(PfeilStil())
        .disabled(sicht.modus == .alle)
        .help(hilfe)
    }

    /// Die Schnellwahl als **inline-`Picker`**, nicht als Knopfliste.
    ///
    /// Grund ist das Häkchen: Ein `Button` mit `Label(…, systemImage: "checkmark")` rendert im
    /// macOS-Menü kein Häkchen, ein `Picker` setzt es von selbst an den ausgewählten Eintrag –
    /// und zwar genauso, wie es das Filtermenü der Ausgaben-View schon tut. So sieht man dem
    /// geöffneten Menü an, welcher Zeitraum gerade gilt, statt es nur als Sprungbrett zu haben.
    @ViewBuilder private var eintraege: some View {
        Picker("Zeitraum", selection: auswahl) {
            if Zeitfilter.erlaubt(.monat, in: umfang) {
                Text("Dieser Monat").tag(Schnellwahl.dieserMonat)
                Text("Letzter Monat").tag(Schnellwahl.letzterMonat)
                Divider()
            }
            if Zeitfilter.erlaubt(.quartal, in: umfang) {
                Text("Dieses Quartal").tag(Schnellwahl.diesesQuartal)
                Text("Letztes Quartal").tag(Schnellwahl.letztesQuartal)
                Divider()
            }
            if Zeitfilter.erlaubt(.jahr, in: umfang) {
                Text("Dieses Jahr").tag(Schnellwahl.diesesJahr)
                Text("Letztes Jahr").tag(Schnellwahl.letztesJahr)
            }
            if Zeitfilter.erlaubt(.alle, in: umfang) {
                Divider()
                Text("Gesamt").tag(Schnellwahl.gesamt)
            }
        }
        .pickerStyle(.inline)
    }

    /// Die angebotenen Zeiträume. `.keiner` steht für „mit den Pfeilen irgendwohin gewandert" –
    /// dann ist keiner der Einträge angehakt, was genau richtig ist.
    private enum Schnellwahl: Hashable {
        case keiner, dieserMonat, letzterMonat, diesesQuartal, letztesQuartal
        case diesesJahr, letztesJahr, gesamt

        var filter: Zeitfilter? {
            switch self {
            case .keiner: nil
            case .dieserMonat: .dieserMonat()
            case .letzterMonat: .letzterMonat()
            case .diesesQuartal: .diesesQuartal()
            case .letztesQuartal: .letztesQuartal()
            case .diesesJahr: .diesesJahr()
            case .letztesJahr: .letztesJahr()
            case .gesamt: .gesamt
            }
        }
    }

    private var auswahl: Binding<Schnellwahl> {
        Binding(
            get: { aktuelle },
            set: { if let neu = $0.filter { filter = neu } }
        )
    }

    /// Welcher Eintrag trägt gerade das Häkchen?
    ///
    /// Verglichen wird nur, was den Zeitraum ausmacht: Im Jahres-Modus ist der Monat
    /// bedeutungslos und darf das Häkchen nicht verhindern.
    private var aktuelle: Schnellwahl {
        let kandidaten: [Schnellwahl] = [
            .dieserMonat, .letzterMonat, .diesesQuartal, .letztesQuartal,
            .diesesJahr, .letztesJahr, .gesamt,
        ]
        return kandidaten.first { passt($0.filter) } ?? .keiner
    }

    private func passt(_ ziel: Zeitfilter?) -> Bool {
        let s = sicht
        guard let ziel, s.modus == ziel.modus else { return false }
        switch s.modus {
        case .alle: return true
        case .jahr: return s.jahr == ziel.jahr
        case .quartal: return s.jahr == ziel.jahr && s.quartal == ziel.quartal
        case .monat: return s.jahr == ziel.jahr && s.monat == ziel.monat
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
                .frame(width: 30, height: 28)
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
