import SwiftData
import SwiftUI

/// Jahresabschluss → Vorsorge (KSK): Soll aus den je Monat hinterlegten KV/RV/PV-Beträgen
/// gegen die tatsächlichen Abbuchungen.
struct JahresVorsorgeView: View {
    @Environment(Zeitkontext.self) private var zeit
    @Environment(Navigation.self) private var nav

    var body: some View {
        JahresSeite(titel: "Vorsorge (KSK)") { w in
            ThemaPaar(
                // Die tatsächlichen KSK-Abbuchungen liegen als Vorsorge-Zeilen im Ledger.
                istAktion: { nav.zeigeAusgabenJahr(jahr: w.jahr, art: .vorsorge, zeit: zeit) },
                soll: { KSKSollBlock(w: w) }, ist: { KSKIstBlock(w: w) })
            if !w.vorsorgeGezahlt.isEmpty {
                Panel(
                    titel: "Weitere Vorsorge (privat)",
                    aktion: { nav.zeigeAusgabenJahr(jahr: w.jahr, art: .vorsorge, zeit: zeit) }
                ) {
                    VStack(spacing: 2) {
                        ForEach(w.vorsorgeGezahlt) { ZahlungLeseZeile(eintrag: $0) }
                        Summenzeile(label: "Gezahlt gesamt", wert: w.vorsorgeSumme)
                        Text(
                            "Basisrente, BU, freiwillige Kranken- und Pflegeversicherung neben der KSK. Mindert die voraussichtliche Einkommensteuer (ohne Höchstbeträge gerechnet), nie EÜR oder USt."
                        )
                        .erklaerung()
                    }
                }
            }
            if let s = Steuer.kskSchaetzung(
                jahr: w.jahr, einnahmen: w.einP, ausgaben: w.ausP, settings: jahre.first { $0.jahr == w.jahr })
            {
                KSKEinkommenKarte(s: s)
            }
        }
    }

    @Query private var jahre: [YearSettings]
}

/// Gemeldetes Jahresarbeitseinkommen gegen die Hochrechnung aus der EÜR.
private struct KSKEinkommenKarte: View {
    let s: KSKEinkommensschaetzung

    private var laufend: Bool { s.monate < 12 }

    var body: some View {
        Panel(titel: "Arbeitseinkommen für die KSK") {
            VStack(spacing: 2) {
                Kartenzeile(
                    label: laufend ? "Gewinn Januar bis \(monatsName(s.monate))" : "Gewinn \(String(s.jahr)) (EÜR)",
                    wert: s.gewinnBisher, icon: "function")
                if laufend {
                    Kartenzeile(
                        label: "Hochgerechnet auf das Jahr", wert: s.hochrechnung, icon: "chart.line.uptrend.xyaxis")
                }
                if s.gemeldet > 0 {
                    Kartenzeile(label: "Gemeldetes Jahresarbeitseinkommen", wert: s.gemeldet, icon: "doc.text")
                    Kartenzeile(label: "Abweichung", wert: s.abweichung, icon: "plusminus", signiert: true)
                }
                Text(hinweis).erklaerung()
            }
        }
    }

    private var hinweis: String {
        if s.gemeldet == 0 {
            return
                "Kein Jahresarbeitseinkommen hinterlegt (Monatsabschluss › Werte). Die KSK bemisst die Beiträge danach."
        }
        let basis =
            laufend
            ? "Hochrechnung aus \(s.monate) abgeschlossenen Monaten, grob: Einmaliges verzerrt sie."
            : "Ergebnis des Jahres."
        let rat =
            s.deutlich
            ? " Die Abweichung ist deutlich: Die Schätzung lässt sich bei der KSK jederzeit für die Zukunft ändern (wirkt ab dem Folgemonat)."
            : " Liegt im Rahmen der Meldung."
        return basis + rat + " Die Meldung fürs Folgejahr geht bis zum 1. Dezember an die KSK."
    }
}

private struct KSKSollBlock: View {
    let w: Jahreswerte

    var body: some View {
        VStack(spacing: 2) {
            Kartenzeile(label: "Krankenversicherung (KV)", wert: w.ksk.kv, icon: "cross.case")
            Kartenzeile(label: "Rentenversicherung (RV)", wert: w.ksk.rv, icon: "building.columns")
            Kartenzeile(label: "Pflegeversicherung (PV)", wert: w.ksk.pv, icon: "heart.text.square")
            Summenzeile(label: "Summe KSK (Soll) \(String(w.jahr))", wert: w.kskGesamt)
            Text("Aus den je Monat hinterlegten Beitragssätzen (Soll); gepflegt im Monatsabschluss unter „Werte“.")
                .erklaerung()
        }
    }
}

private struct KSKIstBlock: View {
    let w: Jahreswerte

    var body: some View {
        VStack(spacing: 2) {
            if w.kskGezahlt.isEmpty {
                Text("Noch keine KSK-Abbuchung erfasst (Kontoauszug-Import).").erklaerung()
            } else {
                ForEach(w.kskGezahlt) { ZahlungLeseZeile(eintrag: $0) }
                Summenzeile(label: "Gezahlt gesamt", wert: w.kskGezahlt.reduce(Decimal(0)) { $0 + $1.betrag })
            }
        }
    }
}
