import SwiftUI
import SwiftData
import Charts

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
        var kurz: String { switch self { case .gewinn: "Gewinn"; case .frei: "Frei"; case .ruecklage: "Rücklage" } }
        var lang: String { switch self { case .gewinn: "Betrieblicher Gewinn"; case .frei: "Frei verfügbar"; case .ruecklage: "Steuerrücklage" } }
        var farbe: Color { switch self { case .gewinn: Stil.gewinn; case .frei: Stil.einnahmen; case .ruecklage: Stil.steuer } }
    }

    private var heute: Date { Date() }
    private var jahr: Int { appKalender.component(.year, from: heute) }
    private var monat: Int { appKalender.component(.month, from: heute) }
    private var quartal: Int { (monat - 1) / 3 + 1 }
    /// USt-VA-Rhythmus des laufenden Jahres – steuert, ob die USt-Zahllast als Monat oder Quartal gezeigt wird.
    private var rhythmus: UStVARhythmus { (jahre.first { $0.jahr == jahr })?.ustvaRhythmus ?? .vierteljaehrlich }
    private var ustvaPeriode: Periode { rhythmus == .monatlich ? Periode.monat(jahr, monat) : Periode.quartal(jahr, quartal) }
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
        return Mon(rn: a.rn, gewinn: a.betrieblicherGewinn, steuerRuecklage: a.steuerRuecklage,
                   frei: a.verfuegbar)
    }

    private var offene: [Income] { einnahmen.filter { $0.status == .offen } }
    private var offeneSumme: Decimal { offene.reduce(0) { $0 + $1.brutto } }
    private var naechsteFrist: (titel: String, datum: Date)? {
        let start = appKalender.startOfDay(for: heute)
        var kandidaten: [(String, Date)] = []
        kandidaten += tasks.filter { !$0.erledigt && $0.monat >= start }.map { ($0.titel, $0.monat) }
        kandidaten += steuern.filter { !$0.bezahlt && $0.faellig >= start }.map { ($0.kind.bezeichnung, $0.faellig) }
        return kandidaten.min { $0.1 < $1.1 }.map { ($0.0, $0.1) }
    }

    private func insights(akt: Mon, vormonat: Mon?, ustVA: Decimal) -> [String] {
        var r: [String] = []
        if akt.frei < 0 {
            r.append("Der laufende Monat ist nach allen Ausgaben negativ (\(akt.frei.euro)) – Einnahmen oder Ausgaben prüfen.")
        }
        if !offene.isEmpty {
            r.append("\(offene.count) offene Rechnung(en) über \(offeneSumme.euro) – Zahlungseingänge im Blick behalten.")
        }
        if ustVA > 0 {
            r.append("USt-Zahllast \(ustvaLabel) liegt aktuell bei \(ustVA.euro) (fällig nach \(rhythmus == .monatlich ? "Monatsende" : "Quartalsende")).")
        }
        if let v = vormonat, akt.gewinn > v.gewinn {
            r.append("Betrieblicher Gewinn über dem Vormonat (\(akt.gewinn.euro) vs. \(v.gewinn.euro)).")
        }
        if r.isEmpty { r.append("Alles im grünen Bereich – keine Auffälligkeiten.") }
        return Array(r.prefix(4))
    }

    private func chartDaten(einP: [EinnahmePosten], ausP: [AusgabePosten]) -> [(name: String, wert: Double)] {
        (1...12).compactMap { m in
            guard !istZukunftsmonat(m, jahr: chartJahr) else { return nil }   // keine Balken für künftige Monate
            let w = werteFuer(jahr: chartJahr, monat: m, einP: einP, ausP: ausP)
            let d: Decimal = switch chartMetrik { case .gewinn: w.gewinn; case .frei: w.frei; case .ruecklage: w.steuerRuecklage }
            return (name: kurzMonat(m), wert: (d as NSDecimalNumber).doubleValue)
        }
    }
    private func kompakt(_ d: Double) -> String { Int(d.rounded()).formatted(.number.locale(Locale(identifier: "de_DE"))) }
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
        .navigationTitle("Übersicht")
    }

    /// Onboarding für eine frische, leere Datenbank – führt statt vier 0,00-€-Kacheln.
    private var leererStart: some View {
        ContentUnavailableView {
            Label("Noch keine Daten", systemImage: "tray")
        } description: {
            Text("Erfasse deine erste Einnahme oder importiere einen Kontoauszug – danach zeigt die Übersicht Umsatz, Rücklagen und Trends.")
        } actions: {
            Button { nav.modul = .einnahmen } label: { Label("Einnahme erfassen", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
            Button { nav.modul = .kontoauszug } label: { Label("Kontoauszug importieren", systemImage: "tray.and.arrow.down") }
            Button { nav.modul = .einstellungen } label: { Label("Einstellungen öffnen", systemImage: "gearshape") }
                .buttonStyle(.link)
        }
    }

    private var inhalt: some View {
        let einP = einnahmen.flatMap(\.postenListe), ausP = ausgaben.map(\.posten)
        let akt = werteFuer(jahr: jahr, monat: monat, einP: einP, ausP: ausP)
        let vormonat = monat > 1 ? werteFuer(jahr: jahr, monat: monat - 1, einP: einP, ausP: ausP) : nil
        let ustVA = Steuer.ustva(einnahmen: einP, ausgaben: ausP, periode: ustvaPeriode).zahllast
        let chart = chartDaten(einP: einP, ausP: ausP)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                kpis(akt: akt, ustVA: ustVA)
                trendKarte(daten: chart)
                insightsKarte(akt: akt, vormonat: vormonat, ustVA: ustVA)
            }
            .padding()
        }
    }

    // MARK: KPIs

    private func kpis(akt: Mon, ustVA: Decimal) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            Kennzahl(titel: "Offene Rechnungen", wert: offeneSumme, symbol: "tray.full")
            Kennzahl(titel: "USt-Zahllast \(ustvaLabel)", wert: ustVA, symbol: "building.columns")
            Kennzahl(titel: "Umsatz \(monatsName(monat))", wert: akt.rn, symbol: "eurosign.circle")
            fristKarte
        }
    }
    /// „Nächste Frist" im Kennzahl-Card-Stil (Datum als Hauptwert, Titel als Untertitel).
    private var fristKarte: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                Text("Nächste Frist").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            if let f = naechsteFrist {
                Text(f.datum, format: .dateTime.day().month().year())
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(f.titel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("—").font(.system(size: 22, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .karte()
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
                        .foregroundStyle(chartMetrik.farbe.gradient)
                        .cornerRadius(5)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            if d.wert != 0 {
                                Text(kompakt(d.wert)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                }
                .chartXScale(domain: (1...12).map { kurzMonat($0) })
                .chartYScale(domain: yBereich(daten))   // Kopfraum für die Wert-Labels über den Balken
                .chartYAxis(.hidden)   // Höhe per Quadratwurzel gestaucht; exakte Werte stehen an den Balken
                .frame(height: 240)
            }
        }
    }

    // MARK: Insights

    private func insightsKarte(akt: Mon, vormonat: Mon?, ustVA: Decimal) -> some View {
        Panel(titel: "Hinweise") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(insights(akt: akt, vormonat: vormonat, ustVA: ustVA), id: \.self) { text in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(.yellow).font(.callout)
                        Text(text)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
