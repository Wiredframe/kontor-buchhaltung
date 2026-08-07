import Charts
import SwiftUI

/// Kennzahl des Monats-Trendcharts.
enum TrendMetrik: String, CaseIterable, Identifiable {
    case gewinn, frei, ruecklage
    var id: String { rawValue }
    var kurz: String {
        switch self {
        case .gewinn: "Gewinn"
        case .frei: "Frei"
        case .ruecklage: "Rücklage"
        }
    }
    var lang: String {
        switch self {
        case .gewinn: "Betrieblicher Gewinn"
        case .frei: "Frei verfügbar"
        case .ruecklage: "Steuerrücklage"
        }
    }
    // Einfarbig im System-Akzent – der Picker sagt schon, welche Kennzahl gemeint ist.
    var farbe: Color { .accentColor }

    /// Wert des Punkts zu dieser Kennzahl; `nil`, wenn der Aufrufer die nötigen Daten
    /// nicht geliefert hat (siehe `Monatsreihe.Punkt.frei`).
    func wert(_ p: Monatsreihe.Punkt) -> Decimal? {
        switch self {
        case .gewinn: p.gewinn
        case .frei: p.frei
        case .ruecklage: p.steuerRuecklage
        }
    }
}

/// Monats-Balkenchart als Panel – geteilt von Übersicht (Dashboard) und Jahresabschluss.
///
/// Zwei Aufrufer, zwei Modi:
/// - **Dashboard**: eigener lokaler Jahres-State, interner Jahr-Picker, alle drei Kennzahlen.
/// - **Jahresabschluss**: Jahr hängt am `Zeitkontext` (der Wähler steht dort schon in der
///   Kopfleiste), deshalb `jahrWaehler: false` und nur `[.gewinn]` – dann entfällt auch der
///   Kennzahl-Picker und der Panel-Titel ist die Kennzahl selbst.
///
/// Die Daten kommen **hinein**, statt per eigenem `@Query` geholt zu werden: beide Aufrufer
/// haben die Arrays bereits geladen, ein zweiter Fetch wäre reine Verschwendung.
struct GewinnChartKarte: View {
    @Binding var jahr: Int
    var jahrWaehler: Bool = true
    var metriken: [TrendMetrik] = TrendMetrik.allCases
    let reihe: [Monatsreihe.Punkt]

    @State private var metrik: TrendMetrik = .gewinn

    /// Aktive Kennzahl, auf das Angebot des Aufrufers geklemmt – sonst zeigte eine Karte mit
    /// `metriken: [.ruecklage]` den Default `.gewinn` an.
    private var aktiv: TrendMetrik { metriken.contains(metrik) ? metrik : (metriken.first ?? .gewinn) }

    private var daten: [(name: String, wert: Double)] {
        reihe.compactMap { p in
            guard let d = aktiv.wert(p) else { return nil }
            return (name: kurzMonat(p.monat), wert: (d as NSDecimalNumber).doubleValue)
        }
    }

    private func kompakt(_ d: Double) -> String {
        Int(d.rounded()).formatted(.number.locale(Locale(identifier: "de_DE")))
    }
    /// Signierte Quadratwurzel: staucht Ausreißer (Mittelweg linear↔log), behält das Vorzeichen.
    private func wurzel(_ w: Double) -> Double { copysign(sqrt(abs(w)), w) }
    /// Y-Bereich mit Kopf-/Fußraum, damit die Wert-Labels über den Balken Platz haben.
    private func yBereich(_ daten: [(name: String, wert: Double)]) -> ClosedRange<Double> {
        let w = daten.map { wurzel($0.wert) }
        let oben = max(w.max() ?? 0, 0), unten = min(w.min() ?? 0, 0)
        let spanne = max(oben - unten, 1)
        return (unten - spanne * 0.04)...(oben + spanne * 0.18)
    }

    var body: some View {
        let d = daten
        return Panel(titel: aktiv.lang) {
            VStack(spacing: 10) {
                if metriken.count > 1 || jahrWaehler {
                    HStack {
                        if metriken.count > 1 {
                            Picker("Kennzahl", selection: $metrik) {
                                ForEach(metriken) { Text($0.kurz).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden().fixedSize()
                        }
                        Spacer()
                        if jahrWaehler { JahrWaehler(jahr: $jahr) }
                    }
                }
                Chart(d, id: \.name) { p in
                    BarMark(x: .value("Monat", p.name), y: .value(aktiv.kurz, wurzel(p.wert)), width: .ratio(0.7))
                        .foregroundStyle(aktiv.farbe)
                        .cornerRadius(5)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            if p.wert != 0 {
                                Text(kompakt(p.wert)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                }
                .chartXScale(domain: (1...12).map { kurzMonat($0) })
                .chartYScale(domain: yBereich(d))  // Kopfraum für die Wert-Labels über den Balken
                .chartYAxis(.hidden)  // Höhe per Quadratwurzel gestaucht; exakte Werte stehen an den Balken
                .frame(height: 240)
            }
        }
    }
}
