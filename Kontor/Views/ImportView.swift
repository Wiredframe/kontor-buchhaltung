import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Eine Bankzeile im Import-Triage-Zustand (Vorschlag + gewählte Zuordnung + Status).
@Observable
final class ImportZeile: Identifiable {
    let id = UUID()
    let buchung: Bankbuchung
    var zuordnung: Zuordnung
    var zielId: PersistentIdentifier?      // vorhandener Datensatz (Match/Dublette) – nil = neu
    var bereitsImportiert: Bool
    var erledigt: Bool
    var ergebnis: String?                  // Ergebnis-/Skip-Text nach dem Buchen

    init(_ b: Bankbuchung, zuordnung: Zuordnung, bereitsImportiert: Bool) {
        self.buchung = b
        self.zuordnung = zuordnung
        self.bereitsImportiert = bereitsImportiert
        self.erledigt = bereitsImportiert
        self.ergebnis = bereitsImportiert ? "schon importiert" : nil
    }

    /// Wird diese Zeile als betriebliche Ausgabe gebucht (→ Steuerart relevant)?
    var buchtBetrieb: Bool {
        switch zuordnung.kategorie {
        case .betriebsausgabe:          true
        case .fixkosten, .subscription: zuordnung.betrieblich
        default:                        false
        }
    }
}

/// Kontoauszug-Import: CSV wählen → jede Bankbewegung selbst zuordnen (mit lernenden
/// Vorschlägen) → buchen / überschreiben / überspringen.
struct ImportView: View {
    @Environment(\.modelContext) private var context
    @State private var zeilen: [ImportZeile] = []
    @State private var dateiName: String?
    @State private var status: String?
    @State private var zeigeErledigte = false

    private var sichtbar: [ImportZeile] { zeilen.filter { zeigeErledigte || !$0.erledigt } }
    private var offeneAnzahl: Int { zeilen.filter { !$0.erledigt }.count }
    private var erledigteAnzahl: Int { zeilen.filter { $0.erledigt }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                kopf
                ForEach(sichtbar) { zeile in
                    ImportZeileRow(zeile: zeile,
                                   buchen: { anwenden(zeile, $0) },
                                   zielNeuBerechnen: { zeile.zielId = ImportAnwendung.ziel(zeile.buchung, zeile.zuordnung, context) })
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Kontoauszug")
    }

    private var kopf: some View {
        Panel(titel: "Sparkasse-Kontoauszug (CSV-CAMT V8)") {
            HStack(spacing: 12) {
                Button { waehleCSV() } label: { Label("CSV wählen …", systemImage: "doc.badge.plus") }
                if let dateiName { Text(dateiName).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                if !zeilen.isEmpty {
                    Text("\(offeneAnzahl) offen · \(zeilen.count) gesamt").font(.callout).foregroundStyle(.secondary)
                }
            }
            if !zeilen.isEmpty {
                HStack(spacing: 12) {
                    if offeneAnzahl > 0 {
                        Button { bucheAlleOhneTreffer() } label: { Label("Alle ohne Treffer buchen", systemImage: "checklist.checked") }
                    }
                    Toggle("Erledigte zeigen", isOn: $zeigeErledigte).toggleStyle(.switch).controlSize(.small)
                    if zeigeErledigte && erledigteAnzahl > 0 {
                        Button { alleErneutZuordnen() } label: { Label("Alle erneut zuordnen", systemImage: "arrow.uturn.backward") }
                            .controlSize(.small)
                            .help("Alle erledigten/„schon importierten“ Buchungen wieder zur Zuordnung öffnen – z. B. um einen bereits importierten Auszug erneut durchzugehen. Erneutes Buchen überschreibt den bestehenden Eintrag (keine Dubletten).")
                    }
                    Spacer()
                }
            }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            else if zeilen.isEmpty {
                Text("Export in der Sparkasse: Exportieren → Excel (CSV-CAMT V8). Jede Bewegung wird hier einzeln zugeordnet; Zuordnungen werden gelernt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Aktionen

    private func waehleCSV() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .text]
        panel.message = "Sparkasse-Export im Format CSV-CAMT V8 wählen"
        panel.prompt = "Importieren"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { status = "Datei nicht lesbar."; NSSound.beep(); return }
        let ergebnis = Bankimport.lies(data)
        // Ein nicht verstandener Kopf sah bisher aus wie „keine Buchungen drin" – der Nutzer
        // konnte die falsche Datei nicht von einem leeren Auszug unterscheiden.
        guard ergebnis.kopfErkannt else {
            status = "Diese Datei sieht nicht nach einem Sparkasse-Export im Format CSV-CAMT V8 aus – "
                + "die Spalten „Betrag“ und „Buchungstag“ fehlen. Es wurde nichts geladen."
            NSSound.beep(); return
        }
        lade(ergebnis, name: url.lastPathComponent)
    }

    private func lade(_ ergebnis: Bankimport.Ergebnis, name: String) {
        lade(ergebnis.buchungen, name: name, verworfen: ergebnis.verworfen)
    }

    private func lade(_ buchungen: [Bankbuchung], name: String, verworfen: Int = 0) {
        let regeln = (try? context.fetch(FetchDescriptor<ZuordnungsRegel>())) ?? []
        zeilen = buchungen
            .sorted { $0.buchungstag > $1.buchungstag }
            .map { b in
                let z = ImportVorschlag.fuer(b, regeln: regeln)
                let zeile = ImportZeile(b, zuordnung: z, bereitsImportiert: ImportAnwendung.schonVerarbeitet(b, context))
                zeile.zielId = ImportAnwendung.ziel(b, z, context)
                return zeile
            }
        dateiName = name
        let neu = zeilen.filter { !$0.bereitsImportiert }.count
        // Verworfene Zeilen (unlesbarer Betrag/Datum) gehören sichtbar gemacht: stillschweigend
        // übersprungen sähe eine teilkorrupte CSV aus wie eine vollständig importierte.
        let hinweis = verworfen > 0
            ? " · \(verworfen) Zeile\(verworfen == 1 ? "" : "n") übersprungen (Betrag/Datum unlesbar)"
            : ""
        if neu == 0 && !zeilen.isEmpty {
            zeigeErledigte = true   // komplett importierter Auszug → Zeilen direkt sichtbar machen
            status = "\(buchungen.count) Buchungen – alle schon importiert.\(hinweis) „Alle erneut zuordnen“ (oder „Neu zuordnen“ je Zeile), um sie noch einmal durchzugehen."
        } else {
            zeigeErledigte = false
            status = "\(buchungen.count) Buchungen geladen · \(neu) neu · \(buchungen.count - neu) schon importiert\(hinweis)."
        }
        if verworfen > 0 { NSSound.beep() }
    }

    /// Öffnet alle erledigten/„schon importierten“ Buchungen wieder zur Zuordnung, um einen
    /// bereits importierten Auszug erneut durchzugehen (Re-Import). Erneutes Buchen trifft über
    /// `ImportAnwendung.ziel` den bestehenden Datensatz (Überschreiben) → keine Dubletten.
    private func alleErneutZuordnen() {
        for zeile in zeilen where zeile.erledigt { zeile.erledigt = false; zeile.ergebnis = nil }
        status = "\(zeilen.count) Buchungen zur erneuten Zuordnung geöffnet."
    }

    private func anwenden(_ zeile: ImportZeile, _ aktion: ImportAnwendung.Aktion) {
        do {
            zeile.ergebnis = try ImportAnwendung.anwenden(zeile.buchung, zeile.zuordnung, aktion: aktion, context)
            zeile.erledigt = true
        } catch {
            status = "Fehler: \(error.localizedDescription)"; NSSound.beep()
        }
    }

    /// Bulk: alle offenen Zeilen ohne vorhandenen Treffer anlegen/abhaken
    /// (Einnahmen ohne Rechnungs-Match bleiben für die manuelle Prüfung offen).
    private func bucheAlleOhneTreffer() {
        let ziel = zeilen.filter { !$0.erledigt && $0.zielId == nil && $0.zuordnung.kategorie != .einnahme }
        for zeile in ziel { anwenden(zeile, .neu) }
        status = "\(ziel.count) Buchungen ohne Treffer verarbeitet."
    }
}

// MARK: - Zeile

private struct ImportZeileRow: View {
    @Bindable var zeile: ImportZeile
    let buchen: (ImportAnwendung.Aktion) -> Void
    let zielNeuBerechnen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(zeile.buchung.anzeigename).font(.callout).fontWeight(.medium).lineLimit(1)
                Text("\(zeile.buchung.buchungstag.formatted(date: .numeric, time: .omitted)) · \(zeile.buchung.buchungstext)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(zeile.buchung.betrag.euro)
                .font(.callout).monospacedDigit()
                .foregroundStyle(zeile.buchung.istEingang ? Stil.gewinn : .primary)
                .frame(width: 95, alignment: .trailing)

            if zeile.erledigt {
                HStack(spacing: 8) {
                    Label(zeile.ergebnis ?? "erledigt", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Neu zuordnen") { zeile.erledigt = false; zeile.ergebnis = nil }
                        .controlSize(.small)
                        .help("Diese Buchung erneut zuordnen (z. B. zuvor ignoriert)")
                }
                .frame(width: 360, alignment: .leading)
            } else {
                steuerung
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .karte(10)
        .opacity(zeile.erledigt ? 0.5 : 1)
    }

    @ViewBuilder private var steuerung: some View {
        Picker("", selection: $zeile.zuordnung.kategorie) {
            ForEach(ImportKategorie.allCases) { Text($0.bezeichnung).tag($0) }
        }
        .labelsHidden().frame(width: 150)
        .onChange(of: zeile.zuordnung.kategorie) { _, _ in
            zeile.zuordnung = zeile.zuordnung.normalisiert   // z. B. Wechsel auf Betriebsausgabe → betrieblich
            zielNeuBerechnen()
        }

        if zeile.zuordnung.kategorie == .fixkosten || zeile.zuordnung.kategorie == .subscription {
            Picker("", selection: $zeile.zuordnung.betrieblich) {
                Text("privat").tag(false); Text("betr.").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 104)
        }

        if zeile.zuordnung.kategorie == .steuer || zeile.zuordnung.kategorie == .steuererstattung {
            Picker("", selection: $zeile.zuordnung.steuerKind) {
                ForEach(SteuerKind.allCases.filter { $0 != .ksk }) { Text($0.bezeichnung).tag($0) }
            }
            .labelsHidden().frame(width: 170)
            .onChange(of: zeile.zuordnung.steuerKind) { _, _ in zielNeuBerechnen() }
        }

        if zeile.buchtBetrieb {
            Picker("", selection: $zeile.zuordnung.steuerart) {
                ForEach(Steuerart.allCases) { Text($0.bezeichnung).tag($0) }
            }
            .labelsHidden().frame(width: 132)
        }

        Button(zeile.zielId == nil ? "Buchen" : "Überschreiben") {
            buchen(zeile.zielId.map { .ueberschreiben($0) } ?? .neu)
        }
        .buttonStyle(.borderedProminent).controlSize(.small)
        .help(zeile.zielId == nil ? "Neu anlegen / abhaken" : "Vorhandenen Eintrag aktualisieren")

        Button("Überspringen") { buchen(.ueberspringen) }
            .controlSize(.small)
    }
}
