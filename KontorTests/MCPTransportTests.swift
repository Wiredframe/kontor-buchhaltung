import Testing
import Foundation
@testable import Kontor

/// Transport-Schicht des MCP-Servers: HTTP-Parser und Token-Vergleich.
///
/// Beides fasst **unauthentifizierte** Bytes an bzw. entscheidet über den Zugang – und war
/// bisher zu 0 % gedeckt (die bestehenden MCP-Tests gehen alle über `MCPProtokoll.verarbeite`
/// und sehen den Transport nie).
struct MCPTransportTests {

    private func anfrage(_ text: String) -> MCPServer.Anfrage? {
        MCPServer.httpParsen(Data(text.utf8))
    }

    // MARK: - HTTP-Parser

    @Test func vollstaendigeAnfrageWirdGeparst() throws {
        let a = try #require(anfrage("POST /mcp HTTP/1.1\r\nAuthorization: Bearer geheim\r\nContent-Length: 2\r\n\r\n{}"))
        #expect(a.methode == "POST")
        #expect(a.pfad == "/mcp")
        #expect(a.authorization == "Bearer geheim")
        #expect(a.vollstaendig)
        #expect(String(data: a.body, encoding: .utf8) == "{}")
    }

    /// Regression: Ohne Content-Length war `laenge = 0` und `body.count >= 0` **immer** wahr –
    /// die Anfrage galt als vollständig und wurde dispatcht, sobald die Header da waren,
    /// mit abgeschnittenem Body.
    @Test func fehlendesContentLengthIstNichtVollstaendig() throws {
        let a = try #require(anfrage("POST /mcp HTTP/1.1\r\nAuthorization: Bearer x\r\n\r\n{\"jsonrpc\""))
        #expect(a.vollstaendig == false)
    }

    /// Kaputtes oder negatives Content-Length verhielt sich genauso wie ein fehlendes.
    @Test(arguments: ["abc", "-1", "", "12abc", "9999999999999999999999"])
    func kaputtesContentLengthIstNichtVollstaendig(_ wert: String) throws {
        let a = try #require(anfrage("POST /mcp HTTP/1.1\r\nContent-Length: \(wert)\r\n\r\n{}"))
        #expect(a.vollstaendig == false)
    }

    /// Ein noch unvollständiger Body (Rest unterwegs) darf nicht dispatcht werden.
    @Test func zuKurzerBodyIstNichtVollstaendig() throws {
        let a = try #require(anfrage("POST /mcp HTTP/1.1\r\nContent-Length: 100\r\n\r\n{\"a\":1}"))
        #expect(a.vollstaendig == false)
    }

    /// Kommt mehr als angekündigt, ist die Anfrage trotzdem verarbeitbar.
    @Test func laengererBodyGiltAlsVollstaendig() throws {
        let a = try #require(anfrage("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}extra"))
        #expect(a.vollstaendig)
    }

    /// Ohne Header-Ende ist noch nichts zu parsen (der Rest ist unterwegs).
    @Test func unvollstaendigerKopfLiefertNil() {
        #expect(anfrage("POST /mcp HTTP/1.1\r\nContent-Len") == nil)
    }

    @Test func headerNamenSindGrossKleinEgal() throws {
        let a = try #require(anfrage("POST /mcp HTTP/1.1\r\nAUTHORIZATION: Bearer x\r\ncontent-length: 2\r\n\r\n{}"))
        #expect(a.authorization == "Bearer x")
        #expect(a.vollstaendig)
    }

    // MARK: - Token-Vergleich

    @Test func tokenVergleichAkzeptiertNurExakteGleichheit() {
        #expect(MCPServer.sicherGleich("geheim", "geheim"))
        #expect(MCPServer.sicherGleich("geheim", "geheiM") == false)
        #expect(MCPServer.sicherGleich("geheim", "geheim ") == false)
        #expect(MCPServer.sicherGleich("geheim", "") == false)
        #expect(MCPServer.sicherGleich("", "") )
        #expect(MCPServer.sicherGleich("geheim", "geheimX") == false)   // Präfix reicht nicht
        #expect(MCPServer.sicherGleich("geheimX", "geheim") == false)
    }

    /// Unicode/Mehrbyte darf den Vergleich nicht durcheinanderbringen.
    @Test func tokenVergleichIstByteGenau() {
        #expect(MCPServer.sicherGleich("tökén", "tökén"))
        #expect(MCPServer.sicherGleich("tökén", "token") == false)
    }
}
