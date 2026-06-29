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

    /// Realistisches Zwei-Spalten-Layout einer eigenen Ausgangsrechnung (Empfänger links,
    /// Absender-Kontakt rechts, Positionszeile mit Stundenzahl neben dem Betrag, USt-IdNr.):
    /// Empfänger muss aus der linken Spalte kommen, die USt aus Brutto − Netto – nicht aus der
    /// Stundenzahl oder der USt-IdNr.
    @Test func ausgangsrechnungZweiSpalten() {
        let h: CGFloat = 0.012
        func f(_ t: String, x: CGFloat, y: CGFloat) -> BelegOCR.TextFragment {
            BelegOCR.TextFragment(text: t, box: CGRect(x: x, y: y, width: 0.18, height: h))
        }
        let frag = [
            f("Lena Brandt • Oranienstraße 40 • 10999 Berlin", x: 0.06, y: 0.840),
            f("Nordstern Studio GmbH", x: 0.06, y: 0.815),
            f("Chausseestraße 5", x: 0.06, y: 0.800),
            f("10115 Berlin", x: 0.06, y: 0.785),
            // rechte Absender-Kontaktspalte (darf NICHT als Empfänger gewählt werden)
            f("Lena Brandt", x: 0.72, y: 0.740),
            f("Freiberufliche UI Designerin", x: 0.55, y: 0.725),
            f("10999 Berlin", x: 0.74, y: 0.690),
            f("UStID DE300000007", x: 0.62, y: 0.600),
            f("Rechnungsdatum: 26.05.2026", x: 0.58, y: 0.585),
            f("Rechnung #202605261", x: 0.06, y: 0.530),
            // Positionszeile: Stundenzahl 37 und Einzelpreis stehen neben dem Betrag
            f("Konzeption, Gestaltung und UI-Design – Website-Relaunch", x: 0.06, y: 0.400),
            f("37", x: 0.66, y: 0.400), f("85,00 €", x: 0.74, y: 0.400), f("3.145,00 €", x: 0.86, y: 0.400),
            // Summenblock (Label links, Betrag rechtsbündig)
            f("Summe netto", x: 0.66, y: 0.340), f("3.145,00 €", x: 0.86, y: 0.340),
            f("USt. (19%)", x: 0.66, y: 0.318), f("597,55 €", x: 0.86, y: 0.318),
            f("Gesamtbetrag", x: 0.66, y: 0.296), f("3.742,55 €", x: 0.86, y: 0.296),
            f("Zahlungsinformationen: Musterbank Berlin • IBAN: DE00 0000 0000 0000 0000 00 • BIC: ABCDDEFFXXX", x: 0.06, y: 0.045),
        ]
        #expect(BelegOCR.empfaenger(frag) == "Nordstern Studio GmbH")
        #expect(BelegOCR.betragRechtsVomLabel(["summe netto", "netto"], frag) == dez("3145.00"))
        #expect(BelegOCR.betragRechtsVomLabel(["ust", "mwst"], frag) == dez("597.55"))   // nicht UStID, nicht 37
        let d = BelegOCR.extrahiereEinnahme(fragmente: frag)
        #expect(d.kunde == "Nordstern Studio GmbH")
        #expect(d.rnNetto == dez("3145.00"))
        #expect(d.ust == dez("597.55"))
        #expect(d.rechnungsnummer == "202605261")
        let c = appKalender.dateComponents([.year, .month, .day], from: d.datum ?? .distantPast)
        #expect(c.year == 2026 && c.month == 5 && c.day == 26)
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

    @Test func mehrwertsteuerAusgeschrieben() {
        // USt-Zeile als ausgeschriebenes „Mehrwertsteuer" (auch „Mehrwert-Steuer" via Wortstamm).
        let d = BelegOCR.extrahiere(aus: ["Anbieter X", "Netto 100,00", "Mehrwertsteuer 19 % 19,00", "Gesamtbetrag 119,00"])
        #expect(d.vst == dez("19.00"))
        #expect(d.steuerart == .inland19)
        #expect(BelegOCR.extrahiere(aus: ["Mehrwert-Steuer 19,00", "Gesamt 119,00"]).vst == dez("19.00"))
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

    /// Englische Auslandsrechnungen (Figma/Anthropic) datieren als Monatsname – früher fiel das Datum
    /// komplett aus. „4. Juni 2025" deckt den dt. Monatsnamen mit ab.
    @Test func englischeUndBenannteDatumsformate() {
        func ymd(_ s: String) -> (Int, Int, Int)? {
            BelegOCR.ersteDatum(in: [s]).map {
                let c = appKalender.dateComponents([.year, .month, .day], from: $0)
                return (c.year!, c.month!, c.day!)
            }
        }
        #expect(ymd("Date of issue June 4, 2025").map { $0 == (2025, 6, 4) } == true)
        #expect(ymd("Jun 4, 2025").map { $0 == (2025, 6, 4) } == true)
        #expect(ymd("4 June 2025").map { $0 == (2025, 6, 4) } == true)
        #expect(ymd("Rechnungsdatum: 4. Juni 2025").map { $0 == (2025, 6, 4) } == true)
        // Numerische Formate weiterhin unverändert
        #expect(ymd("Rechnungsdatum: 14.06.2026").map { $0 == (2026, 6, 14) } == true)
        // Rechnungsnummer mit Ziffern darf NICHT als Datum durchgehen
        #expect(BelegOCR.ersteDatum(in: ["Invoice number 86C79197-0015"]) == nil)
    }

    /// Komplette englische Figma-Rechnung (Reverse-Charge, 0 % VAT): Datum aus „June 4, 2025",
    /// Steuerart §13b aus „reverse charge basis", Betrag aus „Total".
    @Test func englischeReverseChargeRechnung() {
        let zeilen = [
            "Invoice",
            "Invoice number 86C79197-0015",
            "Date of issue June 4, 2025",
            "Date due June 4, 2025",
            "Figma, Inc.",
            "Bill to Ulf Schuster",
            "Subtotal €50.00",
            "Total excluding tax €50.00",
            "Tax (0% on €50.00) €0.00",
            "Total €50.00",
            "Amount due €50.00",
            "Tax to be paid on reverse charge basis",
        ]
        let d = BelegOCR.extrahiere(aus: zeilen)
        #expect(d.anbieter == "Figma")
        #expect(d.steuerart == .reverseCharge)
        #expect(d.brutto == dez("50.00"))
        let c = appKalender.dateComponents([.year, .month, .day], from: d.datum ?? .distantPast)
        #expect(c.year == 2025 && c.month == 6 && c.day == 4)
    }

    /// „Amount due" muss vor „Total" greifen – sonst zieht „Total excluding tax" (= Netto bei VAT≠0)
    /// den falschen Betrag. Geometrie-Pfad (rechtsbündige Beträge je Zeile).
    @Test func amountDueSchlaegtNettoZeile() {
        let h: CGFloat = 0.02
        func f(_ t: String, x: CGFloat, y: CGFloat) -> BelegOCR.TextFragment {
            BelegOCR.TextFragment(text: t, box: CGRect(x: x, y: y, width: 0.2, height: h))
        }
        let frag = [
            f("Subtotal", x: 0.50, y: 0.34), f("£100.00", x: 0.85, y: 0.34),
            f("Total excluding tax", x: 0.50, y: 0.30), f("£100.00", x: 0.85, y: 0.30),
            f("VAT (20%)", x: 0.50, y: 0.26), f("£20.00", x: 0.85, y: 0.26),
            f("Total", x: 0.50, y: 0.18), f("£120.00", x: 0.85, y: 0.18),
            f("Amount due", x: 0.50, y: 0.14), f("£120.00", x: 0.85, y: 0.14),
        ]
        #expect(BelegOCR.betragRechtsVomLabel(["amount due", "total"], frag) == dez("120.00"))
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
