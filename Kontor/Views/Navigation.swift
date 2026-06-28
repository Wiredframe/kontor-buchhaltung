import SwiftUI

/// Filter-Wunsch für einen Querlink in die Ausgaben-View (Art + Sparte). Der Zeitraum
/// läuft über den geteilten `Zeitkontext`; `nil` heißt jeweils „nicht einschränken".
struct AusgabenZiel: Equatable {
    var art: AusgabeArt?       // nil = alle Arten
    var betrieblich: Bool?     // nil = alle Sparten
}

/// Geteilter Navigationszustand: welches Modul ist in der Sidebar gewählt.
/// Erlaubt Querlinks (z. B. vom Monatsabschluss zu Betriebsausgaben).
@Observable
final class Navigation {
    var modul: Modul? = .dashboard
    /// Vorfilter-Wunsch, den die Ausgaben-View beim Erscheinen konsumiert und dann zurücksetzt.
    var ausgabenZiel: AusgabenZiel?

    /// Springt in die Ausgaben-View und filtert sie auf Monat + Art + Sparte vor.
    func zeigeAusgaben(jahr: Int, monat: Int, art: AusgabeArt? = nil,
                       betrieblich: Bool? = nil, zeit: Zeitkontext) {
        zeit.filter.modus = .monat
        zeit.filter.jahr = jahr
        zeit.filter.monat = monat
        ausgabenZiel = AusgabenZiel(art: art, betrieblich: betrieblich)
        modul = .betriebsausgaben
    }

    /// Springt in die Einnahmen-View und filtert sie auf den Monat vor.
    func zeigeEinnahmen(jahr: Int, monat: Int, zeit: Zeitkontext) {
        zeit.filter.modus = .monat
        zeit.filter.jahr = jahr
        zeit.filter.monat = monat
        modul = .einnahmen
    }

    /// Springt in die Ausgaben-View und filtert sie auf das ganze Jahr + Sparte (+ Art) vor.
    func zeigeAusgabenJahr(jahr: Int, art: AusgabeArt? = nil, betrieblich: Bool? = nil, zeit: Zeitkontext) {
        zeit.filter.modus = .jahr
        zeit.filter.jahr = jahr
        ausgabenZiel = AusgabenZiel(art: art, betrieblich: betrieblich)
        modul = .betriebsausgaben
    }
}

/// App-weiter Zeitraum (Jahr/Monat/Modus), den sich alle Views teilen – so bleibt
/// die Auswahl beim Wechsel zwischen Bereichen erhalten. Das Dashboard zeigt
/// bewusst immer „heute" und nutzt diesen Kontext nicht.
@Observable
final class Zeitkontext {
    var filter = Zeitfilter()
    /// Wählbarer Jahresbereich für die Dropdowns – beim Start aus den Daten abgeleitet.
    var jahre: ClosedRange<Int> = {
        let h = appKalender.component(.year, from: Date()); return h...(h + 1)
    }()
}
