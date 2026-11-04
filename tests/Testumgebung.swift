import Foundation

/// Angaben des Prüfprogramms aus der Umgebung, gesetzt von testlauf.sh. Fehlt etwas oder passt etwas nicht, bricht es
/// ab, bevor irgendein Teil der App startet. So rührt ein Prüflauf nie echte Bilder, Einstellungen oder Modelle an.
/// Nur das Prüfprogramm kennt diese Datei, die App selbst hat keinen Testmodus.
enum Testumgebung {
    /// Diese Datei legt testlauf.sh in jeden frischen Testordner. Ohne sie gilt ein Ordner nicht als Testordner.
    static let kennzeichen = ".graphis-testordner"
    private static let umgebung = ProcessInfo.processInfo.environment

    static func abbrechen(_ text: String) -> Never {
        FileHandle.standardError.write(Data("FEHLER Testumgebung: \(text)\n".utf8))
        exit(2)
    }

    /// Der Pfad mit aufgelösten Verknüpfungen. Fehlt das Ende noch, wird der vorhandene Anfang aufgelöst.
    static func aufgeloest(_ url: URL) -> [String] {
        var vorhanden = url.standardizedFileURL
        var rest = [String]()
        while !FileManager.default.fileExists(atPath: vorhanden.path), vorhanden.pathComponents.count > 1 {
            rest.insert(vorhanden.lastPathComponent, at: 0)
            vorhanden.deleteLastPathComponent()
        }
        return vorhanden.resolvingSymlinksInPath().pathComponents + rest
    }

    /// Liegt ort im Ordner basis? Verglichen werden ganze Pfadteile, nicht Zeichen. So zählt /tmp/test2 nicht
    /// als Teil von /tmp/test.
    static func innerhalb(_ ort: URL, _ basis: URL) -> Bool {
        let b = aufgeloest(basis), o = aufgeloest(ort)
        return o.count > b.count && Array(o.prefix(b.count)) == b
    }

    /// Der Testordner: absolut, vorhanden, mit Kennzeichen und im Ordner für temporäre Dateien.
    static let ordner: URL = {
        guard let wert = umgebung["GRAPHIS_TESTORDNER"], wert.hasPrefix("/") else {
            abbrechen("GRAPHIS_TESTORDNER fehlt oder ist kein absoluter Pfad.")
        }
        let url = URL(fileURLWithPath: wert, isDirectory: true).standardizedFileURL
        var istOrdner: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &istOrdner), istOrdner.boolValue,
              FileManager.default.fileExists(atPath: url.appendingPathComponent(kennzeichen).path) else {
            abbrechen("Der Testordner fehlt oder trägt das Kennzeichen \(kennzeichen) nicht.")
        }
        let temporaer = [URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
                         URL(fileURLWithPath: "/private/tmp", isDirectory: true)]
        guard temporaer.contains(where: { innerhalb(url, $0) }) else {
            abbrechen("Der Testordner muss im Ordner für temporäre Dateien liegen.")
        }
        return url
    }()

    /// Das Scheinprogramm, das statt des Rechenmotors aufgerufen wird. Es muss im Testordner liegen.
    static let programm: String = {
        guard let wert = umgebung["GRAPHIS_TESTCLI"] else { abbrechen("GRAPHIS_TESTCLI fehlt.") }
        let url = URL(fileURLWithPath: wert)
        guard innerhalb(url, ordner), FileManager.default.isExecutableFile(atPath: url.path) else {
            abbrechen("GRAPHIS_TESTCLI muss ein ausführbares Programm im Testordner sein.")
        }
        return url.path
    }()

    /// Manifest mit kleinen Dateien vom lokalen Testserver. Nur Adressen auf 127.0.0.1 gelten. Unter module stehen
    /// zusätzlich Moduldateien, die nicht zur Einrichtung gehören.
    static let manifest: Modellmanifest = {
        guard let wert = umgebung["GRAPHIS_TESTMANIFEST"] else { abbrechen("GRAPHIS_TESTMANIFEST fehlt.") }
        guard let daten = try? Data(contentsOf: URL(fileURLWithPath: wert)),
              let manifest = try? JSONDecoder().decode(Modellmanifest.self, from: daten),
              manifest.kennung != Modellmanifest.moss.kennung, !manifest.dateien.isEmpty,
              manifest.dateien.allSatisfy({ $0.adresse.host == "127.0.0.1" }) else {
            abbrechen("GRAPHIS_TESTMANIFEST ist unlesbar oder zeigt nicht auf den lokalen Testserver.")
        }
        return manifest
    }()

    /// Protokoll des Testservers: eine Zeile je Anfrage.
    static let serverLog: URL = {
        guard let wert = umgebung["GRAPHIS_TESTSERVERLOG"] else { abbrechen("GRAPHIS_TESTSERVERLOG fehlt.") }
        return URL(fileURLWithPath: wert)
    }()

    /// Statt GitHub fragt die Suche nach neuen Versionen den lokalen Testserver, nur eine Adresse auf 127.0.0.1 gilt.
    static let versionenAdresse: URL = {
        guard let wert = umgebung["GRAPHIS_TESTVERSIONEN"], let url = URL(string: wert),
              url.scheme == "http", url.host == "127.0.0.1" else {
            abbrechen("GRAPHIS_TESTVERSIONEN fehlt oder zeigt nicht auf den lokalen Testserver.")
        }
        return url
    }()

    /// Ganz am Anfang: alle Angaben prüfen, bevor irgendein Teil der App startet.
    static func pruefen() {
        _ = ordner
        _ = programm
        _ = manifest
        _ = serverLog
        _ = versionenAdresse
    }
}
