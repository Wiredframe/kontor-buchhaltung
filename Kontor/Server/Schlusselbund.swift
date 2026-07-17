#if !APPSTORE
import Foundation
import Security

/// Minimaler Keychain-Wrapper (`kSecClassGenericPassword`) für kleine Geheimnisse wie das
/// MCP-Bearer-Token. Bewusst tolerant: schlägt ein Keychain-Zugriff fehl (z. B. unsignierter
/// Debug-Build ohne Keychain-Anbindung), liefert er `nil`/`false` und der Aufrufer fällt auf
/// einen Ersatzpfad zurück. Im signierten/notarisierten Release ist die Keychain verfügbar.
enum Schlusselbund {
    private static let service = "de.wiredframe.Kontor"

    private static func basis(_ konto: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: konto]
    }

    /// Ergebnis eines Lesezugriffs.
    ///
    /// Die Unterscheidung ist der ganze Punkt: „es gibt kein Geheimnis" und „die Keychain ist
    /// gerade nicht ansprechbar" sind **völlig verschiedene** Lagen. Früher lieferte `lade`
    /// für beide `nil` – und der Aufrufer legte daraufhin ein neues Token an, das das
    /// bestehende überschrieb.
    enum LadeErgebnis: Equatable {
        case gefunden(String)
        /// Es existiert wirklich keines (`errSecItemNotFound`) → neu anlegen ist richtig.
        case nichtVorhanden
        /// Keychain gesperrt, fehlende Entitlements, unsignierter Build … → **nichts schreiben**.
        case nichtVerfuegbar(OSStatus)
    }

    /// Liest ein Geheimnis und sagt dazu, **warum** es ggf. keines gibt.
    static func lies(_ konto: String) -> LadeErgebnis {
        var query = basis(konto)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &ergebnis)
        switch status {
        case errSecSuccess:
            guard let data = ergebnis as? Data, let s = String(data: data, encoding: .utf8) else {
                return .nichtVerfuegbar(status)   // Eintrag da, aber unlesbar → nicht überschreiben
            }
            return .gefunden(s)
        case errSecItemNotFound:
            return .nichtVorhanden
        default:
            return .nichtVerfuegbar(status)
        }
    }

    /// Liest ein Geheimnis; `nil`, wenn keines vorliegt **oder** die Keychain nicht verfügbar ist.
    /// Für Aufrufer, denen der Unterschied egal ist – beim Token ist er es **nicht**, dort `lies`.
    static func lade(_ konto: String) -> String? {
        if case .gefunden(let s) = lies(konto) { return s }
        return nil
    }

    /// Speichert (oder ersetzt) ein Geheimnis. Liefert `true` bei Erfolg.
    @discardableResult
    static func speichere(_ wert: String, konto: String) -> Bool {
        let daten = Data(wert.utf8)
        let query = basis(konto)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            // `kSecAttrAccessible` mit aktualisieren: Beim Add wird es gesetzt, beim Update stand
            // es früher nicht dabei – ein Eintrag aus einer älteren Version behielte sonst für
            // immer sein altes Zugriffs-Attribut.
            return SecItemUpdate(query as CFDictionary,
                                 [kSecValueData as String: daten,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
                                 as CFDictionary) == errSecSuccess
        }
        // Nur bei „gibt es wirklich nicht" anlegen. Ein anderer Fehler (Keychain gesperrt) heißt
        // nicht, dass der Platz frei ist – hier blind zu schreiben hieße raten.
        guard status == errSecItemNotFound else { return false }
        var neu = query
        neu[kSecValueData as String] = daten
        neu[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(neu as CFDictionary, nil) == errSecSuccess
    }

    /// Entfernt ein Geheimnis (idempotent).
    static func loesche(_ konto: String) {
        SecItemDelete(basis(konto) as CFDictionary)
    }
}

#endif
