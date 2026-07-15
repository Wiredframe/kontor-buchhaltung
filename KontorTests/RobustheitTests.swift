import Testing
import Foundation
@testable import Kontor

/// Robustheit/Sicherheit: Beleg-Pfad-Guard (Defense-in-Depth) und Engine-Verhalten bei
/// komplett leeren Daten (Leerzustand des frischen Stores).
struct RobustheitTests {

    // MARK: - Beleg-Pfade dürfen nicht aus dem Belege-Ordner ausbrechen

    @Test func belegPfadBleibtImOrdner() {
        let basis = Belege.basis.standardizedFileURL.path
        // Normaler relativer Pfad → innerhalb der Basis.
        #expect(Belege.url(fuer: "2026/rechnung.pdf").path.hasPrefix(basis + "/"))
        // Traversal / absoluter Pfad → kein Ausbruch (bleibt unter der Basis).
        #expect(Belege.url(fuer: "../../etc/passwd").path.hasPrefix(basis + "/"))
        #expect(Belege.url(fuer: "/etc/passwd").path.hasPrefix(basis + "/"))
        // Ein Traversal-Pfad zeigt auf nichts Existierendes.
        #expect(Belege.existiert("../../etc/passwd") == false)
    }

    // MARK: - Engine bei leeren Daten (keine Crashes, alles 0)

    @Test func ustvaLeerLiefertNull() {
        let e = Steuer.ustva(einnahmen: [], ausgaben: [], periode: Periode.quartal(2026, 1))
        #expect(e.kz81 == 0 && e.ust81 == 0 && e.kz86 == 0 && e.ust86 == 0 && e.kz66 == 0 && e.kz84 == 0 && e.kz85 == 0)
        #expect(e.zahllast == 0)
    }

    @Test func euerUndRuecklageLeerLiefertNull() {
        #expect(Steuer.euerGewinn(einnahmen: [], ausgaben: [], jahr: 2026) == 0)
        #expect(Steuer.estRuecklageJahr(jahr: 2026, einnahmen: [], ausgaben: [],
                                        kskFuer: { _, _ in 0 }, pauschalSatz: { _, _ in dez("0.15") }) == 0)
        #expect(Steuer.ustZahllastJahr(jahr: 2026, einnahmen: [], ausgaben: []) == 0)
    }

    /// Ein Ausfall ohne Nettobetrag darf nichts auflösen – und vor allem kein NaN erzeugen:
    /// Die anteilige Auflösung teilt durch den Soll-Umsatz des Rechnungsmonats, und
    /// `Decimal`-Division durch 0 trappt nicht, sondern liefert stillschweigend NaN.
    @Test func ausfallOhneNettobetragLoestNichtsAufUndErzeugtKeinNaN() {
        let einnahmen = [EinnahmePosten(rnNetto: 0, ust: 0, rechnungsdatum: tag(2026, 5, 10),
            zahlungsdatum: nil, status: .ausgefallen, ausfalldatum: tag(2026, 8, 15))]
        let a = Steuer.monatsauswertung(monat: 8, jahr: 2026, einnahmen: einnahmen, ausgaben: [],
            kskFuer: { _, _ in 0 }, fixkostenPrivat: 0, pauschalSatz: { _, _ in dez("0.15") })
        #expect(a.estKorrektur == 0)
        #expect(a.estKorrektur.isNaN == false)
        #expect(a.steuerRuecklage.isNaN == false)
    }

    /// Ohne hinterlegte YearSettings liefern die Array-Helfer sichere Defaults (kein Crash).
    @Test func jahreloseDefaults() {
        let keine: [YearSettings] = []
        #expect(keine.ksk(jahr: 2026, monat: 3) == 0)
        #expect(keine.estSatz(jahr: 2026, monat: 3) == dez("0.15"))   // Fallback 15 %
    }
}
