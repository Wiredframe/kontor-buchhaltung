import Foundation

// MARK: - Zahlen für die Jahreserklärungen
//
// Was in die USt-Jahreserklärung und die Anlage EÜR gehört, als reine Rechnung auf Posten.
// Vorbild ist wiredframe (`tax_engine.ust_annual`, `tax_engine.euer`, `exports/steuer.py`),
// dort am Übertragungsprotokoll einer echten Erklärung geprüft. Welche Zahl in welche Zeile
// welches Formulars gehört, ändert sich je Jahr – Kontor liefert die Größen, nicht die Zeilen.

/// Eine Steuerzahlung, wie die Erklärung sie sieht (aus `TaxPayment`).
struct SteuerzahlungPosten: Hashable {
    var kind: SteuerKind
    /// Steuerjahr, zu dem die Zahlung gehört.
    var jahr: Int
    var faellig: Date
    var betrag: Decimal
    var bezahlt: Bool
    var bezahltAm: Date?

    /// Tag des Abflusses; ohne Zahldatum die Fälligkeit.
    var zahltag: Date { bezahltAm ?? faellig }
}

extension TaxPayment {
    var posten: SteuerzahlungPosten {
        SteuerzahlungPosten(
            kind: kind, jahr: jahr, faellig: faellig, betrag: betrag, bezahlt: bezahlt, bezahltAm: bezahltAm)
    }
}

/// Umsatzsteuer-Jahreserklärung.
///
/// Die Bemessungsgrundlagen des **Jahres** werden auf volle Euro gekürzt und die Steuer daraus
/// gerechnet – auch bei §13b, anders als in der Voranmeldung, wo KZ 85 ein eigenes Cent-Feld ist.
/// Deshalb weicht die Summe der vier Voranmeldungen um Cent von der Jahressteuer ab; das ist
/// richtig so (wiredframe: am Übertragungsprotokoll 2025 geprüft).
struct UStJahreserklaerung: Hashable {
    var bemessung19: Decimal
    var ust19: Decimal
    var bemessung7: Decimal
    var ust7: Decimal
    /// Sonstige Leistungen an EU-Unternehmer (nicht steuerbar, nur Meldung).
    var euLeistungen: Decimal
    /// Übrige nicht steuerbare Umsätze (Drittland, nur Meldung).
    var drittland: Decimal
    /// §13b als Leistungsempfänger: Bemessung und Steuer (zugleich abziehbare Vorsteuer).
    var rcBemessung: Decimal
    var rcUSt: Decimal
    /// Vorsteuer aus Rechnungen anderer Unternehmer.
    var vorsteuer: Decimal
    /// Geleistete Vorauszahlungen für das Jahr (Σ bezahlter USt-Zahlungen mit diesem Steuerjahr).
    var vorauszahlungen: Decimal

    /// Verbleibende Umsatzsteuer des Jahres (§13b hebt sich auf).
    var steuer: Decimal { ust19 + ust7 + rcUSt - vorsteuer - rcUSt }
    /// Abschlusszahlung (positiv) bzw. Erstattung (negativ).
    var nochZuZahlen: Decimal { steuer - vorauszahlungen }
}

/// Anlage EÜR nach Zu- und Abfluss, **Bruttomethode**: vereinnahmte USt ist Betriebseinnahme,
/// gezahlte Vorsteuer und an das Finanzamt gezahlte USt sind Betriebsausgaben. Der Gewinn weicht
/// deshalb vom Netto-Gewinn der Jahresübersicht um den USt-Saldo des Jahres ab.
struct EUeRErklaerung: Hashable {
    var einnahmenNetto: Decimal
    /// USt der im Jahr bezahlten Rechnungen.
    var ustVereinnahmt: Decimal
    /// Vom Finanzamt erstattete USt (negative USt-Zahlungen), im Jahr des Zuflusses.
    var ustErstattet: Decimal
    /// Betriebsausgaben netto nach Abfluss, **ohne** AfA.
    var ausgabenNetto: Decimal
    var afa: Decimal
    /// Vorsteuer der im Jahr bezahlten betrieblichen Ausgaben.
    var vorsteuerGezahlt: Decimal
    /// An das Finanzamt gezahlte USt (Vorauszahlungen und Abschluss), Zehn-Tage-Regel beachtet.
    var ustGezahlt: Decimal

    var einnahmen: Decimal { einnahmenNetto + ustVereinnahmt + ustErstattet }
    var ausgaben: Decimal { ausgabenNetto + afa + vorsteuerGezahlt + ustGezahlt }
    var gewinn: Decimal { einnahmen - ausgaben }
}

/// Ein Punkt der Vorprüfung: `warnung` verändert Zahlen, sonst erklärt er sie.
struct Pruefpunkt: Hashable, Identifiable {
    var warnung: Bool
    var text: String
    var details: [String] = []
    var id: String { text }
}

extension Steuer {

    /// Jahr, in dem eine USt-Zahlung in der EÜR zählt: im Jahr der Zahlung, außer Zahlung **und**
    /// Fälligkeit liegen in den zehn Tagen um den Jahreswechsel – dann im Jahr, zu dem sie
    /// wirtschaftlich gehört (§11 Abs. 2 Satz 2 EStG; Q4 am 10. Januar gezahlt: Vorjahr).
    static func abflussJahr(_ z: SteuerzahlungPosten) -> Int {
        let zahlJahr = appKalender.component(.year, from: z.zahltag)
        if umJahreswechsel(z.zahltag), umJahreswechsel(z.faellig), abs(zahlJahr - z.jahr) <= 1 {
            return z.jahr
        }
        return zahlJahr
    }

    static func ustJahreserklaerung(
        jahr: Int, einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten], zahlungen: [SteuerzahlungPosten]
    ) -> UStJahreserklaerung {
        let u = ustva(einnahmen: einnahmen, ausgaben: ausgaben, periode: .jahr(jahr))
        let vz = zahlungen.filter { $0.kind == .ustVz && $0.bezahlt && $0.jahr == jahr }
            .reduce(Decimal(0)) { $0 + $1.betrag }
        return UStJahreserklaerung(
            bemessung19: u.kz81, ust19: u.ust81, bemessung7: u.kz86, ust7: u.ust86,
            euLeistungen: u.kz21, drittland: u.kz45,
            rcBemessung: u.kz84, rcUSt: (u.kz84 * satz19).gerundet(),
            vorsteuer: u.kz66, vorauszahlungen: vz)
    }

    static func euerErklaerung(
        jahr: Int, einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten], zahlungen: [SteuerzahlungPosten]
    ) -> EUeRErklaerung {
        let p = Periode.jahr(jahr)
        let bezahlt = einnahmen.filter { $0.zahlungsdatum.map(p.enthaelt) ?? false }
        let betrieblich = ausgaben.filter(\.betrieblich)
        let ust = zahlungen.filter { $0.kind == .ustVz && $0.bezahlt && abflussJahr($0) == jahr }
        return EUeRErklaerung(
            einnahmenNetto: bezahlt.reduce(Decimal(0)) { $0 + $1.rnNetto },
            ustVereinnahmt: bezahlt.reduce(Decimal(0)) { $0 + $1.ust },
            ustErstattet: -ust.filter { $0.betrag < 0 }.reduce(Decimal(0)) { $0 + $1.betrag },
            ausgabenNetto: betrieblich.filter { !$0.istAnlagegut }
                .reduce(Decimal(0)) { $0 + $1.betriebsausgabe(in: p, abfluss: true) },
            afa: afa(betrieblich, in: p),
            vorsteuerGezahlt: betrieblich.filter { p.enthaelt($0.abflussdatum) }.reduce(Decimal(0)) { $0 + $1.vst },
            ustGezahlt: ust.filter { $0.betrag > 0 }.reduce(Decimal(0)) { $0 + $1.betrag })
    }
}

extension Steuer {

    /// Was vor der Erklärung geklärt sein sollte. Rein lesend auf den Modellen.
    ///
    /// - Parameter letzteBankbuchung: jüngster importierter Buchungstag (`ImportBuchung`), `nil`
    ///   = noch nie ein Kontoauszug importiert.
    /// - Parameter ustVoranmeldungen: Σ der berechneten Zahllasten der Voranmeldungen des Jahres.
    /// - Parameter kskSoll: KSK laut Monatswerten.
    static func vorpruefung(
        jahr: Int, einnahmen: [Income], ausgaben: [ExpenseEntry], zahlungen: [TaxPayment],
        hatJahresEinstellungen: Bool, letzteBankbuchung: Date?, ustVoranmeldungen: Decimal, kskSoll: Decimal
    ) -> [Pruefpunkt] {
        let p = Periode.jahr(jahr)
        var punkte: [Pruefpunkt] = []
        func jahrVon(_ d: Date) -> Int { appKalender.component(.year, from: d) }
        func rechnung(_ e: Income) -> String {
            let nr = e.rechnungsnummer.map { "\($0) " } ?? ""
            return "\(nr)\(e.kunde.isEmpty ? "ohne Kunde" : e.kunde) (\(e.rechnungsdatum.deutsch()), \(e.brutto.euro))"
        }

        if !hatJahresEinstellungen {
            punkte.append(
                Pruefpunkt(
                    warnung: true,
                    text: "Für \(jahr) fehlen die Jahres-Einstellungen: ESt-Satz und KSK laufen mit Ersatzwerten."))
        }
        if let letzte = letzteBankbuchung {
            if letzte < tag(jahr, 12, 31), jahr <= jahrVon(Date()) {
                punkte.append(
                    Pruefpunkt(
                        warnung: true,
                        text: "Kontoauszug nur bis \(letzte.deutsch()) importiert – das Jahr ist nicht vollständig."))
            }
        } else {
            punkte.append(
                Pruefpunkt(warnung: false, text: "Noch kein Kontoauszug importiert – Zahlungen bitte von Hand prüfen."))
        }

        let desJahres = einnahmen.filter { p.enthaelt($0.rechnungsdatum) }
        let offen = desJahres.filter { $0.status == .offen }
        if !offen.isEmpty {
            punkte.append(
                Pruefpunkt(
                    warnung: true, text: "Rechnungen des Jahres noch nicht bezahlt – sie fehlen in der EÜR.",
                    details: offen.map(rechnung)))
        }
        let spaeter = desJahres.filter { e in e.zahlungsdatum.map { jahrVon($0) > jahr } ?? false }
        if !spaeter.isEmpty {
            punkte.append(
                Pruefpunkt(
                    warnung: false,
                    text: "Rechnungen des Jahres, bezahlt erst im Folgejahr: USt jetzt, EÜR im Folgejahr.",
                    details: spaeter.map(rechnung)))
        }
        let frueher = einnahmen.filter { e in
            !p.enthaelt(e.rechnungsdatum) && (e.zahlungsdatum.map(p.enthaelt) ?? false)
        }
        if !frueher.isEmpty {
            punkte.append(
                Pruefpunkt(
                    warnung: false,
                    text: "Rechnungen aus dem Vorjahr, bezahlt in diesem Jahr: zählen jetzt in der EÜR.",
                    details: frueher.map(rechnung)))
        }

        let betrieblich = ausgaben.filter(\.betrieblich)
        func ausgabe(_ e: ExpenseEntry) -> String {
            "\(e.bezeichnung.isEmpty ? e.anbieter : e.bezeichnung) (\(e.datum.deutsch()), \(e.netto.euro) netto)"
        }
        let vorlaeufig = betrieblich.filter { $0.istFremdwaehrung && $0.zahlungsdatum == nil && p.enthaelt($0.datum) }
        if !vorlaeufig.isEmpty {
            punkte.append(
                Pruefpunkt(
                    warnung: true,
                    text: "Ausgaben in Fremdwährung ohne Abbuchung: Der Euro-Betrag ist noch vorläufig.",
                    details: vorlaeufig.map(ausgabe)))
        }
        let quer = betrieblich.filter { e in
            let a = e.posten.abflussdatum
            return p.enthaelt(e.datum) != p.enthaelt(a) && (p.enthaelt(e.datum) || p.enthaelt(a))
        }
        if !quer.isEmpty {
            punkte.append(
                Pruefpunkt(
                    warnung: false,
                    text: "Belegdatum und Zahlung in verschiedenen Jahren: Vorsteuer nach Beleg, EÜR nach Zahlung.",
                    details: quer.map { "\(ausgabe($0)), bezahlt \($0.zahlungsdatum?.deutsch() ?? "")" }))
        }
        let kandidaten = betrieblich.filter {
            p.enthaelt($0.datum) && $0.kannAbgeschriebenWerden && $0.nutzungsdauerEffektiv == 0
        }
        if !kandidaten.isEmpty {
            punkte.append(
                Pruefpunkt(
                    warnung: false,
                    text:
                        "Anschaffungen über 800 € netto ohne Abschreibung: prüfen, ob es Anlagegüter sind (Rechner und Software bleiben sofort).",
                    details: kandidaten.map(ausgabe)))
        }
        let ohneBeleg = betrieblich.filter { p.enthaelt($0.datum) && !Belege.existiert($0.belegPfad) }
        if !ohneBeleg.isEmpty {
            punkte.append(
                Pruefpunkt(
                    warnung: false,
                    text: "\(ohneBeleg.count) betriebliche Ausgaben ohne hinterlegten Beleg in Kontor."))
        }

        let gezahlt = zahlungen.filter { $0.kind == .ustVz && $0.bezahlt && $0.jahr == jahr }
            .reduce(Decimal(0)) { $0 + $1.betrag }
        if gezahlt != ustVoranmeldungen {
            punkte.append(
                Pruefpunkt(
                    warnung: true,
                    text:
                        "USt-Vorauszahlungen \(gezahlt.euro) gezahlt, Voranmeldungen ergeben \(ustVoranmeldungen.euro): Protokolle der UStVA prüfen."
                ))
        }
        let kskIst = zahlungen.filter { $0.kind == .ksk && $0.bezahlt && p.enthaelt($0.anzeigeDatum) }
            .reduce(Decimal(0)) { $0 + $1.betrag }
        if kskIst != kskSoll {
            punkte.append(
                Pruefpunkt(
                    warnung: false, text: "KSK laut Monatswerten \(kskSoll.euro), laut Zahlungen \(kskIst.euro)."))
        }
        return punkte
    }
}
