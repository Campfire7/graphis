import AppKit
import Foundation

/// Prüft gespeicherte Daten mit erfundenen Inhalten: Einstellungen, Warteschlangen, Bildangaben und Messwerte mit
/// unbekannten Modellnamen oder fehlenden Feldern. Nichts davon darf abstürzen oder echte Werte verdrängen.
/// Dazu das Übernehmen der Einstellungen eines Bildes.
@MainActor
enum DatenPruefung {
    private static func json(_ wert: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: wert)) ?? Data()
    }

    static func ausfuehren(_ bericht: Pruefbericht) async {
        let speicher = Pfade.speicher

        // Einstellungen je Modell, wie JSONEncoder sie ablegt, als Liste aus Schlüssel und Wert.
        let liste: [Any] = ["anderes-modell", ["schritte": 7, "textfuehrung": 2.0, "turbo": true],
                            "moss", ["schritte": 12, "textfuehrung": 3.5, "turbo": false],
                            "noch-ein-modell", "kein Wert", "ohne Partner"]
        let ausListe = ModellEinstellung.lesen(json(liste))
        let ausWoerterbuch = ModellEinstellung.lesen(json(["moss": ["schritte": 20, "textfuehrung": 2.5],
                                                           "anderes-modell": ["schritte": 1]]))
        let unlesbar = ModellEinstellung.lesen(Data("kein JSON".utf8)).isEmpty
            && ModellEinstellung.lesen(json(["moss": "kein Wert"])).isEmpty && ModellEinstellung.lesen(json([1, 2, 3])).isEmpty
        bericht.pruefen("Einstellungen mit unbekannten Modellen", ausListe == [.moss: ModellEinstellung(schritte: 12, textfuehrung: 3.5, turbo: false)]
                        && ausWoerterbuch == [.moss: ModellEinstellung(schritte: 20, textfuehrung: 2.5, turbo: false)] && unlesbar,
                        "Liste \(ausListe), Wörterbuch \(ausWoerterbuch), unlesbar leer \(unlesbar)")
        let eigene = ModellEinstellung(schritte: 9, textfuehrung: 1.5, turbo: true)
        let zurueck = (try? JSONEncoder().encode([ModellID.moss: eigene])).map(ModellEinstellung.lesen)
        bericht.pruefen("Gespeicherte Einstellungen kommen unverändert zurück", zurueck == [.moss: eigene], "\(zurueck ?? [:])")

        // Vorgaben aus einem Speicher mit fremden Modellnamen: MOSS bleibt eingeschaltet, sein Wert gilt.
        speicher.set(["anderes-modell", "noch-ein-modell"], forKey: "aktiv")
        speicher.set(2, forKey: "einstellungsstand")
        speicher.set(json(liste), forKey: "einstellungen")
        speicher.set("Standard", forKey: "stufe")
        let fremd = Vorgaben()
        let fremdOk = fremd.aktiv == [.moss] && fremd.modelle == [.moss]
            && fremd.einstellung(.moss) == ModellEinstellung(schritte: 12, textfuehrung: 3.5, turbo: false)
        speicher.set(Data("kein JSON".utf8), forKey: "einstellungen")
        speicher.set("unbekannte Stufe", forKey: "stufe")
        let kaputt = Vorgaben()
        let kaputtOk = kaputt.stufe == .standard && kaputt.einstellung(.moss) == ModellID.moss.vorgabe(.standard)
        bericht.pruefen("Vorgaben mit fremden und unlesbaren Einstellungen", fremdOk && kaputtOk,
                        "fremd \(fremd.aktiv.map(\.rawValue)), \(fremd.einstellung(.moss)), unlesbar \(kaputt.einstellung(.moss))")

        // Eine Warteschlange, die gar nicht lesbar ist, kommt beiseite und wird nie überschrieben.
        try? Data("kein JSON".utf8).write(to: Pfade.warteDatei)
        let unlesbarSchlange = Generator()
        let beiseite = ((try? FileManager.default.contentsOfDirectory(atPath: Pfade.bilder.path)) ?? [])
            .filter { $0.hasPrefix(".warteschlange-unlesbar-") }
        bericht.pruefen("Unlesbare Warteschlange kommt beiseite", unlesbarSchlange.warteschlange.isEmpty && !unlesbarSchlange.pausiert
                        && unlesbarSchlange.fehler == "Die gespeicherte Warteschlange liess sich nicht lesen. Sie liegt als Sicherung im Bildordner."
                        && beiseite.count == 1
                        && beiseite.first.flatMap { try? Data(contentsOf: Pfade.bilder.appendingPathComponent($0)) } == Data("kein JSON".utf8)
                        && !FileManager.default.fileExists(atPath: Pfade.warteDatei.path),
                        "\(unlesbarSchlange.fehler ?? "kein Fehler"), Sicherungen \(beiseite.count)")

        // Lauter Einträge, die Graphis nicht kennt: nichts wartet, alles liegt als Sicherung da.
        let gruppe = UUID()
        let nurFremdes: [Any] = [["id": gruppe.uuidString, "prompt": "Fremd", "laengeSeite": 768, "auftraege": [
            ["gruppe": gruppe.uuidString, "prompt": "Fremd", "modell": "anderes-modell", "schritte": 8, "breite": 768,
             "hoehe": 768, "seed": 1]] as [Any]]]
        try? json(nurFremdes).write(to: Pfade.warteDatei)
        let leer = Generator()
        let sicherungen = ((try? FileManager.default.contentsOfDirectory(atPath: Pfade.bilder.path)) ?? [])
            .filter { $0.hasPrefix(".warteschlange-nicht-lesbar-") }
        bericht.pruefen("Warteschlange nur mit fremden Einträgen", leer.warteschlange.isEmpty && !leer.pausiert
                        && (leer.fehler ?? "").hasPrefix("1 Eintrag der gespeicherten Warteschlange liess sich nicht lesen")
                        && sicherungen.count == 1 && !FileManager.default.fileExists(atPath: Pfade.warteDatei.path),
                        "\(leer.fehler ?? "kein Fehler"), Sicherungen \(sicherungen.count)")

        // Bildangaben: lesbare kommen in den Verlauf, fremde, falsch benannte und unvollständige nicht.
        func angaben(_ name: String, _ werte: [String: Any], bild: Bool = true) {
            if bild { Hilfe.testbild(name + ".png", 32, 32, .gray, in: Pfade.bilder) }
            try? json(werte).write(to: Pfade.bilder.appendingPathComponent(name + ".json"))
        }
        func werte(_ name: String, modell: String = "moss", datei: String? = nil) -> [String: Any] {
            ["datei": datei ?? name + ".png", "gruppe": UUID().uuidString, "prompt": "Verlauf", "negativ": "", "modell": modell,
             "seed": 5, "breite": 1024, "hoehe": 1024, "schritte": 8, "textfuehrung": 1.0, "sekunden": 30.0,
             "geschaetzt": 28.0, "referenzen": 0]
        }
        let neu = "2026-01-01_10-00-00_moss_1", schlicht = "2026-01-01_09-00-00_moss_2"
        var vollstaendig = werte(neu)
        vollstaendig["auftrag"] = UUID().uuidString
        vollstaendig["turbo"] = true
        vollstaendig["referenzDateien"] = ["vorlage.png"]
        angaben(neu, vollstaendig)
        var mitDatei = werte(schlicht)
        mitDatei["referenzDatei"] = "nur-eine.png"
        mitDatei["referenzen"] = 1
        angaben(schlicht, mitDatei)
        angaben("2026-01-01_08-00-00_anderes_3", werte("2026-01-01_08-00-00_anderes_3", modell: "anderes-modell"))
        angaben("2026-01-01_07-00-00_moss_4", werte("2026-01-01_07-00-00_moss_4", datei: "anderer-name.png"))
        var ohneSeed = werte("2026-01-01_06-00-00_moss_5")
        ohneSeed["seed"] = nil
        angaben("2026-01-01_06-00-00_moss_5", ohneSeed)
        angaben("2026-01-01_05-00-00_moss_6", werte("2026-01-01_05-00-00_moss_6"), bild: false)
        let verlauf = Generator()
        let gelesen = verlauf.ergebnisse.map(\.datei)
        let referenzen = verlauf.ergebnisse.map(\.referenzNamen)
        bericht.pruefen("Bildangaben mit fremden oder fehlenden Werten", gelesen == [neu + ".png", schlicht + ".png"]
                        && referenzen == [["vorlage.png"], ["nur-eine.png"]] && verlauf.ergebnisse.first?.turbo == true,
                        "gelesen \(gelesen)")

        // Absturz nach dem letzten Bild: Die Warteschlange enthält nur noch Erledigtes. Nichts wartet, die Datei
        // mit dem Prompt verschwindet.
        let erledigtGruppe = UUID()
        let nurErledigtes: [Any] = [["id": erledigtGruppe.uuidString, "prompt": "Erledigt", "laengeSeite": 768, "auftraege": [
            ["id": vollstaendig["auftrag"] as? String ?? "", "gruppe": erledigtGruppe.uuidString, "prompt": "Erledigt",
             "modell": "moss", "schritte": 8, "breite": 1024, "hoehe": 1024, "seed": 5]] as [Any]]]
        try? json(nurErledigtes).write(to: Pfade.warteDatei)
        let erledigt = Generator()
        bericht.pruefen("Warteschlange nur mit Erledigtem", erledigt.warteschlange.isEmpty && !erledigt.pausiert
                        && erledigt.fehler == nil && !FileManager.default.fileExists(atPath: Pfade.warteDatei.path),
                        "Stapel \(erledigt.warteschlange.count), Datei da \(FileManager.default.fileExists(atPath: Pfade.warteDatei.path))")

        // Messwerte mit fremden Schlüsseln stören die Schätzung nicht.
        try? json(["anderes.gross": ["schrittzeit": 30, "grundzeit": 20, "anzahl": 4],
                   "moss.turbo.gross": ["schrittzeit": 20, "grundzeit": 5, "anzahl": 3]]).write(to: Pfade.messwerte)
        let zeilen = Zeitschaetzer().uebersicht()
        bericht.pruefen("Messwerte mit fremden Schlüsseln", zeilen.count == 4 && zeilen.allSatisfy { $0.id.hasPrefix("moss.") }
                        && zeilen.first { $0.id == "moss.turbo.gross" }?.wert.contains("3 Mal gemessen") == true,
                        "\(zeilen.map(\.id))")

        await uebernahme(bericht)
    }

    /// Stellt nach einem Bild ein und prüft, ob derselbe Auftrag wieder entsteht.
    private static func uebernahme(_ bericht: Pruefbericht) async {
        let vorgaben = Vorgaben.gemeinsam
        for name in ["probe-eins", "probe-zwei"] {
            Hilfe.safetensors("\(name).safetensors", [
                ("diffusion_model.layers.0.proj.q.lora_A.weight", [4, 64], 512),
                ("diffusion_model.layers.0.proj.q.lora_B.weight", [64, 4], 512)], in: Pfade.module)
        }
        await vorgaben.moduleNeuLaden()
        vorgaben.stufeAnwenden(.standard)
        vorgaben.referenzenLeeren()
        vorgaben.aktiv = [.moss]
        vorgaben.prompt = "T"
        vorgaben.negativ = "N"
        vorgaben.format = .hoch
        vorgaben.laengeSeite = 1024
        vorgaben.festerStartwert = true
        vorgaben.startwert = 12345
        vorgaben.anzahl = 1
        vorgaben.modulAktiv = Set(vorgaben.module.prefix(2).map(\.datei))
        if let erstes = vorgaben.module.first { vorgaben.modulStaerke[erstes.datei] = 0.65 }
        guard let vorher = vorgaben.auftragsliste().first else { return }
        let ergebnis = Ergebnis(
            datei: "t.png", gruppe: vorher.gruppe, prompt: vorher.prompt, negativ: vorher.negativ, modell: vorher.modell,
            seed: vorher.seed, breite: vorher.breite, hoehe: vorher.hoehe, schritte: vorher.schritte,
            textfuehrung: vorher.textfuehrung, sekunden: 1, geschaetzt: 1, referenzen: 0,
            module: vorher.module.map(\.name), auftrag: UUID(), turbo: vorher.turbo, modulDaten: vorher.module,
            formatName: vorher.formatName)
        vorgaben.prompt = "anders"
        vorgaben.negativ = ""
        vorgaben.format = .quadrat
        vorgaben.laengeSeite = 768
        vorgaben.festerStartwert = false
        vorgaben.anzahl = 3
        vorgaben.modulAktiv = []
        vorgaben.modulStaerke = [:]
        vorgaben.stufeAnwenden(.beste)
        vorgaben.uebernehmen(ergebnis)
        let nachher = vorgaben.auftragsliste().first
        let gleich = nachher.map { n in vorher.prompt == n.prompt && vorher.negativ == n.negativ && vorher.seed == n.seed
            && vorher.breite == n.breite && vorher.hoehe == n.hoehe && vorher.schritte == n.schritte
            && vorher.textfuehrung == n.textfuehrung && vorher.turbo == n.turbo && Set(vorher.module) == Set(n.module) } ?? false
        bericht.pruefen("Übernahme stellt denselben Auftrag her", gleich && vorher.module.count == 3 && vorgaben.anzahl == 1
                        && vorgaben.format == .hoch && vorgaben.uebernahmeLuecken.isEmpty,
                        "Module \(nachher?.module.count ?? 0), Anzahl \(vorgaben.anzahl), Lücken \(vorgaben.uebernahmeLuecken)")

        func bild(_ seed: Int, schritte: Int = 9, fuehrung: Double = 1, turbo: Bool = true, negativ: String = "") -> Ergebnis {
            Ergebnis(datei: "s\(seed).png", gruppe: vorher.gruppe, prompt: "Z", negativ: negativ, modell: .moss, seed: seed,
                     breite: 832, hoehe: 1216, schritte: schritte, textfuehrung: fuehrung, sekunden: 1, geschaetzt: 1,
                     referenzen: 0, module: turbo ? ["Turbo"] : [], auftrag: UUID(), turbo: turbo)
        }
        vorgaben.uebernehmen([bild(500), bild(501)])
        let serie = vorgaben.auftragsliste()
        bericht.pruefen("Übernahme einer festen Serie", vorgaben.anzahl == 2 && vorgaben.startwert == 500
                        && serie.map(\.seed) == [500, 501] && serie.allSatisfy { $0.schritte == 9 && $0.textfuehrung == 1 && $0.turbo }
                        && vorgaben.uebernahmeLuecken.isEmpty, "Startwerte \(serie.map(\.seed)), Lücken \(vorgaben.uebernahmeLuecken)")
        vorgaben.uebernehmen([bild(700), bild(40)])
        bericht.pruefen("Freie Zufallszahlen werden gemeldet", vorgaben.anzahl == 2 && vorgaben.startwert == 700
                        && vorgaben.uebernahmeLuecken.count == 1, "\(vorgaben.uebernahmeLuecken)")

        // Mit Negativprompt wird Textführung 2 gerechnet, der Grundwert bleibt aber 1.
        vorgaben.uebernehmen(bild(9, schritte: 8, fuehrung: 2, negativ: "N"))
        let mitNegativ = vorgaben.auftragsliste().first?.textfuehrung
        vorgaben.negativ = ""
        let ohneNegativ = vorgaben.auftragsliste().first?.textfuehrung
        bericht.pruefen("Textführung nach Negativprompt", mitNegativ == 2 && ohneNegativ == 1,
                        "mit \(mitNegativ ?? 0), ohne \(ohneNegativ ?? 0)")

        // Fehlende Module und Angaben ohne Modulstärken werden genannt.
        var ohneStaerken = bild(10, turbo: false)
        ohneStaerken.module = ["Gibt es nicht"]
        vorgaben.uebernehmen(ohneStaerken)
        bericht.pruefen("Fehlende Module werden genannt", vorgaben.uebernahmeLuecken.contains("Diese Module fehlen jetzt: Gibt es nicht.")
                        && vorgaben.uebernahmeLuecken.contains("Die Modulstärken dieses Bildes sind nicht gespeichert, es gelten die aktuellen."),
                        "\(vorgaben.uebernahmeLuecken)")
    }
}
