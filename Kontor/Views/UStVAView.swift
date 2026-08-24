import SwiftData
import SwiftUI

struct UStVAView: View {
    @Query private var einnahmen: [Income]
    @Query private var ausgaben: [ExpenseEntry]
    @Query private var jahre: [YearSettings]
    @Query private var aufgaben: [MonthlyTask]
    @Environment(\.modelContext) private var context

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
        Steuer.ustva(
            einnahmen: einnahmen.flatMap(\.postenListe),
            ausgaben: ausgaben.map(\.posten),
            periode: periode)
    }
    /// Das Quartal, für das die ZM abzugeben ist – **auch in der Monatsansicht**.
    /// Meldezeitraum für sonstige Leistungen ist nach `§18a Abs. 2 UStG` das Kalendervierteljahr,
    /// unabhängig davon, in welchem Rhythmus die Voranmeldung läuft.
    private var zmQuartal: Int { monatlich ? (monat - 1) / 3 + 1 : quartal }
    private var zm: ZMMeldung {
        Steuer.zm(einnahmen.compactMap(\.zmPosten), in: .quartal(jahr, zmQuartal))
    }

    /// Titel der wiederkehrenden ZM-Aufgabe – zugleich der Schlüssel, über den erkannt wird,
    /// ob sie schon existiert (dieselbe Dedup-Regel wie `TaskVorlagen.nachAbschluss`).
    private static let zmAufgabenTitel = "Zusammenfassende Meldung (ZM) abgeben"
    private var zmAufgabeExistiert: Bool {
        aufgaben.contains { $0.titel == Self.zmAufgabenTitel && !$0.erledigt }
    }
    /// Legt die ZM als **quartalsweise** Aufgabe zum 25. an (Jan/Apr/Jul/Okt).
    ///
    /// Bewusst auf Knopfdruck statt im Seed: Wer keine EU-Kunden hat, braucht die Aufgabe nie,
    /// und eine Dauer-Aufgabe, die man immer wieder wegklickt, erzieht dazu, Aufgaben zu ignorieren.
    /// Der Knopf erscheint erst, wenn tatsächlich etwas zu melden ist.
    private func legeZMAufgabeAn() {
        let faellig =
            TaskVorlagen.naechsteFaelligkeit(
                intervall: .quartalsweise, faelligTag: 25, monate: [1, 4, 7, 10], ab: Date())
        context.insert(
            MonthlyTask(
                titel: Self.zmAufgabenTitel, monat: faellig,
                intervall: .quartalsweise, faelligTag: 25, quartalsMonate: [1, 4, 7, 10]))
        try? context.save()
    }

    private func hinweis(_ titel: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(titel).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(text).font(.caption).foregroundStyle(Stil.erklaerungFarbe)
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
                VStack(alignment: .leading, spacing: 24) {
                    Text(
                        "Die Kennzahlen (KZ) entsprechen den Feldern im ELSTER-Formular – Werte per Klick kopierbar."
                    )
                    .erklaerung()

                    Panel(titel: "Umsätze · geschuldete USt") {
                        VStack(spacing: 0) {
                            UStVAZeile(
                                kz: "81", label: "Steuerpflichtige Umsätze 19 % (netto)",
                                erklaerung:
                                    "Summe deiner Netto-Honorare mit 19 % USt – nach Rechnungsdatum (Soll-Versteuerung).",
                                wert: e.kz81)
                            UStVAZeile(
                                kz: nil, label: "darauf USt 19 %",
                                erklaerung: "Berechnet ELSTER automatisch aus KZ 81 – hier zur Kontrolle.",
                                wert: e.ust81, unterzeile: true)
                            UStVAZeile(
                                kz: "86", label: "Steuerpflichtige Umsätze 7 % (netto)",
                                erklaerung:
                                    "Netto-Honorare mit ermäßigten 7 % USt (z. B. Einräumung von Nutzungsrechten) – nach Rechnungsdatum (Soll).",
                                wert: e.kz86)
                            UStVAZeile(
                                kz: nil, label: "darauf USt 7 %",
                                erklaerung: "Berechnet ELSTER automatisch aus KZ 86 – hier zur Kontrolle.",
                                wert: e.ust86, unterzeile: true)
                            // Nur zeigen, wenn belegt: Zwei Dauer-Nullzeilen wären für den
                            // Regelfall (reines Inlandsgeschäft) bloß Ballast.
                            if e.kz21 != 0 {
                                UStVAZeile(
                                    kz: "21", label: "Sonstige Leistungen EU-Unternehmer (netto)",
                                    erklaerung:
                                        "Leistungen an Unternehmer im EU-Ausland: Leistungsort ist beim Kunden (§3a Abs. 2 UStG), "
                                        + "**er** schuldet die USt. In Deutschland nicht steuerbar – der Betrag wird nur gemeldet, "
                                        + "nicht besteuert. **Zusätzlich fällig: die Zusammenfassende Meldung** (unten).",
                                    wert: e.kz21)
                            }
                            if e.kz45 != 0 {
                                UStVAZeile(
                                    kz: "45", label: "Übrige nicht steuerbare Umsätze (netto)",
                                    erklaerung:
                                        "Leistungsort im Drittland (außerhalb der EU). Ebenfalls nur Meldung, keine deutsche USt – "
                                        + "und **keine** Zusammenfassende Meldung.",
                                    wert: e.kz45)
                            }
                            UStVAZeile(
                                kz: "84", label: "§13b Reverse-Charge (netto)",
                                erklaerung:
                                    "Netto aus Auslands-Leistungen (z. B. Figma, Adobe), für die du die USt selbst schuldest.",
                                wert: e.kz84)
                            UStVAZeile(
                                kz: "85", label: "§13b – USt 19 %",
                                erklaerung:
                                    "USt auf KZ 84 – schuldest du, ziehst sie aber unten (KZ 67) wieder ab → Saldo 0.",
                                wert: e.kz85)
                            if e.korrektur17 != 0 {
                                UStVAZeile(
                                    kz: nil, label: "davon §17-Korrektur (Forderungsausfall)",
                                    erklaerung:
                                        "Nur zur Erläuterung – **nichts extra einzutragen**. Das Formular hat kein §17-Feld: "
                                        + "Die ausgefallenen Rechnungen sind oben bereits von KZ 81/86 abgezogen, ELSTER rechnet die "
                                        + "Erstattung daraus selbst aus.",
                                    wert: e.korrektur17)
                            }
                        }
                    }

                    Panel(titel: "Vorsteuer · abziehbar") {
                        VStack(spacing: 0) {
                            UStVAZeile(
                                kz: "66", label: "Vorsteuer Inland",
                                erklaerung: "USt aus Eingangsrechnungen deutscher Lieferanten (betriebliche Ausgaben).",
                                wert: e.kz66)
                            UStVAZeile(
                                kz: "67", label: "Vorsteuer aus §13b-Leistungen",
                                erklaerung: "= KZ 85. Macht Reverse-Charge unterm Strich neutral.",
                                wert: e.kz67)
                        }
                    }

                    Panel(titel: "Ergebnis") {
                        VStack(alignment: .leading, spacing: 8) {
                            Summenzeile(
                                label: "KZ 83 · USt-Vorauszahlung", wert: e.zahllast, akzent: true)
                            Text(
                                e.zahllast >= 0
                                    ? "Betrag, den du ans Finanzamt überweist."
                                    : "Erstattungsbetrag (Vorsteuer-Überhang) vom Finanzamt."
                            )
                            .erklaerung()
                        }
                    }

                    if !zm.istLeer {
                        Panel(titel: "Zusammenfassende Meldung · Q\(zmQuartal) \(jahr)") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(
                                    "Eigene Meldung ans BZSt, **zusätzlich** zur Voranmeldung – je USt-IdNr. eine Zeile. "
                                        + "Abgabe bis zum **25. nach Quartalsende**; eine Dauerfristverlängerung gilt dafür "
                                        + "**nicht**."
                                )
                                .erklaerung()
                                if monatlich {
                                    Text(
                                        "Auch bei monatlicher Voranmeldung wird quartalsweise gemeldet (§18a Abs. 2 UStG) – "
                                            + "deshalb steht hier das ganze Quartal."
                                    )
                                    .erklaerung()
                                }
                                ForEach(zm.zeilen) { z in
                                    // UID zuerst: Sie ist das, was ins Formular getippt wird.
                                    // Der Kundenname steht nur zur Sichtkontrolle daneben.
                                    Kartenzeile(
                                        label: z.ustIdNr + " · " + z.kunden.joined(separator: ", "),
                                        wert: z.netto)
                                }
                                Summenzeile(label: "Summe (= KZ 21)", wert: zm.summe)
                                if !zmAufgabeExistiert {
                                    Button {
                                        legeZMAufgabeAn()
                                    } label: {
                                        Label("Als Quartalsaufgabe anlegen (25.)", systemImage: "plus.circle")
                                    }
                                    .buttonStyle(.borderless).font(.caption)
                                }
                                if !zm.istVollstaendig {
                                    Label(
                                        "Ohne USt-IdNr. und daher nicht meldbar: "
                                            + zm.ohneUstIdNr.joined(separator: ", ")
                                            + ". Ohne gültige USt-IdNr. trägt der Übergang der Steuerschuld nicht – "
                                            + "die Rechnung wäre dann im Inland steuerpflichtig.",
                                        systemImage: "exclamationmark.triangle"
                                    )
                                    .font(.caption).foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    Panel(titel: "Hinweise zum Ausfüllen") {
                        VStack(alignment: .leading, spacing: 12) {
                            hinweis(
                                "Soll-Versteuerung", "Maßgeblich ist das Rechnungsdatum, nicht der Zahlungseingang.")
                            hinweis(
                                "Reverse-Charge (§13b)",
                                "Bei Auslands-Tools schuldest du die USt selbst (KZ 84/85) und ziehst sie zugleich als Vorsteuer ab (KZ 67) – Saldo 0. Der Netto-Betrag bleibt trotzdem Betriebsausgabe in der EÜR."
                            )
                            hinweis(
                                "Steuersätze",
                                "Ausgangsseitig 19 % (Regelsatz) oder 7 % (ermäßigt, z. B. Einräumung von Nutzungsrechten) – kein steuerfreier Ausgang (außer USt = 0). Mischrechnungen mit beiden Sätzen sind möglich (zweiter Satz je Rechnung)."
                            )
                            hinweis(
                                "Vorsteuer",
                                "Steuerfreie und Reverse-Charge-Eingangsrechnungen haben keine abziehbare Vorsteuer → tauchen nicht in KZ 66 auf."
                            )
                            hinweis(
                                "Kunden im EU-Ausland",
                                "Bei Unternehmern mit gültiger USt-IdNr. geht die Steuerschuld auf den Kunden über: Rechnung ohne USt, mit beiden USt-IdNr. und dem Hinweis „Steuerschuldnerschaft des Leistungsempfängers“. Der Umsatz läuft in KZ 21 **und** in die Zusammenfassende Meldung. Bei Privatkunden gilt das nicht – dort ist der Leistungsort Deutschland und du berechnest ganz normal 19 %."
                            )
                        }
                    }
                }
                .padding()
            }
            .seitenGrund()
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
                Text(erklaerung).font(.caption).foregroundStyle(Stil.erklaerungFarbe)
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
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { kopiereMitHaken(wert, $kopiert) }
        .help("Klicken, um den Wert zu kopieren")
        .contextMenu { Button("Wert kopieren") { kopiereMitHaken(wert, $kopiert) } }
    }
}
