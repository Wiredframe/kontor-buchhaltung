import SwiftData
import SwiftUI

/// Jahresabschluss → Steuererklärung: die Zahlen für die Umsatzsteuer-Jahreserklärung und die
/// Anlage EÜR (Bruttomethode), das Anlagenverzeichnis, Vorsorge und eine Vorprüfung dessen, was
/// vor der Abgabe geklärt sein sollte. Werte per Klick kopierbar.
///
/// Eigene Queries auf **alle** Steuerzahlungen: Die Zehn-Tage-Regel holt eine im Januar gezahlte
/// Q4-Vorauszahlung ins Vorjahr, `Jahreswerte.zahlungen` kennt nur die des gewählten Steuerjahres.
struct JahresErklaerungView: View {
    @Query private var einnahmen: [Income]
    @Query private var ausgaben: [ExpenseEntry]
    @Query private var zahlungen: [TaxPayment]
    @Query private var jahre: [YearSettings]
    @Query(sort: \ImportBuchung.buchungstag, order: .reverse) private var bankbuchungen: [ImportBuchung]

    var body: some View {
        JahresSeite(titel: "Steuererklärung") { w in
            let zp = zahlungen.map(\.posten)
            let ust = Steuer.ustJahreserklaerung(jahr: w.jahr, einnahmen: w.einP, ausgaben: w.ausP, zahlungen: zp)
            let euer = Steuer.euerErklaerung(
                jahr: w.jahr, einnahmen: w.einP, ausgaben: w.ausP, zahlungen: zp,
                einstellungen: { j in
                    let s = jahre.first { $0.jahr == j }
                    return (s?.ustvaRhythmus ?? .vierteljaehrlich, s?.dauerfristverlaengerung ?? false)
                })
            let punkte = Steuer.vorpruefung(
                jahr: w.jahr, einnahmen: einnahmen, ausgaben: ausgaben, zahlungen: zahlungen,
                hatJahresEinstellungen: w.hatJahresEinstellungen,
                letzteBankbuchung: bankbuchungen.first?.buchungstag,
                ustVoranmeldungen: w.ustJahr, kskSoll: w.kskGesamt)

            Text(
                "Kontor liefert die Größen, nicht die Formularzeilen – welche Zahl wohin gehört, ändert sich je Jahr. Vor der Abgabe gegen die eigenen Unterlagen prüfen."
            )
            .erklaerung()

            vorpruefung(punkte)
            ustKarte(ust, voranmeldungen: w.ustJahr)
            euerKarte(euer, nettoGewinn: w.a.gewinn)
            let anlagen = Steuer.anlagen(w.ausP, jahr: w.jahr)
            if !anlagen.isEmpty { AnlagenverzeichnisKarte(anlagen: anlagen) }
            vorsorgeKarte(w, zp)
        }
    }

    private func vorpruefung(_ punkte: [Pruefpunkt]) -> some View {
        Panel(titel: "Vorprüfung") {
            VStack(alignment: .leading, spacing: 10) {
                if punkte.isEmpty {
                    Label("Nichts aufgefallen.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                ForEach(punkte) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Label {
                            Text(p.text).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: p.warnung ? "exclamationmark.triangle.fill" : "info.circle")
                                .foregroundStyle(p.warnung ? Color.orange : Color.secondary)
                        }
                        if !p.details.isEmpty {
                            DisclosureGroup(p.details.count == 1 ? "1 Eintrag" : "\(p.details.count) Einträge") {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(p.details, id: \.self) { Text($0).font(.caption) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption).padding(.leading, 28)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ustKarte(_ u: UStJahreserklaerung, voranmeldungen: Decimal) -> some View {
        Panel(titel: "Umsatzsteuer-Jahreserklärung") {
            VStack(spacing: 2) {
                Kartenzeile(
                    label: "Steuerpflichtige Umsätze 19 % (Bemessung)", wert: u.bemessung19, icon: "eurosign.circle")
                Kartenzeile(label: "darauf Umsatzsteuer", wert: u.ust19, icon: "building.columns")
                if u.bemessung7 != 0 {
                    Kartenzeile(
                        label: "Steuerpflichtige Umsätze 7 % (Bemessung)", wert: u.bemessung7, icon: "eurosign.circle")
                    Kartenzeile(label: "darauf Umsatzsteuer", wert: u.ust7, icon: "building.columns")
                }
                if u.euLeistungen != 0 {
                    Kartenzeile(
                        label: "Sonstige Leistungen an EU-Unternehmer (nicht steuerbar)", wert: u.euLeistungen,
                        icon: "globe.europe.africa")
                }
                if u.drittland != 0 {
                    Kartenzeile(label: "Übrige nicht steuerbare Umsätze (Drittland)", wert: u.drittland, icon: "globe")
                }
                if u.rcBemessung != 0 {
                    Kartenzeile(
                        label: "§13b als Leistungsempfänger (Bemessung)", wert: u.rcBemessung,
                        icon: "arrow.left.arrow.right")
                    Kartenzeile(label: "darauf Umsatzsteuer", wert: u.rcUSt, icon: "building.columns")
                }
                Kartenzeile(
                    label: "Vorsteuer aus Rechnungen anderer Unternehmer", wert: u.vorsteuer, icon: "percent",
                    minus: u.vorsteuer != 0)
                if u.rcUSt != 0 {
                    Kartenzeile(
                        label: "Vorsteuer aus §13b-Leistungen", wert: u.rcUSt, icon: "percent", minus: u.rcUSt != 0)
                }
                Summenzeile(label: "Umsatzsteuer des Jahres", wert: u.steuer)
                Kartenzeile(
                    label: "Geleistete Vorauszahlungen", wert: u.vorauszahlungen, icon: "tray.and.arrow.up",
                    minus: u.vorauszahlungen != 0)
                Summenzeile(
                    label: u.nochZuZahlen >= 0 ? "Abschlusszahlung" : "Erstattung", wert: u.nochZuZahlen,
                    akzent: true)
                Text(
                    "Bemessungsgrundlagen des Jahres auf volle Euro gekürzt, die Steuer daraus gerechnet – auch bei §13b. Deshalb weicht die Jahressteuer um Cent von der Summe der Voranmeldungen ab (\(voranmeldungen.euro)); das ist so richtig. Vorauszahlungen sind die bezahlten USt-Zahlungen mit diesem Steuerjahr."
                )
                .erklaerung()
            }
        }
    }

    private func euerKarte(_ e: EUeRErklaerung, nettoGewinn: Decimal) -> some View {
        Panel(titel: "Anlage EÜR") {
            VStack(spacing: 2) {
                Kartenzeile(label: "Betriebseinnahmen (netto)", wert: e.einnahmenNetto, icon: "eurosign.circle")
                Kartenzeile(label: "Vereinnahmte Umsatzsteuer", wert: e.ustVereinnahmt, icon: "building.columns")
                if e.ustErstattet != 0 {
                    Kartenzeile(
                        label: "Vom Finanzamt erstattete Umsatzsteuer", wert: e.ustErstattet, icon: "arrow.uturn.left")
                }
                Summenzeile(label: "Summe Betriebseinnahmen", wert: e.einnahmen)
                Kartenzeile(
                    label: "Betriebsausgaben (netto, ohne AfA)", wert: e.ausgabenNetto, icon: "creditcard",
                    minus: e.ausgabenNetto != 0)
                if e.afa != 0 {
                    Kartenzeile(
                        label: "Abschreibungen (AfA)", wert: e.afa, icon: "chart.line.downtrend.xyaxis",
                        minus: e.afa != 0)
                }
                Kartenzeile(
                    label: "Gezahlte Vorsteuer", wert: e.vorsteuerGezahlt, icon: "percent",
                    minus: e.vorsteuerGezahlt != 0)
                Kartenzeile(
                    label: "An das Finanzamt gezahlte Umsatzsteuer", wert: e.ustGezahlt, icon: "building.columns",
                    minus: e.ustGezahlt != 0)
                Summenzeile(label: "Summe Betriebsausgaben", wert: e.ausgaben)
                Summenzeile(label: "Gewinn", wert: e.gewinn, akzent: true)
                Text(
                    "Bruttomethode nach Zu- und Abfluss: Umsatzsteuer und Vorsteuer laufen als Einnahme bzw. Ausgabe mit. Eine USt-Zahlung um den Jahreswechsel (bis 10. Januar, fällig im selben Zeitraum) zählt im Jahr, zu dem sie gehört. Der Netto-Gewinn der EÜR-Seite (\(nettoGewinn.euro)) weicht um den USt-Saldo des Jahres ab."
                )
                .erklaerung()
            }
        }
    }

    private func vorsorgeKarte(_ w: Jahreswerte, _ zp: [SteuerzahlungPosten]) -> some View {
        let p = Periode.jahr(w.jahr)
        let kskGezahlt = zp.filter { $0.kind == .ksk && $0.bezahlt && p.enthaelt($0.zahltag) }
            .reduce(Decimal(0)) { $0 + $1.betrag }
        return Panel(titel: "Vorsorge und Einkommensteuer") {
            VStack(spacing: 2) {
                Kartenzeile(label: "KSK Rentenversicherung (Monatswerte)", wert: w.ksk.rv, icon: "cross.case")
                Kartenzeile(label: "KSK Krankenversicherung (Monatswerte)", wert: w.ksk.kv, icon: "cross.case")
                Kartenzeile(label: "KSK Pflegeversicherung (Monatswerte)", wert: w.ksk.pv, icon: "cross.case")
                Summenzeile(label: "KSK gesamt", wert: w.kskGesamt)
                Kartenzeile(label: "KSK laut Abbuchungen", wert: kskGezahlt, icon: "tray.and.arrow.down")
                if w.vorsorgeSumme != 0 {
                    Kartenzeile(label: "Weitere Vorsorge (privat)", wert: w.vorsorgeSumme, icon: "cross.case")
                }
                Kartenzeile(label: "Geleistete ESt-Vorauszahlungen", wert: w.estVzBezahlt, icon: "percent")
                Text(
                    "Die KSK-Beiträge gehören in die Anlage Vorsorgeaufwand, die Vorauszahlungen gleicht das Finanzamt mit dem Bescheid ab."
                )
                .erklaerung()
            }
        }
    }
}
