import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Verkleinert Bilder für die Anzeige und hält sie im Speicher, damit sie nicht jedes Mal neu dekodiert werden.
enum Vorschau {
    private static let speicher: NSCache<NSString, NSImage> = {
        let speicher = NSCache<NSString, NSImage>()
        speicher.totalCostLimit = 256 * 1024 * 1024
        return speicher
    }()

    private static func schluessel(_ url: URL, kante: Int) -> NSString {
        "\(kante)|\(url.path)" as NSString
    }

    /// Pixelmasse eines Bildes, gedreht wie angezeigt.
    static func masse(_ url: URL) -> (breite: Int, hoehe: Int)? {
        guard let quelle = CGImageSourceCreateWithURL(url as CFURL, nil),
              let werte = CGImageSourceCopyPropertiesAtIndex(quelle, 0, nil) as? [CFString: Any],
              let breite = werte[kCGImagePropertyPixelWidth] as? Int,
              let hoehe = werte[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (werte[kCGImagePropertyOrientation] as? Int ?? 1) >= 5 ? (hoehe, breite) : (breite, hoehe)
    }

    /// Schreibt ein Referenzbild als PNG ohne Metadaten. So liest mflux auch HEIC, und die Drehung stimmt.
    static func referenzSchreiben(von url: URL, nach ziel: URL, kante: Int) -> Bool {
        guard let quelle = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        let optionen: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: kante,
        ]
        guard let bild = CGImageSourceCreateThumbnailAtIndex(quelle, 0, optionen as CFDictionary),
              let ausgabe = CGImageDestinationCreateWithURL(ziel as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(ausgabe, bild, nil)
        return CGImageDestinationFinalize(ausgabe)
    }

    static func gespeichert(_ url: URL, kante: Int) -> NSImage? {
        speicher.object(forKey: schluessel(url, kante: kante))
    }

    /// Liest und dekodiert die Datei, gehört also nicht in den Hauptthread.
    static func laden(_ url: URL, kante: Int) -> NSImage? {
        guard let quelle = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let optionen: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: kante,
        ]
        guard let bild = CGImageSourceCreateThumbnailAtIndex(quelle, 0, optionen as CFDictionary) else { return nil }
        let vorschau = NSImage(cgImage: bild, size: NSSize(width: bild.width, height: bild.height))
        speicher.setObject(vorschau, forKey: schluessel(url, kante: kante), cost: bild.width * bild.height * 4)
        return vorschau
    }
}
