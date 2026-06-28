import Foundation

/// Sämtliche Steuer-/Rücklagen-Berechnungen als reine, testbare Funktionen.
///
/// Leitprinzipien:
/// - USt/UStVA = **Soll** (nach Rechnungsdatum); Gewinn/ESt = **Zufluss** (nach Zahlungsdatum).
/// - Nur **betriebliche** Posten gehen in VSt/EÜR.
/// - **Reverse-Charge**: USt in KZ 84/85, cash-neutral; Netto bleibt EÜR-Ausgabe.
enum Steuer {

    static let satz19 = dez("0.19")

    // MARK: - Pro Ausgabe / Einnahme

    /// Vorschlag für die abziehbare Vorsteuer einer Ausgabe.
    static func vorsteuerVorschlag(brutto: Decimal, steuerart: Steuerart) -> Decimal {
        switch steuerart {
        case .inland19:                   (brutto - brutto / dez("1.19")).gerundet()
        case .reverseCharge, .steuerfrei: 0
        }
    }

    /// USt (19 %) aus einem Nettobetrag.
    static func ust(ausNetto rnNetto: Decimal) -> Decimal {
        (rnNetto * satz19).gerundet()
    }

    // MARK: - USt / Vorsteuer je Periode

    /// USt (Soll) = Σ USt aller Rechnungen mit **Rechnungsdatum** in der Periode.
    /// (Ausfälle bleiben hier; die Korrektur erfolgt separat über §17.)
    static func ustSoll(_ einnahmen: [EinnahmePosten], in periode: Periode) -> Decimal {
        einnahmen
            .filter { periode.enthaelt($0.rechnungsdatum) }
            .reduce(Decimal(0)) { $0 + $1.ust }
    }

    /// KZ 81: Netto-Bemessungsgrundlage der zu 19 % steuerpflichtigen Umsätze (Soll).
    /// Steuerfreie/nicht steuerbare Umsätze (USt = 0) bleiben hier außen vor.
    static func umsatzNetto19(_ einnahmen: [EinnahmePosten], in periode: Periode) -> Decimal {
        einnahmen
            .filter { $0.ust != 0 && periode.enthaelt($0.rechnungsdatum) }
            .reduce(Decimal(0)) { $0 + $1.rnNetto }
    }

    /// Abziehbare Vorsteuer (Inland) = Σ VSt betrieblicher Ausgaben in der Periode.
    static func vorsteuer(_ ausgaben: [AusgabePosten], in periode: Periode) -> Decimal {
        ausgaben
            .filter { $0.betrieblich && periode.enthaelt($0.datum) }
            .reduce(Decimal(0)) { $0 + $1.vst }
    }

    /// §17-Korrektur (negativ): USt uneinbringlicher Forderungen, deren
    /// **Ausfalldatum** in der Periode liegt.
    static func ustKorrekturAusfall(_ einnahmen: [EinnahmePosten], in periode: Periode) -> Decimal {
        let summe = einnahmen
            .filter { $0.status == .ausgefallen && ($0.ausfalldatum.map(periode.enthaelt) ?? false) }
            .reduce(Decimal(0)) { $0 + $1.ust }
        return -summe
    }

    /// ESt-Rücklagen-Korrektur (negativ) für Forderungsausfälle: Die im Rechnungsmonat
    /// (Soll-Basis) gebildete ESt-Rücklage wird im **Ausfallmonat** wieder aufgelöst,
    /// da ohne Zufluss keine Einkommensteuer anfällt. `satzFuer(jahr, monat)` liefert den
    /// Pauschalsatz des jeweiligen Rechnungsmonats (exakte Umkehrung der Bildung).
    static func estAusfallKorrektur(_ einnahmen: [EinnahmePosten], in periode: Periode,
                                    satzFuer: (Int, Int) -> Decimal) -> Decimal {
        let summe = einnahmen
            .filter { $0.status == .ausgefallen && ($0.ausfalldatum.map(periode.enthaelt) ?? false) }
            .reduce(Decimal(0)) { teil, e in
                let j = appKalender.component(.year, from: e.rechnungsdatum)
                let m = appKalender.component(.month, from: e.rechnungsdatum)
                return teil + (e.rnNetto * satzFuer(j, m)).gerundet()
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

    /// Vollständige UStVA-Kennzahlen einer Periode.
    static func ustva(einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten], periode: Periode) -> UStVAErgebnis {
        let rcUSt = reverseChargeUSt(ausgaben, in: periode)
        return UStVAErgebnis(
            kz81: umsatzNetto19(einnahmen, in: periode),
            ust81: ustSoll(einnahmen, in: periode),
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
        let ausgabenSumme = ausgaben
            .filter { $0.betrieblich && p.enthaelt($0.datum) }
            .reduce(Decimal(0)) { $0 + $1.netto }
        return einnahmenSumme - ausgabenSumme
    }

    // MARK: - Einkommensteuer-Rücklage

    /// Pauschale ESt-Rücklage: `(Basis − KSK) × Satz`, nie negativ. Basis = betrieblicher
    /// Gewinn (RN − Betriebsausgaben); KSK ist als Vorsorgeaufwand (Sonderausgabe) abziehbar.
    static func estPauschal(basis: Decimal, ksk: Decimal, satz: Decimal) -> Decimal {
        (max(0, basis - ksk) * satz).gerundet()
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
