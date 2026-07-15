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

    /// Ergebnis eines CSV-Laufs – **inklusive dem, was nicht geklappt hat**.
    ///
    /// Vorher lieferte der Parser nur `[Bankbuchung]`. Damit sahen drei sehr verschiedene Lagen
    /// identisch aus: „keine neuen Buchungen", „ein paar Zeilen waren kaputt" und „die Datei
    /// wurde überhaupt nicht verstanden". Eine teilkorrupte CSV importierte still nur teilweise.
    struct Ergebnis {
        var buchungen: [Bankbuchung]
        /// Datenzeilen mit unlesbarem Betrag/Datum. Werden übersprungen – aber nicht lautlos.
        var verworfen: Int
        /// Wurden die tragenden Spalten (Betrag, Buchungstag) im Kopf gefunden?
        /// `false` heißt: falsche Datei oder fremdes Format, nicht „nichts drin".
        var kopfErkannt: Bool
    }

    static func lies(_ data: Data) -> Ergebnis {
        // Sparkasse-CSV ist Latin-1; UTF-8 als Fallback (falls die Bank das mal ändert).
        let text = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) ?? ""
        return lies(text: text)
    }

    static func lies(text: String) -> Ergebnis {
        // Annahme: keine eingebetteten Zeilenumbrüche in Feldern (gilt für CSV-CAMT).
        let zeilen = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let kopf = zeilen.first else { return Ergebnis(buchungen: [], verworfen: 0, kopfErkannt: false) }
        var index: [String: Int] = [:]
        for (i, name) in felder(kopf).enumerated() { index[schluessel(name)] = i }

        func feld(_ row: [String], _ name: String) -> String {
            guard let i = index[schluessel(name)], i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespaces)
        }

        let kopfErkannt = index[schluessel("Betrag")] != nil && index[schluessel("Buchungstag")] != nil

        var ergebnis: [Bankbuchung] = []
        var verworfen = 0
        for zeile in zeilen.dropFirst() {
            let row = felder(zeile)
            // Komplett leere Zeile (Trailing-Newline o. Ä.) ist kein Fehler, nur nichts.
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            guard let betrag = dezimal(feld(row, "Betrag")),
                  let datum = datum(feld(row, "Buchungstag")) else { verworfen += 1; continue }
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
        return Ergebnis(buchungen: ergebnis, verworfen: verworfen, kopfErkannt: kopfErkannt)
    }

    static func parse(_ data: Data) -> [Bankbuchung] { lies(data).buchungen }
    static func parse(text: String) -> [Bankbuchung] { lies(text: text).buchungen }

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

    /// Deutsches Betragsformat: optionales Vorzeichen, Tausender-Punkte in exakten 3er-Gruppen,
    /// Komma als Dezimaltrenner mit 1–2 Stellen. Bewusst **streng** verankert (`^…$`).
    private static let betragsMuster = "^[+-]?([0-9]{1,3}(\\.[0-9]{3})*|[0-9]+)(,[0-9]{1,2})?$"

    /// Deutscher Betrag „-1.332,80" → Decimal (Punkt = Tausender, Komma = Dezimal).
    ///
    /// Prüft das Format, statt es anzunehmen. Vorher wurden Punkte bedingungslos als
    /// Tausendertrenner entfernt: Ein englisch formatiertes „1332.80" wurde damit still zu
    /// **133.280,00 €** – hundertfach zu viel, ohne jeden Hinweis. Und `Decimal(string:)`
    /// parst Präfixe, „12abc" ergab **12**. Beides ist jetzt ausgeschlossen; solche Zeilen
    /// werden abgewiesen und als `verworfen` gemeldet, statt falsche Beträge zu buchen.
    private static func dezimal(_ s: String) -> Decimal? {
        guard s.range(of: betragsMuster, options: .regularExpression) != nil else { return nil }
        let normalisiert = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalisiert, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// „25.06.26" (dd.MM.yy) → lokale Mitternacht via appKalender.
    ///
    /// `Calendar.date(from:)` ist **lenient** und rollt Unsinn stillschweigend weiter:
    /// „32.13.26" ergäbe den 01.02.2027, „31.02.26" den 03.03.2026, „01.00.26" sogar den
    /// 01.12.2025 – also das **Vorjahr**. Eine so verrutschte Buchung landete im falschen
    /// Monat und damit in der falschen UStVA-Periode. `isValidDate(in:)` weist das ab, lässt
    /// echte Schaltjahrtage (29.02.2024) aber durch.
    private static func datum(_ s: String) -> Date? {
        let teile = s.split(separator: ".")
        guard teile.count == 3, let d = Int(teile[0]), let m = Int(teile[1]), var y = Int(teile[2]) else { return nil }
        if y < 100 { y += 2000 }
        let komponenten = DateComponents(year: y, month: m, day: d)
        guard komponenten.isValidDate(in: appKalender) else { return nil }
        return appKalender.date(from: komponenten)
    }
}
