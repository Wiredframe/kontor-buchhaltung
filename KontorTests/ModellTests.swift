import Testing
import Foundation
@testable import Kontor

/// Private Ausgaben speisen ausschließlich die Liquidität – aber sie dürfen dabei nicht
/// zwischen den Aggregaten hindurchfallen.
struct PrivateAusgabenAggregateTests {

    /// Regression: Eine private **einmalige** Ausgabe zählte in KEINER Auswertung.
    /// Aus der EÜR zu Recht (privat), aus `wiederkehrendBrutto` mangels Fixkosten-Art, und
    /// aus `privatVariabel`, weil dort nur Lebensmittel/Anschaffungen zählen. Genau das
    /// erzeugt „In Ausgaben verschieben" in den Anschaffungen: Das Geld war weg, „Frei
    /// verfügbar" blieb unverändert hoch.
    @Test func privateEinmaligeAusgabeFaelltNichtDurchsRaster() {
        let sneaker = ExpenseEntry(datum: tag(2026, 6, 12), bezeichnung: "Sneaker", anbieter: "",
                                   brutto: dez("180"), vst: 0, steuerart: .steuerfrei,
                                   betrieblich: false, art: .betriebsausgabe)
        let liste = [sneaker]
        #expect(liste.privatEinmaligBrutto(jahr: 2026, monat: 6) == dez("180"))
        // …und bleibt weiterhin aus EÜR und Vorsteuer draußen.
        #expect(Steuer.euerGewinn(einnahmen: [], ausgaben: [sneaker.posten], jahr: 2026) == 0)
        #expect(Steuer.vorsteuer([sneaker.posten], in: Periode.monat(2026, 6)) == 0)
    }

    /// Abgrenzung: Wiederkehrendes gehört zu den Fixkosten, nicht zu den einmaligen –
    /// sonst zählte es doppelt.
    @Test func wiederkehrendesZaehltNichtAlsEinmalig() {
        let liste = [
            ExpenseEntry(datum: tag(2026, 6, 1), bezeichnung: "Miete", anbieter: "",
                         brutto: dez("725"), vst: 0, steuerart: .steuerfrei,
                         betrieblich: false, art: .fixkosten),
            ExpenseEntry(datum: tag(2026, 6, 3), bezeichnung: "Netflix", anbieter: "",
                         brutto: dez("13"), vst: 0, steuerart: .steuerfrei,
                         betrieblich: false, art: .subscription),
        ]
        #expect(liste.privatEinmaligBrutto(jahr: 2026, monat: 6) == 0)
        #expect(liste.wiederkehrendBrutto(jahr: 2026, monat: 6, betrieblich: false) == dez("738"))
    }

    /// Betriebliches gehört in die EÜR, nicht in die privaten Kosten.
    @Test func betrieblicheEinmaligeAusgabeZaehltNichtAlsPrivat() {
        let liste = [ExpenseEntry(datum: tag(2026, 6, 12), bezeichnung: "Monitor", anbieter: "",
                                  brutto: dez("357"), vst: dez("57"), steuerart: .inland19,
                                  betrieblich: true, art: .betriebsausgabe)]
        #expect(liste.privatEinmaligBrutto(jahr: 2026, monat: 6) == 0)
    }

    /// Der Monat grenzt sauber ab.
    @Test func einmaligeAusgabeZaehltNurImEigenenMonat() {
        let liste = [ExpenseEntry(datum: tag(2026, 6, 12), bezeichnung: "Sneaker", anbieter: "",
                                  brutto: dez("180"), vst: 0, steuerart: .steuerfrei,
                                  betrieblich: false, art: .betriebsausgabe)]
        #expect(liste.privatEinmaligBrutto(jahr: 2026, monat: 5) == 0)
        #expect(liste.privatEinmaligBrutto(jahr: 2026, monat: 7) == 0)
        #expect(liste.privatEinmaligBrutto(jahr: 2025, monat: 6) == 0)
    }
}

/// Reine Datenmodell-Logik (ohne Datenbank): Status-/Zahlungsdatum-Konsistenz,
/// ESt-Satz-Overrides und Monatsabschluss-Status auf `YearSettings`/`Income`.
struct ModellTests {

    @Test func incomeStatusHaeltZahlungsdatumKonsistent() {
        let e = Income(kunde: "X", rnNetto: 100, ust: 19, rechnungsdatum: Date())
        e.setze(status: .bezahlt)
        #expect(e.status == .bezahlt && e.zahlungsdatum != nil)
        let datum = e.zahlungsdatum
        e.setze(status: .bezahlt)                       // erneut bezahlt → Datum bleibt
        #expect(e.zahlungsdatum == datum)
        e.setze(status: .offen)                         // offen → Datum gelöscht
        #expect(e.zahlungsdatum == nil)
        e.setze(status: .bezahlt); e.setze(status: .ausgefallen)
        #expect(e.zahlungsdatum == nil)                 // ausgefallen → kein Zufluss
        #expect(e.ausfalldatum != nil)                  // ausgefallen → Ausfalldatum gesetzt (§17 greift)
        e.setze(status: .bezahlt)
        #expect(e.ausfalldatum == nil)                  // wieder bezahlt → Ausfalldatum gelöscht
    }

    @Test func mischrechnungBucketsUndAggregate() {
        // Regel-Bucket 19 % + zweiter Bucket 7 % (Nutzungsrechte) auf einer Rechnung.
        let inc = Income(kunde: "Studio X", rnNetto: dez("2000"), ust: dez("380"),
                         rechnungsdatum: tag(2026, 5, 22), status: .offen,
                         satz: .satz19, rnNetto2: dez("900"), ust2: dez("63"), satz2: .satz7)
        #expect(inc.satzEffektiv == .satz19 && inc.hatZweitenSatz)
        #expect(inc.nettoGesamt == dez("2900") && inc.ustGesamt == dez("443"))
        #expect(inc.brutto == dez("3343"))
        // postenListe → zwei Posten je Satz; daraus trennt die Engine KZ 81/86.
        let p = inc.postenListe
        #expect(p.count == 2)
        #expect(p.contains { $0.satz == .satz19 && $0.rnNetto == dez("2000") })
        #expect(p.contains { $0.satz == .satz7 && $0.rnNetto == dez("900") })
    }

    @Test func einSatzRechnungHatNurEinenPosten() {
        // Altbestand ohne satz → 19 %; kein zweiter Bucket → genau ein Posten.
        let inc = Income(kunde: "Y", rnNetto: dez("1000"), ust: dez("190"), rechnungsdatum: tag(2026, 2, 1))
        #expect(inc.satz == nil && inc.satzEffektiv == .satz19 && !inc.hatZweitenSatz)
        #expect(inc.postenListe.count == 1)
        #expect(inc.nettoGesamt == dez("1000") && inc.brutto == dez("1190"))
    }

    @Test func vorlage7ProzentBuchtKorrekteVorsteuer() {
        // Ausgaben-Vorlage mit ermäßigtem Satz → Buchung zieht 7-%-Vorsteuer automatisch.
        let buch = Vorlage(bezeichnung: "Fachbuch", betragBrutto: dez("42.80"), steuerart: .inland7,
                           betrieblich: true, art: .betriebsausgabe)
        let b = buch.buchung(am: tag(2026, 4, 9))
        #expect(b.steuerart == .inland7 && b.vst == dez("2.80") && b.netto == dez("40.00"))
    }

    @Test func estSatzErbtVomVormonat() {
        let s = YearSettings(jahr: 2026, estPauschalSatz: dez("0.15"))
        #expect(s.estSatz(monat: 3) == dez("0.15"))     // nichts gesetzt → Jahres-Standard
        #expect(s.hatEigenenSatz(monat: 3) == false)
        s.estSatzProMonat["3"] = dez("0.19")
        #expect(s.estSatz(monat: 3) == dez("0.19"))     // eigener Wert
        #expect(s.estSatz(monat: 4) == dez("0.19"))     // April erbt März (Vormonat)
        #expect(s.estSatz(monat: 2) == dez("0.15"))     // Februar liegt davor → Standard
        #expect(s.hatEigenenSatz(monat: 4) == false)    // erbt nur, kein eigener Wert
    }

    @Test func kskBetraegeProMonat() {
        let s = YearSettings(jahr: 2026, estPauschalSatz: dez("0.15"))
        #expect(s.ksk(monat: 5) == 0)                   // nichts hinterlegt
        // Feb (synthetisch): RV 230,00 / KV 130,00 / PV 60,00 → Summe 420,00; JAE nur Info.
        s.setzeJAE(monat: 2, dez("36000"))
        s.setzeKSKBetrag(monat: 2, .rv, dez("230.00"))
        s.setzeKSKBetrag(monat: 2, .kv, dez("130.00"))
        s.setzeKSKBetrag(monat: 2, .pv, dez("60.00"))
        #expect(s.ksk(monat: 2) == dez("420.00"))
        #expect(s.kskTeile(monat: 2).rv == dez("230.00"))
        #expect(s.jae(monat: 2) == dez("36000"))
        #expect(s.hatEigenenKSK(monat: 2))
        // Mai erbt Februar (Beträge + JAE) → gleiche Summe, aber kein eigener Wert.
        #expect(s.ksk(monat: 5) == dez("420.00"))
        #expect(s.kskTeile(monat: 5).pv == dez("60.00"))
        #expect(s.jae(monat: 5) == dez("36000"))
        #expect(s.hatEigenenKSK(monat: 5) == false)
        #expect(s.ksk(monat: 1) == 0)                   // Januar liegt davor
        // Einzelner Zweig im Mai überschrieben → Rest erbt unabhängig weiter aus Februar.
        s.setzeKSKBetrag(monat: 5, .rv, dez("250"))
        #expect(s.kskTeile(monat: 5).rv == dez("250"))
        #expect(s.kskTeile(monat: 5).kv == dez("130.00"))
        #expect(s.hatEigenenKSK(monat: 5))
    }

    @Test func vorlageErzeugtDatierteBuchung() {
        // Private Fixkosten-Vorlage (steuerfrei) → Buchung ohne VSt, privat, Art Fixkosten.
        let miete = Vorlage(bezeichnung: "Miete", betragBrutto: 1000, steuerart: .steuerfrei,
                            betrieblich: false, art: .fixkosten)
        let b = miete.buchung(am: tag(2026, 6, 1))
        #expect(b.bezeichnung == "Miete" && b.brutto == 1000 && b.betrieblich == false)
        #expect(b.artEffektiv == .fixkosten && b.vst == 0 && b.datum == tag(2026, 6, 1))

        // Betriebliche Subscription (19 %) → VSt automatisch, Art Subscription.
        let adobe = Vorlage(bezeichnung: "Adobe", betragBrutto: dez("59.49"), steuerart: .inland19,
                            betrieblich: true, art: .subscription)
        let ab = adobe.buchung(am: tag(2026, 6, 1))
        #expect(ab.artEffektiv == .subscription && ab.betrieblich)
        #expect(ab.vst == Steuer.vorsteuerVorschlag(brutto: dez("59.49"), steuerart: .inland19))

        // Altbestand ohne `art` zählt als Betriebsausgabe.
        let alt = ExpenseEntry(datum: Date(), bezeichnung: "x", anbieter: "", brutto: 0, vst: 0, steuerart: .steuerfrei)
        #expect(alt.artEffektiv == .betriebsausgabe)
    }

    @Test func monatsabschlussStatus() {
        let s = YearSettings(jahr: 2026, estPauschalSatz: dez("0.15"))
        #expect(s.istAbgeschlossen(monat: 5) == false)
        s.abschlussProMonat["5"] = Date()
        #expect(s.istAbgeschlossen(monat: 5))
        #expect(s.abschlussDatum(monat: 5) != nil)
        #expect(s.istAbgeschlossen(monat: 6) == false)   // andere Monate unberührt
    }

    @Test func snapshotEinfrierenUndEntsperren() {
        let s = YearSettings(jahr: 2026, estPauschalSatz: dez("0.15"))
        #expect(s.snapshot(monat: 3) == nil)
        let snap = MonatsSnapshot(rn: dez("4000"), ust: dez("760.00"), vst: 0, ustKorrektur: 0,
                                  ksk: dez("420.00"), est: dez("537.00"), estKorrektur: 0,
                                  betriebsausgabenNetto: 0, umlagefaehig: 0, privatFix: 0, privatVariabel: 0)
        s.setzeSnapshot(monat: 3, snap)
        #expect(s.snapshot(monat: 3) == snap)            // JSON-Roundtrip stimmt
        s.loescheSnapshot(monat: 3)
        #expect(s.snapshot(monat: 3) == nil)             // entsperrt → wieder live
    }
}
