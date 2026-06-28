import Testing
import Foundation
import CoreGraphics
@testable import Kontor

struct BelegOCRTests {
    /// Rechtsbündige Beträge liefert Vision als eigene Fragmente – sie müssen über die Geometrie
    /// wieder neben ihr Label gruppiert werden (Layout wie bei einer eigenen Ausgangsrechnung).
    @Test func zeilenAusSpaltenLayout() {
        let h: CGFloat = 0.02
        func f(_ t: String, x: CGFloat, y: CGFloat) -> BelegOCR.TextFragment {
            BelegOCR.TextFragment(text: t, box: CGRect(x: x, y: y, width: 0.2, height: h))
        }
        // Label-Spalte links (x≈0.1), Beträge rechts (x≈0.8), jeweils auf gleicher y-Höhe.
        let frag = [
            f("3.145,00 €", x: 0.80, y: 0.305), f("Summe netto", x: 0.10, y: 0.300),
            f("Gesamtbetrag", x: 0.10, y: 0.220), f("3.742,55 €", x: 0.80, y: 0.221),
            f("597,55 €", x: 0.80, y: 0.262), f("USt. (19%)", x: 0.10, y: 0.260),
        ]
        let zeilen = BelegOCR.zeilen(aus: frag)
        #expect(zeilen.first == "Summe netto 3.145,00 €")        // links→rechts, oben→unten
        let d = BelegOCR.extrahiereEinnahme(aus: zeilen)
        #expect(d.rnNetto == dez("3145.00"))
        #expect(d.ust == dez("597.55"))                          // Brutto − Netto
    }

    @Test func betragNormalisierung() {
        #expect(BelegOCR.normalisiere("35,00") == dez("35.00"))
        #expect(BelegOCR.normalisiere("1.234,56") == dez("1234.56"))   // de: Punkt = Tausender
        #expect(BelegOCR.normalisiere("1,234.56") == dez("1234.56"))   // en: Komma = Tausender
        #expect(BelegOCR.normalisiere("12.99") == dez("12.99"))
    }

    @Test func extraktionAusRechnungstext() {
        let zeilen = [
            "Figma, Inc.",
            "Rechnung Nr. 0027",
            "Rechnungsdatum: 14.06.2026",
            "Figma Professional   29,41 €",
            "MwSt 19 %   5,59 €",
            "Gesamtbetrag   35,00 €",
        ]
        let d = BelegOCR.extrahiere(aus: zeilen)
        #expect(d.anbieter == "Figma")               // bekannter Anbieter
        #expect(d.brutto == dez("35.00"))            // „Gesamtbetrag"
        #expect(d.vst == dez("5.59"))                // „MwSt"
        #expect(d.steuerart == .inland19)            // MwSt vorhanden → Inland 19 %
        #expect(d.rechnungsnummer == "0027")         // RN auch für Ausgaben extrahiert (Bank-Matching)
        let c = appKalender.dateComponents([.year, .month, .day], from: d.datum ?? .distantPast)
        #expect(c.year == 2026 && c.month == 6 && c.day == 14)
    }

    @Test func groessterBetragAlsFallback() {
        let d = BelegOCR.extrahiere(aus: ["Beleg ohne Schlagworte", "Posten A 10,00", "Posten B 119,00"])
        #expect(d.brutto == dez("119.00"))           // kein „Gesamt" → größter Betrag
    }

    @Test func einnahmeAusRechnungstext() {
        let zeilen = [
            "Lena Brandt • Oranienstraße 40 • 10999 Berlin",
            "Nordstern Studio GmbH",
            "Chausseestraße 5",
            "10115 Berlin",
            "Lena Brandt",
            "UStID DE300000007",
            "Rechnungsdatum: 02.04.2026",
            "Fälligkeitsdatum: 15.04.2026",
            "Rechnung #202604017",
            "Monatsrechnung April 2026",
            "Summe netto 3.000,00 €",
            "USt. (19 %) 570,00 €",
            "Gesamtbetrag 3.570,00 €",
        ]
        let d = BelegOCR.extrahiereEinnahme(aus: zeilen)
        #expect(d.kunde == "Nordstern Studio GmbH")
        #expect(d.rnNetto == dez("3000.00"))
        #expect(d.ust == dez("570.00"))                 // Brutto − Netto, nicht aus „UStID"
        #expect(d.rechnungsnummer == "202604017")
        let c = appKalender.dateComponents([.year, .month, .day], from: d.datum ?? .distantPast)
        #expect(c.year == 2026 && c.month == 4 && c.day == 2)
    }

    @Test func steuerartErkennung() {
        // MwSt-Zeile → Inland; VSt-Betrag aus der Folgezeile
        let inland = BelegOCR.extrahiere(aus: ["DomainFactory", "Netto 10,92", "zzgl. 19 % MwSt", "2,07", "Gesamt 12,99"])
        #expect(inland.steuerart == .inland19)
        #expect(inland.vst == dez("2.07"))           // Betrag stand in der Folgezeile
        // expliziter Reverse-Charge-Hinweis
        #expect(BelegOCR.extrahiere(aus: ["Figma", "Reverse charge", "Total 35,00"]).steuerart == .reverseCharge)
        // gar kein VAT-Hinweis → Reverse-Charge (Auslands-Leistung)
        #expect(BelegOCR.extrahiere(aus: ["Anthropic", "Claude Pro", "Total 18,00"]).steuerart == .reverseCharge)
    }
}
