import Foundation
import SwiftData

/// Minimaler MCP-Dispatch (JSON-RPC 2.0): initialize / ping / tools/list / tools/call /
/// resources/list / resources/templates/list / resources/read.
/// `initialize` liefert zusätzlich `instructions` (knappes Briefing). Bewusst schlank
/// gehalten: wenige Tools + Resources, alle Antworten als Engine-Zahlen bzw. CSV.
enum MCPProtokoll {
    static let protokollVersion = "2025-06-18"

    /// Verarbeitet eine eingehende JSON-RPC-Nachricht. Gibt die Antwort als Daten
    /// zurück – oder `nil`, wenn es eine Notification war (HTTP 202, kein Body).
    static func verarbeite(_ data: Data, container: ModelContainer, sitzung: String = "lokal") async -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fehler(id: nil, code: -32700, nachricht: "Parse error")
        }
        let methode = obj["method"] as? String ?? ""
        let id = obj["id"]   // nil ⇒ Notification

        switch methode {
        case "initialize":
            await MainActor.run { KISicherung.neueSitzung() }   // neue MCP-Session → nächster Schreibzugriff sichert
            let clientVer = ((obj["params"] as? [String: Any])?["protocolVersion"] as? String) ?? protokollVersion
            return antwort(id: id, result: [
                "protocolVersion": clientVer,
                "capabilities": ["tools": [String: Any](), "resources": [String: Any]()],
                "serverInfo": ["name": "Kontor", "version": "1.1"],
                "instructions": KontorMCP.briefing,
            ])
        case "ping":
            return antwort(id: id, result: [String: Any]())
        case "notifications/initialized", "notifications/cancelled":
            return nil

        // MARK: Tools
        case "tools/list":
            let tools: [[String: Any]] = KontorMCP.werkzeuge.map {
                ["name": $0.name, "description": $0.beschreibung, "inputSchema": $0.schema]
            }
            return antwort(id: id, result: ["tools": tools])
        case "tools/call":
            let params = obj["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try await MainActor.run { try KontorMCP.fuehreAus(name: name, argumente: args, container: container) }
                return antwort(id: id, result: ["content": [["type": "text", "text": text]], "isError": false])
            } catch {
                let m = (error as? MCPFehler)?.text ?? error.localizedDescription
                return antwort(id: id, result: ["content": [["type": "text", "text": "Fehler: \(m)"]], "isError": true])
            }

        // MARK: Resources
        case "resources/list":
            return antwort(id: id, result: ["resources": KontorMCP.ressourcen])
        case "resources/templates/list":
            return antwort(id: id, result: ["resourceTemplates": KontorMCP.ressourcenVorlagen])
        case "resources/read":
            let params = obj["params"] as? [String: Any] ?? [:]
            let uri = params["uri"] as? String ?? ""
            do {
                let text = try await MainActor.run { try KontorMCP.leseRessource(uri: uri, container: container) }
                return antwort(id: id, result: ["contents": [["uri": uri, "mimeType": "text/plain", "text": text]]])
            } catch {
                let m = (error as? MCPFehler)?.text ?? error.localizedDescription
                return id == nil ? nil : fehler(id: id, code: -32602, nachricht: m)
            }

        default:
            return id == nil ? nil : fehler(id: id, code: -32601, nachricht: "Method not found: \(methode)")
        }
    }

    // MARK: - Antworten bauen

    private static func antwort(id: Any?, result: [String: Any]) -> Data {
        var obj: [String: Any] = ["jsonrpc": "2.0", "result": result]
        obj["id"] = id ?? NSNull()
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }
    private static func fehler(id: Any?, code: Int, nachricht: String) -> Data {
        var obj: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": nachricht]]
        obj["id"] = id ?? NSNull()
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }
}

/// Fehler mit klartextlicher, tokensparender Meldung für Tool-/Resource-Antworten.
struct MCPFehler: Error { let text: String; init(_ text: String) { self.text = text } }
