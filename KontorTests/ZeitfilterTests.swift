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
}
