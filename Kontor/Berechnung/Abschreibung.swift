import Foundation

// MARK: - Abschreibung (AfA) und Abflussprinzip
//
// Zwei Regeln, die nur die **Betriebsausgabe** einer Periode betreffen, nie die Vorsteuer:
//
// 1. **AfA (§7 Abs. 1 EStG):** Ein abnutzbares Anlagegut (Nutzungsdauer an der Ausgabe) geht
//    nicht beim Kauf, sondern linear über die Nutzungsdauer in den Gewinn ein, **monatsgenau** ab
//    dem Kaufmonat (der Kaufmonat zählt voll). Kumuliert gerundet, damit die Summe aller Raten
//    exakt das Netto ergibt. Die Vorsteuer zählt trotzdem voll im Kaufzeitraum (UStVA).
// 2. **Abfluss (§11 Abs. 2 EStG):** Die EÜR zählt eine Ausgabe im Jahr der Zahlung. Monatsgewinn
//    und ESt-Rücklage bleiben beim Belegdatum, sie sind Soll-Größen wie die Einnahmenseite.
//    Regelmäßig wiederkehrende Ausgaben, die innerhalb von zehn Tagen um den Jahreswechsel fällig
//    und bezahlt sind, gehören in das Jahr, zu dem sie wirtschaftlich gehören (Satz 2).

extension Steuer {

    /// Grenze für geringwertige Wirtschaftsgüter (§6 Abs. 2 EStG, netto): bis hierhin darf sofort
    /// abgezogen werden, darüber wird abgeschrieben.
    static let gwgGrenze = Decimal(800)

    /// Nutzungsdauern, die der Ausgaben-Editor anbietet (AfA-Tabelle AV, gängige Güter). Rechner,
    /// Monitore und Software haben laut BMF ein Jahr – die bleiben sofort abziehbar.
    static let nutzungsdauern = Array(3...13)

    /// „Kurze Zeit" um den Jahreswechsel: 22.12. bis 10.01. (zehn Tage, H 11 EStH).
    static func umJahreswechsel(_ datum: Date) -> Bool {
        let m = appKalender.component(.month, from: datum)
        let t = appKalender.component(.day, from: datum)
        return (m == 12 && t >= 22) || (m == 1 && t <= 10)
    }
}

/// Fortlaufender Monatsindex (Jahr × 12 + Monat), um Monatsabstände zu zählen.
private func monatsIndex(_ datum: Date) -> Int {
    appKalender.component(.year, from: datum) * 12 + appKalender.component(.month, from: datum) - 1
}

extension AusgabePosten {

    /// Bis **vor** den Monat von `stichtag` aufgelaufene AfA (Perioden beginnen am Monatsersten).
    func abgeschrieben(vor stichtag: Date) -> Decimal {
        let monate = nutzungsdauer * 12
        guard monate > 0 else { return 0 }
        let fertig = min(max(monatsIndex(stichtag) - monatsIndex(datum), 0), monate)
        return (netto * Decimal(fertig) / Decimal(monate)).gerundet()
    }

    /// AfA in der Periode.
    func afa(in periode: Periode) -> Decimal {
        abgeschrieben(vor: periode.bis) - abgeschrieben(vor: periode.von)
    }

    /// Tag, an dem die Ausgabe für die EÜR abgeflossen ist.
    ///
    /// Zehn-Tage-Regel: Eine wiederkehrende Ausgabe mit Belegdatum **und** Zahlung um denselben
    /// Jahreswechsel zählt im Jahr des Belegdatums (Dezember-Miete am 3. Januar bezahlt: Vorjahr).
    var abflussdatum: Date {
        guard let z = zahlungsdatum else { return datum }
        if wiederkehrend, Steuer.umJahreswechsel(datum), Steuer.umJahreswechsel(z),
            abs(appKalender.component(.year, from: z) - appKalender.component(.year, from: datum)) == 1
        {
            return datum
        }
        return z
    }

    /// Betriebsausgabe in der Periode: bei einem Anlagegut die AfA, sonst das Netto nach
    /// Belegdatum bzw. – für die EÜR (`abfluss`) – nach Abfluss. Die AfA folgt immer der
    /// Anschaffung, nicht der Zahlung.
    func betriebsausgabe(in periode: Periode, abfluss: Bool = false) -> Decimal {
        if istAnlagegut { return afa(in: periode) }
        return periode.enthaelt(abfluss ? abflussdatum : datum) ? netto : 0
    }
}

/// Zeile des Anlagenverzeichnisses (Anlage AVEÜR): Anschaffung, Buchwert zu Jahresbeginn, AfA
/// des Jahres, Buchwert zum Jahresende.
struct Anlagegut: Hashable {
    var bezeichnung: String
    var angeschafft: Date
    var kosten: Decimal
    var nutzungsdauer: Int
    /// 0, wenn im Jahr angeschafft (dann steht der Zugang in `kosten`).
    var buchwertAnfang: Decimal
    var afa: Decimal
    var buchwertEnde: Decimal
    /// Im Jahr angeschafft?
    var zugang: Bool
}

extension Steuer {

    /// Anlagegüter, die im Jahr angeschafft oder noch abgeschrieben werden, nach Anschaffung.
    static func anlagen(_ ausgaben: [AusgabePosten], jahr: Int) -> [Anlagegut] {
        let p = Periode.jahr(jahr)
        return ausgaben.compactMap { a -> Anlagegut? in
            guard a.istAnlagegut, a.datum < p.bis else { return nil }
            let zugang = a.datum >= p.von
            let anfang = zugang ? 0 : a.netto - a.abgeschrieben(vor: p.von)
            if !zugang && anfang == 0 { return nil }  // schon ganz abgeschrieben
            return Anlagegut(
                bezeichnung: a.bezeichnung, angeschafft: a.datum, kosten: a.netto,
                nutzungsdauer: a.nutzungsdauer, buchwertAnfang: anfang, afa: a.afa(in: p),
                buchwertEnde: a.netto - a.abgeschrieben(vor: p.bis), zugang: zugang)
        }
        .sorted { ($0.angeschafft, $0.bezeichnung) < ($1.angeschafft, $1.bezeichnung) }
    }

    /// Summe der AfA aller Anlagegüter in der Periode.
    static func afa(_ ausgaben: [AusgabePosten], in periode: Periode) -> Decimal {
        ausgaben.filter(\.istAnlagegut).reduce(Decimal(0)) { $0 + $1.afa(in: periode) }
    }
}
