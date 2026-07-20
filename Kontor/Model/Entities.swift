import Foundation
import SwiftData

/// KSK-Versicherungszweig in Bescheid-Reihenfolge: Renten-, Kranken-, Pflegeversicherung.
enum KSKZweig: CaseIterable { case rv, kv, pv }

// MARK: - Pro-Jahr-Einstellungen

@Model
final class YearSettings {
    @Attribute(.unique) var jahr: Int
    var ustvaRhythmus: UStVARhythmus
    var dauerfristverlaengerung: Bool
    var versteuerung: Versteuerung
    /// Jahres-Standardsatz für die ESt-Rücklage (z. B. 0,15).
    var estPauschalSatz: Decimal
    /// Lokaler Grundfreibetrag-Override für die jahresbasierte ESt-Schätzung (Grundtarif, z. B.
    /// Splitting). `nil` = gesetzlicher Standard des Jahres (`Steuer.grundfreibetragStandard`).
    /// Optional gehalten → migrationssicher; bestehende Stores materialisieren `nil`.
    var grundfreibetrag: Decimal? = nil
    /// Monatliche Satz-Overrides (Key = Monat "1"…"12"). Ohne Eintrag gilt
    /// estPauschalSatz – so lassen sich Rücklagen agil je Monat steuern, ohne
    /// bereits gesetzte Monate zu verändern (nur explizit gesetzte sind fix).
    var estSatzProMonat: [String: Decimal] = [:]
    /// Manuell abgeschlossene Monate (Key = Monat "1"…"12" → Abschlussdatum).
    /// Existiert ein Eintrag, gilt der Monat als „durch / alles erledigt".
    var abschlussProMonat: [String: Date] = [:]

    // MARK: Monatswerte (KSK je Monat als KV/RV/PV-Beträge) – Monatswert-Modell

    /// Voraussichtliches Jahresarbeitseinkommen (JAE) je Monat (Key "1"…"12"). **Nur informativ –
    /// keine Berechnungsgrundlage.** Erbt vom Vormonat, falls ein Monat keinen eigenen Wert hat.
    var kskJAEProMonat: [String: Decimal] = [:]
    /// KSK-Monatsbeiträge je Zweig (Key "1"…"12"), Reihenfolge wie im Bescheid:
    /// **Renten-, Kranken-, Pflegeversicherung**. Jeder Zweig wird direkt eingetragen und erbt
    /// unabhängig vom Vormonat; Summe = Monatsbeitrag. Die Zweige speisen die
    /// „KSK nach Versicherung"-Jahresansicht.
    var kskRVProMonat: [String: Decimal] = [:]
    var kskKVProMonat: [String: Decimal] = [:]
    var kskPVProMonat: [String: Decimal] = [:]

    /// Eingefrorene Monatsstände (Key "1"…"12" → JSON-kodierter `MonatsSnapshot`). Existiert
    /// ein Eintrag, zeigt der abgeschlossene Monat diese fixen Zahlen statt der Live-Rechnung.
    var snapshotProMonat: [String: Data] = [:]

    init(
        jahr: Int,
        ustvaRhythmus: UStVARhythmus = .vierteljaehrlich,
        dauerfristverlaengerung: Bool = false,
        versteuerung: Versteuerung = .soll,
        estPauschalSatz: Decimal,
        grundfreibetrag: Decimal? = nil,
        estSatzProMonat: [String: Decimal] = [:],
        abschlussProMonat: [String: Date] = [:],
        kskJAEProMonat: [String: Decimal] = [:],
        kskRVProMonat: [String: Decimal] = [:],
        kskKVProMonat: [String: Decimal] = [:],
        kskPVProMonat: [String: Decimal] = [:],
        snapshotProMonat: [String: Data] = [:]
    ) {
        self.jahr = jahr
        self.ustvaRhythmus = ustvaRhythmus
        self.dauerfristverlaengerung = dauerfristverlaengerung
        self.versteuerung = versteuerung
        self.estPauschalSatz = estPauschalSatz
        self.grundfreibetrag = grundfreibetrag
        self.estSatzProMonat = estSatzProMonat
        self.abschlussProMonat = abschlussProMonat
        self.kskJAEProMonat = kskJAEProMonat
        self.kskRVProMonat = kskRVProMonat
        self.kskKVProMonat = kskKVProMonat
        self.kskPVProMonat = kskPVProMonat
        self.snapshotProMonat = snapshotProMonat
    }

    /// Effektiver ESt-Satz eines Monats: expliziter Wert, sonst der zuletzt davor gesetzte
    /// (Vormonat erbt automatisch), ganz zuletzt der Jahres-Standard.
    func estSatz(monat: Int) -> Decimal {
        for m in stride(from: monat, through: 1, by: -1) {
            if let v = estSatzProMonat[String(m)] { return v }
        }
        return estPauschalSatz
    }
    /// Hat der Monat einen eigenen (fixierten) Satz?
    func hatEigenenSatz(monat: Int) -> Bool { estSatzProMonat[String(monat)] != nil }

    /// Letzter gesetzter Wert ≤ monat aus einem Monats-Dictionary (Vormonat erbt); sonst nil.
    private func geerbt(_ dict: [String: Decimal], monat: Int) -> Decimal? {
        for m in stride(from: monat, through: 1, by: -1) {
            if let v = dict[String(m)] { return v }
        }
        return nil
    }

    /// KV/RV/PV-Monatsbeiträge des Monats – jeder Zweig erbt unabhängig vom Vormonat; sonst 0.
    func kskTeile(monat: Int) -> (kv: Decimal, rv: Decimal, pv: Decimal) {
        (geerbt(kskKVProMonat, monat: monat) ?? 0,
         geerbt(kskRVProMonat, monat: monat) ?? 0,
         geerbt(kskPVProMonat, monat: monat) ?? 0)
    }
    /// Effektiver KSK-Monatsbeitrag = KV + RV + PV; 0 wenn nichts hinterlegt.
    func ksk(monat: Int) -> Decimal { let t = kskTeile(monat: monat); return t.kv + t.rv + t.pv }
    /// Hat der Monat eigene KSK-Angaben (JAE oder einen Zweig-Betrag)?
    func hatEigenenKSK(monat: Int) -> Bool {
        let k = String(monat)
        return kskJAEProMonat[k] != nil || kskRVProMonat[k] != nil
            || kskKVProMonat[k] != nil || kskPVProMonat[k] != nil
    }
    /// Setzt den Monatsbeitrag eines Zweigs explizit.
    func setzeKSKBetrag(monat: Int, _ zweig: KSKZweig, _ betrag: Decimal) {
        let k = String(monat)
        switch zweig {
        case .rv: kskRVProMonat[k] = betrag
        case .kv: kskKVProMonat[k] = betrag
        case .pv: kskPVProMonat[k] = betrag
        }
    }
    /// Entfernt die eigenen KSK-Angaben des Monats (JAE + KV/RV/PV) → erbt wieder vom Vormonat.
    func loescheKSK(monat: Int) {
        let k = String(monat)
        kskJAEProMonat[k] = nil
        kskRVProMonat[k] = nil; kskKVProMonat[k] = nil; kskPVProMonat[k] = nil
    }

    /// Voraussichtliches Jahresarbeitseinkommen des Monats – nur Info (erbt vom Vormonat; sonst 0).
    func jae(monat: Int) -> Decimal { geerbt(kskJAEProMonat, monat: monat) ?? 0 }
    func setzeJAE(monat: Int, _ wert: Decimal) { kskJAEProMonat[String(monat)] = wert }

    /// Ist der Monat manuell abgeschlossen?
    func istAbgeschlossen(monat: Int) -> Bool { abschlussProMonat[String(monat)] != nil }
    /// Abschlussdatum des Monats (falls abgeschlossen).
    func abschlussDatum(monat: Int) -> Date? { abschlussProMonat[String(monat)] }

    /// Eingefrorener Monatsstand (falls beim Abschließen gespeichert).
    func snapshot(monat: Int) -> MonatsSnapshot? {
        guard let d = snapshotProMonat[String(monat)] else { return nil }
        return try? JSONDecoder().decode(MonatsSnapshot.self, from: d)
    }
    /// Friert den Monatsstand ein. Liefert `false`, wenn das nicht gelang – dann bleibt ein
    /// **bereits vorhandener** Snapshot unangetastet.
    ///
    /// Zwei Fallen stecken hier:
    /// 1. `dict[key] = try?` weist bei einem Fehler `nil` zu und **löscht den Schlüssel** –
    ///    der abgeschlossene Monat verlöre still seinen eingefrorenen Stand und rechnete
    ///    wieder live, ohne dass irgendwo etwas schiefzugehen scheint.
    /// 2. Ein `Decimal.nan` im Snapshot lässt `JSONEncoder` **nicht** werfen; er schreibt
    ///    literales `NaN`. Der Encode „gelingt", aber `snapshot(monat:)` bekommt es nie wieder
    ///    dekodiert. Deshalb wird die Gültigkeit hier geprüft, statt nur auf `try?` zu bauen.
    @discardableResult
    func setzeSnapshot(monat: Int, _ snap: MonatsSnapshot) -> Bool {
        guard let d = try? JSONEncoder().encode(snap), istGueltigesJSON(d) else { return false }
        snapshotProMonat[String(monat)] = d
        return true
    }
    func loescheSnapshot(monat: Int) { snapshotProMonat[String(monat)] = nil }
}

extension Array where Element == YearSettings {
    /// Effektiver ESt-Satz für (Jahr, Monat) aus den passenden Jahres-Einstellungen;
    /// Fallback 15 %. Praktisch als Satz-Quelle für Steuer.monatsauswertung.
    func estSatz(jahr: Int, monat: Int) -> Decimal {
        (first { $0.jahr == jahr })?.estSatz(monat: monat) ?? dez("0.15")
    }
    /// Effektiver KSK-Monatsbeitrag für (Jahr, Monat); 0, wenn nichts hinterlegt.
    func ksk(jahr: Int, monat: Int) -> Decimal {
        (first { $0.jahr == jahr })?.ksk(monat: monat) ?? 0
    }
}

// MARK: - Konkrete Monatsausgabe

@Model
final class ExpenseEntry {
    var datum: Date
    var bezeichnung: String
    var anbieter: String
    var brutto: Decimal
    var vst: Decimal
    var steuerart: Steuerart
    var betrieblich: Bool
    var umlagefaehig: Bool = false
    var belegPfad: String?
    /// Routet die Buchung in die richtige Ansicht (nil = Betriebsausgabe). Optional, weil neu
    /// (nicht-optionale Enum-Felder crashen die Store-Migration).
    var art: AusgabeArt?
    /// Rechnungsnummer (z. B. aus OCR) – stabilster Schlüssel für den Kontoauszug-Abgleich.
    var rechnungsnummer: String?
    /// Zahltag aus dem Kontoauszug (rein informativ – die EÜR zählt weiterhin nach `datum`).
    var zahlungsdatum: Date?

    /// Netto = Brutto − Vorsteuer (berechnet, nicht gespeichert).
    var netto: Decimal { brutto - vst }
    /// Effektive Art (Altbestand ohne `art` = Betriebsausgabe).
    var artEffektiv: AusgabeArt { art ?? .betriebsausgabe }

    init(
        datum: Date,
        bezeichnung: String,
        anbieter: String,
        brutto: Decimal,
        vst: Decimal,
        steuerart: Steuerart,
        betrieblich: Bool = true,
        umlagefaehig: Bool = false,
        belegPfad: String? = nil,
        art: AusgabeArt? = nil,
        rechnungsnummer: String? = nil,
        zahlungsdatum: Date? = nil
    ) {
        self.datum = datum
        self.bezeichnung = bezeichnung
        self.anbieter = anbieter
        self.brutto = brutto
        self.vst = vst
        self.steuerart = steuerart
        self.betrieblich = betrieblich
        self.umlagefaehig = umlagefaehig
        self.belegPfad = belegPfad
        self.art = art
        self.rechnungsnummer = rechnungsnummer
        self.zahlungsdatum = zahlungsdatum
    }
}

// MARK: - Vorlage (Sidebar-Vorlage für Fixkosten/Subscriptions – zählt NICHT in der Berechnung)

/// Eine wiederkehrende Kosten-Vorlage, die man per Klick als datierte Buchung (`ExpenseEntry`)
/// in einen Monat einfügt. Bewusst minimal: **kein** Datum, **keine** Gültigkeit, **kein** „aktiv".
@Model
final class Vorlage {
    var bezeichnung: String
    var anbieter: String
    var betragBrutto: Decimal
    var steuerart: Steuerart
    var betrieblich: Bool
    /// Nur `.fixkosten` oder `.subscription`.
    var art: AusgabeArt
    var umlagefaehig: Bool

    init(bezeichnung: String, anbieter: String = "", betragBrutto: Decimal,
         steuerart: Steuerart = .steuerfrei, betrieblich: Bool = false,
         art: AusgabeArt = .fixkosten, umlagefaehig: Bool = false) {
        self.bezeichnung = bezeichnung
        self.anbieter = anbieter
        self.betragBrutto = betragBrutto
        self.steuerart = steuerart
        self.betrieblich = betrieblich
        self.art = art
        self.umlagefaehig = umlagefaehig
    }

    /// Erzeugt eine datierte Buchung aus der Vorlage (Vorsteuer automatisch aus der Steuerart).
    func buchung(am datum: Date) -> ExpenseEntry {
        ExpenseEntry(
            datum: datum, bezeichnung: bezeichnung, anbieter: anbieter,
            brutto: betragBrutto, vst: Steuer.vorsteuerVorschlag(brutto: betragBrutto, steuerart: steuerart),
            steuerart: steuerart, betrieblich: betrieblich,
            umlagefaehig: umlagefaehig, art: art)
    }
}

extension Array where Element == ExpenseEntry {
    /// Brutto-Summe der wiederkehrenden Buchungen (Fixkosten/Subscriptions) eines Monats,
    /// wahlweise nur privat oder nur betrieblich. Für Liquiditäts-/Übersichtsanzeigen.
    func wiederkehrendBrutto(jahr: Int, monat: Int, betrieblich: Bool) -> Decimal {
        let p = Periode.monat(jahr, monat)
        return filter {
            $0.betrieblich == betrieblich
                && ($0.artEffektiv == .fixkosten || $0.artEffektiv == .subscription)
                && p.enthaelt($0.datum)
        }.reduce(Decimal(0)) { $0 + $1.brutto }
    }

    /// Brutto-Summe der **privaten einmaligen** Ausgaben eines Monats (alles, was nicht
    /// wiederkehrend ist) – die variable Hälfte der privaten Kosten.
    ///
    /// Ohne diese Summe fiele eine private Ausgabe mit `art == .betriebsausgabe` aus **jeder**
    /// Auswertung: aus der EÜR zu Recht (sie ist privat), aus `wiederkehrendBrutto` mangels
    /// Fixkosten-/Subscription-Art, und aus `privatVariabel`, weil dort nur Lebensmittel und
    /// Anschaffungen zählen. Das Geld wäre ausgegeben, „Frei verfügbar" aber unverändert hoch.
    /// Genau diesen Zustand erzeugt „In Ausgaben verschieben" in den Anschaffungen.
    func privatEinmaligBrutto(jahr: Int, monat: Int) -> Decimal {
        let p = Periode.monat(jahr, monat)
        return filter {
            !$0.betrieblich && $0.artEffektiv == .betriebsausgabe && p.enthaelt($0.datum)
        }.reduce(Decimal(0)) { $0 + $1.brutto }
    }
}

// MARK: - Einnahme / Ausgangsrechnung

@Model
final class Income {
    var kunde: String
    var rnNetto: Decimal
    var ust: Decimal
    var rechnungsdatum: Date
    var zahlungsdatum: Date?
    var status: InvoiceStatus
    /// Datum der Uneinbringlichkeit – steuert die §17-USt-Korrektur (Quartal des Ausfalls).
    var ausfalldatum: Date?
    /// Rechnungsnummer – für Import-Dedup und Referenz.
    var rechnungsnummer: String?
    /// Pfad zur angehängten Rechnungs-PDF (relativ zum Belege-Ordner).
    var belegPfad: String?
    /// USt-Satz des Regel-Buckets. **Optional** (neu hinzugefügtes Enum-Feld → sonst
    /// Migrations-Crash bestehender Stores); `nil` = Regelsatz 19 % (Altbestand). Zugriff über `satzEffektiv`.
    var satz: UStSatz?
    /// Zweiter Satz-Bucket für **Mischrechnungen** (7 % UND 19 % auf einer Rechnung), z. B. Nutzungsrechte
    /// 7 % + sonstige Leistung 19 %. `satz2 == nil` ⇒ kein zweiter Satz; Beträge dann 0.
    var rnNetto2: Decimal = 0
    var ust2: Decimal = 0
    var satz2: UStSatz?

    /// Effektiver Satz des Regel-Buckets (Altbestand ohne `satz` = 19 %).
    var satzEffektiv: UStSatz { satz ?? .satz19 }
    /// Trägt die Rechnung einen zweiten Steuersatz (Mischrechnung)?
    var hatZweitenSatz: Bool { satz2 != nil }
    /// Netto **gesamt** über beide Buckets – Basis für Tabelle/Summen/EÜR/Backup (nie nur `rnNetto`).
    var nettoGesamt: Decimal { rnNetto + rnNetto2 }
    /// USt **gesamt** über beide Buckets.
    var ustGesamt: Decimal { ust + ust2 }
    /// Bruttobetrag der Rechnung (beide Buckets).
    var brutto: Decimal { nettoGesamt + ustGesamt }
    /// Sortierschlüssel für die (optionale) Rechnungsnummer – ohne Nummer ans Ende.
    var rechnungsnummerSort: String { rechnungsnummer ?? "\u{10FFFF}" }
    /// Sortierschlüssel für das (optionale) Zahlungsdatum – noch unbezahlte ganz nach vorn/hinten.
    var zahlungsdatumSort: Date { zahlungsdatum ?? .distantPast }

    init(
        kunde: String,
        rnNetto: Decimal,
        ust: Decimal,
        rechnungsdatum: Date,
        zahlungsdatum: Date? = nil,
        status: InvoiceStatus = .offen,
        ausfalldatum: Date? = nil,
        rechnungsnummer: String? = nil,
        belegPfad: String? = nil,
        satz: UStSatz? = nil,
        rnNetto2: Decimal = 0,
        ust2: Decimal = 0,
        satz2: UStSatz? = nil
    ) {
        self.kunde = kunde
        self.rnNetto = rnNetto
        self.ust = ust
        self.rechnungsdatum = rechnungsdatum
        self.zahlungsdatum = zahlungsdatum
        self.status = status
        self.ausfalldatum = ausfalldatum
        self.rechnungsnummer = rechnungsnummer
        self.belegPfad = belegPfad
        self.satz = satz
        self.rnNetto2 = rnNetto2
        self.ust2 = ust2
        self.satz2 = satz2
    }

    /// Setzt den Status und hält Zahlungs-/Ausfalldatum konsistent:
    /// bezahlt → Zahlungsdatum (heute, falls leer), kein Ausfall; offen → beides leer;
    /// ausgefallen → kein Zahlungsdatum, Ausfalldatum (heute, falls leer) – damit die
    /// §17-USt-Korrektur ohne manuelles Nachtragen greift.
    func setze(status neu: InvoiceStatus) {
        status = neu
        switch neu {
        case .bezahlt:     if zahlungsdatum == nil { zahlungsdatum = Date() }; ausfalldatum = nil
        case .offen:       zahlungsdatum = nil; ausfalldatum = nil
        case .ausgefallen: zahlungsdatum = nil; if ausfalldatum == nil { ausfalldatum = Date() }
        }
    }
}

// MARK: - Steuern & Abgaben (Zahlungen/Termine)

@Model
final class TaxPayment {
    var kind: SteuerKind
    var jahr: Int
    var faellig: Date
    var betrag: Decimal
    var bezahlt: Bool
    var bezahltAm: Date?
    var bemerkung: String

    init(kind: SteuerKind, jahr: Int, faellig: Date, betrag: Decimal = 0,
         bezahlt: Bool = false, bezahltAm: Date? = nil, bemerkung: String = "") {
        self.kind = kind
        self.jahr = jahr
        self.faellig = faellig
        self.betrag = betrag
        self.bezahlt = bezahlt
        self.bezahltAm = bezahltAm
        self.bemerkung = bemerkung
    }
}

// MARK: - Privat: Lebensmittel-Einkauf

@Model
final class GroceryEntry {
    var datum: Date
    var betrag: Decimal
    var ort: String

    init(datum: Date, betrag: Decimal, ort: String) {
        self.datum = datum
        self.betrag = betrag
        self.ort = ort
    }
}

// MARK: - Privat: Bestellung / Anschaffung

@Model
final class PurchaseEntry {
    var datum: Date
    var bezeichnung: String
    var preis: Decimal
    var belegPfad: String?

    init(datum: Date, bezeichnung: String, preis: Decimal, belegPfad: String? = nil) {
        self.datum = datum
        self.bezeichnung = bezeichnung
        self.preis = preis
        self.belegPfad = belegPfad
    }
}

// MARK: - Aufgabe (optional wiederkehrend)

enum TaskIntervall: String, Codable, CaseIterable, Identifiable {
    case einmalig, monatlich, quartalsweise, jaehrlich
    var id: String { rawValue }
    var bezeichnung: String {
        switch self {
        case .einmalig:      "einmalig"
        case .monatlich:     "monatlich"
        case .quartalsweise: "quartalsweise"
        case .jaehrlich:     "jährlich"
        }
    }
    /// Sortierrang nach Häufigkeit (für sortierbare Tabellenspalte „Wiederholung").
    var sortRang: Int {
        switch self {
        case .einmalig:      0
        case .monatlich:     1
        case .quartalsweise: 2
        case .jaehrlich:     3
        }
    }

    /// Robust gegen unbekannte Werte: → einmalig (entspricht dem Import-Default für
    /// Backups aus der Zeit vor der Wiederhol-Mechanik; erzeugt keine Folgeaufgaben).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskIntervall(rawValue: raw) ?? .einmalig
    }
}

/// Eine Aufgabe – einmalig oder wiederkehrend (Reminders-Logik: beim Abhaken einer
/// wiederkehrenden Aufgabe erscheint automatisch die nächste fällige).
@Model
final class MonthlyTask {
    var titel: String
    /// Fälligkeit dieser konkreten Instanz.
    var monat: Date
    var erledigt: Bool
    var intervall: TaskIntervall
    /// Tag im Monat, an dem wiederkehrende Aufgaben fällig sind.
    var faelligTag: Int
    /// Nur für `quartalsweise`: Monate (1…12), in denen die Aufgabe anfällt.
    var quartalsMonate: [Int]

    var istWiederkehrend: Bool { intervall != .einmalig }
    /// Sortierschlüssel der Checkbox-Spalte (Bool ist nicht `Comparable`): offen vor erledigt.
    var erledigtSort: Int { erledigt ? 1 : 0 }

    init(titel: String, monat: Date, erledigt: Bool = false,
         intervall: TaskIntervall = .einmalig, faelligTag: Int = 1, quartalsMonate: [Int] = []) {
        self.titel = titel
        self.monat = monat
        self.erledigt = erledigt
        self.intervall = intervall
        self.faelligTag = faelligTag
        self.quartalsMonate = quartalsMonate
    }
}

// MARK: - Kontoauszug-Import: Lern-Regel + Verarbeitungs-Gedächtnis

/// Gelernte Zuordnung: Händlerschlüssel → vorgeschlagene Kategorie. Wird beim Anwenden
/// (oder Ändern) eines Vorschlags per Upsert aktualisiert → nächster Import nutzt sie als Default.
@Model
final class ZuordnungsRegel {
    @Attribute(.unique) var schluessel: String   // Bankbuchung.haendlerSchluessel
    var kategorie: ImportKategorie
    var betrieblich: Bool
    var steuerart: Steuerart
    /// Gelernte Steuerart für `.steuer`-Buchungen (USt-VZ/ESt-VZ/…). Nur dort relevant.
    /// **Optional**, weil ein neu hinzugefügtes Enum-Attribut sonst die Lightweight-Migration
    /// bestehender Stores sprengt (Default wird nicht materialisiert → Cast-Crash). Nutzung über `… ?? .ustVz`.
    var steuerKind: SteuerKind?
    var aktualisiert: Date

    init(schluessel: String, kategorie: ImportKategorie, betrieblich: Bool,
         steuerart: Steuerart = .inland19, steuerKind: SteuerKind = .ustVz, aktualisiert: Date = Date()) {
        self.schluessel = schluessel
        self.kategorie = kategorie
        self.betrieblich = betrieblich
        self.steuerart = steuerart
        self.steuerKind = steuerKind
        self.aktualisiert = aktualisiert
    }
}

/// Gedächtnis, welche Bankbewegung bereits verarbeitet wurde (Dedup über den stabilen
/// Bank-Schlüssel) – macht den Import idempotent und merkt sich „abgehakt".
@Model
final class ImportBuchung {
    @Attribute(.unique) var schluessel: String   // Bankbuchung.dedupSchluessel
    var buchungstag: Date
    var betrag: Decimal
    var gegenpartei: String
    var kategorie: ImportKategorie
    var betrieblich: Bool
    var erstellt: Date

    init(schluessel: String, buchungstag: Date, betrag: Decimal, gegenpartei: String,
         kategorie: ImportKategorie, betrieblich: Bool, erstellt: Date = Date()) {
        self.schluessel = schluessel
        self.buchungstag = buchungstag
        self.betrag = betrag
        self.gegenpartei = gegenpartei
        self.kategorie = kategorie
        self.betrieblich = betrieblich
        self.erstellt = erstellt
    }
}
