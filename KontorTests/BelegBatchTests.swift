import Testing
import Foundation
import SwiftData
@testable import Kontor

/// Regression: Die OCR läuft asynchron, das Formular ist ab dem ersten Moment editierbar
/// (`ladeAlle` setzt `aktiv` vor dem `await`). Das eintreffende Ergebnis überschrieb
/// kommentarlos alles, was der Nutzer in der Zwischenzeit getippt hatte – am schlimmsten
/// `brutto = d.brutto ?? 0`, das seinen Betrag selbst dann auf 0 setzte, wenn die OCR gar
/// nichts erkannt hatte.
struct BelegEntwurfOCRTests {
    private func entwurf() -> BelegEntwurf {
        BelegEntwurf(url: URL(fileURLWithPath: "/tmp/RE-Test.pdf"))
    }

    @Test func ocrUeberschreibtGetippteAusgabeNicht() {
        let e = entwurf()
        e.bezeichnung = "Hotel Berlin"          // Nutzer tippt, während die OCR läuft
        e.brutto = dez("238")
        e.vst = dez("38")
        e.fuelle(BelegDaten(anbieter: "Hotal Berlni", datum: tag(2026, 6, 12),
                            brutto: dez("23.80"), vst: dez("3.80"), steuerart: .inland7,
                            rechnungsnummer: "RE-1"))
        #expect(e.bezeichnung == "Hotel Berlin")   // nicht die schlechte OCR-Lesung
        #expect(e.brutto == dez("238"))
        #expect(e.vst == dez("38"))
        #expect(e.rechnungsnummer == "RE-1")       // leeres Feld wird sehr wohl gefüllt
    }

    /// Der schlimmste Fall: OCR erkennt den Betrag NICHT – vorher wurde die Eingabe auf 0 genullt.
    @Test func ocrOhneBetragNulltDieEingabeNicht() {
        let e = entwurf()
        e.brutto = dez("238")
        e.fuelle(BelegDaten(anbieter: nil, datum: nil, brutto: nil, vst: nil,
                            steuerart: nil, rechnungsnummer: nil))
        #expect(e.brutto == dez("238"))
    }

    @Test func ocrUeberschreibtGetippteEinnahmeNicht() {
        let e = entwurf()
        e.kunde = "Kranzler Digital GmbH"
        e.rnNetto = dez("4000")
        e.fuelle(EinnahmeDaten(kunde: "Kranzier Digitai", datum: tag(2026, 6, 12),
                               rnNetto: dez("400"), ust: dez("76"), rechnungsnummer: "R-9"))
        #expect(e.kunde == "Kranzler Digital GmbH")
        #expect(e.rnNetto == dez("4000"))
        #expect(e.ust == dez("76"))            // war leer → OCR füllt
        #expect(e.rechnungsnummer == "R-9")
    }

    /// Gegenprobe: Ein unberührter Entwurf wird vollständig aus der OCR gefüllt.
    @Test func unberuehrterEntwurfWirdVollGefuellt() {
        let e = entwurf()
        e.fuelle(BelegDaten(anbieter: "Figma", datum: tag(2026, 6, 12), brutto: dez("35"),
                            vst: 0, steuerart: .reverseCharge, rechnungsnummer: "F-1"))
        #expect(e.bezeichnung == "Figma")
        #expect(e.anbieter == "Figma")
        #expect(e.brutto == dez("35"))
        #expect(e.steuerart == .reverseCharge)
        #expect(e.datum == tag(2026, 6, 12))   // Datum war unberührt → OCR-Datum gewinnt
    }

    /// Ein selbst gesetztes Datum bleibt stehen.
    @Test func ocrUeberschreibtGesetztesDatumNicht() {
        let e = entwurf()
        e.datum = tag(2026, 3, 1)
        e.fuelle(BelegDaten(anbieter: "Figma", datum: tag(2026, 6, 12), brutto: dez("35"),
                            vst: 0, steuerart: .reverseCharge, rechnungsnummer: nil))
        #expect(e.datum == tag(2026, 3, 1))
    }
}

@MainActor
struct BelegBatchTests {
    /// Geteilt: siehe Testhelfer.swift (das Schema stand hier 5x wortgleich).
    private func container() throws -> ModelContainer { try testContainer() }

    private func ausgabeEntwurf(_ bez: String, _ brutto: String) -> BelegEntwurf {
        let e = BelegEntwurf(url: URL(fileURLWithPath: "/tmp/\(bez).pdf"))
        e.bezeichnung = bez; e.anbieter = bez
        e.brutto = dez(brutto); e.vst = 0; e.steuerart = .reverseCharge
        e.datum = tag(2026, 6, 28)
        return e
    }

    /// Versehentlich „Zusammenführen", dann „Trotzdem neu anlegen": es muss ein eigener Eintrag
    /// entstehen (Merge hängt nur den Beleg an, blockiert die Neuanlage nicht).
    @Test func zusammenfuehrenDannTrotzdemNeuAnlegen() throws {
        let c = try container()
        let claude = ExpenseEntry(datum: tag(2026, 6, 28), bezeichnung: "Claude Pro", anbieter: "Anthropic",
                                  brutto: dez("18"), vst: 0, steuerart: .reverseCharge)
        c.mainContext.insert(claude); try c.mainContext.save()

        let e = ausgabeEntwurf("Figma", "18")
        e.dublette = claude.persistentModelID

        // 1) versehentlich zusammenführen → kein eigener Eintrag, Beleg hängt an Claude Pro
        e.zusammenfuehren(modus: .ausgabe, in: c.mainContext); try c.mainContext.save()
        #expect(e.ausgabe == nil)
        #expect(try c.mainContext.fetchCount(FetchDescriptor<ExpenseEntry>()) == 1)

        // 2) zurück und „Trotzdem neu anlegen" → eigener Figma-Eintrag entsteht
        e.anlegenOderAktualisieren(modus: .ausgabe, in: c.mainContext); try c.mainContext.save()
        let ausgaben = try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>())
        #expect(ausgaben.count == 2)
        #expect(ausgaben.contains { $0.bezeichnung == "Figma" && $0.brutto == dez("18") })
    }

    /// Idempotenz: erneutes Bestätigen desselben Entwurfs aktualisiert den Eintrag, statt einen
    /// zweiten anzulegen (verhindert Mehrfach-/0-€-Spam bei wiederholtem Enter).
    @Test func wiederholtesAnlegenAktualisiertNur() throws {
        let c = try container()
        let e = ausgabeEntwurf("Hosting", "0")          // Betrag fehlt zunächst
        e.anlegenOderAktualisieren(modus: .ausgabe, in: c.mainContext); try c.mainContext.save()
        #expect(try c.mainContext.fetchCount(FetchDescriptor<ExpenseEntry>()) == 1)

        e.brutto = dez("50")                            // Betrag nachgetragen, erneut bestätigt
        e.anlegenOderAktualisieren(modus: .ausgabe, in: c.mainContext); try c.mainContext.save()
        let ausgaben = try c.mainContext.fetch(FetchDescriptor<ExpenseEntry>())
        #expect(ausgaben.count == 1)                    // kein zweiter Eintrag
        #expect(ausgaben.first?.brutto == dez("50"))    // aktualisiert
    }
}
