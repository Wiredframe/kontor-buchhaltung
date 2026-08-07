import SwiftData
import SwiftUI

/// Jahresabschluss → Einkommensteuer: die beiden Berechnungen (pauschale Rücklage, jahresbasierte
/// ESt mit Grundfreibetrag), die geleisteten Vorauszahlungen und – sobald erfasst – der Abgleich
/// gegen die **festgesetzte** ESt aus dem Steuerbescheid.
struct JahresEinkommensteuerView: View {
    @Environment(Zeitkontext.self) private var zeit
    @Environment(Navigation.self) private var nav

    var body: some View {
        JahresSeite(titel: "Einkommensteuer") { w in
            ThemaPaar(
                // Gerechnet wird auf dem EÜR-Gewinn – der steht im Nachbarbereich.
                sollAktion: { nav.modul = .jahresEUR },
                // Vorauszahlungen und Bescheid-Zahlungen liegen als Steuer-Zeilen im Ledger.
                istAktion: { nav.zeigeAusgabenJahr(jahr: w.jahr, art: .steuern, zeit: zeit) },
                soll: { ESTSollBlock(w: w) }, ist: { ESTIstBlock(w: w) })
            BescheidPanel(w: w)
            SonstigeZahlungenPanel(w: w)
        }
    }
}

// MARK: - Berechnung

private struct ESTSollBlock: View {
    let w: Jahreswerte

    var body: some View {
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
                label: "Grundfreibetrag (Grundtarif \(String(w.jahr)))", wert: w.grundfreibetrag,
                icon: "person.crop.circle", minus: true)
            Kartenzeile(label: "Voraussichtliche ESt", wert: w.estVoraussichtlich, icon: "percent")
            Kartenzeile(
                label: "Puffer ggü. Rücklage", wert: w.estRuecklage - w.estVoraussichtlich,
                icon: "arrow.down.right.circle")
            Text(
                "Jahresbasiert (Gewinn − KSK − Grundfreibetrag) × Satz, ohne Hochrechnen.\(w.istAktuellesJahr ? " Laufendes Jahr: Stand jetzt." : "") Grobe Orientierung, keine Steuererklärung; Grundfreibetrag in den Einstellungen je Jahr anpassbar."
            )
            .erklaerung()
        }
    }
}

// MARK: - Tatsächlich gezahlt

private struct ESTIstBlock: View {
    let w: Jahreswerte

    var body: some View {
        let diff = w.estRuecklage - w.estVzBezahlt
        VStack(spacing: 2) {
            if w.estGezahlt.isEmpty {
                Text("Noch keine ESt-Vorauszahlung erfasst.").erklaerung()
            } else {
                ForEach(w.estGezahlt) { ZahlungLeseZeile(eintrag: $0) }
            }
            Summenzeile(
                label: diff >= 0 ? "Noch zurückzulegen (über VZ hinaus)" : "VZ über Berechnung", wert: abs(diff))
            Text("Die VZ sind Anzahlungen auf die ESt; mit dem Bescheid wird verrechnet (Nach- oder Rückzahlung).")
                .erklaerung()
        }
    }
}

// MARK: - Steuerbescheid

/// Erfassung der **festgesetzten** ESt und der Abgleich gegen Berechnungen und Zahlungen.
///
/// Bewusst hier und nicht in den Einstellungen: `grundfreibetrag` dort ist ein *Parameter* der
/// Berechnung (ein Stammdatum wie Rhythmus oder Satz), die Bescheid-ESt dagegen ein
/// *Jahresergebnis* – man hat den Bescheid in der Hand, wenn man den Jahresabschluss aufmacht,
/// und will sofort Abweichung und offenen Betrag sehen.
private struct BescheidPanel: View {
    let w: Jahreswerte
    @Query private var jahre: [YearSettings]
    @Environment(\.modelContext) private var context

    private var settings: YearSettings? { jahre.first { $0.jahr == w.jahr } }

    private var bindung: Binding<Decimal?> {
        Binding(
            get: { settings?.estLautBescheid },
            set: {
                settings?.estLautBescheid = $0
                try? context.save()
            })
    }

    var body: some View {
        Panel(titel: "Steuerbescheid \(String(w.jahr))") {
            VStack(spacing: 2) {
                // Label links, Eingabe rechts – dieselbe Zeilenrhythmik wie die `Kartenzeile`n
                // darunter, deren Werte ebenfalls rechts stehen. Feste Feldbreite, damit die
                // Eingabe nicht über die halbe Karte läuft.
                HStack(spacing: 12) {
                    Text("ESt laut Bescheid")
                    Spacer(minLength: 12)
                    GeldFeldOptional("ESt laut Bescheid", wert: bindung, platzhalter: "z. B. 4.200,00")
                        .labelsHidden()
                        .frame(width: 170)
                        .disabled(settings == nil)
                }
                .padding(.vertical, 7)

                if let festgesetzt = w.estLautBescheid {
                    let a = Steuer.ESTBescheidAbgleich(
                        festgesetzt: festgesetzt, ruecklage: w.estRuecklage,
                        voraussichtlich: w.estVoraussichtlich, vzBezahlt: w.estVzBezahlt,
                        bescheidBezahlt: w.estBescheidBezahlt)
                    Divider().padding(.vertical, 6)
                    Kartenzeile(
                        label: "ggü. ESt-Rücklage (pauschal)", wert: a.abweichungRuecklage,
                        icon: "arrow.left.arrow.right", signiert: true)
                    Kartenzeile(
                        label: "ggü. Voraussichtlicher ESt", wert: a.abweichungVoraussichtlich,
                        icon: "percent", signiert: true)
                    Kartenzeile(label: "Bereits gezahlte VZ", wert: a.vzBezahlt, icon: "calendar")
                    if a.bescheidBezahlt != 0 {
                        Kartenzeile(
                            label: "Zahlungen nach Bescheid", wert: a.bescheidBezahlt,
                            icon: "checkmark.circle", minus: true)
                    }
                    Summenzeile(
                        label: a.nochZuZahlen >= 0 ? "Noch zu zahlen (Bescheid)" : "Erstattung (Bescheid)",
                        wert: abs(a.nochZuZahlen))
                    Text(
                        "Positive Abweichung heißt: die Berechnung lag über der Festsetzung, es blieb also etwas übrig. Der offene Betrag verrechnet Vorauszahlungen und bereits geleistete Bescheid-Zahlungen; Solidaritätszuschlag und Kirchensteuer bleiben außen vor."
                    )
                    .erklaerung()
                } else if settings == nil {
                    Text("Erst die Jahres-Einstellungen anlegen (Hinweis oben), dann lässt sich der Bescheid erfassen.")
                        .erklaerung()
                } else {
                    Text(
                        "Trag hier die festgesetzte Einkommensteuer aus deinem Bescheid ein – Kontor rechnet dann Abweichung zu beiden Berechnungen und den offenen Betrag aus. Die Nach- oder Rückzahlung selbst gehört als Zahlung ins Modul „Ausgaben“ (Art „ESt-Bescheid“)."
                    )
                    .erklaerung()
                }
            }
        }
    }
}

// MARK: - Sonstige Steuerzahlungen

/// `SteuerKind.sonstige` fängt Finanzamt-Bewegungen ab, die weder USt-VZ noch ESt-VZ noch KSK
/// sind (Solidaritätszuschlag, Kirchensteuer, Säumnis-/Verspätungszuschläge, Erstattungen).
/// Thematisch Finanzamt, deshalb hier und nicht bei der Vorsorge. Fließt bewusst **nicht** in
/// „Noch zu zahlen (Bescheid)" ein: das sind eigene Festsetzungen.
private struct SonstigeZahlungenPanel: View {
    let w: Jahreswerte
    @Environment(Zeitkontext.self) private var zeit
    @Environment(Navigation.self) private var nav

    var body: some View {
        if !w.sonstigeGezahlt.isEmpty {
            Panel(
                titel: "Sonstige Steuerzahlungen \(String(w.jahr))",
                aktion: { nav.zeigeAusgabenJahr(jahr: w.jahr, art: .steuern, zeit: zeit) }
            ) {
                VStack(spacing: 2) {
                    ForEach(w.sonstigeGezahlt) { ZahlungLeseZeile(eintrag: $0) }
                    Summenzeile(
                        label: "Summe sonstige",
                        wert: w.sonstigeGezahlt.reduce(Decimal(0)) { $0 + $1.betrag })
                }
            }
        }
    }
}
