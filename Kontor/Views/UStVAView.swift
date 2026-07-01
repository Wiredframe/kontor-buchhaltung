import SwiftUI
import SwiftData

struct UStVAView: View {
    @Query private var einnahmen: [Income]
    @Query private var ausgaben: [ExpenseEntry]
    @Query private var jahre: [YearSettings]

    @Environment(Zeitkontext.self) private var zeit
    private var jahr: Int { zeit.filter.jahr }
    private var monat: Int { zeit.filter.monat }
    private var settings: YearSettings? { jahre.first { $0.jahr == jahr } }
    @State private var quartal = (appKalender.component(.month, from: Date()) - 1) / 3 + 1
    @State private var monatlich = false

    private var periode: Periode {
        monatlich ? Periode.monat(jahr, monat) : Periode.quartal(jahr, quartal)
    }
    private var istAktuell: Bool {
        let j = appKalender.component(.year, from: Date())
        let m = appKalender.component(.month, from: Date())
        guard jahr == j else { return false }
        return monatlich ? monat == m : quartal == (m - 1) / 3 + 1
    }
    private func aufHeute() {
        zeit.filter.jahr = appKalender.component(.year, from: Date())
        zeit.filter.monat = appKalender.component(.month, from: Date())
        quartal = (monat - 1) / 3 + 1
    }
    private var e: UStVAErgebnis {
        Steuer.ustva(einnahmen: einnahmen.flatMap(\.postenListe),
                     ausgaben: ausgaben.map(\.posten),
                     periode: periode)
    }

    private func hinweis(_ titel: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(titel).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(text).font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        @Bindable var zeit = zeit
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Rhythmus", selection: $monatlich) {
                    Text("Quartal").tag(false)
                    Text("Monat").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170)

                if monatlich {
                    Picker("Monat", selection: $zeit.filter.monat) {
                        ForEach(1...12, id: \.self) { Text(monatsName($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: 140)
                } else {
                    Picker("Quartal", selection: $quartal) {
                        ForEach(1...4, id: \.self) { Text("Q\($0)").tag($0) }
                    }
                    .labelsHidden().frame(width: 90)
                }
                JahrWaehler(jahr: $zeit.filter.jahr)
                HeuteButton(deaktiviert: istAktuell) { aufHeute() }
                Spacer()
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Die Kennzahlen (KZ) entsprechen den Feldern im ELSTER-Formular – Werte per Klick kopierbar.")
                        .font(.subheadline).foregroundStyle(.secondary)

                    Panel(titel: "Umsätze · geschuldete USt") {
                        VStack(spacing: 0) {
                            UStVAZeile(kz: "81", label: "Steuerpflichtige Umsätze 19 % (netto)",
                                       erklaerung: "Summe deiner Netto-Honorare mit 19 % USt – nach Rechnungsdatum (Soll-Versteuerung).",
                                       wert: e.kz81)
                            Divider()
                            UStVAZeile(kz: nil, label: "darauf USt 19 %",
                                       erklaerung: "Berechnet ELSTER automatisch aus KZ 81 – hier zur Kontrolle.",
                                       wert: e.ust81, unterzeile: true)
                            Divider()
                            UStVAZeile(kz: "84", label: "§13b Reverse-Charge (netto)",
                                       erklaerung: "Netto aus Auslands-Leistungen (z. B. Figma, Adobe), für die du die USt selbst schuldest.",
                                       wert: e.kz84)
                            Divider()
                            UStVAZeile(kz: "85", label: "§13b – USt 19 %",
                                       erklaerung: "USt auf KZ 84 – schuldest du, ziehst sie aber unten (KZ 67) wieder ab → Saldo 0.",
                                       wert: e.kz85)
                            if e.korrektur17 != 0 {
                                Divider()
                                UStVAZeile(kz: nil, label: "§17-Korrektur (Forderungsausfall)",
                                           erklaerung: "USt aus ausgefallenen Rechnungen dieses Zeitraums – mindert die Zahllast.",
                                           wert: e.korrektur17)
                            }
                        }
                    }

                    Panel(titel: "Vorsteuer · abziehbar") {
                        VStack(spacing: 0) {
                            UStVAZeile(kz: "66", label: "Vorsteuer Inland",
                                       erklaerung: "USt aus Eingangsrechnungen deutscher Lieferanten (betriebliche Ausgaben).",
                                       wert: e.kz66)
                            Divider()
                            UStVAZeile(kz: "67", label: "Vorsteuer aus §13b-Leistungen",
                                       erklaerung: "= KZ 85. Macht Reverse-Charge unterm Strich neutral.",
                                       wert: e.kz67)
                        }
                    }

                    Panel(titel: "Ergebnis") {
                        Summenzeile(label: "KZ 83 · USt-Vorauszahlung", wert: e.zahllast,
                                    farbe: e.zahllast >= 0 ? Stil.steuer : .green)
                        Text(e.zahllast >= 0 ? "Betrag, den du ans Finanzamt überweist." : "Erstattungsbetrag (Vorsteuer-Überhang) vom Finanzamt.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }

                    Panel(titel: "Hinweise zum Ausfüllen") {
                        VStack(alignment: .leading, spacing: 8) {
                            hinweis("Soll-Versteuerung", "Maßgeblich ist das Rechnungsdatum, nicht der Zahlungseingang.")
                            hinweis("Reverse-Charge (§13b)", "Bei Auslands-Tools schuldest du die USt selbst (KZ 84/85) und ziehst sie zugleich als Vorsteuer ab (KZ 67) – Saldo 0. Der Netto-Betrag bleibt trotzdem Betriebsausgabe in der EÜR.")
                            hinweis("Steuerfrei", "Steuerfreie und Reverse-Charge-Eingangsrechnungen haben keine abziehbare Vorsteuer → tauchen nicht in KZ 66 auf. Ausgangsseitig gelten aktuell alle Honorare als 19 % steuerpflichtig.")
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("UStVA")
        .onChange(of: jahr, initial: true) { _, _ in
            // Default-Rhythmus aus den Jahres-Einstellungen übernehmen (manuell weiter umschaltbar).
            monatlich = (settings?.ustvaRhythmus == .monatlich)
        }
    }
}

/// Eine UStVA-Zeile: KZ-Badge, Klartext-Label, Erklärung und Betrag (Klick kopiert).
/// `unterzeile` = eingerückte Info-Zeile (z. B. die automatisch berechnete USt).
private struct UStVAZeile: View {
    let kz: String?
    let label: String
    let erklaerung: String
    let wert: Decimal
    var unterzeile = false
    @State private var kopiert = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let kz {
                    Text("KZ \(kz)")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 52, height: 24)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                } else {
                    Color.clear.frame(width: 52, height: 1)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(unterzeile ? .subheadline : .body.weight(.medium))
                    .foregroundStyle(unterzeile ? .secondary : .primary)
                Text(erklaerung).font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                KopierHaken(sichtbar: kopiert)
                Text(wert.euro)
                    .font(.body.weight(unterzeile ? .regular : .medium)).monospacedDigit()
                    .foregroundStyle(unterzeile ? .secondary : .primary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { kopiereMitHaken(wert, $kopiert) }
        .help("Klicken, um den Wert zu kopieren")
        .contextMenu { Button("Wert kopieren") { kopiereMitHaken(wert, $kopiert) } }
    }
}
