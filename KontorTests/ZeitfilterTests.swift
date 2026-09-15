import Foundation
import Testing

@testable import Kontor

// MARK: - Zeitfilter: Start-Zustand und Zeitraum-Zuordnung

/// Der `Zeitfilter` ist der geteilte Zeitraum aller Tabellen-Views (Einnahmen, Ausgaben,
/// Lebensmittel, Anschaffungen, Aufgaben). Sein Default ist der Zustand beim App-Start,
/// weil `Zeitkontext` genau einmal in `ContentView` erzeugt wird – deshalb hier festgenagelt.
struct ZeitfilterTests {

    @Test func startetImAktuellenMonat() {
        let f = Zeitfilter()
        let heute = Date()
        #expect(f.modus == .monat)
        #expect(f.jahr == appKalender.component(.year, from: heute))
        #expect(f.monat == appKalender.component(.month, from: heute))
        #expect(f.istAktuellerMonat)
        #expect(f.enthaelt(heute))
    }

    @Test func monatsmodusSchliesstNachbarmonateAus() {
        var f = Zeitfilter()
        f.modus = .monat
        f.jahr = 2026
        f.monat = 3
        #expect(f.enthaelt(tag(2026, 3, 1)))
        #expect(f.enthaelt(tag(2026, 3, 31)))
        #expect(!f.enthaelt(tag(2026, 2, 28)))
        #expect(!f.enthaelt(tag(2026, 4, 1)))
        #expect(!f.enthaelt(tag(2025, 3, 15)))
        #expect(!f.istAktuellerMonat)
    }

    @Test func jahrUndAlleIgnorierenDenMonat() {
        var f = Zeitfilter()
        f.modus = .jahr
        f.jahr = 2026
        f.monat = 3
        #expect(f.enthaelt(tag(2026, 11, 4)))
        #expect(!f.enthaelt(tag(2027, 1, 1)))
        #expect(!f.istAktuellerMonat)  // „Heute"-Button bleibt im Jahres-Modus aktiv

        f.modus = .alle
        #expect(f.enthaelt(tag(1999, 7, 1)))
    }

    @Test func aufAktuellenMonatSetztAlleDreiFelder() {
        var f = Zeitfilter()
        f.modus = .alle
        f.jahr = 2019
        f.monat = 7
        f.aufAktuellenMonat()
        #expect(f.istAktuellerMonat)
        #expect(f.modus == .monat)
        #expect(f.jahr == appKalender.component(.year, from: Date()))
        #expect(f.monat == appKalender.component(.month, from: Date()))
    }

    // MARK: Quartals-Modus

    @Test func quartalsmodusUmfasstGenauDreiMonate() {
        var f = Zeitfilter()
        f.modus = .quartal
        f.jahr = 2026
        f.quartal = 3
        #expect(f.enthaelt(tag(2026, 7, 1)))
        #expect(f.enthaelt(tag(2026, 8, 15)))
        #expect(f.enthaelt(tag(2026, 9, 30)))
        #expect(!f.enthaelt(tag(2026, 6, 30)))
        #expect(!f.enthaelt(tag(2026, 10, 1)))
    }

    /// Die Invariante, auf die sich Monatsabschluss und Privat-Uebersicht verlassen: Sie lesen
    /// `monat` **direkt**, ohne den Modus anzusehen. Im Quartals-Modus muss dort deshalb eine
    /// gueltige Monatszahl stehen, nicht die Quartalsnummer.
    @Test func quartalHaeltDenMonatAufDemQuartalsanfang() {
        var f = Zeitfilter()
        f.modus = .quartal
        for (q, m) in [(1, 1), (2, 4), (3, 7), (4, 10)] {
            f.quartal = q
            #expect(f.monat == m)
            #expect(f.quartal == q)
        }
    }

    /// `quartal` ist aus `monat` abgeleitet, nicht getrennt gespeichert.
    @Test func quartalFolgtDemGesetztenMonat() {
        var f = Zeitfilter()
        for (m, q) in [(1, 1), (3, 1), (4, 2), (6, 2), (7, 3), (9, 3), (10, 4), (12, 4)] {
            f.monat = m
            #expect(f.quartal == q)
        }
    }

    // MARK: Periodenschritte

    @Test func pfeileSchiebenInDerGranularitaetDesModus() {
        var f = Zeitfilter(modus: .monat, jahr: 2026, monat: 5)
        f.vor()
        #expect(f.monat == 6 && f.jahr == 2026)
        f.zurueck()
        #expect(f.monat == 5 && f.jahr == 2026)

        f.modus = .quartal
        f.quartal = 2
        f.vor()
        #expect(f.quartal == 3 && f.monat == 7)
        f.zurueck()
        #expect(f.quartal == 2 && f.monat == 4)

        f.modus = .jahr
        f.vor()
        #expect(f.jahr == 2027)
        f.zurueck()
        #expect(f.jahr == 2026)
    }

    @Test func monatsschrittUeberDieJahresgrenze() {
        var f = Zeitfilter(modus: .monat, jahr: 2026, monat: 12)
        f.vor()
        #expect(f.jahr == 2027 && f.monat == 1)

        f = Zeitfilter(modus: .monat, jahr: 2026, monat: 1)
        f.zurueck()
        #expect(f.jahr == 2025 && f.monat == 12)
    }

    @Test func quartalsschrittUeberDieJahresgrenze() {
        var f = Zeitfilter(modus: .quartal, jahr: 2026, monat: 10)
        #expect(f.quartal == 4)
        f.vor()
        #expect(f.jahr == 2027 && f.quartal == 1 && f.monat == 1)
        f.zurueck()
        #expect(f.jahr == 2026 && f.quartal == 4 && f.monat == 10)
    }

    /// „Gesamt" hat keine Nachbarperiode – die Pfeile duerfen dort nichts tun (die UI stellt sie
    /// zusaetzlich inaktiv).
    @Test func gesamtModusKenntKeineNachbarperiode() {
        var f = Zeitfilter(modus: .alle, jahr: 2026, monat: 5)
        f.vor()
        f.zurueck()
        #expect(f.modus == .alle && f.jahr == 2026 && f.monat == 5)
        #expect(f.enthaelt(tag(1999, 7, 1)))
    }

    // MARK: Beschriftung

    @Test func beschriftungProModus() {
        var f = Zeitfilter(modus: .monat, jahr: 2026, monat: 9)
        #expect(f.beschriftung == "September 2026")
        f.modus = .quartal
        #expect(f.beschriftung == "Q3 2026")
        f.modus = .jahr
        #expect(f.beschriftung == "2026")
        f.modus = .alle
        #expect(f.beschriftung == "Gesamt")
        // Kein Tausenderpunkt in der Jahreszahl (String(jahr), nicht "\(jahr)" ueber ein Format).
        #expect(!f.beschriftung.contains("."))
    }

    // MARK: Vorberechnete Periode

    /// Die `periode` ist gecacht – sie muss nach **jeder** einzelnen Aenderung stimmen, sonst
    /// filtert die halbe App nach einem veralteten Zeitraum.
    @Test func periodeStimmtNachJederEinzelnenAenderung() {
        var f = Zeitfilter(modus: .monat, jahr: 2026, monat: 3)
        #expect(f.periode == Periode.monat(2026, 3))
        f.monat = 7
        #expect(f.periode == Periode.monat(2026, 7))
        f.jahr = 2027
        #expect(f.periode == Periode.monat(2027, 7))
        f.modus = .quartal
        #expect(f.periode == Periode.quartal(2027, 3))
        f.quartal = 1
        #expect(f.periode == Periode.quartal(2027, 1))
        f.modus = .jahr
        #expect(f.periode == Periode.jahr(2027))
        f.modus = .alle
        #expect(f.periode == nil)
    }

    @Test func enthaeltAnDenPeriodengrenzen() {
        var f = Zeitfilter(modus: .jahr, jahr: 2026, monat: 1)
        #expect(f.enthaelt(tag(2026, 1, 1)))
        #expect(f.enthaelt(tag(2026, 12, 31)))
        #expect(!f.enthaelt(tag(2027, 1, 1)))
        #expect(!f.enthaelt(tag(2025, 12, 31)))

        // Schaltjahr: der 29. Februar gehoert in den Februar, nicht in den Maerz.
        f.modus = .monat
        f.jahr = 2028
        f.monat = 2
        #expect(f.enthaelt(tag(2028, 2, 29)))
        #expect(!f.enthaelt(tag(2028, 3, 1)))
    }

    // MARK: Schnellwahl

    @Test func presetsRechnenUeberDenJahreswechsel() {
        let jan = tag(2026, 1, 15)
        #expect(letzterMonatIst(2025, 12, heute: jan))

        let feb = tag(2026, 2, 15)
        let lq = Zeitfilter.letztesQuartal(heute: feb)
        #expect(lq.modus == .quartal && lq.jahr == 2025 && lq.quartal == 4)

        let lj = Zeitfilter.letztesJahr(heute: feb)
        #expect(lj.modus == .jahr && lj.jahr == 2025)

        let dq = Zeitfilter.diesesQuartal(heute: feb)
        #expect(dq.modus == .quartal && dq.jahr == 2026 && dq.quartal == 1 && dq.monat == 1)

        #expect(Zeitfilter.gesamt.modus == .alle)
    }

    private func letzterMonatIst(_ jahr: Int, _ monat: Int, heute: Date) -> Bool {
        let f = Zeitfilter.letzterMonat(heute: heute)
        return f.modus == .monat && f.jahr == jahr && f.monat == monat
    }

    /// `diesesQuartal` muss den Monat auf den Quartalsanfang ruecken, egal an welchem Tag im
    /// Quartal man es aufruft.
    @Test func diesesQuartalRuecktAufDenQuartalsanfang() {
        for (m, erwartet) in [(1, 1), (2, 1), (3, 1), (8, 7), (11, 10), (12, 10)] {
            let f = Zeitfilter.diesesQuartal(heute: tag(2026, m, 20))
            #expect(f.monat == erwartet)
        }
    }

    // MARK: Umfang

    @Test func begrenzeAufNormalisiertNurAusserhalbDesUmfangs() {
        // Monat/Jahr bleiben im Umfang .monatJahr unveraendert.
        var f = Zeitfilter(modus: .monat, jahr: 2026, monat: 5)
        f.begrenzeAuf(.monatJahr)
        #expect(f.modus == .monat && f.monat == 5)

        f = Zeitfilter(modus: .jahr, jahr: 2026, monat: 5)
        f.begrenzeAuf(.monatJahr)
        #expect(f.modus == .jahr)

        // Quartal wird zum Monat – und zwar zum ersten Monat des Quartals.
        f = Zeitfilter(modus: .quartal, jahr: 2026, monat: 8)
        f.quartal = 3
        f.begrenzeAuf(.monatJahr)
        #expect(f.modus == .monat && f.monat == 7)

        // Gesamt wird zum Jahr.
        f = Zeitfilter(modus: .alle, jahr: 2026, monat: 5)
        f.begrenzeAuf(.monatJahr)
        #expect(f.modus == .jahr)

        // .nurJahr zieht alles auf das Jahr.
        for m in [Zeitfilter.Modus.alle, .monat, .quartal, .jahr] {
            var g = Zeitfilter(modus: m, jahr: 2026, monat: 5)
            g.begrenzeAuf(.nurJahr)
            #expect(g.modus == .jahr)
        }

        // .voll laesst jeden Modus stehen.
        for m in [Zeitfilter.Modus.alle, .monat, .quartal, .jahr] {
            var g = Zeitfilter(modus: m, jahr: 2026, monat: 5)
            g.begrenzeAuf(.voll)
            #expect(g.modus == m)
        }
    }

    @Test func erlaubtMeldetDieAngeboteneGranularitaet() {
        #expect(Zeitfilter.erlaubt(.quartal, in: .voll))
        #expect(!Zeitfilter.erlaubt(.quartal, in: .monatJahr))
        #expect(!Zeitfilter.erlaubt(.alle, in: .monatJahr))
        #expect(Zeitfilter.erlaubt(.monat, in: .monatJahr))
        #expect(Zeitfilter.erlaubt(.jahr, in: .nurJahr))
        #expect(!Zeitfilter.erlaubt(.monat, in: .nurJahr))
    }
}
