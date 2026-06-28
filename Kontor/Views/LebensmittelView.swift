import SwiftUI
import SwiftData

struct LebensmittelView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \GroceryEntry.datum, order: .reverse) private var alle: [GroceryEntry]

    @Environment(Zeitkontext.self) private var zeit
    @State private var selection = Set<GroceryEntry.ID>()
    @State private var sortOrder = [KeyPathComparator(\GroceryEntry.datum, order: .reverse)]
    @State private var zeigeInspektor = true
    @State private var suche = ""

    @AppStorage("budgetLebensmittelWoche") private var budgetWoche = 50.0
    private var budget: Decimal { Decimal(budgetWoche) }
    private let iso = Calendar(identifier: .iso8601)

    private var gefiltert: [GroceryEntry] {
        alle.filter { zeit.filter.enthaelt($0.datum) && (suche.isEmpty || $0.ort.localizedCaseInsensitiveContains(suche)) }
    }
    private var anzeige: [GroceryEntry] { gefiltert.sorted(using: sortOrder) }
    private var ausgewaehlt: GroceryEntry? { selection.count == 1 ? alle.first { $0.id == selection.first } : nil }
    private func kw(_ d: Date) -> Int { iso.component(.weekOfYear, from: d) }
    private var recentOrte: [String] {
        // alle ist nach Datum absteigend → eindeutige Orte in „zuletzt genutzt"-Reihenfolge.
        var gesehen = Set<String>(); var ergebnis: [String] = []
        for o in alle.map(\.ort) where !o.isEmpty && gesehen.insert(o).inserted {
            ergebnis.append(o)
            if ergebnis.count == 10 { break }
        }
        return ergebnis
    }
    /// Aktuelle ISO-Woche – Grundlage des Budget-Hinweises (Budget ist ein Wochenwert).
    private var dieseWoche: Decimal {
        let w = kw(Date()), j = iso.component(.yearForWeekOfYear, from: Date())
        return alle.filter { kw($0.datum) == w && iso.component(.yearForWeekOfYear, from: $0.datum) == j }
            .reduce(0) { $0 + $1.betrag }
    }
    /// Summe der aktuell gefilterten Einträge (folgt Alle/Jahr/Monat).
    private var summe: Decimal { gefiltert.reduce(0) { $0 + $1.betrag } }

    var body: some View {
        @Bindable var zeit = zeit
        return VStack(spacing: 0) {
            ZeitraumLeiste(filter: $zeit.filter)
            Divider()

            Table(anzeige, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Datum", value: \.datum) { Text($0.datum, format: .dateTime.day().month().year()).lineLimit(1) }
                    .width(min: 96, ideal: 110)
                TableColumn("KW") { Text("KW \(kw($0.datum))").foregroundStyle(.secondary).lineLimit(1) }
                    .width(min: 56, ideal: 70)
                TableColumn("Ort", value: \.ort) { Text($0.ort.isEmpty ? "—" : $0.ort).lineLimit(1) }
                    .width(min: 140, ideal: 220)
                TableColumn("Betrag", value: \.betrag) { Text($0.betrag.euro).monospacedDigit().lineLimit(1) }
                    .width(min: 90, ideal: 100)
            }
            .environment(\.defaultMinListRowHeight, 34)
            .contextMenu(forSelectionType: GroceryEntry.ID.self) { ids in
                Button("Duplizieren") { duplizieren(ids) }
                Button("Löschen", role: .destructive) { loesche(ids) }
            }
        }
        .navigationTitle("Lebensmittel")
        .searchable(text: $suche, prompt: "Ort suchen")
        .toolbar {
            ToolbarItemGroup {
                Button { neu() } label: { Label("Neu", systemImage: "plus") }
                Button { zeigeInspektor.toggle() } label: { Label("Details", systemImage: "sidebar.trailing") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 24) {
                SummenWert(titel: "Summe", wert: summe)
                if budgetWoche > 0 {
                    BudgetWert(titel: "Diese Woche", ist: dieseWoche, budget: budget)
                }
                Spacer()
                Text("\(gefiltert.count) Einträge").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
        .inspector(isPresented: $zeigeInspektor) {
            Group {
                if let e = ausgewaehlt { LebensmittelInspektor(eintrag: e, orte: recentOrte) }
                else { ContentUnavailableView("Kein Eintrag gewählt", systemImage: "sidebar.right",
                        description: Text("Zeile wählen – oder „+“ für einen neuen Eintrag.")) }
            }
            .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
    }

    private func neu() {
        let e = GroceryEntry(datum: Date(), betrag: 0, ort: "")
        context.insert(e); try? context.save()
        suche = ""; if !zeit.filter.enthaelt(e.datum) { zeit.filter.modus = .alle }
        selection = [e.id]; zeigeInspektor = true
    }
    private func duplizieren(_ ids: Set<GroceryEntry.ID>) {
        for e in alle where ids.contains(e.id) {
            context.insert(GroceryEntry(datum: e.datum, betrag: e.betrag, ort: e.ort))
        }
    }
    private func loesche(_ ids: Set<GroceryEntry.ID>) {
        guard bestaetigeLoeschung(ids.count) else { return }
        selection.subtract(ids)
        for e in alle where ids.contains(e.id) { context.delete(e) }
    }
}

struct LebensmittelInspektor: View {
    @Bindable var eintrag: GroceryEntry
    var orte: [String] = []
    @FocusState private var fokus: Bool

    var body: some View {
        Form {
            DatePicker("Datum", selection: $eintrag.datum, displayedComponents: .date)
            TextField("Ort", text: $eintrag.ort).focused($fokus)
            if !orte.isEmpty {
                Menu("Zuletzt genutzter Ort …") {
                    ForEach(orte, id: \.self) { o in Button(o) { eintrag.ort = o } }
                }
                .font(.caption)
            }
            TextField("Betrag", value: $eintrag.betrag, format: .currency(code: "EUR"))
        }
        .formStyle(.grouped)
        .onChange(of: eintrag.id, initial: true) { _, _ in fokus = eintrag.ort.isEmpty }
    }
}
