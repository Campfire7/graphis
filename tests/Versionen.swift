import Foundation

/// Prüft die Suche nach neuen Versionen gegen den lokalen Testserver statt GitHub: Vergleich der Versionen, keine
/// Anfrage ohne Erlaubnis oder innerhalb eines Tages, Anfrage wenn fällig, Hinweis nur bei einer neueren Version,
/// unbrauchbare Antworten und fremde Seiten werden übergangen, die Anfrage verrät nichts über den Mac.
@MainActor
enum VersionenPruefung {
    private static var nummer = 0

    /// Jeder Fall bekommt eigene Einstellungen im Testordner.
    private static func speicher() -> UserDefaults {
        nummer += 1
        let pfad = Testumgebung.ordner.appendingPathComponent("versionen-\(nummer)").path
        guard let speicher = UserDefaults(suiteName: pfad) else {
            Testumgebung.abbrechen("Die Einstellungsdatei \(pfad) liess sich nicht anlegen.")
        }
        return speicher
    }

    private static func adresse(_ fall: String, umleiten: Bool = false) -> URL {
        let basis = Versionspruefung.standardAdresse.deletingLastPathComponent().deletingLastPathComponent()
        return basis.appendingPathComponent(umleiten ? "versionen-umleitung" : "versionen").appendingPathComponent(fall)
    }

    private static func anfragen() -> [String] { Hilfe.serverLog().filter { $0.contains(" /versionen") } }

    private typealias Schluessel = Versionspruefung.Schluessel
    private static let tag: TimeInterval = 24 * 60 * 60
    private static let seite = URL(string: "https://github.com/Campfire7/graphis/releases/tag/v1.1")!

    /// Eine Prüfung mit eigenen Einstellungen. Liefert die Prüfung, ihren Speicher und die Zahl neuer Anfragen.
    private static func lauf(_ fall: String, aktuell: String = "1.0", erlaubt: Bool? = true, zuletzt: Date? = nil,
                             jetzt: Date = Date(), umleiten: Bool = false, vorher fund: Bool = false)
        async -> (pruefung: Versionspruefung, speicher: UserDefaults, anfragen: Int) {
        let speicher = speicher()
        if let erlaubt { speicher.set(erlaubt, forKey: Schluessel.erlaubt) }
        if let zuletzt { speicher.set(zuletzt.timeIntervalSince1970, forKey: Schluessel.geprueftAm) }
        if fund {
            speicher.set("1.1", forKey: Schluessel.version)
            speicher.set(seite.absoluteString, forKey: Schluessel.seite)
        }
        let stand = anfragen().count
        let pruefung = Versionspruefung(speicher: speicher, adresse: adresse(fall, umleiten: umleiten),
                                        aktuelleVersion: aktuell, jetzt: { jetzt })
        await pruefung.pruefenFallsFaellig()?.value
        return (pruefung, speicher, anfragen().count - stand)
    }

    static func ausfuehren(_ bericht: Pruefbericht) async {
        vergleichen(bericht)
        seitenPruefen(bericht)
        await anfragenPruefen(bericht)
        await antwortenPruefen(bericht)
        await speichernPruefen(bericht)
    }

    private static func vergleichen(_ bericht: Pruefbericht) {
        let neuer = [("1.0.1", "1.0"), ("1.10", "1.9"), ("v1.1", "1.0"), ("V2", "1.9.9"), ("2.0", "v1.10"), ("1.0.0.1", "1.0")]
        let nichtNeuer = [("1.0", "1.0"), ("1.0.0", "1.0"), ("v1.0", "1.0.0"), ("1.9", "1.10"), ("0.9", "1.0"), ("1.0", "1.0.1")]
        let unsinn = ["", "v", "latest", "1..2", "1.2a", "1.2-beta", "-1", " 1.1", "1.1 ", "1.0.", ".1", "1.2.3.4.5",
                      "vv1.1", "1234567890.1", "1,1", "１.１", "+1.1"]
        let falschNeuer = neuer.filter { !Versionspruefung.istNeuer($0.0, als: $0.1) }
        bericht.pruefen("Neuere Versionen erkannt, auch 1.10 nach 1.9 und mit v davor", falschNeuer.isEmpty, falschNeuer.isEmpty ? "" : "\(falschNeuer)")
        let falschGleich = nichtNeuer.filter { Versionspruefung.istNeuer($0.0, als: $0.1) }
        bericht.pruefen("Gleiche und ältere Versionen gelten nicht als neuer", falschGleich.isEmpty, falschGleich.isEmpty ? "" : "\(falschGleich)")
        let angenommen = unsinn.filter {
            Versionspruefung.zahlen($0) != nil || Versionspruefung.istNeuer($0, als: "1.0") || Versionspruefung.istNeuer("9.9", als: $0)
        }
        bericht.pruefen("Unsinn ist keine Version", angenommen.isEmpty, angenommen.isEmpty ? "" : "\(angenommen)")
        bericht.pruefen("Zahlen einer Version", Versionspruefung.zahlen("v1.10.2") == [1, 10, 2] && Versionspruefung.zahlen("3") == [3])
    }

    private static func seitenPruefen(_ bericht: Pruefbericht) {
        let gut = ["https://github.com/Campfire7/graphis/releases/tag/v1.1", "https://github.com/campfire7/Graphis/releases",
                   "https://GitHub.com/Campfire7/graphis", "https://github.com/Campfire7/graphis#donate"]
        let schlecht = ["http://github.com/Campfire7/graphis/releases", "https://github.com.evil.example/Campfire7/graphis",
                        "https://evil.example/Campfire7/graphis", "https://github.com/Campfire7/anderes",
                        "https://github.com/Campfire7", "https://github.com/Campfire7/graphisx/releases",
                        "https://github.com/Campfire7/graphis/../../evil/graphis",
                        "https://github.com/Campfire7/graphis/%2e%2e/%2e%2e/evil", "https://github.com/Campfire7/graphis%2F..%2F..%2Fevil",
                        "https://name@github.com/Campfire7/graphis", "https://github.com:8443/Campfire7/graphis",
                        "file:///Campfire7/graphis", "javascript:alert(1)//github.com/Campfire7/graphis"]
        let abgelehnt = gut.filter { !(URL(string: $0).map(Versionspruefung.projektseite) ?? false) }
        bericht.pruefen("Seiten im Projekt auf GitHub gelten", abgelehnt.isEmpty, abgelehnt.isEmpty ? "" : "\(abgelehnt)")
        let angenommen = schlecht.filter { URL(string: $0).map(Versionspruefung.projektseite) ?? false }
        bericht.pruefen("Fremde, unsichere und hinausführende Seiten gelten nicht", angenommen.isEmpty, angenommen.isEmpty ? "" : "\(angenommen)")
        bericht.pruefen("Feste Adressen", Fassung.neusteVersion.absoluteString == "https://api.github.com/repos/Campfire7/graphis/releases/latest"
                        && Fassung.unterstuetzen.absoluteString == "https://github.com/Campfire7/graphis#donate"
                        && Versionspruefung.standardAdresse.host == "127.0.0.1",
                        "\(Fassung.neusteVersion), \(Fassung.unterstuetzen), im Prüfprogramm \(Versionspruefung.standardAdresse)")
    }

    private static func anfragenPruefen(_ bericht: Pruefbericht) async {
        let jetzt = Date()
        let gefragt = await lauf("neuer.json", erlaubt: nil)
        bericht.pruefen("Ohne Antwort auf die Frage keine Anfrage", gefragt.anfragen == 0 && gefragt.pruefung.frageOffen
                        && gefragt.pruefung.neu == nil, "\(gefragt.anfragen) Anfragen")
        let aus = await lauf("neuer.json", erlaubt: false)
        bericht.pruefen("Ausgeschaltet keine Anfrage", aus.anfragen == 0 && !aus.pruefung.frageOffen && aus.pruefung.neu == nil,
                        "\(aus.anfragen) Anfragen")
        let frisch = await lauf("neuer.json", zuletzt: jetzt.addingTimeInterval(-tag + 60), jetzt: jetzt)
        bericht.pruefen("Innerhalb eines Tages keine Anfrage", frisch.anfragen == 0 && frisch.pruefung.neu == nil,
                        "\(frisch.anfragen) Anfragen")
        let faellig = await lauf("neuer.json", zuletzt: jetzt.addingTimeInterval(-tag - 60), jetzt: jetzt)
        bericht.pruefen("Nach einem Tag fällig: eine Anfrage und ein Hinweis", faellig.anfragen == 1
                        && faellig.pruefung.neu == Versionspruefung.Fund(version: "1.1", seite: seite)
                        && abs(faellig.speicher.double(forKey: Schluessel.geprueftAm) - jetzt.timeIntervalSince1970) < 1,
                        "\(faellig.anfragen) Anfragen, \(String(describing: faellig.pruefung.neu))")
        let nochmals = faellig.pruefung.pruefenFallsFaellig()
        await nochmals?.value
        bericht.pruefen("Gleich danach nicht nochmals", nochmals == nil)
        let erste = await lauf("neuer.json")
        bericht.pruefen("Erster Versuch ohne früheren ist fällig", erste.anfragen == 1 && erste.pruefung.neu != nil,
                        "\(erste.anfragen) Anfragen")
        let uhr = await lauf("neuer.json", zuletzt: jetzt.addingTimeInterval(3600), jetzt: jetzt)
        bericht.pruefen("Zurückgestellte Uhr hält die Suche nicht auf", uhr.anfragen == 1, "\(uhr.anfragen) Anfragen")

        // Der Versuch zählt auch, wenn er scheitert: kein zweiter Versuch am selben Tag.
        let fehlt = await lauf("gibt-es-nicht.json")
        let danach = Versionspruefung(speicher: fehlt.speicher, adresse: adresse("neuer.json"), aktuelleVersion: "1.0")
        bericht.pruefen("Ein gescheiterter Versuch zählt", fehlt.anfragen == 1 && fehlt.pruefung.neu == nil && !danach.faellig,
                        "\(fehlt.anfragen) Anfragen")

        // Einschalten in den Einstellungen fragt gleich nach, Ausschalten blendet den Hinweis nur aus.
        let schalter = await lauf("neuer.json", erlaubt: nil)
        let stand = anfragen().count
        await schalter.pruefung.erlauben(true)?.value
        let an = schalter.pruefung.neu != nil && anfragen().count == stand + 1
            && schalter.speicher.object(forKey: Schluessel.erlaubt) as? Bool == true
        schalter.pruefung.erlauben(false)
        let wiederAus = schalter.pruefung.neu == nil && schalter.speicher.string(forKey: Schluessel.version) == "1.1"
            && schalter.speicher.object(forKey: Schluessel.erlaubt) as? Bool == false
        let neustartAus = Versionspruefung(speicher: schalter.speicher, adresse: adresse("neuer.json"), aktuelleVersion: "1.0")
        bericht.pruefen("Einschalten fragt nach, Ausschalten blendet den Hinweis aus", an && wiederAus && neustartAus.neu == nil,
                        "an \(an), aus \(wiederAus), nach Neustart \(String(describing: neustartAus.neu))")
        // Wieder an, am selben Tag: Der Hinweis ist sofort zurück, ohne neue Anfrage.
        let vorher = anfragen().count
        await schalter.pruefung.erlauben(true)?.value
        bericht.pruefen("Wieder einschalten zeigt den Hinweis sofort", schalter.pruefung.neu?.version == "1.1"
                        && anfragen().count == vorher, "\(String(describing: schalter.pruefung.neu)), \(anfragen().count - vorher) Anfragen")

        // Die Anfrage nennt nur eine feste Kennung und Sprache, ohne Cookies.
        let zeile = anfragen().last ?? ""
        bericht.pruefen("Anfrage verrät nichts über den Mac", zeile.hasPrefix("GET /versionen/neuer.json ")
                        && zeile.contains(" ua='Graphis' ") && zeile.contains(" lang='en' ") && zeile.hasSuffix(" cookie='-'"), zeile)
    }

    private static func antwortenPruefen(_ bericht: Pruefbericht) async {
        var falsch = [String]()
        for (fall, aktuell) in [("gleich.json", "1.0"), ("aelter.json", "1.0"), ("neuer.json", "1.1"), ("neuer.json", "1.2")] {
            let ergebnis = await lauf(fall, aktuell: aktuell)
            if ergebnis.anfragen != 1 || ergebnis.pruefung.neu != nil { falsch.append("\(fall) bei \(aktuell)") }
        }
        let neuer = await lauf("neuer.json", aktuell: "1.0.9")
        bericht.pruefen("Hinweis nur bei einer neueren Version", falsch.isEmpty && neuer.pruefung.neu?.version == "1.1",
                        "falsch \(falsch), bei 1.0.9 \(String(describing: neuer.pruefung.neu))")

        // Eine gültige Antwort ohne neuere Version nimmt einen alten Hinweis weg.
        let ueberholt = await lauf("gleich.json", aktuell: "1.0", zuletzt: Date().addingTimeInterval(-2 * tag), vorher: true)
        bericht.pruefen("Gültige Antwort ohne Neues nimmt den alten Hinweis weg", ueberholt.pruefung.neu == nil
                        && ueberholt.speicher.string(forKey: Schluessel.version) == nil)

        // Unbrauchbare Antworten ändern nichts: kein neuer Hinweis, ein alter bleibt.
        var angenommen = [String]()
        for fall in ["kaputt.json", "keinobjekt.json", "muell.json", "ohne-seite.json", "vorab.json", "entwurf.json",
                     "gross.json", "gibt-es-nicht.json"] {
            let ohne = await lauf(fall)
            let mit = await lauf(fall, zuletzt: Date().addingTimeInterval(-2 * tag), vorher: true)
            if ohne.anfragen != 1 || ohne.pruefung.neu != nil || mit.pruefung.neu?.version != "1.1" { angenommen.append(fall) }
        }
        bericht.pruefen("Unlesbare Antworten, Entwürfe und Vorabversionen übergangen", angenommen.isEmpty, angenommen.isEmpty ? "" : "\(angenommen)")

        var fremd = [String]()
        for fall in ["fremd.json", "fremdes-projekt.json", "unsicher.json", "ausbruch.json", "anmeldung.json"] {
            let ergebnis = await lauf(fall)
            if ergebnis.anfragen != 1 || ergebnis.pruefung.neu != nil { fremd.append(fall) }
        }
        bericht.pruefen("Fremde Seiten in der Antwort abgelehnt", fremd.isEmpty, fremd.isEmpty ? "" : "\(fremd)")

        // Eine Weiterleitung zu einem anderen Server folgt die App nicht, hier zu localhost statt 127.0.0.1.
        let stand = anfragen().count
        let umgeleitet = await lauf("neuer.json", umleiten: true)
        let ziele = anfragen().dropFirst(stand)
        bericht.pruefen("Weiterleitung zu einem anderen Server nicht befolgt", umgeleitet.pruefung.neu == nil
                        && ziele.count == 1 && ziele.allSatisfy { $0.contains("/versionen-umleitung/") }, "\(Array(ziele))")
    }

    private static func speichernPruefen(_ bericht: Pruefbericht) async {
        // Ein Fund bleibt nach einem Neustart sichtbar, ohne neue Anfrage, und verschwindet nach dem Update.
        let jetzt = Date()
        let fund = await lauf("neuer.json", zuletzt: jetzt.addingTimeInterval(-2 * tag), jetzt: jetzt)
        let stand = anfragen().count
        let neustart = Versionspruefung(speicher: fund.speicher, adresse: adresse("neuer.json"), aktuelleVersion: "1.0",
                                        jetzt: { jetzt.addingTimeInterval(3600) })
        await neustart.pruefenFallsFaellig()?.value
        let sichtbar = neustart.neu == Versionspruefung.Fund(version: "1.1", seite: seite) && anfragen().count == stand
        let aktualisiert = Versionspruefung(speicher: fund.speicher, adresse: adresse("neuer.json"), aktuelleVersion: "1.1",
                                            jetzt: { jetzt.addingTimeInterval(3600) })
        let weg = aktualisiert.neu == nil && fund.speicher.string(forKey: Schluessel.version) == nil
        bericht.pruefen("Hinweis bleibt nach Neustart und geht nach dem Update", sichtbar && weg, "sichtbar \(sichtbar), weg \(weg)")

        // Eine von Hand veränderte Seite in den Einstellungen gilt nicht.
        let speicher = speicher()
        speicher.set(true, forKey: Schluessel.erlaubt)
        speicher.set(jetzt.timeIntervalSince1970, forKey: Schluessel.geprueftAm)
        speicher.set("2.0", forKey: Schluessel.version)
        speicher.set("https://evil.example/Campfire7/graphis", forKey: Schluessel.seite)
        let verfaelscht = Versionspruefung(speicher: speicher, adresse: adresse("neuer.json"), aktuelleVersion: "1.0")
        bericht.pruefen("Veränderte Seite in den Einstellungen gilt nicht", verfaelscht.neu == nil)
    }
}
