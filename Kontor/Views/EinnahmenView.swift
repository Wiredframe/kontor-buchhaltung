import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct EinnahmenView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Income.rechnungsdatum, order: .reverse) private var alle: [Income]

    @Environment(Zeitkontext.self) private var zeit
    @State private var selection = Set<Income.ID>()
    @State private var sortOrder = [KeyPathComparator(\Income.rechnungsdatum, order: .reverse)]
    @State private var zeigeInspektor = true
    @State private var suche = ""
    @State private var zielAktiv = false

    private var gefiltert: [Income] {
        alle.filter { e in
            zeit.filter.enthaelt(e.rechnungsdatum)
                && (suche.isEmpty
                    || e.kunde.localizedCaseInsensitiveContains(suche)
                    || (e.rechnungsnummer?.localizedCaseInsensitiveContains(suche) ?? false))
        }
    }
    private var anzeige: [Income] { gefiltert.sorted(using: sortOrder) }
    private var ausgewaehlt: Income? { selection.count == 1 ? alle.first { $0.id == selection.first } : nil }

    private var summeRN: Decimal { gefiltert.reduce(0) { $0 + $1.rnNetto } }
    private var summeUSt: Decimal { gefiltert.reduce(0) { $0 + $1.ust } }
    private var summeOffen: Decimal { gefiltert.filter { $0.status == .offen }.reduce(0) { $0 + $1.brutto } }

    var body: some View {
        @Bindable var zeit = zeit
        return VStack(spacing: 0) {
            ZeitraumLeiste(filter: $zeit.filter)
            Divider()
            Table(anzeige, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Rechnungsnr.", value: \.rechnungsnummerSort) { e in
                    Text(e.rechnungsnummer ?? "—")
                        .foregroundStyle(e.rechnungsnummer == nil ? .secondary : .primary)
                        .lineLimit(1)
                }
                .width(min: 110, ideal: 150)
                TableColumn("Kunde", value: \.kunde) { Text($0.kunde).lineLimit(1) }
                    .width(min: 140, ideal: 200)
                TableColumn("RN (netto)", value: \.rnNetto) { Text($0.rnNetto.euro).monospacedDigit().lineLimit(1) }
                    .width(min: 90, ideal: 100)
                TableColumn("USt", value: \.ust) { Text($0.ust.euro).monospacedDigit().lineLimit(1) }
                    .width(min: 80, ideal: 90)
                TableColumn("Brutto") { Text($0.brutto.euro).monospacedDigit().lineLimit(1) }
                    .width(min: 80, ideal: 90)
                TableColumn("Rechnung", value: \.rechnungsdatum) { Text($0.rechnungsdatum, format: .dateTime.day().month().year()).lineLimit(1) }
                    .width(min: 96, ideal: 106)
                TableColumn("Zahlung") { e in
                    if let z = e.zahlungsdatum { Text(z, format: .dateTime.day().month().year()).lineLimit(1) }
                    else { Text("—").foregroundStyle(.secondary) }
                }
                .width(min: 96, ideal: 106)
                TableColumn("Status") { e in
                    Menu(e.status.bezeichnung) {
                        ForEach(InvoiceStatus.allCases) { s in
                            Button(s.bezeichnung) { setzeStatus(e, s) }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .foregroundStyle(farbe(e.status))
                }
                .width(min: 96, ideal: 110)
            }
            .contextMenu(forSelectionType: Income.ID.self) { ids in
                Button("Als bezahlt markieren (heute)") { bezahltHeute(ids) }
                Button("Duplizieren (heute)") { duplizieren(ids) }
                Button("Löschen", role: .destructive) { loesche(ids) }
            }
            .environment(\.defaultMinListRowHeight, 34)
            .dropDestination(for: URL.self) { urls, _ in
                for url in urls { verarbeiteRechnung(url) }
                return !urls.isEmpty
            } isTargeted: { zielAktiv = $0 }
            .overlay {
                if zielAktiv {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            Label("Ausgangsrechnung ablegen – Kunde, Beträge und Datum werden per Texterkennung vorausgefüllt",
                                  systemImage: "doc.viewfinder")
                                .font(.headline).foregroundStyle(Color.accentColor)
                        }
                        .padding(10).allowsHitTesting(false)
                }
            }
        }
        .navigationTitle("Einnahmen")
        .searchable(text: $suche, prompt: "Kunde oder Rechnungsnummer suchen")
        .toolbar {
            ToolbarItemGroup {
                Button { neu() } label: { Label("Neu", systemImage: "plus") }
                Button { zeigeInspektor.toggle() } label: { Label("Details", systemImage: "sidebar.trailing") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 24) {
                SummenWert(titel: "RN (netto)", wert: summeRN)
                SummenWert(titel: "USt", wert: summeUSt)
                SummenWert(titel: "offen (brutto)", wert: summeOffen)
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
        .inspector(isPresented: $zeigeInspektor) {
            Group {
                if let e = ausgewaehlt {
                    EinnahmeInspektor(eintrag: e)
                } else {
                    ContentUnavailableView("Kein Eintrag gewählt", systemImage: "sidebar.right",
                        description: Text("Zeile wählen – oder „+“ für eine neue Rechnung."))
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 330, max: 440)
        }
    }

    private func farbe(_ s: InvoiceStatus) -> Color {
        switch s { case .offen: .orange; case .bezahlt: .secondary; case .ausgefallen: .red }
    }
    private func setzeStatus(_ e: Income, _ s: InvoiceStatus) { e.setze(status: s) }
    private func bezahltHeute(_ ids: Set<Income.ID>) {
        for e in alle where ids.contains(e.id) { setzeStatus(e, .bezahlt) }
    }
    private func neu() {
        let e = Income(kunde: "", rnNetto: 0, ust: 0, rechnungsdatum: Date(), status: .offen)
        context.insert(e); try? context.save()
        suche = ""; if !zeit.filter.enthaelt(e.rechnungsdatum) { zeit.filter.modus = .alle }
        selection = [e.id]; zeigeInspektor = true
    }

    private func verarbeiteRechnung(_ url: URL) {
        Task {
            let d = await BelegOCR.analysiereEinnahme(url)
            let datum = d.datum ?? Date()
            await MainActor.run {
                if let nr = d.rechnungsnummer, let vorhanden = alle.first(where: { $0.rechnungsnummer == nr }) {
                    if vorhanden.belegPfad == nil {        // PDF an vorhandenen Eintrag nachtragen
                        vorhanden.belegPfad = Belege.speichere(url, jahr: appKalender.component(.year, from: datum))
                    }
                    selection = [vorhanden.id]; zeigeInspektor = true; return   // Duplikat vermeiden
                }
                let pfad = Belege.speichere(url, jahr: appKalender.component(.year, from: datum))
                let e = Income(
                    kunde: d.kunde ?? url.deletingPathExtension().lastPathComponent,
                    rnNetto: d.rnNetto ?? 0,
                    ust: d.ust ?? 0,
                    rechnungsdatum: datum,
                    status: .offen,
                    rechnungsnummer: d.rechnungsnummer,
                    belegPfad: pfad)
                context.insert(e)
                try? context.save()        // ID permanent → Auswahl bleibt gültig
                selection = [e.id]
                zeigeInspektor = true
            }
        }
    }
    private func duplizieren(_ ids: Set<Income.ID>) {
        for e in alle where ids.contains(e.id) {
            context.insert(Income(kunde: e.kunde, rnNetto: e.rnNetto, ust: e.ust,
                rechnungsdatum: Date(), status: .offen))
        }
    }
    private func loesche(_ ids: Set<Income.ID>) {
        guard bestaetigeLoeschung(ids.count) else { return }
        selection.subtract(ids)
        for e in alle where ids.contains(e.id) { context.delete(e) }
    }
}

// MARK: - Inspector (Live-Bearbeitung)

struct EinnahmeInspektor: View {
    @Bindable var eintrag: Income
    @FocusState private var fokus: Bool

    private var zahlung: Binding<Date> {
        Binding { eintrag.zahlungsdatum ?? Date() } set: { eintrag.zahlungsdatum = $0 }
    }
    private var ausfall: Binding<Date> {
        Binding { eintrag.ausfalldatum ?? Date() } set: { eintrag.ausfalldatum = $0 }
    }
    private var rechnungsnummer: Binding<String> {
        Binding { eintrag.rechnungsnummer ?? "" } set: { eintrag.rechnungsnummer = $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        Form {
            TextField("Kunde", text: $eintrag.kunde).focused($fokus)
            TextField("RN (netto)", value: $eintrag.rnNetto, format: .currency(code: "EUR"))
            HStack {
                TextField("USt", value: $eintrag.ust, format: .currency(code: "EUR"))
                Button("aus Netto") { eintrag.ust = Steuer.ust(ausNetto: eintrag.rnNetto) }
            }
            LabeledContent("Brutto", value: eintrag.brutto.euro)
            DatePicker("Rechnungsdatum", selection: $eintrag.rechnungsdatum, displayedComponents: .date)
            Picker("Status", selection: $eintrag.status) {
                ForEach(InvoiceStatus.allCases) { Text($0.bezeichnung).tag($0) }
            }
            .onChange(of: eintrag.status) { _, neu in eintrag.setze(status: neu) }
            if eintrag.zahlungsdatum != nil {
                DatePicker("Zahlungsdatum", selection: zahlung, displayedComponents: .date)
            }
            if eintrag.status == .ausgefallen {
                DatePicker("Ausfalldatum (§17)", selection: ausfall, displayedComponents: .date)
            }
            TextField("Rechnungsnummer", text: rechnungsnummer)
            Section("Beleg") {
                if let p = eintrag.belegPfad, Belege.existiert(p) {
                    BelegVorschau(pfad: p)
                    HStack {
                        Text((p as NSString).lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button("Entfernen", role: .destructive) { eintrag.belegPfad = nil }
                    }
                } else {
                    BelegDropArea(hinweis: "Rechnung hierher ziehen oder klicken") { url in
                        eintrag.belegPfad = Belege.speichere(url, jahr: appKalender.component(.year, from: eintrag.rechnungsdatum))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: eintrag.id, initial: true) { _, _ in fokus = eintrag.kunde.isEmpty }
    }
}
