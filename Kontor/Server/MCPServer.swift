import Foundation
import Network
import SwiftData
import Observation

/// Lokaler MCP-Server (HTTP/JSON-RPC) auf 127.0.0.1, damit ein externer MCP-Client
/// (z. B. Claude Code) die Kontor-Daten lesen und – sparsam – schreiben kann.
/// Nur Loopback, Token-geschützt. Antworten sind bewusst tokensparend: fertige
/// Engine-Zahlen bzw. dichte CSV statt Rohzeilen-Dumps (siehe `KontorMCP`).
@Observable
final class MCPServer {
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private let sitzungsId = UUID().uuidString

    private(set) var aktiv = false
    private(set) var letzterFehler: String?
    let port: UInt16
    let token: String

    /// Obergrenze je Anfrage (Belege-Uploads möglich) – verhindert unbegrenzt wachsende Puffer.
    @ObservationIgnored private let maxAnfrageBytes = 25 * 1024 * 1024
    /// Verbindungs-Timeout: hängende/teilweise Anfragen werden nach dieser Frist geschlossen.
    @ObservationIgnored private let anfrageTimeout: TimeInterval = 30

    var url: String { "http://127.0.0.1:\(port)/mcp" }
    var einrichtbefehl: String {
        "claude mcp add --transport http kontor \(url) --header \"Authorization: Bearer \(token)\""
    }

    init(container: ModelContainer, port: UInt16 = 8787) {
        self.container = container
        self.port = port
        self.token = Self.ermittleToken()
    }

    private static let tokenKonto = "mcpToken"

    /// Token bevorzugt aus der Keychain; migriert ein evtl. vorhandenes Alt-Token aus
    /// `UserDefaults` (Klartext) dorthin; legt sonst ein neues an. `UserDefaults` dient nur
    /// noch als Fallback, falls die Keychain nicht verfügbar ist (unsignierter Debug-Build).
    private static func ermittleToken() -> String {
        if let t = Schlusselbund.lade(tokenKonto) { return t }
        if let alt = UserDefaults.standard.string(forKey: tokenKonto) {
            if Schlusselbund.speichere(alt, konto: tokenKonto) {
                UserDefaults.standard.removeObject(forKey: tokenKonto)   // Klartext-Kopie entfernen
            }
            return alt
        }
        let neu = UUID().uuidString
        if !Schlusselbund.speichere(neu, konto: tokenKonto) {
            UserDefaults.standard.set(neu, forKey: tokenKonto)          // Fallback (Dev)
        }
        return neu
    }

    // MARK: - Lebenszyklus

    func starten() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true            // Loopback wird je Verbindung erzwungen
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            l.newConnectionHandler = { [weak self] conn in self?.behandle(conn) }
            l.stateUpdateHandler = { [weak self] zustand in
                Task { @MainActor in self?.zustandGeaendert(zustand) }
            }
            l.start(queue: .global(qos: .userInitiated))
            listener = l
        } catch {
            aktiv = false
            letzterFehler = error.localizedDescription
        }
    }

    func stoppen() {
        listener?.cancel()
        listener = nil
        aktiv = false
        letzterFehler = nil
    }

    @MainActor
    private func zustandGeaendert(_ zustand: NWListener.State) {
        switch zustand {
        case .ready:           aktiv = true; letzterFehler = nil
        case .waiting(let e):  aktiv = false; letzterFehler = meldung(e)
        case .failed(let e):   aktiv = false; letzterFehler = meldung(e); listener = nil
        case .cancelled:       aktiv = false
        default:               break
        }
    }

    private func meldung(_ e: NWError) -> String {
        if case .posix(let code) = e, code == .EADDRINUSE {
            return "Port \(port) ist belegt – läuft Kontor evtl. noch? (Fenster schließen beendet die App nicht; mit ⌘Q ganz beenden.)"
        }
        return e.localizedDescription
    }

    // MARK: - Verbindung

    private func behandle(_ conn: NWConnection) {
        guard Self.istLoopback(conn.endpoint) else { conn.cancel(); return }
        conn.start(queue: .global(qos: .userInitiated))
        // Hängende/teilweise Anfragen nach einer Frist schließen (cancel auf bereits
        // geschlossener Verbindung ist ein No-Op).
        DispatchQueue.global().asyncAfter(deadline: .now() + anfrageTimeout) { [weak conn] in
            conn?.cancel()
        }
        empfange(conn, puffer: Data())
    }

    /// Konstantzeitiger Vergleich (Defense-in-Depth gegen Timing-Seitenkanäle beim Token-Check).
    private static func sicherGleich(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    private static func istLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let a): return a.isLoopback
        case .ipv6(let a): return a.isLoopback
        case .name(let n, _): return n == "localhost"
        @unknown default: return false
        }
    }

    private func empfange(_ conn: NWConnection, puffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 17) { [weak self] daten, _, abgeschlossen, fehler in
            guard let self else { conn.cancel(); return }
            var p = puffer
            if let daten { p.append(daten) }
            if p.count > self.maxAnfrageBytes {
                self.sende(conn, status: "413 Payload Too Large",
                           body: Data("payload too large".utf8), typ: "text/plain")
                return
            }
            if let anfrage = Self.httpParsen(p), anfrage.vollstaendig {
                Task { await self.antworten(conn, anfrage) }
                return
            }
            if fehler != nil || abgeschlossen { conn.cancel(); return }
            self.empfange(conn, puffer: p)
        }
    }

    private func antworten(_ conn: NWConnection, _ anfrage: Anfrage) async {
        guard let auth = anfrage.authorization, Self.sicherGleich(auth, "Bearer \(token)") else {
            sende(conn, status: "401 Unauthorized", body: Data("unauthorized".utf8), typ: "text/plain"); return
        }
        guard anfrage.methode == "POST" else {
            sende(conn, status: "405 Method Not Allowed", body: Data(), typ: "text/plain"); return
        }
        if let antwort = await MCPProtokoll.verarbeite(anfrage.body, container: container, sitzung: sitzungsId) {
            sende(conn, status: "200 OK", body: antwort, typ: "application/json",
                  extra: ["Mcp-Session-Id": sitzungsId])
        } else {
            sende(conn, status: "202 Accepted", body: Data(), typ: "application/json")
        }
    }

    private func sende(_ conn: NWConnection, status: String, body: Data, typ: String, extra: [String: String] = [:]) {
        var kopf = "HTTP/1.1 \(status)\r\nContent-Type: \(typ)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (k, v) in extra { kopf += "\(k): \(v)\r\n" }
        kopf += "\r\n"
        var daten = Data(kopf.utf8); daten.append(body)
        conn.send(content: daten, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Minimaler HTTP-Parser

    private struct Anfrage {
        let methode, pfad: String
        let authorization: String?
        let body: Data
        let vollstaendig: Bool
    }

    private static func httpParsen(_ data: Data) -> Anfrage? {
        guard let trenn = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let kopf = String(data: data.subdata(in: data.startIndex..<trenn.lowerBound), encoding: .utf8) else { return nil }
        let zeilen = kopf.components(separatedBy: "\r\n")
        let start = zeilen.first?.components(separatedBy: " ") ?? []
        let methode = start.first ?? ""
        let pfad = start.count > 1 ? start[1] : "/"
        var auth: String?; var laenge = 0
        for z in zeilen.dropFirst() {
            guard let doppel = z.firstIndex(of: ":") else { continue }
            let schluessel = z[..<doppel].trimmingCharacters(in: .whitespaces).lowercased()
            let wert = z[z.index(after: doppel)...].trimmingCharacters(in: .whitespaces)
            switch schluessel {
            case "authorization":  auth = wert
            case "content-length": laenge = Int(wert) ?? 0
            default: break
            }
        }
        let body = data.subdata(in: trenn.upperBound..<data.endIndex)
        return Anfrage(methode: methode, pfad: pfad, authorization: auth, body: body, vollstaendig: body.count >= laenge)
    }
}
