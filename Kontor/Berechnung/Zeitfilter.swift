import Foundation

/// Der geteilte Zeitraum aller Tabellen- und Auswertungs-Views: Gesamt / Jahr / Quartal / Monat.
///
/// Liegt bewusst in `Berechnung/` und nicht bei den Views: Das hier ist reine, testbare
/// Datumslogik ohne SwiftUI. Die Views lesen ihn über den `Zeitkontext` aus dem Environment.
///
/// **Start-Zustand = aktueller Monat** (nicht „Gesamt"): Erfassen und Auswerten passieren fast
/// immer im laufenden Monat, „Gesamt" war beim App-Start nur eine lange Liste, die man erst
/// wegfiltern musste. Jahr/Monat stehen ohnehin schon auf heute, der Modus zog nach.
///
/// **Die Periode ist vorberechnet, nicht je Datensatz.** `enthaelt(_:)` läuft in den Tabellen
/// einmal pro Zeile; früher stand dort ein `appKalender.dateComponents(...)`, also eine echte
/// Kalender-Operation je Datensatz. Jetzt wird bei jeder Änderung einmal eine `Periode` gebaut
/// und die Prüfung ist ein Vergleich zweier `Date`. Der Umweg lohnt nur so herum: `Periode`
/// selbst baut über `tag()`/`monateNach()` zwei `Date`-Objekte, wäre also als Computed Property
/// je Zeile teurer als die alte Variante.
struct Zeitfilter: Equatable {
    enum Modus: Hashable, CaseIterable { case alle, jahr, quartal, monat }

    private var _modus: Modus
    private var _jahr: Int
    private var _monat: Int

    /// Der vorberechnete Zeitraum; `nil` = Gesamt (kein Filter).
    private(set) var periode: Periode?

    var modus: Modus {
        get { _modus }
        set {
            _modus = newValue
            baue()
        }
    }
    var jahr: Int {
        get { _jahr }
        set {
            _jahr = newValue
            baue()
        }
    }
    /// 1…12. Im Quartals-Modus steht hier immer der **erste Monat des Quartals**.
    ///
    /// Diese Invariante ist wichtig, weil Monatsabschluss und Privat-Übersicht `monat` direkt
    /// lesen, statt über `enthaelt(_:)` zu filtern. Sie bekommen dadurch auch nach einer
    /// Quartalswahl in einem anderen Modul eine gültige Monatszahl zu sehen.
    var monat: Int {
        get { _monat }
        set {
            _monat = min(max(newValue, 1), 12)
            baue()
        }
    }
    /// 1…4, aus `monat` abgeleitet. Setzen springt auf den Anfang des Quartals.
    ///
    /// Bewusst **kein** eigenes gespeichertes Feld: zwei Felder für dieselbe Information könnten
    /// auseinanderlaufen.
    var quartal: Int {
        get { (_monat - 1) / 3 + 1 }
        set { monat = (min(max(newValue, 1), 4) - 1) * 3 + 1 }
    }

    init(
        modus: Modus = .monat,
        jahr: Int = appKalender.component(.year, from: Date()),
        monat: Int = appKalender.component(.month, from: Date())
    ) {
        _modus = modus
        _jahr = jahr
        _monat = min(max(monat, 1), 12)
        baue()
    }

    private mutating func baue() {
        periode =
            switch _modus {
            case .alle: nil
            case .jahr: .jahr(_jahr)
            case .quartal: .quartal(_jahr, (_monat - 1) / 3 + 1)
            case .monat: .monat(_jahr, _monat)
            }
    }

    /// Trifft `datum` auf den eingestellten Zeitraum zu?
    func enthaelt(_ datum: Date) -> Bool { periode?.enthaelt(datum) ?? true }

    var istAktuellerMonat: Bool {
        modus == .monat
            && jahr == appKalender.component(.year, from: Date())
            && monat == appKalender.component(.month, from: Date())
    }

    mutating func aufAktuellenMonat() { self = .dieserMonat() }
}
