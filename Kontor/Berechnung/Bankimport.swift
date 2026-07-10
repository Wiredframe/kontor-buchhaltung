import Foundation

/// Eine geparste Bankbewegung aus dem Sparkasse-CSV-CAMT-Export (reiner Werttyp,
/// ohne SwiftData – damit der Parser testbar bleibt).
struct Bankbuchung: Hashable, Identifiable {
    var buchungstag: Date
    var betrag: Decimal            // signiert: + Eingang, − Ausgang
    var buchungstext: String       // z. B. KARTENZAHLUNG, SEPA-ELV-LASTSCHRIFT, ÜBERTRAG
    var verwendungszweck: String
    var gegenpartei: String        // „Beguenstigter/Zahlungspflichtiger" (Händlername)
    var iban: String               // Gegen-IBAN
    var glaeubigerID: String
    var mandatsreferenz: String
    var kundenreferenz: String     // End-to-End-Referenz
    var waehrung: String

    var id: String { dedupSchluessel }
    var istEingang: Bool { betrag > 0 }

    /// Kurzer Anzeige-/Bezeichnungsname in Normal Case (ALL-CAPS → Title Case): Händler vor
    /// dem ersten „/", sonst Zweck/Buchungstext. Rein kosmetisch – das Matching nutzt die Rohfelder.
    var anzeigename: String {
        let vorn = String(gegenpartei.split(separator: "/").first ?? "").trimmingCharacters(in: .whitespaces)
        let z = verwendungszweck.trimmingCharacters(in: .whitespaces)
        let roh = !vorn.isEmpty ? vorn : (z.isEmpty ? buchungstext : z)
        return Bankimport.normalCase(roh)
    }

    /// Stabiler Schlüssel für „schon importiert?". Datum+Betrag gehen **immer** ein: eine
    /// End-to-End-/Kundenreferenz ist bei Lastschriften oft eine feste Mandats-/Vertragsref
    /// (oder „NOTPROVIDED") und wiederholt sich monatlich – allein darauf zu schlüsseln würde
    /// Folgebuchungen fälschlich als „schon importiert" ausblenden. Die Referenz dient nur als
    /// zusätzliche Unterscheidung, falls die Bank eine echte eindeutige liefert.
    var dedupSchluessel: String {
        let basis = "\(Int(buchungstag.timeIntervalSince1970))|\(betrag)"
        if !kundenreferenz.isEmpty { return "k:\(kundenreferenz)|\(basis)" }
        let z = verwendungszweck.prefix(40).lowercased()
        return "h:\(basis)|\(gegenpartei.lowercased())|\(z)"
    }

    /// Schlüssel für lernende Zuordnungs-Vorschläge: Gläubiger-ID (sehr stabil bei
    /// Lastschriften) sonst der normalisierte Händlername (gut bei Kartenzahlungen).
    var haendlerSchluessel: String {
        glaeubigerID.isEmpty ? Bankimport.normalisiere(gegenpartei) : "gl:" + glaeubigerID
    }
}

/// Parser für den Sparkasse-CSV-CAMT-Export (V2/V8): ISO-8859-1, `;`-getrennt,
/// Felder in `"…"`. Spalten werden über den Header (nicht die Position) zugeordnet,
/// damit kleine Layout-Varianten der Bank nicht stören.
enum Bankimport {

    static func parse(_ data: Data) -> [Bankbuchung] {
        // Sparkasse-CSV ist Latin-1; UTF-8 als Fallback (falls die Bank das mal ändert).
        let text = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) ?? ""
        return parse(text: text)
    }

    static func parse(text: String) -> [Bankbuchung] {
        // Annahme: keine eingebetteten Zeilenumbrüche in Feldern (gilt für CSV-CAMT).
        let zeilen = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let kopf = zeilen.first else { return [] }
        var index: [String: Int] = [:]
        for (i, name) in felder(kopf).enumerated() { index[schluessel(name)] = i }

        func feld(_ row: [String], _ name: String) -> String {
            guard let i = index[schluessel(name)], i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespaces)
        }

        var ergebnis: [Bankbuchung] = []
        for zeile in zeilen.dropFirst() {
            let row = felder(zeile)
            guard let betrag = dezimal(feld(row, "Betrag")),
                  let datum = datum(feld(row, "Buchungstag")) else { continue }
            ergebnis.append(Bankbuchung(
                buchungstag: datum,
                betrag: betrag,
                buchungstext: feld(row, "Buchungstext"),
                verwendungszweck: feld(row, "Verwendungszweck"),
                gegenpartei: feld(row, "Beguenstigter/Zahlungspflichtiger"),
                iban: feld(row, "Kontonummer/IBAN"),
                glaeubigerID: feld(row, "Glaeubiger ID"),
                mandatsreferenz: feld(row, "Mandatsreferenz"),
                kundenreferenz: feld(row, "Kundenreferenz (End-to-End)"),
                waehrung: feld(row, "Waehrung")))
        }
        return ergebnis
    }

    /// Zerlegt eine CSV-Zeile an `;` – respektiert `"…"`-Quotes und `""`-Escapes.
    static func felder(_ zeile: String) -> [String] {
        var out: [String] = []
        var feld = ""
        var inQuote = false
        let chars = Array(zeile)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if inQuote, i + 1 < chars.count, chars[i + 1] == "\"" { feld.append("\""); i += 2; continue }
                inQuote.toggle(); i += 1; continue
            }
            if c == ";", !inQuote { out.append(feld); feld = ""; i += 1; continue }
            feld.append(c); i += 1
        }
        out.append(feld)
        return out
    }

    /// Normalisierter Händlername (für Lern-Schlüssel & Anzeige): Adresszusatz nach „/"
    /// abschneiden, klein, nur Wörter (Buchstaben/Ziffern), einfache Leerzeichen.
    static func normalisiere(_ s: String) -> String {
        let basis = String(s.split(separator: "/").first ?? Substring(s))
        return basis.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    /// Wandelt nur **ALL-CAPS**-Wörter in Title Case (bereits gemischte wie „GmbH", „Märznhof"
    /// bleiben unangetastet). Rein für die Anzeige/den gespeicherten Titel – ändert kein Matching.
    static func normalCase(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: false).map { teil -> String in
            let wort = String(teil)
            let buchstaben = wort.filter(\.isLetter)
            guard !buchstaben.isEmpty, buchstaben == buchstaben.uppercased(), buchstaben != buchstaben.lowercased()
            else { return wort }                       // gemischt/ohne Buchstaben → unverändert
            return wort.capitalized(with: Locale(identifier: "de_DE"))
        }.joined(separator: " ")
    }

    // MARK: - Feld-Parsing

    /// Spaltenname → kanonischer Schlüssel (nur Buchstaben/Ziffern, klein) für robustes Mapping.
    private static func schluessel(_ s: String) -> String {
        s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    /// Deutscher Betrag „-1.332,80" → Decimal (Punkt = Tausender, Komma = Dezimal).
    private static func dezimal(_ s: String) -> Decimal? {
        guard !s.isEmpty else { return nil }
        let normalisiert = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalisiert)
    }

    /// „25.06.26" (dd.MM.yy) → lokale Mitternacht via appKalender.
    private static func datum(_ s: String) -> Date? {
        let teile = s.split(separator: ".")
        guard teile.count == 3, let d = Int(teile[0]), let m = Int(teile[1]), var y = Int(teile[2]) else { return nil }
        if y < 100 { y += 2000 }
        return appKalender.date(from: DateComponents(year: y, month: m, day: d))
    }
}
