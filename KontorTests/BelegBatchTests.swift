import Testing
import Foundation
import SwiftData
@testable import Kontor

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
