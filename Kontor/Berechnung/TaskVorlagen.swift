import Foundation
import SwiftData

/// Wiederkehrungs-Logik für Aufgaben (Reminders-Stil): beim Abhaken einer
/// wiederkehrenden Aufgabe wird automatisch die nächste fällige erzeugt.
enum TaskVorlagen {

    /// Gehört das Intervall in die **Monatsabschluss**-Sidebar? Monatliche, einmalige und
    /// quartalsweise Aufgaben werden dort im Fälligkeitsmonat ihrer Instanz gezeigt; jährliche
    /// gehören ausschließlich in den Jahresabschluss.
    static func inMonatsSidebar(_ intervall: TaskIntervall) -> Bool {
        intervall != .jaehrlich
    }

    /// Vier Monate im Quartalsabstand ab `m` (z. B. 2 → [2, 5, 8, 11]).
    static func quartalsSchema(ab m: Int) -> [Int] {
        (0..<4).map { ((m - 1 + $0 * 3) % 12) + 1 }.sorted()
    }

    /// Nächste Fälligkeit ≥ `ab`: monatlich = jeder Monat, quartalsweise/jährlich = nur die
    /// angegebenen Monate, jeweils am `faelligTag` (auf gültige Tage geklemmt).
    static func naechsteFaelligkeit(intervall: TaskIntervall, faelligTag: Int, monate: [Int], ab ref: Date) -> Date {
        let cal = appKalender
        let start = cal.startOfDay(for: ref)
        let c = cal.dateComponents([.year, .month], from: start)
        var jahr = c.year ?? 2026
        var monat = c.month ?? 1

        // quartalsweise & jährlich beschränken auf die angegebenen Monate (jährlich = ein Monat).
        // **Leere Liste heißt nicht „nie":** Vorher blieb `gueltig` dann leer, die Schleife fand
        // nichts und fiel auf `start` durch – also auf den Folgetag. Beim Abhaken erzeugte sich
        // die Aufgabe damit **täglich** neu statt vierteljährlich. Ohne Schema wird deshalb der
        // Referenzmonat zum Anker.
        let gueltig: Set<Int>
        switch intervall {
        case .monatlich, .einmalig:
            gueltig = Set(1...12)
        case .quartalsweise:
            gueltig = monate.isEmpty ? Set(quartalsSchema(ab: monat)) : Set(monate)
        case .jaehrlich:
            gueltig = monate.isEmpty ? [monat] : Set(monate)
        }

        for _ in 0..<60 {
            if gueltig.contains(monat), let d = datumImMonat(jahr: jahr, monat: monat, tag: faelligTag), d >= start {
                return d
            }
            monat += 1
            if monat > 12 { monat = 1; jahr += 1 }
        }
        return start
    }

    /// Der `tag` im Monat, geklemmt auf dessen **echte** Länge (31. Februar → 28./29.).
    ///
    /// Intern, damit die View dieselbe Regel nutzt: Sie klemmte früher selbst auf hart 28. Bei
    /// `faelligTag = 31` setzte sie damit den 28. Januar, während diese Funktion den 31. Januar
    /// liefert – das Abhaken erzeugte prompt eine **zweite Instanz im selben Monat**.
    static func datumImMonat(jahr: Int, monat: Int, tag: Int) -> Date? {
        let cal = appKalender
        guard let erster = cal.date(from: DateComponents(year: jahr, month: monat, day: 1)) else { return nil }
        let maxTag = cal.range(of: .day, in: .month, for: erster)?.count ?? 28
        return cal.date(from: DateComponents(year: jahr, month: monat, day: min(max(tag, 1), maxTag)))
    }

    /// Nach dem Abhaken einer wiederkehrenden Aufgabe die nächste fällige erzeugen –
    /// sofern noch keine offene Aufgabe gleichen Titels/Intervalls existiert.
    static func nachAbschluss(_ task: MonthlyTask, in context: ModelContext) {
        guard task.istWiederkehrend, task.erledigt else { return }
        let alle = (try? context.fetch(FetchDescriptor<MonthlyTask>())) ?? []
        let id = task.persistentModelID
        let schonOffen = alle.contains {
            $0.persistentModelID != id && !$0.erledigt && $0.titel == task.titel && $0.intervall == task.intervall
        }
        guard !schonOffen else { return }
        let ab = appKalender.date(byAdding: .day, value: 1, to: task.monat) ?? task.monat
        let next = naechsteFaelligkeit(intervall: task.intervall, faelligTag: task.faelligTag,
                                       monate: task.quartalsMonate, ab: ab)
        context.insert(MonthlyTask(titel: task.titel, monat: next, intervall: task.intervall,
                                   faelligTag: task.faelligTag, quartalsMonate: task.quartalsMonate))
        try? context.save()
    }
}
