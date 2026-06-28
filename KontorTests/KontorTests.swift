import Testing

/// Platzhalter, damit das Test-Target von Anfang an baut und läuft.
/// Die echten Berechnungstests (USt, VSt, KSK, ESt …) kommen in Schritt 3.
struct KontorTests {
    @Test func projektGeruestSteht() {
        #expect(1 + 1 == 2)
    }
}
