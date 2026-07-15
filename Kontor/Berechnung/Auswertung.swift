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
    var ausgabenNetto: Decimal
    var vstGesamt: Decimal

    var gewinn: Decimal { einnahmenBezahlt - ausgabenNetto }
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
        let ust = ustSoll(einnahmen, in: p)
        let vst = vorsteuer(ausgaben, in: p)
        let ustKorrektur = ustKorrekturAusfall(einnahmen, in: p)

        // ESt-Rücklage pauschal: (betrieblicher Gewinn − KSK) × Satz; ein Forderungsausfall
        // löst sie im Ausfallmonat wieder auf (per Rechnung über den Umsatzanteil).
        // `estGebildet` ist die gemeinsame Quelle von Bildung und Auflösung.
        let gebildet = estGebildet(jahr: jahr, monat: monat, einnahmen: einnahmen, ausgaben: ausgaben,
                                   kskFuer: { _, _ in kskMonat }, satzFuer: pauschalSatz)
        let rn = gebildet.rn
        let est = gebildet.est
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

    /// EÜR-Jahresauswertung (Einnahmen nach Zufluss, betriebliche Ausgaben netto).
    static func jahresauswertung(jahr: Int, einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten]) -> JahresAuswertung {
        let p = Periode.jahr(jahr)
        let einnahmenBezahlt = einnahmen
            .filter { if let z = $0.zahlungsdatum { p.enthaelt(z) } else { false } }
            .reduce(Decimal(0)) { $0 + $1.rnNetto }
        let betrieblich = ausgaben.filter { $0.betrieblich && p.enthaelt($0.datum) }
        return JahresAuswertung(
            einnahmenBezahlt: einnahmenBezahlt,
            ausgabenNetto: betrieblich.reduce(Decimal(0)) { $0 + $1.netto },
            vstGesamt: betrieblich.reduce(Decimal(0)) { $0 + $1.vst })
    }
}
