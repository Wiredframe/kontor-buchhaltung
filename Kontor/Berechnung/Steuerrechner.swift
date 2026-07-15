import Foundation

/// Sämtliche Steuer-/Rücklagen-Berechnungen als reine, testbare Funktionen.
///
/// Leitprinzipien:
/// - USt/UStVA = **Soll** (nach Rechnungsdatum); Gewinn/ESt = **Zufluss** (nach Zahlungsdatum).
/// - Nur **betriebliche** Posten gehen in VSt/EÜR.
/// - **Reverse-Charge**: USt in KZ 84/85, cash-neutral; Netto bleibt EÜR-Ausgabe.
enum Steuer {

    static let satz19 = dez("0.19")
    static let satz7  = dez("0.07")

    // MARK: - Pro Ausgabe / Einnahme

    /// Vorschlag für die abziehbare Vorsteuer einer Ausgabe.
    static func vorsteuerVorschlag(brutto: Decimal, steuerart: Steuerart) -> Decimal {
        switch steuerart {
        case .inland19:                   (brutto - brutto / dez("1.19")).gerundet()
        case .inland7:                    (brutto - brutto / dez("1.07")).gerundet()
        case .reverseCharge, .steuerfrei: 0
        }
    }

    /// USt aus einem Nettobetrag zum gewählten Satz (Default Regelsatz 19 %).
    static func ust(ausNetto rnNetto: Decimal, satz: UStSatz = .satz19) -> Decimal {
        (rnNetto * satz.wert).gerundet()
    }

    // MARK: - USt / Vorsteuer je Periode

    /// USt (Soll) = Σ USt aller Rechnungen mit **Rechnungsdatum** in der Periode.
    /// (Ausfälle bleiben hier; die Korrektur erfolgt separat über §17.)
    static func ustSoll(_ einnahmen: [EinnahmePosten], in periode: Periode) -> Decimal {
        einnahmen
            .filter { periode.enthaelt($0.rechnungsdatum) }
            .reduce(Decimal(0)) { $0 + $1.ust }
    }

    /// Netto-Bemessungsgrundlage der zum gegebenen `satz` steuerpflichtigen Umsätze (Soll):
    /// KZ 81 (19 %) bzw. KZ 86 (7 %). Steuerfreie/nicht steuerbare Umsätze (USt = 0) bleiben außen vor.
    static func umsatzNetto(_ einnahmen: [EinnahmePosten], satz: UStSatz, in periode: Periode) -> Decimal {
        einnahmen
            .filter { $0.satz == satz && $0.ust != 0 && periode.enthaelt($0.rechnungsdatum) }
            .reduce(Decimal(0)) { $0 + $1.rnNetto }
    }

    /// Abziehbare Vorsteuer (Inland) = Σ VSt betrieblicher Ausgaben in der Periode.
    static func vorsteuer(_ ausgaben: [AusgabePosten], in periode: Periode) -> Decimal {
        ausgaben
            .filter { $0.betrieblich && periode.enthaelt($0.datum) }
            .reduce(Decimal(0)) { $0 + $1.vst }
    }

    /// Σ Netto-Umsatz (**Soll**) = alle Rechnungen mit Rechnungsdatum in der Periode.
    /// Der Status bleibt unbeachtet: ein Ausfall zählt hier weiter mit, denn er ist die
    /// Basis, gegen die die §17-/ESt-Korrektur im Ausfallmonat rechnet.
    static func rnSoll(_ einnahmen: [EinnahmePosten], in periode: Periode) -> Decimal {
        einnahmen
            .filter { periode.enthaelt($0.rechnungsdatum) }
            .reduce(Decimal(0)) { $0 + $1.rnNetto }
    }

    /// Σ Netto der **betrieblichen** Ausgaben in der Periode – gemeinsame Basis von
    /// EÜR-Gewinn und ESt-Rücklage. Privates bleibt draußen.
    static func betrieblichNetto(_ ausgaben: [AusgabePosten], in periode: Periode) -> Decimal {
        ausgaben
            .filter { $0.betrieblich && periode.enthaelt($0.datum) }
            .reduce(Decimal(0)) { $0 + $1.netto }
    }

    /// §17-Korrektur (negativ): USt uneinbringlicher Forderungen, deren
    /// **Ausfalldatum** in der Periode liegt.
    static func ustKorrekturAusfall(_ einnahmen: [EinnahmePosten], in periode: Periode) -> Decimal {
        let summe = einnahmen
            .filter { $0.status == .ausgefallen && ($0.ausfalldatum.map(periode.enthaelt) ?? false) }
            .reduce(Decimal(0)) { $0 + $1.ust }
        return -summe
    }

    /// Jahr+Monat als hashbarer Schlüssel – zum Gruppieren der Ausfälle nach Rechnungsmonat.
    private struct JahrMonat: Hashable { var jahr: Int; var monat: Int }

    /// ESt-Rücklagen-Auflösung (negativ) für Forderungsausfälle: Die im **Rechnungsmonat**
    /// gebildete Rücklage wird im Ausfallmonat **anteilig** wieder aufgelöst, da ohne Zufluss
    /// keine Einkommensteuer anfällt.
    ///
    /// Anteil = `rnNetto` der ausgefallenen Rechnung ÷ `rn` (Soll-Umsatz) ihres Rechnungsmonats.
    /// Die Bildung arbeitet auf dem **Monats-Aggregat** (`max(0, (rn − Ausgaben) − KSK) × Satz`);
    /// eine einzelne Rechnung daraus zurückzurechnen ist deshalb eine Zuordnungs-Entscheidung,
    /// keine Rechnung. Die anteilige Zerlegung addiert sich exakt zur gebildeten Rücklage:
    /// bei Vollausfall wird genau sie aufgelöst, bei Teilausfall entsprechend weniger – und
    /// **nie mehr, als gebildet wurde**, auch wenn mehrere Rechnungen desselben Monats ausfallen.
    ///
    /// Die Bildungsgrößen (Ausgaben, KSK, Satz) stammen aus dem Rechnungsmonat, der in einem
    /// **Vorjahr** liegen kann. Gerundet wird **einmal je Rechnungsmonat** – dieselbe Konvention
    /// wie bei KZ 81/86 (erst summieren, dann runden).
    static func estAusfallKorrektur(_ einnahmen: [EinnahmePosten], in periode: Periode,
                                    ausgaben: [AusgabePosten],
                                    kskFuer: (Int, Int) -> Decimal,
                                    satzFuer: (Int, Int) -> Decimal) -> Decimal {
        let ausgefallen = einnahmen
            .filter { $0.status == .ausgefallen && ($0.ausfalldatum.map(periode.enthaelt) ?? false) }
        guard !ausgefallen.isEmpty else { return 0 }

        let nachRechnungsmonat = Dictionary(grouping: ausgefallen) {
            JahrMonat(jahr: appKalender.component(.year, from: $0.rechnungsdatum),
                      monat: appKalender.component(.month, from: $0.rechnungsdatum))
        }

        // Je Rechnungsmonat einmal die Bildung nachschlagen, einmal runden, exakt aufsummieren –
        // dadurch ist das Ergebnis unabhängig von der Iterationsreihenfolge des Dictionaries.
        let summe = nachRechnungsmonat.reduce(Decimal(0)) { teil, eintrag in
            let (jm, posten) = eintrag
            let gebildet = estGebildet(jahr: jm.jahr, monat: jm.monat, einnahmen: einnahmen,
                                       ausgaben: ausgaben, kskFuer: kskFuer, satzFuer: satzFuer)
            // Ohne positiven Soll-Umsatz gibt es keinen Anteil zu bilden. Der Guard ist Pflicht:
            // Decimal-Division durch 0 trappt nicht, sondern liefert NaN – das liefe still als
            // „NaN €" durch Rücklage und Jahres-ESt und wäre schlimmer als ein Absturz.
            guard gebildet.rn > 0 else { return teil }
            let ausgefallenNetto = posten.reduce(Decimal(0)) { $0 + $1.rnNetto }
            return teil + (gebildet.est * ausgefallenNetto / gebildet.rn).gerundet()
        }
        return -summe
    }

    // MARK: - Reverse-Charge (§13b, KZ 84/85)

    /// KZ 84: Netto-Bemessung der Reverse-Charge-Ausgaben in der Periode.
    static func reverseChargeNetto(_ ausgaben: [AusgabePosten], in periode: Periode) -> Decimal {
        ausgaben
            .filter { $0.betrieblich && $0.steuerart == .reverseCharge && periode.enthaelt($0.datum) }
            .reduce(Decimal(0)) { $0 + $1.netto }
    }

    /// KZ 85: USt (19 %) auf die Reverse-Charge-Bemessung (zugleich als Vorsteuer abziehbar).
    static func reverseChargeUSt(_ ausgaben: [AusgabePosten], in periode: Periode) -> Decimal {
        (reverseChargeNetto(ausgaben, in: periode) * satz19).gerundet()
    }

    /// Vollständige UStVA-Kennzahlen einer Periode. Die USt je Satz wird **wie ELSTER** aus der
    /// Netto-Summe des jeweiligen Buckets berechnet (erst summieren, dann einmal `Summe × Satz` runden) –
    /// nicht die je Beleg vorgerundeten Beträge aufaddieren.
    static func ustva(einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten], periode: Periode) -> UStVAErgebnis {
        let rcUSt = reverseChargeUSt(ausgaben, in: periode)
        let netto19 = umsatzNetto(einnahmen, satz: .satz19, in: periode)
        let netto7  = umsatzNetto(einnahmen, satz: .satz7,  in: periode)
        return UStVAErgebnis(
            kz81: netto19,
            ust81: (netto19 * satz19).gerundet(),
            kz86: netto7,
            ust86: (netto7 * satz7).gerundet(),
            kz66: vorsteuer(ausgaben, in: periode),
            kz84: reverseChargeNetto(ausgaben, in: periode),
            kz85: rcUSt,
            kz67: rcUSt,
            korrektur17: ustKorrekturAusfall(einnahmen, in: periode)
        )
    }

    /// Veranlagungsjahr + Notiz für eine **USt-Vorauszahlung** anhand des Zahlungsmonats.
    /// Die letzte VA eines Jahres (Q4 bzw. Dezember) wird erst im Folgejahr gezahlt – fällig 10.1.
    /// (ohne) bzw. 10.2. (mit **Dauerfristverlängerung**). Eine Zahlung in diesem Fenster zählt zum
    /// **Vorjahr**. `rhythmus`/`dauerfrist` kommen aus den `YearSettings` des Vorjahres.
    static func ustVzZuordnung(zahlMonat: Int, zahlJahr: Int, rhythmus: UStVARhythmus, dauerfrist: Bool)
        -> (jahr: Int, notiz: String) {
        let faelligMonat = dauerfrist ? 2 : 1
        guard zahlMonat <= faelligMonat else { return (zahlJahr, "") }
        let jahr = zahlJahr - 1
        let zeitraum = rhythmus == .monatlich ? "Dez" : "Q4"
        return (jahr, "USt-VA \(zeitraum) \(jahr)")
    }

    // MARK: - EÜR

    /// EÜR-Gewinn (Zuflussprinzip): Σ bezahlter Netto-Einnahmen − Σ betrieblicher Netto-Ausgaben im Jahr.
    static func euerGewinn(einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten], jahr: Int) -> Decimal {
        let p = Periode.jahr(jahr)
        let einnahmenSumme = einnahmen
            .filter { if let z = $0.zahlungsdatum { p.enthaelt(z) } else { false } }
            .reduce(Decimal(0)) { $0 + $1.rnNetto }
        return einnahmenSumme - betrieblichNetto(ausgaben, in: p)
    }

    // MARK: - Einkommensteuer-Rücklage

    /// Pauschale ESt-Rücklage: `(Basis − KSK) × Satz`, nie negativ. Basis = betrieblicher
    /// Gewinn (RN − Betriebsausgaben); KSK ist als Vorsorgeaufwand (Sonderausgabe) abziehbar.
    static func estPauschal(basis: Decimal, ksk: Decimal, satz: Decimal) -> Decimal {
        (max(0, basis - ksk) * satz).gerundet()
    }

    /// Die in (`jahr`, `monat`) **gebildete** ESt-Rücklage samt zugehöriger Soll-Basis `rn`.
    ///
    /// **Einzige Quelle** für beide Richtungen: die Bildung (`monatsauswertung`) und die
    /// Auflösung bei Forderungsausfall (`estAusfallKorrektur`) lesen hier – vorher war die
    /// Formel an zwei Stellen unabhängig codiert und driftete auseinander.
    static func estGebildet(jahr: Int, monat: Int,
                            einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten],
                            kskFuer: (Int, Int) -> Decimal,
                            satzFuer: (Int, Int) -> Decimal) -> (est: Decimal, rn: Decimal) {
        let p = Periode.monat(jahr, monat)
        let rn = rnSoll(einnahmen, in: p)
        let est = estPauschal(basis: rn - betrieblichNetto(ausgaben, in: p),
                              ksk: kskFuer(jahr, monat), satz: satzFuer(jahr, monat))
        return (est, rn)
    }

    // MARK: - Monatsrücklage / Verfügbar

    /// Steuerrücklage eines Monats: `(USt − VSt + §17-Korrektur) + KSK + ESt-Anteil`. (ohne Fixkosten)
    /// Die §17-Korrektur ist negativ (Forderungsausfall) und mindert die Rücklage im Ausfallmonat.
    static func steuerRuecklage(ust: Decimal, vorsteuer: Decimal, ustKorrektur: Decimal,
                                ksk: Decimal, estAnteil: Decimal) -> Decimal {
        (ust - vorsteuer + ustKorrektur) + ksk + estAnteil
    }

    /// Verfügbar = Brutto − Steuerrücklage − Fixkosten.
    static func verfuegbar(brutto: Decimal, steuerRuecklage: Decimal, fixkosten: Decimal) -> Decimal {
        brutto - steuerRuecklage - fixkosten
    }
}
