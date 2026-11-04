import AppKit
import SwiftUI

/// Bildschirmfotos des Hauptfensters für das README, ohne dass ein Fenster auf dem Bildschirm erscheint. Alles liegt
/// im Testordner: Das Modell kommt vom lokalen Testserver, das fertige Bild legt testlauf.sh als quelle.png hinein.
/// Nur von Hand: zsh tests/testlauf.sh screenshots, die Bilder kommen in einen eigenen Ordner.
///
/// macOS zeichnet die Seitenleiste aus Glas offscreen nicht, ihr Inhalt bleibt leer. Darum liegt über ihr dieselbe
/// Seitenleiste der App, einzeln gezeichnet, auf einer hellen Fläche in der Form der Glasfläche. Die Ampel oben links
/// erscheint grau, weil das Fenster nie aktiv wird.
@MainActor
enum Bildschirmfotos {
    static let prompt = "A large stainless steel pot of boiling water on a gas stove, several fresh yellow corn cobs bobbing in the bubbling water, rising steam, warm evening kitchen light, close-up food photography, shallow depth of field, highly detailed"
    static let negativ = "blurry, low quality, deformed, text, watermark, cartoon"
    static let groesse = CGSize(width: 1280, height: 800)

    static func ausfuehren(_ bericht: Pruefbericht) async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
        // Die Frage nach neuen Versionen gehört nicht ins Bild.
        Pfade.speicher.set(false, forKey: Versionspruefung.Schluessel.erlaubt)

        let bereit = await Hilfe.einrichten()
        bericht.pruefen("Modell vom Testserver eingerichtet", bereit, "\(Modellinstallation.gemeinsam.zustand)")
        guard bereit, let gruppe = ergebnisAnlegen(bericht) else { return }

        let generator = Generator.gemeinsam
        generator.ergebnisseLaden()
        let vorgaben = Vorgaben.gemeinsam
        await vorgaben.moduleNeuLaden()
        vorgaben.stufeAnwenden(.beste)
        vorgaben.format = .quer
        vorgaben.anzahl = 1
        vorgaben.festerStartwert = false
        vorgaben.prompt = prompt
        vorgaben.negativ = ""

        // 1: Das fertige Bild gross in der Ergebnisansicht.
        let ergebnis = await zeichnen("screenshot-result", seitenleiste: .lauf(gruppe)) {
            generator.sprungZu = gruppe
        }
        bericht.pruefen("Ergebnisansicht gezeichnet", ergebnis)

        // 2: Neues Bild mit Prompt und Negativprompt, bereit zum Erzeugen.
        vorgaben.negativ = negativ
        let neu = await zeichnen("screenshot-prompt", seitenleiste: .neu) {}
        bericht.pruefen("Neues Bild gezeichnet", neu)
    }

    /// Legt das Bild aus quelle.png als fertige Generierung in den Bildordner des Tests, mit Angaben wie nach dem
    /// Rechnen in der Stufe Beste und im Querformat. Liefert die Gruppe.
    private static func ergebnisAnlegen(_ bericht: Pruefbericht) -> UUID? {
        let quelle = Testumgebung.ordner.appendingPathComponent("quelle.png")
        let name = "2026-11-04_19-42-07_moss_4207.png"
        let ziel = Pfade.bilder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: ziel)
        guard (try? FileManager.default.copyItem(at: quelle, to: ziel)) != nil, let masse = Vorschau.masse(ziel) else {
            bericht.pruefen("Bild für die Ergebnisansicht", false, "quelle.png fehlt im Testordner")
            return nil
        }
        let gruppe = UUID()
        let ergebnis = Ergebnis(
            datei: name, gruppe: gruppe, prompt: prompt, negativ: "", modell: .moss, seed: 4207,
            breite: masse.breite, hoehe: masse.hoehe, schritte: 30, textfuehrung: 3, sekunden: 412, geschaetzt: 398,
            referenzen: 0, module: [], auftrag: UUID(), turbo: false, modulDaten: [],
            formatName: Bildformat.quer.rawValue)
        guard let daten = try? JSONEncoder().encode(ergebnis),
              (try? daten.write(to: ziel.deletingPathExtension().appendingPathExtension("json"))) != nil else {
            bericht.pruefen("Angaben für die Ergebnisansicht", false)
            return nil
        }
        return gruppe
    }

    private final class Fenster: NSWindow {
        /// Bleibt, wo es angelegt wurde, weit ausserhalb jedes Bildschirms.
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private static func alle(_ ansicht: NSView) -> [NSView] { [ansicht] + ansicht.subviews.flatMap(alle) }
    private static func art(_ ansicht: NSView) -> String { String(describing: type(of: ansicht)) }

    /// Das Hauptfenster samt Titelleiste, in doppelter Auflösung. vorher läuft, sobald das Fenster steht.
    private static func zeichnen(_ name: String, seitenleiste auswahl: Auswahl, vorher: () -> Void) async -> Bool {
        // AppKit zeichnet nur auf dem echten Hauptthread, main.swift lässt ihn für diese Art laufen.
        guard pthread_main_np() != 0 else { return false }
        let generator = Generator.gemeinsam
        let wirt = NSHostingView(rootView: Hauptansicht()
            .environmentObject(generator)
            .environmentObject(Vorgaben.gemeinsam)
            .frame(minWidth: 960, minHeight: 640))
        let fenster = Fenster(contentRect: NSRect(origin: CGPoint(x: -30000, y: -30000), size: groesse),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        fenster.appearance = NSAppearance(named: .aqua)
        fenster.isReleasedWhenClosed = false
        fenster.contentView = wirt
        await warten(wirt, 3)
        vorher()
        await warten(wirt, 4)
        guard let rahmen = wirt.superview else { return false }

        // Was offscreen schwarz würde, weicht der Fensterfarbe.
        for ansicht in alle(rahmen) where art(ansicht) == "NSBlurryAlleywayView"
            || (art(ansicht) == "NSVisualEffectView" && ansicht.superview === rahmen) {
            ansicht.isHidden = true
        }
        for ansicht in alle(rahmen) where art(ansicht) == "_NSSplitViewItemViewWrapper" {
            ansicht.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        // Unter der Titelleiste spiegelt macOS den Inhalt jeder Scrollfläche in eine Tasche aus Glas. Solange es die gibt,
        // zeichnet sich der Inhalt offscreen nicht. Ohne Tasche erscheint er wie im Fenster.
        for ansicht in alle(rahmen) where art(ansicht) == "NSScrollPocket" { ansicht.isHidden = true }
        // Die Seitenleiste der App einzeln über der Glasfläche. Der schmale Rand oben hält sie aus dem Glas heraus.
        if let glas = alle(rahmen).filter({ art($0) == "NSContainerConcentricGlassEffectView" })
            .max(by: { $0.bounds.height < $1.bounds.height }), let traeger = glas.superview {
            let seite = NSHostingView(rootView: VStack(spacing: 0) {
                Color.clear.frame(height: 1)
                Seitenleiste(auswahl: .constant(Optional(auswahl))).scrollContentBackground(.hidden)
            }
            .environmentObject(generator)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.96))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)))
            seite.frame = glas.frame
            traeger.addSubview(seite, positioned: .above, relativeTo: glas)
            await warten(wirt, 3)
        }

        let punkte = rahmen.bounds.size
        guard let bild = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(punkte.width) * 2, pixelsHigh: Int(punkte.height) * 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        bild.size = punkte
        rahmen.cacheDisplay(in: rahmen.bounds, to: bild)
        let ziel = Testumgebung.ordner.appendingPathComponent("\(name).png")
        let geschrieben = (try? bild.representation(using: .png, properties: [:])?.write(to: ziel)) != nil
        fenster.contentView = nil
        fenster.close()
        return geschrieben
    }

    /// Lässt SwiftUI nachkommen: Layout, Vorschaubilder und Wechsel der Ansicht.
    private static func warten(_ wirt: NSView, _ runden: Int) async {
        for _ in 0..<runden {
            wirt.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(400))
        }
    }
}
