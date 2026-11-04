import AppKit
import SwiftUI

/// Zeichnet Hauptfenster und Einstellungen als PNG in den Testordner, ohne dass ein Fenster auf dem Bildschirm
/// erscheint. Die Sprache folgt dem Prüfprogramm: testlauf.sh legt für die Art ansichten eine Kopie mit den
/// Sprachordnern der App an und startet sie je Sprache. Die Seitenleiste zeichnet macOS so nicht, sie bleibt leer.
@MainActor
enum AnsichtenZeichnen {
    static func ausfuehren(_ bericht: Pruefbericht) async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
        let sprache = Bundle.main.preferredLocalizations.first ?? "?"
        let generator = Generator.gemeinsam
        let vorgaben = Vorgaben.gemeinsam
        vorgaben.prompt = sprache == "de" ? "Ein Leuchtturm im Nebel bei Sonnenaufgang" : "A lighthouse in the fog at sunrise"
        await vorgaben.moduleNeuLaden()

        // Ein Hinweis auf eine neue Version, ohne Anfrage: Der Fund liegt schon in eigenen Einstellungen.
        let speicher = UserDefaults(suiteName: Testumgebung.ordner.appendingPathComponent("ansichten-versionen").path)!
        speicher.set(true, forKey: Versionspruefung.Schluessel.erlaubt)
        speicher.set(Date().timeIntervalSince1970, forKey: Versionspruefung.Schluessel.geprueftAm)
        speicher.set("1.1", forKey: Versionspruefung.Schluessel.version)
        speicher.set("https://github.com/Campfire7/graphis/releases/tag/v1.1", forKey: Versionspruefung.Schluessel.seite)
        let mitHinweis = Versionspruefung(speicher: speicher, aktuelleVersion: "1.0")

        let hauptfenster = Hauptansicht().environmentObject(generator).environmentObject(vorgaben)
        bericht.pruefen("Hauptfenster gezeichnet", await zeichnen(hauptfenster, CGSize(width: 1180, height: 820), "hauptfenster-\(sprache)"))
        let module = ModulBereich().environmentObject(generator).environmentObject(vorgaben)
            .safeAreaInset(edge: .bottom, spacing: 0) { Fusszeile(versionen: mitHinweis) }
        bericht.pruefen("Module mit Hinweis gezeichnet", await zeichnen(module, CGSize(width: 860, height: 820), "module-\(sprache)"))
        let einstellungen = Einstellungsfenster().environmentObject(generator).environmentObject(vorgaben)
        bericht.pruefen("Einstellungen gezeichnet", await zeichnen(einstellungen, CGSize(width: 600, height: 760), "einstellungen-\(sprache)"))
    }

    private static func zeichnen(_ ansicht: some View, _ groesse: CGSize, _ name: String) async -> Bool {
        // AppKit zeichnet nur auf dem echten Hauptthread, main.swift lässt ihn für diese Art laufen.
        guard pthread_main_np() != 0 else { return false }
        let wirt = NSHostingView(rootView: ansicht.frame(width: groesse.width, height: groesse.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        let fenster = NSWindow(contentRect: NSRect(origin: CGPoint(x: -20000, y: -20000), size: groesse),
                               styleMask: [.titled], backing: .buffered, defer: false)
        fenster.appearance = NSAppearance(named: .aqua)
        fenster.contentView = wirt
        // Die Hauptschleife läuft weiter, so kommt SwiftUI dazwischen nach und lädt auch die Vorschaubilder.
        for _ in 0..<4 {
            wirt.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(400))
        }
        guard let bild = wirt.bitmapImageRepForCachingDisplay(in: wirt.bounds) else { return false }
        wirt.cacheDisplay(in: wirt.bounds, to: bild)
        let ziel = Testumgebung.ordner.appendingPathComponent("\(name).png")
        guard (try? bild.representation(using: .png, properties: [:])?.write(to: ziel)) != nil else { return false }
        fenster.contentView = nil
        return true
    }
}
