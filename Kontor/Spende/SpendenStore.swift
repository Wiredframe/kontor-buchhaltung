#if APPSTORE
import StoreKit
import SwiftUI

/// Verwaltet das freiwillige Trinkgeld über Apple In-App-Kauf.
///
/// **Nur in der App-Store-Variante vorhanden** (gesamter Typ hinter `#if APPSTORE`).
/// Der Kauf ist ein **verbrauchbarer** IAP: Der Nutzer darf mehrfach spenden. Consumables
/// hinterlassen kein dauerhaftes Apple-Entitlement, deshalb merken wir den „schon
/// unterstützt“-Status **lokal** (UserDefaults) – nur als UI-Hinweis, keine Freischaltung.
@MainActor
@Observable
final class SpendenStore {
    /// Produkt-ID des Trinkgelds. Muss identisch in App Store Connect als **Consumable** angelegt sein.
    static let produktID = "de.wiredframe.Kontor.trinkgeld"

    private enum Keys {
        static let gespendet = "spendeGeleistet"
        static let dankeAus = "spendeDankeAusgeblendet"
    }

    /// Das geladene StoreKit-Produkt (nil, solange nicht geladen bzw. bei Fehler).
    private(set) var produkt: Product?
    /// True, während ein Kauf läuft (für Spinner + Doppelklick-Schutz).
    private(set) var laeuft = false
    /// Letzter Kauf-/Ladefehler (für einen dezenten Hinweis im Screen).
    var letzterFehler: String?
    /// Steuert das Öffnen des Spenden-Screens (aus Sidebar **und** Einstellungen).
    var zeigeScreen = false

    /// Hat der Nutzer schon mindestens einmal gespendet? (lokal gemerkt, reiner UI-Hinweis)
    var hatGespendet: Bool {
        didSet { UserDefaults.standard.set(hatGespendet, forKey: Keys.gespendet) }
    }
    /// Wurde die „Vielen Dank“-Zeile im Menü dauerhaft weggeklickt?
    var dankeAusgeblendet: Bool {
        didSet { UserDefaults.standard.set(dankeAusgeblendet, forKey: Keys.dankeAus) }
    }

    init() {
        hatGespendet = UserDefaults.standard.bool(forKey: Keys.gespendet)
        dankeAusgeblendet = UserDefaults.standard.bool(forKey: Keys.dankeAus)
    }

    /// Lokalisierter Preis („9,99 €“) aus dem StoreKit-Produkt – leer, solange nicht geladen.
    var preisText: String { produkt?.displayPrice ?? "" }

    /// Lädt das Produkt und beobachtet danach dauerhaft Transaktions-Updates – schließt so auch
    /// unterbrochene oder nachträglich (z. B. „Ask to Buy“) bestätigte Käufe sauber ab.
    /// Als langlebiger `.task` an der Wurzel-View gedacht.
    func starten() async {
        await ladeProdukt()
        for await ergebnis in Transaction.updates {
            if case .verified(let transaktion) = ergebnis {
                hatGespendet = true
                await transaktion.finish()
            }
        }
    }

    func ladeProdukt() async {
        do {
            produkt = try await Product.products(for: [Self.produktID]).first
            if produkt == nil {
                letzterFehler = "Das Trinkgeld-Produkt konnte nicht geladen werden."
            }
        } catch {
            letzterFehler = error.localizedDescription
        }
    }

    /// Startet den Kauf. Bei Erfolg wird `hatGespendet` gesetzt und das „Danke“ wieder eingeblendet.
    func spenden() async {
        guard let produkt, !laeuft else { return }
        laeuft = true
        letzterFehler = nil
        defer { laeuft = false }
        do {
            switch try await produkt.purchase() {
            case .success(let verifikation):
                if case .verified(let transaktion) = verifikation {
                    hatGespendet = true
                    dankeAusgeblendet = false
                    await transaktion.finish()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            letzterFehler = error.localizedDescription
        }
    }
}
#endif
