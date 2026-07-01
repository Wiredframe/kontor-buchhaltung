import Foundation

// MARK: - Enums (laut Spezifikation)

/// Steuerliche Behandlung einer Ausgabe.
enum Steuerart: String, Codable, CaseIterable, Identifiable {
    case inland19       // 19 % deutsche Vorsteuer abziehbar
    case reverseCharge  // §13b: USt in KZ 84/85, cash-neutral, VSt = 0
    case steuerfrei     // keine USt/VSt

    var id: String { rawValue }
    var bezeichnung: String {
        switch self {
        case .inland19:      "Inland 19 %"
        case .reverseCharge: "Reverse-Charge (§13b)"
        case .steuerfrei:    "steuerfrei"
        }
    }
}

/// Ausgangs-USt-Satz einer Einnahme/Ausgangsrechnung. Bewusst nur die beiden Regelsätze
/// **19 % (Regelsatz)** und **7 % (ermäßigt, z. B. Einräumung von Nutzungsrechten)** – kein
/// 0 %/steuerfrei-Ausgang, kein Kleinunternehmer. Der Decimal-Wert liegt zentral in `Steuer`.
enum UStSatz: String, Codable, CaseIterable, Identifiable {
    case satz19   // Regelsatz 19 %
    case satz7    // ermäßigter Satz 7 %

    var id: String { rawValue }
    /// Effektiver Steuersatz als Decimal (Konstanten zentral in `Steuer`).
    var wert: Decimal { self == .satz19 ? Steuer.satz19 : Steuer.satz7 }
    var bezeichnung: String {
        switch self {
        case .satz19: "19 %"
        case .satz7:  "7 %"
        }
    }

    /// Robust gegen Altdaten/unbekannte Werte: Unbekanntes → Regelsatz 19 %.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UStSatz(rawValue: raw) ?? .satz19
    }
}

/// Wiederholungs-Intervall einer Vorlage.
enum Intervall: String, Codable, CaseIterable, Identifiable {
    case monatlich
    case jaehrlich

    var id: String { rawValue }
    var bezeichnung: String {
        switch self {
        case .monatlich: "monatlich"
        case .jaehrlich: "jährlich"
        }
    }
}

/// Art einer datierten Ausgabe-Buchung. Steuert **nur die Ansicht** (Betriebsausgaben vs.
/// das gemeinsame Modul „Fixkosten & Subscriptions"); die EÜR zählt unverändert nach `betrieblich`.
enum AusgabeArt: String, Codable, CaseIterable, Identifiable {
    case betriebsausgabe   // einmalige Betriebsausgabe / Anschaffung
    case fixkosten         // wiederkehrende Fixkosten (Miete, Handy, Versicherung …)
    case subscription      // Abo / Subscription

    var id: String { rawValue }
    var bezeichnung: String {
        switch self {
        case .betriebsausgabe: "Betriebsausgabe"
        case .fixkosten:       "Fixkosten"
        case .subscription:    "Subscription"
        }
    }
}

/// Status einer Ausgangsrechnung.
enum InvoiceStatus: String, Codable, CaseIterable, Identifiable {
    case offen
    case bezahlt
    case ausgefallen  // uneinbringlich → USt-Korrektur §17 im Quartal des Ausfalls

    var id: String { rawValue }
    var bezeichnung: String {
        switch self {
        case .offen:       "offen"
        case .bezahlt:     "bezahlt"
        case .ausgefallen: "ausgefallen"
        }
    }
    /// Logischer Sortierrang (für sortierbare Tabellenspalte): offen → bezahlt → ausgefallen.
    var sortRang: Int {
        switch self {
        case .offen:       0
        case .bezahlt:     1
        case .ausgefallen: 2
        }
    }
}

/// Rhythmus der UStVA (pro Jahr einstellbar). Nur **monatlich** oder **vierteljährlich** –
/// eine jährliche Voranmeldung gibt es nicht (die Jahres-USt ist die Erklärung, keine VA).
enum UStVARhythmus: String, Codable, CaseIterable, Identifiable {
    case monatlich
    case vierteljaehrlich

    var id: String { rawValue }
    var bezeichnung: String {
        switch self {
        case .monatlich:        "monatlich"
        case .vierteljaehrlich: "vierteljährlich"
        }
    }

    /// Robust gegen Altdaten (früher gab es zusätzlich „jaehrlich"): Unbekanntes → vierteljährlich.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UStVARhythmus(rawValue: raw) ?? .vierteljaehrlich
    }
}

/// Versteuerungsart. Kontor rechnet ausschließlich nach **Soll** (vereinbarte
/// Entgelte, USt nach Rechnungsdatum). Die frühere „Ist"-Option wurde entfernt.
enum Versteuerung: String, Codable, CaseIterable, Identifiable {
    case soll  // USt entsteht mit Rechnungsstellung

    var id: String { rawValue }
    var bezeichnung: String { "Soll (vereinbarte Entgelte)" }

    /// Robust gegen Altdaten (früher gab es zusätzlich „ist"): Unbekanntes → soll.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Versteuerung(rawValue: raw) ?? .soll
    }
}

/// Art einer Steuerzahlung/-position.
enum SteuerKind: String, Codable, CaseIterable, Identifiable {
    case ustVz        // Umsatzsteuer-Zahllast (Voranmeldung)
    case estVz        // Einkommensteuer-Vorauszahlung
    case estBescheid  // ESt-Nachzahlung/Erstattung laut Bescheid
    case ksk          // KSK-Beitrag (Vorsorge): Ist-Zahlung; Soll kommt aus dem Beitragssatz
    case sonstige

    var id: String { rawValue }
    var bezeichnung: String {
        switch self {
        case .ustVz:       "USt-Vorauszahlung"
        case .estVz:       "ESt-Vorauszahlung"
        case .estBescheid: "ESt-Bescheid"
        case .ksk:         "KSK-Beitrag"
        case .sonstige:    "Sonstige"
        }
    }
}

// MARK: - Kontoauszug-Import: Triage-Kategorie

/// Vom Nutzer je Bankzeile gewählte Zuordnung beim Kontoauszug-Import.
enum ImportKategorie: String, Codable, CaseIterable, Identifiable {
    case einnahme         // Zahlungseingang → offene Rechnung als bezahlt matchen
    case lebensmittel     // privater Lebensmittel-Einkauf → GroceryEntry
    case anschaffung      // private Anschaffung/Ausgabe → PurchaseEntry
    case erstattung       // Rückerstattung/Gutschrift → negative PurchaseEntry (mindert Einkäufe)
    case betriebsausgabe  // Betriebsausgabe → ExpenseEntry
    case fixkosten        // Fixkosten (betrieblich → ExpenseEntry, privat → nur abhaken)
    case subscription     // Abo (betrieblich → ExpenseEntry, privat → nur abhaken)
    case ksk              // KSK-Beitrag → TaxPayment(kind:.ksk), Ist-Zahlung (Betrag = Abbuchung)
    case steuer           // Steuerzahlung (Finanzamt) → TaxPayment (USt-VZ/ESt-VZ/…), positiv
    case steuererstattung // Steuererstattung (Finanzamt → Eingang) → negativer TaxPayment
    case ignorieren       // eigener Übertrag, Bargeld … → nur abhaken

    var id: String { rawValue }
    var bezeichnung: String {
        switch self {
        case .einnahme:         "Zahlungseingang"
        case .lebensmittel:     "Lebensmittel"
        case .anschaffung:      "Anschaffung (privat)"
        case .erstattung:       "Erstattung (Gutschrift)"
        case .betriebsausgabe:  "Betriebsausgabe"
        case .fixkosten:        "Fixkosten"
        case .subscription:     "Subscription"
        case .ksk:              "KSK-Beitrag"
        case .steuer:           "Steuerzahlung"
        case .steuererstattung: "Steuererstattung"
        case .ignorieren:       "Ignorieren"
        }
    }

    /// Erzeugt diese Wahl einen Datensatz, oder wird die Bankzeile nur „abgehakt"?
    /// Fixkosten/Subscriptions buchen **immer** (privat = Liquiditäts-Buchung, betrieblich = EÜR).
    /// Nur „Ignorieren" legt nichts an. Steuer/Steuererstattung **und KSK** → `TaxPayment` (Ist-Ledger).
    func bucht(betrieblich: Bool) -> Bool {
        switch self {
        case .einnahme, .lebensmittel, .anschaffung, .erstattung, .betriebsausgabe: true
        case .steuer, .steuererstattung, .ksk:                         true
        case .fixkosten, .subscription:                                true
        case .ignorieren:                                              false
        }
    }
}
