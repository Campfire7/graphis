import Foundation

/// Das Modell, mit dem die App rechnet. Graphis kennt nur MOSS-Image, denn dessen Lizenz (Apache 2.0) erlaubt die
/// freie Weitergabe. Gespeicherte Angaben mit einem anderen Modellnamen werden beim Lesen übergangen, nie geraten.
enum ModellID: String, CaseIterable, Codable, Identifiable {
    case moss

    var id: String { rawValue }
    var name: String { "MOSS-Image" }
    var hinweis: String { String(localized: "Best results, extendable with modules") }
    /// Der Name, unter dem mflux das Modell kennt.
    var basisModell: String { "moss-image" }
    var ordnerName: String { "moss-image-q8" }

    /// Turbo braucht wenige Schritte, ohne Turbo sind es viele.
    func schrittBereich(turbo: Bool) -> ClosedRange<Int> {
        turbo ? 4...16 : 10...60
    }

    var schrittTipp: String { String(localized: "With Turbo, 8 is right, without Turbo 30 to 50.") }
    var textfuehrungTipp: String { String(localized: "With Turbo, 1 is right, without Turbo 3.") }

    func vorgabe(_ stufe: Stufe) -> ModellEinstellung {
        switch stufe {
        case .schnell, .standard: return ModellEinstellung(schritte: 8, textfuehrung: 1, turbo: true)
        case .beste: return ModellEinstellung(schritte: 30, textfuehrung: 3, turbo: false)
        }
    }
}

struct ModellEinstellung: Codable, Equatable {
    var schritte: Int
    var textfuehrung: Double
    var turbo = false

    init(schritte: Int, textfuehrung: Double, turbo: Bool) {
        self.schritte = schritte
        self.textfuehrung = textfuehrung
        self.turbo = turbo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schritte = try c.decode(Int.self, forKey: .schritte)
        textfuehrung = try c.decode(Double.self, forKey: .textfuehrung)
        turbo = try c.decodeIfPresent(Bool.self, forKey: .turbo) ?? false
    }

    /// Bei Textführung 1 ignoriert das Modell den Negativprompt, darum wird sie dann angehoben.
    func wirksameTextfuehrung(negativ: String) -> Double {
        let hatNegativ = !negativ.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hatNegativ && textfuehrung <= 1 ? 2 : textfuehrung
    }

    /// Liest gespeicherte Einstellungen je Modell. JSON legt ein Wörterbuch mit Modellschlüssel als Liste
    /// [Schlüssel, Wert, Schlüssel, Wert] ab. Unbekannte Modelle und unlesbare Werte fallen weg, statt dass alles scheitert.
    static func lesen(_ daten: Data) -> [ModellID: ModellEinstellung] {
        guard let roh = try? JSONSerialization.jsonObject(with: daten) else { return [:] }
        var paare = [(Any, Any)]()
        if let liste = roh as? [Any] {
            paare = stride(from: 0, to: liste.count - 1, by: 2).map { (liste[$0], liste[$0 + 1]) }
        } else if let woerterbuch = roh as? [String: Any] {
            paare = woerterbuch.map { ($0.key, $0.value) }
        }
        var werte = [ModellID: ModellEinstellung]()
        for (schluessel, wert) in paare {
            guard let name = schluessel as? String, let modell = ModellID(rawValue: name),
                  JSONSerialization.isValidJSONObject(wert),
                  let teil = try? JSONSerialization.data(withJSONObject: wert),
                  let einstellung = try? JSONDecoder().decode(ModellEinstellung.self, from: teil) else { continue }
            werte[modell] = einstellung
        }
        return werte
    }
}

/// Der Rohwert ist gespeichert und bleibt in jeder Sprache gleich, angezeigt wird anzeigeName.
enum Stufe: String, CaseIterable, Identifiable {
    case schnell = "Schnell"
    case standard = "Standard"
    case beste = "Beste"

    var id: String { rawValue }
    var laengeSeite: Int { self == .schnell ? 768 : 1024 }

    var anzeigeName: String {
        switch self {
        case .schnell: String(localized: "Fast")
        case .standard: String(localized: "Standard")
        case .beste: String(localized: "Best")
        }
    }

    static var erklaerung: String {
        String(localized: """
        Sets image size and calculation mode together.

        Fast: 768 pixels with the Turbo module, 8 steps. For drafts.

        Standard: 1024 pixels with the Turbo module, 8 steps. A good everyday choice.

        Best: 1024 pixels without Turbo, 30 steps. Full quality, takes much longer.

        A click overwrites image size, steps, Turbo and guidance. If your values match no level, it says Custom here.
        """)
    }
}

/// Der Rohwert steht in gespeicherten Einstellungen und Bildangaben und bleibt in jeder Sprache gleich.
enum Bildformat: String, CaseIterable, Identifiable {
    case quadrat = "Quadrat"
    case hoch = "Hochformat 2:3"
    case quer = "Querformat 3:2"
    case breit = "Breitbild 16:9"
    case schmal = "Hochkant 9:16"

    var id: String { rawValue }

    var anzeigeName: String {
        switch self {
        case .quadrat: String(localized: "Square")
        case .hoch: String(localized: "Portrait 2:3")
        case .quer: String(localized: "Landscape 3:2")
        case .breit: String(localized: "Widescreen 16:9")
        case .schmal: String(localized: "Tall 9:16")
        }
    }

    /// Ein gespeicherter Name in der Sprache des Mac. Unbekannte Namen erscheinen, wie sie sind.
    static func anzeige(_ name: String) -> String {
        Bildformat(rawValue: name)?.anzeigeName ?? name
    }

    private var verhaeltnis: (Double, Double) {
        switch self {
        case .quadrat: return (1, 1)
        case .hoch: return (2, 3)
        case .quer: return (3, 2)
        case .breit: return (16, 9)
        case .schmal: return (9, 16)
        }
    }

    func masse(laengeSeite: Int) -> (breite: Int, hoehe: Int) {
        let (b, h) = verhaeltnis
        let groesste = max(b, h)
        return (runde64(Double(laengeSeite) * b / groesste), runde64(Double(laengeSeite) * h / groesste))
    }
}

func runde16(_ wert: Double) -> Int {
    max(Int((wert / 16).rounded()), 1) * 16
}

func runde64(_ wert: Double) -> Int {
    max(Int((wert / 64).rounded()), 1) * 64
}

/// Ein zugeschaltetes Modul mit seiner Stärke, festgehalten im Auftrag.
struct GewaehltesModul: Codable, Hashable {
    let name: String
    let pfad: String
    let staerke: Double
}

/// Ein einzelnes Bild, das berechnet werden soll.
struct Auftrag: Identifiable, Codable {
    var id = UUID()
    let gruppe: UUID
    let prompt: String
    let negativ: String
    let modell: ModellID
    let schritte: Int
    let textfuehrung: Double
    let breite: Int
    let hoehe: Int
    let seed: Int
    var referenzen: [URL]
    var turbo = false
    var module: [GewaehltesModul] = []
    /// Wörter, die ein Modul im Prompt braucht. Sie gehen nur ans Modell.
    var ausloeser: String? = nil
    /// Wie nah das Bild am Referenzbild bleibt: 0 ohne Einfluss, 1 unverändert.
    var referenzStaerke: Double? = nil
    /// Das gewählte Format, weil kleine Bilder bei mehreren Formaten gleich gross sind.
    var formatName: String? = nil

    /// Über Textführung 1 rechnet das Modell jeden Schritt zweimal.
    var durchgaenge: Int { textfuehrung > 1 ? 2 : 1 }

    /// MOSS rechnet auch mit Referenzbild alle Schritte, nur auf einem kürzeren Weg.
    var rechenSchritte: Int { schritte }
}

/// Neue Felder dürfen fehlen, sonst wäre eine gespeicherte Warteschlange nach einem Update unlesbar.
/// Mehr Referenzbilder als erlaubt kommen nie zurück, MOSS nutzt nur das erste.
extension Auftrag {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        gruppe = try c.decode(UUID.self, forKey: .gruppe)
        prompt = try c.decode(String.self, forKey: .prompt)
        negativ = try c.decodeIfPresent(String.self, forKey: .negativ) ?? ""
        modell = try c.decode(ModellID.self, forKey: .modell)
        schritte = try c.decode(Int.self, forKey: .schritte)
        textfuehrung = try c.decodeIfPresent(Double.self, forKey: .textfuehrung) ?? 1
        breite = try c.decode(Int.self, forKey: .breite)
        hoehe = try c.decode(Int.self, forKey: .hoehe)
        seed = try c.decode(Int.self, forKey: .seed)
        let gespeichert = try c.decodeIfPresent([URL].self, forKey: .referenzen) ?? []
        referenzen = Array(gespeichert.prefix(Vorgaben.hoechstensReferenzen))
        turbo = try c.decodeIfPresent(Bool.self, forKey: .turbo) ?? false
        module = try c.decodeIfPresent([GewaehltesModul].self, forKey: .module) ?? []
        ausloeser = try c.decodeIfPresent(String.self, forKey: .ausloeser)
        referenzStaerke = try c.decodeIfPresent(Double.self, forKey: .referenzStaerke)
        formatName = try c.decodeIfPresent(String.self, forKey: .formatName)
    }
}

/// Ein fertiges Bild samt allen Einstellungen, gespeichert als JSON neben dem PNG.
struct Ergebnis: Identifiable, Codable, Hashable {
    var id: String { datei }
    let datei: String
    let gruppe: UUID
    let prompt: String
    let negativ: String
    let modell: ModellID
    let seed: Int
    let breite: Int
    let hoehe: Int
    let schritte: Int
    let textfuehrung: Double
    let sekunden: Double
    let geschaetzt: Double
    let referenzen: Int
    var module: [String]? = nil
    var auftrag: UUID? = nil
    var hinweis: String? = nil
    /// Genaue Werte, damit sich die Einstellungen eines Bildes eins zu eins übernehmen lassen.
    var turbo: Bool? = nil
    var modulDaten: [GewaehltesModul]? = nil
    var referenzStaerke: Double? = nil
    /// Name der Kopie des Referenzbildes im versteckten Ordner .referenzen.
    var referenzDatei: String? = nil
    var formatName: String? = nil
    /// Wörter, die Module dem Prompt für das Modell vorangestellt haben.
    var ausloeser: String? = nil
    /// Namen der Kopien aller Referenzbilder in ihrer Reihenfolge. Manche Angaben kennen nur referenzDatei.
    var referenzDateien: [String]? = nil
}

extension Ergebnis {
    /// Die Referenzbilder in ihrer Reihenfolge, für beide Arten von Angaben gleich.
    var referenzNamen: [String] { referenzDateien ?? referenzDatei.map { [$0] } ?? [] }
}

/// Ein Klick auf "Bild erzeugen": eines oder mehrere Bilder, die zusammen in die Warteschlange gehen.
struct Stapel: Identifiable, Codable {
    let id: UUID
    let prompt: String
    var auftraege: [Auftrag]
    let laengeSeite: Int
}

/// Liest einen Wert, ohne dass ein einzelner unlesbarer Eintrag die ganze Liste unbrauchbar macht.
struct Nachsichtig<Wert: Decodable>: Decodable {
    let wert: Wert?

    init(from decoder: Decoder) throws {
        wert = try? Wert(from: decoder)
    }
}

/// So liest die App eine gespeicherte Warteschlange: Aufträge, die sich nicht lesen lassen, etwa weil ihr Modell
/// fehlt, fallen weg und werden gezählt. Der Rest bleibt in seiner Reihenfolge.
struct GespeicherterStapel: Decodable {
    let id: UUID
    let prompt: String
    let auftraege: [Nachsichtig<Auftrag>]
    let laengeSeite: Int

    var stapel: Stapel {
        Stapel(id: id, prompt: prompt, auftraege: auftraege.compactMap(\.wert), laengeSeite: laengeSeite)
    }

    var ausgelassen: Int { auftraege.filter { $0.wert == nil }.count }
}

/// Alles, was mit einem Klick auf "Bild erzeugen" entstanden ist.
struct Lauf: Identifiable {
    let id: UUID
    let prompt: String
    let ergebnisse: [Ergebnis]

    var modelle: [ModellID] { ModellID.allCases.filter { modell in ergebnisse.contains { $0.modell == modell } } }
    var dauer: Double { ergebnisse.map(\.sekunden).reduce(0, +) }
    var untertitel: String {
        ergebnisse.count == 1 ? String(localized: "1 image") : String(localized: "\(ergebnisse.count) images")
    }
}

/// Die Pfeiltasten in der Grossansicht.
enum Pfeil {
    case hoch, runter, links, rechts
}

extension Array where Element == Lauf {
    /// Das Bild, zu dem eine Pfeiltaste führt. Hoch und runter wechseln die Generierung wie im Verlauf,
    /// links und rechts das Bild darin. Läufe ohne fertiges Bild zählen nicht, am Rand bleibt es stehen.
    func nachbar(von bild: Ergebnis, _ pfeil: Pfeil) -> Ergebnis? {
        let fertige = filter { !$0.ergebnisse.isEmpty }
        guard let stelle = fertige.firstIndex(where: { $0.id == bild.gruppe }),
              let nummer = fertige[stelle].ergebnisse.firstIndex(where: { $0.id == bild.id }) else { return nil }
        let bilder = fertige[stelle].ergebnisse
        switch pfeil {
        case .links: return nummer > 0 ? bilder[nummer - 1] : nil
        case .rechts: return nummer + 1 < bilder.count ? bilder[nummer + 1] : nil
        case .hoch, .runter:
            let ziel = stelle + (pfeil == .hoch ? -1 : 1)
            guard fertige.indices.contains(ziel) else { return nil }
            // Gleiche Stelle wie vorher, damit sich Bilder derselben Einstellung direkt vergleichen lassen.
            return fertige[ziel].ergebnisse[Swift.min(nummer, fertige[ziel].ergebnisse.count - 1)]
        }
    }
}

enum Pfade {
    /// Der Rechenmotor liegt fertig im App-Paket und wird dort nie verändert.
    static var paketMotor: URL {
        (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("Motor", isDirectory: true)
    }

    /// Programm und vorangestellte Argumente für einen Auftrag: immer das Python im Paket mit -I -B und vollem Pfad
    /// zum Startskript, nie ein Motor ausserhalb des Pakets. Mit Referenzbild läuft MOSS über moss_referenz.py.
    /// Im Prüfprogramm rechnet stattdessen ein Scheinprogramm.
    static func aufruf(mitReferenz: Bool = false) -> (programm: String, vorweg: [String]) {
        let echt = (programm: paketMotor.appendingPathComponent("python/bin/python3.12").path,
                    vorweg: ["-I", "-B", paketMotor.appendingPathComponent("motor_start.py").path,
                             mitReferenz ? "referenz" : "bild"])
        #if TESTLAUF
        return (Testumgebung.programm, echt.vorweg)
        #else
        return echt
        #endif
    }

    /// Nur das Prüfprogramm hat einen Testordner. Dort liegt alles, was ein Prüflauf schreibt, getrennt von echten Daten.
    #if TESTLAUF
    static let testordner: URL? = Testumgebung.ordner
    #else
    static let testordner: URL? = nil
    #endif

    /// Nur im Prüfprogramm darf die App über http von ihrem lokalen Testserver laden.
    static var testlauf: Bool { testordner != nil }

    private static var zuhause: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var bilder: URL {
        testordner ?? zuhause.appendingPathComponent("Downloads/\(Fassung.ordnerName)", isDirectory: true)
    }

    private static var appOrdner: URL {
        testordner ?? zuhause.appendingPathComponent("Library/Application Support/\(Fassung.ordnerName)", isDirectory: true)
    }

    static var modelle: URL { appOrdner.appendingPathComponent("Modelle", isDirectory: true) }

    static func ordner(_ modell: ModellID) -> URL {
        modelle.appendingPathComponent(modell.ordnerName, isDirectory: true)
    }

    /// Schreibbare Zwischenspeicher des Motors, ausserhalb des schreibgeschützten App-Pakets.
    static var zwischenspeicher: URL { appOrdner.appendingPathComponent("Zwischenspeicher", isDirectory: true) }

    /// Kopien der Referenzbilder, damit sich die Einstellungen eines Bildes auch später übernehmen lassen.
    static var referenzen: URL { bilder.appendingPathComponent(".referenzen", isDirectory: true) }

    /// Die Kopie eines Referenzbildes. Ein Name mit Pfadteilen zeigte aus dem Ordner hinaus und gilt nicht.
    static func referenzKopie(_ name: String) -> URL? {
        guard !name.isEmpty, name != ".", name != "..", (name as NSString).lastPathComponent == name else { return nil }
        return referenzen.appendingPathComponent(name)
    }

    static var module: URL { appOrdner.appendingPathComponent("Module", isDirectory: true) }

    /// Liegt im Bildordner, weil die Warteschlange Prompts enthält.
    static var warteDatei: URL { bilder.appendingPathComponent(".warteschlange.json") }

    static var arbeit: URL { bilder.appendingPathComponent(".arbeit", isDirectory: true) }

    static var messwerte: URL { appOrdner.appendingPathComponent("messwerte.json") }

    /// Im Prüfprogramm liegen die Einstellungen in einer eigenen Datei im Testordner, nie bei den echten.
    static let speicher: UserDefaults = {
        #if TESTLAUF
        guard let test = UserDefaults(suiteName: Testumgebung.ordner.appendingPathComponent("einstellungen").path) else {
            Testumgebung.abbrechen("Die Einstellungsdatei im Testordner liess sich nicht anlegen.")
        }
        return test
        #else
        return .standard
        #endif
    }()
}
