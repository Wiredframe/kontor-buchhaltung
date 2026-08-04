import CoreGraphics
import Foundation
import Testing

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
        #expect(zeilen.first == "Summe netto 3.145,00 €")  // links→rechts, oben→unten
        let d = BelegOCR.extrahiereEinnahme(aus: zeilen)
        #expect(d.rnNetto == dez("3145.00"))
        #expect(d.ust == dez("597.55"))  // Brutto − Netto
    }

    @Test func betragNormalisierung() {
        #expect(BelegOCR.normalisiere("35,00") == dez("35.00"))
        #expect(BelegOCR.normalisiere("1.234,56") == dez("1234.56"))  // de: Punkt = Tausender
        #expect(BelegOCR.normalisiere("1,234.56") == dez("1234.56"))  // en: Komma = Tausender
        #expect(BelegOCR.normalisiere("12.99") == dez("12.99"))
    }

    /// Deutscher Tausenderpunkt ohne Cent-Angabe: „1.500" ist 1500, nicht 1,50 – der
    /// Betrag wird sowohl beim Parsen als auch bei der Extraktion aus der Zeile korrekt.
    @Test func tausenderOhneNachkomma() {
        #expect(BelegOCR.normalisiere("1.500") == dez("1500"))
        #expect(BelegOCR.normalisiere("3.000") == dez("3000"))
        #expect(BelegOCR.normalisiere("1.234.567") == dez("1234567"))
        #expect(BelegOCR.betraege(in: "Gesamtbetrag 1.500 €") == [dez("1500")])
        #expect(BelegOCR.betraege(in: "Pauschale 3.000") == [dez("3000")])
        // Anschaffung > 1000 € mit Cent bleibt ebenfalls korrekt.
        #expect(BelegOCR.betraege(in: "Summe 1.499,00 €") == [dez("1499.00")])
    }

    /// OCR verwechselt Dezimaltrenner: „1.234,56" wird mal als „1.234.56" oder „1,234,56"
    /// gelesen. Der letzte Trenner mit zwei Folgeziffern ist der Dezimaltrenner.
    @Test func ocrDezimaltrennerVerwechslung() {
        #expect(BelegOCR.normalisiere("1.234.56") == dez("1234.56"))
        #expect(BelegOCR.normalisiere("1,234,56") == dez("1234.56"))
        #expect(BelegOCR.betraege(in: "Rechnungsbetrag 1.234.56") == [dez("1234.56")])
    }

    /// Tausender-Erkennung darf NICHT in vierstelligen Zahlen (Jahr im Datum, IBAN-Vierergruppen)
    /// falsch anschlagen – das `(?!\d)` hinter der Dreiergruppe verhindert das.
    @Test func tausenderKeinFalschtreffer() {
        let vomDatum = BelegOCR.betraege(in: "Rechnungsdatum: 14.06.2026")
        #expect(!vomDatum.contains(dez("6202")))
        #expect(!vomDatum.contains(dez("6.202")))
        #expect(BelegOCR.betraege(in: "IBAN DE00 0000 0000 0000 0000 00").isEmpty)
        // Der echte Betrag daneben gewinnt trotzdem als größter Betrag.
        #expect(BelegOCR.groessterBetrag(in: ["Rechnungsdatum: 14.06.2026", "Gesamt 1.234,56 €"]) == dez("1234.56"))
    }

    /// Schmale/geschützte Leerzeichen als Tausender-Trenner (aus PDF-Layouts) werden erkannt.
    @Test func schmalesLeerzeichenAlsTausender() {
        #expect(BelegOCR.normalisiere("1\u{202F}234,56") == dez("1234.56"))
        #expect(BelegOCR.betraege(in: "Betrag 1\u{00A0}234,56 €") == [dez("1234.56")])
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
            f(
                "Zahlungsinformationen: Musterbank Berlin • IBAN: DE00 0000 0000 0000 0000 00 • BIC: ABCDDEFFXXX",
                x: 0.06, y: 0.045),
        ]
        #expect(BelegOCR.empfaenger(frag) == "Nordstern Studio GmbH")
        #expect(BelegOCR.betragRechtsVomLabel(["summe netto", "netto"], frag) == dez("3145.00"))
        #expect(BelegOCR.betragRechtsVomLabel(["ust", "mwst"], frag) == dez("597.55"))  // nicht UStID, nicht 37
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
        #expect(d.anbieter == "Figma")  // bekannter Anbieter
        #expect(d.brutto == dez("35.00"))  // „Gesamtbetrag"
        #expect(d.vst == dez("5.59"))  // „MwSt"
        #expect(d.steuerart == .inland19)  // MwSt vorhanden → Inland 19 %
        #expect(d.rechnungsnummer == "0027")  // RN auch für Ausgaben extrahiert (Bank-Matching)
        let c = appKalender.dateComponents([.year, .month, .day], from: d.datum ?? .distantPast)
        #expect(c.year == 2026 && c.month == 6 && c.day == 14)
    }

    @Test func mehrwertsteuerAusgeschrieben() {
        // USt-Zeile als ausgeschriebenes „Mehrwertsteuer" (auch „Mehrwert-Steuer" via Wortstamm).
        let d = BelegOCR.extrahiere(aus: [
            "Anbieter X", "Netto 100,00", "Mehrwertsteuer 19 % 19,00", "Gesamtbetrag 119,00",
        ])
        #expect(d.vst == dez("19.00"))
        #expect(d.steuerart == .inland19)
        #expect(BelegOCR.extrahiere(aus: ["Mehrwert-Steuer 19,00", "Gesamt 119,00"]).vst == dez("19.00"))
    }

    @Test func groessterBetragAlsFallback() {
        let d = BelegOCR.extrahiere(aus: ["Beleg ohne Schlagworte", "Posten A 10,00", "Posten B 119,00"])
        #expect(d.brutto == dez("119.00"))  // kein „Gesamt" → größter Betrag
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
        #expect(d.ust == dez("570.00"))  // Brutto − Netto, nicht aus „UStID"
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
            "Bill to Lena Brandt",
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

    // MARK: - Gehärtete Betragserkennung

    /// Der häufigste Fehlgriff: „MwSt 19,00 %" ohne weiteren Betrag in der Zeile machte den
    /// **Steuersatz** zur Vorsteuer. Prozentangaben sind keine Geldbeträge.
    @Test func prozentangabeIstKeinBetrag() {
        #expect(BelegOCR.betraege(in: "MwSt 19,00 % auf Netto").isEmpty)
        #expect(BelegOCR.betraege(in: "Rabatt 7,50%").isEmpty)
        // Betrag in derselben Zeile bleibt erhalten, nur die Prozentzahl fällt weg.
        #expect(BelegOCR.betraege(in: "MwSt 19,00 % 66,50 €") == [dez("66.50")])
        let d = BelegOCR.extrahiere(aus: ["Anbieter", "MwSt 19,00 %", "Gesamtbetrag 119,00"])
        #expect(d.vst == dez("19.00"))  // aus dem Brutto abgeleitet, nicht die 19,00 % übernommen
        #expect(d.unsicher.contains(.vst))
    }

    /// Nach der Zeilenrekonstruktion steht ein Summenblock oft in **einer** Zeile. Vorher lieferte
    /// `max()` über die Zeile für jedes Label denselben (größten) Wert, also die MwSt = Gesamt.
    @Test func summenblockInEinerZeile() {
        let zeile = "Zwischensumme 350,00 MwSt 19 % 66,50 Gesamt 416,50"
        #expect(BelegOCR.betragNach("mwst", in: zeile) == dez("66.50"))
        #expect(BelegOCR.betragNach("zwischensumme", in: zeile) == dez("350.00"))
        #expect(BelegOCR.betragNach("gesamt", in: zeile) == dez("416.50"))
        let d = BelegOCR.extrahiere(aus: ["Werkstatt Meier", zeile])
        #expect(d.brutto == dez("416.50"))
        #expect(d.vst == dez("66.50"))
        #expect(!d.unsicher.contains(.vst))  // 66,50 passt zu 19 % von 416,50 → bestätigt
    }

    /// Steht das nächste Label noch vor dem Betrag („Total excluding tax €50.00"), darf die
    /// Segmentgrenze den Betrag nicht wegschneiden.
    @Test func labelGrenzeVerschlucktBetragNicht() {
        #expect(BelegOCR.betragNach("total", in: "Total excluding tax €50.00") == dez("50.00"))
    }

    /// Ziffern, die an Buchstaben kleben, sind Referenzen und keine Beträge.
    @Test func referenznummerIstKeinBetrag() {
        #expect(BelegOCR.betraege(in: "Auftrag A123,45 bestätigt").isEmpty)
        #expect(BelegOCR.betraege(in: "Kundennummer 4711 vom 14.06.2026").isEmpty)
    }

    // MARK: - Plausibilisierung

    /// Passt die gefundene Vorsteuer zu keinem Satz, wird sie aus dem Brutto abgeleitet und das
    /// Feld markiert – statt einen offensichtlich falschen Wert still zu übernehmen.
    @Test func unpassendeVorsteuerWirdKorrigiert() {
        let d = BelegOCR.plausibilisiere(
            BelegDaten(brutto: dez("119.00"), vst: dez("100.00"), steuerart: .inland19))
        #expect(d.vst == dez("19.00"))
        #expect(d.unsicher.contains(.vst))
        #expect(d.unsicher.contains(.steuerart))
    }

    /// Ein zum Brutto passender 7-%-Betrag bestätigt den ermäßigten Satz, auch wenn die
    /// Textheuristik auf 19 % getippt hatte.
    @Test func vorsteuerBestaetigtSatz() {
        let d = BelegOCR.plausibilisiere(
            BelegDaten(brutto: dez("42.80"), vst: dez("2.80"), steuerart: .inland19))
        #expect(d.steuerart == .inland7)
        #expect(d.vst == dez("2.80"))
        #expect(!d.unsicher.contains(.vst))
    }

    /// Reverse-Charge zieht nie Vorsteuer; eine trotzdem erkannte wird auf 0 gesetzt und markiert.
    @Test func reverseChargeOhneVorsteuer() {
        let d = BelegOCR.plausibilisiere(
            BelegDaten(brutto: dez("35.00"), vst: dez("5.59"), steuerart: .reverseCharge))
        #expect(d.vst == 0)
        #expect(d.unsicher.contains(.vst))
    }

    /// Eine **explizit** mit 0 ausgewiesene Steuer (Kleinunternehmer, 0-%-Ausweis) wird nicht
    /// überschrieben – erfunden wird Vorsteuer nur, wo gar nichts gefunden wurde.
    @Test func ausgewieseneNullBleibtNull() {
        let d = BelegOCR.plausibilisiere(
            BelegDaten(brutto: dez("100.00"), vst: 0, steuerart: .inland19))
        #expect(d.vst == 0)
        #expect(d.unsicher.contains(.vst))
    }

    /// Kleinunternehmer-Hinweis: keine Vorsteuer erfinden, nur weil „Umsatzsteuer" im Text steht.
    @Test func kleinunternehmerOhneVorsteuer() {
        let d = BelegOCR.extrahiere(aus: [
            "Atelier Sonnfeld", "Leistung 200,00", "Gemäß §19 UStG wird keine Umsatzsteuer berechnet",
            "Gesamtbetrag 200,00",
        ])
        #expect(d.steuerart == .steuerfrei)
        #expect(d.vst == 0)
    }

    // MARK: - Rechnungsnummer, Anbieter, Steuerart

    /// Englische Belege: „Invoice number …" wurde vorher gar nicht gefunden – ausgerechnet dort,
    /// wo die Nummer als Bank-Matching-Schlüssel am wichtigsten ist.
    @Test func rechnungsnummerEnglisch() {
        #expect(BelegOCR.rechnungsnummer(in: ["Invoice number 86C79197-0015"]) == "86C79197-0015")
        #expect(BelegOCR.rechnungsnummer(in: ["Invoice #A-1234"]) == "A-1234")
        #expect(BelegOCR.rechnungsnummer(in: ["Invoice", "Invoice no: 2026-014"]) == "2026-014")
        #expect(BelegOCR.rechnungsnummer(in: ["Receipt 5567123"]) == "5567123")
        // Rechnungs*datum* trägt keine Nummer
        #expect(BelegOCR.rechnungsnummer(in: ["Rechnungsdatum: 14.06.2026"]) == nil)
        // deutsche Formen unverändert
        #expect(BelegOCR.rechnungsnummer(in: ["Rechnung Nr. 0027"]) == "0027")
        #expect(BelegOCR.rechnungsnummer(in: ["Rechnung #202605261"]) == "202605261")
    }

    @Test func anbieterAusKatalogUndDomain() {
        // Der Katalog (bereits erfasste Anbieter des Nutzers) schlägt die generische Heuristik.
        #expect(
            BelegOCR.anbieter(in: ["Zahlungsbeleg", "Nordwind Hosting GmbH", "Betrag 12,99"], katalog: ["Nordwind Hosting"])
                == "Nordwind Hosting")
        // Domain/Mailadresse als Quelle
        #expect(BelegOCR.anbieterAusDomain(in: "Fragen an billing@nordwind-hosting.de") == "Nordwind-Hosting")
        #expect(BelegOCR.anbieterAusDomain(in: "Kontakt: mail@gmail.com") == nil)  // freier Mailhoster
        // Stoppwörter sind kein Anbieter
        #expect(BelegOCR.anbieter(in: ["Rechnung", "Seite 1", "Buchbinderei Kalt"]) == "Buchbinderei Kalt")
    }

    /// „19 % Rabatt" ist kein Steuerhinweis – vorher wurde daraus eine Inlandsrechnung mit
    /// erfundener Vorsteuer.
    @Test func prozentOhneSteuerwortZaehltNicht() {
        let d = BelegOCR.extrahiere(aus: ["Studio Nordlicht", "19 % Rabatt auf alle Posten", "Total 100,00"])
        #expect(d.steuerart == .reverseCharge)  // kein Steuerwort → wie bisher Auslands-/RC-Annahme
        #expect(d.vst == 0)
    }

    /// Ausländische USt-IdNr des Ausstellers ist ein Reverse-Charge-Indiz, die deutsche nicht.
    @Test func auslaendischeUstIdAlsIndiz() {
        #expect(BelegOCR.auslaendischeUstId(in: ["vat id ie6388047v"]))
        #expect(BelegOCR.auslaendischeUstId(in: ["ustid de300000007"]) == false)
        #expect(BelegOCR.auslaendischeUstId(in: ["bestellnummer ab12345678"]) == false)  // kein ID-Kontext
    }

    // MARK: - PDF-Textlayer

    /// Digitale Rechnungen tragen ihren Text exakt in sich: der Textlayer wird gelesen, nicht
    /// gerastert und zurückerkannt. Das Layout entspricht einer typischen Eingangsrechnung mit
    /// Positionstabelle **und** Summenblock – die MwSt muss aus dem Summenblock kommen.
    @Test func pdfTextlayerStattOCR() async {
        let url = machePDF([
            PDFText("Nordwind Hosting GmbH", x: 60, y: 780, groesse: 14),
            PDFText("Rechnung Nr. 2026-0815", x: 60, y: 750),
            PDFText("Rechnungsdatum: 12.03.2026", x: 60, y: 730),
            // Positionszeile mit eigener MwSt-Spalte (darf den Summenblock nicht verdrängen)
            PDFText("Webhosting Paket M", x: 60, y: 640),
            PDFText("19 %", x: 330, y: 640),
            PDFText("42,02", x: 470, y: 640),
            PDFText("Domain .de", x: 60, y: 620),
            PDFText("19 %", x: 330, y: 620),
            PDFText("10,08", x: 470, y: 620),
            // Summenblock
            PDFText("Zwischensumme", x: 330, y: 540),
            PDFText("52,10", x: 470, y: 540),
            PDFText("MwSt 19 %", x: 330, y: 520),
            PDFText("9,90", x: 470, y: 520),
            PDFText("Gesamtbetrag", x: 330, y: 500),
            PDFText("62,00", x: 470, y: 500),
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let seiten = BelegOCR.seiten(von: url)
        if case .bild = seiten.first { Issue.record("Textlayer wurde nicht erkannt, es lief OCR") }

        let d = await BelegOCR.analysiere(url)
        #expect(d.brutto == dez("62.00"))
        #expect(d.vst == dez("9.90"))  // aus dem Summenblock, nicht aus einer Positionszeile
        #expect(d.steuerart == .inland19)
        #expect(d.rechnungsnummer == "2026-0815")
        #expect(d.anbieter == "Nordwind Hosting GmbH")
        #expect(d.unsicher.isEmpty)
        let c = appKalender.dateComponents([.year, .month, .day], from: d.datum ?? .distantPast)
        #expect(c.year == 2026 && c.month == 3 && c.day == 12)
    }

    /// Englische Auslandsrechnung als PDF: Reverse-Charge, keine Vorsteuer, Nummer gefunden.
    @Test func pdfEnglischeReverseCharge() async {
        let url = machePDF([
            PDFText("Figma, Inc.", x: 60, y: 780, groesse: 14),
            PDFText("Invoice number 86C79197-0015", x: 60, y: 750),
            PDFText("Date of issue June 4, 2025", x: 60, y: 730),
            PDFText("Subtotal", x: 330, y: 560),
            PDFText("EUR 50.00", x: 470, y: 560),
            PDFText("Total", x: 330, y: 520),
            PDFText("EUR 50.00", x: 470, y: 520),
            PDFText("Tax to be paid on reverse charge basis", x: 60, y: 460),
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let d = await BelegOCR.analysiere(url)
        #expect(d.anbieter == "Figma")
        #expect(d.brutto == dez("50.00"))
        #expect(d.steuerart == .reverseCharge)
        #expect(d.vst == 0)
        #expect(d.rechnungsnummer == "86C79197-0015")
    }

    @Test func steuerartErkennung() {
        // MwSt-Zeile → Inland; VSt-Betrag aus der Folgezeile
        let inland = BelegOCR.extrahiere(aus: [
            "DomainFactory", "Netto 10,92", "zzgl. 19 % MwSt", "2,07", "Gesamt 12,99",
        ])
        #expect(inland.steuerart == .inland19)
        #expect(inland.vst == dez("2.07"))  // Betrag stand in der Folgezeile
        // expliziter Reverse-Charge-Hinweis
        #expect(BelegOCR.extrahiere(aus: ["Figma", "Reverse charge", "Total 35,00"]).steuerart == .reverseCharge)
        // gar kein VAT-Hinweis → Reverse-Charge (Auslands-Leistung)
        #expect(BelegOCR.extrahiere(aus: ["Anthropic", "Claude Pro", "Total 18,00"]).steuerart == .reverseCharge)
        // ermäßigter Satz: 7-%-Hinweis ohne 19 % → Inland 7 %
        #expect(
            BelegOCR.extrahiere(aus: ["Buchhandlung", "Netto 40,00", "zzgl. 7 % MwSt", "2,80", "Gesamt 42,80"])
                .steuerart == .inland7)
        // Mischbeleg (7 % UND 19 %) → Regelsatz 19 %
        #expect(BelegOCR.extrahiere(aus: ["Kiosk", "7 % MwSt", "19 % MwSt", "Gesamt 50,00"]).steuerart == .inland19)
    }
}
