import SwiftUI
import SwiftData

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
    // Privat
    case privatUebersicht
    case lebensmittel
    case anschaffungen
    // System
    case einstellungen

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .dashboard:        "Übersicht"
        case .monatsabschluss:  "Monatsabschluss"
        case .kontoauszug:      "Kontoauszug"
        case .aufgaben:         "Aufgaben"
        case .betriebsausgaben: "Ausgaben"
        case .einnahmen:        "Einnahmen"
        case .ustva:            "UStVA"
        case .jahresuebersicht: "Jahresabschluss"
        case .privatUebersicht: "Privat-Übersicht"
        case .lebensmittel:     "Lebensmittel"
        case .anschaffungen:    "Einkäufe"
        case .einstellungen:    "Einstellungen"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard:        "rectangle.3.group"
        case .monatsabschluss:  "calendar.badge.checkmark"
        case .kontoauszug:      "tray.and.arrow.down"
        case .aufgaben:         "checklist"
        case .betriebsausgaben: "creditcard"
        case .einnahmen:        "eurosign.circle"
        case .ustva:            "doc.plaintext"
        case .jahresuebersicht: "chart.bar.xaxis"
        case .privatUebersicht: "person.crop.circle"
        case .lebensmittel:     "cart"
        case .anschaffungen:    "bag"
        case .einstellungen:    "gearshape"
        }
    }
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
        case .stammdaten:     [.einnahmen, .betriebsausgaben]
        case .auswertungen:   [.ustva, .jahresuebersicht]
        case .privat:         [.privatUebersicht, .lebensmittel, .anschaffungen]
        case .system:         [.einstellungen]
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
    #if APPSTORE
    @State private var spendenStore = SpendenStore()
    #else
    /// Spendenseite (Stripe) – nur in der freien Variante; im App-Store-Build physisch nicht vorhanden.
    private static let stripeSpendenURL = "https://donate.stripe.com/28E14obXGgBH3ol2Fs6sw00"
    #endif

    var body: some View {
        @Bindable var nav = nav
        #if APPSTORE
        @Bindable var spende = spendenStore
        #endif
        NavigationSplitView {
            List(selection: $nav.modul) {
                ForEach(ModulGruppe.allCases) { gruppe in
                    Section(gruppe.rawValue) {
                        ForEach(gruppe.module) { modul in
                            Label(modul.titel, systemImage: modul.symbol)
                                .tag(modul)
                        }
                    }
                }
                spendenMenue
            }
            .navigationTitle("Kontor")
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
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
            Text("Die Datenbank war beschädigt und wurde neu angelegt. Stelle deine Daten über Einstellungen → Import aus einem Auto-Backup wieder her (Ordner App-Daten/Backups).")
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
                })
            .interactiveDismissDisabled()
        }
        .task {
            aktualisiereJahre(zeit, context)
            // Erst-Start: nur bei komplett leerem Store die Demodaten-/Leer-Auswahl zeigen.
            if !UserDefaults.standard.bool(forKey: "onboardingErledigt"), Demodaten.istLeer(context) {
                zeigeOnboarding = true
            }
        }
        .onChange(of: nav.modul) { _, _ in aktualisiereJahre(zeit, context) }
        #if APPSTORE
        .environment(spendenStore)
        .task { await spendenStore.starten() }
        .sheet(isPresented: $spende.zeigeScreen) {
            SpendenView(store: spendenStore)
        }
        #endif
    }

    /// Letzter Menüpunkt zum Unterstützen der Entwicklung.
    /// - App-Store-Variante (APPSTORE): freiwilliges Trinkgeld per In-App-Kauf, drei Zustände
    ///   (Button, dann Dank-Zeile mit ✕ zum dauerhaften Ausblenden, danach Wiedereinstieg via Einstellungen).
    /// - Freie Variante: einfacher Link auf die Stripe-Spendenseite (im App-Store-Build NICHT enthalten).
    @ViewBuilder private var spendenMenue: some View {
        #if APPSTORE
        if !spendenStore.hatGespendet {
            Section {
                Button {
                    spendenStore.zeigeScreen = true
                } label: {
                    Label("Kontor unterstützen", systemImage: "heart")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else if !spendenStore.dankeAusgeblendet {
            Section {
                HStack(spacing: 6) {
                    Button {
                        spendenStore.zeigeScreen = true
                    } label: {
                        Label("Vielen Dank für deine Unterstützung", systemImage: "heart.fill")
                            .foregroundStyle(Stil.privat)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button {
                        spendenStore.dankeAusgeblendet = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Diesen Hinweis dauerhaft ausblenden")
                }
            }
        }
        #else
        Section {
            Button {
                if let url = URL(string: Self.stripeSpendenURL) { openURL(url) }
            } label: {
                Label("Kontor unterstützen", systemImage: "heart")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        #endif
    }

    /// Routet auf die Ansicht des gewählten Moduls.
    @ViewBuilder
    private func detailAnsicht(_ modul: Modul) -> some View {
        switch modul {
        case .dashboard:        DashboardView()
        case .monatsabschluss:  MonatsabschlussView()
        case .kontoauszug:      ImportView()
        case .aufgaben:         AufgabenView()
        case .betriebsausgaben: AusgabenView()
        case .einnahmen:        EinnahmenView()
        case .ustva:            UStVAView()
        case .jahresuebersicht: JahresuebersichtView()
        case .privatUebersicht: PrivatUebersichtView()
        case .lebensmittel:     LebensmittelView()
        case .anschaffungen:    AnschaffungenView()
        case .einstellungen:    EinstellungenView()
        }
    }
}

#Preview {
    ContentView()
}
