import SwiftUI
import SwiftData
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Beschrifteter Zahlenwert als elevierte Karte mit optionalem Akzent-Icon.
/// Klick kopiert den Wert (deutsches Zahlformat, ohne Tausenderpunkt) in die Zwischenablage.
struct Kennzahl: View {
    let titel: String
    let wert: Decimal
    var symbol: String? = nil
    var akzent: Color = .accentColor
    var betont = false
    var farbe: Color? = nil
    @State private var kopiert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                }
                Text(titel).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                KopierHaken(sichtbar: kopiert)
            }
            Text(wert.euro)
                .font(betont ? .system(size: 30, weight: .bold) : .system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(farbe ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .karte()
        .contentShape(Rectangle())
        .onTapGesture(perform: kopiere)
        .help("Klicken, um den Wert zu kopieren")
        .contextMenu { Button("Wert kopieren", action: kopiere) }
    }

    private func kopiere() { kopiereMitHaken(wert, $kopiert) }
}

/// Wählbarer Jahresbereich aus den vorhandenen Daten: frühestes erfasstes Jahr bis
/// aktuelles Jahr + 1 (Puffer fürs Vorausplanen). Ohne Daten nur aktuelles Jahr (+1).
/// Nutzt günstige limit-1-Fetches (frühester/spätester Eintrag je Bewegungstyp).
func verfuegbareJahre(_ ctx: ModelContext) -> ClosedRange<Int> {
    let heute = appKalender.component(.year, from: Date())
    var jahre: Set<Int> = [heute, heute + 1]
    func rand<T: PersistentModel>(_ make: (SortOrder) -> FetchDescriptor<T>, _ datum: (T) -> Date) {
        for order: SortOrder in [.forward, .reverse] {
            var d = make(order); d.fetchLimit = 1
            if let e = try? ctx.fetch(d).first { jahre.insert(appKalender.component(.year, from: datum(e))) }
        }
    }
    rand({ FetchDescriptor<Income>(sortBy: [SortDescriptor(\.rechnungsdatum, order: $0)]) }, { $0.rechnungsdatum })
    rand({ FetchDescriptor<ExpenseEntry>(sortBy: [SortDescriptor(\.datum, order: $0)]) }, { $0.datum })
    rand({ FetchDescriptor<GroceryEntry>(sortBy: [SortDescriptor(\.datum, order: $0)]) }, { $0.datum })
    rand({ FetchDescriptor<PurchaseEntry>(sortBy: [SortDescriptor(\.datum, order: $0)]) }, { $0.datum })
    return (jahre.min() ?? heute)...(jahre.max() ?? heute)
}

/// Rechnet den wählbaren Jahresbereich aus den Daten neu und hält die aktuelle Filter-Auswahl
/// gültig (klemmt sie in den Bereich, falls das gewählte Jahr keine Daten mehr hat). Wird
/// reaktiv bei Datenänderungen aufgerufen, damit neue/entfernte Jahre sofort greifen.
@MainActor func aktualisiereJahre(_ zeit: Zeitkontext, _ context: ModelContext) {
    zeit.jahre = verfuegbareJahre(context)
    if !zeit.jahre.contains(zeit.filter.jahr) {
        zeit.filter.jahr = min(max(zeit.filter.jahr, zeit.jahre.lowerBound), zeit.jahre.upperBound)
    }
}

/// Jahres-Auswahl als Dropdown. Ohne expliziten `bereich` kommen die Jahre aus dem
/// Zeitkontext (aus den Daten abgeleitet) – keine fest verdrahteten Jahreszahlen.
struct JahrWaehler: View {
    @Binding var jahr: Int
    var bereich: ClosedRange<Int>? = nil
    @Environment(Zeitkontext.self) private var zeit

    var body: some View {
        Picker("Jahr", selection: $jahr) {
            ForEach(bereich ?? zeit.jahre, id: \.self) { Text(verbatim: String($0)).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// Monat-/Jahr-Auswahl für die Auswertungs-Screens.
struct MonatJahrWaehler: View {
    @Binding var jahr: Int
    @Binding var monat: Int

    var body: some View {
        HStack(spacing: 12) {
            Picker("Monat", selection: $monat) {
                ForEach(1...12, id: \.self) { Text(monatsName($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 140)
            JahrWaehler(jahr: $jahr)
        }
    }
}

private let _deMonthSymbols: [String] = {
    let df = DateFormatter(); df.locale = Locale(identifier: "de_DE")
    return df.monthSymbols ?? []
}()

private let _deShortMonthSymbols: [String] = {
    let df = DateFormatter(); df.locale = Locale(identifier: "de_DE")
    return df.shortMonthSymbols ?? []
}()

func monatsName(_ monat: Int) -> String {
    guard monat >= 1, monat <= _deMonthSymbols.count else { return "\(monat)" }
    return _deMonthSymbols[monat - 1]
}

/// Kurzer Monatsname (z. B. „Jan"), de_DE – für Chart-Achsen und kompakte Tabellen.
func kurzMonat(_ monat: Int) -> String {
    guard monat >= 1, monat <= _deShortMonthSymbols.count else { return "\(monat)" }
    return _deShortMonthSymbols[monat - 1]
}

// MARK: - Zeitraum-Filter (Tabellen)

/// Zeitraum-Filter für Tabellen-Views: Alle / Jahr / Monat. Kapselt die Filterlogik,
/// damit alle Views denselben Zustand und dieselbe Semantik nutzen.
struct Zeitfilter {
    enum Modus: Hashable { case alle, jahr, monat }
    var modus: Modus = .alle
    var jahr = appKalender.component(.year, from: Date())
    var monat = appKalender.component(.month, from: Date())

    /// Trifft `datum` auf den eingestellten Zeitraum zu?
    func enthaelt(_ datum: Date) -> Bool {
        let c = appKalender.dateComponents([.year, .month], from: datum)
        switch modus {
        case .alle:  return true
        case .jahr:  return c.year == jahr
        case .monat: return c.year == jahr && c.month == monat
        }
    }

    var istAktuellerMonat: Bool {
        modus == .monat
            && jahr == appKalender.component(.year, from: Date())
            && monat == appKalender.component(.month, from: Date())
    }

    mutating func aufAktuellenMonat() {
        modus = .monat
        jahr = appKalender.component(.year, from: Date())
        monat = appKalender.component(.month, from: Date())
    }
}

/// Einheitliche Zeitraum-Kopfzeile (Alle/Jahr/Monat) mit Schnellzugriff
/// „Aktueller Monat" – im Stil des Monatsabschlusses. Optionaler Inhalt rechts.
struct ZeitraumLeiste<Trailing: View>: View {
    @Binding var filter: Zeitfilter
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        // Eine Zeile, solange sie passt; sonst bricht das Trailing (z. B. ein
        // zusätzlicher Filter) in eine zweite Zeile um – senkt die Mindest-Fensterbreite.
        ViewThatFits(in: .horizontal) {
            zeile(umgebrochen: false)
            zeile(umgebrochen: true)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    @ViewBuilder
    private var zeitControls: some View {
        Picker("Zeitraum", selection: $filter.modus) {
            Text("Alle").tag(Zeitfilter.Modus.alle)
            Text("Jahr").tag(Zeitfilter.Modus.jahr)
            Text("Monat").tag(Zeitfilter.Modus.monat)
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()

        if filter.modus != .alle {
            JahrWaehler(jahr: $filter.jahr)
        }
        if filter.modus == .monat {
            Picker("Monat", selection: $filter.monat) {
                ForEach(1...12, id: \.self) { Text(monatsName($0)).tag($0) }
            }
            .labelsHidden().frame(width: 130)
        }

        HeuteButton(deaktiviert: filter.istAktuellerMonat) { filter.aufAktuellenMonat() }
    }

    @ViewBuilder
    private func zeile(umgebrochen: Bool) -> some View {
        if umgebrochen {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) { zeitControls; Spacer(minLength: 0) }
                HStack(spacing: 12) { trailing(); Spacer(minLength: 0) }
            }
        } else {
            HStack(spacing: 12) {
                zeitControls
                Spacer(minLength: 8)
                trailing()
            }
        }
    }
}

extension ZeitraumLeiste where Trailing == EmptyView {
    init(filter: Binding<Zeitfilter>) { self.init(filter: filter) { EmptyView() } }
}

// MARK: - Beleg-Vorschau

/// Großflächige Inline-Vorschau eines Belegs (PDF erste Seite oder Bild) im Inspector.
/// Klick öffnet das Dokument in der macOS-Vorschau (Preview.app). Liest nur aus dem
/// App-Container (sandbox-konform).
struct BelegVorschau: View {
    let pfad: String
    @State private var bild: NSImage?
    @State private var geladen = false

    private var url: URL { Belege.url(fuer: pfad) }

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            ZStack {
                if let bild {
                    Image(nsImage: bild)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 460)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor))
                        .frame(height: 160)
                        .overlay {
                            Image(systemName: geladen ? "doc" : "")
                                .font(.largeTitle).foregroundStyle(.secondary)
                            if !geladen { ProgressView().controlSize(.small) }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .padding(6)
            }
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .help("In der Vorschau öffnen")
        .task(id: pfad) { lade() }
    }

    private func lade() {
        bild = nil; geladen = false
        defer { geladen = true }
        let ext = (pfad as NSString).pathExtension.lowercased()
        if ext == "pdf" {
            if let doc = PDFDocument(url: url), let seite = doc.page(at: 0) {
                bild = seite.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)
            }
        } else {
            bild = NSImage(contentsOf: url)
        }
    }
}

/// Ablagefläche für einen Beleg (PDF/Bild): Drag & Drop **oder** Klick öffnet den
/// Datei-Dialog. Gleiche Größe/Optik wie die leere Beleg-Vorschau. Liefert die
/// gewählte Datei über `aufnehmen`; das Speichern (Jahr aus dem Eintrag) macht der Aufrufer.
struct BelegDropArea: View {
    var hinweis: String = "Beleg hierher ziehen oder klicken"
    let aufnehmen: (URL) -> Void
    @State private var zielAktiv = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .font(.largeTitle).foregroundStyle(zielAktiv ? Color.accentColor : .secondary)
            Text(hinweis).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(zielAktiv ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: zielAktiv ? 2 : 1, dash: [6]))
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { waehle() }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            aufnehmen(url); return true
        } isTargeted: { zielAktiv = $0 }
        .help("Beleg per Drag & Drop ablegen oder klicken zum Auswählen")
    }

    private func waehle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        aufnehmen(url)
    }
}

/// Schnellzugriff-Knopf, der den Zeitraum auf den laufenden Monat bzw. das laufende
/// Jahr zurücksetzt – konsistent über alle Auswertungs- und Tabellen-Views.
struct HeuteButton: View {
    var titel = "Aktueller Monat"
    var deaktiviert = false
    let aktion: () -> Void

    var body: some View {
        Button(action: aktion) { Label(titel, systemImage: "calendar.badge.clock") }
            .disabled(deaktiviert)
            .help("Auf den aktuellen Zeitraum springen")
    }
}

// MARK: - Karten-Zeilen (geteilt zwischen Monats-/Jahresabschluss)

/// Plakativer Abschluss-Hero: zwei große Kennzahlen nebeneinander auf einem Verlauf
/// (Klick kopiert den Wert). Geteilt zwischen Monats- und Jahresabschluss – die Farbe
/// (`verlauf`) unterscheidet die Screens: Monat = `Stil.markenVerlauf`, Jahr = `Stil.jahresVerlauf`.
struct AbschlussHero: View {
    /// Eine Hero-Kennzahl: Titel, Wert und (bei Negativwerten) abweichende Wertfarbe.
    struct Metrik {
        let titel: String
        let wert: Decimal
        var farbe: Color = .white
    }
    let verlauf: LinearGradient
    let links: Metrik
    let rechts: Metrik
    @State private var kopiertLinks = false
    @State private var kopiertRechts = false

    var body: some View {
        HStack(spacing: 0) {
            metrik(links, kopiert: $kopiertLinks)
            Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 60)
            metrik(rechts, kopiert: $kopiertRechts)
        }
        .padding(.vertical, 22).padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(verlauf, in: RoundedRectangle(cornerRadius: Stil.eckRadius))
    }

    private func metrik(_ m: Metrik, kopiert: Binding<Bool>) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text(m.titel).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                KopierHaken(sichtbar: kopiert.wrappedValue, farbe: .white)
            }
            Text(m.wert.euro).font(.system(size: 30, weight: .semibold)).monospacedDigit()
                .foregroundStyle(m.farbe)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { kopiereMitHaken(m.wert, kopiert) }
        .help("Klicken, um den Wert zu kopieren")
    }
}

/// Eine Kennzahl der unteren Summen-Leiste einer Tabelle (Caption + Geldwert) – einheitlich
/// für Einnahmen/Ausgaben/Einkäufe/Lebensmittel. `farbe` für Hinweise (z. B. rot bei Überzug).
/// Klick kopiert den Wert (wie alle Kennzahlen/Card-Zeilen) – diese Summen wandern oft direkt
/// in UStVA/EÜR-Formulare.
struct SummenWert: View {
    let titel: String
    let wert: Decimal
    var farbe: Color = .primary
    @State private var kopiert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(titel).font(.caption).foregroundStyle(.secondary)
                KopierHaken(sichtbar: kopiert)
            }
            Text(wert.euro).font(.headline).monospacedDigit().foregroundStyle(farbe)
        }
        .contentShape(Rectangle())
        .onTapGesture { kopiereMitHaken(wert, $kopiert) }
        .help("Klicken, um den Wert zu kopieren")
        .contextMenu { Button("Wert kopieren") { kopiereMitHaken(wert, $kopiert) } }
    }
}

/// Budget-Kennzahl der Summen-Leiste: „Ist / Budget" für die aktuelle Periode (Woche/Monat),
/// Ist-Wert rot, sobald er das Budget überschreitet. Klick kopiert den Ist-Wert.
struct BudgetWert: View {
    let titel: String
    let ist: Decimal
    let budget: Decimal
    @State private var kopiert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(titel).font(.caption).foregroundStyle(.secondary)
                KopierHaken(sichtbar: kopiert)
            }
            HStack(spacing: 4) {
                Text(ist.euro).font(.headline).monospacedDigit().foregroundStyle(ist > budget ? .red : .primary)
                Text("/ \(budget.euro)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { kopiereMitHaken(ist, $kopiert) }
        .help("Klicken, um den Ist-Wert zu kopieren")
        .contextMenu { Button("Wert kopieren") { kopiereMitHaken(ist, $kopiert) } }
    }
}

/// Kopiert einen Geldbetrag im dt. Format **ohne** Tausenderpunkt in die Zwischenablage.
func kopiereInZwischenablage(_ wert: Decimal) {
    let text = wert.formatted(.number.grouping(.never).precision(.fractionLength(2)).locale(Locale(identifier: "de_DE")))
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Wie `kopiereInZwischenablage`, blendet zusätzlich kurz ein grünes Häkchen ein
/// (setzt `flag` ~1,2 s auf true) – einheitliches Klick-Feedback der kopierbaren Werte.
@MainActor func kopiereMitHaken(_ wert: Decimal, _ flag: Binding<Bool>) {
    kopiereInZwischenablage(wert)
    withAnimation { flag.wrappedValue = true }
    Task { try? await Task.sleep(for: .seconds(1.2)); withAnimation { flag.wrappedValue = false } }
}

/// Kleines Kopier-Häkchen (für die kopierbaren Card-Zeilen). Standardfarbe grün;
/// für dunkle Hintergründe (z. B. AbschlussHero-Verlauf) kann `farbe: .white` übergeben werden.
struct KopierHaken: View {
    let sichtbar: Bool
    var farbe: Color = .green
    var body: some View {
        if sichtbar {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(farbe).font(.caption)
                .transition(.opacity)
        }
    }
}

/// Nativer Bestätigungsdialog vor dem Löschen – verhindert versehentlichen Datenverlust.
/// Gibt true zurück, wenn „Löschen" gewählt wird. Einheitlich für alle Tabellen.
@MainActor func bestaetigeLoeschung(_ anzahl: Int) -> Bool {
    guard anzahl > 0 else { return false }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = anzahl == 1 ? "Diesen Eintrag löschen?" : "\(anzahl) Einträge löschen?"
    alert.informativeText = "Das lässt sich nicht rückgängig machen."
    alert.addButton(withTitle: "Löschen")
    alert.addButton(withTitle: "Abbrechen").keyEquivalent = "\u{1b}"   // Escape bricht ab
    return alert.runModal() == .alertFirstButtonReturn
}

/// Eine Aufschlüsselungs-Zeile in einer Card: neutraler Icon-Chip (optional), Label, Wert.
/// Klick kopiert den Wert. `minus` stellt den Wert als Abzug dar.
struct Kartenzeile: View {
    let label: String
    let wert: Decimal
    var icon: String? = nil
    var minus: Bool = false
    @State private var kopiert = false

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            Text(label)
            Spacer()
            KopierHaken(sichtbar: kopiert)
            Text((minus ? "− " : "") + wert.euro)
                .monospacedDigit().foregroundStyle(minus ? .secondary : .primary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { kopiereMitHaken(wert, $kopiert) }
        .help("Klicken, um den Wert zu kopieren")
        .contextMenu { Button("Wert kopieren") { kopiereMitHaken(wert, $kopiert) } }
    }
}

/// Hervorgehobene Summen-/Ergebniszeile (semantische Farbe). Klick kopiert den Wert.
struct Summenzeile: View {
    let label: String
    let wert: Decimal
    var farbe: Color = .primary
    @State private var kopiert = false

    var body: some View {
        HStack {
            Text(label).font(.headline)
            Spacer()
            KopierHaken(sichtbar: kopiert)
            Text(wert.euro).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(farbe)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(farbe.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { kopiereMitHaken(wert, $kopiert) }
        .help("Klicken, um den Wert zu kopieren")
        .contextMenu { Button("Wert kopieren") { kopiereMitHaken(wert, $kopiert) } }
    }
}

/// Klick-freundliche Aufgabenliste für die Inspector-Sidebar der Abschluss-Screens.
/// Die ganze Zeile hakt ab (und erzeugt via `TaskVorlagen.nachAbschluss` die nächste fällige).
struct AufgabenInspektorListe: View {
    @Environment(\.modelContext) private var context
    let aufgaben: [MonthlyTask]
    var leererHinweis: String

    var body: some View {
        if aufgaben.isEmpty {
            ContentUnavailableView("Keine offenen Aufgaben", systemImage: "checklist",
                                   description: Text(leererHinweis))
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(aufgaben) { t in zeile(t) }
                }
                .padding(12)
            }
        }
    }

    private func zeile(_ t: MonthlyTask) -> some View {
        Button {
            t.erledigt.toggle(); TaskVorlagen.nachAbschluss(t, in: context)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: t.erledigt ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(t.erledigt ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.titel.isEmpty ? "—" : t.titel)
                        .strikethrough(t.erledigt).foregroundStyle(t.erledigt ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                    Text("fällig \(t.monat.formatted(.dateTime.day().month().year()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .karte(12)
        }
        .buttonStyle(.plain)
    }
}

/// Leerer Zustand für Inspector-Sidebars, wenn kein Eintrag ausgewählt ist.
struct LeereInspektorView: View {
    var titel: String = "Kein Eintrag gewählt"
    var hinweis: String = "Zeile wählen – oder „+“ für einen neuen Eintrag."

    var body: some View {
        ContentUnavailableView(titel, systemImage: "sidebar.right",
            description: Text(hinweis))
    }
}
