import Foundation

/// Dateien für den Upload in **Mein ELSTER**: die Voranmeldung als XML (Formular
/// „Umsatzsteuer-Voranmeldung", Datenübernahme) und die Zusammenfassende Meldung als CSV (Formular
/// „Zusammenfassende Meldung", Einträge importieren). Gesendet wird in Mein ELSTER, das die Datei
/// beim Hochladen prüft – Kontor bleibt offline.
///
/// Vorbild ist wiredframe (`modules/taxes_elster.py`), dort gegen das Portal erprobt: Mein ELSTER
/// nimmt bei der UStVA nur den Block `<Anmeldungssteuern>` mit Jahresversion an (ohne
/// TransferHeader und NutzdatenHeader), die ZM nur als CSV in UTF-8 mit Versionszeilen.
enum ElsterExport {

    struct Fehler: LocalizedError, Equatable {
        var text: String
        var errorDescription: String? { text }
    }

    /// Absender der Voranmeldung (`DatenLieferant`). Gespeichert in den App-Einstellungen.
    struct Absender: Equatable {
        var name: String
        var strasse: String
        var plz: String
        var ort: String

        static let schluessel = (
            name: "elsterName", strasse: "elsterStrasse", plz: "elsterPLZ", ort: "elsterOrt",
            steuernummer: "elsterSteuernummer"
        )
    }

    // MARK: Steuernummer

    /// Steuernummer im **13-stelligen ELSTER-Format**. Angenommen wird sie schon so oder im Format
    /// des Bescheids, dann umgerechnet nach dem Bundesland des Finanzamts (Finanzamtsnummer =
    /// Landesziffer + Finanzamt, danach eine 0, dann Bezirk, Unterscheidung und Prüfziffer).
    static func steuernummer(_ text: String, land: Bundesland?) throws -> String {
        let ziffern = text.filter(\.isNumber)
        let nurZiffernUndTrenner = text.allSatisfy { $0.isNumber || " /-".contains($0) }
        guard nurZiffernUndTrenner, !ziffern.isEmpty else {
            throw Fehler(text: "Steuernummer fehlt oder enthält Buchstaben (Einstellungen › Finanzamt).")
        }
        if ziffern.count == 13 { return ziffern }
        guard let land else {
            throw Fehler(
                text:
                    "Steuernummer wie auf dem Bescheid umrechnen geht nur mit Bundesland (Einstellungen › Finanzamt) – oder sie 13-stellig im ELSTER-Format eintragen."
            )
        }
        let z = Array(ziffern)
        func teil(_ r: Range<Int>) -> String { String(z[r]) }
        switch (land, z.count) {
        case (.bw, 10), (.be, 10), (.hb, 10), (.hh, 10), (.ni, 10), (.rp, 10), (.sh, 10):
            let prefix = [Bundesland.bw: "28", .be: "11", .hb: "24", .hh: "22", .ni: "23", .rp: "27", .sh: "21"][land]!
            return prefix + teil(0..<2) + "0" + teil(2..<10)
        case (.he, 11) where z[0] == "0":
            return "26" + teil(1..<3) + "0" + teil(3..<11)
        case (.by, 11), (.bb, 11), (.mv, 11), (.sl, 11), (.sn, 11), (.st, 11), (.th, 11), (.nw, 11):
            let prefix = [Bundesland.by: "9", .bb: "3", .mv: "4", .sl: "1", .sn: "3", .st: "3", .th: "4", .nw: "5"][
                land]!
            return prefix + teil(0..<3) + "0" + teil(3..<11)
        default:
            throw Fehler(
                text:
                    "Steuernummer passt nicht zum Format in \(land.bezeichnung) – bitte 13-stellig im ELSTER-Format eintragen."
            )
        }
    }

    // MARK: UStVA

    /// ELSTER-Code des Zeitraums: Monat „01"…„12", Quartal „41"…„44".
    static func zeitraumCode(monat: Int? = nil, quartal: Int? = nil) -> String {
        if let quartal { return "4\(quartal)" }
        return String(format: "%02d", monat ?? 1)
    }

    /// Bemessungsgrundlage in vollen Euro (schon gekürzt), ohne Nachkommastellen.
    private static func euro(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d.volleEuro).stringValue
    }
    /// Steuerbetrag mit Punkt und zwei Nachkommastellen.
    private static func betrag(_ d: Decimal) -> String {
        let g = d.gerundet()
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.minimumIntegerDigits = 1
        f.usesGroupingSeparator = false
        return f.string(from: NSDecimalNumber(decimal: g)) ?? "0.00"
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Nur der Block `<Anmeldungssteuern>`, Kennzahlen aufsteigend, leere fehlen, KZ 83 steht immer.
    static func ustvaXML(
        _ u: UStVAErgebnis, jahr: Int, zeitraum: String, steuernummer: String, absender: Absender,
        berichtigt: Bool = false, erstellt: Date = Date()
    ) throws -> Data {
        let felder = [
            ("Name", absender.name), ("Strasse", absender.strasse), ("PLZ", absender.plz), ("Ort", absender.ort),
        ]
        .map { ($0.0, $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let fehlt = felder.filter { $0.1.isEmpty }.map(\.0)
        if !fehlt.isEmpty {
            throw Fehler(text: "Absender unvollständig (\(fehlt.joined(separator: ", "))): Einstellungen › Finanzamt.")
        }
        var kz: [(Int, String)] = []
        if berichtigt { kz.append((10, "1")) }
        if u.kz21 != 0 { kz.append((21, euro(u.kz21))) }
        if u.kz45 != 0 { kz.append((45, euro(u.kz45))) }
        if u.kz66 != 0 { kz.append((66, betrag(u.kz66))) }
        if u.kz67 != 0 { kz.append((67, betrag(u.kz67))) }
        if u.kz81 != 0 { kz.append((81, euro(u.kz81))) }
        kz.append((83, betrag(u.zahllast)))
        if u.kz84 != 0 { kz.append((84, euro(u.kz84))) }
        if u.kz85 != 0 { kz.append((85, betrag(u.kz85))) }
        if u.kz86 != 0 { kz.append((86, euro(u.kz86))) }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = appKalender
        df.timeZone = appKalender.timeZone
        df.dateFormat = "yyyyMMdd"
        var zeilen = [
            "<?xml version=\"1.0\" encoding=\"ISO-8859-15\"?>",
            "<Anmeldungssteuern xmlns=\"http://finkonsens.de/elster/elsteranmeldung/ustva/v\(jahr)\" version=\"\(jahr)\">",
            "  <Erstellungsdatum>\(df.string(from: erstellt))</Erstellungsdatum>",
            "  <DatenLieferant>",
        ]
        zeilen += felder.map { "    <\($0.0)>\(xmlEscape($0.1))</\($0.0)>" }
        zeilen += [
            "  </DatenLieferant>", "  <Steuerfall>", "    <Umsatzsteuervoranmeldung>",
            "      <Jahr>\(jahr)</Jahr>", "      <Zeitraum>\(zeitraum)</Zeitraum>",
            "      <Steuernummer>\(steuernummer)</Steuernummer>",
        ]
        zeilen += kz.map { "      <Kz\($0.0)>\($0.1)</Kz\($0.0)>" }
        zeilen += ["    </Umsatzsteuervoranmeldung>", "  </Steuerfall>", "</Anmeldungssteuern>", ""]
        return latin9(zeilen.joined(separator: "\n"))
    }

    /// ISO-8859-15; was darin fehlt, als numerische Zeichenreferenz (wie Pythons `xmlcharrefreplace`).
    private static func latin9(_ text: String) -> Data {
        let kodierung = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.isoLatin9.rawValue)))
        var ergebnis = Data()
        for zeichen in text {
            if let d = String(zeichen).data(using: kodierung) {
                ergebnis.append(d)
            } else {
                for skalar in zeichen.unicodeScalars { ergebnis.append(contentsOf: Array("&#\(skalar.value);".utf8)) }
            }
        }
        return ergebnis
    }

    // MARK: ZM

    /// Je USt-IdNr. eine Meldezeile, Art „S" (sonstige Leistung) – Kontor kennt keine Warenlieferungen.
    static func zmCSV(_ m: ZMMeldung) throws -> Data {
        if !m.ohneUstIdNr.isEmpty {
            throw Fehler(text: "Ohne USt-IdNr. nicht meldbar: " + m.ohneUstIdNr.map(\.kunde).joined(separator: ", "))
        }
        if m.zeilen.isEmpty { throw Fehler(text: "Keine Meldezeilen in diesem Quartal.") }
        let zeilen =
            ["#v3.0", "#ve3.2.1", "Umsatzsteuer-Identifikationsnummer (USt-IdNr.),Summe (Euro),Art der Leistung"]
            + m.zeilen.map { "\($0.ustIdNr),\(euro($0.netto)),S" } + [""]
        return Data(zeilen.joined(separator: "\n").utf8)
    }
}
