import SwiftUI
import SwiftData

/// Eine Aufgabenliste – einmalig oder wiederkehrend (Reminders-Logik: beim Abhaken
/// einer wiederkehrenden Aufgabe erscheint automatisch die nächste fällige).
struct AufgabenView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MonthlyTask.monat, order: .reverse) private var tasks: [MonthlyTask]

    @Environment(Zeitkontext.self) private var zeit
    @State private var selection = Set<MonthlyTask.ID>()
    @State private var sortOrder = [KeyPathComparator(\MonthlyTask.monat, order: .reverse)]
    @State private var zeigeInspektor = true
    @State private var suche = ""

    private var gefiltert: [MonthlyTask] {
        tasks.filter { zeit.filter.enthaelt($0.monat) && (suche.isEmpty || $0.titel.localizedCaseInsensitiveContains(suche)) }
    }
    private var anzeige: [MonthlyTask] { gefiltert.sorted(using: sortOrder) }
    private var ausgewaehlt: MonthlyTask? { selection.count == 1 ? tasks.first { $0.id == selection.first } : nil }

    var body: some View {
        @Bindable var zeit = zeit
        return VStack(spacing: 0) {
            ZeitraumLeiste(filter: $zeit.filter)
            Divider()
            Table(anzeige, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("", value: \.erledigtSort) { t in
                    Button { t.erledigt.toggle(); TaskVorlagen.nachAbschluss(t, in: context) } label: {
                        Image(systemName: t.erledigt ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(t.erledigt ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(t.erledigt ? "Als offen markieren" : "Als erledigt markieren")
                }
                .width(30)
                TableColumn("Aufgabe", value: \.titel) { t in
                    Text(t.titel.isEmpty ? "—" : t.titel)
                        .strikethrough(t.erledigt).foregroundStyle(t.erledigt ? .secondary : .primary).lineLimit(1)
                }
                .width(min: 200, ideal: 320)
                TableColumn("Wiederholung", value: \.intervall.sortRang) { t in
                    if t.istWiederkehrend {
                        Label(t.intervall.bezeichnung, systemImage: "repeat").foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .width(min: 110, ideal: 140)
                TableColumn("Fällig", value: \.monat) { Text($0.monat, format: .dateTime.day().month().year()).lineLimit(1) }
                    .width(min: 96, ideal: 120)
            }
            .environment(\.defaultMinListRowHeight, 36)
            .onDeleteCommand { loesche(selection) }
            .contextMenu(forSelectionType: MonthlyTask.ID.self) { ids in
                Button("Duplizieren") { duplizieren(ids) }
                Button("Löschen", role: .destructive) { loesche(ids) }
            }
        }
        .navigationTitle("Aufgaben")
        .searchable(text: $suche, prompt: "Aufgabe suchen")
        .toolbar {
            ToolbarItemGroup {
                Button { neu() } label: { Label("Neu", systemImage: "plus") }
                Button { zeigeInspektor.toggle() } label: { Label("Details", systemImage: "sidebar.trailing") }
            }
        }
        .inspector(isPresented: $zeigeInspektor) {
            Group {
                if let t = ausgewaehlt { AufgabenInspektor(task: t) }
                else { LeereInspektorView(titel: "Keine Aufgabe gewählt",
                        hinweis: "Zeile wählen – oder „+“ für eine neue Aufgabe.") }
            }
            .inspectorColumnWidth(min: 280, ideal: 330, max: 440)
        }
    }

    private func neu() {
        let t = MonthlyTask(titel: "", monat: Date())
        context.insert(t); try? context.save()
        suche = ""; if !zeit.filter.enthaelt(t.monat) { zeit.filter.modus = .alle }
        selection = [t.id]; zeigeInspektor = true
    }
    private func duplizieren(_ ids: Set<MonthlyTask.ID>) {
        for t in tasks where ids.contains(t.id) {
            context.insert(MonthlyTask(titel: t.titel, monat: t.monat, erledigt: false,
                intervall: t.intervall, faelligTag: t.faelligTag, quartalsMonate: t.quartalsMonate))
        }
    }
    private func loesche(_ ids: Set<MonthlyTask.ID>) {
        guard bestaetigeLoeschung(ids.count) else { return }
        selection.subtract(ids)
        for t in tasks where ids.contains(t.id) { context.delete(t) }
    }
}

struct AufgabenInspektor: View {
    @Environment(\.modelContext) private var context
    @Bindable var task: MonthlyTask
    @FocusState private var fokus: Bool

    /// Für „jährlich": der eine Stichtags-Monat steckt in `quartalsMonate`.
    private var jahre: ClosedRange<Int> {
        let h = appKalender.component(.year, from: Date()); return (h - 1)...(h + 2)
    }
    private var faelligMonat: Binding<Int> {
        Binding { appKalender.component(.month, from: task.monat) }
            set: { setzeFaellig(monat: $0, jahr: appKalender.component(.year, from: task.monat)) }
    }
    private var faelligJahr: Binding<Int> {
        Binding { appKalender.component(.year, from: task.monat) }
            set: { setzeFaellig(monat: appKalender.component(.month, from: task.monat), jahr: $0) }
    }
    private var faelligQuartal: Binding<Int> {
        Binding { (appKalender.component(.month, from: task.monat) - 1) / 3 + 1 }
            set: { setzeQuartal($0, jahr: appKalender.component(.year, from: task.monat)) }
    }
    /// Setzt die Fälligkeit dieser Instanz auf Monat/Jahr (Tag = faelligTag); jährlich pflegt den Stichtagsmonat.
    private func setzeFaellig(monat: Int, jahr: Int) {
        let tagN = min(max(task.faelligTag, 1), 28)
        task.monat = appKalender.date(from: DateComponents(year: jahr, month: monat, day: tagN)) ?? task.monat
        if task.intervall == .jaehrlich { task.quartalsMonate = [monat] }
    }
    /// Setzt die Fälligkeit auf das Quartal – Stichtagsmonat aus dem Schema, sonst Quartalsanfang.
    private func setzeQuartal(_ q: Int, jahr: Int) {
        let muster = task.quartalsMonate.sorted()
        let monat = muster.count >= q ? muster[q - 1] : (q - 1) * 3 + 1
        setzeFaellig(monat: monat, jahr: jahr)
    }

    var body: some View {
        Form {
            TextField("Aufgabe", text: $task.titel).focused($fokus)
            Picker("Wiederholung", selection: $task.intervall) {
                ForEach(TaskIntervall.allCases) { Text($0.bezeichnung).tag($0) }
            }
            if task.intervall == .einmalig {
                DatePicker("Fällig", selection: $task.monat, displayedComponents: .date)
            } else if task.intervall == .quartalsweise {
                HStack {
                    Picker("Quartal", selection: faelligQuartal) {
                        ForEach(1...4, id: \.self) { Text("Q\($0)").tag($0) }
                    }
                    Picker("Jahr", selection: faelligJahr) {
                        ForEach(jahre, id: \.self) { Text(verbatim: String($0)).tag($0) }
                    }
                }
                Stepper(value: $task.faelligTag, in: 1...28) { Text(verbatim: "Stichtag: Tag \(task.faelligTag)") }
                Section("Quartals-Schema (Stichtags-Monate)") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 6)], spacing: 6) {
                        ForEach(1...12, id: \.self) { monatChip($0) }
                    }
                    HStack {
                        Button("UStVA (1·4·7·10)") { task.quartalsMonate = [1, 4, 7, 10]; setzeQuartal(faelligQuartal.wrappedValue, jahr: faelligJahr.wrappedValue) }
                        Spacer()
                        Button("ESt-VZ (3·6·9·12)") { task.quartalsMonate = [3, 6, 9, 12]; setzeQuartal(faelligQuartal.wrappedValue, jahr: faelligJahr.wrappedValue) }
                    }
                    .font(.caption).buttonStyle(.link)
                }
                LabeledContent("Nächste Fälligkeit", value: task.monat.formatted(.dateTime.day().month().year()))
            } else {
                // monatlich & jährlich: Monat & Jahr der laufenden Fälligkeit wählen
                HStack {
                    Picker("Monat", selection: faelligMonat) {
                        ForEach(1...12, id: \.self) { Text(monatsName($0)).tag($0) }
                    }
                    Picker("Jahr", selection: faelligJahr) {
                        ForEach(jahre, id: \.self) { Text(verbatim: String($0)).tag($0) }
                    }
                }
                Text(task.intervall == .monatlich
                     ? "Steht im Monatsabschluss des gewählten Monats; Abhaken erzeugt den Folgemonat."
                     : "Steht im Jahresabschluss des gewählten Jahres; Abhaken erzeugt das Folgejahr.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Erledigt", isOn: $task.erledigt)
        }
        .formStyle(.grouped)
        .onChange(of: task.id, initial: true) { _, _ in fokus = task.titel.isEmpty }
        .onChange(of: task.erledigt) { _, _ in TaskVorlagen.nachAbschluss(task, in: context) }
        .onChange(of: task.intervall) { _, neu in
            // Sinnvolle Defaults; die explizit gewählte Fälligkeit (task.monat) bleibt erhalten.
            if neu == .jaehrlich, task.quartalsMonate.isEmpty {
                task.quartalsMonate = [appKalender.component(.month, from: task.monat)]
            }
            if neu == .quartalsweise, task.quartalsMonate.isEmpty {
                task.quartalsMonate = [1, 4, 7, 10]
            }
        }
        .onChange(of: task.faelligTag) { _, _ in
            guard task.istWiederkehrend else { return }
            setzeFaellig(monat: appKalender.component(.month, from: task.monat),
                         jahr: appKalender.component(.year, from: task.monat))
        }
    }

    private func monatChip(_ m: Int) -> some View {
        let an = task.quartalsMonate.contains(m)
        return Button {
            if an { task.quartalsMonate.removeAll { $0 == m } } else { task.quartalsMonate.append(m) }
            setzeQuartal(faelligQuartal.wrappedValue, jahr: faelligJahr.wrappedValue)
        } label: {
            Text(kurzMonat(m)).font(.caption2)
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(an ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(an ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}
