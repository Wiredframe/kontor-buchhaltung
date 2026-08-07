import SwiftUI

/// Jahresabschluss → Umsatzsteuer: geschätzte Zahllast je Voranmeldungs-Zeitraum gegen die
/// tatsächlich geleisteten USt-Vorauszahlungen.
struct JahresUmsatzsteuerView: View {
    var body: some View {
        JahresSeite(titel: "Umsatzsteuer") { w in
            ThemaPaar(soll: { USTSollBlock(w: w) }, ist: { USTIstBlock(w: w) })
        }
    }
}

private struct USTSollBlock: View {
    let w: Jahreswerte

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(w.ustPerioden, id: \.label) { p in Kennzahl(titel: p.label, wert: p.betrag, akzent: true) }
            }
            Summenzeile(label: "USt-Zahllast \(String(w.jahr))", wert: w.ustJahr)
            Text("Soll-Versteuerung nach Rechnungsdatum (KZ 83 je Zeitraum); Detail siehe Modul „UStVA“.")
                .erklaerung()
        }
    }
}

private struct USTIstBlock: View {
    let w: Jahreswerte

    var body: some View {
        VStack(spacing: 2) {
            if w.ustGezahlt.isEmpty {
                Text("Noch keine USt-Zahlung erfasst (Kontoauszug-Import bzw. Modul „Ausgaben“).").erklaerung()
            } else {
                ForEach(w.ustGezahlt) { ZahlungLeseZeile(eintrag: $0) }
                Summenzeile(label: "Gezahlt gesamt", wert: w.ustGezahlt.reduce(Decimal(0)) { $0 + $1.betrag })
            }
        }
    }
}
