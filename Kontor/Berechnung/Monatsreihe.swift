import Foundation

/// Monatsreihe eines Jahres für den Trend-Chart – rein rechnend, ohne SwiftUI und ohne SwiftData.
///
/// Rechnet nichts selbst: der Gewinn-Waterfall liegt in `MonatsAuswertung`, hier wird nur über
/// die zwölf Monate iteriert und das Ergebnis auf die im Chart darstellbaren Kennzahlen reduziert.
enum Monatsreihe {

    /// Ein Monat der Jahresreihe.
    ///
    /// `frei` ist als einzige Kennzahl **optional**: nur sie hängt an den privaten Ausgaben
    /// (Lebensmittel, Anschaffungen, private Fixkosten). Aufrufer, die diese Daten nicht laden
    /// (der Jahresabschluss zeigt nur den Gewinn), bekommen `nil` statt eines still zu hohen
    /// Werts. Die Steuerrücklage kommt dagegen ohne Privatdaten aus (USt-Zahllast + KSK + ESt).
    struct Punkt: Hashable {
        var monat: Int
        var rn: Decimal
        var gewinn: Decimal
        var steuerRuecklage: Decimal
        var frei: Decimal?
    }

    /// Punkte für Januar bis Dezember; **Zukunftsmonate werden ausgelassen**, damit der Chart
    /// keine 0-Balken für noch nicht gelebte Monate zeigt.
    ///
    /// `fixkostenPrivat`/`privatVariabel` sind optional. Fehlen **beide**, bleibt `frei` der
    /// Punkte `nil`, statt einen ohne Privatkosten viel zu hohen Wert vorzutäuschen.
    static func jahr(
        _ jahr: Int,
        einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten],
        kskFuer: (Int, Int) -> Decimal, satzFuer: (Int, Int) -> Decimal,
        fixkostenPrivat: ((Int) -> Decimal)? = nil,
        privatVariabel: ((Int) -> Decimal)? = nil,
        heute: Date = Date()
    ) -> [Punkt] {
        let mitPrivat = fixkostenPrivat != nil || privatVariabel != nil
        return (1...12).compactMap { m in
            guard !istZukunftsmonat(m, jahr: jahr, heute: heute) else { return nil }
            let a = Steuer.monatsauswertung(
                monat: m, jahr: jahr, einnahmen: einnahmen, ausgaben: ausgaben,
                kskFuer: kskFuer,
                fixkostenPrivat: fixkostenPrivat?(m) ?? 0,
                privatVariabel: privatVariabel?(m) ?? 0,
                pauschalSatz: satzFuer)
            return Punkt(
                monat: m, rn: a.rn, gewinn: a.betrieblicherGewinn,
                steuerRuecklage: a.steuerRuecklage,
                frei: mitPrivat ? a.verfuegbar : nil)
        }
    }
}
