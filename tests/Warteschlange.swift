import AppKit
import Foundation

/// Prüft die Warteschlange mit dem Scheinprogramm: Bereitschaft, Reihenfolge, Aufruf des Motors, Fehler, Abbruch
/// und eine gespeicherte Warteschlange nach einem Neustart, auch mit Einträgen, die Graphis nicht lesen kann.
@MainActor
enum WarteschlangePruefung {
    static func ausfuehren(_ bericht: Pruefbericht) async {
        let generator = Generator()
        let vorgaben = Vorgaben.gemeinsam
        await vorgaben.moduleNeuLaden()
        vorgaben.stufeAnwenden(.schnell)
        vorgaben.anzahl = 1
        vorgaben.festerStartwert = true
        vorgaben.startwert = 11
        vorgaben.negativ = ""
        vorgaben.referenzenLeeren()

        // Ohne eingerichtetes Modell ruft die App den Motor gar nicht erst auf.
        vorgaben.prompt = "Prüfbild ohne Modell"
        await generator.starten(vorgaben.auftragsliste(), laengeSeite: 768)
        await Hilfe.fertig(generator)
        bericht.pruefen("Ohne eingerichtetes Modell rechnet nichts", generator.pausiert && Hilfe.aufrufe().isEmpty
                        && (generator.fehler ?? "").contains("nicht vollständig eingerichtet")
                        && generator.warteschlange.first?.auftraege.count == 1, generator.fehler ?? "kein Fehler")
        generator.warteschlangeLeeren()

        let bereit = await Hilfe.einrichten()
        bericht.pruefen("Einrichtung vom Testserver", bereit, "\(Modellinstallation.gemeinsam.zustand)")
        guard bereit else { return }

        // A läuft, B und C warten, C wird entfernt.
        var stand = Hilfe.aufrufe().count
        // Eigene Startwerte: Der Name eines Bildes besteht aus Zeit auf die Sekunde, Modell und Startwert.
        func stapel(_ prompt: String, _ startwert: Int) -> [Auftrag] {
            vorgaben.prompt = prompt
            vorgaben.startwert = startwert
            return vorgaben.auftragsliste()
        }
        let a = stapel("Prüfbild A", 11), b = stapel("Prüfbild B", 12), c = stapel("Prüfbild C", 13)
        vorgaben.festerStartwert = false
        await generator.starten(a, laengeSeite: 768)
        let laeuftA = generator.laeuft && generator.sprungZu == a[0].gruppe
        await generator.starten(b, laengeSeite: 768)
        await generator.starten(c, laengeSeite: 768)
        let wartend = generator.warteschlange.map(\.prompt)
        let platzC = generator.platz(c[0].gruppe)
        generator.ausWarteschlangeEntfernen(c[0].gruppe)
        let ohneC = generator.warteschlange.map(\.prompt)
        var gesehen = [String]()
        let ende = Date().addingTimeInterval(30)
        while (generator.laeuft || !generator.warteschlange.isEmpty) && Date() < ende {
            if let aktiv = generator.laeufe.first(where: { $0.id == generator.aktiveGruppe })?.prompt,
               gesehen.last != aktiv { gesehen.append(aktiv) }
            try? await Task.sleep(for: .milliseconds(20))
        }
        bericht.pruefen("Reihenfolge A, B und C entfernt", laeuftA && wartend == ["Prüfbild B", "Prüfbild C"] && platzC == 2
                        && ohneC == ["Prüfbild B"] && gesehen == ["Prüfbild A", "Prüfbild B"]
                        && generator.ergebnisse.prefix(2).map(\.prompt) == ["Prüfbild B", "Prüfbild A"]
                        && generator.sprungZu == a[0].gruppe && generator.fehler == nil,
                        "wartend \(wartend), Platz C \(platzC ?? 0), ohne C \(ohneC), gesehen \(gesehen), Fehler \(generator.fehler ?? "keiner")")

        // Das Scheinprogramm wurde wirklich zweimal aufgerufen, und der Prompt kam über die Datei.
        var neue = Array(Hilfe.aufrufe().dropFirst(stand))
        bericht.pruefen("Scheinprogramm wirklich aufgerufen", neue.count == 2
                        && Hilfe.prompts().suffix(2) == ["Prüfbild A", "Prüfbild B"],
                        "\(neue.count) Aufrufe, Prompts \(Hilfe.prompts().suffix(2))")
        let zeile = neue.first ?? ""
        let turbo = Pfade.module.appendingPathComponent(Modul.turboDatei).path
        bericht.pruefen("Aufruf wie für den echten Motor", zeile.hasPrefix("-I -B ") && zeile.contains("/Motor/motor_start.py bild --model ")
                        && zeile.contains("\(Pfade.ordner(.moss).path) --base-model moss-image --prompt-file ")
                        && zeile.contains("--seed 11 --steps 8 --guidance 1.0 --width 768 --height 768 --output ")
                        && zeile.contains(" --no-exif --lora \(turbo) 0.7") && !zeile.contains("Prüfbild")
                        && !zeile.contains("--config-from-conf") && !zeile.contains("--image") && !zeile.contains("--low-ram"),
                        zeile)
        let gespeichert = generator.ergebnisse.prefix(2).allSatisfy { ergebnis in
            let bild = Pfade.bilder.appendingPathComponent(ergebnis.datei)
            let angaben = bild.deletingPathExtension().appendingPathExtension("json")
            let gelesen = (try? Data(contentsOf: angaben)).flatMap { try? JSONDecoder().decode(Ergebnis.self, from: $0) }
            return FileManager.default.fileExists(atPath: bild.path) && gelesen == ergebnis && ergebnis.turbo == true
                && ergebnis.textfuehrung == 1 && ergebnis.referenzen == 0 && ergebnis.modulDaten?.first?.name == "Turbo"
                && ergebnis.breite == 768 && ergebnis.hoehe == 768
        }
        bericht.pruefen("Bild und Angaben gespeichert", gespeichert && Set(generator.ergebnisse.prefix(2).map(\.datei)).count == 2,
                        "\(generator.ergebnisse.prefix(2).map(\.datei))")

        // Negativprompt: Textführung 2, der Text geht über eine Datei, nie über die Argumente.
        stand = Hilfe.aufrufe().count
        vorgaben.prompt = "Prüfbild mit Negativprompt"
        vorgaben.negativ = "Wort im Negativprompt"
        await generator.starten(vorgaben.auftragsliste(), laengeSeite: 768)
        await Hilfe.fertig(generator)
        neue = Array(Hilfe.aufrufe().dropFirst(stand))
        let mitNegativ = neue.first ?? ""
        bericht.pruefen("Negativprompt über Datei mit Textführung 2", neue.count == 1 && mitNegativ.contains("--steps 8 --guidance 2.0")
                        && mitNegativ.contains("--config-from-conf ") && !mitNegativ.contains("Wort im Negativprompt")
                        && generator.ergebnisse.first?.negativ == "Wort im Negativprompt"
                        && generator.ergebnisse.first?.textfuehrung == 2, mitNegativ)
        vorgaben.negativ = ""

        // Ein Fehler hält die Warteschlange an. Nochmals versuchen rechnet alles, Überspringen lässt das Bild aus.
        for ueberspringen in [false, true] {
            Hilfe.schein("einmal-fehlschlagen", an: true)
            vorgaben.prompt = ueberspringen ? "Prüfbild überspringen" : "Prüfbild nochmals"
            vorgaben.anzahl = 3
            let auftraege = vorgaben.auftragsliste()
            let bilderVorher = generator.ergebnisse.count
            stand = Hilfe.aufrufe().count
            await generator.starten(auftraege, laengeSeite: 768)
            await Hilfe.fertig(generator)
            let angehalten = generator.pausiert && generator.warteschlange.first?.auftraege.count == 3
                && generator.fehler?.hasPrefix("Das Bild konnte nicht erzeugt werden.") == true
                && generator.fehlerDetails?.contains("absichtlicher Fehler") == true
                && generator.fehlerLauf == auftraege[0].gruppe && generator.ergebnisse.count == bilderVorher
                && Hilfe.aufrufe().count == stand + 1
            let fehlerText = generator.fehler ?? "kein Fehler"
            if ueberspringen { generator.bildUeberspringen() } else { generator.weiterrechnen() }
            await Hilfe.fertig(generator)
            let erwartet = ueberspringen ? 2 : 3
            let weiter = !generator.pausiert && generator.warteschlange.isEmpty && generator.fehler == nil
                && generator.ergebnisse.count == bilderVorher + erwartet && Hilfe.aufrufe().count == stand + 1 + erwartet
            bericht.pruefen(ueberspringen ? "Fehler, dann Bild überspringen" : "Fehler hält an, Nochmals versuchen rechnet alles",
                            angehalten && weiter,
                            "angehalten \(angehalten) (\(fehlerText)), danach \(generator.ergebnisse.count - bilderVorher) Bilder, Fehler \(generator.fehler ?? "keiner")")
        }
        vorgaben.anzahl = 1

        // Abbrechen beendet das laufende Rechenprogramm, ohne ein Bild zu speichern.
        Hilfe.schein("langsam", an: true)
        vorgaben.prompt = "Prüfbild Abbruch"
        let bilderVorher = generator.ergebnisse.count
        stand = Hilfe.aufrufe().count
        await generator.starten(vorgaben.auftragsliste(), laengeSeite: 768)
        let gestartet = await Hilfe.warten(10) { Hilfe.aufrufe().count > stand }
        try? await Task.sleep(for: .milliseconds(300))
        generator.abbrechen()
        let beendet = await Hilfe.warten(10) { !generator.laeuft }
        Hilfe.schein("langsam", an: false)
        bericht.pruefen("Abbrechen", gestartet && beendet && generator.ergebnisse.count == bilderVorher
                        && generator.warteschlange.isEmpty && !generator.pausiert && generator.fehler == nil,
                        "gestartet \(gestartet), beendet \(beendet), Fehler \(generator.fehler ?? "keiner")")

        await gespeicherteWarteschlange(bericht)
    }

    /// Eine gespeicherte Warteschlange nach einem Neustart: lesbare Aufträge kommen zurück, angehalten.
    /// Was Graphis nicht lesen kann, fällt weg und bleibt als Sicherung liegen. Mehr als ein Referenzbild kommt nie zurück.
    private static func gespeicherteWarteschlange(_ bericht: Pruefbericht) async {
        let vorlage = Hilfe.testbild("gespeichert-1.png", 900, 600, .systemGreen, in: Pfade.referenzen)
        let zweite = Hilfe.testbild("gespeichert-2.png", 600, 900, .systemBlue, in: Pfade.referenzen)
        let dritte = Hilfe.testbild("gespeichert-3.png", 500, 500, .systemOrange, in: Pfade.referenzen)
        let gruppe = UUID(), fremd = UUID()
        let schlange: [Any] = [
            ["id": gruppe.uuidString, "prompt": "Gespeichert", "laengeSeite": 768, "auftraege": [
                ["id": UUID().uuidString, "gruppe": gruppe.uuidString, "prompt": "Gespeichert", "negativ": "", "modell": "moss",
                 "schritte": 9, "textfuehrung": 1.0, "breite": 768, "hoehe": 512, "seed": 3,
                 "referenzen": [vorlage, zweite, dritte].map(\.absoluteString), "turbo": false, "module": [] as [Any],
                 "referenzStaerke": 0.5, "formatName": "Quadrat"],
                // Ohne neuere Felder.
                ["gruppe": gruppe.uuidString, "prompt": "Gespeichert", "modell": "moss", "schritte": 9, "breite": 768,
                 "hoehe": 768, "seed": 4],
                // Ein Modell, das Graphis nicht kennt.
                ["id": UUID().uuidString, "gruppe": gruppe.uuidString, "prompt": "Gespeichert", "modell": "anderes-modell",
                 "schritte": 16, "breite": 1024, "hoehe": 704, "seed": 5],
                // Ohne Gruppe nicht lesbar.
                ["prompt": "Gespeichert", "modell": "moss", "schritte": 9, "breite": 768, "hoehe": 768, "seed": 6],
            ] as [Any]],
            ["id": fremd.uuidString, "prompt": "Nur Fremdes", "laengeSeite": 768, "auftraege": [
                ["gruppe": fremd.uuidString, "prompt": "Nur Fremdes", "modell": "noch-ein-modell", "schritte": 8,
                 "breite": 768, "hoehe": 768, "seed": 7],
            ] as [Any]],
            "kein Stapel",
        ]
        guard let daten = try? JSONSerialization.data(withJSONObject: schlange) else { return }
        try? daten.write(to: Pfade.warteDatei)
        let zweiter = Generator()
        let sicherungen = ((try? FileManager.default.contentsOfDirectory(atPath: Pfade.bilder.path)) ?? [])
            .filter { $0.hasPrefix(".warteschlange-nicht-lesbar-") }
        let sicherung = sicherungen.first.map { Pfade.bilder.appendingPathComponent($0) }
        let neuGeschrieben = (try? Data(contentsOf: Pfade.warteDatei))
            .flatMap { try? JSONDecoder().decode([Stapel].self, from: $0) }
        let auftraege = zweiter.warteschlange.first?.auftraege ?? []
        bericht.pruefen("Gespeicherte Warteschlange mit unlesbaren Einträgen", zweiter.pausiert && zweiter.warteschlange.count == 1
                        && auftraege.count == 2 && (zweiter.fehler ?? "").hasPrefix("4 Einträge der gespeicherten Warteschlange")
                        && sicherungen.count == 1 && sicherung.flatMap { try? Data(contentsOf: $0) } == daten
                        && neuGeschrieben?.count == 1 && neuGeschrieben?.first?.auftraege.count == 2,
                        "Stapel \(zweiter.warteschlange.count), Aufträge \(auftraege.count), Fehler \(zweiter.fehler ?? "keiner"), Sicherungen \(sicherungen.count)")

        let stand = Hilfe.aufrufe().count
        let referenzenGelesen = auftraege.first?.referenzen ?? []
        zweiter.weiterrechnen()
        await Hilfe.fertig(zweiter)
        let neue = Array(Hilfe.aufrufe().dropFirst(stand))
        let ergebnis = zweiter.ergebnisse.first { $0.gruppe == gruppe && $0.seed == 3 }
        if neue.count == 2 {
            bericht.pruefen("Wiederhergestellter Auftrag mit drei Referenzbildern nutzt eines", referenzenGelesen == [vorlage]
                            && neue[0].contains("motor_start.py referenz") && neue[0].contains(" --image \(vorlage.path) 0.5")
                            && !neue[0].contains(zweite.path) && !neue[0].contains(dritte.path)
                            && neue[0].components(separatedBy: " --image ").count == 2 && !neue[0].contains("--image-paths")
                            && neue[0].contains("--width 768 --height 512")
                            && ergebnis?.referenzen == 1 && ergebnis?.referenzDateien == [vorlage.lastPathComponent], neue[0])
            bericht.pruefen("Wiederhergestellter Auftrag ohne neuere Felder", neue[1].contains("motor_start.py bild")
                            && neue[1].contains("--seed 4 --steps 9 --guidance 1.0") && !neue[1].contains("--image")
                            && !neue[1].contains("--lora"), neue[1])
        } else {
            bericht.pruefen("Wiederhergestellte Aufträge gerechnet", false,
                            "\(neue.count) Aufrufe, Fehler \(zweiter.fehler ?? "keiner")")
        }
    }
}
