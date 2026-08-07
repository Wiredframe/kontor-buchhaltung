import Foundation

/// Ein Voranmeldungs-Zeitraum mit seiner USt-Zahllast (Monat oder Quartal, je nach Rhythmus).
struct UStPeriodenwert: Hashable {
    var label: String
    var betrag: Decimal
}

/// KSK-Jahressumme nach Versicherungszweig.
struct KSKTeile: Hashable {
    var kv: Decimal
    var rv: Decimal
    var pv: Decimal

    var gesamt: Decimal { kv + rv + pv }
}

/// Alle Jahres-Aggregate des Jahresabschlusses, **einmal** gebaut statt als computed properties
/// bei jedem Zugriff neu gerechnet.
///
/// Liegt bewusst in `Berechnung/` und nicht in der View: seit der Jahresabschluss aus einer
/// Übersicht plus vier Unterseiten besteht, brauchen fünf Views dieselben Zahlen – und nur hier
/// sind sie ohne SwiftUI testbar.
struct Jahreswerte {
    var jahr: Int
    var a: JahresAuswertung
    /// USt-Zahllast je Voranmeldungs-Zeitraum – je nach Rhythmus 12 Monate oder 4 Quartale.
    var ustPerioden: [UStPeriodenwert]
    var ustRhythmus: UStVARhythmus
    var estRuecklage: Decimal  // Σ ESt-Rücklage über 12 Monate (geschätzt, pauschal)
    var ksk: KSKTeile
    var zahlungen: [TaxPayment]  // des Jahres, nach Datum sortiert
    var grundfreibetrag: Decimal  // angesetzter Grundfreibetrag (Standard oder lokaler Override)
    var estVoraussichtlich: Decimal  // jahresbasierte ESt inkl. Grundfreibetrag (realistischer)
    /// Festgesetzte ESt laut Steuerbescheid; `nil` = kein Bescheid erfasst.
    var estLautBescheid: Decimal?
    var istAktuellesJahr: Bool
    /// Gibt es `YearSettings` für dieses Jahr? Ohne sie rechnen ESt und KSK still mit Fallbacks.
    var hatJahresEinstellungen: Bool
    /// Einmal gemappte Posten – Aufrufer, die daraus weiterrechnen (z. B. die Chart-Reihe der
    /// Übersicht), sollen nicht ein zweites Mal über alle Einnahmen/Ausgaben mappen müssen.
    var einP: [EinnahmePosten]
    var ausP: [AusgabePosten]

    var ustJahr: Decimal { ustPerioden.reduce(Decimal(0)) { $0 + $1.betrag } }
    var kskGesamt: Decimal { ksk.gesamt }
    var steuerlast: Decimal { estRuecklage + ustJahr }
    var bezahltGesamt: Decimal { zahlungen.filter(\.bezahlt).reduce(Decimal(0)) { $0 + $1.betrag } }
    var estVzBezahlt: Decimal {
        zahlungen.filter { $0.kind == .estVz && $0.bezahlt }.reduce(Decimal(0)) { $0 + $1.betrag }
    }
    /// Bereits geleistete Zahlungen **nach** Bescheid (Nachzahlung positiv, Erstattung negativ).
    var estBescheidBezahlt: Decimal {
        zahlungen.filter { $0.kind == .estBescheid && $0.bezahlt }.reduce(Decimal(0)) { $0 + $1.betrag }
    }
    // Ist-Zahlungen je Steuerthema (für die „Tatsächlich gezahlt"-Panels).
    var ustGezahlt: [TaxPayment] { zahlungen.filter { $0.kind == .ustVz } }
    var estGezahlt: [TaxPayment] { zahlungen.filter { $0.kind == .estVz || $0.kind == .estBescheid } }
    var kskGezahlt: [TaxPayment] { zahlungen.filter { $0.kind == .ksk } }
    var sonstigeGezahlt: [TaxPayment] { zahlungen.filter { $0.kind == .sonstige } }
}

extension Jahreswerte {

    /// Baut die Jahreswerte aus den Roh-Arrays der View: Posten/KSK werden **einmal** gemappt,
    /// jede Aggregation läuft genau einmal.
    ///
    /// `heute` ist Parameter statt `Date()`, damit die „bis zum laufenden Monat"-Logik der
    /// KSK-Jahressumme deterministisch testbar bleibt.
    static func bauen(
        jahr: Int, einnahmen: [Income], ausgaben: [ExpenseEntry],
        zahlungen: [TaxPayment], jahre: [YearSettings], heute: Date = Date()
    ) -> Jahreswerte {
        // Einstellungen **genau dieses Jahres** – kein Fallback (sonst zöge die KSK-Jahressumme
        // die Beiträge eines fremden Jahres heran, wenn das gewählte Jahr keine `YearSettings` hat).
        let settings = jahre.first { $0.jahr == jahr }
        let einP = einnahmen.flatMap(\.postenListe)
        let ausP = ausgaben.map(\.posten)
        let a = Steuer.jahresauswertung(jahr: jahr, einnahmen: einP, ausgaben: ausP)
        let kskT = kskJahr(jahr: jahr, settings: settings, heute: heute)
        let est = Steuer.estRuecklageJahr(
            jahr: jahr, einnahmen: einP, ausgaben: ausP, kskFuer: { jahre.ksk(jahr: $0, monat: $1) },
            pauschalSatz: { jahre.estSatz(jahr: $0, monat: $1) })
        // Jahresbasierte, realistischere ESt: berücksichtigt den steuerfreien Grundfreibetrag.
        // Standard des Jahres, lokal je Jahr überschreibbar; Satz = zuletzt gültiger (Dez.-effektiv),
        // kein Hochrechnen. Rechnet auf demselben Gewinn/KSK, die oben angezeigt werden.
        let gfb = settings?.grundfreibetrag ?? Steuer.grundfreibetragStandard(jahr: jahr)
        let voraus = Steuer.estVoraussichtlich(
            gewinn: a.gewinn, ksk: kskT.gesamt,
            grundfreibetrag: gfb, satz: jahre.estSatz(jahr: jahr, monat: 12))
        // USt-Zahllast je VA-Zeitraum – Rhythmus aus den Jahres-Einstellungen (monatlich = 12,
        // sonst 4 Quartale). Die Jahressumme ist in beiden Fällen identisch.
        let rhythmus = settings?.ustvaRhythmus ?? .vierteljaehrlich
        let ustP: [UStPeriodenwert] =
            rhythmus == .monatlich
            ? (1...12).map {
                UStPeriodenwert(
                    label: kurzMonat($0),
                    betrag: Steuer.ustva(einnahmen: einP, ausgaben: ausP, periode: Periode.monat(jahr, $0)).zahllast)
            }
            : (1...4).map {
                UStPeriodenwert(
                    label: "Q\($0)",
                    betrag: Steuer.ustva(einnahmen: einP, ausgaben: ausP, periode: Periode.quartal(jahr, $0)).zahllast)
            }
        let jz = zahlungen.filter { $0.jahr == jahr }.sorted { $0.anzeigeDatum < $1.anzeigeDatum }
        return Jahreswerte(
            jahr: jahr, a: a, ustPerioden: ustP, ustRhythmus: rhythmus, estRuecklage: est, ksk: kskT,
            zahlungen: jz, grundfreibetrag: gfb, estVoraussichtlich: voraus,
            estLautBescheid: settings?.estLautBescheid,
            istAktuellesJahr: jahr == appKalender.component(.year, from: heute),
            hatJahresEinstellungen: settings != nil, einP: einP, ausP: ausP)
    }

    /// KSK des Jahres nach Versicherungszweig – Summe der je Monat gültigen Beitragssätze
    /// (bis zum laufenden Monat im aktuellen Jahr, sonst volles Jahr).
    private static func kskJahr(jahr: Int, settings: YearSettings?, heute: Date) -> KSKTeile {
        let hJ = appKalender.component(.year, from: heute)
        let hM = appKalender.component(.month, from: heute)
        let bis = jahr < hJ ? 12 : (jahr == hJ ? hM : 0)
        guard bis >= 1, let s = settings else { return KSKTeile(kv: 0, rv: 0, pv: 0) }
        // Exakte Summe der je Monat hinterlegten KV/RV/PV-Beträge.
        var kv = Decimal(0), rv = Decimal(0), pv = Decimal(0)
        for m in 1...bis {
            let t = s.kskTeile(monat: m)
            kv += t.kv
            rv += t.rv
            pv += t.pv
        }
        return KSKTeile(kv: kv, rv: rv, pv: pv)
    }
}
