import SwiftData
import SwiftUI

/// Gemeinsamer Rahmen **aller fünf** Jahresabschluss-Seiten (Übersicht + EÜR, Einkommensteuer,
/// Umsatzsteuer, Vorsorge).
///
/// Trägt Kopfleiste (Jahr-Wähler, „Aktuelles Jahr"), das Warnbanner für fehlende
/// `YearSettings`, den Aufgaben-Inspector mit den **jährlichen** Aufgaben des Jahres und dessen
/// Toolbar-Schalter. Die `@Query`-Arrays und die `Jahreswerte` leben hier: seit der
/// Jahresabschluss aus fünf Seiten besteht, wäre sonst beides fünfmal codiert.
struct JahresSeite<Inhalt: View, KopfRechts: View>: View {
    let titel: String
    @ViewBuilder var kopfRechts: () -> KopfRechts
    @ViewBuilder var inhalt: (Jahreswerte) -> Inhalt

    @Query private var einnahmen: [Income]
    @Query private var ausgaben: [ExpenseEntry]
    @Query private var zahlungen: [TaxPayment]
    @Query private var jahre: [YearSettings]
    @Query private var tasks: [MonthlyTask]

    @Environment(\.modelContext) private var context
    @Environment(Zeitkontext.self) private var zeit

    /// Bewusst `@AppStorage` statt `@State`: die fünf Seiten sind getrennte Views, mit `@State`
    /// klappte die Aufgaben-Sidebar bei jedem Wechsel in den Startzustand zurück.
    @AppStorage("jahresabschlussAufgabenOffen") private var zeigeAufgaben = true

    private var jahr: Int { zeit.filter.jahr }
    private var settings: YearSettings? { jahre.first { $0.jahr == jahr } }
    /// Nur jährliche Aufgaben des gewählten Jahres – für die Abschluss-Sidebar.
    private var jahresAufgaben: [MonthlyTask] {
        tasks.filter { $0.intervall == .jaehrlich && appKalender.component(.year, from: $0.monat) == jahr }
            .sorted { $0.monat < $1.monat }
    }

    var body: some View {
        @Bindable var zeit = zeit
        let w = Jahreswerte.bauen(
            jahr: jahr, einnahmen: einnahmen, ausgaben: ausgaben, zahlungen: zahlungen, jahre: jahre)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                inhalt(w)
            }
            .padding()
        }
        // Keine Trennlinie zwischen Hinweis-Zone und Inhalt – wie im Monatsabschluss.
        .scrollEdgeEffektAus()
        // Kopf als gepinnter Top-Inset statt als VStack über der ScrollView – dasselbe Muster wie
        // in `MonatsabschlussView`. Der Kopf bleibt beim Scrollen stehen, und Höhenwechsel dieser
        // Zone (das Warnbanner kommt und geht mit dem Jahr) verschieben nicht den Seiteninhalt.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                // Ohne YearSettings rechnen ESt und KSK still mit Fallbacks weiter (15 % / 0 €) –
                // plausibel aussehende, falsche Zahlen. Das gehört sichtbar gemacht, nicht versteckt.
                FehlendeJahresEinstellungen(jahr: jahr, settings: settings) {
                    context.insert(YearSettings(jahr: jahr, estPauschalSatz: dez("0.15")))
                    try? context.save()
                }
            }
            .padding(.horizontal).padding(.bottom, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .seitenGrund()
        .navigationTitle(titel)
        .toolbar {
            // Nur das Jahr ist hier sinnvoll – die Seiten rechnen ausschliesslich je Jahr.
            ToolbarItem(placement: .principal) {
                ZeitraumChip(filter: $zeit.filter, umfang: .nurJahr)
            }
            ToolbarItemGroup {
                kopfRechts()
            }
            // Der Inspector-Schalter steht **allein**, nicht in der Gruppe der Aktionen: Er
            // tut etwas grundlegend anderes (Ansicht umschalten statt Daten zu exportieren), und die
            // gemeinsame Kapsel legte genau das Gegenteil nahe.
            //
            // Ein eigenes `ToolbarItem` reicht dafür **nicht**: macOS fasst benachbarte Items
            // optisch weiter zu einer Kapsel zusammen. Erst der `ToolbarSpacer` trennt sie
            // sichtbar – den gibt es ab macOS 26, darunter bleibt es beim alten Bild.
            if #available(macOS 26.0, *) { ToolbarSpacer(.fixed) }
            ToolbarItem {
                Button {
                    zeigeAufgaben.toggle()
                } label: {
                    Label("Aufgaben", systemImage: "checklist")
                }
                .help("Jahres-Aufgaben ein-/ausblenden")
            }
        }
        .inspector(isPresented: $zeigeAufgaben) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Aufgaben · \(String(jahr))")
                    .font(.headline).padding(.horizontal, 14).padding(.top, 14)
                AufgabenInspektorListe(
                    aufgaben: jahresAufgaben,
                    leererHinweis:
                        "Keine jährlichen Aufgaben für \(String(jahr)). Im Modul „Aufgaben“ anlegen (Wiederholung „jährlich“)."
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .inspektorGrund()
            .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
    }
}

extension JahresSeite where KopfRechts == EmptyView {
    init(titel: String, @ViewBuilder inhalt: @escaping (Jahreswerte) -> Inhalt) {
        self.init(titel: titel, kopfRechts: { EmptyView() }, inhalt: inhalt)
    }
}
