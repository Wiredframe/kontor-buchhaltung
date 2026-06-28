import Testing
import Foundation
import SwiftData
@testable import Kontor

struct TaskVorlagenTests {
    private func ymd(_ d: Date) -> [Int] {
        let c = appKalender.dateComponents([.year, .month, .day], from: d)
        return [c.year!, c.month!, c.day!]
    }

    @Test func naechsteFaelligkeitMonatlich() {
        let d = TaskVorlagen.naechsteFaelligkeit(intervall: .monatlich, faelligTag: 1, monate: [], ab: tag(2026, 6, 24))
        #expect(ymd(d) == [2026, 7, 1])
    }

    @Test func naechsteFaelligkeitQuartalsweise() {
        let d = TaskVorlagen.naechsteFaelligkeit(intervall: .quartalsweise, faelligTag: 10, monate: [1, 4, 7, 10], ab: tag(2026, 6, 24))
        #expect(ymd(d) == [2026, 7, 10])
    }

    private func kontext() throws -> ModelContext {
        let c = try ModelContainer(for: MonthlyTask.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    @Test func abschlussSpawntNaechsteUndDeduppt() throws {
        let ctx = try kontext()
        let t = MonthlyTask(titel: "Miete überweisen", monat: tag(2026, 6, 1), intervall: .monatlich, faelligTag: 1)
        ctx.insert(t); try ctx.save()
        func tasks() throws -> [MonthlyTask] { try ctx.fetch(FetchDescriptor<MonthlyTask>()) }

        t.erledigt = true
        TaskVorlagen.nachAbschluss(t, in: ctx)
        #expect(try tasks().count == 2)
        let offen = try tasks().first { !$0.erledigt }
        #expect(offen != nil)
        #expect(ymd(offen!.monat) == [2026, 7, 1])

        // Erneuter Aufruf darf nicht doppeln (offene Folge existiert bereits)
        TaskVorlagen.nachAbschluss(t, in: ctx)
        #expect(try tasks().count == 2)
    }

    @Test func einmaligeAufgabeSpawntNicht() throws {
        let ctx = try kontext()
        let t = MonthlyTask(titel: "Einmal", monat: tag(2026, 6, 1))   // .einmalig
        ctx.insert(t); try ctx.save()
        t.erledigt = true
        TaskVorlagen.nachAbschluss(t, in: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<MonthlyTask>()) == 1)
    }
}
