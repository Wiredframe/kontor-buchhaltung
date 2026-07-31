import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query private var einnahmen: [Income]
    @Query private var ausgaben: [ExpenseEntry]
    @Query private var jahre: [YearSettings]
    @Query private var tasks: [MonthlyTask]
    @Query private var lebensmittel: [GroceryEntry]
    @Query private var anschaffungen: [PurchaseEntry]
    @Query private var steuern: [TaxPayment]

    @Environment(Navigation.self) private var nav
    @State private var chartJahr = appKalender.component(.year, from: Date())
    @State private var chartMetrik: ChartMetrik = .gewinn

    private enum ChartMetrik: String, CaseIterable, Identifiable {
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
    }

    private var heute: Date { Date() }
    private var jahr: Int { appKalender.component(.year, from: heute) }
    private var monat: Int { appKalender.component(.month, from: heute) }
    private var quartal: Int { (monat - 1) / 3 + 1 }
    /// USt-VA-Rhythmus des laufenden Jahres – steuert, ob die USt-Zahllast als Monat oder Quartal gezeigt wird.
    private var rhythmus: UStVARhythmus { (jahre.first { $0.jahr == jahr })?.ustvaRhythmus ?? .vierteljaehrlich }
    private var ustvaPeriode: Periode {
        rhythmus == .monatlich ? Periode.monat(jahr, monat) : Periode.quartal(jahr, quartal)
    }
    private var ustvaLabel: String { rhythmus == .monatlich ? monatsName(monat) : "Q\(quartal)" }
    /// Das Jahr ist **Parameter**, nicht das laufende: Der Trend-Chart zeigt wahlweise ein
    /// früheres Jahr, und die privaten Fixkosten sind datierte Buchungen – ohne das Jahr zöge
    /// jeder Chart-Balken die Fixkosten des laufenden Jahres heran.
    private func fixkostenPrivat(jahr: Int, _ m: Int) -> Decimal {
        ausgaben.wiederkehrendBrutto(jahr: jahr, monat: m, betrieblich: false)
    }

    private struct Mon { var rn, gewinn, steuerRuecklage, frei: Decimal }
    /// Monatswerte aus **einmal** gemappten Posten-Arrays (der Aufrufer mappt je Render einmal).
    /// Rechnet nichts selbst – der Gewinn-Waterfall liegt in `MonatsAuswertung`.
    private func werteFuer(jahr: Int, monat m: Int, einP: [EinnahmePosten], ausP: [AusgabePosten]) -> Mon {
        let p = Periode.monat(jahr, m)
        let lm = lebensmittel.filter { p.enthaelt($0.datum) }.reduce(Decimal(0)) { $0 + $1.betrag }
        let an = anschaffungen.filter { p.enthaelt($0.datum) }.reduce(Decimal(0)) { $0 + $1.preis }
        let einmalig = ausgaben.privatEinmaligBrutto(jahr: jahr, monat: m)
        let a = Steuer.monatsauswertung(
            monat: m, jahr: jahr,
            einnahmen: einP, ausgaben: ausP,
            kskFuer: { jahre.ksk(jahr: $0, monat: $1) },
            fixkostenPrivat: fixkostenPrivat(jahr: jahr, m),
            privatVariabel: lm + an + einmalig,
            pauschalSatz: { jahre.estSatz(jahr: $0, monat: $1) })
        return Mon(
            rn: a.rn, gewinn: a.betrieblicherGewinn, steuerRuecklage: a.steuerRuecklage,
            frei: a.verfuegbar)
    }

    private var offene: [Income] { einnahmen.filter { $0.status == .offen } }
    private var offeneSumme: Decimal { offene.reduce(0) { $0 + $1.brutto } }

    private func chartDaten(einP: [EinnahmePosten], ausP: [AusgabePosten]) -> [(name: String, wert: Double)] {
        (1...12).compactMap { m in
            guard !istZukunftsmonat(m, jahr: chartJahr) else { return nil }  // keine Balken für künftige Monate
            let w = werteFuer(jahr: chartJahr, monat: m, einP: einP, ausP: ausP)
            let d: Decimal =
                switch chartMetrik {
                case .gewinn: w.gewinn
                case .frei: w.frei
                case .ruecklage: w.steuerRuecklage
                }
            return (name: kurzMonat(m), wert: (d as NSDecimalNumber).doubleValue)
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
        Group {
            if einnahmen.isEmpty && ausgaben.isEmpty {
                leererStart
            } else {
                inhalt
            }
        }
        .seitenGrund()
        .navigationTitle("Übersicht")
    }

    /// Onboarding für eine frische, leere Datenbank – führt statt vier 0,00-€-Kacheln.
    private var leererStart: some View {
        ContentUnavailableView {
            Label("Noch keine Daten", systemImage: "tray")
        } description: {
            Text(
                "Erfasse deine erste Einnahme oder importiere einen Kontoauszug – danach zeigt die Übersicht Umsatz, Rücklagen und Trends."
            )
        } actions: {
            Button {
                nav.modul = .einnahmen
            } label: {
                Label("Einnahme erfassen", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            Button {
                nav.modul = .kontoauszug
            } label: {
                Label("Kontoauszug importieren", systemImage: "tray.and.arrow.down")
            }
            Button {
                nav.modul = .einstellungen
            } label: {
                Label("Einstellungen öffnen", systemImage: "gearshape")
            }
            .buttonStyle(.link)
        }
    }

    private var inhalt: some View {
        let einP = einnahmen.flatMap(\.postenListe), ausP = ausgaben.map(\.posten)
        let akt = werteFuer(jahr: jahr, monat: monat, einP: einP, ausP: ausP)
        let ustVA = Steuer.ustva(einnahmen: einP, ausgaben: ausP, periode: ustvaPeriode).zahllast
        let chart = chartDaten(einP: einP, ausP: ausP)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                trendKarte(daten: chart)
                kpis(akt: akt, ustVA: ustVA)
                schnellstartAbschnitt
            }
            .padding()
        }
    }

    /// Abschnitts-Überschrift über einem Karten-Raster (wie ein Panel-Titel, ohne eigene Karte).
    private func abschnitt(_ titel: String) -> some View {
        Text(titel).font(.title3).fontWeight(.semibold).padding(.horizontal, 4)
    }

    // MARK: KPIs

    private func kpis(akt: Mon, ustVA: Decimal) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            Kennzahl(titel: "Offene Rechnungen", wert: offeneSumme, symbol: "tray.full")
            Kennzahl(titel: "USt-Zahllast \(ustvaLabel)", wert: ustVA, symbol: "building.columns")
            Kennzahl(titel: "Umsatz \(monatsName(monat))", wert: akt.rn, symbol: "eurosign.circle")
        }
    }

    // MARK: Trend

    private func trendKarte(daten: [(name: String, wert: Double)]) -> some View {
        Panel(titel: chartMetrik.lang) {
            VStack(spacing: 10) {
                HStack {
                    Picker("Kennzahl", selection: $chartMetrik) {
                        ForEach(ChartMetrik.allCases) { Text($0.kurz).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                    JahrWaehler(jahr: $chartJahr)
                }
                Chart(daten, id: \.name) { d in
                    BarMark(x: .value("Monat", d.name), y: .value(chartMetrik.kurz, wurzel(d.wert)), width: .ratio(0.7))
                        .foregroundStyle(chartMetrik.farbe)
                        .cornerRadius(5)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            if d.wert != 0 {
                                Text(kompakt(d.wert)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                }
                .chartXScale(domain: (1...12).map { kurzMonat($0) })
                .chartYScale(domain: yBereich(daten))  // Kopfraum für die Wert-Labels über den Balken
                .chartYAxis(.hidden)  // Höhe per Quadratwurzel gestaucht; exakte Werte stehen an den Balken
                .frame(height: 240)
            }
        }
    }

    // MARK: Schnellstart (Onboarding-Shortcuts in Workflow-Reihenfolge)

    private var schnellstartAbschnitt: some View {
        let schritte: [(titel: String, beschreibung: String, icon: String, modul: Modul)] = [
            (
                "Einnahmen & Rechnungen", "Rechnungen erfassen, Zahlungseingänge verfolgen.",
                "eurosign.circle", .einnahmen
            ),
            (
                "Ausgaben erfassen", "Betriebsausgaben, Fixkosten und Belege ablegen.",
                "creditcard", .betriebsausgaben
            ),
            (
                "Kontoauszug importieren", "Sparkasse-CSV zuordnen – lernt deine Zuordnungen.",
                "tray.and.arrow.down", .kontoauszug
            ),
            (
                "Monat abschließen", "Gewinn, Rücklagen und frei verfügbar prüfen.",
                "checkmark.seal", .monatsabschluss
            ),
            ("UStVA prüfen", "Zahllast je Quartal, ELSTER-Kennzahlen ablesen.", "doc.text", .ustva),
            (
                "Jahresabschluss", "EÜR, Steuerlast und tatsächlich Gezahltes.",
                "chart.bar.doc.horizontal", .jahresuebersicht
            ),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            abschnitt("Schnellstart")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(Array(schritte.enumerated()), id: \.offset) { _, s in
                    Button {
                        nav.modul = s.modul
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: s.icon).foregroundStyle(.white).font(.callout)
                                    .frame(width: 30, height: 30).background(Color.accentColor, in: Circle())
                                Text(s.titel).font(.headline).foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            Text(s.beschreibung).font(.caption).foregroundStyle(.secondary)
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
