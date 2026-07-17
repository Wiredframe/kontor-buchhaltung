#if !APPSTORE
import Foundation
import SwiftData

/// Tools + Resources des Kontor-MCP-Servers.
///
/// **Token-sparend von Grund auf:** wenige, grobe Tools; Lese-Antworten sind fertige
/// Engine-Zahlen (`Steuer`/`Auswertung`) bzw. dichte CSV (`;`-getrennt, Punkt-Dezimal),
/// **keine** Rohzeilen-Dumps. Schreiben ist auf zwei eng umrissene Tools beschränkt und
/// legt vorab automatisch ein Backup an (`KISicherung`).
enum KontorMCP {

    struct Werkzeug { let name: String; let beschreibung: String; let schema: [String: Any] }

    static let briefing = """
    Kontor – lokale Buchhaltung eines Freiberuflers (EÜR, Soll-USt, KSK). Geld in EUR.
    Lesen: kontor_uebersicht (Jahres-Schnappschuss), kontor_eur (Gewinn/Ausgaben), \
    kontor_ustva (KZ-Zahlen je Quartal/Monat), kontor_monat (Rücklage), kontor_liste \
    (CSV je Modul: einnahmen, offene_rechnungen, ausgaben, fixkosten, subscriptions, vorlagen, ksk, \
    zahlungen, aufgaben, lebensmittel, einkaeufe). fixkosten/subscriptions sind datierte Buchungen \
    (mit Jahr/Monat filterbar); vorlagen = Sidebar-Vorlagen. \
    Schreiben (alle Module, selten nötig): kontor_anlegen / kontor_aktualisieren / kontor_loeschen \
    mit demselben typ-Vokabular; für Ändern/Löschen vorher kontor_liste mit mit_id=true (liefert die id). \
    Belege: kontor_beleg hängt eine PDF/Bild (Base64) an einnahmen|ausgaben|einkaeufe an (Feld belegPfad, \
    Ablage Belege/<Jahr>/); die beleg-Spalte dieser Listen zeigt den hinterlegten Pfad. \
    Beträge stets brutto in EUR, Datum als YYYY-MM-DD. Zahlen sind Schätzungen, keine Steuerberatung.
    """

    // MARK: - Tool-Katalog

    static var werkzeuge: [Werkzeug] {
        [
            Werkzeug(name: "kontor_uebersicht",
                     beschreibung: "Kompakter Finanz-Schnappschuss eines Jahres: EÜR-Gewinn, USt-Zahllast, offene Rechnungen, KSK/Monat, Betriebsausgaben, nächste Frist.",
                     schema: obj(props: ["jahr": zahl("Kalenderjahr, Default = laufendes Jahr.")])),
            Werkzeug(name: "kontor_eur",
                     beschreibung: "EÜR-Jahresrechnung (Zuflussprinzip): bezahlte Einnahmen, Betriebsausgaben (netto), Vorsteuer, Gewinn.",
                     schema: obj(props: ["jahr": zahl("Kalenderjahr.")], required: ["jahr"])),
            Werkzeug(name: "kontor_ustva",
                     beschreibung: "UStVA-Kennzahlen (Soll) einer Periode: KZ81/USt19/KZ66/KZ84/KZ85/KZ67, §17-Korrektur, Zahllast KZ83. Quartal ODER Monat angeben.",
                     schema: obj(props: [
                        "jahr": zahl("Kalenderjahr."),
                        "quartal": zahl("Quartal 1–4 (alternativ zu monat)."),
                        "monat": zahl("Monat 1–12 (alternativ zu quartal)."),
                     ], required: ["jahr"])),
            Werkzeug(name: "kontor_monat",
                     beschreibung: "Monatsauswertung/Rücklage: RN, USt, Vorsteuer, KSK, ESt-Rücklage, Steuerrücklage gesamt, frei verfügbar.",
                     schema: obj(props: [
                        "jahr": zahl("Kalenderjahr."),
                        "monat": zahl("Monat 1–12."),
                     ], required: ["jahr", "monat"])),
            Werkzeug(name: "kontor_liste",
                     beschreibung: "Datensätze eines Moduls als CSV (;-getrennt). typ: einnahmen | offene_rechnungen | ausgaben | fixkosten | subscriptions | vorlagen | ksk | zahlungen | aufgaben | lebensmittel | einkaeufe. fixkosten/subscriptions sind datierte Buchungen (mit Jahr/Monat filterbar wie Ausgaben); vorlagen komplett. ksk = Monatswerte KV/RV/PV/JAE/Summe eines Jahres (read-only, ohne id). Für Ändern/Löschen mit_id=true setzen → letzte Spalte 'id'.",
                     schema: obj(props: [
                        "typ": text("einnahmen | offene_rechnungen | ausgaben | fixkosten | subscriptions | vorlagen | ksk | zahlungen | aufgaben | lebensmittel | einkaeufe"),
                        "jahr": zahl("Jahr-Filter (datierte Listen)."),
                        "monat": zahl("Monat-Filter 1–12 (datierte Listen)."),
                        "status": text("Status-Filter (Einnahmen: offen|bezahlt|ausgefallen)."),
                        "limit": zahl("Max. Zeilen, Default 50."),
                        "mit_id": flag("id-Spalte für kontor_aktualisieren/kontor_loeschen anhängen (Default false)."),
                     ], required: ["typ"])),
            Werkzeug(name: "kontor_anlegen",
                     beschreibung: """
                     Legt einen Datensatz in einem Modul an. Datum als YYYY-MM-DD, Geld brutto in EUR. 'felder' je typ:
                     einnahmen: kunde, rnNetto, ust, rechnungsdatum [, satz(satz19|satz7, Default satz19), zahlungsdatum, status(offen|bezahlt|ausgefallen), ausfalldatum, rechnungsnummer, rnNetto2, ust2, satz2(satz19|satz7) für Mischrechnungen];
                     ausgaben: datum, bezeichnung, brutto [, anbieter, vst(sonst geschätzt), steuerart(inland19|inland7|reverseCharge|steuerfrei), kategorie(laufend|jaehrlich|anschaffung), betrieblich, umlagefaehig];
                     fixkosten / subscriptions (datierte Buchung): datum, bezeichnung, betrag [, anbieter, vst(sonst geschätzt), steuerart, betrieblich, umlagefaehig];
                     vorlagen (Sidebar-Vorlage): bezeichnung, betrag [, anbieter, steuerart, betrieblich, art(fixkosten|subscription), umlagefaehig];
                     zahlungen: kind(ustVz|estVz|estBescheid|ksk|sonstige), jahr, faellig [, betrag, bezahlt, bezahltAm, bemerkung];
                     aufgaben: titel, monat [, intervall(einmalig|monatlich|quartalsweise|jaehrlich), faelligTag, quartalsMonate, erledigt];
                     lebensmittel: datum, betrag [, ort];
                     einkaeufe: datum, bezeichnung, preis.
                     """,
                     schema: obj(props: [
                        "typ": text("Modul (wie bei kontor_liste, Singular-Synonyme erlaubt)."),
                        "felder": freiObj("Feld→Wert je typ (siehe Beschreibung)."),
                     ], required: ["typ", "felder"])),
            Werkzeug(name: "kontor_aktualisieren",
                     beschreibung: "Ändert Felder eines bestehenden Datensatzes. 'id' stammt aus kontor_liste mit mit_id=true. Nur übergebene 'felder' werden geändert (Feldnamen wie bei kontor_anlegen). typ wie bei kontor_liste.",
                     schema: obj(props: [
                        "typ": text("Modul (wie bei kontor_liste)."),
                        "id": text("id aus kontor_liste (mit_id=true)."),
                        "felder": freiObj("Zu ändernde Felder (Feldnamen wie bei kontor_anlegen)."),
                     ], required: ["typ", "id", "felder"])),
            Werkzeug(name: "kontor_loeschen",
                     beschreibung: "Löscht einen Datensatz. 'id' stammt aus kontor_liste mit mit_id=true. typ wie bei kontor_liste. Vorher wird automatisch ein Backup angelegt.",
                     schema: obj(props: [
                        "typ": text("Modul (wie bei kontor_liste)."),
                        "id": text("id aus kontor_liste (mit_id=true)."),
                     ], required: ["typ", "id"])),
            Werkzeug(name: "kontor_beleg",
                     beschreibung: """
                     Hängt eine Beleg-PDF (oder Bild) an einen Datensatz an und legt die Datei lokal unter \
                     Belege/<Jahr>/ ab (Jahr = Datum des Datensatzes); der relative Pfad wird im Feld 'belegPfad' \
                     gespeichert. Nur Module mit Beleg: einnahmen | ausgaben | einkaeufe. 'inhalt_base64' = \
                     Base64 des Dateiinhalts, 'dateiname' liefert Endung/Name. 'id' aus kontor_liste (mit_id=true). \
                     Ein vorhandener Beleg wird ersetzt. Mit entfernen=true wird nur der Verweis gelöst (kein Upload).
                     """,
                     schema: obj(props: [
                        "typ": text("einnahmen | ausgaben | einkaeufe"),
                        "id": text("id aus kontor_liste (mit_id=true)."),
                        "dateiname": text("Originaldateiname inkl. Endung, z. B. 'RE41197676.pdf'."),
                        "inhalt_base64": text("Base64-kodierter Dateiinhalt (PDF/Bild)."),
                        "entfernen": flag("true → vorhandenen Beleg-Verweis entfernen (ohne Upload)."),
                     ], required: ["typ", "id"])),
        ]
    }

    // MARK: - Tool-Ausführung

    @MainActor
    static func fuehreAus(name: String, argumente a: [String: Any], container: ModelContainer) throws -> String {
        let ctx = container.mainContext
        switch name {
        case "kontor_uebersicht": return uebersichtText(jahr: intArg(a["jahr"]) ?? heuteJahr, ctx)
        case "kontor_eur":        return eurText(jahr: try pflichtInt(a, "jahr", bereich: jahrBereich), ctx)
        case "kontor_ustva":      return ustvaText(jahr: try pflichtInt(a, "jahr", bereich: jahrBereich),
                                                    quartal: try intArg(a, "quartal", bereich: 1...4),
                                                    monat: try intArg(a, "monat", bereich: 1...12), ctx)
        case "kontor_monat":      return monatText(jahr: try pflichtInt(a, "jahr", bereich: jahrBereich),
                                                    monat: try pflichtInt(a, "monat", bereich: 1...12), ctx)
        case "kontor_liste":      return try listeCSV(a, ctx)
        case "kontor_anlegen":       return try anlegen(a, ctx)
        case "kontor_aktualisieren": return try aktualisieren(a, ctx)
        case "kontor_loeschen":      return try loeschen(a, ctx)
        case "kontor_beleg":         return try beleg(a, ctx)
        default: throw MCPFehler("Unbekanntes Tool: \(name)")
        }
    }

    // MARK: - Resources

    static let ressourcen: [[String: Any]] = [
        ["uri": "kontor://uebersicht", "name": "Übersicht (laufendes Jahr)",
         "description": "Finanz-Schnappschuss des laufenden Jahres.", "mimeType": "text/plain"],
    ]

    static let ressourcenVorlagen: [[String: Any]] = [
        ["uriTemplate": "kontor://eur/{jahr}", "name": "EÜR-Jahr",
         "description": "EÜR-Jahresrechnung für {jahr}.", "mimeType": "text/plain"],
        ["uriTemplate": "kontor://ustva/{jahr}/{quartal}", "name": "UStVA-Quartal",
         "description": "UStVA-Kennzahlen für {jahr} Quartal {quartal}.", "mimeType": "text/plain"],
        ["uriTemplate": "kontor://monat/{jahr}/{monat}", "name": "Monatsauswertung",
         "description": "Monatsauswertung/Rücklage für {jahr}-{monat}.", "mimeType": "text/plain"],
    ]

    @MainActor
    static func leseRessource(uri: String, container: ModelContainer) throws -> String {
        let ctx = container.mainContext
        let rest = uri.hasPrefix("kontor://") ? String(uri.dropFirst("kontor://".count)) : uri
        let teile = rest.split(separator: "/").map(String.init)
        switch teile.first {
        case "uebersicht": return uebersichtText(jahr: heuteJahr, ctx)
        case "eur":
            guard teile.count >= 2, let j = Int(teile[1]) else { throw MCPFehler("Erwartet kontor://eur/{jahr}") }
            return eurText(jahr: j, ctx)
        case "ustva":
            guard teile.count >= 3, let j = Int(teile[1]), let q = Int(teile[2]) else { throw MCPFehler("Erwartet kontor://ustva/{jahr}/{quartal}") }
            return ustvaText(jahr: j, quartal: q, monat: nil, ctx)
        case "monat":
            guard teile.count >= 3, let j = Int(teile[1]), let m = Int(teile[2]) else { throw MCPFehler("Erwartet kontor://monat/{jahr}/{monat}") }
            return monatText(jahr: j, monat: m, ctx)
        default: throw MCPFehler("Unbekannte Ressource: \(uri)")
        }
    }

    // MARK: - Lese-Formatter (Engine-Zahlen)

    @MainActor
    static func uebersichtText(jahr: Int, _ ctx: ModelContext) -> String {
        let e = einnahmenPosten(ctx), aus = ausgabenPosten(ctx)
        let jahresA = Steuer.jahresauswertung(jahr: jahr, einnahmen: e, ausgaben: aus)
        let zahllast = Steuer.ustva(einnahmen: e, ausgaben: aus, periode: .jahr(jahr)).zahllast
        let offene = alle(Income.self, ctx).filter { $0.status == .offen }
        let offeneSumme = offene.reduce(Decimal(0)) { $0 + $1.brutto }
        let kskMonat = jahr == heuteJahr ? heuteMonat : 12
        let ksk = alle(YearSettings.self, ctx).ksk(jahr: jahr, monat: kskMonat)
        var z = [
            "Kontor – Übersicht \(jahr)",
            "EÜR-Gewinn (Zufluss):        \(g(jahresA.gewinn)) €",
            "USt-Zahllast (Jahr, Soll):   \(g(zahllast)) €",
            "Offene Rechnungen:           \(offene.count) (\(g(offeneSumme)) €)",
            "KSK/Monat:                   \(g(ksk)) €",
            "Betriebsausgaben (netto):    \(g(jahresA.ausgabenNetto)) €",
        ]
        if let f = naechsteFrist(ctx) { z.append("Nächste Frist:               \(tagText(f.faellig)) – \(f.kind.bezeichnung) \(g(f.betrag)) €") }
        return z.joined(separator: "\n")
    }

    @MainActor
    static func eurText(jahr: Int, _ ctx: ModelContext) -> String {
        let a = Steuer.jahresauswertung(jahr: jahr, einnahmen: einnahmenPosten(ctx), ausgaben: ausgabenPosten(ctx))
        return """
        EÜR \(jahr)
        Einnahmen (bezahlt, netto):  \(g(a.einnahmenBezahlt)) €
        Betriebsausgaben (netto):    \(g(a.ausgabenNetto)) €
        Vorsteuer gesamt:            \(g(a.vstGesamt)) €
        Gewinn:                      \(g(a.gewinn)) €
        """
    }

    @MainActor
    static func ustvaText(jahr: Int, quartal: Int?, monat: Int?, _ ctx: ModelContext) -> String {
        let periode: Periode; let label: String
        if let m = monat { periode = .monat(jahr, m); label = "\(jahr)-\(String(format: "%02d", m))" }
        else {
            let q = quartal ?? (jahr == heuteJahr ? (heuteMonat + 2) / 3 : 4)
            periode = .quartal(jahr, q); label = "\(jahr) Q\(q)"
        }
        let r = Steuer.ustva(einnahmen: einnahmenPosten(ctx), ausgaben: ausgabenPosten(ctx), periode: periode)
        return """
        UStVA \(label)
        KZ81 (Netto 19 %):           \(g(r.kz81)) €
        USt 19 % (auto):             \(g(r.ust81)) €
        KZ86 (Netto 7 %):            \(g(r.kz86)) €
        USt 7 % (auto):              \(g(r.ust86)) €
        KZ66 (Vorsteuer Inland):     \(g(r.kz66)) €
        KZ84 (§13b Netto):           \(g(r.kz84)) €
        KZ85 (§13b USt):             \(g(r.kz85)) €
        KZ67 (§13b Vorsteuer):       \(g(r.kz67)) €
        §17-Korrektur:               \(g(r.korrektur17)) €
        Zahllast (KZ83):             \(g(r.zahllast)) €
        """
    }

    @MainActor
    static func monatText(jahr: Int, monat: Int, _ ctx: ModelContext) -> String {
        let settings = alle(YearSettings.self, ctx)
        let fixPrivat = alle(ExpenseEntry.self, ctx).wiederkehrendBrutto(jahr: jahr, monat: monat, betrieblich: false)
        // Privat variabel gehört in den Waterfall – sonst meldete „Frei verfügbar" zu viel.
        let p = Periode.monat(jahr, monat)
        let lm = alle(GroceryEntry.self, ctx).filter { p.enthaelt($0.datum) }.reduce(Decimal(0)) { $0 + $1.betrag }
        let an = alle(PurchaseEntry.self, ctx).filter { p.enthaelt($0.datum) }.reduce(Decimal(0)) { $0 + $1.preis }
        let einmalig = alle(ExpenseEntry.self, ctx).privatEinmaligBrutto(jahr: jahr, monat: monat)
        let a = Steuer.monatsauswertung(
            monat: monat, jahr: jahr,
            einnahmen: einnahmenPosten(ctx), ausgaben: ausgabenPosten(ctx),
            kskFuer: { j, m in settings.ksk(jahr: j, monat: m) },
            fixkostenPrivat: fixPrivat,
            privatVariabel: lm + an + einmalig,
            pauschalSatz: { j, m in settings.estSatz(jahr: j, monat: m) })
        return """
        Monat \(jahr)-\(String(format: "%02d", monat))
        RN (netto, Soll):            \(g(a.rn)) €
        USt:                         \(g(a.ust)) €
        Brutto:                      \(g(a.brutto)) €
        Vorsteuer:                   \(g(a.vst)) €
        Betriebsausgaben (netto):    \(g(a.betriebsausgabenNetto)) €
        Betrieblicher Gewinn:        \(g(a.betrieblicherGewinn)) €
        KSK:                         \(g(a.ksk)) €
        ESt-Rücklage:                \(g(a.est + a.estKorrektur)) €
        Steuerrücklage gesamt:       \(g(a.steuerRuecklage)) €
        Fixkosten privat:            \(g(a.fixkostenPrivat)) €
        Privat variabel:             \(g(a.privatVariabel)) €
        Frei verfügbar:              \(g(a.verfuegbar)) €
        """
    }

    // MARK: - Liste (CSV)

    @MainActor
    static func listeCSV(_ a: [String: Any], _ ctx: ModelContext) throws -> String {
        let typ = (a["typ"] as? String ?? "").lowercased()
        let jahr = try intArg(a, "jahr", bereich: jahrBereich)
        let monat = try intArg(a, "monat", bereich: 1...12)
        // Geklemmt statt vertraut: `Array.prefix(_:)` hat precondition(maxLength >= 0) – ein
        // limit von -1 riss die gesamte App runter, per einzelnem MCP-Aufruf. Die Obergrenze
        // hält die Antwort tokensparend (und den Vollfetch auf dem MainActor kurz).
        let limit = min(max(intArg(a["limit"]) ?? 50, 0), 1000)
        let mitId = a["mit_id"] as? Bool ?? false
        func imZeitraum(_ d: Date) -> Bool {
            if let j = jahr, appKalender.component(.year, from: d) != j { return false }
            if let m = monat, appKalender.component(.month, from: d) != m { return false }
            return true
        }
        func kopf(_ k: [String]) -> [String] { mitId ? k + ["id"] : k }
        func zeile(_ m: any PersistentModel, _ v: [String]) -> [String] { mitId ? v + [idText(m)] : v }
        switch typ {
        case "einnahmen":
            let status = (a["status"] as? String).flatMap { InvoiceStatus(rawValue: $0) }
            let rows = alle(Income.self, ctx)
                .filter { imZeitraum($0.rechnungsdatum) && (status == nil || $0.status == status) }
                .sorted { $0.rechnungsdatum < $1.rechnungsdatum }.prefix(limit)
            return csv(kopf(["datum", "rechnungsnummer", "kunde", "netto", "ust", "satz", "netto2", "ust2", "satz2", "brutto", "status", "zahlungsdatum", "beleg"]),
                       rows.map { zeile($0, [tagText($0.rechnungsdatum), $0.rechnungsnummer ?? "", $0.kunde,
                                   g($0.rnNetto), g($0.ust), $0.satzEffektiv.rawValue,
                                   g($0.rnNetto2), g($0.ust2), $0.satz2?.rawValue ?? "",
                                   g($0.brutto), $0.status.rawValue,
                                   $0.zahlungsdatum.map(tagText) ?? "", $0.belegPfad ?? ""]) })
        case "offene_rechnungen":
            let rows = alle(Income.self, ctx).filter { $0.status == .offen && imZeitraum($0.rechnungsdatum) }
                .sorted { $0.rechnungsdatum < $1.rechnungsdatum }.prefix(limit)
            return csv(kopf(["datum", "rechnungsnummer", "kunde", "brutto"]),
                       rows.map { zeile($0, [tagText($0.rechnungsdatum), $0.rechnungsnummer ?? "", $0.kunde, g($0.brutto)]) })
        case "ausgaben":
            let rows = alle(ExpenseEntry.self, ctx).filter { imZeitraum($0.datum) }
                .sorted { $0.datum < $1.datum }.prefix(limit)
            return csv(kopf(["datum", "bezeichnung", "anbieter", "brutto", "vst", "netto", "steuerart", "betrieblich", "beleg"]),
                       rows.map { zeile($0, [tagText($0.datum), $0.bezeichnung, $0.anbieter, g($0.brutto), g($0.vst), g($0.netto),
                                   $0.steuerart.rawValue, $0.betrieblich ? "ja" : "nein", $0.belegPfad ?? ""]) })
        case "fixkosten", "subscriptions":
            // Datierte Buchungen (Fixkosten/Subscriptions) – nach Art gefiltert, mit Zeitraum.
            let zielArt: AusgabeArt = (typ == "subscriptions") ? .subscription : .fixkosten
            let rows = alle(ExpenseEntry.self, ctx).filter { $0.artEffektiv == zielArt && imZeitraum($0.datum) }
                .sorted { $0.datum < $1.datum }.prefix(limit)
            return csv(kopf(["datum", "bezeichnung", "anbieter", "brutto", "vst", "netto", "steuerart", "betrieblich", "beleg"]),
                       rows.map { zeile($0, [tagText($0.datum), $0.bezeichnung, $0.anbieter, g($0.brutto), g($0.vst), g($0.netto),
                                   $0.steuerart.rawValue, $0.betrieblich ? "ja" : "nein", $0.belegPfad ?? ""]) })
        case "vorlagen":
            let rows = alle(Vorlage.self, ctx).sorted { $0.bezeichnung < $1.bezeichnung }.prefix(limit)
            return csv(kopf(["bezeichnung", "anbieter", "brutto", "art", "steuerart", "betrieblich"]),
                       rows.map { zeile($0, [$0.bezeichnung, $0.anbieter, g($0.betragBrutto), $0.art.rawValue,
                                   $0.steuerart.rawValue, $0.betrieblich ? "ja" : "nein"]) })
        case "aufgaben":
            let rows = alle(MonthlyTask.self, ctx).filter { imZeitraum($0.monat) }
                .sorted { $0.monat < $1.monat }.prefix(limit)
            return csv(kopf(["faellig", "titel", "intervall", "erledigt", "faelligTag"]),
                       rows.map { zeile($0, [tagText($0.monat), $0.titel, $0.intervall.rawValue, $0.erledigt ? "ja" : "nein", String($0.faelligTag)]) })
        case "lebensmittel":
            let rows = alle(GroceryEntry.self, ctx).filter { imZeitraum($0.datum) }
                .sorted { $0.datum < $1.datum }.prefix(limit)
            return csv(kopf(["datum", "ort", "betrag"]), rows.map { zeile($0, [tagText($0.datum), $0.ort, g($0.betrag)]) })
        case "einkaeufe", "anschaffungen":
            let rows = alle(PurchaseEntry.self, ctx).filter { imZeitraum($0.datum) }
                .sorted { $0.datum < $1.datum }.prefix(limit)
            return csv(kopf(["datum", "bezeichnung", "preis", "beleg"]), rows.map { zeile($0, [tagText($0.datum), $0.bezeichnung, g($0.preis), $0.belegPfad ?? ""]) })
        case "zahlungen":
            let rows = alle(TaxPayment.self, ctx)
                .filter { (jahr == nil || $0.jahr == jahr) && (monat == nil || appKalender.component(.month, from: $0.faellig) == monat) }
                .sorted { $0.faellig < $1.faellig }.prefix(limit)
            return csv(kopf(["faellig", "art", "jahr", "betrag", "bezahlt", "bezahltAm", "bemerkung"]),
                       rows.map { zeile($0, [tagText($0.faellig), $0.kind.rawValue, String($0.jahr), g($0.betrag),
                                   $0.bezahlt ? "ja" : "nein", $0.bezahltAm.map(tagText) ?? "", $0.bemerkung]) })
        case "ksk":
            // KSK (Soll) ist ein Monatswert auf YearSettings – **kein** eigenständiger Datensatz,
            // daher read-only und ohne id-Spalte. Je Monat KV/RV/PV/JAE/Summe des Jahres.
            let j = jahr ?? heuteJahr
            let kskKopf = ["jahr", "monat", "kv", "rv", "pv", "jae", "summe"]
            guard let s = alle(YearSettings.self, ctx).first(where: { $0.jahr == j }) else {
                return csv(kskKopf, [])
            }
            let monate = monat.map { [$0] } ?? Array(1...12)
            return csv(kskKopf, monate.map { m in
                let t = s.kskTeile(monat: m)
                return [String(j), String(m), g(t.kv), g(t.rv), g(t.pv), g(s.jae(monat: m)), g(s.ksk(monat: m))]
            })
        default:
            throw MCPFehler("Unbekannter typ '\(typ)'. Erlaubt: einnahmen | offene_rechnungen | ausgaben | fixkosten | subscriptions | vorlagen | ksk | zahlungen | aufgaben | lebensmittel | einkaeufe")
        }
    }

    // MARK: - Schreib-Tools (generisch über alle Module)

    @MainActor
    static func anlegen(_ a: [String: Any], _ ctx: ModelContext) throws -> String {
        let typ = (a["typ"] as? String ?? "").lowercased()
        let f = a["felder"] as? [String: Any] ?? [:]
        try KISicherung.sichereVorSchreibzugriff(ctx)
        let obj: any PersistentModel
        switch typ {
        case "einnahmen", "einnahme":
            guard let kunde = f["kunde"] as? String, let netto = dezArg(f["rnNetto"]),
                  let ust = dezArg(f["ust"]), let rdat = datum(f["rechnungsdatum"]) else {
                throw fehlt("einnahmen", "kunde, rnNetto, ust, rechnungsdatum") }
            let s: InvoiceStatus = enumWert(f["status"]) ?? .offen
            // Status/Datum konsistent halten: Eine ausgefallene Rechnung **ohne** Ausfalldatum
            // ist ein Widerspruch – die gesamte §17-Logik (ustKorrekturAusfall, ausfallNetto,
            // estAusfallKorrektur) filtert auf `ausfalldatum != nil`. Sie stünde also für immer
            // als ausgefallen da, ohne dass USt oder ESt-Rücklage je korrigiert würden.
            // Fällt kein Datum, gilt der Zeitpunkt der Feststellung – wie `setze(status:)` es
            // in der UI auch macht (der Raw-Init hier umging das).
            let ausfall = datum(f["ausfalldatum"]) ?? (s == .ausgefallen ? Date() : nil)
            obj = Income(kunde: kunde, rnNetto: netto, ust: ust, rechnungsdatum: rdat,
                         zahlungsdatum: datum(f["zahlungsdatum"]) ?? (s == .bezahlt ? rdat : nil),
                         status: s, ausfalldatum: ausfall,
                         rechnungsnummer: f["rechnungsnummer"] as? String,
                         satz: enumWert(f["satz"]),
                         rnNetto2: dezArg(f["rnNetto2"]) ?? 0, ust2: dezArg(f["ust2"]) ?? 0,
                         satz2: enumWert(f["satz2"]))
        case "ausgaben", "ausgabe":
            guard let dat = datum(f["datum"]), let bez = f["bezeichnung"] as? String, let brutto = dezArg(f["brutto"]) else {
                throw fehlt("ausgaben", "datum, bezeichnung, brutto") }
            let st: Steuerart = enumWert(f["steuerart"]) ?? .inland19
            obj = ExpenseEntry(datum: dat, bezeichnung: bez, anbieter: f["anbieter"] as? String ?? "",
                               brutto: brutto, vst: dezArg(f["vst"]) ?? Steuer.vorsteuerVorschlag(brutto: brutto, steuerart: st),
                               steuerart: st,
                               betrieblich: f["betrieblich"] as? Bool ?? true,
                               umlagefaehig: f["umlagefaehig"] as? Bool ?? false,
                               // `art` **explizit** setzen. Das war der einzige Erzeuger-Pfad im
                               // Projekt, der es wegließ – und `art == nil` greift `ArtNachtrag`
                               // beim nächsten Start auf und rät die Art aus dem Namen: Eine per
                               // MCP gebuchte einmalige Ausgabe namens „Adobe" wurde so still zur
                               // `.subscription` und von „Vormonat duplizieren" mitgeschleppt.
                               art: .betriebsausgabe)
        case "fixkosten", "subscriptions", "subscription":
            guard let bez = f["bezeichnung"] as? String,
                  let brutto = dezArg(f["betrag"]) ?? dezArg(f["betragBrutto"]) ?? dezArg(f["brutto"]),
                  let dat = datum(f["datum"]) else { throw fehlt(typ, "bezeichnung, betrag, datum") }
            let st: Steuerart = enumWert(f["steuerart"]) ?? .steuerfrei
            let zielArt: AusgabeArt = (typ == "fixkosten") ? .fixkosten : .subscription
            obj = ExpenseEntry(datum: dat, bezeichnung: bez, anbieter: f["anbieter"] as? String ?? "",
                               brutto: brutto, vst: dezArg(f["vst"]) ?? Steuer.vorsteuerVorschlag(brutto: brutto, steuerart: st),
                               steuerart: st,
                               betrieblich: f["betrieblich"] as? Bool ?? false,
                               umlagefaehig: f["umlagefaehig"] as? Bool ?? false, art: zielArt)
        case "vorlagen", "vorlage":
            guard let bez = f["bezeichnung"] as? String,
                  let brutto = dezArg(f["betrag"]) ?? dezArg(f["betragBrutto"]) ?? dezArg(f["brutto"]) else {
                throw fehlt("vorlagen", "bezeichnung, betrag") }
            obj = Vorlage(bezeichnung: bez, anbieter: f["anbieter"] as? String ?? "", betragBrutto: brutto,
                          steuerart: enumWert(f["steuerart"]) ?? .steuerfrei,
                          betrieblich: f["betrieblich"] as? Bool ?? false,
                          art: (f["art"] as? String == "subscription") ? .subscription : .fixkosten,
                          umlagefaehig: f["umlagefaehig"] as? Bool ?? false)
        case "zahlungen", "zahlung":
            guard let kind: SteuerKind = enumWert(f["kind"]), let jahr = intArg(f["jahr"]), let fae = datum(f["faellig"]) else {
                throw fehlt("zahlungen", "kind, jahr, faellig") }
            obj = TaxPayment(kind: kind, jahr: jahr, faellig: fae, betrag: dezArg(f["betrag"]) ?? 0,
                             bezahlt: f["bezahlt"] as? Bool ?? false, bezahltAm: datum(f["bezahltAm"]),
                             bemerkung: f["bemerkung"] as? String ?? "")
        case "aufgaben", "aufgabe":
            guard let titel = f["titel"] as? String, let m = datum(f["monat"] ?? f["faellig"]) else { throw fehlt("aufgaben", "titel, monat") }
            let qm = (f["quartalsMonate"] as? [Any])?.compactMap { intArg($0) } ?? []
            obj = MonthlyTask(titel: titel, monat: m, erledigt: f["erledigt"] as? Bool ?? false,
                              intervall: enumWert(f["intervall"]) ?? .einmalig, faelligTag: intArg(f["faelligTag"]) ?? 1, quartalsMonate: qm)
        case "lebensmittel":
            guard let dat = datum(f["datum"]), let betrag = dezArg(f["betrag"]) else { throw fehlt("lebensmittel", "datum, betrag") }
            obj = GroceryEntry(datum: dat, betrag: betrag, ort: f["ort"] as? String ?? "")
        case "einkaeufe", "einkauf", "anschaffungen", "anschaffung":
            guard let dat = datum(f["datum"]), let bez = f["bezeichnung"] as? String, let preis = dezArg(f["preis"]) else {
                throw fehlt("einkaeufe", "datum, bezeichnung, preis") }
            obj = PurchaseEntry(datum: dat, bezeichnung: bez, preis: preis)
        default:
            throw MCPFehler("Unbekannter typ '\(typ)' für kontor_anlegen.")
        }
        ctx.insert(obj)
        try ctx.save()
        return "Angelegt (\(typ)). id=\(idText(obj))"
    }

    @MainActor
    static func aktualisieren(_ a: [String: Any], _ ctx: ModelContext) throws -> String {
        let typ = (a["typ"] as? String ?? "").lowercased()
        guard let id = a["id"] as? String, !id.isEmpty else { throw MCPFehler("'id' fehlt (aus kontor_liste mit mit_id=true).") }
        let f = a["felder"] as? [String: Any] ?? [:]
        guard !f.isEmpty else { throw MCPFehler("Keine 'felder' zum Ändern übergeben.") }
        try KISicherung.sichereVorSchreibzugriff(ctx)
        func hat(_ k: String) -> Bool { f.keys.contains(k) }
        switch typ {
        case "einnahmen", "einnahme":
            let o = try modell(Income.self, id: id, ctx)
            if let v = f["kunde"] as? String { o.kunde = v }
            if let v = dezArg(f["rnNetto"]) { o.rnNetto = v }
            if let v = dezArg(f["ust"]) { o.ust = v }
            if let v = datum(f["rechnungsdatum"]) { o.rechnungsdatum = v }
            if let v: InvoiceStatus = enumWert(f["status"]) { o.setze(status: v) }
            // `datumFeld` wirft bei unparsbarem Datum, statt das Feld still zu leeren.
            if let v = try datumFeld(f, "zahlungsdatum") { o.zahlungsdatum = v }
            if let v = try datumFeld(f, "ausfalldatum") { o.ausfalldatum = v }
            if hat("rechnungsnummer") { o.rechnungsnummer = f["rechnungsnummer"] as? String }
            if hat("satz") { o.satz = enumWert(f["satz"]) }
            if let v = dezArg(f["rnNetto2"]) { o.rnNetto2 = v }
            if let v = dezArg(f["ust2"]) { o.ust2 = v }
            if hat("satz2") { o.satz2 = enumWert(f["satz2"]) }
        case "ausgaben", "ausgabe":
            let o = try modell(ExpenseEntry.self, id: id, ctx)
            if let v = datum(f["datum"]) { o.datum = v }
            if let v = f["bezeichnung"] as? String { o.bezeichnung = v }
            if let v = f["anbieter"] as? String { o.anbieter = v }
            if let v = dezArg(f["brutto"]) { o.brutto = v }
            if let v: Steuerart = enumWert(f["steuerart"]) { o.steuerart = v }
            if let v = dezArg(f["vst"]) { o.vst = v }
            if let v = f["betrieblich"] as? Bool { o.betrieblich = v }
            if let v = f["umlagefaehig"] as? Bool { o.umlagefaehig = v }
        case "fixkosten", "subscriptions", "subscription", "fixkosten_eintrag":
            let o = try modell(ExpenseEntry.self, id: id, ctx)
            if let v = datum(f["datum"]) { o.datum = v }
            if let v = f["bezeichnung"] as? String { o.bezeichnung = v }
            if let v = f["anbieter"] as? String { o.anbieter = v }
            if let v = dezArg(f["betrag"]) ?? dezArg(f["betragBrutto"]) ?? dezArg(f["brutto"]) { o.brutto = v }
            if let v: Steuerart = enumWert(f["steuerart"]) { o.steuerart = v }
            if let v = dezArg(f["vst"]) { o.vst = v }
            if let v = f["betrieblich"] as? Bool { o.betrieblich = v }
            if let v = f["umlagefaehig"] as? Bool { o.umlagefaehig = v }
            if let v = f["art"] as? String, let a = AusgabeArt(rawValue: v) { o.art = a }
        case "vorlagen", "vorlage":
            let o = try modell(Vorlage.self, id: id, ctx)
            if let v = f["bezeichnung"] as? String { o.bezeichnung = v }
            if let v = f["anbieter"] as? String { o.anbieter = v }
            if let v = dezArg(f["betrag"]) ?? dezArg(f["betragBrutto"]) ?? dezArg(f["brutto"]) { o.betragBrutto = v }
            if let v: Steuerart = enumWert(f["steuerart"]) { o.steuerart = v }
            if let v = f["betrieblich"] as? Bool { o.betrieblich = v }
            if let v = f["art"] as? String, let a = AusgabeArt(rawValue: v) { o.art = a }
            if let v = f["umlagefaehig"] as? Bool { o.umlagefaehig = v }
        case "zahlungen", "zahlung":
            let o = try modell(TaxPayment.self, id: id, ctx)
            if let v: SteuerKind = enumWert(f["kind"]) { o.kind = v }
            if let v = intArg(f["jahr"]) { o.jahr = v }
            if let v = datum(f["faellig"]) { o.faellig = v }
            if let v = dezArg(f["betrag"]) { o.betrag = v }
            if let v = f["bezahlt"] as? Bool { o.bezahlt = v }
            if let v = try datumFeld(f, "bezahltAm") { o.bezahltAm = v }
            if let v = f["bemerkung"] as? String { o.bemerkung = v }
        case "aufgaben", "aufgabe":
            let o = try modell(MonthlyTask.self, id: id, ctx)
            if let v = f["titel"] as? String { o.titel = v }
            if let v = datum(f["monat"] ?? f["faellig"]) { o.monat = v }
            if let v = f["erledigt"] as? Bool { o.erledigt = v }
            if let v: TaskIntervall = enumWert(f["intervall"]) { o.intervall = v }
            if let v = intArg(f["faelligTag"]) { o.faelligTag = v }
            if let v = (f["quartalsMonate"] as? [Any])?.compactMap({ intArg($0) }) { o.quartalsMonate = v }
        case "lebensmittel":
            let o = try modell(GroceryEntry.self, id: id, ctx)
            if let v = datum(f["datum"]) { o.datum = v }
            if let v = dezArg(f["betrag"]) { o.betrag = v }
            if let v = f["ort"] as? String { o.ort = v }
        case "einkaeufe", "einkauf", "anschaffungen", "anschaffung":
            let o = try modell(PurchaseEntry.self, id: id, ctx)
            if let v = datum(f["datum"]) { o.datum = v }
            if let v = f["bezeichnung"] as? String { o.bezeichnung = v }
            if let v = dezArg(f["preis"]) { o.preis = v }
        default:
            throw MCPFehler("Unbekannter typ '\(typ)' für kontor_aktualisieren.")
        }
        try ctx.save()
        return "Aktualisiert (\(typ))."
    }

    @MainActor
    static func loeschen(_ a: [String: Any], _ ctx: ModelContext) throws -> String {
        let typ = (a["typ"] as? String ?? "").lowercased()
        guard let id = a["id"] as? String, !id.isEmpty else { throw MCPFehler("'id' fehlt (aus kontor_liste mit mit_id=true).") }
        try KISicherung.sichereVorSchreibzugriff(ctx)
        switch typ {
        case "einnahmen", "einnahme":                          ctx.delete(try modell(Income.self, id: id, ctx))
        case "ausgaben", "ausgabe",
             "fixkosten", "subscriptions", "subscription", "fixkosten_eintrag":
                                                               ctx.delete(try modell(ExpenseEntry.self, id: id, ctx))
        case "vorlagen", "vorlage":                            ctx.delete(try modell(Vorlage.self, id: id, ctx))
        case "zahlungen", "zahlung":                           ctx.delete(try modell(TaxPayment.self, id: id, ctx))
        case "aufgaben", "aufgabe":                            ctx.delete(try modell(MonthlyTask.self, id: id, ctx))
        case "lebensmittel":                                   ctx.delete(try modell(GroceryEntry.self, id: id, ctx))
        case "einkaeufe", "einkauf", "anschaffungen", "anschaffung": ctx.delete(try modell(PurchaseEntry.self, id: id, ctx))
        default: throw MCPFehler("Unbekannter typ '\(typ)' für kontor_loeschen.")
        }
        try ctx.save()
        return "Gelöscht (\(typ))."
    }

    // MARK: - Beleg anhängen (PDF/Bild)

    /// Hängt eine Base64-Datei als Beleg an einen Datensatz (einnahmen|ausgaben|einkaeufe) und
    /// setzt dessen `belegPfad`. Mit `entfernen=true` wird der Verweis nur gelöst. Das Jahr für
    /// die Ablage ergibt sich aus dem Datum des Datensatzes.
    @MainActor
    static func beleg(_ a: [String: Any], _ ctx: ModelContext) throws -> String {
        let typ = (a["typ"] as? String ?? "").lowercased()
        guard let id = a["id"] as? String, !id.isEmpty else { throw MCPFehler("'id' fehlt (aus kontor_liste mit mit_id=true).") }
        let entfernen = a["entfernen"] as? Bool ?? false

        let jahr: Int
        let aktuellerPfad: String?
        let setze: (String?) -> Void
        switch typ {
        case "einnahmen", "einnahme":
            let o = try modell(Income.self, id: id, ctx)
            jahr = appKalender.component(.year, from: o.rechnungsdatum)
            aktuellerPfad = o.belegPfad; setze = { o.belegPfad = $0 }
        case "ausgaben", "ausgabe":
            let o = try modell(ExpenseEntry.self, id: id, ctx)
            jahr = appKalender.component(.year, from: o.datum)
            aktuellerPfad = o.belegPfad; setze = { o.belegPfad = $0 }
        case "einkaeufe", "einkauf", "anschaffungen", "anschaffung":
            let o = try modell(PurchaseEntry.self, id: id, ctx)
            jahr = appKalender.component(.year, from: o.datum)
            aktuellerPfad = o.belegPfad; setze = { o.belegPfad = $0 }
        default:
            throw MCPFehler("typ '\(typ)' führt keinen Beleg. Erlaubt: einnahmen | ausgaben | einkaeufe.")
        }

        try KISicherung.sichereVorSchreibzugriff(ctx)

        if entfernen {
            setze(nil)
            try ctx.save()
            return "Beleg-Verweis entfernt (\(typ))."
        }

        guard let b64 = a["inhalt_base64"] as? String, !b64.isEmpty else {
            throw MCPFehler("'inhalt_base64' fehlt (Base64 des Dateiinhalts) – oder entfernen=true setzen.")
        }
        guard let daten = Data(base64Encoded: b64, options: .ignoreUnknownCharacters), !daten.isEmpty else {
            throw MCPFehler("'inhalt_base64' ist kein gültiges Base64.")
        }
        let name = (a["dateiname"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "beleg.pdf"
        let pfad = try Belege.speichere(daten: daten, dateiname: name, jahr: jahr)
        setze(pfad)
        try ctx.save()
        let ersetzt = (aktuellerPfad?.isEmpty == false) ? " (ersetzt \(aktuellerPfad!))" : ""
        return "Beleg angehängt (\(typ)): \(pfad) [\(daten.count) Bytes]\(ersetzt)"
    }

    // MARK: - Daten laden

    @MainActor private static func alle<T: PersistentModel>(_ t: T.Type, _ ctx: ModelContext) -> [T] {
        (try? ctx.fetch(FetchDescriptor<T>())) ?? []
    }
    @MainActor private static func einnahmenPosten(_ ctx: ModelContext) -> [EinnahmePosten] { alle(Income.self, ctx).flatMap(\.postenListe) }
    @MainActor private static func ausgabenPosten(_ ctx: ModelContext) -> [AusgabePosten] { alle(ExpenseEntry.self, ctx).map(\.posten) }

    @MainActor private static func naechsteFrist(_ ctx: ModelContext) -> TaxPayment? {
        let heute = appKalender.startOfDay(for: Date())
        return alle(TaxPayment.self, ctx).filter { !$0.bezahlt && $0.faellig >= heute }.min { $0.faellig < $1.faellig }
    }

    // MARK: - Formatierung & Parsing

    // `var`, nicht `let`: Ein `static let` wird einmal beim ersten Zugriff ausgewertet und
    // bleibt dann für die **gesamte Prozesslaufzeit** eingefroren. Kontor läuft als
    // Desktop-App wochenlang durch – über den Jahreswechsel hätte der MCP still weiter die
    // Zahlen des Vorjahres geliefert (Default-Jahr von kontor_uebersicht, Quartals-Default
    // von kontor_ustva, Monats-Default der KSK-Liste).
    private static var heuteJahr: Int { appKalender.component(.year, from: Date()) }
    private static var heuteMonat: Int { appKalender.component(.month, from: Date()) }

    private static let mcpTag: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.calendar = appKalender; f.timeZone = appKalender.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static func tagText(_ d: Date) -> String { mcpTag.string(from: d) }

    /// Decimal mit fester 2-Stellen-Punkt-Notation (maschinen-/tokenfreundlich).
    private static func g(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d.gerundet(2))
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2; f.usesGroupingSeparator = false
        return f.string(from: n) ?? "\(d)"
    }

    /// Ein CSV-Feld maskieren (RFC-4180-Stil: in `"…"`, inneres `"` verdoppelt).
    ///
    /// Pflicht, nicht Kosmetik: Freitextfelder (Bezeichnung, Kunde, Anbieter, Ort, Bemerkung,
    /// Titel) dürfen `;` und Zeilenumbrüche enthalten. Roh gejoint verschöben die sich die
    /// Spalten – und da die `id` in der **letzten** Spalte steht und die KI sie in
    /// `kontor_aktualisieren`/`kontor_loeschen` zurückspeist, griffe sie danach die **falsche
    /// id** und änderte oder löschte den falschen Datensatz. Eine Ausgabe namens
    /// „Miete; Nebenkosten" genügt dafür.
    private static func csvFeld(_ s: String) -> String {
        guard s.contains(";") || s.contains("\"") || s.contains("\n") || s.contains("\r") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func csv(_ kopf: [String], _ zeilen: [[String]]) -> String {
        ([kopf.map(csvFeld).joined(separator: ";")]
            + zeilen.map { $0.map(csvFeld).joined(separator: ";") }).joined(separator: "\n")
    }

    private static func intArg(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }
    private static func dezArg(_ v: Any?) -> Decimal? {
        if let s = v as? String { return Decimal(string: s.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) }
        if let n = v as? NSNumber { return Decimal(string: n.stringValue, locale: Locale(identifier: "en_US_POSIX")) }
        return nil
    }
    private static func pflichtInt(_ a: [String: Any], _ schluessel: String) throws -> Int {
        guard let i = intArg(a[schluessel]) else { throw MCPFehler("Pflichtfeld '\(schluessel)' fehlt oder ist keine Zahl.") }
        return i
    }

    /// Pflicht-Int mit Bereichsprüfung – für Jahr/Monat/Quartal.
    ///
    /// Ohne Prüfung landeten diese Werte ungefiltert in `Periode.monat`/`Periode.quartal` und
    /// damit in `tag()`. Beides ist nachsichtig: `quartal: 0` normalisiert still auf Oktober des
    /// **Vorjahres**, `monat: 13` auf Januar des Folgejahres – der Client bekäme also klaglos die
    /// Zahlen einer ganz anderen Periode. Bei extremen Jahreszahlen liefert `Calendar.date(from:)`
    /// dagegen `nil` und der Force-Unwrap in `tag()` reißt die App runter.
    private static func pflichtInt(_ a: [String: Any], _ schluessel: String, bereich: ClosedRange<Int>) throws -> Int {
        let i = try pflichtInt(a, schluessel)
        guard bereich.contains(i) else {
            throw MCPFehler("'\(schluessel)' muss zwischen \(bereich.lowerBound) und \(bereich.upperBound) liegen (war \(i)).")
        }
        return i
    }

    /// Optionaler Int mit Bereichsprüfung (nil bleibt nil, Unsinn wirft).
    private static func intArg(_ a: [String: Any], _ schluessel: String, bereich: ClosedRange<Int>) throws -> Int? {
        guard a[schluessel] != nil else { return nil }
        return try pflichtInt(a, schluessel, bereich: bereich)
    }

    /// Plausible Jahre. Großzügig genug für Altbestand und Vorausplanung, eng genug, dass
    /// `Calendar` nicht aussteigt.
    static let jahrBereich = 1990...2200
    /// „2026-06-25" → lokale Mitternacht. **Streng**: ein unmögliches Datum wird abgewiesen,
    /// nicht weitergerollt.
    ///
    /// `DateFormatter` half hier nicht: Auch mit `isLenient == false` prüft er nur das *Format*,
    /// nicht die Kalender-Gültigkeit – „2026-06-31" ergab klaglos den 01.07.2026 und
    /// „2025-02-29" den 01.03.2025. Unter Soll-Versteuerung verschiebt das die Rechnung in ein
    /// anderes Quartal: KZ 81 im einen zu niedrig, im anderen zu hoch – zwei falsche UStVAs aus
    /// einem Tippfehler. Derselbe Pfad trägt `ExpenseEntry.datum` (Vorsteuer-Periode) und
    /// `TaxPayment.faellig`.
    ///
    /// Beim Format bleibt es tolerant (`2026-6-5` ist in Ordnung), bei der Gültigkeit nicht.
    private static func datum(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let teile = s.split(separator: "-")
        guard teile.count == 3, teile[0].count == 4,
              let j = Int(teile[0]), let m = Int(teile[1]), let t = Int(teile[2]) else { return nil }
        let komponenten = DateComponents(year: j, month: m, day: t)
        guard komponenten.isValidDate(in: appKalender) else { return nil }
        return appKalender.date(from: komponenten)
    }

    /// Optionales Datumsfeld aus `felder` lesen.
    ///
    /// Unterscheidet drei Fälle, die vorher alle in `nil` mündeten:
    /// - Feld **nicht übergeben** → `.none` (nichts ändern)
    /// - Feld ist **`null`** → `.some(nil)` (bewusst leeren)
    /// - Feld ist ein **unparsbarer String** → Fehler
    ///
    /// Vorher war `o.zahlungsdatum = datum(f["zahlungsdatum"])` gegen alles blind: Ein
    /// Datums-Tippfehler **löschte das Feld** – und das Tool meldete trotzdem „Aktualisiert".
    /// Verlor eine bezahlte Rechnung so ihr `zahlungsdatum`, fiel sie aus der EÜR
    /// (Zuflussprinzip) – ohne dass Client oder Nutzer etwas bemerkten.
    private static func datumFeld(_ f: [String: Any], _ schluessel: String) throws -> Date?? {
        guard let roh = f[schluessel] else { return .none }
        if roh is NSNull { return .some(nil) }
        guard let d = datum(roh) else {
            throw MCPFehler("'\(schluessel)' ist kein gültiges Datum (erwartet YYYY-MM-DD, war: \(roh)).")
        }
        return .some(d)
    }
    private static func enumWert<E: RawRepresentable>(_ v: Any?) -> E? where E.RawValue == String {
        guard let s = v as? String else { return nil }
        return E(rawValue: s)
    }
    private static func fehlt(_ typ: String, _ felder: String) -> MCPFehler {
        MCPFehler("\(typ): Pflichtfelder fehlen oder sind ungültig (\(felder)).")
    }

    // MARK: - Stabile id (für Aktualisieren/Löschen)

    /// Opaker, über kontor_liste (mit_id=true) ausgegebener Schlüssel = base64(JSON(PersistentIdentifier)).
    private static func idText(_ m: any PersistentModel) -> String {
        (try? JSONEncoder().encode(m.persistentModelID))?.base64EncodedString() ?? ""
    }
    private static func modell<T: PersistentModel>(_ t: T.Type, id: String, _ ctx: ModelContext) throws -> T {
        guard let data = Data(base64Encoded: id),
              let pid = try? JSONDecoder().decode(PersistentIdentifier.self, from: data) else {
            throw MCPFehler("Ungültige id – bitte aus kontor_liste (mit_id=true) übernehmen.")
        }
        // Über einen Fetch statt `ctx.model(for:)`: Letzteres **trappt** bei einem unbekannten
        // oder veralteten PersistentIdentifier (gelöschter Datensatz, id eines anderen Typs),
        // statt nil zu liefern – eine zurückgespeiste alte id hätte die App also abgeschossen,
        // statt einen sauberen Fehler an den Client zu geben.
        let treffer = (try? ctx.fetch(FetchDescriptor<T>()))?.first { $0.persistentModelID == pid }
        guard let obj = treffer else {
            throw MCPFehler("Kein Datensatz dieses typs mit dieser id gefunden (evtl. gelöscht?).")
        }
        return obj
    }

    // MARK: - Schema-Bausteine

    private static func obj(props: [String: Any], required: [String] = []) -> [String: Any] {
        var s: [String: Any] = ["type": "object", "properties": props]
        if !required.isEmpty { s["required"] = required }
        return s
    }
    private static func zahl(_ d: String) -> [String: Any] { ["type": "number", "description": d] }
    private static func text(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func flag(_ d: String) -> [String: Any] { ["type": "boolean", "description": d] }
    private static func freiObj(_ d: String) -> [String: Any] { ["type": "object", "description": d, "additionalProperties": true] }
}

#endif
