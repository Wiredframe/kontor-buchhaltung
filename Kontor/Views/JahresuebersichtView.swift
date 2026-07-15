import SwiftUI
import SwiftData
import AppKit
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

    // MARK: Pro Render einmal berechnete Jahreswerte

    /// Bündelt die teuren Jahres-Aggregate in einem Wert – einmal pro Render via `baueWerte()`
    /// gebaut, statt sie als computed properties bei jedem Zugriff im Body neu zu rechnen.
    private struct Jahreswerte {
        var a: JahresAuswertung
        /// USt-Zahllast je Voranmeldungs-Zeitraum des Jahres – je nach Rhythmus 12 Monate
        /// oder 4 Quartale (Label + Betrag). Folgt dem `ustvaRhythmus` des Jahres.
        var ustPerioden: [(label: String, betrag: Decimal)]
        var ustRhythmus: UStVARhythmus
        var estRuecklage: Decimal            // Σ ESt-Rücklage über 12 Monate (geschätzt)
        var ksk: (kv: Decimal, rv: Decimal, pv: Decimal)
        var zahlungen: [TaxPayment]          // des Jahres, nach Datum sortiert

        var ustJahr: Decimal { ustPerioden.reduce(Decimal(0)) { $0 + $1.betrag } }
        var kskGesamt: Decimal { ksk.kv + ksk.rv + ksk.pv }
        var steuerlast: Decimal { estRuecklage + ustJahr }
        var bezahltGesamt: Decimal { zahlungen.filter(\.bezahlt).reduce(Decimal(0)) { $0 + $1.betrag } }
        var estVzBezahlt: Decimal { zahlungen.filter { $0.kind == .estVz && $0.bezahlt }.reduce(Decimal(0)) { $0 + $1.betrag } }
        /// Nach Art gruppiert (nur nicht-leere Gruppen, stabile Reihenfolge).
        var gruppen: [(SteuerKind, [TaxPayment])] {
            SteuerKind.allCases.compactMap { kind in
                let p = zahlungen.filter { $0.kind == kind }
                return p.isEmpty ? nil : (kind, p)
            }
        }
    }

    /// Einstellungen **genau dieses Jahres** – kein Fallback (sonst zöge die KSK-Jahressumme
    /// die Beiträge eines fremden Jahres heran, wenn das gewählte Jahr keine `YearSettings` hat).
    private var settings: YearSettings? { jahre.first { $0.jahr == jahr } }

    /// Baut die Jahreswerte: Posten/KSK werden **einmal** gemappt, jede Aggregation läuft genau einmal.
    private func baueWerte() -> Jahreswerte {
        let einP = einnahmen.flatMap(\.postenListe)
        let ausP = ausgaben.map(\.posten)
        let est = Steuer.estRuecklageJahr(
            jahr: jahr, einnahmen: einP, ausgaben: ausP, kskFuer: { jahre.ksk(jahr: $0, monat: $1) },
            pauschalSatz: { jahre.estSatz(jahr: $0, monat: $1) })
        // USt-Zahllast je VA-Zeitraum – Rhythmus aus den Jahres-Einstellungen (monatlich = 12,
        // sonst 4 Quartale). Die Jahressumme ist in beiden Fällen identisch.
        let rhythmus = settings?.ustvaRhythmus ?? .vierteljaehrlich
        let ustP: [(String, Decimal)] = rhythmus == .monatlich
            ? (1...12).map { (kurzMonat($0), Steuer.ustva(einnahmen: einP, ausgaben: ausP, periode: Periode.monat(jahr, $0)).zahllast) }
            : (1...4).map { ("Q\($0)", Steuer.ustva(einnahmen: einP, ausgaben: ausP, periode: Periode.quartal(jahr, $0)).zahllast) }
        let jz = zahlungen.filter { $0.jahr == jahr }.sorted { $0.anzeigeDatum < $1.anzeigeDatum }
        return Jahreswerte(
            a: Steuer.jahresauswertung(jahr: jahr, einnahmen: einP, ausgaben: ausP),
            ustPerioden: ustP, ustRhythmus: rhythmus, estRuecklage: est, ksk: kskJahr, zahlungen: jz)
    }

    /// KSK des Jahres nach Versicherungszweig – Summe der je Monat gültigen Beitragssätze
    /// (bis zum laufenden Monat im aktuellen Jahr, sonst volles Jahr).
    private var kskJahr: (kv: Decimal, rv: Decimal, pv: Decimal) {
        let hJ = appKalender.component(.year, from: Date())
        let hM = appKalender.component(.month, from: Date())
        let bis = jahr < hJ ? 12 : (jahr == hJ ? hM : 0)
        guard bis >= 1, let s = settings else { return (0, 0, 0) }
        // Exakte Summe der je Monat hinterlegten KV/RV/PV-Beträge.
        var kv = Decimal(0), rv = Decimal(0), pv = Decimal(0)
        for m in 1...bis { let t = s.kskTeile(monat: m); kv += t.kv; rv += t.rv; pv += t.pv }
        return (kv, rv, pv)
    }
    var body: some View {
        @Bindable var zeit = zeit
        let w = baueWerte()
        return VStack(spacing: 0) {
            HStack {
                Text("Jahr").foregroundStyle(.secondary)
                JahrWaehler(jahr: $zeit.filter.jahr)
                HeuteButton(titel: "Aktuelles Jahr", deaktiviert: istAktuellesJahr) {
                    zeit.filter.jahr = appKalender.component(.year, from: Date())
                }
                Spacer()
                Button { belegeExportieren() } label: { Label("Belege \(String(jahr)) exportieren", systemImage: "doc.zipper") }
                    .disabled(belegAnzahl == 0)
                    .help(belegAnzahl == 0 ? "Keine Belege in \(String(jahr))." : "\(belegAnzahl) Belege als ZIP bündeln.")
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Von oben nach unten wie eine Steuererklärung: erst der Gewinn (EÜR, Zuflussprinzip), daraus ESt & USt (Schätzungen) – darunter, was tatsächlich gezahlt wurde. Vorlage für die Erklärung, keine finale Erklärung.")
                        .font(.subheadline).foregroundStyle(.secondary)

                    // Jahresergebnis auf einen Blick – eigener Teal→Smaragd-Hero (Monat = Blau→Violett).
                    AbschlussHero(
                        verlauf: Stil.jahresVerlauf,
                        links: .init(titel: "Gewinn (EÜR)", wert: w.a.gewinn,
                                     farbe: w.a.gewinn < 0 ? Stil.heroNegativ : .white),
                        rechts: .init(titel: "Steuerlast (ESt + USt, geschätzt)", wert: w.steuerlast,
                                      farbe: w.steuerlast < 0 ? Stil.heroNegativ : .white))

                    // 1) Gewinnermittlung (EÜR): Einnahmen − Betriebsausgaben (netto) = Gewinn.
                    Panel(titel: "Einnahmenüberschussrechnung (EÜR)",
                          aktion: { nav.zeigeAusgabenJahr(jahr: jahr, betrieblich: true, zeit: zeit) }) {
                        VStack(spacing: 2) {
                            Kartenzeile(label: "Betriebseinnahmen (Zufluss, netto)", wert: w.a.einnahmenBezahlt, icon: "eurosign.circle")
                            Divider().padding(.vertical, 4)
                            Kartenzeile(label: "Betriebsausgaben (netto)", wert: w.a.ausgabenNetto, icon: "creditcard", minus: true)
                            Summenzeile(label: "Gewinn (EÜR)", wert: w.a.gewinn, farbe: w.a.gewinn < 0 ? .red : Stil.gewinn)
                            Text("Einnahmen nach Zahlungseingang (Zufluss), betriebliche Ausgaben netto. Klick öffnet die betrieblichen Ausgaben des Jahres.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    // 2) Einkommensteuer: Gewinn − Vorsorge (KSK) → grobe Bemessungsgrundlage → pauschale Rücklage.
                    Panel(titel: "Einkommensteuer (Rücklage, geschätzt)") {
                        VStack(spacing: 2) {
                            Kartenzeile(label: "Gewinn (EÜR)", wert: w.a.gewinn, icon: "chart.line.uptrend.xyaxis")
                            Kartenzeile(label: "Vorsorgeaufwand (KSK, Sonderausgabe)", wert: w.kskGesamt, icon: "cross.case", minus: true)
                            Kartenzeile(label: "Steuerpflichtiger Gewinn (grob)", wert: w.a.gewinn - w.kskGesamt, icon: "function")
                            Summenzeile(label: "ESt-Rücklage (pauschal)", wert: w.estRuecklage, farbe: Stil.steuer)
                            Text("Pauschal je Monat (Gewinn − KSK) × Satz, hier über die Monate summiert. Satz wird im Monatsabschluss unter „Werte“ gepflegt.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    // 3) Vorsorgeaufwand-Detail: KSK nach Versicherungszweig.
                    Panel(titel: "Vorsorgeaufwand · KSK \(String(jahr)) nach Versicherung") {
                        let k = w.ksk
                        VStack(spacing: 2) {
                            Kartenzeile(label: "Krankenversicherung (KV)", wert: k.kv, icon: "cross.case")
                            Kartenzeile(label: "Rentenversicherung (RV)", wert: k.rv, icon: "building.columns")
                            Kartenzeile(label: "Pflegeversicherung (PV)", wert: k.pv, icon: "heart.text.square")
                            Summenzeile(label: "Summe KSK", wert: k.kv + k.rv + k.pv, farbe: Stil.ksk)
                            Text("Aus den je Monat hinterlegten Beitragssätzen (Soll); gepflegt im Monatsabschluss unter „Werte“.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    // 4) Umsatzsteuer: Zahllast je Voranmeldungs-Zeitraum + Jahressumme.
                    Panel(titel: "Umsatzsteuer-Zahllast je \(w.ustRhythmus == .monatlich ? "Monat" : "Quartal")") {
                        VStack(spacing: 10) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                                ForEach(w.ustPerioden, id: \.label) { p in Kennzahl(titel: p.label, wert: p.betrag) }
                            }
                            Summenzeile(label: "USt-Zahllast \(String(jahr))", wert: w.ustJahr, farbe: Stil.steuer)
                            Text("Soll-Versteuerung nach Rechnungsdatum (KZ 83 je Zeitraum); Detail siehe Modul „UStVA“.")
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // 5) Ergebnis: ESt + USt = geschätzte Steuerlast (wie das UStVA-„Ergebnis“).
                    Panel(titel: "Steuerlast gesamt (geschätzt)") {
                        VStack(spacing: 2) {
                            Kartenzeile(label: "ESt-Rücklage (geschätzt)", wert: w.estRuecklage, icon: "percent")
                            Kartenzeile(label: "USt-Zahllast", wert: w.ustJahr, icon: "building.columns")
                            Summenzeile(label: "Steuerlast (ESt + USt)", wert: w.steuerlast, farbe: Stil.steuer)
                        }
                    }

                    // — Übergang Soll → Ist: ab hier zählt, was tatsächlich aufs Konto/ans Finanzamt ging.
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()
                        Text("Tatsächlich geleistet")
                            .font(.title3.weight(.semibold))
                        Text("Abgleich der Schätzung mit den echten Abbuchungen – was wirklich an Steuern & Vorsorge gezahlt wurde.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)

                    Panel(titel: "ESt-Abgleich (Schätzung vs. geleistet)") {
                        let diff = w.estRuecklage - w.estVzBezahlt
                        VStack(spacing: 2) {
                            Kartenzeile(label: "ESt-Rücklage (geschätzt, pauschal)", wert: w.estRuecklage, icon: "percent")
                            Kartenzeile(label: "ESt-Vorauszahlungen geleistet", wert: w.estVzBezahlt, icon: "calendar")
                            Summenzeile(label: diff >= 0 ? "Noch zurückzulegen (über VZ hinaus)" : "VZ über Schätzung",
                                        wert: abs(diff), farbe: diff >= 0 ? .orange : .green)
                            Text("Die VZ sind Anzahlungen auf die ESt; mit dem Bescheid wird verrechnet (Nach- oder Rückzahlung).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Panel(titel: "Tatsächlich gezahlt · Steuern & Vorsorge \(String(jahr))") {
                        if w.zahlungen.isEmpty {
                            Text("Noch keine erfassten Zahlungen. Erfassung über den Kontoauszug-Import bzw. im Modul „Ausgaben“ (Bereich Vorsorge/Steuern).")
                                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(w.gruppen, id: \.0) { gruppe in
                                    let summe = gruppe.1.reduce(Decimal(0)) { $0 + $1.betrag }
                                    VStack(spacing: 2) {
                                        Text(gruppe.0.bezeichnung)
                                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        ForEach(gruppe.1) { t in ZahlungLeseZeile(eintrag: t) }
                                        Summenzeile(label: "Summe \(gruppe.0.bezeichnung)", wert: summe,
                                                    farbe: summe < 0 ? .green : Stil.steuer)
                                    }
                                }
                                Summenzeile(label: "Bezahlt gesamt", wert: w.bezahltGesamt, farbe: Stil.steuer)
                            }
                            Text("Read-only · Termine liegen in „Aufgaben“, Erfassung im Modul „Ausgaben“ (Vorsorge/Steuern) bzw. über den Kontoauszug.")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Jahresabschluss")
        .toolbar {
            ToolbarItem {
                Button { zeigeAufgaben.toggle() } label: { Label("Aufgaben", systemImage: "checklist") }
                    .help("Jahres-Aufgaben ein-/ausblenden")
            }
        }
        .inspector(isPresented: $zeigeAufgaben) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Aufgaben · \(String(jahr))")
                    .font(.headline).padding(.horizontal, 14).padding(.top, 14)
                AufgabenInspektorListe(aufgaben: jahresAufgaben,
                    leererHinweis: "Keine jährlichen Aufgaben für \(String(jahr)). Im Modul „Aufgaben“ anlegen (Wiederholung „jährlich“).")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        guard !belegPfade.isEmpty else { NSSound.beep(); return }
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
