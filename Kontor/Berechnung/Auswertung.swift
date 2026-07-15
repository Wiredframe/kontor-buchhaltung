import Foundation

/// Aggregierte Monatswerte – **die** Quelle für den Gewinn-Waterfall des Monats.
///
/// Trägt nur Roh-Aggregate; alles Abgeleitete sind berechnete Eigenschaften. Das ist Absicht:
/// „Frei verfügbar" war zuvor dreimal unabhängig codiert (Monatsabschluss, Dashboard und
/// `Steuer.verfuegbar` für den MCP) – und die MCP-Variante rechnete etwas ganz anderes.
struct MonatsAuswertung: Hashable {
    var rn: Decimal              // Netto-Umsatz (Soll, nach Rechnungsdatum)
    var ust: Decimal
    var vst: Decimal
    var ustKorrektur: Decimal    // §17 (negativ) aus Forderungsausfällen mit Ausfalldatum im Monat
    var ksk: Decimal
    var est: Decimal             // gebildete ESt-Rücklage (Soll-Basis, ohne Ausfall-Korrektur)
    var estKorrektur: Decimal    // ESt-Auflösung (negativ) für Ausfälle mit Ausfalldatum im Monat
    var betriebsausgabenNetto: Decimal
    var fixkostenPrivat: Decimal   // wiederkehrende private Kosten (Fixkosten + Subscriptions), brutto
    var privatVariabel: Decimal    // Lebensmittel + Anschaffungen des Monats

    var brutto: Decimal { rn + ust }
    var ustZahllast: Decimal { ust - vst + ustKorrektur }
    /// Zurückzulegen: USt-Zahllast + KSK + ESt-Anteil (ohne die privaten Kosten).
    var steuerRuecklage: Decimal { ustZahllast + ksk + est + estKorrektur }

    // MARK: Gewinn-Waterfall (CLAUDE.md: „echter Gewinn nach betrieblichen UND privaten Ausgaben")

    var betrieblicherGewinn: Decimal { rn - betriebsausgabenNetto }
    var nachSteuer: Decimal { betrieblicherGewinn - ksk - est - estKorrektur }
    var privatGesamt: Decimal { fixkostenPrivat + privatVariabel }

    /// „Frei verfügbar" – was nach allem übrig bleibt.
    ///
    /// Bewusst **gewinn-**, nicht cash-basiert: Die USt ist ein durchlaufender Posten (vom Kunden
    /// kassiert, ans Finanzamt weitergereicht) und gehört deshalb weder in den Gewinn noch in das,
    /// was zur Verfügung steht. Die frühere Engine-Formel (`brutto − Rücklage − Fixkosten`) ließ
    /// die Betriebsausgaben komplett aus und addierte die Vorsteuer sogar wieder hinzu.
    var verfuegbar: Decimal { nachSteuer - privatGesamt }
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
    ///
    /// `kskFuer(jahr, monat)` statt eines festen Monatsbetrags, weil die Auflösung eines
    /// Forderungsausfalls die KSK des **Rechnungsmonats** braucht – der in einem Vorjahr
    /// liegen kann. Symmetrisch zu `pauschalSatz`.
    /// `privatVariabel` (Lebensmittel + Anschaffungen des Monats) kommt vom Aufrufer: Diese
    /// Entitäten liegen außerhalb der Ausgaben-Posten, die Engine sieht sie nicht.
    static func monatsauswertung(
        monat: Int, jahr: Int,
        einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten],
        kskFuer: (Int, Int) -> Decimal,
        fixkostenPrivat: Decimal,
        privatVariabel: Decimal = 0,
        pauschalSatz: (Int, Int) -> Decimal
    ) -> MonatsAuswertung {
        let p = Periode.monat(jahr, monat)

        // ESt-Rücklage pauschal: (betrieblicher Gewinn − KSK) × Satz; ein Forderungsausfall
        // löst sie im Ausfallmonat anteilig wieder auf (Anteil am Umsatz des Rechnungsmonats).
        // `estGebildet` ist die gemeinsame Quelle von Bildung und Auflösung.
        let gebildet = estGebildet(jahr: jahr, monat: monat, einnahmen: einnahmen, ausgaben: ausgaben,
                                   kskFuer: kskFuer, satzFuer: pauschalSatz)
        return MonatsAuswertung(
            rn: gebildet.rn,
            ust: ustSoll(einnahmen, in: p),
            vst: vorsteuer(ausgaben, in: p),
            ustKorrektur: ustKorrekturAusfall(einnahmen, in: p),
            ksk: kskFuer(jahr, monat),
            est: gebildet.est,
            estKorrektur: estAusfallKorrektur(einnahmen, in: p, ausgaben: ausgaben,
                                              kskFuer: kskFuer, satzFuer: pauschalSatz),
            betriebsausgabenNetto: betrieblichNetto(ausgaben, in: p),
            fixkostenPrivat: fixkostenPrivat,
            privatVariabel: privatVariabel)
    }

    /// Geschätzte ESt-Jahresrücklage = Σ (`est` + `estKorrektur`) über alle zwölf Monate.
    /// Kapselt die Monatsschleife (vorher in der View); die Arrays werden je Monat einmal
    /// gefiltert, der Aufrufer mappt `posten`/`wert` nur einmal. Hängt **nicht** von den
    /// (privaten) Fixkosten ab – daher kein fixkostenPrivat-Parameter.
    static func estRuecklageJahr(
        jahr: Int,
        einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten], kskFuer: (Int, Int) -> Decimal,
        pauschalSatz: (Int, Int) -> Decimal
    ) -> Decimal {
        (1...12).reduce(Decimal(0)) { sum, m in
            let a = monatsauswertung(
                monat: m, jahr: jahr, einnahmen: einnahmen, ausgaben: ausgaben, kskFuer: kskFuer,
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
