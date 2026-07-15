import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Kontor

/// Der PDF-/Bild-Render-Pfad der OCR. Bisher komplett ungetestet: Alle bestehenden
/// BelegOCR-Tests arbeiten auf synthetischen Text-Fragmenten und fassen ihn nie an.
///
/// Genau hier saß ein Main-Thread-Verstoß: `rendere` zeichnete über `NSImage.lockFocus()` /
/// `NSGraphicsContext.current`, obwohl `analysiere` nonisoliert `async` ist (globaler Executor)
/// und der Beleg-Batch mehrere Belege parallel verarbeitet.
struct BelegRenderTests {

    /// Legt ein einseitiges Test-PDF an (schwarzes Rechteck auf der Seite).
    private func pdf(breite: CGFloat, hoehe: CGFloat, seiten: Int = 1) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kontor-test-\(UUID().uuidString).pdf")
        var box = CGRect(x: 0, y: 0, width: breite, height: hoehe)
        let ctx = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        for _ in 0..<seiten {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 10, y: 10, width: breite / 4, height: hoehe / 4))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    @Test func rendertPDFSeiteInDerErwartetenGroesse() throws {
        let url = try pdf(breite: 200, hoehe: 100)
        defer { try? FileManager.default.removeItem(at: url) }
        let bilder = BelegOCR.bilder(von: url)
        #expect(bilder.count == 1)
        let bild = try #require(bilder.first)
        #expect(bild.width == 500)      // 200 × 2,5
        #expect(bild.height == 250)     // 100 × 2,5
    }

    /// Mehrseitige PDFs: höchstens `maxSeiten` (Summen stehen oft erst auf Seite 2).
    @Test func liestHoechstensMaxSeiten() throws {
        let url = try pdf(breite: 200, hoehe: 100, seiten: 5)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(BelegOCR.bilder(von: url).count == BelegOCR.maxSeiten)
    }

    /// Regression: Der Render-Pfad muss **nebenläufig** und abseits des Main Threads halten –
    /// genau so ruft ihn der Beleg-Batch auf. Mit `NSImage.lockFocus()` teilten sich alle
    /// Aufrufe den Grafik-Kontext-Stack des Prozesses.
    @Test func rendertNebenlaeufigOhneMainThread() async throws {
        let url = try pdf(breite: 200, hoehe: 100)
        defer { try? FileManager.default.removeItem(at: url) }

        let ergebnisse = await withTaskGroup(of: (anzahl: Int, breite: Int).self) { gruppe in
            for _ in 0..<8 {
                gruppe.addTask {
                    let b = BelegOCR.bilder(von: url)
                    return (b.count, b.first?.width ?? 0)
                }
            }
            var alle: [(anzahl: Int, breite: Int)] = []
            for await r in gruppe { alle.append(r) }
            return alle
        }
        #expect(ergebnisse.count == 8)
        #expect(ergebnisse.allSatisfy { $0.anzahl == 1 && $0.breite == 500 })
    }

    /// Bilddateien laufen über ImageIO (statt über AppKits NSImage).
    @Test func liestBilddatei() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kontor-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let bild = try #require(ctx.makeImage())
        let ziel = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(ziel, bild, nil)
        #expect(CGImageDestinationFinalize(ziel))

        let gelesen = BelegOCR.bilder(von: url)
        #expect(gelesen.count == 1)
        #expect(gelesen.first?.width == 40)
    }

    /// Kaputte/fremde Dateien liefern nichts, statt zu werfen.
    @Test func unlesbareDateiLiefertNichts() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kontor-test-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("kein PDF, nur Text".utf8).write(to: url)
        #expect(BelegOCR.bilder(von: url).isEmpty)
    }

    @Test func fehlendeDateiLiefertNichts() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gibt-es-nicht-\(UUID().uuidString).pdf")
        #expect(BelegOCR.bilder(von: url).isEmpty)
    }
}
