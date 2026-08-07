import SwiftUI

/// Jahresabschluss → Vorsorge (KSK): Soll aus den je Monat hinterlegten KV/RV/PV-Beträgen
/// gegen die tatsächlichen Abbuchungen.
struct JahresVorsorgeView: View {
    var body: some View {
        JahresSeite(titel: "Vorsorge (KSK)") { w in
            ThemaPaar(soll: { KSKSollBlock(w: w) }, ist: { KSKIstBlock(w: w) })
        }
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
