import Foundation
import Testing

@testable import Kontor

// MARK: - Euro-Format

/// `Decimal.euro` baut sein Format seit dem Performance-Umbau **einmal** auf (`euroFormat`)
/// statt bei jedem Aufruf. Diese Tests nageln fest, dass dabei Zeichen für Zeichen dasselbe
/// herauskommt wie mit dem früheren `formatted(.currency(code:).locale(_:))`.
///
/// **Falle, die hier jeder einmal tritt:** `.currency(code: "EUR")` setzt in de_DE vor das
/// Eurozeichen ein **geschütztes** Leerzeichen (U+00A0), kein ASCII-Space. Ein Vergleich gegen
/// ein von Hand getipptes „1.234,56 €" schlägt deshalb fehl, und der naheliegende „Fix" am
/// Literal machte den Test gegen genau den Unterschied blind, den er schützen soll. Die
/// Erwartung wird darum aus demselben `FormatStyle` gebaut, den die alte Implementierung
/// aufgebaut hat.
struct GeldformatTests {

    /// Exakt der Ausdruck, der vor dem Umbau in `Decimal.euro` stand.
    private func alteImplementierung(_ wert: Decimal) -> String {
        wert.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))
    }

    @Test func euroFormatBleibtUnveraendert() {
        for wert: Decimal in [0, dez("0.01"), dez("6.99"), dez("1234.56"), dez("1000000")] {
            #expect(wert.euro == alteImplementierung(wert))
        }
    }

    @Test func euroFormatBeiNegativenBetraegen() {
        // Erstattungen und Gutschriften sind negativ und kommen im Ledger regelmäßig vor.
        for wert: Decimal in [dez("-0.01"), dez("-6.99"), dez("-1234.56")] {
            #expect(wert.euro == alteImplementierung(wert))
        }
        #expect(dez("-1234.56").euro.hasPrefix("-"))
    }

    /// Struktur statt Literal: Tausenderpunkt, Dezimalkomma, Währungszeichen am Ende, und
    /// davor ein geschütztes Leerzeichen. Das ist der Teil, der bei einem versehentlichen
    /// Wechsel des Locale sofort auffiele.
    @Test func euroFormatIstDeutschMitGeschuetztemLeerzeichen() {
        let s = dez("1234.56").euro
        #expect(s.contains("1.234,56"))
        #expect(s.hasSuffix("€"))
        #expect(s.contains("\u{00A0}€"))
        #expect(!s.contains(" €"))  // ASCII-Space wäre das falsche Zeichen
    }

    /// Das Format hängt am fest verdrahteten `de_DE`, nicht an der Systemsprache: sonst
    /// stünden in einer englisch eingestellten Umgebung plötzlich „1,234.56" in den Tabellen
    /// und im CSV-Export des MCP.
    @Test func euroFormatIstUnabhaengigVonDerSystemsprache() {
        #expect(euroFormat.locale == Locale(identifier: "de_DE"))
        #expect(dez("1234.56").euro == dez("1234.56").formatted(euroFormat))
    }

    /// `volleEuro` kürzt Richtung Null und ist die Grundlage der ELSTER-Bemessungsgrundlagen.
    /// Hier nur die Interaktion mit der Formatierung: gekürzt bleiben null Cent stehen.
    @Test func volleEuroFormatiertOhneCentbetrag() {
        #expect(dez("1234.56").volleEuro.euro == dez("1234").euro)
        #expect(dez("-4000.75").volleEuro.euro == dez("-4000").euro)
    }
}
