import Foundation

// MARK: - Reine Werttypen für die Berechnungs-Schicht
//
// Die Engine arbeitet bewusst auf einfachen Structs (nicht auf @Model), damit
// sie ohne SwiftData testbar bleibt. Die @Model-Klassen liefern Konverter.

struct AusgabePosten: Hashable {
    var brutto: Decimal
    var vst: Decimal
    var steuerart: Steuerart
    var betrieblich: Bool
    var datum: Date
    /// Abfluss (§11 Abs. 2 EStG) – maßgeblich nur für die EÜR. Vorsteuer, Monatsgewinn und
    /// ESt-Rücklage bleiben beim Belegdatum. `nil` = am Belegdatum bezahlt.
    var zahlungsdatum: Date? = nil
    /// Nutzungsdauer in Jahren für die AfA (§7 Abs. 1 EStG); 0 = sofort abziehbar.
    var nutzungsdauer: Int = 0
    /// Wiederkehrende Ausgabe (Fixkosten/Subscription) – für die Zehn-Tage-Regel um den
    /// Jahreswechsel (§11 Abs. 2 Satz 2 EStG).
    var wiederkehrend: Bool = false
    /// Nur für das Anlagenverzeichnis.
    var bezeichnung: String = ""

    var netto: Decimal { brutto - vst }
    /// Abnutzbares Anlagegut: betrieblich und mit Nutzungsdauer.
    var istAnlagegut: Bool { betrieblich && nutzungsdauer > 0 }
}

struct EinnahmePosten: Hashable {
    var rnNetto: Decimal
    var ust: Decimal
    /// USt-Satz dieses Postens – die Engine gruppiert danach in KZ 81 (19 %) bzw. KZ 86 (7 %).
    var satz: UStSatz = .satz19
    /// Steuerliche Verortung: entscheidet **vor** dem Satz, ob der Posten überhaupt in KZ 81/86
    /// gehört (`.inland`) oder in die reinen Meldekennzahlen KZ 21 / KZ 45.
    var umsatzart: Umsatzart = .inland
    var rechnungsdatum: Date
    var zahlungsdatum: Date?
    var status: InvoiceStatus
    var ausfalldatum: Date?

    var brutto: Decimal { rnNetto + ust }

    /// Siehe `forderungsausfallFaktor(status:ausfalldatum:zahlungsdatum:in:)`.
    func ausfallFaktor(in periode: Periode) -> Decimal {
        forderungsausfallFaktor(status: status, ausfalldatum: ausfalldatum, zahlungsdatum: zahlungsdatum, in: periode)
    }
}

/// Wie eine Periode von einem Forderungsausfall (§17 UStG) betroffen ist:
/// **+1**, wenn die Rechnung in der Periode ausgefallen ist, **−1**, wenn sie in der Periode
/// nach dem Ausfall doch noch bezahlt wurde, sonst 0. Liegt beides in derselben Periode, hebt
/// es sich auf.
///
/// Die Rücknahme folgt §17 Abs. 2 Nr. 1 Satz 2 UStG: Wird das Entgelt nach der Berichtigung
/// doch vereinnahmt, sind Steuer und Bemessungsgrundlage **im Zeitraum der Zahlung** erneut zu
/// berichtigen. Der Ausfallzeitraum bleibt dabei unangetastet – dessen Voranmeldung ist längst
/// abgegeben. Früher löschte „bezahlt" das Ausfalldatum, die Minderung verschwand damit
/// rückwirkend aus dem Ausfallquartal und tauchte im Zahlungsquartal nie als Rücknahme auf.
///
/// Ausgefallen ist eine Rechnung, die ein Ausfalldatum trägt und nicht (wieder) offen ist;
/// „nach dem Ausfall bezahlt" heißt Status bezahlt **mit** Ausfall- und Zahlungsdatum.
func forderungsausfallFaktor(status: InvoiceStatus, ausfalldatum: Date?, zahlungsdatum: Date?, in periode: Periode)
    -> Decimal
{
    guard let ausfall = ausfalldatum, status != .offen else { return 0 }
    var faktor: Decimal = periode.enthaelt(ausfall) ? 1 : 0
    if status == .bezahlt, let z = zahlungsdatum, periode.enthaelt(z) { faktor -= 1 }
    return faktor
}

/// Eine Ausgangsrechnung, so wie die **Zusammenfassende Meldung** sie sieht: Kunde, dessen
/// USt-IdNr. und das gemeldete Netto. Bewusst ein eigener Typ neben `EinnahmePosten` – die ZM
/// gruppiert nach USt-IdNr. (die dem Posten fehlt) und kennt keine Satz-Buckets, weil bei
/// Reverse-Charge gar kein deutscher Steuersatz greift.
struct ZMPosten: Hashable {
    var kunde: String
    /// `nil` oder leer = der Rechnung fehlt die UID; die Meldung ist dann unvollständig.
    var ustIdNr: String?
    /// Netto **gesamt** über beide Satz-Buckets (bei EU-RC ist die USt ohnehin 0).
    var netto: Decimal
    var rechnungsdatum: Date
    var status: InvoiceStatus
    var ausfalldatum: Date?
    var zahlungsdatum: Date? = nil

    func ausfallFaktor(in periode: Periode) -> Decimal {
        forderungsausfallFaktor(status: status, ausfalldatum: ausfalldatum, zahlungsdatum: zahlungsdatum, in: periode)
    }
}

/// Eingefrorener Monatsstand: alle Beträge eines Monats, gespeichert beim Abschließen.
/// Ein abgeschlossener Monat zeigt diesen Snapshot statt der Live-Berechnung – die Zahlen
/// bleiben fix, egal was danach an KSK/ESt o. Ä. geändert wird (bis zum Entsperren).
struct MonatsSnapshot: Codable, Hashable {
    var rn, ust, vst, ustKorrektur, ksk, est, estKorrektur: Decimal
    var betriebsausgabenNetto, umlagefaehig, privatFix, privatVariabel: Decimal
    /// Optional: Snapshots von vor dieser Kennzahl kennen sie nicht (`decodeIfPresent`).
    var ausfallNetto: Decimal? = nil
}

// MARK: - Konverter aus den @Model-Klassen

extension ExpenseEntry {
    var posten: AusgabePosten {
        AusgabePosten(
            brutto: brutto, vst: vst, steuerart: steuerart,
            betrieblich: betrieblich, datum: datum, zahlungsdatum: zahlungsdatum,
            nutzungsdauer: nutzungsdauerEffektiv,
            wiederkehrend: artEffektiv == .fixkosten || artEffektiv == .subscription,
            bezeichnung: bezeichnung.isEmpty ? anbieter : bezeichnung)
    }
}

extension Income {
    /// Ein `EinnahmePosten` je genutztem Satz-Bucket: der Regel-Bucket immer, der zweite nur bei einer
    /// Mischrechnung (`satz2 != nil` und Beträge ≠ 0). Beide erben Rechnungs-/Zahlungs-/Ausfalldatum und
    /// Status – so rechnet die Engine je Satz getrennt (KZ 81/86, §17) ganz ohne Sonderfall-Code.
    var postenListe: [EinnahmePosten] {
        var liste = [
            EinnahmePosten(
                rnNetto: rnNetto, ust: ust, satz: satzEffektiv, umsatzart: umsatzartEffektiv,
                rechnungsdatum: rechnungsdatum, zahlungsdatum: zahlungsdatum,
                status: status, ausfalldatum: ausfalldatum)
        ]
        if let s2 = satz2, rnNetto2 != 0 || ust2 != 0 {
            liste.append(
                EinnahmePosten(
                    rnNetto: rnNetto2, ust: ust2, satz: s2, umsatzart: umsatzartEffektiv,
                    rechnungsdatum: rechnungsdatum, zahlungsdatum: zahlungsdatum,
                    status: status, ausfalldatum: ausfalldatum))
        }
        return liste
    }

    /// Der ZM-Posten dieser Rechnung – `nil`, wenn sie keine Meldung auslöst (Inland/Drittland).
    var zmPosten: ZMPosten? {
        guard umsatzartEffektiv.meldepflichtigZM else { return nil }
        return ZMPosten(
            kunde: kunde, ustIdNr: ustIdNrKunde, netto: nettoGesamt,
            rechnungsdatum: rechnungsdatum, status: status, ausfalldatum: ausfalldatum,
            zahlungsdatum: zahlungsdatum)
    }
}

// MARK: - UStVA-Ergebnis

/// Kennzahlen einer Umsatzsteuer-Voranmeldung für eine Periode – benannt wie im
/// ELSTER-Formular, damit die Werte direkt übertragbar sind.
struct UStVAErgebnis: Hashable {
    var kz81: Decimal  // KZ 81: Bemessungsgrundlage (netto) der zu 19 % steuerpflichtigen Umsätze
    var ust81: Decimal  // darauf entfallende USt 19 % (im Formular automatisch berechnet)
    var kz86: Decimal  // KZ 86: Bemessungsgrundlage (netto) der zu 7 % (ermäßigt) steuerpflichtigen Umsätze
    var ust86: Decimal  // darauf entfallende USt 7 % (im Formular automatisch berechnet)
    /// KZ 21: nicht steuerbare **sonstige Leistungen** an Unternehmer im übrigen Gemeinschaftsgebiet
    /// (`§18b Satz 1 Nr. 2 UStG`) – Leistungsort beim Kunden, der die Steuer schuldet.
    ///
    /// Reine Meldung: keine deutsche USt, deshalb **nicht** in `zahllast`. Die Kennzahl ersetzt aber
    /// nicht die **Zusammenfassende Meldung** (`§18a UStG`) – dort ist derselbe Umsatz je USt-IdNr.
    /// des Kunden zu melden, bis zum 25. nach Quartalsende (siehe `Steuer.zm`).
    var kz21: Decimal = 0
    /// KZ 45: übrige nicht steuerbare Umsätze mit Leistungsort im Ausland (Drittland).
    /// Ebenfalls reine Meldung, ohne ZM-Pflicht.
    var kz45: Decimal = 0
    var kz66: Decimal  // KZ 66: abziehbare Vorsteuer aus Rechnungen anderer Unternehmer (Inland)
    var kz84: Decimal  // KZ 84: §13b Reverse-Charge – Netto-Bemessung der bezogenen Leistungen
    var kz85: Decimal  // KZ 85: §13b – darauf geschuldete USt (immer 19 %)
    var kz67: Decimal  // KZ 67: Vorsteuer aus §13b-Leistungen (= KZ 85, zugleich abziehbar)

    /// §17-Korrektur (negativ) aus Forderungsausfällen – **nur zur Erläuterung**.
    ///
    /// Der Betrag ist **bereits in `kz81`/`kz86` und damit in `ust81`/`ust86` verrechnet**
    /// (das ELSTER-Formular hat kein §17-Feld; der Ausfall mindert dort die Bemessungs-
    /// grundlage). Er steht hier, damit die View erklären kann, warum die Bemessung gemindert
    /// ist – **nicht**, um noch einmal in die Zahllast einzugehen.
    var korrektur17: Decimal

    /// USt-Vorauszahlung (KZ 83) = USt 19 % + USt 7 % + §13b-USt − Vorsteuer Inland − §13b-Vorsteuer.
    /// §13b ist cash-neutral (KZ 85 = KZ 67 heben sich auf). Der §17-Ausfall steckt bereits in
    /// `ust81`/`ust86` – genau wie ELSTER es aus den übertragenen Kennzahlen errechnen würde.
    ///
    /// `kz21`/`kz45` fehlen hier **mit Absicht**: nicht steuerbare Auslandsumsätze werden gemeldet,
    /// nicht besteuert. Nähme man sie auf, entstünde eine Zahllast auf Umsätze, für die Deutschland
    /// gar kein Besteuerungsrecht hat.
    var zahllast: Decimal { ust81 + ust86 + kz85 - kz66 - kz67 }
}
