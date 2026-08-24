import Foundation
import Testing

@testable import Kontor

// MARK: - Nicht steuerbare Auslandsumsätze (KZ 21 / KZ 45)

/// Leistungen an Unternehmer im EU-Ausland (`§3a Abs. 2 UStG`) sind in Deutschland nicht
/// steuerbar: Sie gehören in KZ 21, nicht in KZ 81, und dürfen die Zahllast nicht anfassen.
struct AuslandsumsatzTests {
    private static let q2 = Periode.quartal(2026, 2)

    /// Eine Design-Leistung an einen österreichischen Auftraggeber: 4.000 € netto, keine USt.
    private static func wienPosten(
        netto: String = "4000.00",
        rechnung: Date = tag(2026, 5, 12),
        status: InvoiceStatus = .offen,
        ausfall: Date? = nil
    ) -> EinnahmePosten {
        EinnahmePosten(
            rnNetto: dez(netto), ust: 0, satz: .satz19, umsatzart: .euReverseCharge,
            rechnungsdatum: rechnung, zahlungsdatum: nil, status: status, ausfalldatum: ausfall)
    }

    /// Ein Inlandsumsatz daneben, damit sichtbar wird, dass die beiden sich nicht vermischen.
    private static let inland = EinnahmePosten(
        rnNetto: dez("1000.00"), ust: dez("190.00"), satz: .satz19, umsatzart: .inland,
        rechnungsdatum: tag(2026, 5, 20), zahlungsdatum: nil, status: .offen, ausfalldatum: nil)

    @Test func euLeistungLandetInKZ21UndNichtInKZ81() {
        let e = Steuer.ustva(einnahmen: [Self.wienPosten(), Self.inland], ausgaben: [], periode: Self.q2)
        #expect(e.kz21 == dez("4000.00"))
        #expect(e.kz81 == dez("1000.00"))  // nur der Inlandsumsatz
        #expect(e.ust81 == dez("190.00"))
        #expect(e.kz45 == 0)
    }

    /// Der Kern: KZ 21 ist eine Meldung, keine Steuer. Die Zahllast muss identisch zu einem
    /// Quartal ganz ohne den EU-Umsatz sein.
    @Test func kz21LaesstDieZahllastUnberuehrt() {
        let mit = Steuer.ustva(einnahmen: [Self.wienPosten(), Self.inland], ausgaben: [], periode: Self.q2)
        let ohne = Steuer.ustva(einnahmen: [Self.inland], ausgaben: [], periode: Self.q2)
        #expect(mit.zahllast == ohne.zahllast)
        #expect(mit.zahllast == dez("190.00"))
    }

    @Test func drittlandLandetInKZ45() {
        let schweiz = EinnahmePosten(
            rnNetto: dez("2500.00"), ust: 0, satz: .satz19, umsatzart: .drittland,
            rechnungsdatum: tag(2026, 6, 3), zahlungsdatum: nil, status: .offen, ausfalldatum: nil)
        let e = Steuer.ustva(einnahmen: [schweiz], ausgaben: [], periode: Self.q2)
        #expect(e.kz45 == dez("2500.00"))
        #expect(e.kz21 == 0)
        #expect(e.kz81 == 0)
        #expect(e.zahllast == 0)
    }

    /// Regressionsschutz für den Altbestand: Vor der `Umsatzart` wurde ein Reverse-Charge-Umsatz
    /// als Inlandsrechnung mit „USt 0,00" erfasst. Solche Rechnungen dürfen nicht rückwirkend
    /// mit 19 % in KZ 81 rutschen – sie bleiben schlicht draußen (und gehören per Hand umgestellt).
    @Test func altbestandOhneUmsatzartBleibtAusDerBemessung() {
        let alt = Income(
            kunde: "Studio Wien", rnNetto: dez("4000.00"), ust: 0,
            rechnungsdatum: tag(2026, 5, 12))
        #expect(alt.umsatzartEffektiv == .inland)  // nil → Inland
        let e = Steuer.ustva(einnahmen: alt.postenListe, ausgaben: [], periode: Self.q2)
        #expect(e.kz81 == 0)
        #expect(e.ust81 == 0)
        #expect(e.kz21 == 0)  // ohne gesetzte Umsatzart auch keine Meldung
        #expect(e.zahllast == 0)
    }

    /// §17: Fällt die Forderung aus, mindert das KZ 21 im **Ausfallquartal** – nicht KZ 81.
    @Test func forderungsausfallMindertKZ21ImAusfallquartal() {
        let ausgefallen = Self.wienPosten(status: .ausgefallen, ausfall: tag(2026, 8, 4))
        let q2 = Steuer.ustva(einnahmen: [ausgefallen], ausgaben: [], periode: Self.q2)
        #expect(q2.kz21 == dez("4000.00"))  // Rechnungsquartal: voll gemeldet

        let q3 = Steuer.ustva(einnahmen: [ausgefallen], ausgaben: [], periode: Periode.quartal(2026, 3))
        #expect(q3.kz21 == dez("-4000.00"))  // Ausfallquartal: Berichtigung
        #expect(q3.kz81 == 0)
        #expect(q3.korrektur17 == 0)  // keine deutsche USt, also nichts zu korrigieren
        #expect(q3.zahllast == 0)
    }

    /// Rechnung und Ausfall im selben Quartal heben sich auf – die Kennzahl bleibt bei 0,
    /// statt den Umsatz erst zu melden und dann nie zu berichtigen.
    @Test func ausfallImSelbenQuartalHebtSichAuf() {
        let sofortAusgefallen = Self.wienPosten(status: .ausgefallen, ausfall: tag(2026, 6, 28))
        let e = Steuer.ustva(einnahmen: [sofortAusgefallen], ausgaben: [], periode: Self.q2)
        #expect(e.kz21 == 0)
    }

    /// Die Umsatzart hängt an der Rechnung, nicht am Satz-Bucket: Auch eine Mischrechnung
    /// (zwei Sätze) ist entweder ganz im Inland steuerbar oder gar nicht.
    @Test func mischrechnungErbtDieUmsatzartInBeidenBuckets() {
        let rn = Income(
            kunde: "Studio Wien", rnNetto: dez("3000.00"), ust: 0,
            rechnungsdatum: tag(2026, 5, 12),
            satz: .satz19, rnNetto2: dez("1000.00"), ust2: 0, satz2: .satz7,
            umsatzart: .euReverseCharge, ustIdNrKunde: "ATU12345678")
        #expect(rn.postenListe.count == 2)
        #expect(rn.postenListe.allSatisfy { $0.umsatzart == .euReverseCharge })
        let e = Steuer.ustva(einnahmen: rn.postenListe, ausgaben: [], periode: Self.q2)
        #expect(e.kz21 == dez("4000.00"))
        #expect(e.kz81 == 0 && e.kz86 == 0)
    }

    /// Der EU-Umsatz ist trotzdem Gewinn: Nicht steuerbar heißt nicht steuerfrei gestellt vom
    /// Einkommen. Für Soll-Umsatz und EÜR zählt er wie jede andere Rechnung.
    @Test func nichtSteuerbarerUmsatzZaehltTrotzdemZumGewinn() {
        let bezahlt = EinnahmePosten(
            rnNetto: dez("4000.00"), ust: 0, satz: .satz19, umsatzart: .euReverseCharge,
            rechnungsdatum: tag(2026, 5, 12), zahlungsdatum: tag(2026, 6, 1),
            status: .bezahlt, ausfalldatum: nil)
        #expect(Steuer.rnSoll([bezahlt], in: Self.q2) == dez("4000.00"))
        #expect(Steuer.ustSoll([bezahlt], in: Self.q2) == 0)
    }

    /// Die Invariante beim Umschalten: Steht die Rechnung auf EU-RC, darf keine deutsche USt
    /// hängen bleiben – sonst würde sie über `ustSoll` in Rücklage und Voranmeldung laufen.
    @Test func umschaltenAufReverseChargeLoeschtDieUmsatzsteuer() {
        let rn = Income(
            kunde: "Studio Wien", rnNetto: dez("4000.00"), ust: dez("760.00"),
            rechnungsdatum: tag(2026, 5, 12),
            satz: .satz19, rnNetto2: dez("1000.00"), ust2: dez("70.00"), satz2: .satz7)
        rn.umsatzart = .euReverseCharge
        rn.normalisiereUmsatzsteuer()
        #expect(rn.ust == 0 && rn.ust2 == 0)
        #expect(rn.nettoGesamt == dez("5000.00"))  // Netto bleibt unangetastet
        #expect(rn.brutto == dez("5000.00"))

        // Umgekehrt bleibt eine Inlandsrechnung unberührt.
        let inland = Income(
            kunde: "Agentur Berlin", rnNetto: dez("1000.00"), ust: dez("190.00"),
            rechnungsdatum: tag(2026, 5, 20))
        inland.normalisiereUmsatzsteuer()
        #expect(inland.ust == dez("190.00"))
    }
}

// MARK: - Zusammenfassende Meldung

struct ZMTests {
    private static let q2 = Periode.quartal(2026, 2)

    private static func posten(
        _ kunde: String, _ uid: String?, _ netto: String,
        rechnung: Date = tag(2026, 5, 12),
        status: InvoiceStatus = .offen, ausfall: Date? = nil
    ) -> ZMPosten {
        ZMPosten(
            kunde: kunde, ustIdNr: uid, netto: dez(netto),
            rechnungsdatum: rechnung, status: status, ausfalldatum: ausfall)
    }

    @Test func gruppiertNachUstIdNrUndSummiert() {
        let m = Steuer.zm(
            [
                Self.posten("Studio Wien", "ATU12345678", "4000.00"),
                Self.posten("Studio Wien", "ATU12345678", "1500.00", rechnung: tag(2026, 6, 2)),
                Self.posten("Bureau Paris", "FR12345678901", "2000.00", rechnung: tag(2026, 4, 8)),
            ], in: Self.q2)
        #expect(m.zeilen.count == 2)
        #expect(m.zeilen[0].ustIdNr == "ATU12345678")
        #expect(m.zeilen[0].netto == dez("5500.00"))
        #expect(m.zeilen[0].anzahl == 2)
        #expect(m.zeilen[0].kunden == ["Studio Wien"])
        #expect(m.zeilen[1].ustIdNr == "FR12345678901")
        #expect(m.summe == dez("7500.00"))
        #expect(m.istVollstaendig)
        #expect(!m.istLeer)
    }

    /// Verschieden geschriebene UIDs sind derselbe Kunde – sonst stünde er zweimal in der Meldung.
    @Test func normalisiertSchreibweiseDerUstIdNr() {
        #expect(Steuer.normalisiere("atu 1234-5678") == "ATU12345678")
        #expect(Steuer.normalisiere("  ") == nil)
        #expect(Steuer.normalisiere(nil) == nil)

        let m = Steuer.zm(
            [
                Self.posten("Studio Wien", "ATU12345678", "4000.00"),
                Self.posten("Studio Wien", "atu 1234 5678", "1000.00"),
            ], in: Self.q2)
        #expect(m.zeilen.count == 1)
        #expect(m.zeilen[0].netto == dez("5000.00"))
    }

    /// Ohne UID ist die Meldung nicht abgabefähig: Die Rechnung wird nicht stillschweigend
    /// mitsummiert, sondern separat ausgewiesen.
    @Test func rechnungOhneUstIdNrWirdAusgewiesen() {
        let m = Steuer.zm(
            [
                Self.posten("Studio Wien", "ATU12345678", "4000.00"),
                Self.posten("Atelier Graz", nil, "900.00"),
                Self.posten("Atelier Graz", "", "100.00"),
            ], in: Self.q2)
        #expect(m.zeilen.count == 1)
        #expect(m.summe == dez("4000.00"))
        // Der Betrag muss mit: 900 + 100, beide ohne verwertbare UID.
        #expect(m.ohneUstIdNr == [ZMLuecke(kunde: "Atelier Graz", netto: dez("1000.00"))])
        #expect(m.luecke == dez("1000.00"))
        // Erst Summe + Lücke ergibt wieder KZ 21.
        #expect(m.summe + m.luecke == dez("5000.00"))
        #expect(!m.istVollstaendig)
    }

    /// Die Meldung muss Betrag für Betrag zu KZ 21 passen – auch beim Forderungsausfall.
    @Test func stimmtMitKZ21Ueberein() {
        let ausfall = tag(2026, 8, 4)
        let einnahme = Income(
            kunde: "Studio Wien", rnNetto: dez("4000.00"), ust: 0,
            rechnungsdatum: tag(2026, 5, 12), status: .ausgefallen, ausfalldatum: ausfall,
            umsatzart: .euReverseCharge, ustIdNrKunde: "ATU12345678")
        let zmPosten = [einnahme.zmPosten].compactMap { $0 }

        for q in [2, 3] {
            let periode = Periode.quartal(2026, q)
            let kz21 = Steuer.ustva(einnahmen: einnahme.postenListe, ausgaben: [], periode: periode).kz21
            #expect(Steuer.zm(zmPosten, in: periode).summe == kz21)
        }
    }

    /// Regression: Die View beschriftete die Summe fest mit „= KZ 21". Fehlt eine UID, ist die
    /// Summe aber um `luecke` kleiner – ausgerechnet dann log das Label. `istVollstaendig` ist
    /// der Schalter, an dem Label und MCP-Text hängen; erst `summe + luecke` ergibt KZ 21.
    @Test func summeGleichKZ21NurWennAlleUIDsDaSind() {
        let mitUID = Income(
            kunde: "Studio Wien", rnNetto: dez("2060.00"), ust: 0,
            rechnungsdatum: tag(2026, 5, 12),
            umsatzart: .euReverseCharge, ustIdNrKunde: "ATU12345678")
        let ohneUID = Income(
            kunde: "Atelier Graz", rnNetto: dez("500.00"), ust: 0,
            rechnungsdatum: tag(2026, 5, 14), umsatzart: .euReverseCharge)

        let kz21 = Steuer.ustva(
            einnahmen: mitUID.postenListe + ohneUID.postenListe, ausgaben: [], periode: Self.q2
        ).kz21
        #expect(kz21 == dez("2560.00"))

        let unvollstaendig = Steuer.zm([mitUID, ohneUID].compactMap(\.zmPosten), in: Self.q2)
        #expect(!unvollstaendig.istVollstaendig)
        #expect(unvollstaendig.summe == dez("2060.00"))  // nur die meldbare Zeile
        #expect(unvollstaendig.luecke == dez("500.00"))
        #expect(unvollstaendig.summe + unvollstaendig.luecke == kz21)

        // UID nachgetragen → Summe deckt sich wieder mit KZ 21, Lücke weg.
        ohneUID.ustIdNrKunde = "ATU87654321"
        let vollstaendig = Steuer.zm([mitUID, ohneUID].compactMap(\.zmPosten), in: Self.q2)
        #expect(vollstaendig.istVollstaendig)
        #expect(vollstaendig.luecke == 0)
        #expect(vollstaendig.summe == kz21)
    }

    /// Der Fall aus dem Screenshot: **eine einzige** EU-Rechnung, und der fehlt die UID.
    /// Dann steht KZ 21 auf dem vollen Betrag, während die ZM-Summe 0 zeigt.
    @Test func einzigeRechnungOhneUIDLaesstDieSummeAufNull() {
        let ohneUID = Income(
            kunde: "DERTOUR Austria GmbH", rnNetto: dez("2060.00"), ust: 0,
            rechnungsdatum: tag(2026, 5, 12), umsatzart: .euReverseCharge)
        let m = Steuer.zm([ohneUID].compactMap(\.zmPosten), in: Self.q2)
        #expect(m.zeilen.isEmpty)
        #expect(m.summe == 0)
        #expect(!m.istLeer)  // es gibt etwas zu tun – nur nicht meldbar
        #expect(!m.istVollstaendig)
        #expect(m.luecke == dez("2060.00"))
    }

    @Test func inlandUndDrittlandLoesenKeineMeldungAus() {
        let inland = Income(
            kunde: "Agentur Berlin", rnNetto: dez("1000.00"), ust: dez("190.00"),
            rechnungsdatum: tag(2026, 5, 20))
        let schweiz = Income(
            kunde: "Studio Zürich", rnNetto: dez("2500.00"), ust: 0,
            rechnungsdatum: tag(2026, 6, 3), umsatzart: .drittland)
        #expect(inland.zmPosten == nil)
        #expect(schweiz.zmPosten == nil)
        #expect(Steuer.zm([], in: Self.q2).istLeer)
    }
}
