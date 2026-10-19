import CoreGraphics
import Foundation

/// Liest die **eingebettete E-Rechnung** (ZUGFeRD/Factur-X, also CII-XML im PDF) eines Belegs.
///
/// Trägt ein PDF seine Rechnungsdaten maschinenlesbar mit, sind Betrag, Steuer, Datum, Nummer und
/// Verkäufer **exakt** – die Texterkennung rät dort nur. Seit 2025 müssen Unternehmen E-Rechnungen
/// empfangen können, der Anteil solcher Belege wächst. Vorbild: wiredframe
/// (`documents._from_einvoice`/`_from_cii`); Kontor liest das XML ohne Fremdbibliothek.
///
/// Bewusst **vor** der Texterkennung und ohne deren Heuristiken: Wird nichts gefunden, bleibt
/// `BelegOCR` unverändert der Weg (Änderungen dort nur gegen den Echtbeleg-Korpus, siehe CLAUDE.md).
enum ERechnung {

    /// Belegdaten aus dem eingebetteten XML, `nil`, wenn das PDF keine E-Rechnung trägt.
    static func lies(_ url: URL) -> BelegDaten? {
        guard url.pathExtension.lowercased() == "pdf" else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let doc = CGPDFDocument(url as CFURL), let xml = eingebettetesXML(doc) else { return nil }
        return ausCII(xml)
    }

    /// Ausgangsrechnung (eigene E-Rechnung) → Einnahmedaten: Kunde ist der Käufer, Netto die
    /// Steuerbemessung. `nil` ohne eingebettete E-Rechnung.
    static func liesEinnahme(_ url: URL) -> EinnahmeDaten? {
        guard url.pathExtension.lowercased() == "pdf" else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let doc = CGPDFDocument(url as CFURL), let xml = eingebettetesXML(doc) else { return nil }
        return einnahmeAusCII(xml)
    }

    static func einnahmeAusCII(_ xml: Data) -> EinnahmeDaten? {
        guard let w = baum(xml), w.erstes("CrossIndustryInvoice") != nil, let beleg = ausCII(xml) else { return nil }
        let summe = w.erstes("SpecifiedTradeSettlementHeaderMonetarySummation")
        let posix = Locale(identifier: "en_US_POSIX")
        var netto = (summe?.kind("TaxBasisTotalAmount")?.wert).flatMap { Decimal(string: $0, locale: posix) }
        var ust = (summe?.kind("TaxTotalAmount")?.wert).flatMap { Decimal(string: $0, locale: posix) }
        if w.erstes("ExchangedDocument")?.kind("TypeCode")?.wert == "381" {
            netto = netto.map { -$0 }
            ust = ust.map { -$0 }
        }
        let kunde = w.erstes("BuyerTradeParty")?.kind("Name")?.wert
        return EinnahmeDaten(
            kunde: kunde?.isEmpty == false ? kunde : nil, datum: beleg.datum, rnNetto: netto, ust: ust,
            rechnungsnummer: beleg.rechnungsnummer)
    }

    // MARK: PDF: eingebettete Datei finden

    /// Namen, unter denen die Standards die XML ablegen (ZUGFeRD 1/2, Factur-X, XRechnung).
    private static let bekannteNamen = ["factur-x.xml", "zugferd-invoice.xml", "xrechnung.xml", "zugferd-invoice"]

    /// Durchsucht den Namensbaum `/Names /EmbeddedFiles` und liefert die XML der Rechnung.
    static func eingebettetesXML(_ doc: CGPDFDocument) -> Data? {
        guard let katalog = doc.catalog else { return nil }
        var namen: CGPDFDictionaryRef?
        var dateien: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(katalog, "Names", &namen), let namen,
            CGPDFDictionaryGetDictionary(namen, "EmbeddedFiles", &dateien), let dateien
        else { return nil }
        var gefunden: [(name: String, daten: Data)] = []
        sammle(dateien, in: &gefunden, tiefe: 0)
        let xml = gefunden.filter {
            $0.name.lowercased().hasSuffix(".xml") || bekannteNamen.contains($0.name.lowercased())
        }
        return (xml.first { bekannteNamen.contains($0.name.lowercased()) } ?? xml.first)?.daten
    }

    /// Ein Knoten des Namensbaums: `Names` = [Name, Filespec, …], `Kids` = Unterknoten.
    private static func sammle(_ knoten: CGPDFDictionaryRef, in liste: inout [(name: String, daten: Data)], tiefe: Int)
    {
        guard tiefe < 8 else { return }  // gegen zyklische Bäume in kaputten PDFs
        var kinder: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(knoten, "Kids", &kinder), let kinder {
            for i in 0..<CGPDFArrayGetCount(kinder) {
                var kind: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(kinder, i, &kind), let kind { sammle(kind, in: &liste, tiefe: tiefe + 1) }
            }
        }
        var eintraege: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(knoten, "Names", &eintraege), let eintraege else { return }
        var i = 0
        while i + 1 < CGPDFArrayGetCount(eintraege) {
            var name: CGPDFStringRef?
            var spec: CGPDFDictionaryRef?
            if CGPDFArrayGetString(eintraege, i, &name), let name, CGPDFArrayGetDictionary(eintraege, i + 1, &spec),
                let spec, let daten = dateiInhalt(spec)
            {
                let text = (CGPDFStringCopyTextString(name) as String?) ?? ""
                liste.append((text, daten))
            }
            i += 2
        }
    }

    private static func dateiInhalt(_ spec: CGPDFDictionaryRef) -> Data? {
        var ef: CGPDFDictionaryRef?
        var strom: CGPDFStreamRef?
        guard CGPDFDictionaryGetDictionary(spec, "EF", &ef), let ef,
            CGPDFDictionaryGetStream(ef, "F", &strom) || CGPDFDictionaryGetStream(ef, "UF", &strom), let strom
        else { return nil }
        var format = CGPDFDataFormat.raw
        guard let daten = CGPDFStreamCopyData(strom, &format), format == .raw else { return nil }
        return daten as Data
    }

    // MARK: CII auslesen

    /// Ein Element des XML-Baums, Namen ohne Präfix.
    final class Knoten {
        let name: String
        var text = ""
        var kinder: [Knoten] = []
        weak var eltern: Knoten?
        init(_ name: String, eltern: Knoten?) {
            self.name = name
            self.eltern = eltern
        }

        /// Erstes Element mit diesem Namen in Tiefensuche (dieser Knoten eingeschlossen).
        func erstes(_ n: String) -> Knoten? {
            if name == n { return self }
            for k in kinder { if let t = k.erstes(n) { return t } }
            return nil
        }
        /// Direktes Kind.
        func kind(_ n: String) -> Knoten? { kinder.first { $0.name == n } }
        var wert: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private final class Leser: NSObject, XMLParserDelegate {
        let wurzel = Knoten("#", eltern: nil)
        lazy var aktuell: Knoten = wurzel
        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            let lokal = name.split(separator: ":").last.map(String.init) ?? name
            let k = Knoten(lokal, eltern: aktuell)
            aktuell.kinder.append(k)
            aktuell = k
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { aktuell.text += string }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            aktuell = aktuell.eltern ?? wurzel
        }
    }

    static func baum(_ xml: Data) -> Knoten? {
        let parser = XMLParser(data: xml)
        let leser = Leser()
        parser.delegate = leser
        parser.shouldResolveExternalEntities = false  // keine externen Entitäten aus fremden Dateien
        guard parser.parse() else { return nil }
        return leser.wurzel
    }

    /// CII (`CrossIndustryInvoice`) → Belegdaten. Gutschrift (Typ 381): Beträge stehen positiv
    /// im XML und werden negativ übernommen.
    static func ausCII(_ xml: Data) -> BelegDaten? {
        guard let w = baum(xml), w.erstes("CrossIndustryInvoice") != nil else { return nil }
        func betrag(_ n: String) -> Decimal? {
            guard let v = w.erstes(n)?.wert, !v.isEmpty else { return nil }
            return Decimal(string: v, locale: Locale(identifier: "en_US_POSIX"))
        }
        let summe = w.erstes("SpecifiedTradeSettlementHeaderMonetarySummation")
        // Fremdwährung: Kontor bucht nur Euro (`brutto` = Abfluss in Euro) – dann rät die
        // Texterkennung bzw. der Nutzer, nicht das XML.
        if let code = w.erstes("InvoiceCurrencyCode")?.wert, !code.isEmpty, code.uppercased() != "EUR" {
            return nil
        }
        // Rechnungsbetrag, **nicht** der Zahlbetrag: Eine schon bezahlte Shop-Rechnung hat
        // `DuePayableAmount` 0,00, eine mit Anzahlung nur den Rest (wiredframe nimmt ebenso GrandTotal).
        var brutto =
            (summe?.kind("GrandTotalAmount")?.wert).flatMap {
                Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
            }
            ?? betrag("GrandTotalAmount")
        var steuer = (summe?.kind("TaxTotalAmount")?.wert).flatMap {
            Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
        }
        let dokument = w.erstes("ExchangedDocument")
        if dokument?.kind("TypeCode")?.wert == "381" {
            brutto = brutto.map { -$0 }
            steuer = steuer.map { -$0 }
        }
        guard brutto != nil else { return nil }

        var datum: Date?
        if let roh = dokument?.kind("IssueDateTime")?.erstes("DateTimeString")?.wert, roh.count >= 8,
            let j = Int(roh.prefix(4)), let m = Int(roh.dropFirst(4).prefix(2)), let t = Int(roh.dropFirst(6).prefix(2))
        {
            let c = DateComponents(year: j, month: m, day: t)
            if c.isValidDate(in: appKalender) { datum = appKalender.date(from: c) }
        }

        // Steuerart aus der (ersten) Steuerkategorie des Belegs: AE = Reverse-Charge,
        // E/Z/O/K/G = ohne deutsche Vorsteuer, S mit 7 % bzw. 19 %.
        let steuerKnoten = w.erstes("ApplicableHeaderTradeSettlement")?.kind("ApplicableTradeTax")
        let kategorie = steuerKnoten?.kind("CategoryCode")?.wert ?? ""
        let satz = steuerKnoten?.kind("RateApplicablePercent")?.wert ?? ""
        let steuerart: Steuerart? =
            switch kategorie {
            case "AE": .reverseCharge
            case "E", "Z", "O", "K", "G": .steuerfrei
            case "S", "AA":
                (Decimal(string: satz, locale: Locale(identifier: "en_US_POSIX")) == 7) ? .inland7 : .inland19
            default: nil
            }
        let verkaeufer = w.erstes("SellerTradeParty")?.kind("Name")?.wert
        let nummer = dokument?.kind("ID")?.wert
        return BelegDaten(
            anbieter: verkaeufer?.isEmpty == false ? verkaeufer : nil, datum: datum, brutto: brutto,
            vst: (steuerart?.ziehtVorsteuer ?? true) ? steuer : 0, steuerart: steuerart,
            rechnungsnummer: nummer?.isEmpty == false ? nummer : nil)
    }
}
