import Foundation
import SwiftData

/// Nachtrag von `ExpenseEntry.art` für Einträge, die noch keine haben.
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
/// **Läuft bei jedem Start – und das ist Absicht**, kein Versehen: Der Restore eines alten
/// Backups bringt `art == nil` jederzeit neu herein (`Backup.AusgabeDTO.art` ist optional),
/// und genau dann soll die Klassifizierung greifen. Der Kommentar sagte früher „einmalig",
/// was den Blick auf die eigentliche Gefahr verstellte: Solange ein **laufender** Pfad
/// `art == nil` erzeugt, schreibt der Nachtrag auch **neue** Einträge um und rät ihre Art aus
/// dem Namen. Genau das tat `kontor_anlegen` (Ausgaben ohne `art:`) – eine per MCP gebuchte
/// einmalige Ausgabe namens „Adobe" wurde beim nächsten Start zur `.subscription`. Deshalb
/// gilt: **jeder Erzeuger setzt `art` explizit**, dieser Nachtrag ist nur das Netz für Altdaten.
/// (Der Schwester-Nachtrag `PrivatBetriebsausgabeNachtrag` wurde entfernt – er reparierte einen
/// Bug-Zustand, den der Import längst selbst verhindert, und überschrieb dabei Nutzer-Eingaben.)
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
