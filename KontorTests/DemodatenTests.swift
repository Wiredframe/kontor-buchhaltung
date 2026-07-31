import Foundation
import SwiftData
import Testing

@testable import Kontor

@MainActor
struct DemodatenTests {
    /// Geteilt: siehe Testhelfer.swift (das Schema stand hier 5x wortgleich).
    private func container() throws -> ModelContainer { try testContainer() }

    @Test func einspielenFuelltLeerenStore() throws {
        let c = try container()
        #expect(Demodaten.istLeer(c.mainContext))
        Demodaten.einspielen(c.mainContext)
        #expect(!Demodaten.istLeer(c.mainContext))

        // Demo ist relativ zu heute: aktueller Monat + Vormonat → feste Anzahlen (unabhängig vom
        // Startzeitpunkt), nur YearSettings = 1 bzw. 2 am Jahreswechsel (Dez→Jan).
        let ctx = c.mainContext
        #expect((1...2).contains(try ctx.fetchCount(FetchDescriptor<YearSettings>())))
        #expect(try ctx.fetchCount(FetchDescriptor<Income>()) == 4)  // 1×19 % (Vor) + 1×7 % (Vor) + 1 Misch + 1×19 % (offen)
        #expect(try ctx.fetchCount(FetchDescriptor<ExpenseEntry>()) == 22)  // 2×(5 wiederk. betr. + 5 privat) + Laptop + Fachbuch 7 %
        #expect(try ctx.fetchCount(FetchDescriptor<GroceryEntry>()) == 4)  // 2 je Monat
        #expect(try ctx.fetchCount(FetchDescriptor<PurchaseEntry>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<TaxPayment>()) == 2)  // KSK je Monat
        #expect(try ctx.fetchCount(FetchDescriptor<MonthlyTask>()) == 3)
    }

    @Test func einspielenIstNoOpBeiBefuelltemStore() throws {
        let c = try container()
        Demodaten.einspielen(c.mainContext)
        let n = try c.mainContext.fetchCount(FetchDescriptor<Income>())
        Demodaten.einspielen(c.mainContext)  // zweiter Aufruf darf nichts doppeln (nur leerer Store)
        #expect(try c.mainContext.fetchCount(FetchDescriptor<Income>()) == n)
    }

    @Test func kskUndSollSindGesetzt() throws {
        let c = try container()
        Demodaten.einspielen(c.mainContext)
        let s = try #require(try c.mainContext.fetch(FetchDescriptor<YearSettings>()).first)
        #expect(s.ksk(monat: 1) == dez("420.00"))  // RV 230 + KV 130 + PV 60
        #expect(s.ksk(monat: 6) == dez("420.00"))  // erbt vom Januar
        // Eine offene und mehrere bezahlte Rechnungen vorhanden (Zufluss-/Soll-Logik testbar).
        let einnahmen = try c.mainContext.fetch(FetchDescriptor<Income>())
        #expect(einnahmen.contains { $0.status == .offen })
        #expect(einnahmen.contains { $0.status == .bezahlt })
    }
}
