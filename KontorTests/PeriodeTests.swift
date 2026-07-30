import Foundation
import Testing

@testable import Kontor

// MARK: - Periode: Grenzen, Jahreswechsel, Schaltjahr + Härtung gegen extreme Jahre

/// `Periode` ist das halboffene Intervall [von, bis), auf dem die ganze Zeitraum-Zuordnung
/// (UStVA-Quartal, Monatsauswertung, EÜR-Jahr) sitzt. Zuvor nur indirekt getestet; hier
/// direkt inklusive der Ränder und der Force-Unwrap-Härtung aus `tag`/`monateNach`.
struct PeriodeTests {

    @Test func monatGrenzenHalboffen() {
        let p = Periode.monat(2026, 1)
        #expect(p.von == tag(2026, 1, 1))
        #expect(p.bis == tag(2026, 2, 1))
        #expect(p.enthaelt(tag(2026, 1, 1)))  // von inklusive
        #expect(p.enthaelt(tag(2026, 1, 31)))
        #expect(!p.enthaelt(tag(2026, 2, 1)))  // bis exklusive
    }

    @Test func monatJahreswechsel() {
        let dez = Periode.monat(2026, 12)
        #expect(dez.bis == tag(2027, 1, 1))
        #expect(dez.enthaelt(tag(2026, 12, 31)))
        #expect(!dez.enthaelt(tag(2027, 1, 1)))
    }

    @Test func schaltjahrFebruar() {
        let feb = Periode.monat(2024, 2)
        #expect(feb.enthaelt(tag(2024, 2, 29)))  // 2024 ist Schaltjahr
        #expect(feb.bis == tag(2024, 3, 1))
    }

    @Test func quartalQ1UndQ4() {
        let q1 = Periode.quartal(2026, 1)
        #expect(q1.von == tag(2026, 1, 1))
        #expect(q1.bis == tag(2026, 4, 1))

        let q4 = Periode.quartal(2026, 4)
        #expect(q4.von == tag(2026, 10, 1))
        #expect(q4.bis == tag(2027, 1, 1))  // Jahreswechsel
        #expect(q4.enthaelt(tag(2026, 12, 31)))
        #expect(!q4.enthaelt(tag(2027, 1, 1)))
    }

    @Test func jahrGrenzen() {
        let j = Periode.jahr(2026)
        #expect(j.von == tag(2026, 1, 1))
        #expect(j.bis == tag(2027, 1, 1))
        #expect(j.enthaelt(tag(2026, 12, 31)))
        #expect(!j.enthaelt(tag(2027, 1, 1)))
    }

    // MARK: Härtung (Phase 4): extreme/korrupte Jahre klemmen statt zu crashen

    @Test func tagKlemmtExtremeJahre() {
        // klemmeJahr: unter 1 -> 1, ueber 9999 -> 9999. Deterministisch, kein Absturz.
        #expect(tag(999_999, 1, 1) == tag(9999, 1, 1))
        #expect(tag(-100, 1, 1) == tag(1, 1, 1))
        #expect(tag(Int.min, 6, 15) == tag(1, 6, 15))
        // Innerhalb des Bereichs bleibt alles unveraendert.
        #expect(tag(2026, 3, 10) == tag(2026, 3, 10))
    }

    @Test func periodeMitExtrememJahrOhneCrash() {
        // Vor der Haertung war das ein Force-Unwrap-Crash. Jetzt liefert es eine
        // wohlgeformte (geklemmte) Periode, ohne die App abzuschiessen.
        let p = Periode.monat(999_999, 12)
        #expect(p.von == tag(9999, 12, 1))
        #expect(p.bis > p.von)  // wohlgeformtes Intervall
        _ = Periode.jahr(Int.min)  // darf nicht crashen
        _ = Periode.quartal(Int.max, 4)  // darf nicht crashen
    }

    @Test func monateNachVorwaertsUndRueckwaerts() {
        #expect(monateNach(tag(2026, 1, 1), 1) == tag(2026, 2, 1))
        #expect(monateNach(tag(2026, 1, 1), -1) == tag(2025, 12, 1))
        #expect(monateNach(tag(2026, 1, 15), 12) == tag(2027, 1, 15))
        #expect(monateNach(tag(2026, 3, 31), 1) == tag(2026, 4, 30))  // rollt auf gueltigen Tag
    }
}
