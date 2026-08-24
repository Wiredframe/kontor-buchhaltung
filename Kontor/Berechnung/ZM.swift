import Foundation

// MARK: - Zusammenfassende Meldung (§18a UStG)

/// Eine Zeile der Zusammenfassenden Meldung: **je USt-IdNr. genau eine**, so wie das
/// BZSt-Formular sie erwartet. Mehrere Rechnungen an denselben Kunden werden addiert.
struct ZMZeile: Hashable, Identifiable {
    /// USt-IdNr. des Leistungsempfängers, normalisiert (siehe `ZMMeldung.normalisiere`).
    var ustIdNr: String
    /// Die Kundennamen hinter dieser UID – nur zur Sichtkontrolle in der App, nicht Teil der Meldung.
    /// Mehr als ein Name ist ein Hinweis auf einen Tippfehler in der UID oder im Kundennamen.
    var kunden: [String]
    /// Summe der gemeldeten Netto-Beträge (Ausfälle bereits abgezogen).
    var netto: Decimal
    /// Anzahl der eingeflossenen Rechnungen – erklärt, wie die Summe zustande kommt.
    var anzahl: Int

    var id: String { ustIdNr }
}

/// Ein meldepflichtiger Umsatz, der **nicht** gemeldet werden kann, weil die USt-IdNr. fehlt.
///
/// Trägt den Betrag mit, nicht nur den Namen: Ohne ihn bliebe unerklärlich, warum die
/// ZM-Summe von KZ 21 abweicht – und genau diese Differenz ist der Punkt.
struct ZMLuecke: Hashable, Identifiable {
    var kunde: String
    var netto: Decimal

    var id: String { kunde }
}

/// Das Ergebnis einer Quartals-ZM: die zu meldenden Zeilen plus die Rechnungen, die
/// **nicht** gemeldet werden können, weil ihnen die USt-IdNr. fehlt.
struct ZMMeldung: Hashable {
    var zeilen: [ZMZeile]
    /// Umsätze mit EU-Reverse-Charge, aber ohne (verwertbare) USt-IdNr.
    ///
    /// Bewusst getrennt ausgewiesen statt stillschweigend unter „ohne UID" mitzusummieren: Ohne
    /// gültige UID des Empfängers trägt die Reverse-Charge-Konstruktion nicht – dann ist nicht nur
    /// die Meldung unvollständig, sondern womöglich die ganze Rechnung falsch (dann nämlich
    /// steuerpflichtig im Inland). Das ist ein Fall zum Nachbessern, keine Fußnote.
    var ohneUstIdNr: [ZMLuecke]
    /// Summe über alle meldbaren Zeilen (ohne die Rechnungen in `ohneUstIdNr`).
    ///
    /// Gleich KZ 21 **nur wenn** `istVollstaendig`. Sonst fehlt hier genau `luecke`.
    var summe: Decimal

    /// Was wegen fehlender UID nicht in `summe` steckt – die Differenz zu KZ 21.
    var luecke: Decimal { ohneUstIdNr.reduce(Decimal(0)) { $0 + $1.netto } }
    /// Ist für dieses Quartal überhaupt etwas zu tun?
    var istLeer: Bool { zeilen.isEmpty && ohneUstIdNr.isEmpty }
    /// Kann die Meldung so abgegeben werden, oder fehlen noch UIDs?
    var istVollstaendig: Bool { ohneUstIdNr.isEmpty }
}

extension Steuer {

    /// Zusammenfassende Meldung für die Periode: gruppiert die meldepflichtigen Umsätze
    /// nach USt-IdNr. des Kunden und summiert das Netto.
    ///
    /// **Meldezeitraum ist das Quartal** (`§18a Abs. 2 UStG`) – auch bei monatlicher Voranmeldung,
    /// solange es um sonstige Leistungen geht. Abgabe bis zum **25. nach Quartalsende**; eine
    /// Dauerfristverlängerung gilt für die UStVA, **nicht** für die ZM.
    ///
    /// Uneinbringliche Forderungen (`§17`) mindern die Meldung im **Ausfallquartal**, spiegelbildlich
    /// zu `auslandsUmsatzNetto`/KZ 21. Dadurch bleiben Kennzahl und Meldung Betrag für Betrag gleich –
    /// eine Abweichung zwischen beiden ist der häufigste Anlass für Rückfragen des Finanzamts.
    static func zm(_ posten: [ZMPosten], in periode: Periode) -> ZMMeldung {
        var summen: [String: (kunden: [String], netto: Decimal, anzahl: Int)] = [:]
        var ohne: [String: Decimal] = [:]

        for p in posten {
            // Umsatz im Quartal zählt positiv, ein Ausfall im Quartal negativ. Beides kann
            // dieselbe Rechnung betreffen (Rechnung und Ausfall im selben Quartal) – dann
            // heben sich die Beiträge auf, und die Zeile bleibt korrekt bei 0.
            var betrag: Decimal = 0
            var trifft = false
            if periode.enthaelt(p.rechnungsdatum) {
                betrag += p.netto
                trifft = true
            }
            if p.status == .ausgefallen, let a = p.ausfalldatum, periode.enthaelt(a) {
                betrag -= p.netto
                trifft = true
            }
            guard trifft else { continue }

            guard let uid = normalisiere(p.ustIdNr) else {
                ohne[p.kunde, default: 0] += betrag
                continue
            }
            var eintrag = summen[uid] ?? (kunden: [], netto: 0, anzahl: 0)
            if !eintrag.kunden.contains(p.kunde) { eintrag.kunden.append(p.kunde) }
            eintrag.netto += betrag
            eintrag.anzahl += 1
            summen[uid] = eintrag
        }

        let zeilen =
            summen
            .map { ZMZeile(ustIdNr: $0.key, kunden: $0.value.kunden, netto: $0.value.netto, anzahl: $0.value.anzahl) }
            .sorted { $0.ustIdNr < $1.ustIdNr }
        return ZMMeldung(
            zeilen: zeilen,
            ohneUstIdNr: ohne.map { ZMLuecke(kunde: $0.key, netto: $0.value) }.sorted { $0.kunde < $1.kunde },
            summe: zeilen.reduce(Decimal(0)) { $0 + $1.netto })
    }

    /// USt-IdNr. auf Meldeform bringen: Großbuchstaben, ohne Leerzeichen, Punkte und Bindestriche.
    /// Liefert `nil`, wenn danach nichts Verwertbares übrig bleibt.
    ///
    /// Das ist keine Gültigkeitsprüfung – die ist nur über die **qualifizierte Bestätigungsabfrage**
    /// beim BZSt zu haben, und die braucht Netz. Kontor ist offline; die Abfrage bleibt Handarbeit,
    /// hier wird lediglich vermieden, dass „ATU 1234 5678" und „atu12345678" als zwei Kunden gelten.
    static func normalisiere(_ ustIdNr: String?) -> String? {
        guard let roh = ustIdNr else { return nil }
        let sauber = roh.uppercased().filter { $0.isLetter || $0.isNumber }
        return sauber.isEmpty ? nil : sauber
    }
}
