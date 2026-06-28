import Foundation

/// Aggregierte Monatswerte für „Steuer & Rücklagen".
struct MonatsAuswertung: Hashable {
    var rn: Decimal
    var ust: Decimal
    var brutto: Decimal
    var vst: Decimal
    var ustKorrektur: Decimal    // §17 (negativ) aus Forderungsausfällen mit Ausfalldatum im Monat
    var ksk: Decimal
    var est: Decimal             // gebildete ESt-Rücklage (Soll-Basis, ohne Ausfall-Korrektur)
    var estKorrektur: Decimal    // ESt-Auflösung (negativ) für Ausfälle mit Ausfalldatum im Monat
    var steuerRuecklage: Decimal
    var fixkostenPrivat: Decimal
    var verfuegbar: Decimal
}

/// Aggregierte Jahreswerte für die EÜR-Übersicht.
struct JahresAuswertung: Hashable {
    var einnahmenBezahlt: Decimal
    var ausgabenLaufend: Decimal
    var ausgabenJaehrlich: Decimal
    var ausgabenAnschaffung: Decimal
    var vstGesamt: Decimal

    var ausgabenGesamt: Decimal { ausgabenLaufend + ausgabenJaehrlich + ausgabenAnschaffung }
    var gewinn: Decimal { einnahmenBezahlt - ausgabenGesamt }
}

extension Steuer {

    /// Monatsauswertung nach den geltenden Einstellungen (Soll-Basis für RN/USt).
    static func monatsauswertung(
        monat: Int, jahr: Int,
        einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten], kskMonat: Decimal,
        fixkostenPrivat: Decimal,
        pauschalSatz: (Int, Int) -> Decimal
    ) -> MonatsAuswertung {
        let p = Periode.monat(jahr, monat)
        let rn = einnahmen.filter { p.enthaelt($0.rechnungsdatum) }.reduce(Decimal(0)) { $0 + $1.rnNetto }
        let ust = ustSoll(einnahmen, in: p)
        let vst = vorsteuer(ausgaben, in: p)
        let ustKorrektur = ustKorrekturAusfall(einnahmen, in: p)
        let ausgabenNetto = ausgaben
            .filter { $0.betrieblich && p.enthaelt($0.datum) }
            .reduce(Decimal(0)) { $0 + $1.netto }

        // ESt-Rücklage pauschal: (betrieblicher Gewinn − KSK) × Satz; ein Forderungsausfall
        // löst sie im Ausfallmonat wieder auf (per Rechnung über den Umsatzanteil).
        let est = estPauschal(basis: rn - ausgabenNetto, ksk: kskMonat, satz: pauschalSatz(jahr, monat))
        let estKorrektur = estAusfallKorrektur(einnahmen, in: p, satzFuer: pauschalSatz)

        let ruecklage = steuerRuecklage(ust: ust, vorsteuer: vst, ustKorrektur: ustKorrektur,
                                        ksk: kskMonat, estAnteil: est + estKorrektur)
        return MonatsAuswertung(
            rn: rn, ust: ust, brutto: rn + ust, vst: vst, ustKorrektur: ustKorrektur, ksk: kskMonat,
            est: est, estKorrektur: estKorrektur,
            steuerRuecklage: ruecklage, fixkostenPrivat: fixkostenPrivat,
            verfuegbar: verfuegbar(brutto: rn + ust, steuerRuecklage: ruecklage, fixkosten: fixkostenPrivat))
    }

    /// Geschätzte ESt-Jahresrücklage = Σ (`est` + `estKorrektur`) über alle zwölf Monate.
    /// Kapselt die Monatsschleife (vorher in der View); die Arrays werden je Monat einmal
    /// gefiltert, der Aufrufer mappt `posten`/`wert` nur einmal. Hängt **nicht** von den
    /// (privaten) Fixkosten ab – daher kein fixkostenPrivat-Parameter.
    static func estRuecklageJahr(
        jahr: Int,
        einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten], kskFuer: (Int) -> Decimal,
        pauschalSatz: (Int, Int) -> Decimal
    ) -> Decimal {
        (1...12).reduce(Decimal(0)) { sum, m in
            let a = monatsauswertung(
                monat: m, jahr: jahr, einnahmen: einnahmen, ausgaben: ausgaben, kskMonat: kskFuer(m),
                fixkostenPrivat: 0, pauschalSatz: pauschalSatz)
            return sum + a.est + a.estKorrektur
        }
    }

    /// USt-Jahres-Zahllast (Soll) = Σ der vier Quartals-Zahllasten.
    static func ustZahllastJahr(jahr: Int, einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten]) -> Decimal {
        (1...4).reduce(Decimal(0)) { $0 + ustva(einnahmen: einnahmen, ausgaben: ausgaben, periode: Periode.quartal(jahr, $1)).zahllast }
    }

    /// EÜR-Jahresauswertung (Einnahmen nach Zufluss, Ausgaben nach Kategorie netto).
    static func jahresauswertung(jahr: Int, einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten]) -> JahresAuswertung {
        let p = Periode.jahr(jahr)
        let einnahmenBezahlt = einnahmen
            .filter { if let z = $0.zahlungsdatum { p.enthaelt(z) } else { false } }
            .reduce(Decimal(0)) { $0 + $1.rnNetto }
        func nettoSumme(_ kat: Kategorie) -> Decimal {
            ausgaben.filter { $0.betrieblich && $0.kategorie == kat && p.enthaelt($0.datum) }
                .reduce(Decimal(0)) { $0 + $1.netto }
        }
        let vst = ausgaben.filter { $0.betrieblich && p.enthaelt($0.datum) }
            .reduce(Decimal(0)) { $0 + $1.vst }
        return JahresAuswertung(
            einnahmenBezahlt: einnahmenBezahlt,
            ausgabenLaufend: nettoSumme(.laufend),
            ausgabenJaehrlich: nettoSumme(.jaehrlich),
            ausgabenAnschaffung: nettoSumme(.anschaffung),
            vstGesamt: vst)
    }
}
