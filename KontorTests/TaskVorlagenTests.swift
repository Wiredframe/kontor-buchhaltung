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

    /// Quartalsweise Aufgaben erscheinen in der Monatsabschluss-Sidebar (im Fälligkeitsmonat),
    /// jährliche nicht (die gehören in den Jahresabschluss).
    @Test func monatsSidebarIntervalle() {
        #expect(TaskVorlagen.inMonatsSidebar(.monatlich))
        #expect(TaskVorlagen.inMonatsSidebar(.einmalig))
        #expect(TaskVorlagen.inMonatsSidebar(.quartalsweise))
        #expect(!TaskVorlagen.inMonatsSidebar(.jaehrlich))
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

    // MARK: - Wiederkehrung: Randfälle, die still die Frequenz verbogen haben

    /// Regression: Ohne Monats-Schema war `gueltig` leer, die Schleife fand nichts und fiel auf
    /// `start` durch – also auf den **Folgetag**. Beim Abhaken erzeugte sich eine quartalsweise
    /// Aufgabe damit **täglich** neu.
    @Test func quartalsweiseOhneSchemaBleibtQuartalsweise() {
        let d = TaskVorlagen.naechsteFaelligkeit(intervall: .quartalsweise, faelligTag: 10,
                                                 monate: [], ab: tag(2026, 6, 24))
        #expect(ymd(d) == [2026, 9, 10])     // Anker = Juni → [3,6,9,12]; nicht der 25.06.
    }

    /// Dasselbe für jährlich: ohne Schema der Referenzmonat im Folgejahr, nicht morgen.
    @Test func jaehrlichOhneSchemaBleibtJaehrlich() {
        let d = TaskVorlagen.naechsteFaelligkeit(intervall: .jaehrlich, faelligTag: 10,
                                                 monate: [], ab: tag(2026, 6, 24))
        #expect(ymd(d) == [2027, 6, 10])
    }

    /// Regression: Eine „jährliche" Aufgabe mit stehengebliebenem Quartals-Schema wiederholte
    /// sich weiter vierteljährlich – `naechsteFaelligkeit` liest dieselbe Monatsliste.
    /// Der Fix sitzt in der View (Schema beim Umschalten angleichen); hier wird gepinnt, dass
    /// ein sauberes Ein-Monats-Schema auch wirklich jährlich fortschreibt.
    @Test func jaehrlichMitEinemStichtagsmonatSpringtUeberDasJahr() {
        let d = TaskVorlagen.naechsteFaelligkeit(intervall: .jaehrlich, faelligTag: 31,
                                                 monate: [5], ab: tag(2026, 6, 1))
        #expect(ymd(d) == [2027, 5, 31])
    }

    /// Regression: Die View klemmte den Fälligkeitstag hart auf 28, die Fortschreibung auf die
    /// echte Monatslänge. Bei `faelligTag: 31` setzte die View den 28. Januar, die
    /// Fortschreibung fand ab dem 29. noch den 31. Januar – eine **zweite Instanz im selben
    /// Monat**. Jetzt nutzen beide `datumImMonat`.
    @Test func faelligTag31ErzeugtKeineZweiteInstanzImSelbenMonat() throws {
        let ctx = try kontext()
        let januar = try #require(TaskVorlagen.datumImMonat(jahr: 2026, monat: 1, tag: 31))
        #expect(ymd(januar) == [2026, 1, 31])          // View und Engine klemmen jetzt gleich
        let t = MonthlyTask(titel: "Monatsabschluss", monat: januar, intervall: .monatlich, faelligTag: 31)
        ctx.insert(t); try ctx.save()
        t.erledigt = true
        TaskVorlagen.nachAbschluss(t, in: ctx)
        let offen = try #require(try ctx.fetch(FetchDescriptor<MonthlyTask>()).first { !$0.erledigt })
        #expect(ymd(offen.monat) == [2026, 2, 28])     // Februar, nicht nochmal Januar
    }

    /// `datumImMonat` klemmt auf die echte Monatslänge – inklusive Schaltjahr.
    @Test(arguments: [(2026, 1, 31, 31), (2026, 2, 31, 28), (2024, 2, 31, 29),
                      (2026, 4, 31, 30), (2026, 6, 0, 1), (2026, 6, 99, 30)])
    func datumImMonatKlemmtAufDieEchteMonatslaenge(_ j: Int, _ m: Int, _ tag: Int, _ erwartet: Int) throws {
        let d = try #require(TaskVorlagen.datumImMonat(jahr: j, monat: m, tag: tag))
        #expect(ymd(d) == [j, m, erwartet])
    }

    /// Das Quartals-Schema spannt vier Monate im 3er-Abstand auf, egal wo man einsteigt.
    @Test(arguments: [(1, [1, 4, 7, 10]), (2, [2, 5, 8, 11]), (6, [3, 6, 9, 12]), (12, [3, 6, 9, 12])])
    func quartalsSchemaSpanntVierMonate(_ ab: Int, _ erwartet: [Int]) {
        #expect(TaskVorlagen.quartalsSchema(ab: ab) == erwartet)
    }
}
