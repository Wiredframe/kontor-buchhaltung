import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct AnschaffungenView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PurchaseEntry.datum, order: .reverse) private var alle: [PurchaseEntry]

    @Environment(Zeitkontext.self) private var zeit
    @State private var selection = Set<PurchaseEntry.ID>()
    @State private var sortOrder = [KeyPathComparator(\PurchaseEntry.datum, order: .reverse)]
    @State private var zeigeInspektor = true
    @State private var suche = ""
    @State private var zielAktiv = false
    @AppStorage("budgetAnschaffungenMonat") private var budgetMonat = 80.0

    private var gefiltert: [PurchaseEntry] {
        alle.filter { zeit.filter.enthaelt($0.datum) && (suche.isEmpty || $0.bezeichnung.localizedCaseInsensitiveContains(suche)) }
    }
    private var anzeige: [PurchaseEntry] { gefiltert.sorted(using: sortOrder) }
    private var ausgewaehlt: PurchaseEntry? { selection.count == 1 ? alle.first { $0.id == selection.first } : nil }
    /// Aktueller Monat – Grundlage des Budget-Hinweises (Budget ist ein Monatswert).
    private var monatsSumme: Decimal {
        let p = Periode.monat(appKalender.component(.year, from: Date()), appKalender.component(.month, from: Date()))
        return alle.filter { p.enthaelt($0.datum) }.reduce(0) { $0 + $1.preis }
    }
    /// Summe der aktuell gefilterten Einträge (folgt Alle/Jahr/Monat).
    private var summe: Decimal { gefiltert.reduce(0) { $0 + $1.preis } }

    var body: some View {
        @Bindable var zeit = zeit
        return VStack(spacing: 0) {
            ZeitraumLeiste(filter: $zeit.filter)
            Divider()

            Table(anzeige, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Datum", value: \.datum) { Text($0.datum, format: .dateTime.day().month().year()).lineLimit(1) }
                    .width(min: 96, ideal: 110)
                TableColumn("Bezeichnung", value: \.bezeichnung) { Text($0.bezeichnung.isEmpty ? "—" : $0.bezeichnung).lineLimit(1) }
                    .width(min: 180, ideal: 280)
                TableColumn("Preis", value: \.preis) { Text($0.preis.euro).monospacedDigit().lineLimit(1) }
                    .width(min: 90, ideal: 100)
            }
            .environment(\.defaultMinListRowHeight, 34)
            .contextMenu(forSelectionType: PurchaseEntry.ID.self) { ids in
                Button("Duplizieren") { duplizieren(ids) }
                Button("In Ausgaben verschieben") { nachAusgaben(ids) }
                Button("Löschen", role: .destructive) { loesche(ids) }
            }
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
                            Label("Beleg ablegen – Bezeichnung, Preis und Datum werden per Texterkennung vorausgefüllt",
                                  systemImage: "doc.viewfinder")
                                .font(.headline).foregroundStyle(Color.accentColor)
                        }
                        .padding(10).allowsHitTesting(false)
                }
            }
        }
        .navigationTitle("Einkäufe")
        .searchable(text: $suche, prompt: "Bezeichnung suchen")
        .toolbar {
            ToolbarItemGroup {
                Button { neu() } label: { Label("Neu", systemImage: "plus") }
                Button { zeigeInspektor.toggle() } label: { Label("Details", systemImage: "sidebar.trailing") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 24) {
                SummenWert(titel: "Summe", wert: summe)
                if budgetMonat > 0 {
                    BudgetWert(titel: "Dieser Monat", ist: monatsSumme, budget: Decimal(budgetMonat))
                }
                Spacer()
                Text("\(gefiltert.count) Einträge").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
        .inspector(isPresented: $zeigeInspektor) {
            Group {
                if let e = ausgewaehlt { AnschaffungInspektor(eintrag: e) }
                else { ContentUnavailableView("Kein Eintrag gewählt", systemImage: "sidebar.right",
                        description: Text("Zeile wählen – oder „+“ für einen neuen Eintrag.")) }
            }
            .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
    }

    private func neu() {
        let e = PurchaseEntry(datum: Date(), bezeichnung: "", preis: 0)
        context.insert(e); try? context.save()
        suche = ""; if !zeit.filter.enthaelt(e.datum) { zeit.filter.modus = .alle }
        selection = [e.id]; zeigeInspektor = true
    }
    private func duplizieren(_ ids: Set<PurchaseEntry.ID>) {
        for e in alle where ids.contains(e.id) {
            context.insert(PurchaseEntry(datum: e.datum, bezeichnung: e.bezeichnung, preis: e.preis))
        }
    }
    private func loesche(_ ids: Set<PurchaseEntry.ID>) {
        guard bestaetigeLoeschung(ids.count) else { return }
        selection.subtract(ids)
        let pfade = alle.filter { ids.contains($0.id) }.map(\.belegPfad)
        for e in alle where ids.contains(e.id) { context.delete(e) }
        try? context.save()
        entferneVerwaisteBelege(pfade, context)
    }

    /// Verschiebt die gewählten Einkäufe ins Ausgaben-Ledger: je Einkauf eine **private**
    /// `ExpenseEntry` (steuerfrei, VSt 0, nicht in der EÜR – nur Liquidität), Beleg bleibt
    /// verknüpft; die Bestellung wird danach gelöscht (echtes Verschieben).
    private func nachAusgaben(_ ids: Set<PurchaseEntry.ID>) {
        selection.subtract(ids)
        for e in alle where ids.contains(e.id) {
            context.insert(ExpenseEntry(
                datum: e.datum, bezeichnung: e.bezeichnung, anbieter: "",
                brutto: e.preis, vst: 0, steuerart: .steuerfrei,
                kategorie: .anschaffung, betrieblich: false,
                belegPfad: e.belegPfad, art: .betriebsausgabe))
            context.delete(e)
        }
        try? context.save()
    }

    private func verarbeiteBeleg(_ url: URL) {
        Task {
            let daten = await BelegOCR.analysiere(url)
            let datum = daten.datum ?? Date()
            let pfad = Belege.speichere(url, jahr: appKalender.component(.year, from: datum))
            await MainActor.run {
                let e = PurchaseEntry(
                    datum: datum,
                    bezeichnung: daten.anbieter ?? url.deletingPathExtension().lastPathComponent,
                    preis: daten.brutto ?? 0,
                    belegPfad: pfad)
                context.insert(e)
                try? context.save()        // ID permanent → Auswahl bleibt gültig
                selection = [e.id]
                zeigeInspektor = true
            }
        }
    }
}

struct AnschaffungInspektor: View {
    @Environment(\.modelContext) private var context
    @Bindable var eintrag: PurchaseEntry
    @FocusState private var fokus: Bool
    var body: some View {
        Form {
            DatePicker("Datum", selection: $eintrag.datum, displayedComponents: .date)
            TextField("Bezeichnung", text: $eintrag.bezeichnung).focused($fokus)
            TextField("Preis", value: $eintrag.preis, format: .currency(code: "EUR"))
            Section("Beleg") {
                if let p = eintrag.belegPfad, Belege.existiert(p) {
                    BelegVorschau(pfad: p)
                    HStack {
                        Text((p as NSString).lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button("Entfernen", role: .destructive) {
                            let alt = eintrag.belegPfad
                            eintrag.belegPfad = nil
                            try? context.save()
                            entferneVerwaisteBelege([alt], context)
                        }
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
