import SwiftUI
import SwiftData
import Charts

struct PrivatUebersichtView: View {
    @Query private var alleAusgaben: [ExpenseEntry]
    @Query private var lebensmittel: [GroceryEntry]
    @Query private var anschaffungen: [PurchaseEntry]

    @Environment(Zeitkontext.self) private var zeit
    @Environment(Navigation.self) private var nav
    @State private var chartMetrik: PrivatMetrik = .gesamt
    private var jahr: Int { zeit.filter.jahr }
    private var monat: Int { zeit.filter.monat }

    private enum PrivatMetrik: String, CaseIterable, Identifiable {
        case gesamt, lebensmittel, einkaeufe
        var id: String { rawValue }
        var kurz: String { switch self { case .gesamt: "Gesamt"; case .lebensmittel: "Lebensmittel"; case .einkaeufe: "Einkäufe" } }
        var lang: String { switch self { case .gesamt: "Privatausgaben gesamt"; case .lebensmittel: "Lebensmittel"; case .einkaeufe: "Einkäufe" } }
    }

    private var periode: Periode { Periode.monat(jahr, monat) }

    /// Private wiederkehrende Buchungen (Fixkosten/Subscriptions) des gewählten Monats –
    /// aus den **datierten `ExpenseEntry`** (gleiche Quelle wie Monatsabschluss/Dashboard),
    /// nicht mehr aus den abgelösten Alt-Modellen.
    private func privateWiederkehrend(_ art: AusgabeArt) -> [ExpenseEntry] {
        alleAusgaben
            .filter { !$0.betrieblich && $0.artEffektiv == art && periode.enthaelt($0.datum) }
            .sorted { $0.datum < $1.datum }
    }
    private var fixkosten: [ExpenseEntry] { privateWiederkehrend(.fixkosten) }
    private var abos: [ExpenseEntry] { privateWiederkehrend(.subscription) }
    private var summeFixkosten: Decimal { fixkosten.reduce(0) { $0 + $1.brutto } }
    private var summeAbos: Decimal { abos.reduce(0) { $0 + $1.brutto } }

    private var lebensmittelMonat: Decimal {
        lebensmittel.filter { periode.enthaelt($0.datum) }.reduce(0) { $0 + $1.betrag }
    }
    private var einkaeufeMonat: Decimal {
        anschaffungen.filter { periode.enthaelt($0.datum) }.reduce(0) { $0 + $1.preis }
    }
    private var istAktuell: Bool {
        jahr == appKalender.component(.year, from: Date()) && monat == appKalender.component(.month, from: Date())
    }
    private func aufHeute() {
        zeit.filter.jahr = appKalender.component(.year, from: Date())
        zeit.filter.monat = appKalender.component(.month, from: Date())
    }

    // Verlauf über das gewählte Jahr – je Monat die tatsächlich erfassten Beträge.
    private var chartDaten: [(name: String, wert: Double)] {
        (1...12).compactMap { m in
            guard !istZukunftsmonat(m, jahr: jahr) else { return nil }   // keine Balken für künftige Monate
            let p = Periode.monat(jahr, m)
            let lm = lebensmittel.filter { p.enthaelt($0.datum) }.reduce(Decimal(0)) { $0 + $1.betrag }
            let ek = anschaffungen.filter { p.enthaelt($0.datum) }.reduce(Decimal(0)) { $0 + $1.preis }
            let fix = alleAusgaben.wiederkehrendBrutto(jahr: jahr, monat: m, betrieblich: false)
            let d: Decimal = switch chartMetrik {
                case .gesamt:       fix + lm + ek
                case .lebensmittel: lm
                case .einkaeufe:    ek
            }
            return (name: kurzMonat(m), wert: (d as NSDecimalNumber).doubleValue)
        }
    }
    var body: some View {
        @Bindable var zeit = zeit
        return VStack(spacing: 0) {
            HStack {
                MonatJahrWaehler(jahr: $zeit.filter.jahr, monat: $zeit.filter.monat)
                HeuteButton(deaktiviert: istAktuell) { aufHeute() }
                Spacer()
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                        Kennzahl(titel: "Fixkosten (\(monatsName(monat)))", wert: summeFixkosten, symbol: "house", akzent: Stil.privat)
                        Kennzahl(titel: "Subscriptions (\(monatsName(monat)))", wert: summeAbos, symbol: "arrow.triangle.2.circlepath", akzent: Stil.privat)
                        Kennzahl(titel: "Lebensmittel (\(monatsName(monat)))", wert: lebensmittelMonat, symbol: "cart", akzent: Stil.privat)
                        Kennzahl(titel: "Einkäufe (\(monatsName(monat)))", wert: einkaeufeMonat, symbol: "bag", akzent: Stil.privat)
                    }

                    diagramm

                    HStack(alignment: .top, spacing: 14) {
                        Panel(titel: "Private Fixkosten",
                              aktion: { nav.zeigeAusgaben(jahr: jahr, monat: monat, art: .fixkosten, betrieblich: false, zeit: zeit) }) {
                            if fixkosten.isEmpty { leer() }
                            else { VStack(spacing: 2) { ForEach(fixkosten) { zeile($0.bezeichnung, $0.brutto) } } }
                        }
                        .frame(maxWidth: .infinity)
                        Panel(titel: "Private Subscriptions",
                              aktion: { nav.zeigeAusgaben(jahr: jahr, monat: monat, art: .subscription, betrieblich: false, zeit: zeit) }) {
                            if abos.isEmpty { leer() }
                            else { VStack(spacing: 2) { ForEach(abos) { zeile($0.bezeichnung, $0.brutto) } } }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Text("Fixkosten und Subscriptions sind die im gewählten Monat erfassten wiederkehrenden Buchungen (Sparte privat); Lebensmittel und Einkäufe zeigen die im jeweiligen Monat erfassten Ausgaben.")
                        .font(.footnote).foregroundStyle(.tertiary)
                }
                .padding()
            }
        }
        .navigationTitle("Privat-Übersicht")
    }

    private var diagramm: some View {
        Panel(titel: chartMetrik.lang) {
            VStack(spacing: 10) {
                Picker("Kennzahl", selection: $chartMetrik) {
                    ForEach(PrivatMetrik.allCases) { Text($0.kurz).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                Chart(chartDaten, id: \.name) { d in
                    BarMark(x: .value("Monat", d.name), y: .value(chartMetrik.kurz, wurzel(d.wert)), width: .ratio(0.7))
                        .foregroundStyle(Stil.privat.gradient)
                        .cornerRadius(5)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            if d.wert != 0 {
                                Text(kompakt(d.wert)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                }
                .chartXScale(domain: (1...12).map { kurzMonat($0) })
                .chartYScale(domain: yBereich)   // Kopfraum für die Wert-Labels über den Balken
                .chartYAxis(.hidden)   // Höhe per Quadratwurzel gestaucht; exakte Werte stehen an den Balken
                .frame(height: 240)
            }
        }
    }

    private func zeile(_ titel: String, _ wert: Decimal) -> some View {
        HStack {
            Text(titel.isEmpty ? "—" : titel)
            Spacer()
            Text(wert.euro).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
    private func leer() -> some View {
        Text("Keine Einträge.").font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }
    private func kompakt(_ d: Double) -> String { Int(d.rounded()).formatted(.number.locale(Locale(identifier: "de_DE"))) }
    /// Signierte Quadratwurzel: staucht Ausreißer (Mittelweg linear↔log), behält das Vorzeichen.
    private func wurzel(_ w: Double) -> Double { copysign(sqrt(abs(w)), w) }
    /// Y-Bereich mit Kopf-/Fußraum, damit die Wert-Labels über den Balken Platz haben.
    private var yBereich: ClosedRange<Double> {
        let w = chartDaten.map { wurzel($0.wert) }
        let oben = max(w.max() ?? 0, 0), unten = min(w.min() ?? 0, 0)
        let spanne = max(oben - unten, 1)
        return (unten - spanne * 0.04)...(oben + spanne * 0.18)
    }
}
