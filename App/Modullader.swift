import CryptoKit
import Foundation

/// Holt Module aus dem Katalog, nur nach einem Klick auf Laden. Sonst geht die App nur für die Einrichtung des Modells
/// ins Netz und, wenn es erlaubt ist, für die Suche nach neuen Versionen. Prompts und Bilder sind daran nie beteiligt.
@MainActor
final class Modullader: ObservableObject {
    static let gemeinsam = Modullader()

    enum Stand: Equatable {
        case laedt(Double)
        case prueft
        case fehler(String)
    }

    @Published private(set) var staende: [String: Stand] = [:]
    private var aufgaben: [String: Task<Void, Never>] = [:]

    func laeuft(_ eintrag: Katalogeintrag) -> Bool {
        aufgaben[eintrag.datei] != nil
    }

    func laden(_ eintrag: Katalogeintrag) {
        guard aufgaben[eintrag.datei] == nil else { return }
        let datei = eintrag.datei
        staende[datei] = .laedt(0)
        aufgaben[datei] = Task {
            defer { aufgaben[datei] = nil }
            do {
                #if TESTLAUF
                // Das Prüfprogramm geht nie ins echte Netz, nur zu seinem lokalen Testserver.
                guard eintrag.download.host == "127.0.0.1" else { throw Ladefehler.server(0) }
                #endif
                guard Self.genugPlatz(eintrag.bytes) else { throw Ladefehler.zuWenigPlatz }
                let zwischen = try await herunterladen(eintrag)
                defer { try? FileManager.default.removeItem(at: zwischen) }
                staende[datei] = .prueft
                try await Task.detached { try Self.pruefen(zwischen, sha256: eintrag.sha256) }.value
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: Pfade.module, withIntermediateDirectories: true)
                let ziel = Pfade.module.appendingPathComponent(datei)
                // Eine gleichnamige Datei bleibt liegen, wartende Aufträge könnten sie schon verwenden.
                if !FileManager.default.fileExists(atPath: ziel.path) {
                    try FileManager.default.moveItem(at: zwischen, to: ziel)
                }
                staende[datei] = nil
                Vorgaben.gemeinsam.moduleLaden()
            } catch is CancellationError {
                staende[datei] = nil
            } catch is URLError {
                staende[datei] = .fehler(String(localized: "The connection was lost. Check your internet connection and try again."))
            } catch {
                staende[datei] = .fehler(error.localizedDescription)
            }
        }
    }

    func abbrechen(_ eintrag: Katalogeintrag) {
        aufgaben[eintrag.datei]?.cancel()
    }

    private func herunterladen(_ eintrag: Katalogeintrag) async throws -> URL {
        let anfrage = URLRequest(url: eintrag.download, timeoutInterval: 60)
        let datei = eintrag.datei
        let helfer = Ladehelfer(erwartet: eintrag.bytes) { [weak self] anteil in
            Task { @MainActor in
                if case .laedt = self?.staende[datei] { self?.staende[datei] = .laedt(anteil) }
            }
        }
        return try await helfer.laden(anfrage)
    }

    private nonisolated static func genugPlatz(_ bytes: Int64) -> Bool {
        let werte = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return (werte?.volumeAvailableCapacityForImportantUsage ?? .max) > bytes + 1_000_000_000
    }

    /// Übernommen wird nur genau die Datei, die im Katalog steht und die mflux lesen kann.
    private nonisolated static func pruefen(_ url: URL, sha256 erwartet: String) throws {
        let griff = try FileHandle(forReadingFrom: url)
        defer { try? griff.close() }
        var rechner = SHA256()
        while let stueck = try griff.read(upToCount: 1 << 20), !stueck.isEmpty {
            rechner.update(data: stueck)
        }
        let wert = rechner.finalize().map { String(format: "%02x", $0) }.joined()
        guard wert == erwartet.lowercased() else { throw Ladefehler.falscheDatei }
        Modul.angleichen(url)
        guard let format = Modul.dateiformat(url), format != .unbrauchbar else { throw Ladefehler.unpassend }
    }
}

private enum Ladefehler: LocalizedError {
    case server(Int)
    case anmeldeseite
    case zuGross
    case falscheDatei
    case unpassend
    case zuWenigPlatz

    var errorDescription: String? {
        switch self {
        case .server(let code) where code == 401 || code == 403:
            String(localized: "The source does not hand out this file. Try again later.")
        case .server(404):
            String(localized: "The file no longer exists at this address.")
        case .server(let code) where (300..<400).contains(code):
            String(localized: "The source tried to redirect to an unsafe address. The app blocked this.")
        case .server(let code):
            String(localized: "The server reports error \(code). Try again later.")
        case .anmeldeseite:
            String(localized: "A web page came back instead of the file. Try again later.")
        case .zuGross:
            String(localized: "The file is larger than expected. The app stopped the download.")
        case .falscheDatei:
            String(localized: "The file does not match the expected one and was not kept.")
        case .unpassend:
            String(localized: "This file does not fit any model in the app and was not kept.")
        case .zuWenigPlatz:
            String(localized: "There is not enough space on the Mac for this module.")
        }
    }
}

/// Eine einzelne Übertragung. Die Sitzung speichert weder Cookies noch Zwischenstände.
private final class Ladehelfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let erwartet: Int64
    private let fortschritt: @Sendable (Double) -> Void
    private var zuGross = false
    private var letzterAnteil = 0.0
    private var ergebnis: Result<URL, Error>?
    /// Schützt beide Werte: Ein Abbruch kann fertig sein, bevor das Warten beginnt.
    private let schloss = NSLock()
    private var ende: Result<URL, Error>?
    private var fortsetzung: CheckedContinuation<URL, Error>?

    init(erwartet: Int64, fortschritt: @escaping @Sendable (Double) -> Void) {
        self.erwartet = erwartet
        self.fortschritt = fortschritt
    }

    func laden(_ anfrage: URLRequest) async throws -> URL {
        let sitzung = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { sitzung.finishTasksAndInvalidate() }
        let aufgabe = sitzung.downloadTask(with: anfrage)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { fortsetzung in
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

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Der Fingerabdruck greift erst am Schluss. Eine falsche grosse Datei darf die Platte nicht füllen.
        guard totalBytesWritten <= erwartet + erwartet / 5 + 1_000_000 else {
            zuGross = true
            downloadTask.cancel()
            return
        }
        let gesamt = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : erwartet
        let anteil = min(Double(totalBytesWritten) / Double(max(gesamt, 1)), 1)
        guard anteil - letzterAnteil >= 0.01 else { return }
        letzterAnteil = anteil
        fortschritt(anteil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            ergebnis = .failure(Ladefehler.server(code))
            return
        }
        guard downloadTask.response?.mimeType != "text/html" else {
            ergebnis = .failure(Ladefehler.anmeldeseite)
            return
        }
        let ziel = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".safetensors")
        do {
            try FileManager.default.moveItem(at: location, to: ziel)
            ergebnis = .success(ziel)
        } catch {
            ergebnis = .failure(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        var wert = ergebnis ?? .failure(URLError(.unknown))
        if zuGross {
            wert = .failure(Ladefehler.zuGross)
        } else if let error {
            wert = .failure((error as? URLError)?.code == .cancelled ? CancellationError() : error)
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

    /// Hugging Face leitet zu einem Speicherdienst weiter. Weiter geht es nur über https, im Prüfprogramm auch lokal.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" || Pfade.testlauf else {
            completionHandler(nil)
            return
        }
        #if TESTLAUF
        // Auch eine Weiterleitung führt im Prüfprogramm nie ins echte Netz.
        guard request.url?.host == "127.0.0.1" else {
            completionHandler(nil)
            return
        }
        #endif
        completionHandler(request)
    }
}
