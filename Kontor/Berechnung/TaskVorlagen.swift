import Foundation
import SwiftData

/// Wiederkehrungs-Logik für Aufgaben (Reminders-Stil): beim Abhaken einer
/// wiederkehrenden Aufgabe wird automatisch die nächste fällige erzeugt.
enum TaskVorlagen {

    /// Nächste Fälligkeit ≥ `ab`: monatlich = jeder Monat, quartalsweise = nur die
    /// angegebenen Monate, jeweils am `faelligTag` (auf gültige Tage geklemmt).
    static func naechsteFaelligkeit(intervall: TaskIntervall, faelligTag: Int, monate: [Int], ab ref: Date) -> Date {
        let cal = appKalender
        let start = cal.startOfDay(for: ref)
        // quartalsweise & jährlich beschränken auf die angegebenen Monate (jährlich = ein Monat).
        let gueltig: Set<Int> = (intervall == .quartalsweise || intervall == .jaehrlich) ? Set(monate) : Set(1...12)
        let c = cal.dateComponents([.year, .month], from: start)
        var jahr = c.year ?? 2026
        var monat = c.month ?? 1
        for _ in 0..<60 {
            if gueltig.contains(monat), let d = datumImMonat(jahr: jahr, monat: monat, tag: faelligTag), d >= start {
                return d
            }
            monat += 1
            if monat > 12 { monat = 1; jahr += 1 }
        }
        return start
    }

    private static func datumImMonat(jahr: Int, monat: Int, tag: Int) -> Date? {
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
