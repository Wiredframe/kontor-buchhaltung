import Testing
import Foundation
import Security
@testable import Kontor

/// Die Token-Quelle des MCP-Servers – bisher zu 0 % gedeckt.
///
/// Getestet wird die **Entscheidungsregel**, nicht die Keychain selbst: `tokenPlan` ist rein,
/// damit die Regel ohne echte Keychain (die im Testlauf ohnehin unsigniert und damit nicht
/// ansprechbar ist) verifizierbar bleibt.
struct SchlusselbundTests {

    private let neu = { "NEU-TOKEN" }

    /// Der Normalfall: Token liegt in der Keychain → verwenden, nichts schreiben.
    @Test func vorhandenesTokenWirdVerwendetUndNichtNeuGeschrieben() {
        #expect(MCPServer.tokenPlan(keychain: .gefunden("ALT-TOKEN"), klartext: nil, neuesToken: neu)
                == .verwende("ALT-TOKEN"))
    }

    /// Ein vorhandenes Token gewinnt auch gegen eine liegengebliebene Klartext-Kopie.
    @Test func keychainSchlaegtKlartextKopie() {
        #expect(MCPServer.tokenPlan(keychain: .gefunden("ALT-TOKEN"), klartext: "KLARTEXT", neuesToken: neu)
                == .verwende("ALT-TOKEN"))
    }

    /// **Die Regression.** Ein nicht ansprechbarer Schlüsselbund heißt nicht „kein Token".
    /// Vorher wurde hier ein neues erzeugt und per SecItemUpdate über das bestehende
    /// geschrieben – der konfigurierte MCP-Client bekam ab dann 401, ohne dass irgendwo etwas
    /// fehlschlug. Entscheidend ist: **niemals `.speichere`** in diesem Fall.
    @Test(arguments: [errSecInteractionNotAllowed, errSecMissingEntitlement,
                      errSecAuthFailed, errSecNotAvailable, OSStatus(-25308)])
    func nichtVerfuegbarerSchluesselbundSchreibtNichts(_ status: OSStatus) {
        let plan = MCPServer.tokenPlan(keychain: .nichtVerfuegbar(status), klartext: nil, neuesToken: neu)
        #expect(plan == .verwende("NEU-TOKEN"))
        if case .speichere = plan { Issue.record("darf die Keychain nicht anfassen") }
    }

    /// Ist die Keychain weg, aber eine Klartext-Kopie da (unsignierter Dev-Build), gilt die –
    /// und wird ebenfalls nicht in die Keychain zurückgeschrieben.
    @Test func nichtVerfuegbarNutztKlartextKopieOhneZuSchreiben() {
        #expect(MCPServer.tokenPlan(keychain: .nichtVerfuegbar(errSecNotAvailable),
                                    klartext: "KLARTEXT", neuesToken: neu)
                == .verwende("KLARTEXT"))
    }

    /// Gibt es wirklich keines, ist Anlegen richtig.
    @Test func nichtVorhandenLegtNeuesAn() {
        #expect(MCPServer.tokenPlan(keychain: .nichtVorhanden, klartext: nil, neuesToken: neu)
                == .speichere("NEU-TOKEN"))
    }

    /// Migration: Klartext-Kopie aus einer älteren Version wandert in die Keychain.
    @Test func nichtVorhandenMigriertDieKlartextKopie() {
        #expect(MCPServer.tokenPlan(keychain: .nichtVorhanden, klartext: "KLARTEXT", neuesToken: neu)
                == .speichere("KLARTEXT"))
    }

    // MARK: - Keychain-Wrapper

    /// `lies` muss „nicht vorhanden" von „nicht verfügbar" unterscheiden – genau daran hing der
    /// Fehler. Welcher der beiden im Testlauf herauskommt, hängt von der Signatur des Test-Hosts
    /// ab; beides ist gültig. **Nicht** gültig wäre `.gefunden` für ein Konto, das es nie gab.
    @Test func liesLiefertFuerUnbekanntesKontoNieEinGeheimnis() {
        let ergebnis = Schlusselbund.lies("gibt-es-nicht-\(UUID().uuidString)")
        if case .gefunden(let s) = ergebnis {
            Issue.record("unerwartet ein Geheimnis gefunden: \(s)")
        }
    }

    /// `lade` bleibt die tolerante Variante: beide Fehlerlagen → nil.
    @Test func ladeBleibtTolerant() {
        #expect(Schlusselbund.lade("gibt-es-nicht-\(UUID().uuidString)") == nil)
    }
}
