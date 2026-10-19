import Foundation
import Testing

@testable import Kontor

/// Fristen nach §108 Abs. 3 AO – gegen den Kalender nachrechenbar.
struct FristenTests {

    @Test func ostersonntag() {
        #expect(Fristen.ostersonntag(2024) == tag(2024, 3, 31))
        #expect(Fristen.ostersonntag(2025) == tag(2025, 4, 20))
        #expect(Fristen.ostersonntag(2026) == tag(2026, 4, 5))
        #expect(Fristen.ostersonntag(2027) == tag(2027, 3, 28))
    }

    @Test func feiertageJeLand() {
        let bund = Fristen.feiertage(2026, land: nil)
        #expect(bund.count == 9)
        #expect(bund.contains(tag(2026, 4, 3)))  // Karfreitag
        #expect(bund.contains(tag(2026, 5, 14)))  // Christi Himmelfahrt
        #expect(!bund.contains(tag(2026, 1, 6)))
        #expect(Fristen.feiertage(2026, land: .by).contains(tag(2026, 1, 6)))
        #expect(Fristen.feiertage(2026, land: .by).contains(tag(2026, 6, 4)))  // Fronleichnam
        #expect(Fristen.feiertage(2026, land: .be).contains(tag(2026, 3, 8)))
        #expect(!Fristen.feiertage(2018, land: .be).contains(tag(2018, 3, 8)))
        #expect(Fristen.feiertage(2026, land: .sn).contains(tag(2026, 11, 18)))  // Buß- und Bettag
        #expect(Fristen.feiertage(2026, land: .ni).contains(tag(2026, 10, 31)))
        #expect(Fristen.feiertage(2017, land: .by).contains(tag(2017, 10, 31)))  // 500 Jahre Reformation
    }

    @Test func wochenendeUndFeiertagVerschieben() {
        // 10.01.2026 ist ein Samstag → Montag, 12.01.
        #expect(Fristen.ende(tag(2026, 1, 10), land: nil) == tag(2026, 1, 12))
        // 10.05.2026 ist ein Sonntag → Montag, 11.05.
        #expect(Fristen.ende(tag(2026, 5, 10), land: nil) == tag(2026, 5, 11))
        // Werktag bleibt.
        #expect(Fristen.ende(tag(2026, 2, 10), land: nil) == tag(2026, 2, 10))
        // 06.01.2027 (Mittwoch) ist nur in Bayern frei.
        #expect(Fristen.ende(tag(2027, 1, 6), land: .by) == tag(2027, 1, 7))
        #expect(Fristen.ende(tag(2027, 1, 6), land: .nw) == tag(2027, 1, 6))
        // Über den Jahreswechsel: 26.12.2026 Samstag, 27. Sonntag → Montag 28.12.
        #expect(Fristen.ende(tag(2026, 12, 25), land: nil) == tag(2026, 12, 28))
    }

    @Test func ustvaUndZM() {
        // Q4 2025 ohne Dauerfrist: 10.01.2026 (Samstag) → 12.01.
        let q4 = Fristen.ustva(jahr: 2025, bisMonat: 12, dauerfrist: false, land: nil, titel: "Q4")
        #expect(q4.regulaer == tag(2026, 1, 10) && q4.ende == tag(2026, 1, 12) && q4.verschoben)
        // Mit Dauerfristverlängerung einen Monat später: 10.02.2026 (Dienstag).
        let q4d = Fristen.ustva(jahr: 2025, bisMonat: 12, dauerfrist: true, land: nil, titel: "Q4")
        #expect(q4d.ende == tag(2026, 2, 10) && !q4d.verschoben)
        // Monatlich September mit Dauerfrist: 10.11.
        #expect(
            Fristen.ustva(jahr: 2026, bisMonat: 9, dauerfrist: true, land: nil, titel: "").ende == tag(2026, 11, 10))
        // ZM Q3 2026: 25.10.2026 ist ein Sonntag → 26.10.
        #expect(Fristen.zm(jahr: 2026, quartal: 3, land: nil).ende == tag(2026, 10, 26))
    }

    @Test func naechsteFristenSortiertUndGefiltert() {
        let f = Fristen.naechste(
            heute: tag(2026, 10, 19), einstellungen: { _ in (.vierteljaehrlich, false) },
            zmPflicht: { j, q in j == 2026 && q == 3 }, estVz: { $0 == 2025 }, land: nil, anzahl: 3)
        // UStVA Q3 endete am 12.10. (10.10. Samstag). Offen: ZM Q3 (26.10.), ESt-VZ Q4 (10.12.),
        // UStVA Q4 (10.01.2027 ist ein Sonntag → 11.01.).
        #expect(f.map(\.titel) == ["ZM Q3 2026", "ESt-VZ Q4 2026", "UStVA Q4 2026"])
        #expect(f.last?.ende == tag(2027, 1, 11))
        let ohne = Fristen.naechste(
            heute: tag(2026, 10, 19), einstellungen: { _ in (.vierteljaehrlich, false) },
            zmPflicht: { _, _ in false }, estVz: { _ in false }, land: nil, anzahl: 2)
        #expect(ohne.map(\.titel) == ["UStVA Q4 2026", "UStVA Q1 2027"])
    }
}
