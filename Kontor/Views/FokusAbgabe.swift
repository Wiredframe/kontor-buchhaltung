import AppKit
import SwiftUI

/// Gibt den Tastaturfokus eines Textfelds ab, sobald irgendwo anders hingeklickt wird.
///
/// **Das Problem.** In SwiftUI auf macOS behält ein `TextField` (und das Suchfeld von
/// `.searchable`) seinen Fokus, bis eine andere Eingabestelle ihn übernimmt. Klickt man in eine
/// Tabelle, auf eine Karte oder einfach in eine leere Fläche, blinkt der Cursor im Feld weiter
/// und ⌘A oder die Pfeiltasten wirken noch dort. Das entspricht nicht dem, was man von Mac-Apps
/// gewohnt ist.
///
/// **Warum zentral statt je View.** Die App hat gut ein Dutzend Inspektor-Formulare mit eigenem
/// `@FocusState`. Ein `onTapGesture` je View wäre nicht nur Wiederholung, es griffe auch zu
/// kurz: Tabellen und Listen verarbeiten Klicks selbst, ein Hintergrund-Tap bekommt sie nie zu
/// sehen. Ein lokaler Event-Monitor sieht dagegen **jeden** Mausklick im Prozess, bevor ihn
/// jemand verarbeitet.
///
/// **Die Bedingung ist eng gewählt**, damit der Monitor nicht mehr tut als nötig:
/// Zurückgesetzt wird nur, wenn gerade wirklich in einem Textfeld geschrieben wird (der
/// First Responder ist dann der Feldeditor, ein `NSTextView`) **und** der Klick nicht wieder
/// in einer Texteingabe landet. Ein Klick von einem Feld ins nächste bleibt damit AppKit
/// überlassen, das ihn von sich aus richtig macht.
enum FokusAbgabe {
    private static var monitor: Any?

    /// Richtet den Monitor einmalig ein. Mehrfache Aufrufe sind wirkungslos.
    @MainActor static func einrichten() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            pruefe(event)
            return event  // Der Klick läuft unverändert weiter.
        }
    }

    @MainActor private static func pruefe(_ event: NSEvent) {
        guard let fenster = event.window,
            // Nur eingreifen, wenn gerade getippt wird: Beim Bearbeiten eines `TextField` ist
            // der First Responder der Feldeditor des Fensters, nicht das Feld selbst.
            let editor = fenster.firstResponder as? NSTextView, editor.isFieldEditor
        else { return }

        let ziel = fenster.contentView?.hitTest(event.locationInWindow)
        guard !istTexteingabe(ziel) else { return }

        // `nil` macht das Fenster selbst zum First Responder – der Feldeditor gibt ab und das
        // Feld übernimmt seinen Wert, genau wie bei einem Tab-Wechsel.
        fenster.makeFirstResponder(nil)
    }

    /// Ist das angeklickte Element (oder eines seiner Elternelemente) eine Texteingabe?
    ///
    /// Die Elternkette muss mitgeprüft werden, weil ein Klick je nach Feld auf einer inneren
    /// Hilfsansicht landet statt auf dem `NSTextField` selbst.
    private static func istTexteingabe(_ ansicht: NSView?) -> Bool {
        var aktuell = ansicht
        while let a = aktuell {
            if a is NSTextField || a is NSTextView || a is NSSearchField { return true }
            aktuell = a.superview
        }
        return false
    }
}
