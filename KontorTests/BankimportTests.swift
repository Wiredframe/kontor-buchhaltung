import Testing
import Foundation
@testable import Kontor

/// Parser-Tests gegen den Sparkasse-CSV-CAMT-V8-Export. **Synthetische** Zeilen
/// (kanonische Beispiel-IBAN, erfundene Händler/Kunden) – keine echten Kontodaten.
struct BankimportTests {

    // Header + 4 synthetische Zeilen (Karte, Apple Pay, SEPA-Lastschrift, Eingang).
    private let csv = """
    "Auftragskonto";"Buchungstag";"Valutadatum";"Buchungstext";"Verwendungszweck";"Glaeubiger ID";"Mandatsreferenz";"Kundenreferenz (End-to-End)";"Sammlerreferenz";"Lastschrift Ursprungsbetrag";"Auslagenersatz Ruecklastschrift";"Beguenstigter/Zahlungspflichtiger";"Kontonummer/IBAN";"BIC (SWIFT-Code)";"Betrag";"Waehrung";"Info"
    "DE89370400440532013000";"25.06.26";"25.06.26";"KARTENZAHLUNG";"Anthropic Claude Subscription";"";"";"ANTHRO20260624TESTREF0001";"";"";"";"ANTHROPIC. CLAUDE SUB/San Francisco/US";"DE89100000000000000001";"HELADEFFXXX";"-73,95";"EUR";"Umsatz gebucht"
    "DE89370400440532013000";"25.06.26";"25.06.26";"DIGITALE KARTE (APPLE PAY)";"Einkauf";"";"";"TESTREF20260624BIOMARKT002";"";"";"";"BIOMARKT NORD/INVALIDENSTR. 1/BERLIN/DE";"DE89100000000000000002";"WELADEDDXXX";"-10,22";"EUR";"Umsatz gebucht"
    "DE89370400440532013000";"25.06.26";"25.06.26";"SEPA-ELV-LASTSCHRIFT";"DROGERIE NORD BERLIN Einzug";"DE00ZZZ00000000042";"M-TESTMANDAT-003";"TESTREF20260623DROGERIE003";"";"";"";"DROGERIE NORD BERLIN";"DE89100000000000000003";"COBADEFF";"-55,84";"EUR";"Umsatz gebucht"
    "DE89370400440532013000";"15.06.26";"15.06.26";"GUTSCHRIFT ÜBERWEISUNG";"RE 202606011";"";"";"";"";"";"";"KRANZLER DIGITAL GMBH";"DE89100000000000000004";"BYLADEM1SWU";"1.332,80";"EUR";"Umsatz gebucht"
    """

    @Test func parstAlleZeilen() {
        let b = Bankimport.parse(text: csv)
        #expect(b.count == 4)   // Header wird nicht als Buchung gezählt
    }

    // MARK: - Malformed Input (nichts still verschlucken, nichts still verfälschen)

    /// Regression: Ein englisch formatierter Betrag wurde stillschweigend **hundertfach**
    /// zu groß gebucht – die Punkte galten bedingungslos als Tausendertrenner, aus
    /// „1332.80" wurde 133.280,00 €. Jetzt wird die Zeile abgewiesen statt falsch gebucht.
    @Test func englischFormatierterBetragWirdAbgewiesenStattVerhundertfacht() {
        let e = Bankimport.lies(text: """
        "Buchungstag";"Betrag";"Waehrung"
        "25.06.26";"1332.80";"EUR"
        """)
        #expect(e.buchungen.isEmpty)
        #expect(e.verworfen == 1)
        #expect(e.kopfErkannt)
    }

    /// Regression: `Decimal(string:)` parst Präfixe – „12abc" ergab 12.
    @Test func betragsMuellWirdAbgewiesenStattTeilweiseGeparst() {
        let e = Bankimport.lies(text: """
        "Buchungstag";"Betrag";"Waehrung"
        "25.06.26";"12abc";"EUR"
        "25.06.26";"1.33,80";"EUR"
        "25.06.26";"1,234";"EUR"
        """)
        #expect(e.buchungen.isEmpty)
        #expect(e.verworfen == 3)
    }

    /// Gegenprobe: Alle gültigen deutschen Schreibweisen müssen weiter durchgehen.
    @Test(arguments: [("-1.332,80", "-1332.80"), ("1.332,80", "1332.80"), ("133280", "133280"),
                      ("1332,8", "1332.80"), ("12.345.678,90", "12345678.90"),
                      ("0,00", "0"), ("-0,01", "-0.01"), ("5", "5")])
    func gueltigeDeutscheBetraege(_ eingabe: String, _ erwartet: String) throws {
        let e = Bankimport.lies(text: """
        "Buchungstag";"Betrag";"Waehrung"
        "25.06.26";"\(eingabe)";"EUR"
        """)
        #expect(e.verworfen == 0)
        #expect(try #require(e.buchungen.first).betrag == dez(erwartet))
    }

    /// Regression: `Calendar.date(from:)` ist lenient und rollt Unsinn still weiter –
    /// „32.13.26" wurde zum 01.02.2027, „01.00.26" sogar ins **Vorjahr**. Eine so verrutschte
    /// Buchung landete im falschen Monat und damit in der falschen UStVA-Periode.
    @Test(arguments: ["32.13.26", "31.02.26", "01.00.26", "29.02.25", "00.06.26", "25.13.26"])
    func unmoeglichesDatumWirdAbgewiesenStattGerollt(_ datum: String) {
        let e = Bankimport.lies(text: """
        "Buchungstag";"Betrag";"Waehrung"
        "\(datum)";"-10,00";"EUR"
        """)
        #expect(e.buchungen.isEmpty)
        #expect(e.verworfen == 1)
    }

    /// Gegenprobe: Der echte Schalttag muss durchgehen.
    @Test func schalttagBleibtGueltig() throws {
        let e = Bankimport.lies(text: """
        "Buchungstag";"Betrag";"Waehrung"
        "29.02.24";"-10,00";"EUR"
        """)
        #expect(try #require(e.buchungen.first).buchungstag == tag(2024, 2, 29))
    }

    /// Regression: Eine Datei mit fremdem/fehlendem Kopf lieferte ein leeres Array – für den
    /// Nutzer nicht von „keine neuen Buchungen" zu unterscheiden. Jetzt sagt `kopfErkannt`,
    /// dass die Datei gar nicht verstanden wurde.
    @Test func fremderKopfWirdAlsSolcherErkannt() {
        let e = Bankimport.lies(text: """
        "Datum";"Umsatz";"Text"
        "25.06.26";"-10,00";"Irgendwas"
        """)
        #expect(e.kopfErkannt == false)
        #expect(e.buchungen.isEmpty)
    }

    @Test func leereDateiIstKeinErkannterKopf() {
        let e = Bankimport.lies(text: "")
        #expect(e.kopfErkannt == false)
        #expect(e.buchungen.isEmpty && e.verworfen == 0)
    }

    /// Teilkorrupte CSV: die guten Zeilen kommen durch, die kaputten werden **gezählt**.
    @Test func teilkorrupteCSVMeldetDieVerworfenenZeilen() {
        let e = Bankimport.lies(text: """
        "Buchungstag";"Betrag";"Waehrung"
        "25.06.26";"-10,00";"EUR"
        "99.99.99";"-20,00";"EUR"
        "26.06.26";"kaputt";"EUR"
        "27.06.26";"-30,00";"EUR"

        """)
        #expect(e.buchungen.count == 2)
        #expect(e.verworfen == 2)     // Leerzeile am Ende zählt nicht als Fehler
        #expect(e.kopfErkannt)
    }

    @Test func ersteZeileKomplett() throws {
        let b = Bankimport.parse(text: csv)
        let a = try #require(b.first)
        #expect(a.betrag == dez("-73.95"))
        #expect(a.buchungstext == "KARTENZAHLUNG")
        #expect(a.gegenpartei.hasPrefix("ANTHROPIC. CLAUDE SUB"))
        #expect(a.istEingang == false)
        #expect(a.buchungstag == tag(2026, 6, 25))
        // End-to-End-Ref führt den Schlüssel an, Datum+Betrag folgen (gegen wiederkehrende Fixref)
        #expect(a.dedupSchluessel.hasPrefix("k:ANTHRO20260624TESTREF0001|"))
    }

    @Test func eingangMitTausenderUndZweck() throws {
        let kunde = try #require(Bankimport.parse(text: csv).first { $0.istEingang })
        #expect(kunde.betrag == dez("1332.80"))        // „1.332,80" korrekt
        #expect(kunde.verwendungszweck == "RE 202606011")
    }

    @Test func haendlerSchluesselGlaeubigerVorName() {
        let b = Bankimport.parse(text: csv)
        let drogerie = b.first { $0.gegenpartei.contains("DROGERIE") }
        let biomarkt = b.first { $0.gegenpartei.contains("BIOMARKT") }
        #expect(drogerie?.haendlerSchluessel == "gl:DE00ZZZ00000000042")   // Lastschrift → Gläubiger-ID
        #expect(biomarkt?.haendlerSchluessel == "biomarkt nord")           // Karte → normalisierter Name
    }

    @Test func latin1Umlaute() throws {
        // Bank liefert ISO-8859-1; Umlaute müssen korrekt dekodiert werden.
        let mini = """
        "Buchungstag";"Betrag";"Beguenstigter/Zahlungspflichtiger"
        "01.06.26";"-2,65";"DM Drogerie/Berlin/DE"
        "02.06.26";"-9,99";"Bäckerei Müller"
        """
        let data = try #require(mini.data(using: .isoLatin1))
        let b = Bankimport.parse(data)
        #expect(b.count == 2)
        #expect(b.last?.gegenpartei == "Bäckerei Müller")
        #expect(b.last?.betrag == dez("-9.99"))
    }

    @Test func anzeigenameNormalCase() {
        let b = Bankimport.parse(text: csv)
        #expect(b.first?.anzeigename == "Anthropic. Claude Sub")        // ALL-CAPS → Title Case
        #expect(b.first { $0.gegenpartei.contains("BIOMARKT") }?.anzeigename == "Biomarkt Nord")
        #expect(b.first { $0.istEingang }?.anzeigename == "Kranzler Digital Gmbh")
        // Matching-Schlüssel bleibt unberührt (case-insensitiv, aus dem Rohfeld)
        #expect(b.first { $0.gegenpartei.contains("BIOMARKT") }?.haendlerSchluessel == "biomarkt nord")
        #expect(b.first?.dedupSchluessel.hasPrefix("k:ANTHRO20260624TESTREF0001|") == true)
    }

    @Test func normalCaseLaesstGemischtesInRuhe() {
        #expect(Bankimport.normalCase("KRANZLER DIGITAL GMBH") == "Kranzler Digital Gmbh")
        #expect(Bankimport.normalCase("Cafe Märznhof GmbH") == "Cafe Märznhof GmbH")   // gemischt bleibt
        #expect(Bankimport.normalCase("902 E-CENTER BERLIN") == "902 E-Center Berlin")
    }
}
