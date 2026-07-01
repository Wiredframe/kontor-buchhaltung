import SwiftUI
import SwiftData
import AppKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - Batch-Beleg-Erfassung
//
// Modernes Sheet, um mehrere abgelegte PDFs/Bilder zügig durchzuarbeiten: links eine
// Dokument-Liste, in der Mitte die große Vorschau, rechts das OCR-vorbefüllte Formular.
// ⏎ übernimmt und springt zum nächsten Dokument. Erkennt mögliche Dubletten und bietet
// „zusammenführen“ statt Doppel-Anlage an. Rechen-/Matching-Logik liegt bewusst außerhalb
// der View (`BelegOCR`, `BelegDublette`).

enum BelegModus { case einnahme, ausgabe }

/// Trägt die abgelegten Dateien atomar ins Sheet (`.sheet(item:)`) – verhindert, dass die
/// Präsentation einen veralteten/leeren URL-Stand sieht (klassischer `.sheet(isPresented:)`-Bug).
struct BelegBatchAuftrag: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Filtert abgelegte URLs auf unterstützte Beleg-Dateien (PDF/Bild).
func belegDateien(_ urls: [URL]) -> [URL] {
    let erlaubt: Set<String> = ["pdf", "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp"]
    return urls.filter { erlaubt.contains($0.pathExtension.lowercased()) }
}

/// Entfernt Belegdateien, die nach dem Löschen von Einträgen niemand mehr referenziert
/// (prüft alle belegtragenden Modelle, damit ein geteilter Anhang nicht verschwindet).
/// Nach `context.delete` + `save()` aufrufen, damit die Prüfung den neuen Stand sieht.
@MainActor
func entferneVerwaisteBelege(_ pfade: [String?], _ context: ModelContext) {
    let kandidaten = Set(pfade.compactMap { $0 }.filter { !$0.isEmpty })
    guard !kandidaten.isEmpty else { return }
    var nochGenutzt = Set<String>()
    nochGenutzt.formUnion(((try? context.fetch(FetchDescriptor<ExpenseEntry>())) ?? []).compactMap(\.belegPfad))
    nochGenutzt.formUnion(((try? context.fetch(FetchDescriptor<Income>())) ?? []).compactMap(\.belegPfad))
    nochGenutzt.formUnion(((try? context.fetch(FetchDescriptor<PurchaseEntry>())) ?? []).compactMap(\.belegPfad))
    for p in kandidaten where !nochGenutzt.contains(p) { Belege.loesche(p) }
}

/// Bearbeitbarer Entwurf eines Belegs (ein Dokument). Wird per OCR vorbefüllt und vom
/// Nutzer korrigiert, bevor er als `Income`/`ExpenseEntry` übernommen wird.
@Observable
final class BelegEntwurf: Identifiable {
    enum Status { case laeuft, bereit, uebernommen, uebersprungen }

    let id = UUID()
    let url: URL
    var status: Status = .laeuft

    // gemeinsam
    var datum = Date()
    var rechnungsnummer = ""

    // Einnahme
    var kunde = ""
    var rnNetto: Decimal = 0
    var ust: Decimal = 0
    var satz: UStSatz = .satz19   // OCR erkennt den Satz nicht → Default Regelsatz, im Editor änderbar

    // Ausgabe
    var bezeichnung = ""
    var anbieter = ""
    var brutto: Decimal = 0
    var vst: Decimal = 0
    var steuerart: Steuerart = .inland19
    var art: AusgabeArt = .betriebsausgabe
    var betrieblich = true

    var dublette: PersistentIdentifier?
    var ergebnis: String?

    /// Pfad des einmal gespeicherten Belegs (Re-Submit kopiert die Datei nicht erneut).
    var belegPfad: String?
    /// Der bereits aus diesem Entwurf angelegte Eintrag – erneutes Bestätigen aktualisiert ihn,
    /// statt eine zweite Buchung zu erzeugen.
    var income: Income?
    var ausgabe: ExpenseEntry?
    /// Wurde der Entwurf schon einmal übernommen? (→ Button heißt „Aktualisieren")
    var schonAngelegt: Bool { income != nil || ausgabe != nil }

    var bruttoEinnahme: Decimal { rnNetto + ust }
    var netto: Decimal { brutto - vst }
    var dateiName: String { url.lastPathComponent }

    init(url: URL) { self.url = url }

    func fuelle(_ d: EinnahmeDaten) {
        if let x = d.datum { datum = x }
        kunde = d.kunde ?? url.deletingPathExtension().lastPathComponent
        rnNetto = d.rnNetto ?? 0
        ust = d.ust ?? 0
        rechnungsnummer = d.rechnungsnummer ?? ""
    }
    func fuelle(_ d: BelegDaten) {
        if let x = d.datum { datum = x }
        bezeichnung = d.anbieter ?? url.deletingPathExtension().lastPathComponent
        anbieter = d.anbieter ?? ""
        brutto = d.brutto ?? 0
        steuerart = d.steuerart ?? .inland19
        vst = steuerart == .reverseCharge ? 0 : (d.vst ?? 0)
        rechnungsnummer = d.rechnungsnummer ?? ""
    }

    private var rnOpt: String? { rechnungsnummer.isEmpty ? nil : rechnungsnummer }
    private var titelFallback: String { url.deletingPathExtension().lastPathComponent }

    /// Legt den Eintrag an oder aktualisiert den bereits aus diesem Entwurf erzeugten (idempotent –
    /// erneutes Bestätigen erzeugt nie eine zweite Buchung). Setzt `income`/`ausgabe`.
    @MainActor
    func anlegenOderAktualisieren(modus: BelegModus, in context: ModelContext) {
        switch modus {
        case .einnahme:
            let inc = income ?? Income(kunde: "", rnNetto: 0, ust: 0, rechnungsdatum: datum, status: .offen)
            inc.kunde = kunde.isEmpty ? titelFallback : kunde
            inc.rnNetto = rnNetto; inc.ust = ust; inc.satz = satz; inc.rechnungsdatum = datum
            inc.rechnungsnummer = rnOpt; inc.belegPfad = belegPfad
            if income == nil { context.insert(inc); income = inc }
        case .ausgabe:
            let ex = ausgabe ?? ExpenseEntry(datum: datum, bezeichnung: "", anbieter: "",
                                             brutto: 0, vst: 0, steuerart: steuerart)
            ex.datum = datum
            ex.bezeichnung = bezeichnung.isEmpty ? titelFallback : bezeichnung
            ex.anbieter = anbieter; ex.brutto = brutto
            ex.vst = steuerart == .reverseCharge ? 0 : vst; ex.steuerart = steuerart
            ex.betrieblich = betrieblich; ex.art = art
            ex.rechnungsnummer = rnOpt; ex.belegPfad = belegPfad
            if ausgabe == nil { context.insert(ex); ausgabe = ex }
        }
    }

    /// Hängt den Beleg (und ggf. die Rechnungsnummer) an die erkannte Dublette an, statt neu
    /// anzulegen. Setzt `income`/`ausgabe` bewusst NICHT – „Trotzdem neu anlegen" bleibt danach möglich.
    @MainActor
    func zusammenfuehren(modus: BelegModus, in context: ModelContext) {
        guard let pid = dublette else { return }
        switch modus {
        case .einnahme:
            if let inc = context.model(for: pid) as? Income {
                if inc.belegPfad == nil { inc.belegPfad = belegPfad }
                if inc.rechnungsnummer == nil { inc.rechnungsnummer = rnOpt }
            }
        case .ausgabe:
            if let ex = context.model(for: pid) as? ExpenseEntry {
                if ex.belegPfad == nil { ex.belegPfad = belegPfad }
                if ex.rechnungsnummer == nil { ex.rechnungsnummer = rnOpt }
            }
        }
    }
}

struct BelegBatchView: View {
    let modus: BelegModus
    let urls: [URL]
    /// Stellt sicher, dass ein neu angelegter Eintrag im Tabellen-Zeitfilter sichtbar ist.
    var sichtbarMachen: (Date) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var einnahmen: [Income]
    @Query private var ausgaben: [ExpenseEntry]

    @State private var entwuerfe: [BelegEntwurf] = []
    @State private var aktiv: UUID?

    private var aktuell: BelegEntwurf? { entwuerfe.first { $0.id == aktiv } }
    private var uebernommen: Int { entwuerfe.filter { $0.status == .uebernommen }.count }
    private var offen: Int { entwuerfe.filter { $0.status == .laeuft || $0.status == .bereit }.count }

    var body: some View {
        VStack(spacing: 0) {
            kopf
            Divider()
            HStack(spacing: 0) {
                filmstrip.frame(width: 210)
                Divider()
                if let e = aktuell {
                    DokumentVorschau(url: e.url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .underPageBackgroundColor))
                    Divider()
                    BelegFormular(entwurf: e, modus: modus, dubletteText: aktuell.flatMap(dubletteText))
                        .frame(width: 350)
                        .id(e.id)
                } else {
                    ContentUnavailableView("Alle Belege bearbeitet", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
            }
            Divider()
            aktionsleiste
        }
        .frame(minWidth: 980, idealWidth: 1140, minHeight: 660, idealHeight: 760)
        .task { await ladeAlle() }
    }

    // MARK: Kopf / Leiste

    private var kopf: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(modus == .einnahme ? "Rechnungen erfassen" : "Belege erfassen").font(.headline)
                Text("\(entwuerfe.count) Dokumente · \(uebernommen) übernommen")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Fertig") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var aktionsleiste: some View {
        HStack(spacing: 12) {
            if let e = aktuell, let idx = entwuerfe.firstIndex(where: { $0.id == e.id }) {
                Text("Dokument \(idx + 1) / \(entwuerfe.count)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            if let e = aktuell, betragFehlt(e) {
                Label("Betrag fehlt", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            Spacer()
            if let e = aktuell {
                Button("Überspringen") { ueberspringen(e) }
                // Ohne Betrag wird nicht angelegt (Sperre + „Betrag fehlt"-Hinweis) – ein Betrag
                // wird erwartet. Mehrfach-Anlage ist zusätzlich durch die Idempotenz ausgeschlossen.
                if e.schonAngelegt {
                    Button("Aktualisieren") { uebernehmen(e, alsDublette: false) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(betragFehlt(e))
                } else if e.dublette != nil {
                    Button("Trotzdem neu anlegen") { uebernehmen(e, alsDublette: false) }
                        .disabled(betragFehlt(e))
                    Button("Zusammenführen") { uebernehmen(e, alsDublette: true) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Übernehmen & weiter") { uebernehmen(e, alsDublette: false) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(betragFehlt(e))
                }
            } else {
                Button("Schließen") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
    }

    private var filmstrip: some View {
        List(selection: $aktiv) {
            ForEach(entwuerfe) { e in
                BelegStripZeile(entwurf: e).tag(e.id)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: OCR laden

    @MainActor
    private func ladeAlle() async {
        guard entwuerfe.isEmpty else { return }
        entwuerfe = urls.map { BelegEntwurf(url: $0) }
        aktiv = entwuerfe.first?.id
        let modus = self.modus
        await withTaskGroup(of: (UUID, EinnahmeDaten?, BelegDaten?).self) { group in
            for e in entwuerfe {
                let id = e.id, url = e.url
                group.addTask {
                    switch modus {
                    case .einnahme: return (id, await BelegOCR.analysiereEinnahme(url), nil)
                    case .ausgabe:  return (id, nil, await BelegOCR.analysiere(url))
                    }
                }
            }
            for await (id, ein, aus) in group {
                guard let e = entwuerfe.first(where: { $0.id == id }) else { continue }
                if let ein { e.fuelle(ein) }
                if let aus { e.fuelle(aus) }
                e.dublette = findeDublette(e)
                if e.status == .laeuft { e.status = .bereit }
            }
        }
    }

    private func findeDublette(_ e: BelegEntwurf) -> PersistentIdentifier? {
        switch modus {
        case .einnahme:
            return BelegDublette.finde(rechnungsnummer: e.rechnungsnummer, brutto: e.bruttoEinnahme, datum: e.datum,
                in: einnahmen, rechnungsnummerVon: { $0.rechnungsnummer },
                bruttoVon: { $0.brutto }, datumVon: { $0.rechnungsdatum })?.persistentModelID
        case .ausgabe:
            return BelegDublette.finde(rechnungsnummer: e.rechnungsnummer, brutto: e.brutto, datum: e.datum,
                in: ausgaben, rechnungsnummerVon: { $0.rechnungsnummer },
                bruttoVon: { $0.brutto }, datumVon: { $0.datum })?.persistentModelID
        }
    }

    private func dubletteText(_ e: BelegEntwurf) -> String? {
        guard let pid = e.dublette else { return nil }
        switch modus {
        case .einnahme:
            guard let inc = context.model(for: pid) as? Income else { return "bestehender Eintrag" }
            return "\(inc.kunde) · \(inc.brutto.euro)" + (inc.belegPfad != nil ? " · hat schon Beleg" : "")
        case .ausgabe:
            guard let ex = context.model(for: pid) as? ExpenseEntry else { return "bestehender Eintrag" }
            return "\(ex.bezeichnung) · \(ex.brutto.euro)" + (ex.belegPfad != nil ? " · hat schon Beleg" : "")
        }
    }

    // MARK: Aktionen

    private func betragFehlt(_ e: BelegEntwurf) -> Bool {
        modus == .einnahme ? e.bruttoEinnahme == 0 : e.brutto == 0
    }

    private func uebernehmen(_ e: BelegEntwurf, alsDublette: Bool) {
        // Beleg nur einmal pro Entwurf in den Belege-Ordner kopieren (Re-Submit dupliziert die Datei nicht).
        if e.belegPfad == nil {
            e.belegPfad = Belege.speichere(e.url, jahr: appKalender.component(.year, from: e.datum))
        }
        if alsDublette, e.dublette != nil {
            e.zusammenfuehren(modus: modus, in: context)
            e.ergebnis = "zusammengeführt"
        } else {
            let warSchonAngelegt = e.schonAngelegt
            e.anlegenOderAktualisieren(modus: modus, in: context)
            sichtbarMachen(e.datum)
            e.ergebnis = warSchonAngelegt ? "aktualisiert" : "übernommen"
        }
        try? context.save()
        e.status = .uebernommen
        weiter(nach: e)
    }

    private func ueberspringen(_ e: BelegEntwurf) {
        e.status = .uebersprungen
        e.ergebnis = "übersprungen"
        weiter(nach: e)
    }

    private func weiter(nach e: BelegEntwurf) {
        if let idx = entwuerfe.firstIndex(where: { $0.id == e.id }),
           let next = entwuerfe[(idx + 1)...].first(where: { $0.status == .laeuft || $0.status == .bereit }) {
            aktiv = next.id; return
        }
        aktiv = entwuerfe.first { $0.status == .laeuft || $0.status == .bereit }?.id
    }
}

// MARK: - Filmstrip-Zeile

private struct BelegStripZeile: View {
    let entwurf: BelegEntwurf

    var body: some View {
        HStack(spacing: 10) {
            MiniVorschau(url: entwurf.url)
                .frame(width: 34, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
            VStack(alignment: .leading, spacing: 2) {
                Text(entwurf.dateiName).font(.callout).lineLimit(1).truncationMode(.middle)
                statusLabel
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var statusLabel: some View {
        switch entwurf.status {
        case .laeuft:
            HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("liest …") }
                .font(.caption2).foregroundStyle(.secondary)
        case .bereit:
            Text("bereit").font(.caption2).foregroundStyle(.secondary)
        case .uebernommen:
            Label(entwurf.ergebnis ?? "übernommen", systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .uebersprungen:
            Label("übersprungen", systemImage: "minus.circle").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Formular (rechte Spalte)

private struct BelegFormular: View {
    @Bindable var entwurf: BelegEntwurf
    let modus: BelegModus
    let dubletteText: String?
    @FocusState private var fokus: Bool

    private var betragFehlt: Bool {
        modus == .einnahme ? entwurf.bruttoEinnahme == 0 : entwurf.brutto == 0
    }

    var body: some View {
        Form {
            if let dubletteText {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Möglicher Doppel-Eintrag").font(.callout).bold()
                            Text(dubletteText).font(.caption).foregroundStyle(.secondary)
                            Text("„Zusammenführen“ hängt den Beleg an den bestehenden Eintrag, statt neu anzulegen.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }

            switch modus {
            case .einnahme: einnahmeFelder
            case .ausgabe:  ausgabeFelder
            }
        }
        .formStyle(.grouped)
        .onAppear { fokus = true }
    }

    @ViewBuilder private var einnahmeFelder: some View {
        Section {
            TextField("Kunde", text: $entwurf.kunde).focused($fokus)
            Picker("USt-Satz", selection: $entwurf.satz) {
                ForEach(UStSatz.allCases) { Text($0.bezeichnung).tag($0) }
            }
            TextField("RN (netto)", value: $entwurf.rnNetto, format: .currency(code: "EUR"))
            HStack {
                TextField("USt", value: $entwurf.ust, format: .currency(code: "EUR"))
                Button("aus Netto") { entwurf.ust = Steuer.ust(ausNetto: entwurf.rnNetto, satz: entwurf.satz) }
            }
            LabeledContent("Brutto", value: entwurf.bruttoEinnahme.euro)
                .foregroundStyle(betragFehlt ? .red : .primary)
            DatePicker("Rechnungsdatum", selection: $entwurf.datum, displayedComponents: .date)
            TextField("Rechnungsnummer", text: $entwurf.rechnungsnummer)
        }
        if betragFehlt { hinweisBetrag }
    }

    @ViewBuilder private var ausgabeFelder: some View {
        Section {
            TextField("Bezeichnung", text: $entwurf.bezeichnung).focused($fokus)
            TextField("Anbieter", text: $entwurf.anbieter)
            Picker("Art", selection: $entwurf.art) {
                Text("Betriebsausgabe").tag(AusgabeArt.betriebsausgabe)
                Text("Fixkosten").tag(AusgabeArt.fixkosten)
                Text("Subscription").tag(AusgabeArt.subscription)
            }
            Toggle("Betrieblich (in EÜR)", isOn: $entwurf.betrieblich)
            Picker("Steuerart", selection: $entwurf.steuerart) {
                ForEach(Steuerart.allCases) { Text($0.bezeichnung).tag($0) }
            }
            .onChange(of: entwurf.steuerart) { _, neu in if !neu.ziehtVorsteuer { entwurf.vst = 0 } }
            TextField("Brutto", value: $entwurf.brutto, format: .currency(code: "EUR"))
                .foregroundStyle(betragFehlt ? .red : .primary)
            HStack {
                TextField("Vorsteuer", value: $entwurf.vst, format: .currency(code: "EUR"))
                Button("aus Brutto") {
                    entwurf.vst = Steuer.vorsteuerVorschlag(brutto: entwurf.brutto, steuerart: entwurf.steuerart)
                }
                .disabled(!entwurf.steuerart.ziehtVorsteuer)
            }
            LabeledContent("Netto", value: entwurf.netto.euro)
            DatePicker("Datum", selection: $entwurf.datum, displayedComponents: .date)
            TextField("Rechnungsnummer", text: $entwurf.rechnungsnummer)
        }
        if betragFehlt { hinweisBetrag }
    }

    private var hinweisBetrag: some View {
        Label("Betrag konnte nicht erkannt werden – bitte prüfen.", systemImage: "exclamationmark.circle")
            .font(.caption).foregroundStyle(.red)
    }
}

// MARK: - Vorschauen

/// Große, scroll-/zoombare Vorschau des aktuellen Dokuments (PDF mehrseitig, sonst Bild).
struct DokumentVorschau: View {
    let url: URL
    var body: some View {
        if url.pathExtension.lowercased() == "pdf" {
            PDFKitVorschau(url: url)
        } else if let img = NSImage(contentsOf: url) {
            ScrollView { Image(nsImage: img).resizable().scaledToFit().padding() }
        } else {
            ContentUnavailableView("Keine Vorschau möglich", systemImage: "doc")
        }
    }
}

/// Dünner `PDFView`-Wrapper für die mehrseitige Vorschau.
struct PDFKitVorschau: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .underPageBackgroundColor
        v.document = PDFDocument(url: url)
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}

/// Kleines Thumbnail für die Dokument-Liste (erste Seite / Bild), lazy geladen.
private struct MiniVorschau: View {
    let url: URL
    @State private var bild: NSImage?

    var body: some View {
        ZStack {
            if let bild {
                Image(nsImage: bild).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color(nsColor: .windowBackgroundColor))
                    .overlay { Image(systemName: "doc").foregroundStyle(.secondary) }
            }
        }
        .task(id: url) { bild = await Self.lade(url) }
    }

    private static func lade(_ url: URL) async -> NSImage? {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url), let seite = doc.page(at: 0) else { return nil }
            return seite.thumbnail(of: CGSize(width: 120, height: 160), for: .mediaBox)
        }
        return NSImage(contentsOf: url)
    }
}
