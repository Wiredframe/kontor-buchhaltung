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

    /// Liest ein Geheimnis; `nil`, wenn keines vorliegt oder die Keychain nicht verfügbar ist.
    static func lade(_ konto: String) -> String? {
        var query = basis(konto)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &ergebnis) == errSecSuccess,
              let data = ergebnis as? Data, let s = String(data: data, encoding: .utf8)
        else { return nil }
        return s
    }

    /// Speichert (oder ersetzt) ein Geheimnis. Liefert `true` bei Erfolg.
    @discardableResult
    static func speichere(_ wert: String, konto: String) -> Bool {
        let daten = Data(wert.utf8)
        let query = basis(konto)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            return SecItemUpdate(query as CFDictionary,
                                 [kSecValueData as String: daten] as CFDictionary) == errSecSuccess
        }
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
