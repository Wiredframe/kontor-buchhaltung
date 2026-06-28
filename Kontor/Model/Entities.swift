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
    func setzeSnapshot(monat: Int, _ snap: MonatsSnapshot) {
        snapshotProMonat[String(monat)] = try? JSONEncoder().encode(snap)
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
    var kategorie: Kategorie
    var betrieblich: Bool
    var umlagefaehig: Bool = false
    var belegPfad: String?
    /// Routet die Buchung in die richtige Ansicht (nil = Betriebsausgabe). Optional, weil neu
    /// (nicht-optionale Enum-Felder crashen die Store-Migration).
    var art: AusgabeArt?

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
        kategorie: Kategorie = .laufend,
        betrieblich: Bool = true,
        umlagefaehig: Bool = false,
        belegPfad: String? = nil,
        art: AusgabeArt? = nil
    ) {
        self.datum = datum
        self.bezeichnung = bezeichnung
        self.anbieter = anbieter
        self.brutto = brutto
        self.vst = vst
        self.steuerart = steuerart
        self.kategorie = kategorie
        self.betrieblich = betrieblich
        self.umlagefaehig = umlagefaehig
        self.belegPfad = belegPfad
        self.art = art
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
            steuerart: steuerart, kategorie: .laufend, betrieblich: betrieblich,
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

    /// Bruttobetrag der Rechnung.
    var brutto: Decimal { rnNetto + ust }
    /// Sortierschlüssel für die (optionale) Rechnungsnummer – ohne Nummer ans Ende.
    var rechnungsnummerSort: String { rechnungsnummer ?? "\u{10FFFF}" }

    init(
        kunde: String,
        rnNetto: Decimal,
        ust: Decimal,
        rechnungsdatum: Date,
        zahlungsdatum: Date? = nil,
        status: InvoiceStatus = .offen,
        ausfalldatum: Date? = nil,
        rechnungsnummer: String? = nil,
        belegPfad: String? = nil
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
