import Foundation

/// Fragt auf Wunsch bei GitHub nach, ob es eine neuere Version gibt. Aus, bis der Nutzer es erlaubt, dann beim Start
/// höchstens einmal am Tag. Die Anfrage nennt nur die Adresse der Projektseite, keine Angaben zum Nutzer, zum Mac
/// oder zur Sprache. Die App lädt nie etwas herunter: Ist eine neuere Version da, zeigt sie einen Hinweis, dessen Klick
/// die Seite im Browser öffnet. Fehler bleiben still.
@MainActor
final class Versionspruefung: ObservableObject {
    static let gemeinsam = Versionspruefung()

    /// Eine neuere Version und ihre Seite auf GitHub.
    struct Fund: Equatable, Sendable {
        let version: String
        let seite: URL
    }

    /// Was eine Antwort von GitHub hergibt.
    enum Befund: Equatable, Sendable {
        case neuer(Fund)
        /// Die Antwort ist gültig, aber nicht neuer als diese App.
        case aktuell
        /// Unlesbar, ein Entwurf, eine Vorabversion oder eine Seite ausserhalb des Projekts: wird übergangen.
        case unbrauchbar
    }

    /// nil, solange der Nutzer nicht gefragt wurde.
    @Published private(set) var erlaubt: Bool?
    @Published private(set) var neu: Fund?
    /// Die Frage kommt je Programmstart höchstens einmal, auch bei mehreren Fenstern.
    var frageGestellt = false

    let adresse: URL
    private let speicher: UserDefaults
    private let aktuelleVersion: String
    private let jetzt: () -> Date
    private var aufgabe: Task<Void, Never>?

    /// Höchstens eine Anfrage je so viele Sekunden.
    nonisolated static let abstand: TimeInterval = 24 * 60 * 60

    /// Die Schlüssel in den Einstellungen. Sie bleiben gleich, sonst gingen Antwort und Stand verloren.
    enum Schluessel {
        static let erlaubt = "versionenPruefen"
        static let geprueftAm = "versionenGeprueftAm"
        static let version = "neueVersion"
        static let seite = "neueVersionSeite"
    }

    /// Im Prüfprogramm fragt die App nur ihren lokalen Testserver, nie GitHub.
    nonisolated static var standardAdresse: URL {
        #if TESTLAUF
        return Testumgebung.versionenAdresse
        #else
        return Fassung.neusteVersion
        #endif
    }

    init(speicher: UserDefaults = Pfade.speicher, adresse: URL = Versionspruefung.standardAdresse,
         aktuelleVersion: String = Fassung.version, jetzt: @escaping () -> Date = Date.init) {
        self.speicher = speicher
        self.adresse = adresse
        self.aktuelleVersion = aktuelleVersion
        self.jetzt = jetzt
        erlaubt = speicher.object(forKey: Schluessel.erlaubt) as? Bool
        let fund = gespeicherterFund()
        neu = erlaubt == true ? fund : nil
    }

    /// Ein früherer Fund gilt nur, solange er neuer ist als diese App und seine Seite im Projekt liegt. Sonst, etwa
    /// nach einem Update, verschwindet er auch aus den Einstellungen.
    private func gespeicherterFund() -> Fund? {
        if let version = speicher.string(forKey: Schluessel.version), let text = speicher.string(forKey: Schluessel.seite),
           let seite = URL(string: text), Self.projektseite(seite), Self.istNeuer(version, als: aktuelleVersion) {
            return Fund(version: version, seite: seite)
        }
        fundSichern(nil)
        return nil
    }

    /// Muss der Nutzer noch gefragt werden?
    var frageOffen: Bool { erlaubt == nil }

    /// Die Antwort auf die Frage oder der Schalter in den Einstellungen. Aus blendet einen Fund nur aus, wieder an zeigt
    /// ihn gleich wieder. Mit Ja wird nachgefragt, wenn es fällig ist, und die Anfrage kommt zurück.
    @discardableResult
    func erlauben(_ ja: Bool) -> Task<Void, Never>? {
        erlaubt = ja
        speicher.set(ja, forKey: Schluessel.erlaubt)
        if ja {
            neu = gespeicherterFund()
            return pruefenFallsFaellig()
        }
        aufgabe?.cancel()
        neu = nil
        return nil
    }

    /// Erlaubt und der letzte Versuch mindestens einen Tag her. Steht die Uhr vor dem letzten Versuch, wurde sie
    /// zurückgestellt, dann gilt er nicht.
    var faellig: Bool {
        guard erlaubt == true else { return false }
        let letzte = speicher.double(forKey: Schluessel.geprueftAm)
        guard letzte > 0 else { return true }
        let vergangen = jetzt().timeIntervalSince1970 - letzte
        return vergangen >= Self.abstand || vergangen < 0
    }

    /// Beim Start: fragt nach, wenn es erlaubt und fällig ist. Der Versuch zählt, auch wenn er scheitert.
    /// Liefert die laufende Anfrage, damit das Prüfprogramm auf sie warten kann.
    @discardableResult
    func pruefenFallsFaellig() -> Task<Void, Never>? {
        guard faellig, aufgabe == nil else { return nil }
        speicher.set(jetzt().timeIntervalSince1970, forKey: Schluessel.geprueftAm)
        let adresse = adresse
        let aktuell = aktuelleVersion
        let neueAufgabe = Task {
            defer { aufgabe = nil }
            guard let daten = await Self.abfragen(adresse), !Task.isCancelled, erlaubt == true else { return }
            switch Self.auswerten(daten, aktuell: aktuell) {
            case .neuer(let fund): fundSichern(fund)
            case .aktuell: fundSichern(nil)
            case .unbrauchbar: break
            }
        }
        aufgabe = neueAufgabe
        return neueAufgabe
    }

    /// Hält einen Fund fest und zeigt ihn. nil löscht ihn.
    private func fundSichern(_ fund: Fund?) {
        neu = fund
        if let fund {
            speicher.set(fund.version, forKey: Schluessel.version)
            speicher.set(fund.seite.absoluteString, forKey: Schluessel.seite)
        } else {
            speicher.removeObject(forKey: Schluessel.version)
            speicher.removeObject(forKey: Schluessel.seite)
        }
    }

    // MARK: Ohne Zustand, auch für das Prüfprogramm

    /// Eine Version wie 1.2 oder v1.2.3 als Zahlen. Alles andere, etwa 1.2-beta, ist keine Version.
    nonisolated static func zahlen(_ text: String) -> [Int]? {
        var rest = Substring(text)
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
        let teile = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(teile.count) else { return nil }
        var zahlen = [Int]()
        for teil in teile {
            guard (1...9).contains(teil.count), teil.allSatisfy({ ("0"..."9").contains($0) }),
                  let zahl = Int(teil) else { return nil }
            zahlen.append(zahl)
        }
        return zahlen
    }

    /// Vergleicht Stelle für Stelle als Zahlen, so ist 1.10 neuer als 1.9 und 1.0 gleich 1.0.0.
    nonisolated static func istNeuer(_ kandidat: String, als aktuell: String) -> Bool {
        guard let neu = zahlen(kandidat), let alt = zahlen(aktuell) else { return false }
        for stelle in 0..<max(neu.count, alt.count) {
            let a = stelle < neu.count ? neu[stelle] : 0
            let b = stelle < alt.count ? alt[stelle] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Nur https auf github.com und im eigenen Projekt, ohne Anmeldedaten, ohne Port und ohne Pfadteile, die
    /// hinausführen.
    nonisolated static func projektseite(_ url: URL) -> Bool {
        guard let teile = URLComponents(url: url, resolvingAgainstBaseURL: false),
              teile.scheme?.lowercased() == "https", teile.host?.lowercased() == "github.com",
              teile.user == nil, teile.password == nil, teile.port == nil else { return false }
        let pfad = teile.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard pfad.count >= 3, pfad[0].isEmpty,
              pfad[1].lowercased() == Fassung.projektBesitzer.lowercased(),
              pfad[2].lowercased() == Fassung.projektName.lowercased() else { return false }
        return !pfad.contains { $0 == "." || $0 == ".." || $0.contains("\\") }
    }

    /// Liest die Antwort von releases/latest: tag_name und html_url, ohne Entwürfe und Vorabversionen.
    nonisolated static func auswerten(_ daten: Data, aktuell: String) -> Befund {
        guard let antwort = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any],
              let tag = antwort["tag_name"] as? String, let version = zahlen(tag),
              antwort["draft"] as? Bool != true, antwort["prerelease"] as? Bool != true,
              let text = antwort["html_url"] as? String, let seite = URL(string: text), projektseite(seite)
        else { return .unbrauchbar }
        guard istNeuer(tag, als: aktuell) else { return .aktuell }
        return .neuer(Fund(version: version.map(String.init).joined(separator: "."), seite: seite))
    }

    /// Eine einzige GET-Anfrage, ohne Cookies, ohne Zwischenspeicher und mit kurzer Frist. Kennung und Sprache sind
    /// fest, damit sie nichts über den Mac verraten. Liefert nur eine vollständige Antwort mit Status 200.
    nonisolated static func abfragen(_ adresse: URL) async -> Data? {
        #if TESTLAUF
        guard adresse.host == "127.0.0.1" else { return nil }
        #else
        guard adresse.scheme == "https" else { return nil }
        #endif
        let einstellung = URLSessionConfiguration.ephemeral
        einstellung.httpCookieStorage = nil
        einstellung.httpShouldSetCookies = false
        einstellung.urlCredentialStorage = nil
        einstellung.urlCache = nil
        einstellung.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        einstellung.timeoutIntervalForRequest = 10
        einstellung.timeoutIntervalForResource = 20
        einstellung.waitsForConnectivity = false
        let sitzung = URLSession(configuration: einstellung, delegate: Umleitungswache(), delegateQueue: nil)
        defer { sitzung.finishTasksAndInvalidate() }
        var anfrage = URLRequest(url: adresse)
        anfrage.httpMethod = "GET"
        anfrage.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        anfrage.setValue(Fassung.name, forHTTPHeaderField: "User-Agent")
        anfrage.setValue("en", forHTTPHeaderField: "Accept-Language")
        guard let (daten, antwort) = try? await sitzung.data(for: anfrage),
              (antwort as? HTTPURLResponse)?.statusCode == 200, daten.count <= 1_000_000 else { return nil }
        return daten
    }
}

/// Folgt einer Weiterleitung nur zum selben Server über https, im Prüfprogramm nur zum lokalen Testserver.
private final class Umleitungswache: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        #if TESTLAUF
        let erlaubt = request.url?.host == "127.0.0.1"
        #else
        let erlaubt = request.url?.scheme == "https" && request.url?.host == Fassung.neusteVersion.host
        #endif
        completionHandler(erlaubt ? request : nil)
    }
}
