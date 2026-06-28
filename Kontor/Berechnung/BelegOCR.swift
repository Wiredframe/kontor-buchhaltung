import Foundation
import Vision
import PDFKit
import AppKit

struct BelegDaten {
    var anbieter: String?
    var datum: Date?
    var brutto: Decimal?
    var vst: Decimal?
    var steuerart: Steuerart?
    var rechnungsnummer: String?
}

/// Felder einer Ausgangs-(Einnahmen-)Rechnung (OCR-Extraktion).
struct EinnahmeDaten {
    var kunde: String?
    var datum: Date?
    var rnNetto: Decimal?
    var ust: Decimal?
    var rechnungsnummer: String?
}

/// On-Device-OCR (Apple Vision) für Belege + heuristische Feld-Extraktion.
enum BelegOCR {

    /// Wie viele PDF-Seiten höchstens gelesen werden (Beträge/Summen stehen oft erst auf S. 2).
    static let maxSeiten = 2

    static func analysiere(_ url: URL) async -> BelegDaten {
        extrahiere(fragmente: await fragmente(von: url))
    }

    static func analysiereEinnahme(_ url: URL) async -> EinnahmeDaten {
        extrahiereEinnahme(fragmente: await fragmente(von: url))
    }

    // MARK: - Bilder laden (bis zu `maxSeiten` PDF-Seiten oder eine Bilddatei)

    private static func bilder(von url: URL) -> [CGImage] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
            return (0..<min(doc.pageCount, maxSeiten)).compactMap { doc.page(at: $0).flatMap(rendere) }
        }
        if let img = NSImage(contentsOf: url) {
            var r = NSRect(origin: .zero, size: img.size)
            if let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil) { return [cg] }
        }
        return []
    }

    /// Rendert eine PDF-Seite als CGImage (2,5× für bessere Texterkennung).
    private static func rendere(_ page: PDFPage) -> CGImage? {
        let rect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.5
        let groesse = NSSize(width: rect.width * scale, height: rect.height * scale)
        guard groesse.width > 0, groesse.height > 0 else { return nil }
        let img = NSImage(size: groesse)
        img.lockFocus()
        NSColor.white.setFill(); NSRect(origin: .zero, size: groesse).fill()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
        }
        img.unlockFocus()
        var r = NSRect(origin: .zero, size: groesse)
        return img.cgImage(forProposedRect: &r, context: nil, hints: nil)
    }

    /// Fragmente über mehrere Seiten – Folgeseiten werden in y nach unten verschoben, damit die
    /// Lesereihenfolge (Kopf/Kunde/Datum S. 1, Summen ggf. S. 2) erhalten bleibt.
    private static func fragmente(von url: URL) async -> [TextFragment] {
        var alle: [TextFragment] = []
        for (i, cg) in bilder(von: url).enumerated() {
            let f = await erkenneFragmente(cg)
            alle += i == 0 ? f : f.map { TextFragment(text: $0.text, box: $0.box.offsetBy(dx: 0, dy: -CGFloat(i))) }
        }
        return alle
    }

    private static func erkenneFragmente(_ cg: CGImage) async -> [TextFragment] {
        await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { request, _ in
                let obs = request.results as? [VNRecognizedTextObservation] ?? []
                cont.resume(returning: obs.compactMap { o -> TextFragment? in
                    guard let s = o.topCandidates(1).first?.string else { return nil }
                    return TextFragment(text: s, box: o.boundingBox)
                })
            }
            req.recognitionLevel = .accurate
            req.recognitionLanguages = ["de-DE", "en-US"]
            req.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
            }
        }
    }

    /// Ein erkanntes Textfragment mit seiner Position (Vision-Normalkoordinaten, Ursprung unten links).
    struct TextFragment {
        var text: String
        var box: CGRect
    }

    /// Rekonstruiert echte Lesezeilen aus einzelnen Vision-Fragmenten: nach y-Mitte gruppieren
    /// (gleiche Zeile, wenn vertikal nah genug) und je Zeile nach x links→rechts sortieren.
    /// Wichtig für rechtsbündige Beträge, die Vision sonst als eigene Fragmente in unbestimmter
    /// Reihenfolge liefert – sie landen so wieder neben ihrem Label („Summe netto … 3.145,00 €").
    static func zeilen(aus fragmente: [TextFragment]) -> [String] {
        guard !fragmente.isEmpty else { return [] }
        let sortiert = fragmente.sorted { $0.box.midY > $1.box.midY }   // oben zuerst
        var zeilen: [[TextFragment]] = []
        var aktuell: [TextFragment] = []
        var zeilenY = sortiert[0].box.midY
        var zeilenH = sortiert[0].box.height
        for f in sortiert {
            let toleranz = max(zeilenH, f.box.height) * 0.6
            if aktuell.isEmpty || abs(f.box.midY - zeilenY) <= toleranz {
                aktuell.append(f)
            } else {
                zeilen.append(aktuell)
                aktuell = [f]; zeilenY = f.box.midY; zeilenH = f.box.height
            }
        }
        if !aktuell.isEmpty { zeilen.append(aktuell) }
        return zeilen.map { gruppe in
            gruppe.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
    }

    // MARK: - Geometrie-genaue Felder (rein, testbar)

    /// Betrag in **derselben Zeile rechts** vom Schlagwort. Schlagworte werden in Prioritäts-
    /// reihenfolge geprüft; je Treffer wird der am weitesten rechts stehende parsbare Betrag der
    /// Zeilenhöhe genommen. Ignoriert Nachbarspalten anderer Zeilen (z. B. die Stundenzahl).
    static func betragRechtsVomLabel(_ schlagworte: [String], _ frag: [TextFragment]) -> Decimal? {
        for wort in schlagworte {
            guard let label = frag.first(where: { f in
                let l = f.text.lowercased()
                // Kurze, mehrdeutige Steuerworte nur an Wortgrenzen (sonst matcht „Sch**ust**er"/
                // „pri**vat**"); zusätzlich USt-IdNr./VAT-ID ausschließen (kein Steuerbetrag).
                if wort == "ust" || wort == "vat" {
                    guard l.range(of: "\\b" + wort + "\\b", options: .regularExpression) != nil else { return false }
                    for verbot in ["ustid", "ust-id", "ust id", "idnr", "id-nr", "vatid", "vat id"] where l.contains(verbot) {
                        return false
                    }
                    return true
                }
                return l.contains(wort)
            }) else { continue }
            let tol = max(label.box.height, 0.001) * 0.8
            let kandidaten = frag
                .filter { abs($0.box.midY - label.box.midY) <= tol && $0.box.minX >= label.box.minX - 0.01 }
                .sorted { $0.box.minX < $1.box.minX }
            for f in kandidaten.reversed() { if let b = betraege(in: f.text).max() { return b } }
        }
        return nil
    }

    /// Empfänger über Geometrie: erste nicht-numerische Zeile **links unterhalb** der Absenderzeile
    /// („•"); blendet die rechte Absender-Kontaktspalte über die x-Position aus.
    static func empfaenger(_ frag: [TextFragment]) -> String? {
        guard let sender = frag.first(where: { f in
            let l = f.text.lowercased()
            return f.text.contains("•") && !l.contains("iban") && !l.contains("bic") && !l.contains("zahlungsinfo")
        }) else { return nil }
        let kandidaten = frag
            .filter { $0.box.midY < sender.box.midY - 0.001 && abs($0.box.minX - sender.box.minX) <= 0.12 }
            .sorted { $0.box.midY > $1.box.midY }   // oben zuerst
        for f in kandidaten {
            let t = f.text.trimmingCharacters(in: .whitespaces)
            if let c = t.first, !c.isNumber, t.count >= 2 { return t }
        }
        return nil
    }

    /// Ausgabe-Beleg geometrie-genau: Text-Felder aus den rekonstruierten Zeilen, Beträge rechts
    /// vom Schlagwort (sonst Zeilen-Fallback).
    static func extrahiere(fragmente frag: [TextFragment]) -> BelegDaten {
        let zeilen = zeilen(aus: frag)
        var d = extrahiere(aus: zeilen)
        if let v = betragRechtsVomLabel(["mwst", "mehrwert", "umsatzsteuer", "ust", "vat"], frag) { d.vst = v }
        if let b = betragRechtsVomLabel(["gesamtbetrag", "rechnungsbetrag", "zu zahlen", "total", "brutto"], frag) { d.brutto = b }
        d.steuerart = steuerart(text: zeilen.joined(separator: "\n").lowercased(), vst: d.vst)
        return d
    }

    /// Ausgangs-(Einnahmen-)Rechnung geometrie-genau: Empfänger aus der linken Spalte, Beträge
    /// rechts vom jeweiligen Schlagwort (USt am robustesten als Brutto − Netto).
    static func extrahiereEinnahme(fragmente frag: [TextFragment]) -> EinnahmeDaten {
        let zeilen = zeilen(aus: frag)
        var d = EinnahmeDaten()
        d.datum = rechnungsdatum(in: zeilen) ?? ersteDatum(in: zeilen)
        d.rechnungsnummer = rechnungsnummer(in: zeilen)
        d.kunde = empfaenger(frag) ?? kunde(in: zeilen)
        d.rnNetto = betragRechtsVomLabel(["summe netto", "netto", "zwischensumme"], frag)
            ?? betragNahe(["summe netto", "netto", "zwischensumme"], in: zeilen)
        let gesamt = betragRechtsVomLabel(["gesamtbetrag", "rechnungsbetrag", "zu zahlen", "total"], frag)
            ?? betragNahe(["gesamtbetrag", "rechnungsbetrag", "zu zahlen", "total"], in: zeilen)
            ?? groessterBetrag(in: zeilen)
        if let netto = d.rnNetto, let g = gesamt, g > netto {
            d.ust = g - netto
        } else {
            d.ust = betragRechtsVomLabel(["umsatzsteuer", "mwst", "mehrwert", "ust", "vat"], frag)
                ?? betragNahe(["umsatzsteuer", "mwst", "mehrwert", "vat"], in: zeilen)
            if d.rnNetto == nil, let g = gesamt, let u = d.ust, g > u { d.rnNetto = g - u }
        }
        return d
    }

    // MARK: - Heuristische Extraktion (rein, testbar)

    static func extrahiere(aus zeilen: [String]) -> BelegDaten {
        var d = BelegDaten()
        let low = zeilen.joined(separator: "\n").lowercased()
        d.datum = ersteDatum(in: zeilen)
        d.vst = betragNahe(["mwst", "mehrwert", "umsatzsteuer", "ust", "vat"], in: zeilen)
        d.brutto = betragNahe(["gesamtbetrag", "rechnungsbetrag", "gesamt", "summe", "total", "zu zahlen", "amount due", "brutto"], in: zeilen)
            ?? groessterBetrag(in: zeilen)
        d.anbieter = anbieter(in: zeilen)
        d.steuerart = steuerart(text: low, vst: d.vst)
        d.rechnungsnummer = rechnungsnummer(in: zeilen)
        return d
    }

    // MARK: - Einnahmen (Ausgangsrechnungen)

    static func extrahiereEinnahme(aus zeilen: [String]) -> EinnahmeDaten {
        var d = EinnahmeDaten()
        d.datum = rechnungsdatum(in: zeilen) ?? ersteDatum(in: zeilen)
        d.rechnungsnummer = rechnungsnummer(in: zeilen)
        d.kunde = kunde(in: zeilen)
        d.rnNetto = betragNahe(["summe netto", "netto", "zwischensumme"], in: zeilen)
        let gesamt = betragNahe(["gesamtbetrag", "rechnungsbetrag", "zu zahlen", "total"], in: zeilen)
            ?? groessterBetrag(in: zeilen)
        // USt am robustesten als Differenz Brutto − Netto (umgeht „USt." vs. „UStID")
        if let netto = d.rnNetto, let g = gesamt, g > netto {
            d.ust = g - netto
        } else {
            d.ust = betragNahe(["umsatzsteuer", "mwst", "mehrwert", "vat"], in: zeilen)
            if d.rnNetto == nil, let g = gesamt, let u = d.ust, g > u { d.rnNetto = g - u }
        }
        return d
    }

    /// Datum bevorzugt aus der „Rechnungsdatum"-Zeile (nicht Fälligkeit/Leistung).
    static func rechnungsdatum(in zeilen: [String]) -> Date? {
        for z in zeilen where z.lowercased().contains("rechnungsdatum") {
            if let d = ersteDatum(in: [z]) { return d }
        }
        return nil
    }

    static func rechnungsnummer(in zeilen: [String]) -> String? {
        for z in zeilen where z.lowercased().contains("rechnung") {
            if let r = z.range(of: #"#\s*[A-Za-z0-9][A-Za-z0-9\-/]*"#, options: .regularExpression) {
                return String(z[r]).replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
            }
            if let r = z.range(of: #"(?:nr\.?|nummer)\s*:?\s*[A-Za-z0-9][A-Za-z0-9\-/]*"#,
                               options: [.regularExpression, .caseInsensitive]) {
                let s = String(z[r])
                if let t = s.range(of: #"[A-Za-z0-9\-/]+$"#, options: .regularExpression) { return String(s[t]) }
            }
        }
        return nil
    }

    /// Empfänger (Kunde): Zeile direkt unter der Absender-Zeile („•", kein IBAN/BIC),
    /// sonst erste Zeile mit Firmen-Suffix.
    static func kunde(in zeilen: [String]) -> String? {
        if let i = zeilen.firstIndex(where: { z in
            let l = z.lowercased()
            return z.contains("•") && !l.contains("iban") && !l.contains("bic") && !l.contains("zahlungsinfo")
        }) {
            for j in (i + 1)..<zeilen.count {
                let t = zeilen[j].trimmingCharacters(in: .whitespaces)
                if t.isEmpty { continue }
                if let f = t.first, !f.isNumber { return t }
            }
        }
        let suffixe = ["GmbH", "AG", "UG", "GbR", "mbH", "KG", "e.K.", "OHG", "Co."]
        return zeilen.first { z in suffixe.contains { z.contains($0) } }?.trimmingCharacters(in: .whitespaces)
    }

    /// Steuerart heuristisch: Reverse-Charge-Hinweise → §13b; sonst MwSt/USt-Hinweise → inland19.
    static func steuerart(text low: String, vst: Decimal?) -> Steuerart {
        let reverse = ["reverse charge", "reverse-charge", "reverse charged", "§13b", "13b",
                       "steuerschuldnerschaft des leistungsempfängers", "vat reverse"]
        if reverse.contains(where: { low.contains($0) }) { return .reverseCharge }
        let vatHinweis = ["mwst", "mehrwert", "umsatzsteuer", "ust", "19 %", "19%", "7 %", "7%"]
        if (vst ?? 0) > 0 || vatHinweis.contains(where: { low.contains($0) }) { return .inland19 }
        return .reverseCharge   // kein VAT-Hinweis → vermutlich Auslands-/RC-Leistung
    }

    static let bekannteAnbieter = ["Figma", "Anthropic", "OpenAI", "DomainFactory", "GitHub",
                                   "Apple", "Amazon", "Microsoft", "Google", "Adobe", "JACOB", "büroshop24"]

    static func anbieter(in zeilen: [String]) -> String? {
        let text = zeilen.joined(separator: " ")
        for a in bekannteAnbieter where text.range(of: a, options: .caseInsensitive) != nil { return a }
        // sonst erste „inhaltliche" Zeile (Buchstaben, kein reiner Betrag/Datum)
        return zeilen.first { z in
            let t = z.trimmingCharacters(in: .whitespaces)
            return t.count >= 3 && t.rangeOfCharacter(from: .letters) != nil
                && betraege(in: t).isEmpty && ersteDatum(in: [t]) == nil
        }?.trimmingCharacters(in: .whitespaces)
    }

    static func ersteDatum(in zeilen: [String]) -> Date? {
        let muster = [("dd.MM.yyyy", #"\d{1,2}\.\d{1,2}\.\d{4}"#),
                      ("dd.MM.yy", #"\d{1,2}\.\d{1,2}\.\d{2}\b"#),
                      ("yyyy-MM-dd", #"\d{4}-\d{2}-\d{2}"#)]
        let df = DateFormatter(); df.calendar = appKalender; df.locale = Locale(identifier: "de_DE")
        for z in zeilen {
            for (fmt, pat) in muster {
                if let r = z.range(of: pat, options: .regularExpression) {
                    df.dateFormat = fmt
                    if let d = df.date(from: String(z[r])) { return d }
                }
            }
        }
        return nil
    }

    static func betragNahe(_ schlagworte: [String], in zeilen: [String]) -> Decimal? {
        for (i, z) in zeilen.enumerated() {
            let low = z.lowercased()
            guard schlagworte.contains(where: { low.contains($0) }) else { continue }
            if let m = betraege(in: z).max() { return m }
            if i + 1 < zeilen.count, let m = betraege(in: zeilen[i + 1]).max() { return m }  // Betrag in Folgezeile
        }
        return nil
    }

    static func groessterBetrag(in zeilen: [String]) -> Decimal? {
        zeilen.flatMap { betraege(in: $0) }.max()
    }

    /// Alle geldartigen Beträge einer Zeile (mit 2 Nachkommastellen).
    static func betraege(in zeile: String) -> [Decimal] {
        let pat = #"\d{1,3}(?:[.,  ]\d{3})*[.,]\d{2}|\d+[.,]\d{2}"#
        guard let re = try? NSRegularExpression(pattern: pat) else { return [] }
        let ns = zeile as NSString
        return re.matches(in: zeile, range: NSRange(location: 0, length: ns.length)).compactMap {
            normalisiere(ns.substring(with: $0.range))
        }
    }

    static func normalisiere(_ token: String) -> Decimal? {
        var t = token.replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "")
        if let komma = t.lastIndex(of: ","), let punkt = t.lastIndex(of: ".") {
            let dezIstKomma = komma > punkt
            t = t.replacingOccurrences(of: dezIstKomma ? "." : ",", with: "")
            t = t.replacingOccurrences(of: dezIstKomma ? "," : ".", with: ".")
        } else if t.contains(",") {
            t = t.replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: t, locale: Locale(identifier: "en_US_POSIX"))
    }
}
