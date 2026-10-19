import Foundation
import Testing

@testable import Kontor

/// ELSTER-Dateien: Steuernummer-Umrechnung, UStVA-XML und ZM-CSV.
struct ElsterExportTests {

    @Test func steuernummerJeLand() throws {
        #expect(try ElsterExport.steuernummer("9181081508155", land: nil) == "9181081508155")
        #expect(try ElsterExport.steuernummer("181/815/08155", land: .by) == "9181081508155")
        #expect(try ElsterExport.steuernummer("21/815/08150", land: .be) == "1121081508150")
        #expect(try ElsterExport.steuernummer("013 815 08153", land: .he) == "2613081508153")
        #expect(try ElsterExport.steuernummer("133/8150/8159", land: .nw) == "5133081508159")
        #expect(throws: ElsterExport.Fehler.self) { try ElsterExport.steuernummer("181/815/08155", land: nil) }
        #expect(throws: ElsterExport.Fehler.self) { try ElsterExport.steuernummer("12/345/6789", land: .by) }
        #expect(throws: ElsterExport.Fehler.self) { try ElsterExport.steuernummer("DE123", land: .by) }
    }

    private var absender: ElsterExport.Absender {
        ElsterExport.Absender(name: "Lena Brandt & Co", strasse: "Musterweg 1", plz: "10115", ort: "Berlin")
    }

    @Test func ustvaXMLMitKennzahlen() throws {
        let u = UStVAErgebnis(
            kz81: dez("1000"), ust81: dez("190"), kz86: 0, ust86: 0, kz21: dez("-2000"), kz45: 0,
            kz66: dez("42.7"), kz84: dez("44"), kz85: dez("8.36"), kz67: dez("8.36"), korrektur17: 0)
        let daten = try ElsterExport.ustvaXML(
            u, jahr: 2026, zeitraum: ElsterExport.zeitraumCode(quartal: 3), steuernummer: "1121081508150",
            absender: absender, berichtigt: true, erstellt: tag(2026, 10, 19))
        let text = try #require(String(data: daten, encoding: .isoLatin1))
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"ISO-8859-15\"?>"))
        #expect(text.contains("ustva/v2026\" version=\"2026\""))
        #expect(text.contains("<Erstellungsdatum>20261019</Erstellungsdatum>"))
        #expect(text.contains("<Name>Lena Brandt &amp; Co</Name>"))
        #expect(text.contains("<Zeitraum>43</Zeitraum>"))
        let kz = text.split(separator: "\n").filter { $0.contains("<Kz") }.map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        #expect(
            kz == [
                "<Kz10>1</Kz10>", "<Kz21>-2000</Kz21>", "<Kz66>42.70</Kz66>", "<Kz67>8.36</Kz67>",
                "<Kz81>1000</Kz81>", "<Kz83>147.30</Kz83>", "<Kz84>44</Kz84>", "<Kz85>8.36</Kz85>",
            ])
    }

    @Test func ustvaOhneAbsenderWirdAbgelehnt() {
        let leer = UStVAErgebnis(
            kz81: 0, ust81: 0, kz86: 0, ust86: 0, kz66: 0, kz84: 0, kz85: 0, kz67: 0, korrektur17: 0)
        var a = absender
        a.ort = " "
        #expect(throws: ElsterExport.Fehler.self) {
            try ElsterExport.ustvaXML(leer, jahr: 2026, zeitraum: "01", steuernummer: "1", absender: a)
        }
    }

    @Test func zmCSV() throws {
        let posten = [
            ZMPosten(
                kunde: "Studio Wien", ustIdNr: "ATU 1234 5678", netto: dez("1500.80"), rechnungsdatum: tag(2026, 8, 1),
                status: .bezahlt, ausfalldatum: nil)
        ]
        let csv = try ElsterExport.zmCSV(Steuer.zm(posten, in: .quartal(2026, 3)))
        #expect(
            String(decoding: csv, as: UTF8.self)
                == "#v3.0\n#ve3.2.1\nUmsatzsteuer-Identifikationsnummer (USt-IdNr.),Summe (Euro),Art der Leistung\nATU12345678,1500,S\n"
        )
        var ohne = posten
        ohne[0].ustIdNr = nil
        #expect(throws: ElsterExport.Fehler.self) { try ElsterExport.zmCSV(Steuer.zm(ohne, in: .quartal(2026, 3))) }
    }
}
