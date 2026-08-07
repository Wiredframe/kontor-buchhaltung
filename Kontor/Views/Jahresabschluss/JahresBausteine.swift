import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Soll/Ist-Paar

/// Ein Steuerthema als Soll/Ist-Paar untereinander (oben die Berechnung, darunter das tatsächlich
/// Gezahlte) – bewusst nicht zweispaltig, weil die Zeilenzahl je Seite stark schwankt.
///
/// Trägt keine Themen-Überschrift mehr: seit jedes Thema eine eigene Seite hat, sagt der
/// Fenstertitel bereits, worum es geht.
struct ThemaPaar<Soll: View, Ist: View>: View {
    /// Querlink im Kopf der Berechnungs-Karte (z. B. USt → Modul „UStVA").
    var sollAktion: (() -> Void)? = nil
    /// Querlink im Kopf der Zahlungs-Karte – führt in den Ausgaben-Ledger, auf Jahr und
    /// Kategorie vorgefiltert. Genau die Zeilen, die darüber aufgelistet sind.
    var istAktion: (() -> Void)? = nil
    @ViewBuilder var soll: () -> Soll
    @ViewBuilder var ist: () -> Ist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Panel(titel: "Berechnung", aktion: sollAktion) { soll() }
            Panel(titel: "Tatsächlich gezahlt", aktion: istAktion) { ist() }
        }
    }
}

// MARK: - Steuer-Zahlung (read-only Lesezeile)

/// Eine Zeile der read-only Jahres-Zahlungsübersicht: Status, Datum, optional Notiz, Betrag.
/// Negative Beträge (Erstattungen) bleiben neutral – kein Rot; das Minuszeichen zeigt die
/// Erstattung. Erfasst/bearbeitet wird im Modul „Ausgaben“ (Vorsorge/Steuern).
struct ZahlungLeseZeile: View {
    let eintrag: TaxPayment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: eintrag.bezahlt ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(eintrag.bezahlt ? Color.green : .secondary)
            Text(eintrag.anzeigeDatum, format: .dateTime.day().month().year())
            if !eintrag.bemerkung.isEmpty {
                Text(eintrag.bemerkung).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(eintrag.betrag.euro).monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Belege-Export

/// Toolbar-Knopf der Jahresabschluss-Übersicht: bündelt alle Belege des Jahres als ZIP.
///
/// Hält sein eigenes `@Query`, damit `JahresSeite` frei von Export-Logik bleibt – nur die
/// Übersicht bindet ihn ein.
struct BelegeExportButton: View {
    @Query private var einnahmen: [Income]
    @Query private var ausgaben: [ExpenseEntry]
    @Environment(Zeitkontext.self) private var zeit

    private var jahr: Int { zeit.filter.jahr }

    /// Alle Belege des Jahres: **Ausgangsrechnungen** (Einnahmen, nach Rechnungsdatum – so werden
    /// sie auch abgelegt) **und** Eingangsbelege (Ausgaben, nach Abflussdatum).
    ///
    /// Die Einnahmen fehlten hier komplett – dabei sind die Ausgangsrechnungen bei einer
    /// Betriebsprüfung das zentrale Dokument. Wer nur Einnahmen-PDFs erfasst hatte, bekam einen
    /// leeren Export samt ausgegrautem Button („Keine Belege in 2026") und keinen Hinweis darauf,
    /// dass seine Rechnungen einfach nicht mitgesammelt werden.
    /// (`PurchaseEntry` bleibt bewusst draußen: private Einkäufe gehen das Finanzamt nichts an.)
    private var belegPfade: [String] {
        let p = Periode.jahr(jahr)
        let ausEinnahmen = einnahmen.filter { p.enthaelt($0.rechnungsdatum) }.compactMap { $0.belegPfad }
        let ausAusgaben = ausgaben.filter { p.enthaelt($0.datum) }.compactMap { $0.belegPfad }
        // Ein Beleg kann an mehreren Einträgen hängen – im ZIP soll er einmal landen.
        var gesehen = Set<String>()
        return (ausEinnahmen + ausAusgaben).filter { gesehen.insert($0).inserted && Belege.existiert($0) }
    }

    var body: some View {
        let anzahl = belegPfade.count
        return Button {
            exportieren()
        } label: {
            Label("Belege \(String(jahr)) exportieren", systemImage: "doc.zipper")
        }
        .disabled(anzahl == 0)
        .help(anzahl == 0 ? "Keine Belege in \(String(jahr))." : "\(anzahl) Belege als ZIP bündeln.")
    }

    private func exportieren() {
        let pfade = belegPfade
        guard !pfade.isEmpty else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Belege-\(jahr).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let ziel = panel.url else { return }
        try? Belege.exportiereAlsZip(pfade: pfade, nach: ziel)
    }
}
