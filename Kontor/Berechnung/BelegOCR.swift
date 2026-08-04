import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision

// Bewusst **kein** AppKit: Diese Datei läuft nonisoliert auf dem globalen Executor (und im
// Beleg-Batch mehrfach parallel). NSImage/NSGraphicsContext sind Main-Thread-only – siehe
// `rendere`. Alles hier ist CoreGraphics/ImageIO und damit threadsicher.

/// Feld eines Beleg-Entwurfs – Schlüssel für die Unsicherheits-Markierung in der UI.
enum BelegFeld: String, CaseIterable, Sendable {
    case anbieter, datum, brutto, vst, steuerart, rechnungsnummer

    var bezeichnung: String {
        switch self {
        case .anbieter: "Anbieter"
        case .datum: "Datum"
        case .brutto: "Brutto"
        case .vst: "Vorsteuer"
        case .steuerart: "Steuerart"
        case .rechnungsnummer: "Rechnungsnummer"
        }
    }
}

struct BelegDaten {
    var anbieter: String?
    var datum: Date?
    var brutto: Decimal?
    var vst: Decimal?
    var steuerart: Steuerart?
    var rechnungsnummer: String?
    /// Felder, die die Plausibilisierung abgeleitet, korrigiert oder nicht gefunden hat.
    /// Die UI markiert sie, damit ein still übernommener Fehlwert nicht unbemerkt bleibt.
    var unsicher: Set<BelegFeld> = []
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

    static func analysiere(_ url: URL, katalog: [String] = []) async -> BelegDaten {
        extrahiere(fragmente: await fragmente(von: url), katalog: katalog)
    }

    static func analysiereEinnahme(_ url: URL) async -> EinnahmeDaten {
        extrahiereEinnahme(fragmente: await fragmente(von: url))
    }

    // MARK: - Bilder laden (bis zu `maxSeiten` PDF-Seiten oder eine Bilddatei)

    /// Intern (nicht `private`), damit die Tests den Render-Pfad direkt und **nebenläufig**
    /// fahren können – genau dort saß der Main-Thread-Verstoß.
    static func bilder(von url: URL) -> [CGImage] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
            return (0..<min(doc.pageCount, maxSeiten)).compactMap { doc.page(at: $0).flatMap(rendere) }
        }
        // ImageIO statt `NSImage(contentsOf:)` – threadsicher und ohne AppKit-Umweg.
        if let quelle = CGImageSourceCreateWithURL(url as CFURL, nil),
            CGImageSourceGetCount(quelle) > 0,
            let cg = CGImageSourceCreateImageAtIndex(quelle, 0, nil)
        {
            return [cg]
        }
        return []
    }

    /// Rendert eine PDF-Seite als CGImage (2,5× für bessere Texterkennung).
    ///
    /// Bewusst reines CoreGraphics. Vorher lief das über `NSImage.lockFocus()` /
    /// `NSGraphicsContext.current` / `unlockFocus()` – AppKit-Zeichnen, das den **geteilten**
    /// Grafik-Kontext-Stack des Prozesses manipuliert und deshalb nur auf dem Main Thread
    /// zulässig ist. `analysiere` ist aber nonisoliert `async`, läuft also auf dem globalen
    /// Executor, und der Beleg-Batch fährt mehrere Belege parallel: zwei gleichzeitige
    /// `lockFocus`-Aufrufe treten sich auf demselben Stack gegenseitig auf die Füße.
    /// Ein eigener `CGContext` je Aufruf teilt dagegen nichts.
    private static func rendere(_ page: PDFPage) -> CGImage? {
        let rect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.5
        let breite = Int((rect.width * scale).rounded()), hoehe = Int((rect.height * scale).rounded())
        guard breite > 0, hoehe > 0 else { return nil }
        guard
            let ctx = CGContext(
                data: nil, width: breite, height: hoehe,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        // Weißer Grund: PDF-Seiten sind transparent, Vision liest auf Schwarz sonst nichts.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: breite, height: hoehe))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -rect.origin.x, y: -rect.origin.y)  // mediaBox muss nicht bei 0 beginnen
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    /// Fragmente über mehrere Seiten – Folgeseiten werden in y nach unten verschoben, damit die
    /// Lesereihenfolge (Kopf/Kunde/Datum S. 1, Summen ggf. S. 2) erhalten bleibt.
    ///
    /// Je Seite gilt: **hat sie einen Textlayer, wird der gelesen**, sonst wird gerendert und
    /// Vision darübergeschickt. Digitale Rechnungen (die allermeisten Eingangsrechnungen) tragen
    /// ihren Text exakt in sich; ihn erst zu rastern und dann zurückzuerkennen, produzierte
    /// vermeidbare Lesefehler (0/O, 1/l, 6/8) und zerriss Spalten. Der Vision-Pfad bleibt für
    /// Scans, Fotos und Bild-PDFs.
    static func fragmente(von url: URL) async -> [TextFragment] {
        var alle: [TextFragment] = []
        for (i, quelle) in seiten(von: url).enumerated() {
            let f: [TextFragment]
            switch quelle {
            case .text(let fragmente): f = fragmente
            case .bild(let cg): f = await erkenneFragmente(cg)
            }
            alle += i == 0 ? f : f.map { TextFragment(text: $0.text, box: $0.box.offsetBy(dx: 0, dy: -CGFloat(i))) }
        }
        return alle
    }

    /// Eine Beleg-Seite als das, was sie hergibt: fertige Textfragmente oder ein Bild für OCR.
    enum Seitenquelle {
        case text([TextFragment])
        case bild(CGImage)
    }

    /// Mindestzeichenzahl, ab der eine PDF-Seite als „hat Textlayer" gilt. Darunter (leere Seite,
    /// nur ein Wasserzeichen, Scan mit Kopfzeile) ist der Vision-Pfad zuverlässiger.
    static let textlayerSchwelle = 20

    static func seiten(von url: URL) -> [Seitenquelle] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
            return (0..<min(doc.pageCount, maxSeiten)).compactMap { i -> Seitenquelle? in
                guard let page = doc.page(at: i) else { return nil }
                let fragmente = textFragmente(aus: page)
                let zeichen = fragmente.reduce(0) { $0 + $1.text.count }
                if zeichen >= textlayerSchwelle { return .text(fragmente) }
                return rendere(page).map(Seitenquelle.bild)
            }
        }
        return bilder(von: url).map(Seitenquelle.bild)
    }

    /// Wort-Fragmente aus dem eingebetteten Textlayer, in **derselben** Konvention wie Vision:
    /// auf 0…1 normalisiert, Ursprung unten links. Damit sieht der gesamte nachgelagerte
    /// Extraktionspfad (Zeilenrekonstruktion, „rechts vom Label") keinen Unterschied zur OCR.
    static func textFragmente(aus page: PDFPage) -> [TextFragment] {
        let seite = page.bounds(for: .mediaBox)
        // Gedrehte Seiten: `characterBounds` bezieht sich auf die ungedrehte Seite, die Geometrie
        // passte also nicht mehr zur Leserichtung. Solche Seiten gehen über den Bildpfad.
        guard seite.width > 0, seite.height > 0, page.rotation % 360 == 0 else { return [] }
        let text = page.string ?? ""
        guard !text.isEmpty else { return [] }

        var fragmente: [TextFragment] = []
        var wort = ""
        var box: CGRect = .null
        // **Eigener Box-Index.** `page.string` enthält je Textzeile ein „\n" und `numberOfCharacters`
        // zählt es mit – `characterBounds(at:)` vergibt ihm aber **keinen** Index. Wer beide Indizes
        // gleichsetzt, verschiebt ab dem ersten Umbruch jede Box um eins: die Wörter bekommen die
        // Position ihres Nachbarn, Zeilen und Spalten zerfallen, und am Seitenende fehlen Boxen.
        var boxIndex = 0
        func schliesseWortAb() {
            defer {
                wort = ""
                box = .null
            }
            guard !wort.isEmpty, !box.isNull else { return }
            let normalisiert = CGRect(
                x: (box.minX - seite.minX) / seite.width,
                y: (box.minY - seite.minY) / seite.height,
                width: box.width / seite.width,
                height: box.height / seite.height)
            fragmente.append(TextFragment(text: wort, box: normalisiert))
        }
        for zeichen in text {
            if zeichen.isNewline {
                schliesseWortAb()
                continue  // ohne Box-Index: Umbrüche haben keine Zeichenbox
            }
            defer { boxIndex += 1 }
            if zeichen.isWhitespace {
                schliesseWortAb()
                continue
            }
            guard boxIndex < page.numberOfCharacters else { break }
            let zeichenBox = page.characterBounds(at: boxIndex)
            wort.append(zeichen)
            // Leere Boxen (Glyphen ohne Ausdehnung) dürfen die Wortbox nicht auf 0 ziehen.
            if !zeichenBox.isNull, zeichenBox.width > 0 || zeichenBox.height > 0 {
                box = box.union(zeichenBox)
            }
        }
        schliesseWortAb()
        return fragmente
    }

    private static func erkenneFragmente(_ cg: CGImage) async -> [TextFragment] {
        // Neue Swift-native Vision-API (macOS 15+): async/await statt GCD-Hop + Continuation –
        // vermeidet Prioritätsinversion und den Capture des non-Sendable `VNRecognizeTextRequest`.
        var req = RecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US")]
        req.usesLanguageCorrection = true
        guard let obs = try? await req.perform(on: cg) else { return [] }
        return obs.compactMap { o -> TextFragment? in
            guard let s = o.topCandidates(1).first?.string else { return nil }
            return TextFragment(text: s, box: o.boundingBox.cgRect)
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
        let sortiert = fragmente.sorted { $0.box.midY > $1.box.midY }  // oben zuerst
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
                aktuell = [f]
                zeilenY = f.box.midY
                zeilenH = f.box.height
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
    ///
    /// **Alle** passenden Label-Fragmente werden geprüft, von unten nach oben. Vorher entschied
    /// `frag.first(where:)`, und Vision liefert seine Fragmente unsortiert: bei einer Rechnung mit
    /// MwSt-Angabe je Positionszeile traf es mal die Position, mal den Summenblock – dasselbe PDF
    /// konnte zweimal verschiedene Werte ergeben. Von unten zu suchen ist zudem die richtige
    /// Vorannahme: der Summenblock steht am Ende, die Positionen darüber.
    static func betragRechtsVomLabel(_ schlagworte: [String], _ frag: [TextFragment]) -> Decimal? {
        for wort in schlagworte {
            let labels =
                frag
                .filter { f in
                    let l = f.text.lowercased()
                    // Kurze, mehrdeutige Steuerworte nur an Wortgrenzen (sonst matcht „Sch**ust**er"/
                    // „pri**vat**"); zusätzlich USt-IdNr./VAT-ID ausschließen (kein Steuerbetrag).
                    if wort == "ust" || wort == "vat" {
                        guard l.range(of: "\\b" + wort + "\\b", options: .regularExpression) != nil else {
                            return false
                        }
                        for verbot in ["ustid", "ust-id", "ust id", "idnr", "id-nr", "vatid", "vat id"]
                        where l.contains(verbot) {
                            return false
                        }
                        return true
                    }
                    return l.contains(wort)
                }
                .sorted { $0.box.midY < $1.box.midY }  // unten zuerst (Summenblock)
            for label in labels {
                let tol = max(label.box.height, 0.001) * 0.8
                let kandidaten =
                    frag
                    .filter { abs($0.box.midY - label.box.midY) <= tol && $0.box.minX >= label.box.minX - 0.01 }
                    .sorted { $0.box.minX < $1.box.minX }
                for f in kandidaten.reversed() { if let b = betraege(in: f.text).max() { return b } }
            }
        }
        return nil
    }

    /// Empfänger über Geometrie: erste nicht-numerische Zeile **links unterhalb** der Absenderzeile
    /// („•"); blendet die rechte Absender-Kontaktspalte über die x-Position aus.
    static func empfaenger(_ frag: [TextFragment]) -> String? {
        guard
            let sender = frag.first(where: { f in
                let l = f.text.lowercased()
                return f.text.contains("•") && !l.contains("iban") && !l.contains("bic") && !l.contains("zahlungsinfo")
            })
        else { return nil }
        let kandidaten =
            frag
            .filter { $0.box.midY < sender.box.midY - 0.001 && abs($0.box.minX - sender.box.minX) <= 0.12 }
            .sorted { $0.box.midY > $1.box.midY }  // oben zuerst
        for f in kandidaten {
            let t = f.text.trimmingCharacters(in: .whitespaces)
            if let c = t.first, !c.isNumber, t.count >= 2 { return t }
        }
        return nil
    }

    /// Ausgabe-Beleg geometrie-genau: Text-Felder aus den rekonstruierten Zeilen, Beträge rechts
    /// vom Schlagwort (sonst Zeilen-Fallback).
    static func extrahiere(fragmente frag: [TextFragment], katalog: [String] = []) -> BelegDaten {
        let zeilen = zeilen(aus: frag)
        var d = extrahiere(aus: zeilen, katalog: katalog)
        // Die Geometrie ist genauer als der Zeilentext, wo sie etwas findet: sie überschreibt.
        // Die Plausibilisierung läuft danach erneut, sonst blieben die Marken vom Zeilen-Durchlauf
        // stehen und die überschriebenen Werte selbst ungeprüft.
        d.unsicher = []
        if let v = betragRechtsVomLabel(["mwst", "mehrwert", "umsatzsteuer", "ust", "vat"], frag) { d.vst = v }
        if let b = betragRechtsVomLabel(
            ["amount due", "gesamtbetrag", "rechnungsbetrag", "zu zahlen", "total", "brutto"], frag)
        {
            d.brutto = b
        }
        d.steuerart = steuerart(zeilen: zeilen, vst: d.vst)
        return plausibilisiere(d)
    }

    /// Ausgangs-(Einnahmen-)Rechnung geometrie-genau: Empfänger aus der linken Spalte, Beträge
    /// rechts vom jeweiligen Schlagwort (USt am robustesten als Brutto − Netto).
    static func extrahiereEinnahme(fragmente frag: [TextFragment]) -> EinnahmeDaten {
        let zeilen = zeilen(aus: frag)
        var d = EinnahmeDaten()
        d.datum = rechnungsdatum(in: zeilen) ?? ersteDatum(in: zeilen)
        d.rechnungsnummer = rechnungsnummer(in: zeilen)
        d.kunde = empfaenger(frag) ?? kunde(in: zeilen)
        d.rnNetto =
            betragRechtsVomLabel(["summe netto", "netto", "zwischensumme"], frag)
            ?? betragNahe(["summe netto", "netto", "zwischensumme"], in: zeilen)
        let gesamt =
            betragRechtsVomLabel(["gesamtbetrag", "rechnungsbetrag", "zu zahlen", "total"], frag)
            ?? betragNahe(["gesamtbetrag", "rechnungsbetrag", "zu zahlen", "total"], in: zeilen)
            ?? groessterBetrag(in: zeilen)
        if let netto = d.rnNetto, let g = gesamt, g > netto {
            d.ust = g - netto
        } else {
            d.ust =
                betragRechtsVomLabel(["umsatzsteuer", "mwst", "mehrwert", "ust", "vat"], frag)
                ?? betragNahe(["umsatzsteuer", "mwst", "mehrwert", "vat"], in: zeilen)
            if d.rnNetto == nil, let g = gesamt, let u = d.ust, g > u { d.rnNetto = g - u }
        }
        return d
    }

    // MARK: - Heuristische Extraktion (rein, testbar)

    static func extrahiere(aus zeilen: [String], katalog: [String] = []) -> BelegDaten {
        var d = BelegDaten()
        d.datum = ersteDatum(in: zeilen)
        d.vst = betragNahe(["mwst", "mehrwert", "umsatzsteuer", "ust", "vat"], in: zeilen)
        d.brutto =
            betragNahe(
                ["gesamtbetrag", "rechnungsbetrag", "gesamt", "summe", "total", "zu zahlen", "amount due", "brutto"],
                in: zeilen)
            ?? groessterBetrag(in: zeilen)
        d.anbieter = anbieter(in: zeilen, katalog: katalog)
        d.steuerart = steuerart(zeilen: zeilen, vst: d.vst)
        d.rechnungsnummer = rechnungsnummer(in: zeilen)
        return plausibilisiere(d)
    }

    /// Gegenprobe der erkannten Werte, bevor sie in einen Entwurf wandern.
    ///
    /// Bisher wurde übernommen, was die Heuristik lieferte – auch wenn Vorsteuer und Brutto
    /// gar nicht zusammenpassten (Prozentzahl statt Betrag, Netto statt Steuer, Zeile verfehlt).
    /// Hier wird beides gegeneinander geprüft: passt die Vorsteuer zu 19 % oder 7 % des Bruttos,
    /// gilt der Satz als bestätigt; passt sie zu keinem, wird sie aus dem Brutto abgeleitet und
    /// das Feld als unsicher markiert, statt einen falschen Wert still durchzureichen.
    ///
    /// Eine **explizit als 0 erkannte** Steuer bleibt 0 (Kleinunternehmer, 0-%-Ausweis): sie
    /// wird nur markiert. Erfunden wird Vorsteuer ausschließlich dort, wo gar nichts gefunden wurde.
    static func plausibilisiere(_ roh: BelegDaten) -> BelegDaten {
        var d = roh
        if d.anbieter == nil { d.unsicher.insert(.anbieter) }
        if d.datum == nil { d.unsicher.insert(.datum) }
        if d.rechnungsnummer == nil { d.unsicher.insert(.rechnungsnummer) }

        guard let brutto = d.brutto, brutto > 0 else {
            d.unsicher.insert(.brutto)
            if d.vst != nil { d.unsicher.insert(.vst) }
            return d
        }
        let art = d.steuerart ?? .inland19
        guard art.ziehtVorsteuer else {
            if (d.vst ?? 0) != 0 { d.unsicher.insert(.vst) }  // RC/steuerfrei zieht nie Vorsteuer
            d.vst = 0
            return d
        }
        let erwartet19 = Steuer.vorsteuerVorschlag(brutto: brutto, steuerart: .inland19)
        let erwartet7 = Steuer.vorsteuerVorschlag(brutto: brutto, steuerart: .inland7)
        let toleranz = dez("0.02")  // Rundung des Belegs gegen die eigene Rechnung
        guard let vst = d.vst else {
            d.vst = art == .inland7 ? erwartet7 : erwartet19
            d.unsicher.insert(.vst)
            return d
        }
        if abs(vst - erwartet19) <= toleranz {
            d.steuerart = .inland19
        } else if abs(vst - erwartet7) <= toleranz {
            d.steuerart = .inland7
        } else if vst == 0 {
            d.unsicher.insert(.vst)
        } else {
            d.vst = art == .inland7 ? erwartet7 : erwartet19
            d.unsicher.insert(.vst)
            d.unsicher.insert(.steuerart)
        }
        return d
    }

    // MARK: - Einnahmen (Ausgangsrechnungen)

    static func extrahiereEinnahme(aus zeilen: [String]) -> EinnahmeDaten {
        var d = EinnahmeDaten()
        d.datum = rechnungsdatum(in: zeilen) ?? ersteDatum(in: zeilen)
        d.rechnungsnummer = rechnungsnummer(in: zeilen)
        d.kunde = kunde(in: zeilen)
        d.rnNetto = betragNahe(["summe netto", "netto", "zwischensumme"], in: zeilen)
        let gesamt =
            betragNahe(["gesamtbetrag", "rechnungsbetrag", "zu zahlen", "total"], in: zeilen)
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

    /// Schlagworte, hinter denen eine Rechnungs-/Belegnummer steht, deutsch **und** englisch.
    /// Ohne die englischen Varianten blieb das Feld ausgerechnet bei Auslandsrechnungen leer
    /// („Invoice number 86C79197-0015") – und damit fehlte dem Kontoauszug-Abgleich sein
    /// stärkster Schlüssel, der unabhängig von Betrag und Währung trägt.
    static let rechnungsnummerLabels = [
        "rechnungsnummer", "rechnungs-nr", "rechnungsnr", "re-nr", "rechnung",
        "invoice number", "invoice no", "invoice", "receipt", "belegnummer", "beleg-nr", "quittung",
    ]

    static func rechnungsnummer(in zeilen: [String]) -> String? {
        for z in zeilen {
            let low = z.lowercased()
            guard let label = rechnungsnummerLabels.first(where: { low.contains($0) }) else { continue }
            // Steuer-/Datumszeilen tragen keine Rechnungsnummer („Rechnungsdatum: 14.06.2026").
            let verbote = ["ustid", "ust-id", "ust id", "vatid", "vat id", "steuernummer", "tax id", "datum"]
            if verbote.contains(where: { low.contains($0) }) { continue }
            if let r = z.range(of: #"#\s*[A-Za-z0-9][A-Za-z0-9\-/]*"#, options: .regularExpression) {
                return saeubereNummer(String(z[r]).replacingOccurrences(of: "#", with: ""))
            }
            if let r = z.range(
                of: #"(?:nr\.?|nummer|number|no\.?)\s*:?\s*[A-Za-z0-9][A-Za-z0-9\-/]*"#,
                options: [.regularExpression, .caseInsensitive])
            {
                let s = String(z[r])
                if let t = s.range(of: #"[A-Za-z0-9\-/]+$"#, options: .regularExpression) {
                    return saeubereNummer(String(s[t]))
                }
            }
            // „Invoice 86C79197-0015" ohne Nummern-Wort: erstes Token nach dem Label, das
            // Ziffern trägt, lang genug und kein Betrag/Datum ist.
            if let bereich = low.range(of: label) {
                let rest = z[bereich.upperBound...]
                for token in rest.split(whereSeparator: { $0 == " " || $0 == ":" }) {
                    let t = saeubereNummer(String(token))
                    guard t.count >= 4, t.contains(where: \.isNumber),
                        t.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "/" }),
                        ersteDatum(in: [t]) == nil, betragsFunde(in: t).isEmpty
                    else { continue }
                    return t
                }
            }
        }
        return nil
    }

    /// Nummern-Token säubern: umschließende Leerzeichen und angehängte Satzzeichen weg.
    private static func saeubereNummer(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
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
    ///
    /// Der Steuersatz zählt nur, wenn in **derselben Zeile** ein Steuerwort steht: „19 % Rabatt"
    /// oder „7 % Skonto" machten den Beleg vorher zu einem Inlandsbeleg mit erfundener Vorsteuer.
    /// Zusätzlich sind eine ausländische USt-IdNr des Ausstellers ein RC-Indiz und ein
    /// §19-Hinweis (Kleinunternehmer) ein Grund für `steuerfrei` statt „19 % angenommen".
    static func steuerart(zeilen: [String], vst: Decimal?) -> Steuerart {
        let low = zeilen.map { $0.lowercased() }
        let gesamt = low.joined(separator: "\n")
        let reverse = [
            "reverse charge", "reverse-charge", "reverse charged", "§13b", "13b",
            "steuerschuldnerschaft des leistungsempfängers", "vat reverse",
        ]
        if reverse.contains(where: { gesamt.contains($0) }) { return .reverseCharge }
        let kleinunternehmer = [
            "§19", "kleinunternehmer", "umsatzsteuerbefreit", "keine umsatzsteuer", "steuerfrei",
        ]
        if kleinunternehmer.contains(where: { gesamt.contains($0) }) { return .steuerfrei }
        if auslaendischeUstId(in: low) { return .reverseCharge }

        let steuerworte = ["mwst", "mehrwert", "umsatzsteuer", "ust", "vat", "tax"]
        /// Satz nur werten, wenn er in einer Steuerzeile steht. `(?<![0-9])` verhindert, dass
        /// „17 %" als 7-%-Hinweis durchgeht.
        func satzZeile(_ satz: String) -> Bool {
            low.contains { z in
                z.range(of: "(?<![0-9])" + satz + "\\s*%", options: .regularExpression) != nil
                    && steuerworte.contains(where: { z.contains($0) })
            }
        }
        let hat19 = satzZeile("19")
        let hat7 = satzZeile("7")
        // Der generische Hinweis bleibt bewusst auf die deutschen Steuerworte beschränkt:
        // „Tax" steht auch auf jeder US-Rechnung, die gerade **keine** deutsche USt trägt.
        let vatHinweis = ["mwst", "mehrwert", "umsatzsteuer", "ust"]
        if (vst ?? 0) > 0 || hat19 || hat7 || vatHinweis.contains(where: { gesamt.contains($0) }) {
            // Eindeutiger 7-%-Hinweis (ohne 19 %) → ermäßigt; sonst Regelsatz 19 %.
            return (hat7 && !hat19) ? .inland7 : .inland19
        }
        return .reverseCharge  // kein VAT-Hinweis → vermutlich Auslands-/RC-Leistung
    }

    /// Trägt der Beleg eine USt-IdNr mit **nicht-deutschem** Länderpräfix? Starkes Indiz für eine
    /// Auslandsleistung (§13b), auch wenn der Beleg keinen ausformulierten RC-Hinweis trägt.
    /// Geprüft wird nur in Zeilen mit USt-IdNr-Kontext, damit keine beliebige Buchstaben-Ziffern-
    /// Kombination (Bestellnummer, IBAN) als Steuer-ID durchgeht.
    static func auslaendischeUstId(in zeilenLower: [String]) -> Bool {
        let kontext = ["ustid", "ust-id", "ust id", "vatid", "vat id", "vat number", "tax id"]
        for z in zeilenLower where kontext.contains(where: { z.contains($0) }) {
            // Ländercode direkt an der Nummer (DE123456789, IE6388047V) – ohne Leerzeichen
            // dazwischen, sonst gilt schon das „id" aus „vat id" als Ländercode.
            let muster = #"\b([a-z]{2})[0-9][0-9a-z]{6,11}\b"#
            var suchbereich = z.startIndex..<z.endIndex
            while let r = z.range(of: muster, options: .regularExpression, range: suchbereich) {
                if z[r].prefix(2) != "de" { return true }
                guard r.upperBound < z.endIndex else { break }
                suchbereich = r.upperBound..<z.endIndex
            }
        }
        return false
    }

    /// Generische Mailhoster taugen nicht als Anbietername.
    private static let freieMailhoster = [
        "gmail", "googlemail", "outlook", "hotmail", "yahoo", "web", "gmx", "icloud", "me",
        "posteo", "mailbox", "t-online", "aol",
    ]

    /// Wörter, die keine Anbieter sind, aber gern als erste „inhaltliche" Zeile auftauchen.
    static let anbieterStoppworte = [
        "rechnung", "invoice", "receipt", "quittung", "beleg", "kunde", "customer",
        "datum", "date", "seite", "page", "lieferschein", "bestellung", "order",
    ]

    /// Anbieter aus einer Domain oder Mailadresse im Text („billing@figma.com" → „Figma").
    static func anbieterAusDomain(in text: String) -> String? {
        let muster = [
            #"[A-Za-z0-9._%+-]+@([A-Za-z0-9-]{2,})\.[A-Za-z]{2,}"#,
            #"(?:https?://)?(?:www\.)([A-Za-z0-9-]{2,})\.[A-Za-z]{2,}"#,
        ]
        for pat in muster {
            guard let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) else { continue }
            let ns = text as NSString
            for t in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard t.numberOfRanges > 1 else { continue }
                let name = ns.substring(with: t.range(at: 1)).lowercased()
                if freieMailhoster.contains(name) { continue }
                return name.capitalized
            }
        }
        return nil
    }

    static let bekannteAnbieter = [
        "Figma", "Anthropic", "OpenAI", "DomainFactory", "GitHub",
        "Apple", "Amazon", "Microsoft", "Google", "Adobe", "JACOB", "büroshop24",
    ]

    /// Anbieter aus dem Belegtext. `katalog` sind bereits im Bestand vorkommende Anbieternamen
    /// (aus Ausgaben und gelernten Import-Regeln): das beste verfügbare Lexikon, weil es genau
    /// die Anbieter dieses Nutzers enthält. `BelegOCR` bleibt dadurch trotzdem frei von
    /// SwiftData – die aufrufende View reicht die Namen als Werte durch.
    static func anbieter(in zeilen: [String], katalog: [String] = []) -> String? {
        let text = zeilen.joined(separator: " ")
        let bekannte = katalog.filter { $0.trimmingCharacters(in: .whitespaces).count >= 3 } + bekannteAnbieter
        // Längster Treffer gewinnt („Anthropic PBC" vor „Anthropic") und macht die Auswahl
        // unabhängig von der Reihenfolge im Katalog.
        if let treffer =
            bekannte
            .filter({ text.range(of: $0, options: .caseInsensitive) != nil })
            .max(by: { $0.count < $1.count })
        {
            return treffer
        }
        if let ausDomain = anbieterAusDomain(in: text) { return ausDomain }
        // sonst erste „inhaltliche" Zeile (Buchstaben, kein reiner Betrag/Datum, kein Stoppwort)
        return zeilen.first { z in
            let t = z.trimmingCharacters(in: .whitespaces)
            let low = t.lowercased()
            return t.count >= 3 && t.rangeOfCharacter(from: .letters) != nil
                && betraege(in: t).isEmpty && ersteDatum(in: [t]) == nil
                && !anbieterStoppworte.contains(where: { low.contains($0) })
        }?.trimmingCharacters(in: .whitespaces)
    }

    static func ersteDatum(in zeilen: [String]) -> Date? {
        // Numerische Formate (de_DE genügt – reine Ziffern).
        let numerisch = [
            ("dd.MM.yyyy", #"\d{1,2}\.\d{1,2}\.\d{4}"#),
            ("dd.MM.yy", #"\d{1,2}\.\d{1,2}\.\d{2}\b"#),
            ("yyyy-MM-dd", #"\d{4}-\d{2}-\d{2}"#),
        ]
        // Monatsnamen: englische Auslandsrechnungen (Figma/Anthropic) „June 4, 2025"/„Jun 4, 2025",
        // dt. „4. Juni 2025". Je Regex-Treffer werden die Format/Locale-Kombis der Reihe nach versucht.
        let benannt: [(pat: String, fmts: [(fmt: String, loc: String)])] = [
            (
                #"[A-Za-zäöüÄÖÜ]{3,9}\.?\s+\d{1,2},?\s+\d{4}"#,
                [
                    ("MMMM d, yyyy", "en_US_POSIX"), ("MMM d, yyyy", "en_US_POSIX"),
                    ("MMMM d yyyy", "en_US_POSIX"), ("MMM d yyyy", "en_US_POSIX"),
                ]
            ),
            (
                #"\d{1,2}\.?\s+[A-Za-zäöüÄÖÜ]{3,9}\.?\s+\d{4}"#,
                [
                    ("d MMMM yyyy", "en_US_POSIX"), ("d MMM yyyy", "en_US_POSIX"),
                    ("d. MMMM yyyy", "de_DE"), ("d MMMM yyyy", "de_DE"),
                ]
            ),
        ]
        let df = DateFormatter()
        df.calendar = appKalender
        for z in zeilen {
            for (fmt, pat) in numerisch {
                if let r = z.range(of: pat, options: .regularExpression) {
                    df.locale = Locale(identifier: "de_DE")
                    df.dateFormat = fmt
                    if let d = df.date(from: String(z[r])) { return d }
                }
            }
            for (pat, fmts) in benannt {
                guard let r = z.range(of: pat, options: [.regularExpression, .caseInsensitive]) else { continue }
                let s = String(z[r])
                for (fmt, loc) in fmts {
                    df.locale = Locale(identifier: loc)
                    df.dateFormat = fmt
                    if let d = df.date(from: s) { return d }
                }
            }
        }
        return nil
    }

    /// Alle Label-Wörter, an denen ein Summenblock in Spalten zerfällt. Sie begrenzen in
    /// `betragNach` das Segment: „Zwischensumme 350,00 MwSt 66,50 Gesamt 416,50" ist nach der
    /// Zeilenrekonstruktion **eine** Zeile, und ohne Grenze holte jedes Label denselben Betrag.
    static let summenLabels = [
        "zwischensumme", "summe netto", "netto", "brutto", "subtotal",
        "mwst", "mehrwertsteuer", "mehrwert", "umsatzsteuer", "ust", "vat", "tax",
        "gesamtbetrag", "rechnungsbetrag", "gesamt", "summe", "total", "zu zahlen", "amount due",
    ]

    /// Betrag **nach** dem Schlagwort in derselben Zeile.
    ///
    /// Innerhalb des Segments bis zum nächsten Summen-Label gewinnt der **rechteste** Betrag
    /// (Spaltenlayout: „MwSt 19 % 5,59 €"). Bleibt das Segment leer, weil das nächste Label noch
    /// vor dem Betrag steht („Total excluding tax €50.00"), gilt der **erste** Betrag nach dem
    /// Schlagwort. Ersetzt das frühere `max()` über die ganze Zeile, das im zusammengezogenen
    /// Summenblock für die MwSt den Gesamtbetrag lieferte.
    static func betragNach(_ schlagwort: String, in zeile: String) -> Decimal? {
        // Beträge auf **derselben** Zeichenfolge suchen wie das Label, sonst passen die Offsets
        // nicht mehr zueinander (kleingeschriebene Sonderzeichen können die Länge ändern).
        let low = zeile.lowercased()
        guard let label = low.range(of: schlagwort) else { return nil }
        let ab = low.distance(from: low.startIndex, to: label.upperBound)
        let funde = betragsFunde(in: low).filter { $0.start >= ab }
        guard !funde.isEmpty else { return nil }
        // Nächste Label-Grenze nach dem Schlagwort (kürzestes Segment gewinnt).
        let grenze =
            summenLabels
            .compactMap { wort -> Int? in
                guard wort != schlagwort,
                    let r = low.range(of: wort, range: label.upperBound..<low.endIndex)
                else { return nil }
                return low.distance(from: low.startIndex, to: r.lowerBound)
            }
            .min()
        if let grenze, let letzterImSegment = funde.last(where: { $0.start < grenze }) {
            return letzterImSegment.wert
        }
        return grenze == nil ? funde.last?.wert : funde.first?.wert
    }

    static func betragNahe(_ schlagworte: [String], in zeilen: [String]) -> Decimal? {
        for (i, z) in zeilen.enumerated() {
            let low = z.lowercased()
            guard let wort = schlagworte.first(where: { low.contains($0) }) else { continue }
            if let b = betragNach(wort, in: z) { return b }
            // Label ohne Betrag dahinter: Umbruch im Summenblock, Betrag steht in der Folgezeile.
            if i + 1 < zeilen.count, let m = betragsFunde(in: zeilen[i + 1]).last?.wert { return m }
        }
        return nil
    }

    static func groessterBetrag(in zeilen: [String]) -> Decimal? {
        zeilen.flatMap { betraege(in: $0) }.max()
    }

    /// Ein geldartiger Betrag samt Fundstelle in der Zeile (Zeichen-Offsets), damit
    /// `betragNach` „rechts vom Schlagwort" ohne zweiten Parse-Durchgang bestimmen kann.
    struct BetragsFund: Equatable {
        var wert: Decimal
        var start: Int
        var ende: Int
    }

    /// Alle geldartigen Beträge einer Zeile. Erkennt deutsche wie englische Schreibweise inkl.
    /// Tausender-Gruppen (Punkt/Komma/Leerzeichen + genau 3 Ziffern) – auch **ohne** Nachkomma
    /// („1.500" = 1500) und bei OCR-Verwechslung des Dezimaltrenners („1.234.56"). Das `(?!\d)`
    /// hinter jeder Dreiergruppe verhindert, dass eine vierstellige Zahl (etwa das Jahr „2026"
    /// in einem Datum) fälschlich als gruppierter Tausenderbetrag zerfällt.
    ///
    /// Drei Fälle werden verworfen, weil sie regelmäßig falsche Werte in die Felder trugen:
    /// 1. **Prozentangaben** („MwSt 19,00 %"). Stand in der Zeile kein weiterer Betrag, wurde der
    ///    Steuersatz zur Vorsteuer – der häufigste Fehlgriff überhaupt.
    /// 2. **Teile längerer Zahlen** („14.06" aus „14.06.2026").
    /// 3. **An Buchstaben klebende Zahlen** (Artikel-/Referenznummern wie „A123,45").
    static func betragsFunde(in zeile: String) -> [BetragsFund] {
        // Exotische Tausender-Trenner (NBSP, schmale Leerzeichen aus PDF-Layouts) auf ASCII-Space.
        // Bewusst **längenerhaltend**: die Offsets müssen zur Ausgangszeile passen.
        let z =
            zeile
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{2009}", with: " ")
        let pat = #"\d{1,3}(?:[., ]\d{3}(?!\d))+(?:[.,]\d{2})?|\d+[.,]\d{2}"#
        guard let re = try? NSRegularExpression(pattern: pat) else { return [] }
        let ns = z as NSString
        var funde: [BetragsFund] = []
        for treffer in re.matches(in: z, range: NSRange(location: 0, length: ns.length)) {
            guard let r = Range(treffer.range, in: z) else { continue }
            if let davor = z[..<r.lowerBound].last, davor.isLetter { continue }
            let rest = z[r.upperBound...]
            if let direkt = rest.first {
                if direkt.isLetter { continue }
                // Trenner + weitere Ziffer: der Fund ist nur ein Ausschnitt (Datum, lange Nummer).
                if direkt == "." || direkt == "," {
                    let danach = rest.dropFirst().first
                    if danach?.isNumber == true { continue }
                }
            }
            if rest.drop(while: { $0 == " " }).first == "%" { continue }
            guard let wert = normalisiere(String(z[r])) else { continue }
            funde.append(
                BetragsFund(
                    wert: wert,
                    start: z.distance(from: z.startIndex, to: r.lowerBound),
                    ende: z.distance(from: z.startIndex, to: r.upperBound)))
        }
        return funde
    }

    static func betraege(in zeile: String) -> [Decimal] { betragsFunde(in: zeile).map(\.wert) }

    /// Wandelt einen erkannten Betrags-Token in `Decimal`. Der Dezimaltrenner ist das **letzte**
    /// „,"/„.", **sofern** ihm 1–2 Ziffern folgen; folgen genau 3 (oder mehr), ist es ein
    /// Tausender-Trenner und der Betrag ganzzahlig. Alle übrigen „,"/„." sind Gruppierung und
    /// werden entfernt – deckt de/en sowie OCR-Verwechslungen („1.234.56", „1,234,56") ab.
    static func normalisiere(_ token: String) -> Decimal? {
        var t = token
        for weg in ["\u{00A0}", "\u{202F}", "\u{2009}", " ", "€", "\u{00A3}", "$"] {
            t = t.replacingOccurrences(of: weg, with: "")
        }
        guard let letzter = t.lastIndex(where: { $0 == "," || $0 == "." }) else {
            return Decimal(string: t, locale: Locale(identifier: "en_US_POSIX"))
        }
        let nachkomma = t.distance(from: t.index(after: letzter), to: t.endIndex)
        if nachkomma == 1 || nachkomma == 2 {
            let vor = String(t[..<letzter]).replacingOccurrences(of: ",", with: "").replacingOccurrences(
                of: ".", with: "")
            let dez = String(t[t.index(after: letzter)...])
            return Decimal(string: vor + "." + dez, locale: Locale(identifier: "en_US_POSIX"))
        }
        let ganz = t.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")
        return Decimal(string: ganz, locale: Locale(identifier: "en_US_POSIX"))
    }
}
