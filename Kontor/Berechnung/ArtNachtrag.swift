import Foundation
import SwiftData

/// Einmaliger Nachtrag von `ExpenseEntry.art` für Altbestand.
///
/// Das `art`-Feld (Betriebsausgabe/Fixkosten/Subscription) kam **nach** der Erst-Erfassung
/// dazu; Buchungen aus der Obsidian-/SubTotal-Migration (und aus alten Backups, die `art`
/// noch nicht kannten) tragen daher `art == nil`. `artEffektiv` wertet das als Betriebsausgabe –
/// dadurch blieben **Privat-Übersicht / Monatsabschluss / Dashboard** bei Fixkosten &
/// Subscriptions leer (`wiederkehrendBrutto` findet nichts).
///
/// Regel (rein Anzeige-/Liquiditäts-Gruppierung, **keine** EÜR-/USt-/ESt-Wirkung):
/// - bekannte SaaS-/Streaming-Namen → **Subscription** (privat **und** betrieblich)
/// - sonst privat → **Fixkosten**
/// - sonst betrieblich → **Betriebsausgabe** (Normalfall)
///
/// Idempotent: greift nur Einträge mit `art == nil`; nach dem Lauf hat jeder Eintrag eine `art`,
/// ein erneuter Aufruf macht nichts. Der Nutzer kann jede Buchung in „Ausgaben" umtaggen.
enum ArtNachtrag {

    /// Namens-Schnipsel, die eindeutig auf ein Abo/Subscription deuten (Klein­schreibung,
    /// Teilstring-Match gegen Bezeichnung **oder** Anbieter).
    static let aboSchnipsel: [String] = [
        "disney", "youtube", "zattoo", "netflix", "spotify", "audible", "prime video",
        "anthropic", "claude", "chatgpt", "openai", "figma", "github", "copilot",
        "microsoft 365", "office 365", "m365", "adobe", "notion", "dropbox", "icloud+",
        "google one", "midjourney"
    ]

    private static func istAbo(_ e: ExpenseEntry) -> Bool {
        let text = (e.bezeichnung + " " + e.anbieter).lowercased()
        return aboSchnipsel.contains { text.contains($0) }
    }

    static func nachtragen(_ ctx: ModelContext) {
        let alle = (try? ctx.fetch(FetchDescriptor<ExpenseEntry>())) ?? []
        let offen = alle.filter { $0.art == nil }
        guard !offen.isEmpty else { return }
        for e in offen {
            if istAbo(e) { e.art = .subscription }
            else if !e.betrieblich { e.art = .fixkosten }
            else { e.art = .betriebsausgabe }
        }
        try? ctx.save()
    }
}
