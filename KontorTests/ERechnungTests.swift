import CoreGraphics
import Foundation
import Testing

@testable import Kontor

/// Eingebettete E-Rechnung (ZUGFeRD/Factur-X, CII) lesen – an einem von Hand gebauten PDF mit
/// synthetischer Rechnung, damit der PDF-Pfad (Namensbaum, Filespec, Stream) mitgeprüft wird.
struct ERechnungTests {

    private func cii(typ: String = "380", kategorie: String = "S", satz: String = "19.00") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100" xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100" xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">
          <rsm:ExchangedDocumentContext><ram:GuidelineSpecifiedDocumentContextParameter><ram:ID>urn:cen.eu:en16931:2017</ram:ID></ram:GuidelineSpecifiedDocumentContextParameter></rsm:ExchangedDocumentContext>
          <rsm:ExchangedDocument>
            <ram:ID>RE-2026-0815</ram:ID>
            <ram:TypeCode>\(typ)</ram:TypeCode>
            <ram:IssueDateTime><udt:DateTimeString format="102">20261014</udt:DateTimeString></ram:IssueDateTime>
          </rsm:ExchangedDocument>
          <rsm:SupplyChainTradeTransaction>
            <ram:ApplicableHeaderTradeAgreement>
              <ram:SellerTradeParty><ram:Name>Fotohaus Mitte GmbH</ram:Name></ram:SellerTradeParty>
              <ram:BuyerTradeParty><ram:Name>Studio Brandt</ram:Name></ram:BuyerTradeParty>
            </ram:ApplicableHeaderTradeAgreement>
            <ram:ApplicableHeaderTradeSettlement>
              <ram:ApplicableTradeTax>
                <ram:CalculatedAmount>399.00</ram:CalculatedAmount>
                <ram:CategoryCode>\(kategorie)</ram:CategoryCode>
                <ram:RateApplicablePercent>\(satz)</ram:RateApplicablePercent>
              </ram:ApplicableTradeTax>
              <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
                <ram:TaxBasisTotalAmount>2100.00</ram:TaxBasisTotalAmount>
                <ram:TaxTotalAmount currencyID="EUR">399.00</ram:TaxTotalAmount>
                <ram:GrandTotalAmount>2499.00</ram:GrandTotalAmount>
                <ram:DuePayableAmount>2499.00</ram:DuePayableAmount>
              </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
            </ram:ApplicableHeaderTradeSettlement>
          </rsm:SupplyChainTradeTransaction>
        </rsm:CrossIndustryInvoice>
        """
    }

    /// Minimales PDF mit `/Names /EmbeddedFiles` und korrekter xref-Tabelle.
    private func pdf(mitAnhang xml: String, name: String = "factur-x.xml") throws -> URL {
        let objekte = [
            "<< /Type /Catalog /Pages 2 0 R /Names << /EmbeddedFiles << /Names [(\(name)) 4 0 R] >> >> >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>",
            "<< /Type /Filespec /F (\(name)) /EF << /F 5 0 R >> >>",
            "<< /Type /EmbeddedFile /Length \(xml.utf8.count) >>\nstream\n\(xml)\nendstream",
        ]
        var text = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (i, o) in objekte.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(i + 1) 0 obj\n\(o)\nendobj\n"
        }
        let xref = text.utf8.count
        text += "xref\n0 \(objekte.count + 1)\n0000000000 65535 f \n"
        for o in offsets { text += String(format: "%010d 00000 n \n", o) }
        text += "trailer\n<< /Size \(objekte.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kontor-erechnung-\(UUID()).pdf")
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func liestEingebetteteRechnung() throws {
        let url = try pdf(mitAnhang: cii())
        defer { try? FileManager.default.removeItem(at: url) }
        let d = try #require(ERechnung.lies(url))
        #expect(d.anbieter == "Fotohaus Mitte GmbH")
        #expect(d.brutto == dez("2499") && d.vst == dez("399") && d.steuerart == .inland19)
        #expect(d.rechnungsnummer == "RE-2026-0815")
        #expect(d.datum == tag(2026, 10, 14))

        let e = try #require(ERechnung.liesEinnahme(url))
        #expect(e.kunde == "Studio Brandt" && e.rnNetto == dez("2100") && e.ust == dez("399"))
    }

    @Test func gutschriftUndReverseCharge() throws {
        let gut = try #require(ERechnung.ausCII(Data(cii(typ: "381").utf8)))
        #expect(gut.brutto == dez("-2499") && gut.vst == dez("-399"))
        let rc = try #require(ERechnung.ausCII(Data(cii(kategorie: "AE", satz: "0").utf8)))
        #expect(rc.steuerart == .reverseCharge && rc.vst == 0)
        let sieben = try #require(ERechnung.ausCII(Data(cii(satz: "7").utf8)))
        #expect(sieben.steuerart == .inland7)
    }

    /// Schon bezahlte Shop-Rechnung: Zahlbetrag 0, maßgeblich bleibt der Rechnungsbetrag.
    @Test func bezahlteRechnungNimmtGesamtbetrag() throws {
        let xml = cii().replacingOccurrences(
            of: "<ram:DuePayableAmount>2499.00</ram:DuePayableAmount>",
            with:
                "<ram:TotalPrepaidAmount>2499.00</ram:TotalPrepaidAmount><ram:DuePayableAmount>0.00</ram:DuePayableAmount>"
        )
        #expect(ERechnung.ausCII(Data(xml.utf8))?.brutto == dez("2499"))
        let usd = cii().replacingOccurrences(
            of: "<rsm:SupplyChainTradeTransaction>",
            with: "<rsm:SupplyChainTradeTransaction><ram:InvoiceCurrencyCode>USD</ram:InvoiceCurrencyCode>")
        #expect(ERechnung.ausCII(Data(usd.utf8)) == nil)
    }

    @Test func ohneAnhangOderFremdesXMLNil() throws {
        let fremd = try pdf(mitAnhang: "<?xml version=\"1.0\"?><Bestellung><ID>1</ID></Bestellung>", name: "daten.xml")
        defer { try? FileManager.default.removeItem(at: fremd) }
        #expect(ERechnung.lies(fremd) == nil)
        #expect(ERechnung.ausCII(Data("kein xml".utf8)) == nil)
        #expect(ERechnung.lies(URL(fileURLWithPath: "/tmp/beleg.png")) == nil)
    }
}
