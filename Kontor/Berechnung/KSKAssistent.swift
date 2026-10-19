import Foundation

/// Abgleich des bei der Künstlersozialkasse gemeldeten **voraussichtlichen Jahresarbeitseinkommens**
/// (JAE) mit dem, was die Zahlen hergeben.
///
/// Die KSK bemisst die Beiträge nach dem gemeldeten JAE. Weicht das tatsächliche Einkommen deutlich
/// ab, lässt sich die Schätzung jederzeit für die Zukunft ändern (wirkt ab dem Folgemonat), die
/// Meldung fürs Folgejahr geht bis zum 1. Dezember (kuenstlersozialkasse.de, Jahresmeldung).
/// Kontor rechnet nur die Schätzung, gemeldet wird bei der KSK. Vorbild: wiredframe-Idee
/// „KSK-Assistent".
struct KSKEinkommensschaetzung: Hashable {
    var jahr: Int
    /// Abgeschlossene Monate, auf denen die Hochrechnung beruht (12 = Jahr vorbei).
    var monate: Int
    /// EÜR-Gewinn (Zu- und Abfluss) dieser Monate.
    var gewinnBisher: Decimal
    /// Auf zwölf Monate hochgerechnet (im abgelaufenen Jahr = der Jahresgewinn).
    var hochrechnung: Decimal
    /// Gemeldetes JAE (im laufenden Jahr der aktuelle Monat, sonst Dezember); 0 = keins hinterlegt.
    var gemeldet: Decimal

    var abweichung: Decimal { hochrechnung - gemeldet }
    /// Relative Abweichung zum gemeldeten JAE; `nil` ohne Meldung.
    var abweichungAnteil: Decimal? { gemeldet > 0 ? abweichung / gemeldet : nil }
    /// Ab einem Fünftel Abweichung lohnt sich ein Blick (bewusst grob, keine Rechtsgrenze).
    var deutlich: Bool { (abweichungAnteil.map { abs($0) >= dez("0.2") }) ?? false }
}

extension Steuer {

    /// Hochrechnung des Arbeitseinkommens (EÜR-Gewinn) auf das Jahr. Im laufenden Jahr zählen nur
    /// **abgeschlossene** Monate – ein angebrochener drückte die Hochrechnung. `nil` im Januar des
    /// laufenden Jahres und für künftige Jahre (noch keine Grundlage).
    static func kskSchaetzung(
        jahr: Int, einnahmen: [EinnahmePosten], ausgaben: [AusgabePosten], settings: YearSettings?,
        heute: Date = Date()
    ) -> KSKEinkommensschaetzung? {
        let hJ = appKalender.component(.year, from: heute)
        let hM = appKalender.component(.month, from: heute)
        let monate = jahr < hJ ? 12 : (jahr == hJ ? hM - 1 : 0)
        guard monate >= 1 else { return nil }
        let p = Periode(von: tag(jahr, 1, 1), bis: monateNach(tag(jahr, 1, 1), monate))
        let einnahmenBezahlt =
            einnahmen
            .filter { $0.zahlungsdatum.map(p.enthaelt) ?? false }
            .reduce(Decimal(0)) { $0 + $1.rnNetto }
        let gewinn = einnahmenBezahlt - betrieblichNetto(ausgaben, in: p, abfluss: true)
        return KSKEinkommensschaetzung(
            jahr: jahr, monate: monate, gewinnBisher: gewinn,
            hochrechnung: (gewinn * 12 / Decimal(monate)).gerundet(0),
            gemeldet: settings?.jae(monat: jahr == hJ ? hM : 12) ?? 0)
    }
}
