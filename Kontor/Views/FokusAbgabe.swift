import AppKit
import SwiftUI

/// Gibt den Tastaturfokus eines Textfelds ab, sobald irgendwo anders hingeklickt wird, und
/// reicht ihn beim Klick in eine Tabelle an diese weiter.
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
        guard let fenster = event.window else { return }
        let ziel = fenster.contentView?.hitTest(event.locationInWindow)

        // Beim Bearbeiten eines `TextField` ist der First Responder der Feldeditor des Fensters,
        // nicht das Feld selbst. Landet der Klick außerhalb einer Texteingabe, gibt das Feld ab:
        // `nil` macht das Fenster zum First Responder, der Feldeditor übernimmt den Wert ins
        // Feld, genau wie bei einem Tab-Wechsel.
        if let editor = fenster.firstResponder as? NSTextView, editor.isFieldEditor,
            !istTexteingabe(ziel)
        {
            fenster.makeFirstResponder(nil)
        }

        // Klick in eine Tabelle oder Liste: Tastaturfokus dorthin. Siehe `uebergibTabellenfokus`.
        if let tabelle = tabelle(ziel) {
            DispatchQueue.main.async { uebergibTabellenfokus(tabelle, in: fenster) }
        }
    }

    /// Macht die angeklickte Tabelle zum First Responder, falls AppKit das nicht selbst tat.
    ///
    /// **Das zweite Problem.** Auf macOS 26/27 wird eine SwiftUI-`Table` (und die Sidebar-`List`)
    /// durch einen Klick nicht mehr zuverlässig zum First Responder: Die Zeile ist zwar gewählt,
    /// aber grau statt blau, und die Pfeiltasten wirken nicht. Reproduziert mit einer leeren
    /// Minimal-App (`NavigationSplitView` + `Table`) – es liegt also nicht an Kontor. Der
    /// Zustand ist wechselhaft („manchmal geht es"), weil er davon abhängt, wer vorher den
    /// Fokus hatte; nach jedem Modulwechsel beginnt es von vorn.
    ///
    /// Die Übergabe läuft **nach** dem Klick (`async`), damit die Tabelle Auswahl und
    /// Doppelklick zuerst selbst verarbeitet; wer den Fokus schon hat, wird nicht angefasst.
    /// Eingaben in der Tabelle (z. B. ein Menü in einer Zelle) bleiben unberührt: der Klick
    /// hat den Fokus dann bereits an ein anderes Element vergeben, das kein Feldeditor ist.
    @MainActor private static func uebergibTabellenfokus(_ tabelle: NSTableView, in fenster: NSWindow) {
        guard tabelle.window === fenster, tabelle.acceptsFirstResponder else { return }
        let aktuell = fenster.firstResponder
        // Liegt der Fokus schon in der Tabelle (sie selbst, ein Steuerelement in einer Zelle
        // oder der Feldeditor einer Zelle), nichts anfassen. Alles andere (Fenster, Sidebar,
        // ein anderes Modul) gibt an die angeklickte Tabelle ab.
        if let ansicht = aktuell as? NSView, ansicht.isDescendant(of: tabelle) { return }
        fenster.makeFirstResponder(tabelle)
    }

    /// Die Tabelle (`Table`) oder Outline (Sidebar-`List`), in der der Klick landete.
    private static func tabelle(_ ansicht: NSView?) -> NSTableView? {
        var aktuell = ansicht
        while let a = aktuell {
            if let t = a as? NSTableView { return t }
            aktuell = a.superview
        }
        return nil
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
