import Foundation

/// Bundesland am Sitz des Finanzamts – entscheidet, welche Feiertage eine Frist verschieben.
/// Gespeichert als Kürzel (`rawValue`) in den App-Einstellungen; ohne Wahl gelten nur die
/// bundesweiten Feiertage.
enum Bundesland: String, CaseIterable, Identifiable {
    case bw = "BW", by = "BY", be = "BE", bb = "BB", hb = "HB", hh = "HH", he = "HE", mv = "MV"
    case ni = "NI", nw = "NW", rp = "RP", sl = "SL", sn = "SN", st = "ST", sh = "SH", th = "TH"

    var id: String { rawValue }

    var bezeichnung: String {
        switch self {
        case .bw: "Baden-Württemberg"
        case .by: "Bayern"
        case .be: "Berlin"
        case .bb: "Brandenburg"
        case .hb: "Bremen"
        case .hh: "Hamburg"
        case .he: "Hessen"
        case .mv: "Mecklenburg-Vorpommern"
        case .ni: "Niedersachsen"
        case .nw: "Nordrhein-Westfalen"
        case .rp: "Rheinland-Pfalz"
        case .sl: "Saarland"
        case .sn: "Sachsen"
        case .st: "Sachsen-Anhalt"
        case .sh: "Schleswig-Holstein"
        case .th: "Thüringen"
        }
    }

    /// Schlüssel der App-Einstellung (`@AppStorage`).
    static let einstellung = "bundeslandFinanzamt"
}

/// Eine gesetzliche Steuerfrist mit dem Tag, an dem sie tatsächlich endet.
struct Steuerfrist: Hashable, Identifiable {
    var titel: String
    /// Regulärer Termin (z. B. der 10.).
    var regulaer: Date
    /// Fristende nach §108 Abs. 3 AO (Wochenende/Feiertag → nächster Werktag).
    var ende: Date

    var id: String { titel + "\(ende.timeIntervalSinceReferenceDate)" }
    var verschoben: Bool { ende != regulaer }
}

/// Fristen nach §108 Abs. 3 AO: Fällt das Ende einer Frist auf einen Samstag, Sonntag oder
/// gesetzlichen Feiertag, endet sie mit dem nächsten Werktag. Gilt für Abgabe **und** Zahlung
/// (Vorbild: wiredframe `tax_engine.deadline`, dort fest für Bayern).
enum Fristen {

    /// Ostersonntag (gregorianisch, Gauß in der Fassung von Meeus).
    static func ostersonntag(_ jahr: Int) -> Date {
        let a = jahr % 19, b = jahr / 100, c = jahr % 100
        let d = b / 4, e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let monat = (h + l - 7 * m + 114) / 31
        let t = (h + l - 7 * m + 114) % 31 + 1
        return tag(jahr, monat, t)
    }

    private static func plus(_ datum: Date, _ tage: Int) -> Date {
        appKalender.date(byAdding: .day, value: tage, to: datum) ?? datum
    }

    /// Gesetzliche Feiertage des Jahres: bundesweit, dazu die des Landes. Feiertage, die nur in
    /// einzelnen Gemeinden gelten (Mariä Himmelfahrt in Bayern, Fronleichnam in Teilen Sachsens
    /// und Thüringens), fehlen bewusst – sie gelten nicht landesweit.
    static func feiertage(_ jahr: Int, land: Bundesland?) -> Set<Date> {
        let ostern = ostersonntag(jahr)
        var tage: Set<Date> = [
            tag(jahr, 1, 1), plus(ostern, -2), plus(ostern, 1), tag(jahr, 5, 1), plus(ostern, 39),
            plus(ostern, 50), tag(jahr, 10, 3), tag(jahr, 12, 25), tag(jahr, 12, 26),
        ]
        guard let land else { return tage }
        if [.bw, .by, .st].contains(land) { tage.insert(tag(jahr, 1, 6)) }
        if (land == .be && jahr >= 2019) || (land == .mv && jahr >= 2023) { tage.insert(tag(jahr, 3, 8)) }
        if [.bw, .by, .he, .nw, .rp, .sl].contains(land) { tage.insert(plus(ostern, 60)) }
        if land == .sl { tage.insert(tag(jahr, 8, 15)) }
        if land == .th && jahr >= 2019 { tage.insert(tag(jahr, 9, 20)) }
        let reformation: [Bundesland] = [.bb, .mv, .sn, .st, .th] + (jahr >= 2018 ? [.hb, .hh, .ni, .sh] : [])
        if reformation.contains(land) || jahr == 2017 { tage.insert(tag(jahr, 10, 31)) }
        if [.bw, .by, .nw, .rp, .sl].contains(land) { tage.insert(tag(jahr, 11, 1)) }
        if land == .sn {
            // Buß- und Bettag: Mittwoch vor dem 23. November.
            var d = tag(jahr, 11, 22)
            while appKalender.component(.weekday, from: d) != 4 { d = plus(d, -1) }
            tage.insert(d)
        }
        return tage
    }

    /// Fristende nach §108 Abs. 3 AO.
    static func ende(_ regulaer: Date, land: Bundesland?) -> Date {
        var d = appKalender.startOfDay(for: regulaer)
        var jahr = appKalender.component(.year, from: d)
        var frei = feiertage(jahr, land: land)
        while appKalender.isDateInWeekend(d) || frei.contains(d) {
            d = plus(d, 1)
            let j = appKalender.component(.year, from: d)
            if j != jahr {
                jahr = j
                frei = feiertage(j, land: land)
            }
        }
        return d
    }

    /// Voranmeldung samt Zahlung: am 10. nach Ablauf des Zeitraums, mit Dauerfristverlängerung
    /// einen Monat später (§18 Abs. 1, §46 UStDV). `bisMonat` ist der letzte Monat des Zeitraums.
    static func ustva(jahr: Int, bisMonat: Int, dauerfrist: Bool, land: Bundesland?, titel: String)
        -> Steuerfrist
    {
        let regulaer = tag(jahr, bisMonat, 10).addingMonths(dauerfrist ? 2 : 1)
        return Steuerfrist(titel: titel, regulaer: regulaer, ende: ende(regulaer, land: land))
    }

    /// Zusammenfassende Meldung: am 25. nach Quartalsende, **ohne** Dauerfristverlängerung (§18a UStG).
    static func zm(jahr: Int, quartal: Int, land: Bundesland?) -> Steuerfrist {
        let regulaer = tag(jahr, quartal * 3, 25).addingMonths(1)
        return Steuerfrist(titel: "ZM Q\(quartal) \(jahr)", regulaer: regulaer, ende: ende(regulaer, land: land))
    }

    /// ESt-Vorauszahlungen: 10.3., 10.6., 10.9., 10.12. (§37 Abs. 1 EStG).
    static func estVorauszahlungen(jahr: Int, land: Bundesland?) -> [Steuerfrist] {
        [3, 6, 9, 12].enumerated().map { i, m in
            let regulaer = tag(jahr, m, 10)
            return Steuerfrist(
                titel: "ESt-VZ Q\(i + 1) \(jahr)", regulaer: regulaer, ende: ende(regulaer, land: land))
        }
    }

    /// Die nächsten Fristen ab `heute` (einschließlich): UStVA nach Rhythmus und Dauerfrist des
    /// jeweiligen Jahres, ZM nur, wenn das Quartal etwas zu melden hat, ESt-Vorauszahlungen nur,
    /// wenn im Jahr oder Vorjahr welche geleistet bzw. erfasst wurden.
    static func naechste(
        heute: Date, einstellungen: (Int) -> (rhythmus: UStVARhythmus, dauerfrist: Bool),
        zmPflicht: (Int, Int) -> Bool, estVz: (Int) -> Bool, land: Bundesland?, anzahl: Int = 4
    ) -> [Steuerfrist] {
        let start = appKalender.startOfDay(for: heute)
        let jahr = appKalender.component(.year, from: start)
        var fristen: [Steuerfrist] = []
        for j in (jahr - 1)...(jahr + 1) {
            let e = einstellungen(j)
            switch e.rhythmus {
            case .monatlich:
                for m in 1...12 {
                    fristen.append(
                        ustva(
                            jahr: j, bisMonat: m, dauerfrist: e.dauerfrist, land: land,
                            titel: "UStVA \(monatsName(m)) \(j)"))
                }
            case .vierteljaehrlich:
                for q in 1...4 {
                    fristen.append(
                        ustva(jahr: j, bisMonat: q * 3, dauerfrist: e.dauerfrist, land: land, titel: "UStVA Q\(q) \(j)")
                    )
                }
            }
            for q in 1...4 where zmPflicht(j, q) { fristen.append(zm(jahr: j, quartal: q, land: land)) }
            if estVz(j) || estVz(j - 1) { fristen += estVorauszahlungen(jahr: j, land: land) }
        }
        return Array(fristen.filter { $0.ende >= start }.sorted { $0.ende < $1.ende }.prefix(anzahl))
    }
}

extension Date {
    fileprivate func addingMonths(_ n: Int) -> Date { monateNach(self, n) }
}
