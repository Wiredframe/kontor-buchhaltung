import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct EinstellungenView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \YearSettings.jahr, order: .reverse) private var jahre: [YearSettings]
    @State private var jahr = appKalender.component(.year, from: Date())

    private var aktuelle: YearSettings? { jahre.first { $0.jahr == jahr } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Jahr").foregroundStyle(.secondary)
                JahrWaehler(jahr: $jahr)
                Spacer()
            }
            .padding()
            Divider()

            if let s = aktuelle {
                EinstellungenForm(settings: s)
            } else {
                ContentUnavailableView {
                    Label("Keine Einstellungen für \(String(jahr))", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Lege jahresbezogene Einstellungen für \(String(jahr)) an.")
                } actions: {
                    Button("Für \(String(jahr)) anlegen") { anlegen() }
                }
            }
        }
        .navigationTitle("Einstellungen")
    }

    private func anlegen() {
        context.insert(YearSettings(jahr: jahr, estPauschalSatz: dez("0.15")))
    }
}

private struct EinstellungenForm: View {
    @Environment(\.modelContext) private var context
    @Environment(MCPServer.self) private var mcp
    @Bindable var settings: YearSettings
    @State private var status: String?
    @AppStorage("budgetLebensmittelWoche") private var budgetWoche = 50.0
    @AppStorage("budgetAnschaffungenMonat") private var budgetMonat = 80.0

    var body: some View {
        Form {
            Section("Jahr \(String(settings.jahr))") {
                Picker("UStVA-Rhythmus", selection: $settings.ustvaRhythmus) {
                    ForEach(UStVARhythmus.allCases) { Text($0.bezeichnung).tag($0) }
                }
                Toggle("Dauerfristverlängerung", isOn: $settings.dauerfristverlaengerung)
                LabeledContent("Versteuerung", value: "Soll (vereinbarte Entgelte)")
                Text("KSK-Beitrag und ESt-Satz werden pro Monat im Monatsabschluss gepflegt (Sidebar-Tab „Werte“).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Budgets (privat)") {
                TextField("Lebensmittel / Woche", value: $budgetWoche, format: .currency(code: "EUR"))
                TextField("Anschaffungen / Monat", value: $budgetMonat, format: .currency(code: "EUR"))
                Text("0 = kein Budget anzeigen.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Komplett-Backup (mit Belegen)") {
                Button { exportiereKomplett() } label: {
                    Label("Komplett-Backup exportieren …", systemImage: "square.and.arrow.up.on.square")
                }
                Button { importiereKomplett() } label: {
                    Label("Komplett-Backup importieren …", systemImage: "square.and.arrow.down.on.square")
                }
                Text("Sichert alle Daten **samt Belegen** als Ordner (kontor.json + Belege/). Empfohlen für Umzug oder vollständige Wiederherstellung.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Nur Daten (JSON)") {
                Button { exportieren() } label: {
                    Label("Als JSON exportieren …", systemImage: "square.and.arrow.up")
                }
                Button { importiereJSON() } label: {
                    Label("Aus JSON-Backup importieren …", systemImage: "tray.and.arrow.down.fill")
                }
                Text("Leichtgewichtig, ohne Belege. Import ohne Überschreiben (Dedup über Rechnungsnummer bzw. Schlüssel).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Auto-Backup") {
                Button { if let u = Backup.backupOrdner() { NSWorkspace.shared.open(u) } } label: {
                    Label("Auto-Backup-Ordner öffnen …", systemImage: "folder")
                }
                Text("Beim Start wird automatisch ein tägliches Backup angelegt (JSON, letzte 14 Tage). Hinweis: Auto-Backups enthalten keine Beleg-Dateien – dafür das Komplett-Backup nutzen.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("KI-Zugriff (MCP)") {
                Toggle("Lokalen MCP-Server aktivieren", isOn: Binding(
                    get: { mcp.aktiv },
                    set: { an in
                        if an { mcp.starten() } else { mcp.stoppen() }
                        UserDefaults.standard.set(an, forKey: "mcpAktiv")
                    }))
                if mcp.aktiv {
                    LabeledContent("Adresse", value: mcp.url)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(mcp.einrichtbefehl, forType: .string)
                        status = "Claude-Code-Befehl in die Zwischenablage kopiert."
                    } label: {
                        Label("Einrichtungsbefehl für Claude Code kopieren", systemImage: "doc.on.doc")
                    }
                }
                if let fehler = mcp.letzterFehler {
                    Label(fehler, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Erlaubt einem externen KI-Client (z. B. Claude Code) Zugriff auf deine Daten – nur lokal (127.0.0.1), Token-geschützt. Lesen (Engine-Zahlen/CSV) **und** sparsames Schreiben (Ausgabe anlegen, Rechnung bezahlt); vor dem ersten Schreibzugriff je Sitzung wird automatisch ein Backup im Ordner „KI-Backups“ abgelegt.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Unterstützung") {
                Button {
                    if let url = URL(string: "https://donate.stripe.com/28E14obXGgBH3ol2Fs6sw00") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Kontor unterstützen …", systemImage: "heart")
                }
                Text("Kontor ist kostenlos. Über eine freiwillige Spende freue ich mich sehr – der Link öffnet die Spendenseite im Browser.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Rechtliches") {
                Button {
                    if let url = URL(string: "https://www.wiredframe.de/impressum.html") { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Impressum", systemImage: "info.circle")
                }
                Button {
                    if let url = URL(string: "https://www.wiredframe.de/privacy.html") { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Datenschutz", systemImage: "hand.raised")
                }
            }

            Section("Datenbank") {
                Text("Deine Einträge bleiben dauerhaft gespeichert – die App setzt beim Bauen oder Starten nichts zurück. Sicherung und Wiederherstellung laufen über die Backup-/Import-Funktionen oben.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let status {
                Section { Text(status).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    private func exportieren() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "kontor-backup-\(settings.jahr).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Backup.exportData(context).write(to: url)
            status = "Exportiert: \(url.lastPathComponent)"
        } catch {
            status = "Export fehlgeschlagen: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    private func exportiereKomplett() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = "Zielordner für das Komplett-Backup wählen"
        panel.prompt = "Hier sichern"
        guard panel.runModal() == .OK, let ordner = panel.url else { return }
        let scoped = ordner.startAccessingSecurityScopedResource()
        defer { if scoped { ordner.stopAccessingSecurityScopedResource() } }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let ziel = ordner.appendingPathComponent("Kontor-Backup-\(df.string(from: Date()))")
        do {
            try Backup.exportiereKomplett(context, nach: ziel)
            status = "Komplett-Backup gespeichert: \(ziel.lastPathComponent) (inkl. Belege)."
        } catch {
            status = "Export fehlgeschlagen: \(error.localizedDescription)"; NSSound.beep()
        }
    }

    private func importiereKomplett() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Komplett-Backup-Ordner wählen (enthält kontor.json)"
        panel.prompt = "Importieren"
        guard panel.runModal() == .OK, let ordner = panel.url else { return }
        let scoped = ordner.startAccessingSecurityScopedResource()
        defer { if scoped { ordner.stopAccessingSecurityScopedResource() } }
        do {
            let r = try Backup.importiereKomplett(context, von: ordner)
            status = "Komplett-Import: \(r.neu) neu, \(r.uebersprungen) übersprungen (inkl. Belege)."
        } catch {
            status = "Import fehlgeschlagen: \(error.localizedDescription)"; NSSound.beep()
        }
    }

    private func importiereJSON() {
        guard let url = dateiWaehlen(titel: "Kontor JSON-Backup wählen") else { return }
        do {
            let data = try Data(contentsOf: url)
            let r = try Backup.importData(data, in: context)
            status = "Import: \(r.neu) Datensätze neu, \(r.uebersprungen) übersprungen."
        } catch {
            status = "Import fehlgeschlagen: \(error.localizedDescription)"; NSSound.beep()
        }
    }

    private func dateiWaehlen(titel: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = titel
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
