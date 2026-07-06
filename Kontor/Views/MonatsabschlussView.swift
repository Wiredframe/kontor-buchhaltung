import SwiftUI
import SwiftData
import AppKit

struct MonatsabschlussView: View {
    @Environment(Navigation.self) private var nav

    @Query private var ausgaben: [ExpenseEntry]
    @Query private var einnahmen: [Income]
    @Query private var jahre: [YearSettings]
    @Query private var tasks: [MonthlyTask]
    @Query private var lebensmittel: [GroceryEntry]
    @Query private var anschaffungen: [PurchaseEntry]

    @Environment(Zeitkontext.self) private var zeit
    private var jahr: Int { zeit.filter.jahr }
    private var monat: Int { zeit.filter.monat }
    @State private var jahresansicht = false
    @State private var zeigeAufgaben = true
    @State private var sidebarModus: SidebarModus = .aufgaben

    private enum SidebarModus: String, CaseIterable, Identifiable {
        case werte = "Werte", aufgaben = "Aufgaben"
        var id: String { rawValue }
    }

    // MARK: Abgeleitete Daten

    /// Einstellungen **genau dieses Jahres** – kein Fallback auf ein anderes Jahr, sonst
    /// würden KSK/ESt/Snapshot/Abschluss eines Jahres ohne eigene `YearSettings` aus einem
    /// fremden Jahr gelesen bzw. „Monat abschließen" in dessen Settings geschrieben.
    private var settings: YearSettings? { jahre.first { $0.jahr == jahr } }
    /// Wiederkehrende private/betriebliche Kosten (Fixkosten + Subscriptions) des Monats –
    /// aus den **datierten Buchungen** (nicht rückwirkend, da jeder Monat eigene Zeilen hat).
    private func fixkostenPrivat(_ m: Int) -> Decimal {
        ausgaben.wiederkehrendBrutto(jahr: jahr, monat: m, betrieblich: false)
    }
    private func fixkostenBetrieblich(_ m: Int) -> Decimal {
        ausgaben.wiederkehrendBrutto(jahr: jahr, monat: m, betrieblich: true)
    }
    private var aktuellerMonatsbeginn: Date {
        appKalender.date(from: appKalender.dateComponents([.year, .month], from: Date()))!
    }
    private func istZukunft(_ m: Int) -> Bool { Periode.monat(jahr, m).von > aktuellerMonatsbeginn }
    private var istAktuell: Bool {
        jahr == appKalender.component(.year, from: Date()) && monat == appKalender.component(.month, from: Date())
    }
    private func aufHeute() {
        jahresansicht = false
        zeit.filter.jahr = appKalender.component(.year, from: Date())
        zeit.filter.monat = appKalender.component(.month, from: Date())
    }

    /// Betriebsausgaben des Monats (Einzelposten + wiederkehrend) – privat bleibt außen vor.
    private var monatsAusgaben: [ExpenseEntry] {
        let p = Periode.monat(jahr, monat)
        return ausgaben.filter { $0.betrieblich && p.enthaelt($0.datum) }.sorted { $0.datum < $1.datum }
    }
    private var monatsEinnahmen: [Income] {
        let p = Periode.monat(jahr, monat)
        return einnahmen.filter { p.enthaelt($0.rechnungsdatum) }.sorted { $0.rechnungsdatum < $1.rechnungsdatum }
    }
    private var monatsTasks: [MonthlyTask] {
        let p = Periode.monat(jahr, monat)
        return tasks.filter { p.enthaelt($0.monat) }
    }
    /// Aufgaben mit Fälligkeit im gewählten Monat – für die Abschluss-Sidebar: monatliche,
    /// einmalige **und** quartalsweise (letztere im jeweiligen Fälligkeitsmonat ihrer Instanz).
    /// Jährliche stehen im Jahresabschluss.
    private var monatsSidebarAufgaben: [MonthlyTask] {
        monatsTasks.filter { TaskVorlagen.inMonatsSidebar($0.intervall) }
            .sorted { $0.monat < $1.monat }
    }
    struct Zahlen {
        var rn, ust, vst, ustKorrektur, ksk, est, estKorrektur, betriebsausgabenNetto, umlagefaehig, privatFix, privatVariabel: Decimal
        var ustZahllast: Decimal { ust - vst + ustKorrektur }
        var betrieblicherGewinn: Decimal { rn - betriebsausgabenNetto }
        var nachSteuer: Decimal { betrieblicherGewinn - ksk - est - estKorrektur }
        var privatGesamt: Decimal { privatFix + privatVariabel }
        var frei: Decimal { nachSteuer - privatGesamt }
    }

    private func zahlenAus(_ s: MonatsSnapshot) -> Zahlen {
        Zahlen(rn: s.rn, ust: s.ust, vst: s.vst, ustKorrektur: s.ustKorrektur, ksk: s.ksk,
               est: s.est, estKorrektur: s.estKorrektur, betriebsausgabenNetto: s.betriebsausgabenNetto,
               umlagefaehig: s.umlagefaehig, privatFix: s.privatFix, privatVariabel: s.privatVariabel)
    }
    private func snapshotAus(_ z: Zahlen) -> MonatsSnapshot {
        MonatsSnapshot(rn: z.rn, ust: z.ust, vst: z.vst, ustKorrektur: z.ustKorrektur, ksk: z.ksk,
                       est: z.est, estKorrektur: z.estKorrektur, betriebsausgabenNetto: z.betriebsausgabenNetto,
                       umlagefaehig: z.umlagefaehig, privatFix: z.privatFix, privatVariabel: z.privatVariabel)
    }

    /// Posten-Arrays werden vom Aufrufer **einmal** gemappt übergeben (in der Jahresansicht
    /// sonst 12× neu erzeugt). Abgeschlossene Monate liefern ihren eingefrorenen Snapshot,
    /// sonst rechnet die Engine live (KSK aus dem Monatswert der Einstellungen).
    private func zahlen(_ m: Int, einP: [EinnahmePosten], ausP: [AusgabePosten]) -> Zahlen {
        if let snap = settings?.snapshot(monat: m) { return zahlenAus(snap) }
        let p = Periode.monat(jahr, m)
        let a = Steuer.monatsauswertung(
            monat: m, jahr: jahr,
            einnahmen: einP, ausgaben: ausP,
            kskMonat: settings?.ksk(monat: m) ?? 0, fixkostenPrivat: fixkostenPrivat(m),
            pauschalSatz: { jahre.estSatz(jahr: $0, monat: $1) })
        let baNetto = ausgaben.filter { $0.betrieblich && p.enthaelt($0.datum) }.reduce(Decimal(0)) { $0 + $1.netto }
        let umlage = ausgaben.filter { $0.betrieblich && $0.umlagefaehig && p.enthaelt($0.datum) }.reduce(Decimal(0)) { $0 + $1.netto }
        let lm = lebensmittel.filter { p.enthaelt($0.datum) }.reduce(Decimal(0)) { $0 + $1.betrag }
        let an = anschaffungen.filter { p.enthaelt($0.datum) }.reduce(Decimal(0)) { $0 + $1.preis }
        return Zahlen(rn: a.rn, ust: a.ust, vst: a.vst, ustKorrektur: a.ustKorrektur, ksk: a.ksk,
                      est: a.est, estKorrektur: a.estKorrektur,
                      betriebsausgabenNetto: baNetto, umlagefaehig: umlage,
                      privatFix: fixkostenPrivat(m), privatVariabel: lm + an)
    }

    var body: some View {
        VStack(spacing: 0) {
            kopf
            Divider()
            if jahresansicht { jahresAnsicht } else { monatsAnsicht }
        }
        .navigationTitle("Monatsabschluss")
        .toolbar {
            ToolbarItem {
                Button { zeigeAufgaben.toggle() } label: { Label("Seitenleiste", systemImage: "sidebar.trailing") }
                    .help("Werte & Aufgaben ein-/ausblenden")
            }
        }
        .inspector(isPresented: $zeigeAufgaben) {
            VStack(alignment: .leading, spacing: 0) {
                Picker("Seitenleiste", selection: $sidebarModus) {
                    ForEach(SidebarModus.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
                Divider()
                if sidebarModus == .werte {
                    if let s = settings {
                        MonatsWerteEditor(settings: s, monat: monat)
                    } else {
                        ContentUnavailableView("Kein Jahr angelegt", systemImage: "calendar.badge.exclamationmark",
                            description: Text("Lege in den Einstellungen ein Jahr an, um Werte zu pflegen."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Aufgaben · \(monatsName(monat))")
                            .font(.headline).padding(.horizontal, 14).padding(.top, 14)
                        AufgabenInspektorListe(aufgaben: monatsSidebarAufgaben,
                            leererHinweis: "Keine Aufgaben für \(monatsName(monat)). Im Modul „Aufgaben“ anlegen.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
    }

    // MARK: Kopfzeile

    private var kopf: some View {
        @Bindable var zeit = zeit
        return HStack(spacing: 12) {
            Picker("Ansicht", selection: $jahresansicht) {
                Text("Monat").tag(false)
                Text("Jahr").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 160)

            if jahresansicht {
                JahrWaehler(jahr: $zeit.filter.jahr)
            } else {
                MonatJahrWaehler(jahr: $zeit.filter.jahr, monat: $zeit.filter.monat)
            }
            HeuteButton(deaktiviert: !jahresansicht && istAktuell) { aufHeute() }
            Spacer()
            if !jahresansicht {
                if abgeschlossen {
                    Button(role: .destructive) { abschlussAufheben() } label: {
                        Label("Abschluss aufheben", systemImage: "lock.open")
                    }
                    .help("Hebt die Abschluss-Markierung dieses Monats wieder auf.")
                } else {
                    Button { monatAbschliessen() } label: { Label("Monat abschließen", systemImage: "checkmark.seal") }
                        .help("Friert den aktuellen Stand ein und markiert den Monat als erledigt.")
                }
            }
        }
        .padding()
    }

    // MARK: Monatsansicht

    private var monatsAnsicht: some View {
        let einP = einnahmen.flatMap(\.postenListe), ausP = ausgaben.map(\.posten)
        let z = zahlen(monat, einP: einP, ausP: ausP)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if abgeschlossen { abschlussBanner }
                if istZukunft(monat) { zukunftshinweis }
                heroCard(z)

                HStack(alignment: .top, spacing: 14) {
                    gewinnKarte(z)
                    VStack(spacing: 14) {
                        ruecklageKarte(z)
                        fixkostenKarte(z)
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: 14) {
                    kskKarte(z)
                    estKarte(z)
                }

                HStack(alignment: .top, spacing: 12) {
                    // „Betriebsausgaben" zeigt alle betrieblichen Buchungen des Monats
                    // (jede Art) → Ausgaben-View auf Sparte=betrieblich + Monat vorfiltern.
                    listenKarte("Betriebsausgaben", anzahl: monatsAusgaben.count,
                                oeffnen: { nav.zeigeAusgaben(jahr: jahr, monat: monat, betrieblich: true, zeit: zeit) }) {
                        ForEach(monatsAusgaben) { e in
                            postenZeile(e.bezeichnung, e.brutto, akzent: nil)
                        }
                    } fuss: {
                        Divider().padding(.top, 4)
                        postenSummenzeile("Summe", monatsAusgaben.reduce(Decimal(0)) { $0 + $1.brutto }, fett: true)
                        postenSummenzeile("davon umlagefähig", z.umlagefaehig)
                    }
                    listenKarte("Einnahmen", anzahl: monatsEinnahmen.count,
                                oeffnen: { nav.zeigeEinnahmen(jahr: jahr, monat: monat, zeit: zeit) }) {
                        ForEach(monatsEinnahmen) { e in
                            postenZeile(e.kunde, e.rnNetto, akzent: e.status == .offen ? .orange : nil)
                        }
                    }
                }
            }
            .padding()
        }
    }

    /// Gewinn-Rechnung: Umsatz/USt-Kontext, dann Waterfall Umsatz − BA = Gewinn → Frei. Zeilen kopierbar.
    private func gewinnKarte(_ z: Zahlen) -> some View {
        Panel(titel: "Gewinn-Rechnung") {
            VStack(spacing: 2) {
                Kartenzeile(label: "RN brutto", wert: z.rn + z.ust, icon: "tray.and.arrow.down")
                Kartenzeile(label: "USt", wert: z.ust, icon: "building.columns")
                Kartenzeile(label: "Umsatz (RN netto)", wert: z.rn, icon: "eurosign.circle")
                Kartenzeile(label: "Vorsteuer", wert: z.vst, icon: "arrow.down.left.circle")
                Divider().padding(.vertical, 4)
                Kartenzeile(label: "Betriebsausgaben", wert: z.betriebsausgabenNetto, icon: "creditcard", minus: true)
                Summenzeile(label: "Betrieblicher Gewinn", wert: z.betrieblicherGewinn, farbe: Stil.gewinn)
                Kartenzeile(label: "KSK-Beitrag", wert: z.ksk, icon: "cross.case", minus: true)
                Kartenzeile(label: "ESt-Rücklage", wert: z.est + z.estKorrektur, icon: "percent", minus: true)
                Kartenzeile(label: "Private Fixkosten", wert: z.privatFix, icon: "house", minus: true)
                Kartenzeile(label: "Private Ausgaben", wert: z.privatVariabel, icon: "cart", minus: true)
                Summenzeile(label: "Frei verfügbar", wert: z.frei, farbe: z.frei < 0 ? .red : Stil.gewinn)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Was diesen Monat aufs Rücklagenkonto gehört: (USt-Zahllast + ESt) + KSK + private Fixkosten.
    private func ruecklageKarte(_ z: Zahlen) -> some View {
        let summe = z.ustZahllast + z.est + z.estKorrektur + z.ksk + z.privatFix
        return Panel(titel: "Auf Rücklagenkonto") {
            VStack(spacing: 2) {
                Kartenzeile(label: "USt-Zahllast", wert: z.ust - z.vst, icon: "building.columns")
                if z.ustKorrektur != 0 { Kartenzeile(label: "§17-Korrektur (Ausfall)", wert: z.ustKorrektur, icon: "exclamationmark.triangle") }
                Kartenzeile(label: "ESt-Rücklage", wert: z.est, icon: "percent")
                if z.estKorrektur != 0 { Kartenzeile(label: "ESt-Auflösung (Ausfall)", wert: z.estKorrektur, icon: "exclamationmark.triangle") }
                Kartenzeile(label: "KSK-Beitrag", wert: z.ksk, icon: "cross.case")
                Kartenzeile(label: "Fixkosten (privat)", wert: z.privatFix, icon: "house")
                Summenzeile(label: "Summe Rücklage", wert: summe, farbe: Stil.steuer)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Wiederkehrende Monatskosten: Fixkosten (betrieblich/privat) + Subscriptions.
    private func fixkostenKarte(_ z: Zahlen) -> some View {
        Panel(titel: "Fixkosten & Subscriptions") {
            VStack(spacing: 2) {
                Kartenzeile(label: "Privat (Liquidität)", wert: z.privatFix, icon: "house")
                Kartenzeile(label: "Betrieblich (EÜR)", wert: fixkostenBetrieblich(monat), icon: "briefcase")
                Summenzeile(label: "Summe / Monat", wert: z.privatFix + fixkostenBetrieblich(monat), farbe: Stil.umlage)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var estEigenerSatz: Bool { settings?.hatEigenenSatz(monat: monat) ?? false }
    private var kskEigenerWert: Bool { settings?.hatEigenenKSK(monat: monat) ?? false }

    /// KSK-Beitrag des Monats (Betrag wird in der Sidebar „Werte" gepflegt).
    private func kskKarte(_ z: Zahlen) -> some View {
        Panel(titel: "KSK-Beitrag") {
            VStack(alignment: .leading, spacing: 8) {
                Text(z.ksk.euro).font(.system(size: 26, weight: .bold)).monospacedDigit()
                Text(z.ksk == 0 ? "Noch kein Beitrag – in der Sidebar unter „Werte“ eintragen"
                                : (kskEigenerWert ? "Wert für \(monatsName(monat))" : "übernommen aus dem Vormonat"))
                    .font(.caption).foregroundStyle(z.ksk == 0 ? Color.orange : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    /// ESt-Rücklage des Monats (Satz wird in der Sidebar „Werte" gepflegt).
    private func estKarte(_ z: Zahlen) -> some View {
        Panel(titel: "ESt-Rücklage") {
            VStack(alignment: .leading, spacing: 8) {
                Text(z.est.euro).font(.system(size: 26, weight: .bold)).monospacedDigit()
                if let s = settings {
                    Text("Satz \(s.estSatz(monat: monat).formatted(.percent))"
                         + (estEigenerSatz ? " (für \(monatsName(monat)))" : " (übernommen)"))
                        .font(.caption).foregroundStyle(estEigenerSatz ? Stil.steuer : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func heroCard(_ z: Zahlen) -> some View {
        AbschlussHero(
            verlauf: Stil.markenVerlauf,
            links: .init(titel: "Betrieblicher Gewinn", wert: z.betrieblicherGewinn),
            rechts: .init(titel: "Frei verfügbar", wert: z.frei,
                          farbe: z.frei < 0 ? Stil.heroNegativ : .white))
    }

    /// Dezenter Hinweis, dass der Monat noch in der Zukunft liegt – die Zahlen sind dann
    /// eine Vorschau (nur was schon erfasst/vererbt ist), nicht endgültig.
    private var zukunftshinweis: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary)
            Text("\(monatsName(monat)) \(String(jahr)) liegt in der Zukunft – Zahlen sind eine Vorschau.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var abschlussBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("Monat abgeschlossen – alles erledigt").font(.headline).foregroundStyle(.white)
                if let d = settings?.abschlussDatum(monat: monat) {
                    Text("Abgeschlossen am \(d.formatted(.dateTime.day().month().year()))")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Stil.gewinn.gradient, in: RoundedRectangle(cornerRadius: 14))
    }

    private func listenKarte<Inhalt: View, Fuss: View>(_ titel: String, anzahl: Int, oeffnen: @escaping () -> Void,
        @ViewBuilder rows: () -> Inhalt, @ViewBuilder fuss: () -> Fuss = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(titel) (\(anzahl))").font(.headline)
                Spacer()
                Button("öffnen", action: oeffnen).buttonStyle(.link)
            }
            Divider()
            if anzahl == 0 {
                Text("Keine Einträge.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) { rows() }
            }
            fuss()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .karte()
    }

    private func postenZeile(_ titel: String, _ wert: Decimal, akzent: Color?) -> some View {
        HStack {
            if let akzent { Circle().fill(akzent).frame(width: 6, height: 6) }
            Text(titel.isEmpty ? "—" : titel).lineLimit(1)
            Spacer()
            Text(wert.euro).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }

    // MARK: Jahresansicht

    private struct MonatsZeile: Identifiable { let id: Int; let name: String; let z: Zahlen; let zukunft: Bool }

    private var jahresAnsicht: some View {
        let einP = einnahmen.flatMap(\.postenListe), ausP = ausgaben.map(\.posten)
        let zeilen = (1...12).map { MonatsZeile(id: $0, name: monatsName($0),
            z: zahlen($0, einP: einP, ausP: ausP), zukunft: istZukunft($0)) }
        let aktiv = zeilen.filter { !$0.zukunft }
        return Table(zeilen) {
            TableColumn("Monat") { z in
                HStack(spacing: 5) {
                    if settings?.istAbgeschlossen(monat: z.id) == true {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Stil.gewinn).font(.caption)
                    }
                    Text(z.name).lineLimit(1)
                }
            }
            .width(min: 96, ideal: 124)
            TableColumn("RN") { Text($0.z.rn.euro).monospacedDigit().lineLimit(1) }
                .width(min: 84, ideal: 94)
            TableColumn("USt") { Text($0.z.ust.euro).monospacedDigit().lineLimit(1) }
                .width(min: 80, ideal: 90)
            TableColumn("VSt") { Text($0.z.vst.euro).monospacedDigit().lineLimit(1) }
                .width(min: 76, ideal: 86)
            TableColumn("KSK") { Text($0.z.ksk.euro).monospacedDigit().lineLimit(1) }
                .width(min: 80, ideal: 90)
            TableColumn("ESt") { Text($0.z.est.euro).monospacedDigit().lineLimit(1) }
                .width(min: 80, ideal: 90)
            TableColumn("Gewinn") { z in zellWert(z.zukunft ? nil : z.z.betrieblicherGewinn) }
                .width(min: 88, ideal: 98)
            TableColumn("Frei") { z in zellWert(z.zukunft ? nil : z.z.frei, farbe: (z.z.frei < 0 && !z.zukunft) ? .red : nil) }
                .width(min: 84, ideal: 94)
        }
        .environment(\.defaultMinListRowHeight, 30)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Text("Summe \(String(jahr)) (ohne Zukunftsmonate) – Klick kopiert").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    summe("RN", zeilen.reduce(Decimal(0)) { $0 + $1.z.rn })
                    summe("USt", zeilen.reduce(Decimal(0)) { $0 + $1.z.ust })
                    summe("VSt", zeilen.reduce(Decimal(0)) { $0 + $1.z.vst })
                    summe("KSK", aktiv.reduce(Decimal(0)) { $0 + $1.z.ksk })
                    summe("ESt", aktiv.reduce(Decimal(0)) { $0 + $1.z.est })
                    summe("Gewinn", aktiv.reduce(Decimal(0)) { $0 + $1.z.betrieblicherGewinn })
                    summe("Frei", aktiv.reduce(Decimal(0)) { $0 + $1.z.frei })
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func zellWert(_ wert: Decimal?, farbe: Color? = nil) -> some View {
        Group {
            if let wert { Text(wert.euro).monospacedDigit().foregroundStyle(farbe ?? .primary).lineLimit(1) }
            else { Text("—").foregroundStyle(.tertiary).lineLimit(1) }
        }
    }

    private func summe(_ titel: String, _ wert: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titel).font(.caption2).foregroundStyle(.secondary)
            Text(wert.euro).font(.callout).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { kopiere(wert) }
        .help("Klicken, um den Wert zu kopieren")
    }

    // MARK: Bausteine

    /// Schlichte Summen-/Hinweiszeile unter einer Liste (Betriebsausgaben-Fuß). Klick kopiert.
    private func postenSummenzeile(_ label: String, _ wert: Decimal, fett: Bool = false) -> some View {
        HStack {
            Text(label).fontWeight(fett ? .semibold : .regular)
            Spacer()
            Text(wert.euro).monospacedDigit().fontWeight(fett ? .semibold : .regular)
        }
        .foregroundStyle(fett ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { kopiereInZwischenablage(wert) }
        .help("Klicken, um den Wert zu kopieren")
        .contextMenu { Button("Wert kopieren") { kopiereInZwischenablage(wert) } }
    }

    private func kopiere(_ wert: Decimal) {
        let text = wert.formatted(.number.grouping(.never).precision(.fractionLength(2))
            .locale(Locale(identifier: "de_DE")))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Aktionen

    private var abgeschlossen: Bool { settings?.istAbgeschlossen(monat: monat) ?? false }
    private func monatAbschliessen() {
        // Aktuellen Stand live berechnen und einfrieren, bevor der Monat als „zu" markiert wird.
        let einP = einnahmen.flatMap(\.postenListe), ausP = ausgaben.map(\.posten)
        settings?.setzeSnapshot(monat: monat, snapshotAus(zahlen(monat, einP: einP, ausP: ausP)))
        settings?.abschlussProMonat[String(monat)] = Date()
    }
    private func abschlussAufheben() {
        settings?.abschlussProMonat[String(monat)] = nil
        settings?.loescheSnapshot(monat: monat)   // wieder live rechnen & editierbar
    }
}

/// Sidebar-Tab „Werte": KSK (JAE als Info + drei Beträge RV/KV/PV, Summe automatisch) und
/// ESt-Satz des Monats. **Eigene View mit stabiler Identität** – sonst verlieren die Eingabe-
/// felder beim Tippen den Fokus, weil die Eltern-View häufig neu rendert.
private struct MonatsWerteEditor: View {
    @Bindable var settings: YearSettings
    let monat: Int

    private var monatName: String { monatsName(monat) }
    private var abgeschlossen: Bool { settings.istAbgeschlossen(monat: monat) }
    private var kskEigen: Bool { settings.hatEigenenKSK(monat: monat) }
    private var estEigen: Bool { settings.hatEigenenSatz(monat: monat) }

    /// Liest den effektiven (ggf. geerbten) Zweig-Betrag, schreibt beim Commit nur diesen Zweig.
    private func kskBinding(_ zweig: KSKZweig) -> Binding<Decimal> {
        Binding {
            let t = settings.kskTeile(monat: monat)
            switch zweig { case .rv: return t.rv; case .kv: return t.kv; case .pv: return t.pv }
        } set: { settings.setzeKSKBetrag(monat: monat, zweig, $0) }
    }
    private var jaeBinding: Binding<Decimal> {
        Binding { settings.jae(monat: monat) } set: { settings.setzeJAE(monat: monat, $0) }
    }
    private var estSatzBinding: Binding<Decimal> {
        Binding { settings.estSatz(monat: monat) } set: { settings.estSatzProMonat[String(monat)] = $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Monatswerte · \(monatName)").font(.headline)

                if abgeschlossen {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        Text("Monat abgeschlossen – Werte sind eingefroren.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("entsperren") {
                            settings.abschlussProMonat[String(monat)] = nil
                            settings.loescheSnapshot(monat: monat)
                        }
                        .buttonStyle(.link).font(.caption)
                    }
                    .padding(8).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                Group {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("KSK-Beitrag").font(.subheadline.weight(.semibold))
                        euroFeld("JAE", jaeBinding)
                        Text("JAE nur zur Orientierung – keine Berechnungsgrundlage.")
                            .font(.caption2).foregroundStyle(.tertiary)
                        euroFeld("RV", kskBinding(.rv))
                        euroFeld("KV", kskBinding(.kv))
                        euroFeld("PV", kskBinding(.pv))
                        HStack {
                            Text("Monatsbeitrag").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text(settings.ksk(monat: monat).euro).font(.caption.weight(.semibold)).monospacedDigit()
                        }
                        HStack {
                            Text(kskEigen ? "eigene Angaben für \(monatName)" : "übernommen aus dem Vormonat")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if kskEigen {
                                Button("erben") { settings.loescheKSK(monat: monat) }.buttonStyle(.link).font(.caption)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("ESt-Satz (pauschal)").font(.subheadline.weight(.semibold))
                        TextField("Satz", value: estSatzBinding, format: .percent)
                            .multilineTextAlignment(.trailing).monospacedDigit()
                        HStack {
                            Text(estEigen ? "eigener Satz für \(monatName)" : "übernommen aus dem Vormonat")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if estEigen {
                                Button("erben") { settings.estSatzProMonat[String(monat)] = nil }.buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                }
                .disabled(abgeschlossen)

                Text("Werte gelten ab diesem Monat und werden in Folgemonate übernommen, bis du sie änderst.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func euroFeld(_ titel: String, _ binding: Binding<Decimal>) -> some View {
        HStack {
            Text(titel).foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
            TextField(titel, value: binding, format: .currency(code: "EUR"))
                .multilineTextAlignment(.trailing).monospacedDigit()
        }
    }
}
