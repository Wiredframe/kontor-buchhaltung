import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Jahresabschluss: EÜR (Gewinn) + Jahres-Steuerbild (ESt-Schätzung, USt-Zahllast),
/// KSK des Jahres aufgeteilt nach KV/RV/PV, ESt-Abgleich und die Steuer-Zahlungen/Termine.
/// Vereint die frühere „Jahresübersicht (EÜR)" und „Steuern & Abgaben".
struct JahresuebersichtView: View {
    @Query private var einnahmen: [Income]
    @Query private var ausgaben: [ExpenseEntry]
    @Query private var zahlungen: [TaxPayment]
    @Query private var jahre: [YearSettings]
    @Query private var tasks: [MonthlyTask]

    @Environment(\.modelContext) private var context
    @Environment(Zeitkontext.self) private var zeit
    @Environment(Navigation.self) private var nav
    @State private var zeigeAufgaben = true
    private var jahr: Int { zeit.filter.jahr }
    private var istAktuellesJahr: Bool { jahr == appKalender.component(.year, from: Date()) }
    /// Nur jährliche Aufgaben des gewählten Jahres – für die Abschluss-Sidebar.
    private var jahresAufgaben: [MonthlyTask] {
        tasks.filter { $0.intervall == .jaehrlich && appKalender.component(.year, from: $0.monat) == jahr }
            .sorted { $0.monat < $1.monat }
    }

    /// Einstellungen **genau dieses Jahres** – kein Fallback (sonst zöge die KSK-Jahressumme
    /// die Beiträge eines fremden Jahres heran, wenn das gewählte Jahr keine `YearSettings` hat).
    private var settings: YearSettings? { jahre.first { $0.jahr == jahr } }

    /// Themen-Überschrift über einem Soll/Ist-Paar.
    private func themaHeader(_ titel: String) -> some View {
        Text(titel).font(.title2).fontWeight(.semibold).padding(.horizontal, 4).padding(.top, 4)
    }

    // MARK: Soll/Ist-Spalten je Thema

    @ViewBuilder private func estSoll(_ w: Jahreswerte) -> some View {
        VStack(spacing: 2) {
            Kartenzeile(label: "Gewinn (EÜR)", wert: w.a.gewinn, icon: "chart.line.uptrend.xyaxis")
            Kartenzeile(
                label: "Vorsorgeaufwand (KSK, Sonderausgabe)", wert: w.kskGesamt, icon: "cross.case", minus: true)
            Kartenzeile(
                label: "Steuerpflichtiger Gewinn (grob)", wert: w.a.gewinn - w.kskGesamt, icon: "function")
            Summenzeile(label: "ESt-Rücklage (pauschal)", wert: w.estRuecklage)
            Text(
                "Pauschal je Monat (Gewinn − KSK) × Satz, über die Monate summiert. Satz im Monatsabschluss unter „Werte“."
            )
            .erklaerung()
            Divider().padding(.vertical, 6)
            Text("Genauere Orientierung (mit Grundfreibetrag)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Kartenzeile(
                label: "Grundfreibetrag (Grundtarif \(String(jahr)))", wert: w.grundfreibetrag,
                icon: "person.crop.circle", minus: true)
            Kartenzeile(label: "Voraussichtliche ESt", wert: w.estVoraussichtlich, icon: "percent")
            Kartenzeile(
                label: "Puffer ggü. Rücklage", wert: w.estRuecklage - w.estVoraussichtlich,
                icon: "arrow.down.right.circle")
            Text(
                "Jahresbasiert (Gewinn − KSK − Grundfreibetrag) × Satz, ohne Hochrechnen.\(istAktuellesJahr ? " Laufendes Jahr: Stand jetzt." : "") Grobe Orientierung, keine Steuererklärung; Grundfreibetrag in den Einstellungen je Jahr anpassbar."
            )
            .erklaerung()
        }
    }

    @ViewBuilder private func estIst(_ w: Jahreswerte) -> some View {
        let diff = w.estRuecklage - w.estVzBezahlt
        VStack(spacing: 2) {
            if w.estGezahlt.isEmpty {
                Text("Noch keine ESt-Vorauszahlung erfasst.").erklaerung()
            } else {
                ForEach(w.estGezahlt) { ZahlungLeseZeile(eintrag: $0) }
            }
            Summenzeile(
                label: diff >= 0 ? "Noch zurückzulegen (über VZ hinaus)" : "VZ über Schätzung", wert: abs(diff))
            Text("Die VZ sind Anzahlungen auf die ESt; mit dem Bescheid wird verrechnet (Nach- oder Rückzahlung).")
                .erklaerung()
        }
    }

    @ViewBuilder private func ustSoll(_ w: Jahreswerte) -> some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(w.ustPerioden, id: \.label) { p in Kennzahl(titel: p.label, wert: p.betrag, akzent: true) }
            }
            Summenzeile(label: "USt-Zahllast \(String(jahr))", wert: w.ustJahr)
            Text("Soll-Versteuerung nach Rechnungsdatum (KZ 83 je Zeitraum); Detail siehe Modul „UStVA“.")
                .erklaerung()
        }
    }

    @ViewBuilder private func ustIst(_ w: Jahreswerte) -> some View {
        VStack(spacing: 2) {
            if w.ustGezahlt.isEmpty {
                Text("Noch keine USt-Zahlung erfasst (Kontoauszug-Import bzw. Modul „Ausgaben“).").erklaerung()
            } else {
                ForEach(w.ustGezahlt) { ZahlungLeseZeile(eintrag: $0) }
                Summenzeile(label: "Gezahlt gesamt", wert: w.ustGezahlt.reduce(Decimal(0)) { $0 + $1.betrag })
            }
        }
    }

    @ViewBuilder private func kskSoll(_ w: Jahreswerte) -> some View {
        VStack(spacing: 2) {
            Kartenzeile(label: "Krankenversicherung (KV)", wert: w.ksk.kv, icon: "cross.case")
            Kartenzeile(label: "Rentenversicherung (RV)", wert: w.ksk.rv, icon: "building.columns")
            Kartenzeile(label: "Pflegeversicherung (PV)", wert: w.ksk.pv, icon: "heart.text.square")
            Summenzeile(label: "Summe KSK (Soll)", wert: w.kskGesamt)
            Text("Aus den je Monat hinterlegten Beitragssätzen (Soll); gepflegt im Monatsabschluss unter „Werte“.")
                .erklaerung()
        }
    }

    @ViewBuilder private func kskIst(_ w: Jahreswerte) -> some View {
        VStack(spacing: 2) {
            if w.kskGezahlt.isEmpty {
                Text("Noch keine KSK-Abbuchung erfasst (Kontoauszug-Import).").erklaerung()
            } else {
                ForEach(w.kskGezahlt) { ZahlungLeseZeile(eintrag: $0) }
                Summenzeile(label: "Gezahlt gesamt", wert: w.kskGezahlt.reduce(Decimal(0)) { $0 + $1.betrag })
            }
        }
    }

    /// Ein Thema als Soll/Ist-Paar untereinander (oben Schätzung, darunter tatsächlich gezahlt) –
    /// bewusst nicht zweispaltig, weil die Zeilenzahl je Seite stark unterschiedlich sein kann.
    private func themaPaar<S: View, I: View>(_ titel: String, soll: S, ist: I) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            themaHeader(titel)
            Panel(titel: "Schätzung") { soll }
            Panel(titel: "Tatsächlich gezahlt") { ist }
        }
    }

    var body: some View {
        @Bindable var zeit = zeit
        let w = Jahreswerte.bauen(
            jahr: jahr, einnahmen: einnahmen, ausgaben: ausgaben, zahlungen: zahlungen, jahre: jahre)
        return VStack(spacing: 0) {
            HStack {
                Text("Jahr").foregroundStyle(.secondary)
                JahrWaehler(jahr: $zeit.filter.jahr)
                HeuteButton(titel: "Aktuelles Jahr", deaktiviert: istAktuellesJahr) {
                    zeit.filter.jahr = appKalender.component(.year, from: Date())
                }
                Spacer()
                Button {
                    belegeExportieren()
                } label: {
                    Label("Belege \(String(jahr)) exportieren", systemImage: "doc.zipper")
                }
                .disabled(belegAnzahl == 0)
                .help(belegAnzahl == 0 ? "Keine Belege in \(String(jahr))." : "\(belegAnzahl) Belege als ZIP bündeln.")
            }
            .padding()
            Divider()
            // Ohne YearSettings rechnen ESt und KSK still mit Fallbacks weiter (15 % / 0 €) –
            // plausibel aussehende, falsche Zahlen. Das gehört sichtbar gemacht, nicht versteckt.
            FehlendeJahresEinstellungen(jahr: jahr, settings: settings) {
                context.insert(YearSettings(jahr: jahr, estPauschalSatz: dez("0.15")))
                try? context.save()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Kernzahlen auf einen Blick – vier Werte im Hero, Detail in den Blöcken darunter.
                    AbschlussHero([
                        .init(titel: "Gewinn (EÜR)", wert: w.a.gewinn),
                        .init(titel: "ESt-Rücklage", wert: w.estRuecklage),
                        .init(titel: "USt-Zahllast", wert: w.ustJahr),
                        .init(titel: "KSK (Vorsorge)", wert: w.kskGesamt),
                    ])

                    Text(
                        "Von oben nach unten wie eine Steuererklärung: erst der Gewinn (EÜR, Zuflussprinzip), daraus ESt & USt (Schätzungen) – je Thema **oben die Schätzung, darunter das tatsächlich Gezahlte**. Vorlage für die Erklärung, keine finale Erklärung."
                    )
                    .erklaerung()

                    // 1) Gewinnermittlung (EÜR): Einnahmen − Betriebsausgaben (netto) = Gewinn.
                    Panel(
                        titel: "Einnahmenüberschussrechnung (EÜR)",
                        aktion: { nav.zeigeAusgabenJahr(jahr: jahr, betrieblich: true, zeit: zeit) }
                    ) {
                        VStack(spacing: 2) {
                            Kartenzeile(
                                label: "Betriebseinnahmen (Zufluss, netto)", wert: w.a.einnahmenBezahlt,
                                icon: "eurosign.circle")
                            Kartenzeile(
                                label: "Betriebsausgaben (netto)", wert: w.a.ausgabenNetto, icon: "creditcard",
                                minus: true)
                            Summenzeile(label: "Gewinn (EÜR)", wert: w.a.gewinn)
                            Text(
                                "Einnahmen nach Zahlungseingang (Zufluss), betriebliche Ausgaben netto. Klick öffnet die betrieblichen Ausgaben des Jahres."
                            )
                            .erklaerung()
                        }
                    }

                    // Pro Steuerthema ein Soll/Ist-Paar nebeneinander – so bleibt jedes Thema als
                    // Block zusammen und Schätzung vs. gezahlt ist direkt vergleichbar.
                    themaPaar("Einkommensteuer", soll: estSoll(w), ist: estIst(w))
                    themaPaar("Umsatzsteuer", soll: ustSoll(w), ist: ustIst(w))
                    themaPaar("Vorsorge · KSK \(String(jahr))", soll: kskSoll(w), ist: kskIst(w))

                    if !w.sonstigeGezahlt.isEmpty {
                        Panel(titel: "Sonstige Steuerzahlungen \(String(jahr))") {
                            VStack(spacing: 2) {
                                ForEach(w.sonstigeGezahlt) { ZahlungLeseZeile(eintrag: $0) }
                                Summenzeile(
                                    label: "Summe sonstige",
                                    wert: w.sonstigeGezahlt.reduce(Decimal(0)) { $0 + $1.betrag })
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .seitenGrund()
        .navigationTitle("Jahresabschluss")
        .toolbar {
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

    // MARK: Belege-Export

    /// Alle Belege des Jahres: **Ausgangsrechnungen** (Einnahmen, nach Rechnungsdatum – so werden
    /// sie auch abgelegt) **und** Eingangsbelege (Ausgaben, nach Abflussdatum).
    ///
    /// Die Einnahmen fehlten hier komplett – dabei sind die Ausgangsrechnungen bei einer
    /// Betriebsprüfung das zentrale Dokument. Wer nur Einnahmen-PDFs erfasst hatte, bekam einen
    /// leeren Export samt ausgegrautem Button („Keine Belege in 2026") und keinen Hinweis darauf,
    /// dass seine Rechnungen einfach nicht mitgesammelt werden.
    /// (`PurchaseEntry` bleibt bewusst draußen: private Einkäufe gehen das Finanzamt nichts an.)
    private var belegPfade: [String] {
        let p = Periode.jahr(jahr)
        let ausEinnahmen = einnahmen.filter { p.enthaelt($0.rechnungsdatum) }.compactMap { $0.belegPfad }
        let ausAusgaben = ausgaben.filter { p.enthaelt($0.datum) }.compactMap { $0.belegPfad }
        // Ein Beleg kann an mehreren Einträgen hängen – im ZIP soll er einmal landen.
        var gesehen = Set<String>()
        return (ausEinnahmen + ausAusgaben).filter { gesehen.insert($0).inserted && Belege.existiert($0) }
    }
    private var belegAnzahl: Int { belegPfade.count }
    private func belegeExportieren() {
        guard !belegPfade.isEmpty else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Belege-\(jahr).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let ziel = panel.url else { return }
        try? Belege.exportiereAlsZip(pfade: belegPfade, nach: ziel)
    }
}

// MARK: - Steuer-Zahlung (read-only Lesezeile)

/// Eine Zeile der read-only Jahres-Zahlungsübersicht: Status, Datum, optional Notiz, Betrag.
/// Negative Beträge (Erstattungen) bleiben neutral – kein Rot; das Minuszeichen zeigt die
/// Erstattung. Erfasst/bearbeitet wird im Modul „Ausgaben“ (Vorsorge/Steuern).
private struct ZahlungLeseZeile: View {
    let eintrag: TaxPayment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: eintrag.bezahlt ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(eintrag.bezahlt ? Color.green : .secondary)
            Text(eintrag.anzeigeDatum, format: .dateTime.day().month().year())
            if !eintrag.bemerkung.isEmpty {
                Text(eintrag.bemerkung).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(eintrag.betrag.euro).monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
    }
}
