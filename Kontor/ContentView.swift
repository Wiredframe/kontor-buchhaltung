import AppKit
import SwiftData
import SwiftUI

// MARK: - Module

/// Alle Bereiche der App (Phase 1). Die Sidebar wird daraus aufgebaut,
/// die Reihenfolge hier bestimmt die Reihenfolge im Menü.
enum Modul: String, CaseIterable, Identifiable, Hashable {
    // Arbeitsfläche
    case dashboard
    case monatsabschluss
    case kontoauszug
    case aufgaben
    // Stammdaten
    case betriebsausgaben
    case einnahmen
    // Auswertungen
    case ustva
    case jahresuebersicht
    // …mit vier Unterseiten (eingerückt unter „Jahresabschluss", siehe `eltern`/`kinder`)
    case jahresEUR
    case jahresESt
    case jahresUSt
    case jahresVorsorge
    // Privat
    case privatUebersicht
    case lebensmittel
    case anschaffungen
    // System
    case einstellungen

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .dashboard: "Übersicht"
        case .monatsabschluss: "Monatsabschluss"
        case .kontoauszug: "Kontoauszug"
        case .aufgaben: "Aufgaben"
        case .betriebsausgaben: "Ausgaben"
        case .einnahmen: "Einnahmen"
        case .ustva: "UStVA"
        case .jahresuebersicht: "Jahresabschluss"
        case .jahresEUR: "EÜR"
        case .jahresESt: "Einkommensteuer"
        case .jahresUSt: "Umsatzsteuer"
        case .jahresVorsorge: "Vorsorge (KSK)"
        case .privatUebersicht: "Privat-Übersicht"
        case .lebensmittel: "Lebensmittel"
        case .anschaffungen: "Einkäufe"
        case .einstellungen: "Einstellungen"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "rectangle.3.group"
        case .monatsabschluss: "calendar.badge.checkmark"
        case .kontoauszug: "tray.and.arrow.down"
        case .aufgaben: "checklist"
        case .betriebsausgaben: "creditcard"
        case .einnahmen: "eurosign.circle"
        case .ustva: "doc.plaintext"
        case .jahresuebersicht: "chart.bar.xaxis"
        case .jahresEUR: "function"
        case .jahresESt: "percent"
        case .jahresUSt: "building.columns"
        case .jahresVorsorge: "cross.case"
        case .privatUebersicht: "person.crop.circle"
        case .lebensmittel: "cart"
        case .anschaffungen: "bag"
        case .einstellungen: "gearshape"
        }
    }

    /// Übergeordnetes Modul für die Sidebar-Einrückung; `nil` = Zeile auf oberster Ebene.
    var eltern: Modul? {
        switch self {
        case .jahresEUR, .jahresESt, .jahresUSt, .jahresVorsorge: .jahresuebersicht
        default: nil
        }
    }
    /// Untermenüpunkte dieses Moduls (leer = keine aufklappbare Zeile).
    var kinder: [Modul] { Modul.allCases.filter { $0.eltern == self } }
}

/// Gruppierung der Module in der Sidebar.
enum ModulGruppe: String, CaseIterable, Identifiable {
    case arbeitsflaeche = "Arbeitsfläche"
    case stammdaten = "Stammdaten"
    case auswertungen = "Auswertungen"
    case privat = "Privat"
    case system = "System"

    var id: String { rawValue }

    var module: [Modul] {
        switch self {
        case .arbeitsflaeche: [.dashboard, .monatsabschluss, .kontoauszug, .aufgaben]
        case .stammdaten: [.einnahmen, .betriebsausgaben]
        case .auswertungen: [.ustva, .jahresuebersicht]
        case .privat: [.privatUebersicht, .lebensmittel, .anschaffungen]
        case .system: [.einstellungen]
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var nav = Navigation()
    @State private var zeit = Zeitkontext()
    @State private var zeigeWiederherstellung = UserDefaults.standard.bool(forKey: "storeWiederhergestellt")
    @State private var zeigeOnboarding = false
    /// Globale Einstellung: Seitenleiste undurchsichtig (deaktiviert die System-Transparenz/Vibrancy).
    @AppStorage("sidebarOpak") private var sidebarOpak = false
    /// Aufgeklappte Eltern-Module als komma-getrennte rawValues (`AppStorage` kann kein `Set`).
    @AppStorage("sidebarOffeneModule") private var offeneRoh = Modul.jahresuebersicht.rawValue
    #if !APPSTORE
    /// Spendenseite (Stripe) – freiwillige Unterstützung, öffnet im Browser.
    /// Im App-Store-Build (`APPSTORE`) entfällt jeder Spendenaufruf (Guideline 3.1.1).
    private static let stripeSpendenURL = "https://donate.stripe.com/28E14obXGgBH3ol2Fs6sw00"
    #endif

    var body: some View {
        @Bindable var nav = nav
        NavigationSplitView {
            List(selection: $nav.modul) {
                ForEach(ModulGruppe.allCases) { gruppe in
                    Section(gruppe.rawValue) {
                        ForEach(gruppe.module) { modul in
                            if modul.kinder.isEmpty {
                                Label(modul.titel, systemImage: modul.symbol)
                                    .tag(modul)
                            } else {
                                elternZeile(modul)
                                if offen.contains(modul) {
                                    ForEach(modul.kinder) { kind in
                                        Label(kind.titel, systemImage: kind.symbol)
                                            .padding(.leading, 18)
                                            .tag(kind)
                                    }
                                }
                            }
                        }
                    }
                }
                #if !APPSTORE
                spendenMenue
                #endif
            }
            .navigationTitle("Kontor")
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
            // Optional undurchsichtige Seitenleiste: System-Vibrancy ausblenden und opak hinterlegen.
            .scrollContentBackground(sidebarOpak ? .hidden : .automatic)
            .background(sidebarOpak ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        } detail: {
            if let auswahl = nav.modul {
                detailAnsicht(auswahl)
            } else {
                ContentUnavailableView(
                    "Kein Bereich gewählt",
                    systemImage: "sidebar.left",
                    description: Text("Wähle links einen Bereich aus.")
                )
            }
        }
        .environment(nav)
        .environment(zeit)
        .environment(\.locale, Locale(identifier: "de_DE"))
        .alert("Datenbank zurückgesetzt", isPresented: $zeigeWiederherstellung) {
            Button("OK") { UserDefaults.standard.set(false, forKey: "storeWiederhergestellt") }
        } message: {
            Text(
                "Die Datenbank war beschädigt und wurde neu angelegt. Stelle deine Daten über Einstellungen → Import aus einem Auto-Backup wieder her (Ordner App-Daten/Backups)."
            )
        }
        .sheet(isPresented: $zeigeOnboarding) {
            OnboardingView(
                aufDemodaten: {
                    Demodaten.einspielen(context)
                    UserDefaults.standard.set(true, forKey: "onboardingErledigt")
                    aktualisiereJahre(zeit, context)
                    nav.modul = .dashboard
                    zeigeOnboarding = false
                },
                aufLeer: {
                    UserDefaults.standard.set(true, forKey: "onboardingErledigt")
                    zeigeOnboarding = false
                }
            )
            .interactiveDismissDisabled()
        }
        .task {
            aktualisiereJahre(zeit, context)
            #if DEBUG
            // Screenshot-Automatik (nur Dev): per Startargument `-startModul <rawValue>` direkt
            // ein Modul öffnen (z. B. `open -n … --args -startModul monatsabschluss`). Kein Effekt
            // ohne das Argument; in Release ohnehin wegkompiliert.
            if let s = UserDefaults.standard.string(forKey: "startModul"), let m = Modul(rawValue: s) {
                nav.modul = m
                // Erscheinungsbild der ganzen App (inkl. Titelleiste) fürs Screenshot erzwingen.
                if let a = UserDefaults.standard.string(forKey: "startAppearance") {
                    NSApp.appearance = NSAppearance(named: a == "dark" ? .darkAqua : .aqua)
                }
                // Fenster maximieren, damit die Screenshots das volle Layout zeigen.
                try? await Task.sleep(for: .milliseconds(300))
                if let win = NSApp.windows.first(where: { $0.isVisible }),
                    let scr = win.screen ?? NSScreen.main
                {
                    win.setFrame(scr.visibleFrame, display: true)
                }
                return
            }
            #endif
            // Erst-Start: nur bei komplett leerem Store die Demodaten-/Leer-Auswahl zeigen.
            if !UserDefaults.standard.bool(forKey: "onboardingErledigt"), Demodaten.istLeer(context) {
                zeigeOnboarding = true
            }
        }
        .onChange(of: nav.modul) { _, neu in
            aktualisiereJahre(zeit, context)
            // Querlinks (z. B. die Bereichskarten des Jahresabschlusses) und der DEBUG-Startpfad
            // können ein Kind direkt anspringen – dann muss das Eltern-Modul aufklappen, sonst
            // steht die Auswahl auf einer unsichtbaren Zeile.
            if let e = neu?.eltern, !offen.contains(e) { schalteOffen(e) }
        }
    }

    // MARK: Sidebar-Untermenü

    /// Aufgeklappte Eltern-Module.
    private var offen: Set<Modul> {
        Set(offeneRoh.split(separator: ",").compactMap { Modul(rawValue: String($0)) })
    }
    private func schalteOffen(_ m: Modul) {
        var neu = offen
        if neu.contains(m) { neu.remove(m) } else { neu.insert(m) }
        offeneRoh = neu.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// Zeile eines Moduls mit Unterpunkten: eine ganz normale, getaggte List-Zeile (Klick =
    /// Auswahl) mit eigenem Chevron-Button rechts, der **nur** auf- und zuklappt.
    ///
    /// Bewusst kein `DisclosureGroup`: dort ist die Label-Zeile selbst der Disclosure-Control,
    /// ein Klick darauf klappt statt auszuwählen – die Eltern-Seite wäre nicht mehr erreichbar.
    /// `Section(isExpanded:)` scheidet aus demselben Grund aus (Header ist nicht selektierbar).
    private func elternZeile(_ modul: Modul) -> some View {
        HStack(spacing: 6) {
            Label(modul.titel, systemImage: modul.symbol)
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy(duration: 0.18)) { schalteOffen(modul) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(offen.contains(modul) ? 90 : 0))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(offen.contains(modul) ? "Unterbereiche ausblenden" : "Unterbereiche einblenden")
        }
        .tag(modul)
    }

    #if !APPSTORE
    /// Letzter Menüpunkt zum Unterstützen der Entwicklung: Link auf die Stripe-Spendenseite.
    @ViewBuilder private var spendenMenue: some View {
        Section {
            Button {
                if let url = URL(string: Self.stripeSpendenURL) { openURL(url) }
            } label: {
                Label("Kontor unterstützen", systemImage: "heart")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    #endif

    /// Routet auf die Ansicht des gewählten Moduls.
    @ViewBuilder
    private func detailAnsicht(_ modul: Modul) -> some View {
        switch modul {
        case .dashboard: DashboardView()
        case .monatsabschluss: MonatsabschlussView()
        case .kontoauszug: ImportView()
        case .aufgaben: AufgabenView()
        case .betriebsausgaben: AusgabenView()
        case .einnahmen: EinnahmenView()
        case .ustva: UStVAView()
        case .jahresuebersicht: JahresuebersichtView()
        case .jahresEUR: JahresEURView()
        case .jahresESt: JahresEinkommensteuerView()
        case .jahresUSt: JahresUmsatzsteuerView()
        case .jahresVorsorge: JahresVorsorgeView()
        case .privatUebersicht: PrivatUebersichtView()
        case .lebensmittel: LebensmittelView()
        case .anschaffungen: AnschaffungenView()
        case .einstellungen: EinstellungenView()
        }
    }
}

#Preview {
    ContentView()
}
