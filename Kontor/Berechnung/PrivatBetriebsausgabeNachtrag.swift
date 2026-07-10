import Foundation
import SwiftData

/// Einmalige, idempotente Korrektur des früheren „private Betriebsausgabe"-Bugs.
///
/// Beim Kontoauszug-Import blieb `betrieblich` beim Wechsel der Kategorie auf „Betriebsausgabe"
/// auf dem alten Default `false` stehen; `ImportAnwendung.anwenden` schrieb dann eine
/// `art:.betriebsausgabe` **privat** mit `vst:0`. Fachlich gibt es das nicht – eine Betriebsausgabe
/// ist immer betrieblich. (Der Import erzwingt diese Invariante inzwischen über
/// `Zuordnung.normalisiert`; dieser Nachtrag repariert nur bereits so gebuchten Altbestand.)
///
/// Korrektur: betroffene Einträge auf `betrieblich` stellen und die Vorsteuer aus Betrag+Steuerart
/// neu berechnen (`Steuer.vorsteuerVorschlag`) – so zählen sie wieder in die EÜR und, bei Inland-
/// Steuersätzen, in die Vorsteuer (Reverse-Charge/steuerfrei bleiben korrekt bei 0).
///
/// Idempotent: greift nur `artEffektiv == .betriebsausgabe && !betrieblich`; nach dem Lauf gibt es
/// keine solchen Einträge mehr, ein erneuter Aufruf ist ein No-Op. Es wird **nichts gelöscht**.
/// Läuft beim App-Start **nach** `ArtNachtrag` (dort wird `art` materialisiert).
enum PrivatBetriebsausgabeNachtrag {

    static func nachtragen(_ ctx: ModelContext) {
        let betroffen = ((try? ctx.fetch(FetchDescriptor<ExpenseEntry>())) ?? [])
            .filter { $0.artEffektiv == .betriebsausgabe && !$0.betrieblich }
        guard !betroffen.isEmpty else { return }
        for e in betroffen {
            e.betrieblich = true
            e.vst = Steuer.vorsteuerVorschlag(brutto: e.brutto, steuerart: e.steuerart)
        }
        try? ctx.save()
    }
}
