import CryptoKit
import Foundation
import SwiftUI

/// Eine Datei der Einrichtung: woher sie kommt, wohin sie gehört, wie gross sie ist und ihr SHA-256.
struct Manifestdatei: Codable, Sendable, Equatable {
    enum Ziel: String, Codable, Sendable {
        /// In den Modellordner moss-image-q8.
        case modell
        /// In den Modulordner, für das Turbo-Modul.
        case modul
    }

    let ziel: Ziel
    /// Relativ zum Ziel, etwa vae/0.safetensors.
    let pfad: String
    let bytes: Int64
    let sha256: String
    /// Feste Adresse mit Stand. Jeder Versuch beginnt hier, so löst sich eine abgelaufene Download-Adresse neu auf.
    let adresse: URL

    var schluessel: String { "\(ziel.rawValue)/\(pfad)" }
}

/// Was die App beim ersten Start lädt. Alle Stände sind fest, Grössen und SHA-256 stammen aus der
/// Hugging-Face-API zum jeweiligen Stand (abgefragt am 3.11.2026), kleine Dateien zusätzlich selbst gehasht.
struct Modellmanifest: Codable, Sendable {
    /// Ändert sich mit jedem neuen Stand. Eine Prüfung für einen anderen Stand gilt nicht mehr.
    let kennung: String
    let dateien: [Manifestdatei]

    var bytes: Int64 { dateien.map(\.bytes).reduce(0, +) }
    func bytes(_ ziel: Manifestdatei.Ziel) -> Int64 { dateien.filter { $0.ziel == ziel }.map(\.bytes).reduce(0, +) }

    private static let modellStand = "c7c9f94ad909beee13d70a9358ed961e86aa35c9"
    private static let turboStand = "f95df83b5e90ae91ea412434b3f9b7f1c8c6314f"

    private static func modell(_ pfad: String, _ bytes: Int64, _ sha256: String) -> Manifestdatei {
        Manifestdatei(ziel: .modell, pfad: pfad, bytes: bytes, sha256: sha256, adresse: URL(
            string: "https://huggingface.co/mflux-community/moss-image-sft-mflux-q8/resolve/\(modellStand)/\(pfad)")!)
    }

    /// Das Turbo-Modul behält seinen Originalhash, die App ändert die Datei nie.
    private static func turbo(_ bytes: Int64, _ sha256: String) -> Manifestdatei {
        Manifestdatei(ziel: .modul, pfad: Modul.turboDatei, bytes: bytes, sha256: sha256, adresse: URL(
            string: "https://huggingface.co/lodestones/MOSS-Image-SFT-8-steps-dmd/resolve/\(turboStand)/lora_latest.safetensors")!)
    }

    /// MOSS-Image SFT, quantisiert auf 8 Bit von mflux-community, und das Turbo-Modul von lodestones. Beide Apache 2.0.
    static let moss = Modellmanifest(
        kennung: "moss-image-sft-mflux-q8@\(modellStand)+turbo@\(turboStand)",
        dateien: [
            modell("README.md", 2_952, "957c3b02e5b03efba7a860e963bee0ec6e848421c05d33aebc0fc9c495f611f3"),
            modell("mflux_model.json", 477, "536158b42cecc78ed55e44351f4e5d7e4a72426c3128e0e707c370a39fe11369"),
            modell("text_encoder/0.safetensors", 2_124_956_932, "98254128de8d55e25de833ff5a3be770568fbcdbd30d8d84f3caad12417412e6"),
            modell("text_encoder/1.safetensors", 2_123_858_632, "e468ff6790a65c05714721a78eb516aa7ba3ab2e45b5d8cf99698bc369c4248f"),
            modell("text_encoder/2.safetensors", 2_123_875_343, "81a923f2585ca11d9a1ce3be46ee65ad2163d2643151507377d44042dd09390a"),
            modell("text_encoder/3.safetensors", 2_061_132_467, "8b03130b0d3dd77d6d0b655539d13583a4bf4d68f3a5252a80e29298d361c8c1"),
            modell("text_encoder/model.safetensors.index.json", 54_192, "fabf7fccc658686c8224eebf87e0de4f0114f98e6ac91fa5e90b6e656e0248db"),
            modell("tokenizer/chat_template.jinja", 7_756, "a4aee8afcf2e0711942cf848899be66016f8d14a889ff9ede07bca099c28f715"),
            modell("tokenizer/tokenizer.json", 19_989_325, "06b9509352d2af50381ab2247e083b80d32d5c0aba91c272ca9ff729b6a0e523"),
            modell("tokenizer/tokenizer_config.json", 1_123, "bee8eba30f0eb4af73c0fe2cd06d0f89b657d7819941c438157ec42f7c80ea87"),
            modell("transformer/0.safetensors", 2_140_808_302, "c09872e83d00ad4642cab7f0c4ce377216c1ffc391f3db3010bdcab5dd4db416"),
            modell("transformer/1.safetensors", 2_129_324_635, "3e5ad3cd5b177e3c61aa3e2f1253e6555f0522ee05b7a0618c0d9520a6765cf8"),
            modell("transformer/2.safetensors", 1_130_281_951, "9181c447a99b8baf6a5d24706577baa513ed94459d84097c2a30c6f05383c750"),
            modell("transformer/model.safetensors.index.json", 50_578, "b2d12ad3bbb45a0d8ab1bf06eab1060cc4bb1dca4dccec5d5563ceb4b100edf5"),
            modell("vae/0.safetensors", 123_240_398, "db2e11f4960d8a85af3df7201eb76b6e167e27be4335a29ad888b2266923de03"),
            modell("vae/model.safetensors.index.json", 17_547, "832ed7169c0915288b73b3381f9deca52d76fb51b134677bd28c7d2eb27e966b"),
            turbo(1_189_176_800, "be82ab2bef78194651815bb6de443cec67553e01c14559f2ad365449445f0452"),
        ])

    /// Im Prüfprogramm kommt das Manifest aus einer Datei, damit ein lokaler Server kleine Testdateien liefern kann.
    /// Ohne diese Datei bricht es ab, statt das echte Modell zu laden.
    static var aktuell: Modellmanifest {
        #if TESTLAUF
        return Testumgebung.manifest
        #else
        return moss
        #endif
    }
}

/// Lädt und prüft MOSS-Image und das Turbo-Modul. Ins Netz geht die App dafür nur nach einem Klick.
/// Geladen wird in einen eigenen Ordner neben dem Ziel, mit .part-Dateien, die nach Abbruch oder Neustart an ihrem
/// Ende weiterladen. Erst wenn jede Datei Grösse und SHA-256 erfüllt, wird alles auf einmal an seinen Platz gestellt.
@MainActor
final class Modellinstallation: ObservableObject {
    static let gemeinsam = Modellinstallation()

    enum Zustand: Equatable {
        /// Nichts oder erst ein Teil ist da. vorhanden zählt die schon geladenen Bytes.
        case fehlt(vorhanden: Int64)
        /// Der Modellordner ist da, aber noch nicht geprüft, etwa nach einer Änderung von Hand.
        case ungeprueft
        /// Die Prüfung fand so viele fehlende oder falsche Dateien.
        case beschaedigt(Int)
        case laedt(geladen: Int64, gesamt: Int64, datei: Int, von: Int)
        case prueft(datei: Int, von: Int)
        case fehler(String, platzUnbekannt: Bool)
        case bereit
    }

    @Published private(set) var zustand: Zustand = .fehlt(vorhanden: 0)
    let manifest: Modellmanifest
    /// Freier Platz auf dem Volume, auf dem geladen wird. Tests setzen eigene Werte ein, etwa für eine volle Platte.
    var freierPlatz: (URL) -> Int64? = Modellinstallation.platzAufVolume
    /// So oft prüft das Laden unterwegs den Platz. Tests verkleinern den Abstand, weil ihre Dateien klein sind.
    var pruefAbstand: Int64 = 256 * 1024 * 1024
    /// Bleibt nach dem Laden mindestens frei, damit der Mac nicht vollläuft.
    nonisolated static let reserve: Int64 = 2_000_000_000
    private var aufgabe: Task<Void, Never>?

    init(manifest: Modellmanifest = .aktuell) {
        self.manifest = manifest
        zustand = ermitteln()
    }

    var bereit: Bool { zustand == .bereit }
    var beschaeftigt: Bool { aufgabe != nil }

    // MARK: Orte

    private var ladeOrdner: URL { Pfade.modelle.appendingPathComponent(".einrichtung", isDirectory: true) }
    private var protokollDatei: URL { Pfade.modelle.appendingPathComponent(".einrichtung-geprueft.json") }

    private func aktiv(_ datei: Manifestdatei) -> URL {
        switch datei.ziel {
        case .modell: Pfade.ordner(.moss).appendingPathComponent(datei.pfad)
        case .modul: Pfade.module.appendingPathComponent(datei.pfad)
        }
    }

    private func geladen(_ datei: Manifestdatei) -> URL {
        ladeOrdner.appendingPathComponent(datei.schluessel)
    }

    private func teil(_ datei: Manifestdatei) -> URL {
        geladen(datei).appendingPathExtension("part")
    }

    // MARK: Prüfprotokoll

    /// Merkt sich geprüfte Dateien mit Grösse, Änderungszeit und Dateinummer. Ein Umbenennen ändert nichts davon,
    /// jede Änderung am Inhalt dagegen schon. So muss nicht bei jedem Start alles neu gehasht werden.
    private struct Protokoll: Codable {
        struct Eintrag: Codable, Equatable {
            let bytes: Int64
            let zeit: Double
            let nummer: UInt64
            let sha256: String
        }

        var kennung: String
        var dateien: [String: Eintrag] = [:]
    }

    private func protokollLesen() -> Protokoll {
        guard let daten = try? Data(contentsOf: protokollDatei),
              let gelesen = try? JSONDecoder().decode(Protokoll.self, from: daten),
              gelesen.kennung == manifest.kennung else { return Protokoll(kennung: manifest.kennung) }
        return gelesen
    }

    private func protokollSchreiben(_ protokoll: Protokoll) {
        try? FileManager.default.createDirectory(at: Pfade.modelle, withIntermediateDirectories: true)
        try? JSONEncoder().encode(protokoll).write(to: protokollDatei, options: .atomic)
    }

    nonisolated private static func merkmale(_ url: URL) -> (bytes: Int64, zeit: Double, nummer: UInt64)? {
        guard let werte = try? FileManager.default.attributesOfItem(atPath: url.path),
              (werte[.type] as? FileAttributeType) == .typeRegular,
              let bytes = (werte[.size] as? NSNumber)?.int64Value,
              let zeit = (werte[.modificationDate] as? Date)?.timeIntervalSince1970,
              let nummer = (werte[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
        return (bytes, zeit, nummer)
    }

    private func geprueft(_ url: URL, _ datei: Manifestdatei, _ protokoll: Protokoll) -> Bool {
        guard let ist = Self.merkmale(url), ist.bytes == datei.bytes, let eintrag = protokoll.dateien[datei.schluessel] else {
            return false
        }
        return eintrag.sha256 == datei.sha256 && eintrag.bytes == ist.bytes && eintrag.nummer == ist.nummer
            && abs(eintrag.zeit - ist.zeit) < 0.001
    }

    private func vermerken(_ url: URL, _ datei: Manifestdatei, _ protokoll: inout Protokoll) {
        guard let ist = Self.merkmale(url) else { return }
        protokoll.dateien[datei.schluessel] = .init(bytes: ist.bytes, zeit: ist.zeit, nummer: ist.nummer, sha256: datei.sha256)
    }

    // MARK: Zustand

    /// Nur Dateiangaben, kein Hashen: Das geht bei jedem Start und bei jeder Prüfung der Bereitschaft schnell.
    private func ermitteln() -> Zustand {
        let dateien = FileManager.default
        if dateien.fileExists(atPath: ladeOrdner.path) { return .fehlt(vorhanden: vorhandeneBytes()) }
        guard dateien.fileExists(atPath: Pfade.ordner(.moss).path) else { return .fehlt(vorhanden: 0) }
        let protokoll = protokollLesen()
        return manifest.dateien.allSatisfy { geprueft(aktiv($0), $0, protokoll) } ? .bereit : .ungeprueft
    }

    /// Liest den Stand neu, etwa wenn jemand den Modellordner von Hand verändert hat. Während einer Arbeit nicht.
    func auffrischen() {
        guard aufgabe == nil else { return }
        let neu = ermitteln()
        if case .fehler = zustand, neu != .bereit { return }
        if case .beschaedigt = zustand, neu == .ungeprueft { return }
        zustand = neu
    }

    private func vorhandeneBytes() -> Int64 {
        manifest.dateien.map { datei in
            Self.merkmale(geladen(datei))?.bytes ?? Self.merkmale(teil(datei))?.bytes ?? 0
        }.reduce(0, +)
    }

    /// Noch zu ladende Bytes: alles, was weder geprüft noch als Teil schon da ist. Eine vollständige, noch ungeprüfte
    /// Datei zählt nicht, sonst verlangt eine Reparatur Platz für Dateien, die schon daliegen. Fällt sie beim Prüfen
    /// durch, fängt die Platzprüfung unterwegs das ab.
    private func ausstehend(_ protokoll: Protokoll, ab erste: Int = 0) -> Int64 {
        manifest.dateien.dropFirst(erste).map { datei -> Int64 in
            if geprueft(geladen(datei), datei, protokoll) || Self.merkmale(geladen(datei))?.bytes == datei.bytes { return 0 }
            let schon = Self.merkmale(teil(datei))?.bytes ?? 0
            return max(datei.bytes - min(schon, datei.bytes), 0)
        }.reduce(0, +)
    }

    nonisolated static func platzAufVolume(_ ordner: URL) -> Int64? {
        var stelle = ordner
        while !FileManager.default.fileExists(atPath: stelle.path) && stelle.pathComponents.count > 1 {
            stelle.deleteLastPathComponent()
        }
        return (try? stelle.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    // MARK: Handlungen

    /// Lädt, was fehlt, prüft alles und stellt es dann an seinen Platz. Auch für Fortsetzen und Reparieren.
    func laden(trotzUnbekanntemPlatz: Bool = false) {
        guard aufgabe == nil else { return }
        aufgabe = Task {
            defer { aufgabe = nil }
            do {
                try await ladenUndAktivieren(trotzUnbekanntemPlatz: trotzUnbekanntemPlatz)
                zustand = .bereit
            } catch is CancellationError {
                zustand = .fehlt(vorhanden: vorhandeneBytes())
            } catch let fehler as Einrichtungsfehler {
                zustand = .fehler(fehler.text, platzUnbekannt: fehler == .platzUnbekannt)
            } catch let fehler as URLError {
                zustand = .fehler(Einrichtungsfehler.verbindung(fehler).text, platzUnbekannt: false)
            } catch {
                zustand = .fehler(Einrichtungsfehler.ausSchreibfehler(error).text, platzUnbekannt: false)
            }
        }
    }

    /// Hasht die Dateien am Ziel. Ohne erzwingen zählen Dateien, die seit der letzten Prüfung unverändert sind.
    func pruefen(erzwingen: Bool = false) {
        guard aufgabe == nil else { return }
        aufgabe = Task {
            defer { aufgabe = nil }
            var protokoll = erzwingen ? Protokoll(kennung: manifest.kennung) : protokollLesen()
            var falsch = 0
            for (stelle, datei) in manifest.dateien.enumerated() {
                zustand = .prueft(datei: stelle + 1, von: manifest.dateien.count)
                let ort = aktiv(datei)
                if geprueft(ort, datei, protokoll) { continue }
                protokoll.dateien[datei.schluessel] = nil
                if Self.merkmale(ort)?.bytes == datei.bytes, await Self.hash(ort) == datei.sha256 {
                    vermerken(ort, datei, &protokoll)
                } else {
                    falsch += 1
                }
                if Task.isCancelled { break }
            }
            protokollSchreiben(protokoll)
            if Task.isCancelled {
                zustand = ermitteln()
            } else {
                zustand = falsch == 0 && FileManager.default.fileExists(atPath: Pfade.ordner(.moss).path) ? .bereit : .beschaedigt(falsch)
            }
        }
    }

    /// Hält an. Geladene Teile bleiben liegen, beim nächsten Laden geht es dort weiter.
    func anhalten() {
        aufgabe?.cancel()
    }

    private func ladenUndAktivieren(trotzUnbekanntemPlatz: Bool) async throws {
        let dateien = FileManager.default
        var protokoll = protokollLesen()
        // Bei einer Reparatur kommen die vorhandenen Dateien zuerst in den Ladeordner. Gute bleiben, falsche fliegen
        // beim Prüfen raus. Umbenennen ändert weder Inhalt noch Prüfvermerk.
        try dateien.createDirectory(at: ladeOrdner, withIntermediateDirectories: true)
        for datei in manifest.dateien where !dateien.fileExists(atPath: geladen(datei).path)
            && dateien.fileExists(atPath: aktiv(datei).path) {
            try dateien.createDirectory(at: geladen(datei).deletingLastPathComponent(), withIntermediateDirectories: true)
            try dateien.moveItem(at: aktiv(datei), to: geladen(datei))
        }
        if dateien.fileExists(atPath: Pfade.ordner(.moss).path) { try dateien.removeItem(at: Pfade.ordner(.moss)) }

        // Platz auf dem Volume, auf dem tatsächlich geladen wird, mit Reserve.
        let bedarf = ausstehend(protokoll) + Self.reserve
        switch freierPlatz(ladeOrdner) {
        case .none where !trotzUnbekanntemPlatz: throw Einrichtungsfehler.platzUnbekannt
        case .some(let frei) where frei < bedarf: throw Einrichtungsfehler.zuWenigPlatz(fehlt: bedarf - frei)
        default: break
        }

        let gesamt = manifest.bytes
        var fertig: Int64 = 0
        for (stelle, datei) in manifest.dateien.enumerated() {
            try Task.checkCancellation()
            let ziel = geladen(datei)
            try dateien.createDirectory(at: ziel.deletingLastPathComponent(), withIntermediateDirectories: true)
            if dateien.fileExists(atPath: ziel.path) && !geprueft(ziel, datei, protokoll) {
                zustand = .prueft(datei: stelle + 1, von: manifest.dateien.count)
                if Self.merkmale(ziel)?.bytes == datei.bytes, await Self.hash(ziel) == datei.sha256 {
                    vermerken(ziel, datei, &protokoll)
                    protokollSchreiben(protokoll)
                } else {
                    try dateien.removeItem(at: ziel)
                }
            }
            if !geprueft(ziel, datei, protokoll) {
                try await dateiLaden(datei, nummer: stelle + 1, schon: fertig, gesamt: gesamt,
                                     spaeter: ausstehend(protokoll, ab: stelle + 1))
                vermerken(ziel, datei, &protokoll)
                protokollSchreiben(protokoll)
            }
            fertig += datei.bytes
        }

        // Alles geprüft: erst das Turbo-Modul, dann der ganze Modellordner auf einmal. Zuletzt der Prüfvermerk.
        for datei in manifest.dateien where datei.ziel == .modul {
            try dateien.createDirectory(at: Pfade.module, withIntermediateDirectories: true)
            if dateien.fileExists(atPath: aktiv(datei).path) { try dateien.removeItem(at: aktiv(datei)) }
            try dateien.moveItem(at: geladen(datei), to: aktiv(datei))
        }
        try dateien.moveItem(at: ladeOrdner.appendingPathComponent(Manifestdatei.Ziel.modell.rawValue), to: Pfade.ordner(.moss))
        for datei in manifest.dateien { vermerken(aktiv(datei), datei, &protokoll) }
        protokollSchreiben(protokoll)
        try? dateien.removeItem(at: ladeOrdner)
        guard ermitteln() == .bereit else { throw Einrichtungsfehler.nachPruefung }
    }

    /// Eine Datei bis zur vollen Grösse in ihre .part-Datei, dann hashen und erst danach umbenennen.
    /// spaeter sind die Bytes der Dateien danach. Unterwegs gilt dieselbe Reserve wie beim Start.
    private func dateiLaden(_ datei: Manifestdatei, nummer: Int, schon: Int64, gesamt: Int64, spaeter: Int64) async throws {
        guard datei.adresse.scheme == "https" || Pfade.testlauf else { throw Einrichtungsfehler.unsicher }
        #if TESTLAUF
        // Das Prüfprogramm geht nie ins echte Netz, nur zu seinem lokalen Testserver.
        guard datei.adresse.host == "127.0.0.1" else { throw Einrichtungsfehler.unsicher }
        #endif
        let teilDatei = teil(datei)
        let von = manifest.dateien.count
        var neuBegonnen = false
        var verbindungsVersuche = 0
        while true {
            try Task.checkCancellation()
            let startBytes = Self.merkmale(teilDatei)?.bytes ?? 0
            zustand = .laedt(geladen: schon + min(startBytes, datei.bytes), gesamt: gesamt, datei: nummer, von: von)
            let lader = Fortsetzlader(teil: teilDatei, erwartet: datei.bytes, pruefAbstand: pruefAbstand,
                                      platzReicht: { [freierPlatz, ladeOrdner] fehlt in
                                          (freierPlatz(ladeOrdner) ?? .max) >= fehlt + spaeter + Self.reserve },
                                      fortschritt: { [weak self] bytes in
                                          Task { @MainActor in
                                              guard let self, case .laedt = self.zustand else { return }
                                              self.zustand = .laedt(geladen: schon + bytes, gesamt: gesamt, datei: nummer, von: von)
                                          }
                                      })
            do {
                try await lader.laden(datei.adresse)
            } catch Einrichtungsfehler.neuBeginnen where !neuBegonnen {
                // Der Server passte nicht zum Teilstand. Einmal ganz von vorne, nie etwas anhängen.
                neuBegonnen = true
                try? FileManager.default.removeItem(at: teilDatei)
                continue
            } catch let fehler as URLError where Self.voruebergehend(fehler) && verbindungsVersuche < 3 {
                verbindungsVersuche += 1
                try await Task.sleep(for: .seconds(2 * verbindungsVersuche))
                continue
            }
            zustand = .prueft(datei: nummer, von: von)
            guard Self.merkmale(teilDatei)?.bytes == datei.bytes, await Self.hash(teilDatei) == datei.sha256 else {
                try? FileManager.default.removeItem(at: teilDatei)
                // Ein fortgesetzter Teil kann von einem anderen Stand stammen. Dann einmal ganz neu laden.
                if startBytes > 0 && !neuBegonnen {
                    neuBegonnen = true
                    continue
                }
                throw Einrichtungsfehler.falscheDatei
            }
            try FileManager.default.moveItem(at: teilDatei, to: geladen(datei))
            return
        }
    }

    nonisolated private static func voruebergehend(_ fehler: URLError) -> Bool {
        [.networkConnectionLost, .timedOut, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed,
         .cannotFindHost, .resourceUnavailable].contains(fehler.code)
    }

    /// SHA-256 in grossen Stücken, im Hintergrund. Liefert nil, wenn die Datei nicht lesbar ist.
    nonisolated static func hash(_ url: URL) async -> String? {
        await Task.detached(priority: .utility) {
            guard let griff = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? griff.close() }
            var rechner = SHA256()
            while let stueck = try? griff.read(upToCount: 8 << 20), !stueck.isEmpty {
                rechner.update(data: stueck)
                if Task.isCancelled { return nil }
            }
            return rechner.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}

enum Einrichtungsfehler: Error, Equatable {
    case platzUnbekannt
    case zuWenigPlatz(fehlt: Int64)
    case server(Int)
    case anmeldeseite
    case zuGross
    case falscheDatei
    case unsicher
    case neuBeginnen
    case nachPruefung
    case verbindung(URLError)
    case schreiben(String)

    /// Eine volle Platte meldet sich beim Schreiben als ENOSPC, alles andere bleibt ein Schreibfehler.
    static func ausSchreibfehler(_ fehler: Error) -> Einrichtungsfehler {
        let ns = fehler as NSError
        if (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC)) || (ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError) {
            return .zuWenigPlatz(fehlt: 0)
        }
        return .schreiben(ns.localizedDescription)
    }

    var text: String {
        let gb = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        switch self {
        case .platzUnbekannt:
            return String(localized: "The free space on the Mac could not be determined. About \(gb(Modellmanifest.aktuell.bytes + Modellinstallation.reserve)) is needed. Check this in Finder, then click Download Anyway.")
        case .zuWenigPlatz(let fehlt) where fehlt > 0:
            return String(localized: "The Mac still needs \(gb(fehlt)) more free space. Free up some space, then click Resume. What is already downloaded stays.")
        case .zuWenigPlatz:
            return String(localized: "The Mac ran out of space. Free up some space, then click Resume. What is already downloaded stays.")
        case .server(let code) where code == 404:
            return String(localized: "Hugging Face no longer has this file at the expected place. A newer version of the app fixes this.")
        case .server(let code):
            return String(localized: "Hugging Face reports error \(code). Try again later, what is already downloaded stays.")
        case .anmeldeseite:
            return String(localized: "A web page came back instead of the file. Try again later.")
        case .zuGross:
            return String(localized: "A file is larger than expected. The app stopped the download.")
        case .falscheDatei:
            return String(localized: "A file does not match the expected one and was discarded. Click Resume.")
        case .unsicher:
            return String(localized: "The app only downloads over secure connections.")
        case .neuBeginnen, .nachPruefung:
            return String(localized: "The files could not be fully checked. Click Resume.")
        case .verbindung(let fehler) where fehler.code == .notConnectedToInternet:
            return String(localized: "The Mac is not connected to the internet. What is already downloaded stays. Then click Resume.")
        case .verbindung:
            return String(localized: "The connection was lost. What is already downloaded stays. Click Resume.")
        case .schreiben(let text):
            return String(localized: "The file could not be saved: \(text)")
        }
    }
}

/// Lädt in eine .part-Datei und setzt an deren Ende fort. Ein Server, der die Range nicht beachtet (200), oder eine
/// Antwort mit falschem Bereich führt zum Neubeginn, nie zum Anhängen. 416 bei voller Datei heisst: schon fertig.
private final class Fortsetzlader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let teil: URL
    private let erwartet: Int64
    private let pruefAbstand: Int64
    private let platzReicht: @Sendable (Int64) -> Bool
    private let fortschritt: @Sendable (Int64) -> Void
    private var griff: FileHandle?
    private var start: Int64 = 0
    private var bytes: Int64 = 0
    private var naechstePruefung: Int64 = 0
    private var letzteMeldung: Int64 = 0
    private var fehler: Error?
    private var schonFertig = false
    private let schloss = NSLock()
    private var ende: Result<Void, Error>?
    private var fortsetzung: CheckedContinuation<Void, Error>?

    init(teil: URL, erwartet: Int64, pruefAbstand: Int64, platzReicht: @escaping @Sendable (Int64) -> Bool,
         fortschritt: @escaping @Sendable (Int64) -> Void) {
        self.teil = teil
        self.erwartet = erwartet
        self.pruefAbstand = pruefAbstand
        self.platzReicht = platzReicht
        self.fortschritt = fortschritt
    }

    private var bereich: String { "bytes=\(start)-" }

    func laden(_ adresse: URL) async throws {
        let dateien = FileManager.default
        if !dateien.fileExists(atPath: teil.path) { dateien.createFile(atPath: teil.path, contents: nil) }
        start = (try? dateien.attributesOfItem(atPath: teil.path)[.size] as? NSNumber)?.int64Value ?? 0
        if start > erwartet {
            try Data().write(to: teil)
            start = 0
        }
        bytes = start
        naechstePruefung = start + pruefAbstand
        var anfrage = URLRequest(url: adresse, timeoutInterval: 60)
        // Komprimierung würde Grössen und Bereiche verfälschen.
        anfrage.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if start > 0 { anfrage.setValue(bereich, forHTTPHeaderField: "Range") }
        let warteschlange = OperationQueue()
        warteschlange.maxConcurrentOperationCount = 1
        let sitzung = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: warteschlange)
        defer { sitzung.finishTasksAndInvalidate() }
        let aufgabe = sitzung.dataTask(with: anfrage)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (fortsetzung: CheckedContinuation<Void, Error>) in
                schloss.lock()
                defer { schloss.unlock() }
                if let ende {
                    fortsetzung.resume(with: ende)
                } else {
                    self.fortsetzung = fortsetzung
                    aufgabe.resume()
                }
            }
        } onCancel: {
            aufgabe.cancel()
        }
    }

    private func abbrechen(_ grund: Error, _ aufgabe: URLSessionTask) {
        if fehler == nil { fehler = grund }
        aufgabe.cancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let antwort = response as? HTTPURLResponse
        let code = antwort?.statusCode ?? 0
        do {
            switch code {
            case 206:
                // Content-Range muss genau beim Teilstand beginnen und die ganze Datei meinen.
                let bereich = antwort?.value(forHTTPHeaderField: "Content-Range") ?? ""
                let zahlen = bereich.split(whereSeparator: { !$0.isNumber }).compactMap { Int64($0) }
                guard bereich.hasPrefix("bytes "), zahlen.count == 3, zahlen[0] == start, zahlen[1] == erwartet - 1,
                      zahlen[2] == erwartet else { throw Einrichtungsfehler.neuBeginnen }
                griff = try FileHandle(forWritingTo: teil)
                try griff?.seek(toOffset: UInt64(start))
            case 200:
                // Der Server hat die Range nicht beachtet: von vorne, nie anhängen.
                if response.expectedContentLength > 0 && response.expectedContentLength != erwartet {
                    throw Einrichtungsfehler.zuGross
                }
                guard response.mimeType != "text/html" else { throw Einrichtungsfehler.anmeldeseite }
                try Data().write(to: teil)
                start = 0
                bytes = 0
                griff = try FileHandle(forWritingTo: teil)
            case 416 where start == erwartet:
                schonFertig = true
                completionHandler(.cancel)
                return
            case 416:
                throw Einrichtungsfehler.neuBeginnen
            default:
                throw Einrichtungsfehler.server(code)
            }
            completionHandler(.allow)
        } catch {
            if fehler == nil { fehler = error }
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard fehler == nil, let griff else { return }
        guard bytes + Int64(data.count) <= erwartet else { return abbrechen(Einrichtungsfehler.zuGross, dataTask) }
        do {
            try griff.write(contentsOf: data)
        } catch {
            return abbrechen(Einrichtungsfehler.ausSchreibfehler(error), dataTask)
        }
        bytes += Int64(data.count)
        if bytes >= naechstePruefung {
            naechstePruefung = bytes + pruefAbstand
            guard platzReicht(erwartet - bytes) else { return abbrechen(Einrichtungsfehler.zuWenigPlatz(fehlt: 0), dataTask) }
        }
        if bytes - letzteMeldung >= 4 << 20 || bytes == erwartet {
            letzteMeldung = bytes
            fortschritt(bytes)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? griff?.close()
        griff = nil
        var wert: Result<Void, Error> = .success(())
        if schonFertig {
            wert = .success(())
        } else if let fehler {
            wert = .failure(fehler)
        } else if let error {
            wert = .failure((error as? URLError)?.code == .cancelled ? CancellationError() : error)
        } else if bytes != erwartet {
            // Die Verbindung endete vor dem Schluss. Der Teil bleibt, der nächste Versuch setzt dort fort.
            wert = .failure(URLError(.networkConnectionLost))
        }
        schloss.lock()
        defer { schloss.unlock() }
        if let fortsetzung {
            fortsetzung.resume(with: wert)
            self.fortsetzung = nil
        } else {
            ende = wert
        }
    }

    /// Weiterleitungen nur über https, im Prüfprogramm auch lokal. Die Range geht mit, damit das Fortsetzen auch beim
    /// Ziel gilt.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" || Pfade.testlauf else {
            fehler = Einrichtungsfehler.unsicher
            completionHandler(nil)
            return
        }
        #if TESTLAUF
        // Auch eine Weiterleitung führt im Prüfprogramm nie ins echte Netz.
        guard request.url?.host == "127.0.0.1" else {
            fehler = Einrichtungsfehler.unsicher
            completionHandler(nil)
            return
        }
        #endif
        var weiter = request
        weiter.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        weiter.setValue(start > 0 ? bereich : nil, forHTTPHeaderField: "Range")
        completionHandler(weiter)
    }
}

// MARK: Karte unter Neues Bild

/// Erscheint, solange MOSS-Image nicht fertig eingerichtet ist. Ins Netz geht es nur mit dem Knopf.
struct EinrichtungKarte: View {
    @ObservedObject var installation = Modellinstallation.gemeinsam
    @State private var frei: Int64?

    private func gb(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    var body: some View {
        Karte {
            VStack(alignment: .leading, spacing: 10) {
                KartenTitel(text: "Set Up MOSS-Image", symbol: "arrow.down.circle", farbe: .accentColor)
                Text("To make images, the app needs the MOSS-Image model (\(gb(installation.manifest.bytes(.modell)))) and the Turbo module (\(gb(installation.manifest.bytes(.modul)))) once. It downloads both from Hugging Face as soon as you click Download. After that, it works without internet.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                inhalt
            }
        }
        .onAppear { frei = Modellinstallation.platzAufVolume(Pfade.modelle) }
    }

    @ViewBuilder
    private var inhalt: some View {
        switch installation.zustand {
        case .fehlt(let vorhanden):
            platzZeile(vorhanden: vorhanden)
            HStack(spacing: 10) {
                Button(vorhanden > 0 ? "Resume (\(gb(installation.manifest.bytes - vorhanden)) left)"
                       : "Download (\(gb(installation.manifest.bytes)))") { installation.laden() }
                    .buttonStyle(.borderedProminent)
                Text("License Apache 2.0").font(.caption).foregroundStyle(.secondary)
            }
            hinweis(String(localized: "You can close the app meanwhile. The next time you click Resume, it continues where it stopped."))
        case .laedt(let geladen, let gesamt, let datei, let von):
            ProgressView(value: Double(geladen), total: Double(max(gesamt, 1)))
            HStack {
                Text("\(gb(geladen)) of \(gb(gesamt)), file \(datei) of \(von)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Pause") { installation.anhalten() }.controlSize(.small)
            }
        case .prueft(let datei, let von):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking, file \(datei) of \(von)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        case .ungeprueft:
            hinweis(String(localized: "The model files are there, but not checked yet. This takes about a minute and needs no internet."))
            Button("Check") { installation.pruefen() }.buttonStyle(.borderedProminent)
        case .beschaedigt(let anzahl):
            Text(anzahl == 1 ? "1 file is missing or damaged." : "\(anzahl) files are missing or damaged.")
                .font(.caption).foregroundStyle(.orange)
            Button("Repair") { installation.laden() }.buttonStyle(.borderedProminent)
            hinweis(String(localized: "The app only downloads the faulty files again, the good ones stay."))
        case .fehler(let text, let platzUnbekannt):
            Text(verbatim: text).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if platzUnbekannt {
                    Button("Download Anyway") { installation.laden(trotzUnbekanntemPlatz: true) }.buttonStyle(.borderedProminent)
                } else {
                    Button("Resume") { installation.laden() }.buttonStyle(.borderedProminent)
                }
            }
        case .bereit:
            Label("MOSS-Image is set up.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private func platzZeile(vorhanden: Int64) -> some View {
        let noetig = installation.manifest.bytes - vorhanden + Modellinstallation.reserve
        if let frei {
            Text("Free on this Mac: \(gb(frei)). About \(gb(noetig)) is needed.")
                .font(.caption).foregroundStyle(frei < noetig ? .red : .secondary).monospacedDigit()
        } else {
            Text("The free space could not be determined. About \(gb(noetig)) is needed.")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private func hinweis(_ text: String) -> some View {
        Text(verbatim: text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

extension Modellinstallation.Zustand {
    /// Schon geladene Bytes, solange etwas fehlt.
    var vorhanden: Int64 {
        if case .fehlt(let bytes) = self { return bytes }
        return 0
    }

    var fehlerText: String {
        if case .fehler(let text, _) = self { return text }
        return ""
    }

    var platzUnbekannt: Bool {
        if case .fehler(_, true) = self { return true }
        return false
    }
}
