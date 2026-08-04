import Foundation
import SwiftData

/// Vom Nutzer gewählte (oder vorgeschlagene) Zuordnung einer Bankzeile.
struct Zuordnung: Hashable {
    var kategorie: ImportKategorie
    var betrieblich: Bool
    var steuerart: Steuerart = .inland19
    /// Nur für `.steuer` relevant: Art der Steuerzahlung (USt-VZ/ESt-VZ/…).
    var steuerKind: SteuerKind = .ustVz

    /// Erzwingt die Invariante „keine private Betriebsausgabe/Einnahme": bei diesen Kategorien ist
    /// `betrieblich` immer true – egal, was Vorschlag, gelernte Regel oder ein stehengebliebener
    /// UI-Zustand gesetzt haben. (Beim Kategoriewechsel in der Triage bleibt `betrieblich` sonst auf
    /// dem alten Default `false` und die Ausgabe landet fälschlich privat, ohne VSt, ohne EÜR.)
    var normalisiert: Zuordnung {
        guard kategorie.immerBetrieblich, !betrieblich else { return self }
        var z = self
        z.betrieblich = true
        return z
    }
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
            return Zuordnung(
                kategorie: kat, betrieblich: r.betrieblich,
                steuerart: r.steuerart, steuerKind: r.steuerKind ?? .ustVz
            ).normalisiert
        }
        if istEigenerUebertrag(b) { return Zuordnung(kategorie: .ignorieren, betrieblich: false) }
        if b.istEingang { return Zuordnung(kategorie: .einnahme, betrieblich: true) }
        return Zuordnung(kategorie: .anschaffung, betrieblich: false)  // sicherste Annahme: privat
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

    /// Ein vorgeschlagener Zuordnungs-Treffer samt Begründung – die UI zeigt bis zu drei davon
    /// zur Auswahl, statt still den erstbesten zu nehmen.
    struct Kandidat: Identifiable {
        var id: PersistentIdentifier
        var titel: String
        var detail: String
        var punkte: Int
        var begruendung: String
    }

    /// Vorhandener Datensatz, der zur Bankzeile+Kategorie passt (für „überschreiben/überspringen"
    /// bzw. Einnahmen-Match). Nil ⇒ es würde neu angelegt.
    @MainActor
    static func ziel(_ b: Bankbuchung, _ z: Zuordnung, _ ctx: ModelContext) -> PersistentIdentifier? {
        kandidaten(b, z, ctx, maximal: 1).first?.id
    }

    /// Die besten passenden Datensätze, absteigend nach Punkten (siehe `Treffersuche`).
    @MainActor
    static func kandidaten(
        _ b: Bankbuchung, _ z: Zuordnung, _ ctx: ModelContext, maximal: Int = 3
    ) -> [Kandidat] {
        let betrag = abs(b.betrag)
        let fremd = b.fremdbetragHinweis
        let suchbild = Treffersuchbild(
            betrag: betrag, datum: b.buchungstag,
            name: b.gegenpartei.isEmpty ? b.anzeigename : b.gegenpartei,
            text: b.verwendungszweck,
            fremdBetrag: fremd?.betrag ?? 0, fremdwaehrung: fremd?.code)

        func datumText(_ d: Date) -> String { d.formatted(date: .numeric, time: .omitted) }

        switch z.kategorie {
        case .einnahme:
            // Weites Fenster: die Zahlung kommt Wochen nach dem Rechnungsdatum. Offene
            // Rechnungen werden bevorzugt, bezahlte bleiben aber wählbar – sonst fände eine
            // erneut zugeordnete Bankzeile ihre eigene Buchung nicht wieder und legte daneben
            // eine zweite an (derselbe Fehler, den der Steuer-Zweig schon einmal hatte).
            return Treffersuche.beste(
                (try? ctx.fetch(FetchDescriptor<Income>())) ?? [], gegen: suchbild,
                fensterTage: 60, maximal: maximal
            ) { inc in
                Trefferkandidat(
                    betrag: inc.brutto, datum: inc.rechnungsdatum, name: inc.kunde,
                    nummer: inc.rechnungsnummer,
                    bonus: inc.status == .bezahlt ? 0 : 10,
                    bonusGrund: inc.status == .bezahlt ? nil : "offen")
            }.map { treffer, bewertung in
                Kandidat(
                    id: treffer.persistentModelID,
                    titel: treffer.kunde.isEmpty ? "Rechnung" : treffer.kunde,
                    detail: "\(datumText(treffer.rechnungsdatum)) · \(treffer.brutto.euro)",
                    punkte: bewertung.punkte, begruendung: bewertung.begruendung)
            }
        case .lebensmittel:
            return Treffersuche.beste(
                (try? ctx.fetch(FetchDescriptor<GroceryEntry>())) ?? [], gegen: suchbild, maximal: maximal
            ) { g in
                Trefferkandidat(betrag: g.betrag, datum: g.datum, name: g.ort, nummer: nil)
            }.map { treffer, bewertung in
                Kandidat(
                    id: treffer.persistentModelID, titel: treffer.ort,
                    detail: "\(datumText(treffer.datum)) · \(treffer.betrag.euro)",
                    punkte: bewertung.punkte, begruendung: bewertung.begruendung)
            }
        case .anschaffung, .erstattung:
            // Gutschrift = negative Anschaffung; dann über den negierten Preis matchen (Re-Buchung).
            let negiert = z.kategorie == .erstattung
            return Treffersuche.beste(
                (try? ctx.fetch(FetchDescriptor<PurchaseEntry>())) ?? [], gegen: suchbild, maximal: maximal
            ) { p in
                Trefferkandidat(
                    betrag: negiert ? -p.preis : p.preis, datum: p.datum,
                    name: p.bezeichnung, nummer: nil)
            }.map { treffer, bewertung in
                Kandidat(
                    id: treffer.persistentModelID, titel: treffer.bezeichnung,
                    detail: "\(datumText(treffer.datum)) · \(treffer.preis.euro)",
                    punkte: bewertung.punkte, begruendung: bewertung.begruendung)
            }
        case .betriebsausgabe, .fixkosten, .subscription:
            // Enges Datumsfenster, außer die Rechnungsnummer trifft: wiederkehrende Kosten
            // (Miete, Subscriptions) haben monatlich denselben Betrag ~30 Tage auseinander, ein
            // weites Fenster zöge den Vormonatseintrag in den neuen Monat. Vorab per PDF erfasste
            // Rechnungen werden stattdessen über die Rechnungsnummer erkannt.
            return Treffersuche.beste(
                (try? ctx.fetch(FetchDescriptor<ExpenseEntry>())) ?? [], gegen: suchbild, maximal: maximal
            ) { e in
                Trefferkandidat(
                    betrag: e.brutto, datum: e.datum,
                    name: e.anbieter.isEmpty ? e.bezeichnung : e.anbieter,
                    nummer: e.rechnungsnummer,
                    fremdBetrag: e.fremdBetrag, fremdwaehrung: e.fremdwaehrung)
            }.map { treffer, bewertung in
                Kandidat(
                    id: treffer.persistentModelID,
                    titel: treffer.bezeichnung.isEmpty ? treffer.anbieter : treffer.bezeichnung,
                    detail: "\(datumText(treffer.datum)) · \(treffer.brutto.euro)",
                    punkte: bewertung.punkte, begruendung: bewertung.begruendung)
            }
        case .steuer, .ksk, .steuererstattung, .ignorieren:
            guard let id = zahlungsziel(b, z, ctx) else { return [] }
            return [
                Kandidat(
                    id: id, titel: z.kategorie.bezeichnung,
                    detail: "\(datumText(b.buchungstag)) · \(betrag.euro)",
                    punkte: Treffersuche.punkteBetragExakt, begruendung: "vorhandene Zahlung")
            ]
        }
    }

    /// Zahlungs-Zweige (Steuer/KSK/Erstattung): eigene Logik über Steuerjahr und Fälligkeit,
    /// bewusst **nicht** im Namens-/Betrags-Scoring – hier zählt der geplante Termin.
    @MainActor
    private static func zahlungsziel(
        _ b: Bankbuchung, _ z: Zuordnung, _ ctx: ModelContext
    ) -> PersistentIdentifier? {
        let betrag = abs(b.betrag)
        switch z.kategorie {
        case .steuer:
            // Geplanter Termin gleicher Art (Betrag passt oder Termin noch ohne Betrag) – bei
            // mehreren der fälligkeitsnächste (z. B. das passende ESt-VZ-Quartal).
            //
            // Zwei Filter waren hier falsch und erzeugten beim erneuten Zuordnen Dubletten:
            //
            // 1. `!bezahlt` schloss den **selbst gebuchten** Datensatz aus – der Import setzt
            //    `bezahlt = true`. Beim „Neu zuordnen"/„Alle erneut zuordnen" derselben Bankzeile
            //    fand `ziel()` ihn deshalb nie wieder, die UI bot „Buchen" statt „Überschreiben",
            //    und es entstand eine zweite Zahlung: der Jahresabschluss zeigte unter
            //    „Tatsächlich gezahlt" den doppelten Betrag. (Der `.ksk`-Zweig unten hat diesen
            //    Filter nicht – dort trat der Fehler folgerichtig nie auf.)
            //
            // 2. Das **Zahlungsjahr** als Filter passte nicht zu dem, was `anwenden()` schreibt:
            //    Eine USt-VZ im Januar gehört per `Steuer.ustVzZuordnung` ins **Vorjahr**, der
            //    geplante Termin trägt also `jahr = Vorjahr`. Gesucht wurde aber im Zahlungsjahr –
            //    der Termin blieb offen stehen und daneben entstand eine neue Zahlung.
            //    Deshalb: dasselbe Steuerjahr bestimmen wie beim Buchen.
            let zMonat = appKalender.component(.month, from: b.buchungstag)
            let zJahr = appKalender.component(.year, from: b.buchungstag)
            let steuerjahr = steuerjahrFuer(kind: z.steuerKind, zahlMonat: zMonat, zahlJahr: zJahr, ctx)
            let kandidaten = ((try? ctx.fetch(FetchDescriptor<TaxPayment>())) ?? []).filter {
                $0.kind == z.steuerKind && $0.jahr == steuerjahr
                    && ($0.betrag == betrag || $0.betrag == 0)
            }
            return kandidaten.min {
                abs($0.faellig.timeIntervalSince(b.buchungstag)) < abs($1.faellig.timeIntervalSince(b.buchungstag))
            }?.persistentModelID
        case .ksk:
            let zahlungen = ((try? ctx.fetch(FetchDescriptor<TaxPayment>())) ?? []).filter { $0.kind == .ksk }
            return nahestes(
                zahlungen, betrag, b.buchungstag,
                betragVon: { $0.betrag }, datumVon: { $0.bezahltAm ?? $0.faellig })
        case .steuererstattung:
            // Erstattungen liegen als negativer TaxPayment vor → über den Betrag matchen.
            let zahlungen = ((try? ctx.fetch(FetchDescriptor<TaxPayment>())) ?? [])
                .filter { $0.kind == z.steuerKind && $0.betrag < 0 }
            return nahestes(
                zahlungen, betrag, b.buchungstag,
                betragVon: { abs($0.betrag) }, datumVon: { $0.bezahltAm ?? $0.faellig })
        default:
            return nil  // alle übrigen Kategorien laufen über das Scoring in `kandidaten`
        }
    }

    /// Steuerjahr + Notiz einer Zahlung – **die** gemeinsame Quelle für `ziel()` (Suchen) und
    /// `anwenden()` (Schreiben).
    ///
    /// USt-VZ im Jan/Feb gilt fürs Vorjahr (Q4 bzw. Dez) – abhängig von Rhythmus &
    /// Dauerfristverlängerung **des Vorjahres** (beides pro Jahr in den `YearSettings`).
    /// Stand die Logik nur im Schreibpfad, suchte `ziel()` im Zahlungsjahr, während `anwenden()`
    /// ins Vorjahr schrieb: Der geplante Vorjahres-Termin wurde nie getroffen, blieb offen, und
    /// daneben entstand eine zweite Zahlung.
    @MainActor
    static func steuerzuordnung(
        kind: SteuerKind, zahlMonat: Int, zahlJahr: Int,
        _ ctx: ModelContext
    ) -> (jahr: Int, notiz: String) {
        guard kind == .ustVz else { return (jahr: zahlJahr, notiz: "") }
        let vorjahr = ((try? ctx.fetch(FetchDescriptor<YearSettings>())) ?? []).first { $0.jahr == zahlJahr - 1 }
        return Steuer.ustVzZuordnung(
            zahlMonat: zahlMonat, zahlJahr: zahlJahr,
            rhythmus: vorjahr?.ustvaRhythmus ?? .vierteljaehrlich,
            dauerfrist: vorjahr?.dauerfristverlaengerung ?? false)
    }

    @MainActor
    static func steuerjahrFuer(kind: SteuerKind, zahlMonat: Int, zahlJahr: Int, _ ctx: ModelContext) -> Int {
        steuerzuordnung(kind: kind, zahlMonat: zahlMonat, zahlJahr: zahlJahr, ctx).jahr
    }

    /// Führt die Zuordnung aus. Liefert eine kurze Ergebnis-Nachricht.
    @MainActor
    @discardableResult
    static func anwenden(_ b: Bankbuchung, _ zRoh: Zuordnung, aktion: Aktion, _ ctx: ModelContext) throws -> String {
        // Invariante erzwingen, bevor irgendetwas geschrieben oder gelernt wird: eine als
        // Betriebsausgabe/Einnahme klassifizierte Buchung ist immer betrieblich (sonst landet sie
        // privat, mit vst:0 und ohne EÜR-Wirkung – der klassische „private Betriebsausgabe"-Bug).
        let z = zRoh.normalisiert
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
                    g.datum = b.buchungstag
                    g.betrag = betrag
                    g.ort = name
                    nachricht = "Lebensmittel aktualisiert"
                } else {
                    ctx.insert(GroceryEntry(datum: b.buchungstag, betrag: betrag, ort: name))
                    nachricht = "Lebensmittel angelegt"
                }
            case .anschaffung:
                if let p: PurchaseEntry = hole(ziel, ctx) {
                    p.datum = b.buchungstag
                    p.preis = betrag
                    p.bezeichnung = name
                    nachricht = "Anschaffung aktualisiert"
                } else {
                    ctx.insert(PurchaseEntry(datum: b.buchungstag, bezeichnung: name, preis: betrag))
                    nachricht = "Anschaffung angelegt"
                }
            case .erstattung:
                // Gutschrift = negative Anschaffung → mindert die Einkäufe-Summe.
                if let p: PurchaseEntry = hole(ziel, ctx) {
                    p.datum = b.buchungstag
                    p.preis = -betrag
                    p.bezeichnung = "Erstattung: \(name)"
                    nachricht = "Gutschrift aktualisiert"
                } else {
                    ctx.insert(PurchaseEntry(datum: b.buchungstag, bezeichnung: "Erstattung: \(name)", preis: -betrag))
                    nachricht = "Gutschrift angelegt"
                }
            case .betriebsausgabe, .fixkosten, .subscription:
                // Art aus der Triage; privat zieht keine Vorsteuer (zählt nur in die Liquidität).
                let art: AusgabeArt =
                    z.kategorie == .fixkosten
                    ? .fixkosten
                    : z.kategorie == .subscription ? .subscription : .betriebsausgabe
                // **Vorzeichen aus der Bankrichtung.** Ein *Eingang* auf einer Ausgaben-Kategorie ist
                // eine Erstattung des Händlers (Storno, Gutschrift, Abo gekündigt) und muss die
                // Ausgabe **mindern**. Vorher machte `abs()` daraus eine zusätzliche Ausgabe: Die
                // Belastung und ihre Erstattung addierten sich, statt sich aufzuheben – der EÜR-Gewinn
                // sank um den doppelten Netto-Betrag, und KZ 66 zog die Vorsteuer zweimal statt gar
                // nicht. Das trifft genau die gelernten Regeln (auch die ausgelieferten Start-Regeln),
                // denn die ordnen den Händler ja der Ausgaben-Kategorie zu.
                let ausgabeBrutto = b.istEingang ? -betrag : betrag
                // `vorsteuerVorschlag` folgt dem Vorzeichen von selbst (−119 → −19), die Erstattung
                // mindert damit auch die Vorsteuer korrekt.
                let vst = z.betrieblich ? Steuer.vorsteuerVorschlag(brutto: ausgabeBrutto, steuerart: z.steuerart) : 0
                let titel = b.istEingang ? "Erstattung: \(name)" : name
                let fremd = b.fremdbetragHinweis
                if let e: ExpenseEntry = hole(ziel, ctx) {
                    // `datum` bleibt das EÜR-maßgebliche (Abfluss-)Datum = Buchungstag (wie bisher),
                    // `zahlungsdatum` hält den Zahltag zusätzlich fest; eine bereits erfasste
                    // Rechnungsnummer (OCR) wird nicht überschrieben.
                    e.datum = b.buchungstag
                    e.zahlungsdatum = b.buchungstag
                    // **Der Bankbetrag ist die Wahrheit.** Bei einer Fremdwährungsrechnung ersetzt er
                    // den vorläufig umgerechneten Wert: für die EÜR zählt der tatsächliche Abfluss
                    // inklusive Kursaufschlag und Auslandsentgelt. Währung und Originalbetrag bleiben
                    // stehen, sie beschreiben die Rechnung – der Kurs ergibt sich daraus neu.
                    e.brutto = ausgabeBrutto
                    e.vst = vst
                    e.steuerart = z.steuerart
                    // Einen aus der Rechnung gepflegten Titel nicht durch den Bank-Anzeigenamen
                    // ersetzen: wer den Beleg vorab erfasst hat, hat die bessere Bezeichnung.
                    let gepflegt = e.rechnungsnummer != nil || e.istFremdwaehrung
                    if !gepflegt || e.bezeichnung.isEmpty { e.bezeichnung = titel }
                    if !gepflegt || e.anbieter.isEmpty { e.anbieter = name }
                    e.betrieblich = z.betrieblich
                    e.art = art
                    if let fremd, !e.istFremdwaehrung {
                        e.fremdwaehrung = fremd.code
                        e.fremdBetrag = fremd.betrag
                    }
                    nachricht = e.istFremdwaehrung ? "Ausgabe aktualisiert (Kurs übernommen)" : "Ausgabe aktualisiert"
                } else {
                    ctx.insert(
                        ExpenseEntry(
                            datum: b.buchungstag, bezeichnung: titel, anbieter: name,
                            brutto: ausgabeBrutto,
                            vst: vst, steuerart: z.steuerart,
                            betrieblich: z.betrieblich, art: art, zahlungsdatum: b.buchungstag,
                            fremdwaehrung: fremd?.code, fremdBetrag: fremd?.betrag ?? 0))
                    nachricht = b.istEingang ? "Erstattung angelegt" : "Ausgabe angelegt"
                }
            case .einnahme:
                if let inc: Income = hole(ziel, ctx) {
                    inc.setze(status: .bezahlt)
                    inc.zahlungsdatum = b.buchungstag
                    nachricht = "Zahlung zugeordnet"
                } else {
                    nachricht = "keine passende Rechnung gefunden"
                }
            case .steuer:
                let zMonat = appKalender.component(.month, from: b.buchungstag)
                let zJahr = appKalender.component(.year, from: b.buchungstag)
                // Dieselbe Zuordnung, die `ziel()` zum Suchen nutzt – sonst schreibt der Import in
                // ein anderes Jahr, als er vorher gesucht hat, und der geplante Termin bleibt offen.
                let zo = steuerzuordnung(kind: z.steuerKind, zahlMonat: zMonat, zahlJahr: zJahr, ctx)
                if let t: TaxPayment = hole(ziel, ctx) {
                    t.kind = z.steuerKind
                    t.betrag = betrag
                    t.bezahlt = true
                    t.bezahltAm = b.buchungstag
                    t.jahr = zo.jahr
                    if !zo.notiz.isEmpty, t.bemerkung.isEmpty { t.bemerkung = zo.notiz }
                    nachricht = "Steuerzahlung zugeordnet"
                } else {
                    ctx.insert(
                        TaxPayment(
                            kind: z.steuerKind, jahr: zo.jahr, faellig: b.buchungstag, betrag: betrag,
                            bezahlt: true, bezahltAm: b.buchungstag, bemerkung: zo.notiz))
                    nachricht = "Steuerzahlung angelegt"
                }
            case .steuererstattung:
                // Eingang vom Finanzamt = Erstattung → negativer Betrag (mindert die Steuersumme).
                let zJahr = appKalender.component(.year, from: b.buchungstag)
                if let t: TaxPayment = hole(ziel, ctx) {
                    t.kind = z.steuerKind
                    t.betrag = -betrag
                    t.bezahlt = true
                    t.bezahltAm = b.buchungstag
                    t.jahr = zJahr
                    if t.bemerkung.isEmpty { t.bemerkung = "Erstattung" }
                    nachricht = "Steuererstattung zugeordnet"
                } else {
                    ctx.insert(
                        TaxPayment(
                            kind: z.steuerKind, jahr: zJahr, faellig: b.buchungstag, betrag: -betrag,
                            bezahlt: true, bezahltAm: b.buchungstag, bemerkung: "Erstattung"))
                    nachricht = "Steuererstattung angelegt"
                }
            case .ksk:
                // KSK-Abbuchung als Ist-Zahlung buchen (Betrag = Beleg); Soll bleibt der Beitragssatz.
                let zJahr = appKalender.component(.year, from: b.buchungstag)
                if let t: TaxPayment = hole(ziel, ctx) {
                    t.kind = .ksk
                    t.betrag = betrag
                    t.bezahlt = true
                    t.bezahltAm = b.buchungstag
                    t.jahr = zJahr
                    nachricht = "KSK-Zahlung zugeordnet"
                } else {
                    ctx.insert(
                        TaxPayment(
                            kind: .ksk, jahr: zJahr, faellig: b.buchungstag, betrag: betrag,
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
            r.kategorie = z.kategorie
            r.betrieblich = z.betrieblich
            r.steuerart = z.steuerart
            r.steuerKind = z.steuerKind
            r.aktualisiert = Date()
        } else {
            ctx.insert(
                ZuordnungsRegel(
                    schluessel: key, kategorie: z.kategorie, betrieblich: z.betrieblich,
                    steuerart: z.steuerart, steuerKind: z.steuerKind))
        }
    }

    @MainActor
    private static func protokolliere(_ b: Bankbuchung, _ z: Zuordnung, _ ctx: ModelContext) {
        let key = b.dedupSchluessel
        if let p = ((try? ctx.fetch(FetchDescriptor<ImportBuchung>())) ?? []).first(where: { $0.schluessel == key }) {
            p.kategorie = z.kategorie
            p.betrieblich = z.betrieblich
        } else {
            ctx.insert(
                ImportBuchung(
                    schluessel: key, buchungstag: b.buchungstag, betrag: b.betrag,
                    gegenpartei: b.gegenpartei, kategorie: z.kategorie, betrieblich: z.betrieblich))
        }
    }

    @MainActor
    private static func hole<T: PersistentModel>(_ pid: PersistentIdentifier?, _ ctx: ModelContext) -> T? {
        guard let pid else { return nil }
        return ctx.model(for: pid) as? T
    }

    /// Bestehender Datensatz mit gleichem Betrag und **geringstem** Datumsabstand innerhalb der
    /// Toleranz. Bewusst eng (Default 5 Tage): ein falsches „Überschreiben" zerstört eine echte
    /// Buchung aus einer anderen Periode, ein falsches „kein Treffer" legt nur eine löschbare
    /// Dublette an – die Asymmetrie spricht für konservatives Matching (vgl. Miete/Subscriptions,
    /// die sich monatlich mit gleichem Betrag ~30 Tage auseinander wiederholen).
    private static func nahestes<T: PersistentModel>(
        _ liste: [T], _ betrag: Decimal, _ datum: Date, toleranzTage: Int = 5,
        betragVon: (T) -> Decimal, datumVon: (T) -> Date
    ) -> PersistentIdentifier? {
        liste
            .filter {
                betragVon($0) == betrag
                    && abs(datumVon($0).timeIntervalSince(datum)) <= Double(toleranzTage) * 86_400
            }
            .min { abs(datumVon($0).timeIntervalSince(datum)) < abs(datumVon($1).timeIntervalSince(datum)) }?
            .persistentModelID
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
    static let startRegeln:
        [(schluessel: String, kategorie: ImportKategorie, betrieblich: Bool, steuerart: Steuerart)] = [
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
            ctx.insert(
                ZuordnungsRegel(
                    schluessel: r.schluessel, kategorie: r.kategorie,
                    betrieblich: r.betrieblich, steuerart: r.steuerart))
            aenderungen += 1
        }
        if aenderungen > 0 { try? ctx.save() }
    }
}
