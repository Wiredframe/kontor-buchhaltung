import Testing
import Foundation
import SwiftData
@testable import Kontor

@MainActor
struct DemodatenTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: YearSettings.self, ExpenseEntry.self, Vorlage.self,
                Income.self, MonthlyTask.self,
                GroceryEntry.self, PurchaseEntry.self, TaxPayment.self,
                ZuordnungsRegel.self, ImportBuchung.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func einspielenFuelltLeerenStore() throws {
        let c = try container()
        #expect(Demodaten.istLeer(c.mainContext))
        Demodaten.einspielen(c.mainContext)
        #expect(!Demodaten.istLeer(c.mainContext))

        let ctx = c.mainContext
        #expect(try ctx.fetchCount(FetchDescriptor<YearSettings>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<Income>()) == 8)   // 6 × 19 % + 1 × 7 % + 1 Mischrechnung
        #expect(try ctx.fetchCount(FetchDescriptor<ExpenseEntry>()) == 61)   // 30 betr. + 1 Anschaffung + 30 privat
        #expect(try ctx.fetchCount(FetchDescriptor<GroceryEntry>()) == 12)
        #expect(try ctx.fetchCount(FetchDescriptor<PurchaseEntry>()) == 3)
        #expect(try ctx.fetchCount(FetchDescriptor<TaxPayment>()) == 6)      // 5 KSK + 1 USt-VZ
        #expect(try ctx.fetchCount(FetchDescriptor<MonthlyTask>()) == 3)
    }

    @Test func einspielenIstNoOpBeiBefuelltemStore() throws {
        let c = try container()
        Demodaten.einspielen(c.mainContext)
        let n = try c.mainContext.fetchCount(FetchDescriptor<Income>())
        Demodaten.einspielen(c.mainContext)   // zweiter Aufruf darf nichts doppeln (nur leerer Store)
        #expect(try c.mainContext.fetchCount(FetchDescriptor<Income>()) == n)
    }

    @Test func kskUndSollSindGesetzt() throws {
        let c = try container()
        Demodaten.einspielen(c.mainContext)
        let s = try #require(try c.mainContext.fetch(FetchDescriptor<YearSettings>()).first)
        #expect(s.ksk(monat: 1) == dez("420.00"))   // RV 230 + KV 130 + PV 60
        #expect(s.ksk(monat: 6) == dez("420.00"))   // erbt vom Januar
        // Eine offene und mehrere bezahlte Rechnungen vorhanden (Zufluss-/Soll-Logik testbar).
        let einnahmen = try c.mainContext.fetch(FetchDescriptor<Income>())
        #expect(einnahmen.contains { $0.status == .offen })
        #expect(einnahmen.contains { $0.status == .bezahlt })
    }
}
