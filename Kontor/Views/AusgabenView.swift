import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - Anzeige-Helfer auf dem Zahlungs-Modell

extension TaxPayment {
    /// Für Tabelle/Filter maßgebliches Datum: das tatsächliche Zahldatum, sonst die Fälligkeit.
    var anzeigeDatum: Date { bezahltAm ?? faellig }
    /// Negativer Betrag = Erstattung (Geld vom Finanzamt zurück bzw. Gutschrift).
    var istErstattung: Bool { betrag < 0 }
}

/// Eine Zeile im gemeinsamen Ausgaben-Ledger – entweder eine `ExpenseEntry` (Betriebsausgabe/
/// Fixkosten/Subscription) oder ein `TaxPayment` (Vorsorgeaufwand/Steuer). Reine Anzeige-Hülle.
private struct LedgerZeile: Identifiable {
    let id: PersistentIdentifier
    let datum: Date
    let bezeichnung: String
    let artLabel: String
    let sparte: String?           // nil = Steuer/Vorsorge (keine Sparte)
    let betrag: Decimal
    let vst: Decimal?             // nil = Steuer/Vorsorge
    let netto: Decimal?
    let ausgabe: ExpenseEntry?
    let zahlung: TaxPayment?

    // Sortierschlüssel für die optionalen Spalten (Optional ist nicht `Comparable`):
    /// Sparte – Steuer/Vorsorge (ohne Sparte) ans Ende.
    var sparteSort: String { sparte ?? "\u{10FFFF}" }
    /// VSt – ohne Vorsteuer (Steuer/Vorsorge) sortiert als 0.
    var vstSort: Decimal { vst ?? 0 }
    /// Netto – ohne Netto (Steuer/Vorsorge) sortiert als 0.
    var nettoSort: Decimal { netto ?? 0 }
}

/// Modul „Ausgaben": gemeinsamer Ledger aller Abflüsse – Betriebsausgaben, Fixkosten,
/// Subscriptions **und** Vorsorgeaufwendungen (KSK) / Steuern (`TaxPayment`). Filter Art · Sparte ·
/// Monat. Rechts der passende Editor oder die Vorlagen-Sidebar. Beleg-Drop mit Texterkennung.
struct AusgabenView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ExpenseEntry.datum, order: .reverse) private var alle: [ExpenseEntry]
    @Query private var zahlungen: [TaxPayment]
    @Query(sort: \Vorlage.bezeichnung) private var vorlagen: [Vorlage]

    @Environment(Zeitkontext.self) private var zeit
    @Environment(Navigation.self) private var nav
    @State private var selection = Set<PersistentIdentifier>()
    @State private var sortOrder = [KeyPathComparator(\LedgerZeile.datum, order: .reverse)]
    @State private var zeigeInspektor = true
    @State private var sidebarModus: SidebarModus = .eintrag
    /// Im Vorlagen-Tab gewählte Vorlage – steuert den Editor unten in der `VorlagenPanel`.
    /// Liegt hier (statt in der Panel), damit „Vorlage erstellen" sie gleich vorwählen kann.
    @State private var vorlagenAuswahl: Vorlage.ID?
    @State private var artFilter: ArtFilter = .alle
    @State private var sparte: SparteFilter = .alle
    @State private var suche = ""
    @State private var zielAktiv = false

    enum SidebarModus: String, CaseIterable, Identifiable {
        case eintrag = "Eintrag", vorlagen = "Vorlagen"
        var id: String { rawValue }
    }
    enum ArtFilter: String, CaseIterable, Identifiable {
        case alle = "Alle", betriebsausgabe = "Betriebsausgaben", fixkosten = "Fixkosten"
        case subscription = "Subscriptions", vorsorge = "Vorsorge", steuern = "Steuern"
        var id: String { rawValue }
        /// Mappt eine Querlink-Art (`AusgabeArt`) auf den Tabellen-Filter; `nil` → „Alle".
        init(ziel art: AusgabeArt?) {
            switch art {
            case .betriebsausgabe: self = .betriebsausgabe
            case .fixkosten:       self = .fixkosten
            case .subscription:    self = .subscription
            case nil:              self = .alle
            }
        }
        var symbol: String {
            switch self {
            case .alle:            "tray.full"
            case .betriebsausgabe: "briefcase"
            case .fixkosten:       "house"
            case .subscription:    "arrow.triangle.2.circlepath"
            case .vorsorge:        "cross.case"
            case .steuern:         "building.columns"
            }
        }
        /// Hat diese Art überhaupt eine Sparte (privat/betrieblich)? Betriebsausgaben sind
        /// per Definition betrieblich, Vorsorge/Steuern haben gar keine Sparte → Filter sinnlos.
        var hatSparte: Bool { self == .alle || self == .fixkosten || self == .subscription }
        /// VSt/Netto gibt es nur bei Ausgaben (ExpenseEntry), nicht bei Vorsorge/Steuern.
        var hatVorsteuer: Bool { self != .vorsorge && self != .steuern }
        /// Vorlagen (Sidebar) existieren nur für wiederkehrende Ausgaben (Fixkosten/Subscription).
        var hatVorlagen: Bool { self == .alle || self == .fixkosten || self == .subscription }
        /// Lässt diese Filterwahl Ausgaben (ExpenseEntry) der gegebenen Art durch?
        func passtAusgabe(_ e: ExpenseEntry) -> Bool {
            switch self {
            case .alle:            true
            case .betriebsausgabe: e.artEffektiv == .betriebsausgabe
            case .fixkosten:       e.artEffektiv == .fixkosten
            case .subscription:    e.artEffektiv == .subscription
            case .vorsorge, .steuern: false
            }
        }
        /// Lässt diese Filterwahl die Zahlung (TaxPayment) durch?
        func passtZahlung(_ t: TaxPayment) -> Bool {
            switch self {
            case .alle:     true
            case .vorsorge: t.kind == .ksk
            case .steuern:  t.kind != .ksk
            default:        false
            }
        }
    }
    enum SparteFilter: String, CaseIterable, Identifiable {
        case alle = "Alle", privat = "Privat", betrieblich = "Betrieblich"
        var id: String { rawValue }
        func passt(betrieblich: Bool) -> Bool {
            switch self { case .alle: true; case .privat: !betrieblich; case .betrieblich: betrieblich }
        }
        func passt(_ e: ExpenseEntry) -> Bool { passt(betrieblich: e.betrieblich) }
    }

    private func sucheMatch(_ felder: String...) -> Bool {
        suche.isEmpty || felder.contains { $0.localizedCaseInsensitiveContains(suche) }
    }

    private var zeilen: [LedgerZeile] {
        var rows: [LedgerZeile] = []
        for e in alle where artFilter.passtAusgabe(e) && sparte.passt(e)
            && zeit.filter.enthaelt(e.datum) && sucheMatch(e.bezeichnung, e.anbieter) {
            rows.append(LedgerZeile(id: e.id, datum: e.datum, bezeichnung: e.bezeichnung,
                artLabel: e.artEffektiv.bezeichnung, sparte: e.betrieblich ? "betrieblich" : "privat",
                betrag: e.brutto, vst: e.vst, netto: e.netto, ausgabe: e, zahlung: nil))
        }
        // Steuer/Vorsorge haben keine Sparte → nur zeigen, wenn nicht nach Sparte gefiltert wird.
        if sparte == .alle {
            for t in zahlungen where artFilter.passtZahlung(t)
                && zeit.filter.enthaelt(t.anzeigeDatum) && sucheMatch(t.kind.bezeichnung, t.bemerkung) {
                rows.append(LedgerZeile(id: t.id, datum: t.anzeigeDatum,
                    bezeichnung: t.bemerkung.isEmpty ? t.kind.bezeichnung : t.bemerkung,
                    artLabel: t.kind == .ksk ? "Vorsorgeaufwand" : "Steuer",
                    sparte: nil, betrag: t.betrag, vst: nil, netto: nil, ausgabe: nil, zahlung: t))
            }
        }
        return rows
    }
    private var ausgewaehlt: LedgerZeile? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return zeilen.first { $0.id == id }
    }

    /// Vorlagen reagieren auf die Bereichs-/Sparte-Wahl der Tabelle: bei „Fixkosten" nur
    /// Fixkosten-Vorlagen, bei „Subscriptions" nur Subscriptions, Sparte analog. So fügt man
    /// nie eine Vorlage ein, deren Buchung der aktive Filter danach gleich wieder ausblendet.
    private var sichtbareVorlagen: [Vorlage] {
        vorlagen.filter { v in
            let artOk = artFilter == .alle
                || (artFilter == .fixkosten && v.art == .fixkosten)
                || (artFilter == .subscription && v.art == .subscription)
            return artOk && sparte.passt(betrieblich: v.betrieblich)
        }
    }

    private var zielJahrMonat: (jahr: Int, monat: Int) {
        if zeit.filter.modus == .monat { return (zeit.filter.jahr, zeit.filter.monat) }
        return (appKalender.component(.year, from: Date()), appKalender.component(.month, from: Date()))
    }
    private func ersterTag(_ jahr: Int, _ monat: Int) -> Date {
        appKalender.date(from: DateComponents(year: jahr, month: monat, day: 1))!
    }

    /// Übernimmt einen Querlink-Vorfilter (Art/Sparte) aus der Navigation und setzt ihn
    /// danach zurück, damit er nur einmal wirkt. Der Zeitraum kommt über `zeit.filter`.
    private func konsumiereZiel() {
        guard let ziel = nav.ausgabenZiel else { return }
        artFilter = ArtFilter(ziel: ziel.art)
        sparte = ziel.betrieblich.map { $0 ? .betrieblich : .privat } ?? .alle
        nav.ausgabenZiel = nil
    }

    var body: some View {
        @Bindable var zeit = zeit
        let liste = zeilen.sorted(using: sortOrder)
        return VStack(spacing: 0) {
            ZeitraumLeiste(filter: $zeit.filter) {
                // Sparte-Filter rechts in der Zeitleiste – spart Breite in der Bereichszeile.
                if artFilter.hatSparte {
                    Picker("Sparte", selection: $sparte) {
                        ForEach(SparteFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).fixedSize().labelsHidden()
                }
            }
            Divider()
            HStack(spacing: 12) {
                ArtLeiste(auswahl: $artFilter)
                Spacer(minLength: 0)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .onChange(of: artFilter) { _, neu in
                if !neu.hatSparte { sparte = .alle }
                if !neu.hatVorlagen { sidebarModus = .eintrag }
            }
            Divider()
            Table(liste, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Datum", value: \.datum) { Text($0.datum, format: .dateTime.day().month().year()).lineLimit(1) }
                    .width(min: 64, ideal: 92)
                TableColumn("Bezeichnung", value: \.bezeichnung) { Text($0.bezeichnung.isEmpty ? "—" : $0.bezeichnung).lineLimit(1) }
                    .width(min: 70, ideal: 180)
                // „Art" nur in der Gesamtansicht – sonst ist sie durch die Bereichswahl ohnehin bekannt.
                if artFilter == .alle {
                    TableColumn("Art", value: \.artLabel) { Text($0.artLabel).foregroundStyle(.secondary).lineLimit(1) }
                        .width(min: 60, ideal: 116)
                }
                // „Sparte" nur, wo es privat/betrieblich überhaupt gibt.
                if artFilter.hatSparte {
                    TableColumn("Sparte", value: \.sparteSort) { Text($0.sparte ?? "—").foregroundStyle(.secondary).lineLimit(1) }
                        .width(min: 50, ideal: 92)
                }
                TableColumn("Betrag", value: \.betrag) { z in
                    Text(z.betrag.euro).monospacedDigit().foregroundStyle(z.betrag < 0 ? .red : .primary).lineLimit(1)
                }
                .width(min: 60, ideal: 88)
                // VSt/Netto nur bei Ausgaben – Vorsorge/Steuern haben keine Vorsteuer.
                if artFilter.hatVorsteuer {
                    TableColumn("VSt", value: \.vstSort) { Text($0.vst.map(\.euro) ?? "—").foregroundStyle(.secondary).monospacedDigit().lineLimit(1) }
                        .width(min: 50, ideal: 74)
                    TableColumn("Netto", value: \.nettoSort) { Text($0.netto.map(\.euro) ?? "—").foregroundStyle(.secondary).monospacedDigit().lineLimit(1) }
                        .width(min: 56, ideal: 80)
                }
            }
            .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                let ausgabenIds = ids.filter { id in alle.contains { $0.id == id } }
                Button("Duplizieren (heute)") { duplizieren(ids) }
                if !ausgabenIds.isEmpty {
                    Button("Vorlage erstellen") { vorlageErstellen(ausgabenIds) }
                }
                Button("Löschen", role: .destructive) { loesche(ids) }
            }
            .environment(\.defaultMinListRowHeight, 34)
            .onChange(of: selection) { _, neu in if neu.count == 1 { sidebarModus = .eintrag } }
            .dropDestination(for: URL.self) { urls, _ in
                for url in urls { verarbeiteBeleg(url) }
                return !urls.isEmpty
            } isTargeted: { zielAktiv = $0 }
            .overlay {
                if zielAktiv {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            Label("Beleg ablegen – Felder werden per Texterkennung vorausgefüllt",
                                  systemImage: "doc.viewfinder")
                                .font(.headline).foregroundStyle(Color.accentColor)
                        }
                        .padding(10).allowsHitTesting(false)
                }
            }
        }
        .navigationTitle("Ausgaben")
        .onAppear(perform: konsumiereZiel)
        .searchable(text: $suche, prompt: "Bezeichnung oder Anbieter suchen")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Section("Ausgabe") {
                        Button("Betriebsausgabe") { neu(.betriebsausgabe) }
                        Button("Fixkosten") { neu(.fixkosten) }
                        Button("Subscription") { neu(.subscription) }
                    }
                    Section("Zahlung") {
                        Button("Vorsorgeaufwand") { neu(.vorsorge) }
                        Button("Steuer") { neu(.steuer) }
                    }
                } label: {
                    Label("Neu", systemImage: "plus")
                }
                Button { vormonatDuplizieren() } label: { Label("Vormonat duplizieren", systemImage: "doc.on.doc") }
                    .help("Kopiert die wiederkehrenden Buchungen des Vormonats in \(monatsName(zielJahrMonat.monat)) \(String(zielJahrMonat.jahr))")
                Button { zeigeInspektor.toggle() } label: { Label("Details", systemImage: "sidebar.trailing") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 24) {
                SummenWert(titel: "Summe", wert: liste.reduce(0) { $0 + $1.betrag })
                Spacer()
                Text("\(liste.count) Einträge").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
        .inspector(isPresented: $zeigeInspektor) {
            VStack(spacing: 0) {
                // Der Vorlagen-Tab erscheint nur, wenn der gewählte Bereich Vorlagen kennt
                // (Fixkosten/Subscriptions) – bei Betriebsausgaben/Vorsorge/Steuern nur der Eintrag.
                if artFilter.hatVorlagen {
                    Picker("", selection: $sidebarModus) {
                        ForEach(SidebarModus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().padding(10)
                    Divider()
                }
                // Inhalt füllt die Resthöhe, damit der Tab-Umschalter oben bleibt
                // (sonst zentriert der VStack alles vertikal).
                Group {
                    if sidebarModus == .eintrag || !artFilter.hatVorlagen {
                        if let e = ausgewaehlt?.ausgabe {
                            AusgabeInspektor(eintrag: e)
                        } else if let t = ausgewaehlt?.zahlung {
                            ZahlungInspektor(eintrag: t)
                        } else {
                            ContentUnavailableView("Kein Eintrag gewählt", systemImage: "sidebar.right",
                                description: Text("Zeile wählen – oder Tab Vorlagen zum Einfügen."))
                        }
                    } else {
                        VorlagenPanel(vorlagen: sichtbareVorlagen, auswahl: $vorlagenAuswahl,
                                      zielText: "\(monatsName(zielJahrMonat.monat)) \(String(zielJahrMonat.jahr))",
                                      einfuegen: einfuegen, neueVorlage: neueVorlage, loescheVorlage: loescheVorlage)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .inspectorColumnWidth(min: 260, ideal: 320, max: 460)
        }
    }

    private func verarbeiteBeleg(_ url: URL) {
        Task {
            let daten = await BelegOCR.analysiere(url)
            let datum = daten.datum ?? Date()
            let pfad = Belege.speichere(url, jahr: appKalender.component(.year, from: datum))
            await MainActor.run {
                let st = daten.steuerart ?? .inland19
                let e = ExpenseEntry(
                    datum: datum,
                    bezeichnung: daten.anbieter ?? url.deletingPathExtension().lastPathComponent,
                    anbieter: daten.anbieter ?? "",
                    brutto: daten.brutto ?? 0,
                    vst: st == .reverseCharge ? 0 : (daten.vst ?? 0),
                    steuerart: st,
                    kategorie: .laufend, betrieblich: true, belegPfad: pfad,
                    art: .betriebsausgabe)
                context.insert(e); try? context.save()
                selection = [e.id]; sidebarModus = .eintrag; zeigeInspektor = true
            }
        }
    }

    // MARK: Aktionen

    enum NeuTyp { case betriebsausgabe, fixkosten, subscription, vorsorge, steuer }
    private func neu(_ typ: NeuTyp) {
        let neueID: PersistentIdentifier
        switch typ {
        case .vorsorge, .steuer:
            let jahr = appKalender.component(.year, from: Date())
            let t = TaxPayment(kind: typ == .vorsorge ? .ksk : .estVz, jahr: jahr, faellig: Date(),
                               bezahlt: true, bezahltAm: Date())
            context.insert(t); try? context.save()
            neueID = t.id
            if !zeit.filter.enthaelt(t.anzeigeDatum) { zeit.filter.modus = .alle }
        case .betriebsausgabe, .fixkosten, .subscription:
            let art: AusgabeArt = typ == .fixkosten ? .fixkosten : typ == .subscription ? .subscription : .betriebsausgabe
            let datum = zeit.filter.modus == .monat ? ersterTag(zielJahrMonat.jahr, zielJahrMonat.monat) : Date()
            let e = ExpenseEntry(datum: datum, bezeichnung: "", anbieter: "", brutto: 0, vst: 0,
                                 steuerart: .inland19, kategorie: .laufend, betrieblich: true,
                                 art: art)
            context.insert(e); try? context.save()
            neueID = e.id
            if !zeit.filter.enthaelt(e.datum) { zeit.filter.modus = .alle }
        }
        // Filter zurücksetzen, damit der neue Eintrag sicher sichtbar ist.
        artFilter = .alle; sparte = .alle; suche = ""
        selection = [neueID]; sidebarModus = .eintrag; zeigeInspektor = true
    }
    private func duplizieren(_ ids: Set<PersistentIdentifier>) {
        for e in alle where ids.contains(e.id) {
            context.insert(ExpenseEntry(datum: Date(), bezeichnung: e.bezeichnung, anbieter: e.anbieter,
                brutto: e.brutto, vst: e.vst, steuerart: e.steuerart, kategorie: e.kategorie,
                betrieblich: e.betrieblich, umlagefaehig: e.umlagefaehig, art: e.art))
        }
        for t in zahlungen where ids.contains(t.id) {
            context.insert(TaxPayment(kind: t.kind, jahr: t.jahr, faellig: Date(), betrag: t.betrag,
                                      bezahlt: true, bezahltAm: Date(), bemerkung: t.bemerkung))
        }
    }
    private func loesche(_ ids: Set<PersistentIdentifier>) {
        guard bestaetigeLoeschung(ids.count) else { return }
        selection.subtract(ids)
        for e in alle where ids.contains(e.id) { context.delete(e) }
        for t in zahlungen where ids.contains(t.id) { context.delete(t) }
    }

    /// Kopiert die wiederkehrenden Buchungen (Fixkosten/Subscriptions) des Vormonats in den Zielmonat.
    private func vormonatDuplizieren() {
        let (zJ, zM) = zielJahrMonat
        let quelle = appKalender.date(byAdding: .month, value: -1, to: ersterTag(zJ, zM))!
        let qJ = appKalender.component(.year, from: quelle), qM = appKalender.component(.month, from: quelle)
        let quellPeriode = Periode.monat(qJ, qM), zielPeriode = Periode.monat(zJ, zM)
        let zielDatum = ersterTag(zJ, zM)
        let wiederkehrend = alle.filter { $0.artEffektiv == .fixkosten || $0.artEffektiv == .subscription }
        for e in wiederkehrend where quellPeriode.enthaelt(e.datum) {
            let schonDa = wiederkehrend.contains {
                zielPeriode.enthaelt($0.datum) && $0.bezeichnung.caseInsensitiveCompare(e.bezeichnung) == .orderedSame
            }
            if schonDa { continue }
            context.insert(ExpenseEntry(datum: zielDatum, bezeichnung: e.bezeichnung, anbieter: e.anbieter,
                brutto: e.brutto, vst: e.vst, steuerart: e.steuerart, kategorie: e.kategorie,
                betrieblich: e.betrieblich, umlagefaehig: e.umlagefaehig, art: e.art))
        }
        try? context.save()
        if zeit.filter.modus != .monat { zeit.filter.modus = .monat; zeit.filter.jahr = zJ; zeit.filter.monat = zM }
    }

    private func einfuegen(_ v: Vorlage) {
        let (j, m) = zielJahrMonat
        let e = v.buchung(am: ersterTag(j, m))
        context.insert(e); try? context.save()
        if !zeit.filter.enthaelt(e.datum) { zeit.filter.modus = .alle }
        selection = [e.id]; sidebarModus = .eintrag
    }
    private func neueVorlage() -> Vorlage {
        // Neue Vorlage erbt den aktiven Filter (Art/Sparte), damit sie sofort sichtbar bleibt.
        let art: AusgabeArt = artFilter == .subscription ? .subscription : .fixkosten
        let v = Vorlage(bezeichnung: "Neue Vorlage", betragBrutto: 0,
                        betrieblich: sparte == .betrieblich, art: art)
        context.insert(v); try? context.save()
        return v
    }
    private func loescheVorlage(_ v: Vorlage) { context.delete(v) }

    /// Legt aus den gewählten Ausgaben je eine wiederkehrende `Vorlage` an (Subscription bleibt
    /// Subscription, alles andere wird Fixkosten – Vorlagen kennen nur diese beiden Arten) und
    /// öffnet die zuletzt erzeugte direkt im Vorlagen-Tab zum Bearbeiten.
    private func vorlageErstellen(_ ids: Set<PersistentIdentifier>) {
        var letzte: Vorlage?
        for e in alle where ids.contains(e.id) {
            let art: AusgabeArt = e.artEffektiv == .subscription ? .subscription : .fixkosten
            let v = Vorlage(bezeichnung: e.bezeichnung, anbieter: e.anbieter, betragBrutto: e.brutto,
                            steuerart: e.steuerart, betrieblich: e.betrieblich, art: art,
                            umlagefaehig: e.betrieblich && e.umlagefaehig)
            context.insert(v)
            letzte = v
        }
        try? context.save()
        guard let neu = letzte else { return }
        // Filter öffnen, damit der Vorlagen-Tab erreichbar und die neue Vorlage sichtbar ist.
        artFilter = .alle; sparte = .alle
        sidebarModus = .vorlagen; zeigeInspektor = true
        vorlagenAuswahl = neu.id
    }
}

// MARK: - Bereichswahl (Art) als Button-Gruppe mit Icons

/// Segmentierte Bereichswahl statt Menü-Filter: je Art ein Button mit Icon + Label.
/// Der aktive Bereich wird mit der Akzentfarbe hinterlegt. Bei schmalem Fenster fällt
/// die Leiste per `ViewThatFits` automatisch auf eine reine Icon-Variante zurück –
/// so erzwingt sie keine zu hohe Mindest-Fensterbreite.
private struct ArtLeiste: View {
    @Binding var auswahl: AusgabenView.ArtFilter

    var body: some View {
        ViewThatFits(in: .horizontal) {
            leiste(zeigeText: true)
            leiste(zeigeText: false)
        }
    }

    private func leiste(zeigeText: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(AusgabenView.ArtFilter.allCases) { art in
                let aktiv = art == auswahl
                Button {
                    auswahl = art
                } label: {
                    Group {
                        if zeigeText {
                            Label(art.rawValue, systemImage: art.symbol).labelStyle(.titleAndIcon)
                        } else {
                            Image(systemName: art.symbol)
                        }
                    }
                        .font(.callout.weight(aktiv ? .semibold : .regular))
                        .foregroundStyle(aktiv ? Color.accentColor : .secondary)
                        .padding(.horizontal, zeigeText ? 10 : 8).padding(.vertical, 5)
                        .background {
                            if aktiv {
                                RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.14))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(art.rawValue)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .quaternarySystemFill)))
        .fixedSize()
    }
}

// MARK: - Inspector: Ausgabe bearbeiten

struct AusgabeInspektor: View {
    @Bindable var eintrag: ExpenseEntry
    @FocusState private var fokus: Bool

    private var artBinding: Binding<AusgabeArt> {
        Binding { eintrag.artEffektiv } set: { eintrag.art = $0 }
    }

    var body: some View {
        Form {
            DatePicker("Datum", selection: $eintrag.datum, displayedComponents: .date)
            TextField("Bezeichnung", text: $eintrag.bezeichnung).focused($fokus)
            TextField("Anbieter", text: $eintrag.anbieter)
            Picker("Art", selection: artBinding) {
                Text("Betriebsausgabe").tag(AusgabeArt.betriebsausgabe)
                Text("Fixkosten").tag(AusgabeArt.fixkosten)
                Text("Subscription").tag(AusgabeArt.subscription)
            }
            Toggle("Betrieblich (in EÜR)", isOn: $eintrag.betrieblich)
            Picker("Steuerart", selection: $eintrag.steuerart) {
                ForEach(Steuerart.allCases) { Text($0.bezeichnung).tag($0) }
            }
            .onChange(of: eintrag.steuerart) { _, neu in if neu != .inland19 { eintrag.vst = 0 } }
            TextField("Brutto", value: $eintrag.brutto, format: .currency(code: "EUR"))
            HStack {
                TextField("Vorsteuer", value: $eintrag.vst, format: .currency(code: "EUR"))
                Button("aus Brutto") {
                    eintrag.vst = Steuer.vorsteuerVorschlag(brutto: eintrag.brutto, steuerart: eintrag.steuerart)
                }
                .disabled(eintrag.steuerart != .inland19)
            }
            LabeledContent("Netto", value: eintrag.netto.euro)
            Picker("Kategorie", selection: $eintrag.kategorie) {
                ForEach(Kategorie.allCases) { Text($0.bezeichnung).tag($0) }
            }
            Toggle("Umlagefähig", isOn: $eintrag.umlagefaehig)
            Section("Beleg") {
                if let p = eintrag.belegPfad, Belege.existiert(p) {
                    BelegVorschau(pfad: p)
                    HStack {
                        Text((p as NSString).lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button("Entfernen", role: .destructive) { eintrag.belegPfad = nil }
                    }
                } else {
                    BelegDropArea { url in
                        eintrag.belegPfad = Belege.speichere(url, jahr: appKalender.component(.year, from: eintrag.datum))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: eintrag.id, initial: true) { _, _ in fokus = eintrag.bezeichnung.isEmpty }
    }
}

// MARK: - Inspector: Zahlung (Vorsorge/Steuer) bearbeiten

struct ZahlungInspektor: View {
    @Bindable var eintrag: TaxPayment

    private var bezahltAm: Binding<Date> {
        Binding { eintrag.bezahltAm ?? Date() } set: { eintrag.bezahltAm = $0 }
    }

    var body: some View {
        Form {
            Picker("Art", selection: $eintrag.kind) {
                ForEach(SteuerKind.allCases) { Text($0.bezeichnung).tag($0) }
            }
            TextField("Betrag", value: $eintrag.betrag, format: .currency(code: "EUR"))
            Text(eintrag.istErstattung ? "Negativ = Erstattung (mindert die Steuersumme)." : "Positiv = Zahlung ans Finanzamt / an die KSK.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Jahr (Zuordnung)", value: $eintrag.jahr, format: .number.grouping(.never))
            DatePicker("Fällig", selection: $eintrag.faellig, displayedComponents: .date)
            Toggle("bezahlt", isOn: $eintrag.bezahlt)
                .onChange(of: eintrag.bezahlt) { _, neu in eintrag.bezahltAm = neu ? (eintrag.bezahltAm ?? Date()) : nil }
            if eintrag.bezahlt {
                DatePicker("Bezahlt am", selection: bezahltAm, displayedComponents: .date)
            }
            TextField("Notiz", text: $eintrag.bemerkung)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Inspector: Vorlagen (Card-Stil)

struct VorlagenPanel: View {
    let vorlagen: [Vorlage]
    @Binding var auswahl: Vorlage.ID?
    let zielText: String
    let einfuegen: (Vorlage) -> Void
    let neueVorlage: () -> Vorlage
    let loescheVorlage: (Vorlage) -> Void

    private var gewaehlt: Vorlage? { vorlagen.first { $0.id == auswahl } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Vorlagen").font(.headline)
                Spacer()
                Button { auswahl = neueVorlage().id } label: { Label("Neu", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)

            if vorlagen.isEmpty {
                ContentUnavailableView("Keine Vorlagen", systemImage: "doc.badge.plus",
                    description: Text("Oben mit Plus eine Fixkosten- oder Subscription-Vorlage anlegen."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vorlagen) { vorlageCard($0) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }
                Text("Einfügen bucht in \(zielText).").font(.caption2).foregroundStyle(.tertiary)
                    .padding(.horizontal, 14).padding(.bottom, 6)

                if let v = gewaehlt {
                    Divider()
                    VorlageEditor(vorlage: v) { loescheVorlage(v); auswahl = nil }
                        .frame(maxHeight: 340)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func vorlageCard(_ v: Vorlage) -> some View {
        let gewaehlt = v.id == auswahl
        return HStack(spacing: 10) {
            Image(systemName: v.art == .subscription ? "arrow.triangle.2.circlepath" : "house")
                .foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.bezeichnung.isEmpty ? "—" : v.bezeichnung).fontWeight(.medium).lineLimit(1)
                Text("\(v.betragBrutto.euro) · \(v.betrieblich ? "betrieblich" : "privat")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button("einfügen") { einfuegen(v) }.buttonStyle(.borderless).font(.caption)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .karte(12)
        .overlay {
            if gewaehlt { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2) }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { auswahl = (auswahl == v.id) ? nil : v.id }
    }
}

struct VorlageEditor: View {
    @Bindable var vorlage: Vorlage
    var loeschen: () -> Void
    @FocusState private var fokus: Bool

    var body: some View {
        Form {
            Section("Vorlage bearbeiten") {
                TextField("Bezeichnung", text: $vorlage.bezeichnung).focused($fokus)
                TextField("Anbieter", text: $vorlage.anbieter)
                Picker("Art", selection: $vorlage.art) {
                    Text("Fixkosten").tag(AusgabeArt.fixkosten)
                    Text("Subscription").tag(AusgabeArt.subscription)
                }
                Toggle("Betrieblich (in EÜR)", isOn: $vorlage.betrieblich)
                    .onChange(of: vorlage.betrieblich) { _, neu in if !neu { vorlage.umlagefaehig = false } }
                // Umlagefähig nur bei betrieblichen Vorlagen sinnvoll (Weiterberechnung an Kunden).
                if vorlage.betrieblich {
                    Toggle("Umlagefähig", isOn: $vorlage.umlagefaehig)
                }
                Picker("Steuerart", selection: $vorlage.steuerart) {
                    ForEach(Steuerart.allCases) { Text($0.bezeichnung).tag($0) }
                }
                TextField("Betrag (brutto)", value: $vorlage.betragBrutto, format: .currency(code: "EUR"))
                Button("Vorlage löschen", role: .destructive) { loeschen() }
            }
        }
        .formStyle(.grouped)
        .onChange(of: vorlage.id, initial: true) { _, _ in fokus = vorlage.bezeichnung == "Neue Vorlage" || vorlage.bezeichnung.isEmpty }
    }
}
