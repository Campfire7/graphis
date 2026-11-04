import AppKit
import Foundation

/// Hält die Prüfungen fest. Jede Zeile beginnt mit ok oder FEHLER und erscheint sofort, damit auch ein Abbruch
/// durch das Zeitlimit zeigt, wie weit es kam.
@MainActor
final class Pruefbericht {
    private(set) var anzahl = 0
    private(set) var fehler = 0

    func pruefen(_ name: String, _ ok: Bool, _ angaben: @autoclosure () -> String = "") {
        anzahl += 1
        if !ok { fehler += 1 }
        let zusatz = angaben()
        print("\(ok ? "ok" : "FEHLER") \(name)\(zusatz.isEmpty ? "" : ": \(Hilfe.kurz(zusatz))")")
        fflush(stdout)
    }
}

@MainActor
enum Hilfe {
    /// Wartet, bis die Bedingung gilt, höchstens so viele Sekunden. Liefert, ob sie eingetreten ist.
    @discardableResult
    static func warten(_ sekunden: Double = 30, _ bedingung: () -> Bool) async -> Bool {
        let ende = Date().addingTimeInterval(sekunden)
        while !bedingung() {
            if Date() > ende { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    /// Bis der Generator nichts mehr rechnet und keine Arbeit mehr wartet, ausser angehaltener.
    @discardableResult
    static func fertig(_ generator: Generator, _ sekunden: Double = 60) async -> Bool {
        await warten(sekunden) { !generator.laeuft && (generator.warteschlange.isEmpty || generator.pausiert) }
    }

    /// Kürzt den Testordner, damit die Zeilen lesbar bleiben.
    static func kurz(_ text: String) -> String {
        text.replacingOccurrences(of: Testumgebung.ordner.path, with: "<test>")
    }

    /// Ein einfarbiges Testbild, damit die Prüfungen ohne echte Fotos auskommen.
    @discardableResult
    static func testbild(_ name: String, _ breite: Int, _ hoehe: Int, _ farbe: NSColor, in ordner: URL) -> URL {
        let ziel = ordner.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        guard let bild = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: breite, pixelsHigh: hoehe, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return ziel }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bild)
        farbe.setFill()
        NSRect(x: 0, y: 0, width: breite, height: hoehe).fill()
        NSGraphicsContext.restoreGraphicsState()
        try? bild.representation(using: .png, properties: [:])?.write(to: ziel)
        return ziel
    }

    /// Der Ordner des Scheinprogramms. Dort hält es jeden Aufruf in aufrufe.txt und jeden Prompt in prompts.txt fest.
    static var scheinOrdner: URL { URL(fileURLWithPath: Testumgebung.programm).deletingLastPathComponent() }

    static func zeilen(_ datei: URL) -> [String] {
        guard let text = try? String(contentsOf: datei, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
    }

    static func aufrufe() -> [String] { zeilen(scheinOrdner.appendingPathComponent("aufrufe.txt")) }
    static func prompts() -> [String] { zeilen(scheinOrdner.appendingPathComponent("prompts.txt")) }
    static func serverLog() -> [String] { zeilen(Testumgebung.serverLog) }

    /// Legt neben dem Scheinprogramm eine Steuerdatei an: einmal-fehlschlagen oder langsam.
    static func schein(_ name: String, an: Bool) {
        let datei = scheinOrdner.appendingPathComponent(name)
        if an {
            FileManager.default.createFile(atPath: datei.path, contents: Data())
        } else {
            try? FileManager.default.removeItem(at: datei)
        }
    }

    /// Richtet MOSS-Image vom lokalen Testserver ein, so wie es der erste Start der App tut.
    static func einrichten() async -> Bool {
        let installation = Modellinstallation.gemeinsam
        installation.freierPlatz = { _ in 1 << 40 }
        if !installation.bereit { installation.laden() }
        await warten(60) { !installation.beschaeftigt }
        return installation.bereit
    }

    /// Schreibt eine Datei im Format safetensors: Länge des Kopfs, Kopf als JSON, dann die Gewichte.
    /// tensoren nennt je Name die Form und die Zahl der Bytes, die Gewichte sind fortlaufende Zahlen.
    @discardableResult
    static func safetensors(_ name: String, _ tensoren: [(String, [Int], Int)], in ordner: URL,
                            abschneiden: Int = 0) -> URL {
        var kopf = [String: Any]()
        var gewichte = Data()
        for (tensor, form, bytes) in tensoren {
            kopf[tensor] = ["dtype": "F16", "shape": form, "data_offsets": [gewichte.count, gewichte.count + bytes]]
            gewichte.append(Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ tensor.count) }))
        }
        kopf["__metadata__"] = ["format": "pt"]
        let json = (try? JSONSerialization.data(withJSONObject: kopf, options: .sortedKeys)) ?? Data()
        var inhalt = withUnsafeBytes(of: UInt64(json.count).littleEndian) { Data($0) }
        inhalt.append(json)
        inhalt.append(gewichte.dropLast(abschneiden))
        let ziel = ordner.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try? inhalt.write(to: ziel)
        return ziel
    }

    /// Liest den Kopf einer safetensors-Datei, um das Ergebnis des Angleichens zu prüfen.
    static func kopf(_ url: URL) -> [String: Any] {
        guard let daten = try? Data(contentsOf: url), daten.count >= 8 else { return [:] }
        let laenge = daten.prefix(8).withUnsafeBytes { Int(UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self))) }
        guard daten.count >= 8 + laenge else { return [:] }
        return (try? JSONSerialization.jsonObject(with: daten.subdata(in: 8..<8 + laenge))) as? [String: Any] ?? [:]
    }
}
