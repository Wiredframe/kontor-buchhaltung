import Foundation
import SwiftData

/// Vom Nutzer gewählte (oder vorgeschlagene) Zuordnung einer Bankzeile.
struct Zuordnung: Hashable {
    var kategorie: ImportKategorie
    var betrieblich: Bool
    var steuerart: Steuerart = .inland19
    /// Nur für `.steuer` relevant: Art der Steuerzahlung (USt-VZ/ESt-VZ/…).
    var steuerKind: SteuerKind = .ustVz
}

/// Schlägt aus gelernten Regeln + einfachen Heuristiken eine Zuordnung vor (rein/testbar).
enum ImportVorschlag {
    static func fuer(_ b: Bankbuchung, regeln: [ZuordnungsRegel]) -> Zuordnung {
        if let r = regeln.first(where: { $0.schluessel == b.haendlerSchluessel }) {
            // Finanzamt-Regel deckt Zahlung UND Erstattung ab – die **Richtung** entscheidet,
            // unabhängig davon, welche der beiden zuletzt gelernt wurde (Ausgang = Zahlung,
            // Eingang = Erstattung). Sonst würde eine gelernte Erstattung künftige Zahlungen
            // fälschlich als Erstattung vorschlagen (und umgekehrt).
            let kat: ImportKategorie
            if r.kategorie == .steuer || r.kategorie == .steuererstattung {
                kat = b.istEingang ? .steuererstattung : .steuer
            } else {
                kat = r.kategorie
            }
            return Zuordnung(kategorie: kat, betrieblich: r.betrieblich,
                             steuerart: r.steuerart, steuerKind: r.steuerKind ?? .ustVz)
        }
        if istEigenerUebertrag(b) { return Zuordnung(kategorie: .ignorieren, betrieblich: false) }
        if b.istEingang          { return Zuordnung(kategorie: .einnahme, betrieblich: true) }
        return Zuordnung(kategorie: .anschaffung, betrieblich: false)   // sicherste Annahme: privat
    }

    /// Eigener Übertrag (Buchungstext „ÜBERTRAG…") → Vorschlag „ignorieren".
    static func istEigenerUebertrag(_ b: Bankbuchung) -> Bool {
        b.buchungstext.uppercased().contains("ÜBERTRAG")
    }
}

/// Wendet eine Zuordnung auf die Datenbank an: erzeugt/aktualisiert den passenden Datensatz
/// (bzw. hakt nur ab), merkt die Lern-Regel und protokolliert die Bankzeile (Idempotenz).
enum ImportAnwendung {
    enum Aktion { case neu, ueberschreiben(PersistentIdentifier), ueberspringen }

    /// Wurde diese Bankzeile früher schon verarbeitet? (→ „überspringen"-Default beim Re-Import)
    @MainActor
    static func schonVerarbeitet(_ b: Bankbuchung, _ ctx: ModelContext) -> Bool {
        let k = b.dedupSchluessel
        return ((try? ctx.fetch(FetchDescriptor<ImportBuchung>())) ?? []).contains { $0.schluessel == k }
    }

    /// Vorhandener Datensatz, der zur Bankzeile+Kategorie passt (für „überschreiben/überspringen"
    /// bzw. Einnahmen-Match). Nil ⇒ es würde neu angelegt.
    @MainActor
    static func ziel(_ b: Bankbuchung, _ z: Zuordnung, _ ctx: ModelContext) -> PersistentIdentifier? {
        let betrag = abs(b.betrag)
        switch z.kategorie {
        case .einnahme:
            let incs = (try? ctx.fetch(FetchDescriptor<Income>())) ?? []
            let zweckZiffern = b.verwendungszweck.filter(\.isNumber)
            if !zweckZiffern.isEmpty, let m = incs.first(where: { inc in
                guard let nr = inc.rechnungsnummer?.filter(\.isNumber), nr.count >= 4 else { return false }
                return zweckZiffern.contains(nr)
            }) { return m.persistentModelID }
            return incs.first { $0.brutto == betrag && $0.status != .bezahlt }?.persistentModelID
        case .lebensmittel:
            return nahestes((try? ctx.fetch(FetchDescriptor<GroceryEntry>())) ?? [], betrag, b.buchungstag,
                            betragVon: { $0.betrag }, datumVon: { $0.datum })
        case .anschaffung:
            return nahestes((try? ctx.fetch(FetchDescriptor<PurchaseEntry>())) ?? [], betrag, b.buchungstag,
                            betragVon: { $0.preis }, datumVon: { $0.datum })
        case .erstattung:
            // Gutschrift = negative Anschaffung; über den negierten Preis matchen (Re-Buchung).
            return nahestes((try? ctx.fetch(FetchDescriptor<PurchaseEntry>())) ?? [], betrag, b.buchungstag,
                            betragVon: { -$0.preis }, datumVon: { $0.datum })
        case .betriebsausgabe, .fixkosten, .subscription:
            return nahestes((try? ctx.fetch(FetchDescriptor<ExpenseEntry>())) ?? [], betrag, b.buchungstag,
                            betragVon: { $0.brutto }, datumVon: { $0.datum })
        case .steuer:
            // Offener, geplanter Termin gleicher Art im selben Jahr (Betrag passt oder Termin noch ohne
            // Betrag) – bei mehreren der fälligkeitsnächste (z. B. das passende ESt-VZ-Quartal).
            let jahrB = appKalender.component(.year, from: b.buchungstag)
            let kandidaten = ((try? ctx.fetch(FetchDescriptor<TaxPayment>())) ?? []).filter {
                $0.kind == z.steuerKind && $0.jahr == jahrB && !$0.bezahlt
                    && ($0.betrag == betrag || $0.betrag == 0)
            }
            return kandidaten.min {
                abs($0.faellig.timeIntervalSince(b.buchungstag)) < abs($1.faellig.timeIntervalSince(b.buchungstag))
            }?.persistentModelID
        case .ksk:
            let zahlungen = ((try? ctx.fetch(FetchDescriptor<TaxPayment>())) ?? []).filter { $0.kind == .ksk }
            return nahestes(zahlungen, betrag, b.buchungstag,
                            betragVon: { $0.betrag }, datumVon: { $0.bezahltAm ?? $0.faellig })
        case .steuererstattung:
            // Erstattungen liegen als negativer TaxPayment vor → über den Betrag matchen.
            let zahlungen = ((try? ctx.fetch(FetchDescriptor<TaxPayment>())) ?? [])
                .filter { $0.kind == z.steuerKind && $0.betrag < 0 }
            return nahestes(zahlungen, betrag, b.buchungstag,
                            betragVon: { abs($0.betrag) }, datumVon: { $0.bezahltAm ?? $0.faellig })
        case .ignorieren:
            return nil
        }
    }

    /// Führt die Zuordnung aus. Liefert eine kurze Ergebnis-Nachricht.
    @MainActor
    @discardableResult
    static func anwenden(_ b: Bankbuchung, _ z: Zuordnung, aktion: Aktion, _ ctx: ModelContext) throws -> String {
        protokolliere(b, z, ctx)
        // „Überspringen" heißt „später / nicht jetzt" – das ist keine Klassifizierung,
        // also daraus keine Regel lernen (nur aktives Buchen/Überschreiben lehrt).
        if case .ueberspringen = aktion {} else { merkeRegel(b, z, ctx) }

        var nachricht = "abgehakt"
        let betrag = abs(b.betrag)
        let name = b.anzeigename
        let ziel: PersistentIdentifier? = { if case .ueberschreiben(let p) = aktion { return p } else { return nil } }()

        if case .ueberspringen = aktion {
            // nur Protokoll + Lern-Regel, kein Datensatz
        } else if z.kategorie.bucht(betrieblich: z.betrieblich) {
            switch z.kategorie {
            case .lebensmittel:
                if let g: GroceryEntry = hole(ziel, ctx) {
                    g.datum = b.buchungstag; g.betrag = betrag; g.ort = name; nachricht = "Lebensmittel aktualisiert"
                } else {
                    ctx.insert(GroceryEntry(datum: b.buchungstag, betrag: betrag, ort: name)); nachricht = "Lebensmittel angelegt"
                }
            case .anschaffung:
                if let p: PurchaseEntry = hole(ziel, ctx) {
                    p.datum = b.buchungstag; p.preis = betrag; p.bezeichnung = name; nachricht = "Anschaffung aktualisiert"
                } else {
                    ctx.insert(PurchaseEntry(datum: b.buchungstag, bezeichnung: name, preis: betrag)); nachricht = "Anschaffung angelegt"
                }
            case .erstattung:
                // Gutschrift = negative Anschaffung → mindert die Einkäufe-Summe.
                if let p: PurchaseEntry = hole(ziel, ctx) {
                    p.datum = b.buchungstag; p.preis = -betrag; p.bezeichnung = "Erstattung: \(name)"; nachricht = "Gutschrift aktualisiert"
                } else {
                    ctx.insert(PurchaseEntry(datum: b.buchungstag, bezeichnung: "Erstattung: \(name)", preis: -betrag)); nachricht = "Gutschrift angelegt"
                }
            case .betriebsausgabe, .fixkosten, .subscription:
                // Art aus der Triage; privat zieht keine Vorsteuer (zählt nur in die Liquidität).
                let art: AusgabeArt = z.kategorie == .fixkosten ? .fixkosten
                                    : z.kategorie == .subscription ? .subscription : .betriebsausgabe
                let vst = z.betrieblich ? Steuer.vorsteuerVorschlag(brutto: betrag, steuerart: z.steuerart) : 0
                if let e: ExpenseEntry = hole(ziel, ctx) {
                    e.datum = b.buchungstag; e.brutto = betrag; e.vst = vst; e.steuerart = z.steuerart
                    e.bezeichnung = name; e.anbieter = name; e.betrieblich = z.betrieblich; e.art = art
                    nachricht = "Ausgabe aktualisiert"
                } else {
                    ctx.insert(ExpenseEntry(datum: b.buchungstag, bezeichnung: name, anbieter: name, brutto: betrag,
                                            vst: vst, steuerart: z.steuerart, kategorie: .laufend,
                                            betrieblich: z.betrieblich, art: art))
                    nachricht = "Ausgabe angelegt"
                }
            case .einnahme:
                if let inc: Income = hole(ziel, ctx) {
                    inc.setze(status: .bezahlt); inc.zahlungsdatum = b.buchungstag; nachricht = "Zahlung zugeordnet"
                } else {
                    nachricht = "keine passende Rechnung gefunden"
                }
            case .steuer:
                let zMonat = appKalender.component(.month, from: b.buchungstag)
                let zJahr = appKalender.component(.year, from: b.buchungstag)
                // USt-VZ im Jan/Feb gilt fürs Vorjahr (Q4 bzw. Dez) – abhängig von Rhythmus &
                // Dauerfristverlängerung des Vorjahres (beides pro Jahr in den YearSettings).
                let vorjahr = ((try? ctx.fetch(FetchDescriptor<YearSettings>())) ?? []).first { $0.jahr == zJahr - 1 }
                let zo = z.steuerKind == .ustVz
                    ? Steuer.ustVzZuordnung(zahlMonat: zMonat, zahlJahr: zJahr,
                                            rhythmus: vorjahr?.ustvaRhythmus ?? .vierteljaehrlich,
                                            dauerfrist: vorjahr?.dauerfristverlaengerung ?? false)
                    : (jahr: zJahr, notiz: "")
                if let t: TaxPayment = hole(ziel, ctx) {
                    t.kind = z.steuerKind; t.betrag = betrag; t.bezahlt = true; t.bezahltAm = b.buchungstag; t.jahr = zo.jahr
                    if !zo.notiz.isEmpty, t.bemerkung.isEmpty { t.bemerkung = zo.notiz }
                    nachricht = "Steuerzahlung zugeordnet"
                } else {
                    ctx.insert(TaxPayment(kind: z.steuerKind, jahr: zo.jahr, faellig: b.buchungstag, betrag: betrag,
                                          bezahlt: true, bezahltAm: b.buchungstag, bemerkung: zo.notiz))
                    nachricht = "Steuerzahlung angelegt"
                }
            case .steuererstattung:
                // Eingang vom Finanzamt = Erstattung → negativer Betrag (mindert die Steuersumme).
                let zJahr = appKalender.component(.year, from: b.buchungstag)
                if let t: TaxPayment = hole(ziel, ctx) {
                    t.kind = z.steuerKind; t.betrag = -betrag; t.bezahlt = true; t.bezahltAm = b.buchungstag; t.jahr = zJahr
                    if t.bemerkung.isEmpty { t.bemerkung = "Erstattung" }
                    nachricht = "Steuererstattung zugeordnet"
                } else {
                    ctx.insert(TaxPayment(kind: z.steuerKind, jahr: zJahr, faellig: b.buchungstag, betrag: -betrag,
                                          bezahlt: true, bezahltAm: b.buchungstag, bemerkung: "Erstattung"))
                    nachricht = "Steuererstattung angelegt"
                }
            case .ksk:
                // KSK-Abbuchung als Ist-Zahlung buchen (Betrag = Beleg); Soll bleibt der Beitragssatz.
                let zJahr = appKalender.component(.year, from: b.buchungstag)
                if let t: TaxPayment = hole(ziel, ctx) {
                    t.kind = .ksk; t.betrag = betrag; t.bezahlt = true; t.bezahltAm = b.buchungstag; t.jahr = zJahr
                    nachricht = "KSK-Zahlung zugeordnet"
                } else {
                    ctx.insert(TaxPayment(kind: .ksk, jahr: zJahr, faellig: b.buchungstag, betrag: betrag,
                                          bezahlt: true, bezahltAm: b.buchungstag, bemerkung: "KSK-Beitrag"))
                    nachricht = "KSK-Zahlung angelegt"
                }
            case .ignorieren:
                break
            }
        }
        try ctx.save()
        return nachricht
    }

    // MARK: - Intern

    @MainActor
    private static func merkeRegel(_ b: Bankbuchung, _ z: Zuordnung, _ ctx: ModelContext) {
        let key = b.haendlerSchluessel
        guard !key.isEmpty else { return }
        if let r = ((try? ctx.fetch(FetchDescriptor<ZuordnungsRegel>())) ?? []).first(where: { $0.schluessel == key }) {
            r.kategorie = z.kategorie; r.betrieblich = z.betrieblich
            r.steuerart = z.steuerart; r.steuerKind = z.steuerKind; r.aktualisiert = Date()
        } else {
            ctx.insert(ZuordnungsRegel(schluessel: key, kategorie: z.kategorie, betrieblich: z.betrieblich,
                                       steuerart: z.steuerart, steuerKind: z.steuerKind))
        }
    }

    @MainActor
    private static func protokolliere(_ b: Bankbuchung, _ z: Zuordnung, _ ctx: ModelContext) {
        let key = b.dedupSchluessel
        if let p = ((try? ctx.fetch(FetchDescriptor<ImportBuchung>())) ?? []).first(where: { $0.schluessel == key }) {
            p.kategorie = z.kategorie; p.betrieblich = z.betrieblich
        } else {
            ctx.insert(ImportBuchung(schluessel: key, buchungstag: b.buchungstag, betrag: b.betrag,
                                     gegenpartei: b.gegenpartei, kategorie: z.kategorie, betrieblich: z.betrieblich))
        }
    }

    @MainActor
    private static func hole<T: PersistentModel>(_ pid: PersistentIdentifier?, _ ctx: ModelContext) -> T? {
        guard let pid else { return nil }
        return ctx.model(for: pid) as? T
    }

    private static func nahestes<T: PersistentModel>(
        _ liste: [T], _ betrag: Decimal, _ datum: Date, toleranzTage: Int = 5,
        betragVon: (T) -> Decimal, datumVon: (T) -> Date) -> PersistentIdentifier? {
        liste.first {
            betragVon($0) == betrag && abs(datumVon($0).timeIntervalSince(datum)) <= Double(toleranzTage) * 86_400
        }?.persistentModelID
    }
}

// MARK: - Start-Regeln (generischer, nicht-personenbezogener Vorschlags-Starter)

extension ZuordnungsRegel {
    /// Kleiner, **nicht-personenbezogener** Vorschlags-Starter aus verbreiteten SaaS-/Design-
    /// Tools, die viele Freiberufler nutzen. Reine Startvorschläge – der Nutzer überschreibt sie
    /// jederzeit, und der Import **lernt mit jeder gebuchten Bewegung** eigene Regeln dazu
    /// (`ImportAnwendung.merkeRegel`, unabhängig von diesem Seed). Schlüssel =
    /// `Bankbuchung.haendlerSchluessel` (normalisierter Händlername; das Matching ist **exakt**,
    /// die Treffer sind also best effort – alles Übrige lernt der Import selbst).
    static let startRegeln: [(schluessel: String, kategorie: ImportKategorie, betrieblich: Bool, steuerart: Steuerart)] = [
        // Vorsorge: KSK-Beitrag → Zahlungen-Ledger (kein EÜR-Posten)
        ("kuenstlersozialkasse", .ksk, false, .inland19),
        // Verbreitete Auslands-SaaS (Design/Dev) → Betriebsausgabe, Reverse-Charge (§13b)
        ("figma", .betriebsausgabe, true, .reverseCharge),
        ("anthropic claude sub", .betriebsausgabe, true, .reverseCharge),
        ("anthropic", .betriebsausgabe, true, .reverseCharge),
        ("openai", .betriebsausgabe, true, .reverseCharge),
        ("github", .betriebsausgabe, true, .reverseCharge),
        ("github inc", .betriebsausgabe, true, .reverseCharge),
        ("vercel", .betriebsausgabe, true, .reverseCharge),
        ("notion labs", .betriebsausgabe, true, .reverseCharge),
        // SaaS mit deutscher USt → Betriebsausgabe, Inland 19 %
        ("adobe", .betriebsausgabe, true, .inland19),
    ]

    /// Legt fehlende Start-Regeln idempotent an (nur Schlüssel, die noch nicht existieren) –
    /// so bekommen auch bestehende Datenbanken die Vorschläge, ohne Nutzer-Regeln zu überschreiben.
    static func seedeStartRegeln(_ ctx: ModelContext) {
        let vorhandene = (try? ctx.fetch(FetchDescriptor<ZuordnungsRegel>())) ?? []
        let keys = Set(vorhandene.map(\.schluessel))
        var aenderungen = 0
        for r in startRegeln where !keys.contains(r.schluessel) {
            ctx.insert(ZuordnungsRegel(schluessel: r.schluessel, kategorie: r.kategorie,
                                       betrieblich: r.betrieblich, steuerart: r.steuerart))
            aenderungen += 1
        }
        if aenderungen > 0 { try? ctx.save() }
    }
}
