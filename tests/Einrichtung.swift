import Foundation

/// Prüft das Laden der Modelle mit kleinen Dateien vom lokalen Testserver: erster Start, volle Platte,
/// unbekannter Platz, Anhalten und Fortsetzen (206), Neustart, beschädigte Dateien, Server ohne Range (200),
/// 416, falscher Bereich, Umleitung, falscher Hash, zu grosse Datei und Platzmangel unterwegs.
@MainActor
enum EinrichtungPruefung {
    static func ausfuehren(_ bericht: Pruefbericht) async {
        let test = Testumgebung.ordner
        let basis = Modellmanifest.aktuell
        guard basis.kennung != Modellmanifest.moss.kennung, Testumgebung.innerhalb(Pfade.modelle, test),
              Testumgebung.innerhalb(Pfade.module, test),
              let gross = basis.dateien.filter({ $0.ziel == .modell }).max(by: { $0.bytes < $1.bytes }) else {
            bericht.pruefen("Testmanifest und Testordner", false, "Manifest fehlt oder ein Ziel liegt ausserhalb")
            return
        }
        let dateien = FileManager.default
        func log() -> [String] { Hilfe.serverLog() }
        func seit(_ stand: Int) -> [String] { Array(log().dropFirst(stand)) }
        func art(_ name: String, nur pfad: String? = nil, sha256: String? = nil) -> Modellmanifest {
            Modellmanifest(kennung: basis.kennung, dateien: basis.dateien.map { datei in
                guard pfad == nil || datei.pfad == pfad else { return datei }
                let adresse = URL(string: datei.adresse.absoluteString.replacingOccurrences(of: "/ok/", with: "/\(name)/"))!
                return Manifestdatei(ziel: datei.ziel, pfad: datei.pfad, bytes: datei.bytes,
                                     sha256: sha256 ?? datei.sha256, adresse: adresse)
            })
        }
        func fertig(_ einrichtung: Modellinstallation) async {
            await Hilfe.warten(30) { !einrichtung.beschaeftigt }
        }
        let ladeTeil = Pfade.modelle.appendingPathComponent(".einrichtung/modell/\(gross.pfad).part")
        let aktivGross = Pfade.ordner(.moss).appendingPathComponent(gross.pfad)
        let turbo = basis.dateien.first { $0.ziel == .modul }.map { Pfade.module.appendingPathComponent($0.pfad) }
        func groesse(_ url: URL) -> Int64 { (try? dateien.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? -1 }
        func leeren() {
            try? dateien.removeItem(at: Pfade.modelle)
            if let turbo { try? dateien.removeItem(at: turbo) }
        }
        /// Lädt die grösste Datei langsam an und hält mitten darin an.
        func anladen() async -> Int64 {
            let einrichtung = Modellinstallation(manifest: art("langsam", nur: gross.pfad))
            einrichtung.freierPlatz = { _ in 1 << 40 }
            einrichtung.laden()
            await Hilfe.warten(10) { groesse(ladeTeil) >= 200_000 }
            einrichtung.anhalten()
            await fertig(einrichtung)
            return groesse(ladeTeil)
        }
        func teilAnlegen(_ daten: Data) {
            try? dateien.createDirectory(at: ladeTeil.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? daten.write(to: ladeTeil)
        }
        func alleAmZiel() -> Bool {
            basis.dateien.allSatisfy { datei in
                let ort = datei.ziel == .modell ? Pfade.ordner(.moss).appendingPathComponent(datei.pfad)
                    : Pfade.module.appendingPathComponent(datei.pfad)
                return groesse(ort) == datei.bytes
            } && !dateien.fileExists(atPath: Pfade.modelle.appendingPathComponent(".einrichtung").path)
        }
        func zeilen(_ liste: [String], _ teil: String) -> [String] { liste.filter { $0.contains(teil) } }
        let name = gross.pfad

        // 1 bis 3: Erster Start, dann volle Platte und unbekannter Platz: kein Byte aus dem Netz.
        leeren()
        var einrichtung = Modellinstallation(manifest: basis)
        bericht.pruefen("Erster Start", einrichtung.zustand == .fehlt(vorhanden: 0) && !einrichtung.bereit, "\(einrichtung.zustand)")
        var stand = log().count
        einrichtung.freierPlatz = { _ in 1_000_000 }
        einrichtung.laden()
        await fertig(einrichtung)
        if case .fehler(let text, false) = einrichtung.zustand {
            bericht.pruefen("Volle Platte vor dem Laden", text.contains("fehlen noch") && seit(stand).isEmpty, text)
        } else {
            bericht.pruefen("Volle Platte vor dem Laden", false, "\(einrichtung.zustand)")
        }
        einrichtung.freierPlatz = { _ in nil }
        einrichtung.laden()
        await fertig(einrichtung)
        bericht.pruefen("Unbekannter Platz verlangt Bestätigung", einrichtung.zustand.platzUnbekannt && seit(stand).isEmpty,
                        "\(einrichtung.zustand)")

        // 4 und 5: Anhalten mitten in der grössten Datei, Neustart, Fortsetzen mit Range und 206.
        let teilBytes = await anladen()
        einrichtung = Modellinstallation(manifest: basis)
        let nachNeustart = einrichtung.zustand
        stand = log().count
        einrichtung.laden(trotzUnbekanntemPlatz: true)
        await fertig(einrichtung)
        let fortgesetzt = zeilen(seit(stand), name)
        bericht.pruefen("Anhalten, Neustart und Fortsetzen mit 206", teilBytes > 0 && teilBytes < gross.bytes
                        && nachNeustart.vorhanden >= teilBytes && einrichtung.bereit && alleAmZiel()
                        && fortgesetzt.count == 1 && fortgesetzt[0].contains("bytes=\(teilBytes)-") && fortgesetzt[0].hasSuffix(" 206"),
                        "Teil \(teilBytes) von \(gross.bytes), nach Neustart \(nachNeustart), danach \(einrichtung.zustand), Anfragen \(fortgesetzt)")
        let schonGeladen = seit(stand).filter { !$0.contains(name) }
        bericht.pruefen("Fertige Dateien nicht nochmals geladen", schonGeladen.allSatisfy { zeile in
            !basis.dateien.prefix { $0.pfad != name }.contains { zeile.contains("/\($0.pfad) ") } }, "\(schonGeladen.count) weitere Anfragen")

        // 6: Ein Neustart erkennt die fertige Einrichtung ohne Hashen und ohne Netz.
        stand = log().count
        let uhr = ContinuousClock.now
        einrichtung = Modellinstallation(manifest: basis)
        let dauer = ContinuousClock.now - uhr
        bericht.pruefen("Neustart erkennt Bereitschaft", einrichtung.bereit && seit(stand).isEmpty && dauer < .seconds(1), "\(dauer)")
        let vorrat = (try? Data(contentsOf: aktivGross)) ?? Data()

        // 7: Inhalt geändert: Die Prüfung findet die Datei, die Reparatur lädt nur sie neu.
        var kaputt = vorrat
        kaputt[kaputt.count / 2] ^= 0xFF
        try? kaputt.write(to: aktivGross)
        einrichtung = Modellinstallation(manifest: basis)
        let vorPruefung = einrichtung.zustand
        einrichtung.pruefen()
        await fertig(einrichtung)
        let befund = einrichtung.zustand
        stand = log().count
        einrichtung.laden()
        await fertig(einrichtung)
        let repariert = seit(stand)
        bericht.pruefen("Beschädigte Datei finden und reparieren", vorPruefung == .ungeprueft && befund == .beschaedigt(1)
                        && einrichtung.bereit && alleAmZiel() && repariert.count == 1 && repariert[0].contains(name)
                        && repariert[0].hasSuffix(" 200") && (try? Data(contentsOf: aktivGross)) == vorrat,
                        "vor der Prüfung \(vorPruefung), Befund \(befund), Anfragen \(repariert)")

        // 8: Gleiche Grösse und Zeit: Der schnelle Start merkt es nicht, die erzwungene Prüfung schon.
        if let griff = try? FileHandle(forUpdating: aktivGross),
           let zeit = try? dateien.attributesOfItem(atPath: aktivGross.path)[.modificationDate] as? Date {
            try? griff.seek(toOffset: 10)
            try? griff.write(contentsOf: Data([vorrat[10] ^ 0xFF]))
            try? griff.close()
            try? dateien.setAttributes([.modificationDate: zeit], ofItemAtPath: aktivGross.path)
        }
        einrichtung = Modellinstallation(manifest: basis)
        let still = einrichtung.zustand
        einrichtung.pruefen(erzwingen: true)
        await fertig(einrichtung)
        let erzwungen = einrichtung.zustand
        einrichtung.laden()
        await fertig(einrichtung)
        bericht.pruefen("Stille Beschädigung mit erzwungener Prüfung", still == .bereit && erzwungen == .beschaedigt(1)
                        && einrichtung.bereit && (try? Data(contentsOf: aktivGross)) == vorrat,
                        "schneller Start \(still), erzwungen \(erzwungen)")

        // 9: Server ohne Range: Antwort 200, die App beginnt die Datei neu statt anzuhängen.
        leeren()
        var teil = await anladen()
        stand = log().count
        einrichtung = Modellinstallation(manifest: art("ohne-range", nur: name))
        einrichtung.laden(trotzUnbekanntemPlatz: true)
        await fertig(einrichtung)
        var anfragen = zeilen(seit(stand), name)
        bericht.pruefen("Server ignoriert Range (200)", teil > 0 && einrichtung.bereit && alleAmZiel() && anfragen.count == 1
                        && anfragen[0].contains("bytes=\(teil)-") && anfragen[0].hasSuffix(" 200")
                        && (try? Data(contentsOf: aktivGross)) == vorrat, "\(anfragen)")

        // 10: Vollständige Teildatei, etwa nach einem Absturz vor dem Prüfen: 416 heisst fertig.
        leeren()
        teilAnlegen(vorrat)
        stand = log().count
        einrichtung = Modellinstallation(manifest: basis)
        let mitVollemTeil = einrichtung.zustand
        einrichtung.laden(trotzUnbekanntemPlatz: true)
        await fertig(einrichtung)
        anfragen = zeilen(seit(stand), name)
        bericht.pruefen("Volle Teildatei mit 416", mitVollemTeil.vorhanden == gross.bytes && einrichtung.bereit && alleAmZiel()
                        && anfragen.count == 1 && anfragen[0].contains("bytes=\(gross.bytes)-") && anfragen[0].hasSuffix(" 416"),
                        "\(anfragen)")

        // 11 bis 13: 416 für einen echten Teilstand, falscher Bereich und Umleitung: jedes Mal sauber weiter.
        for (modus, erwartet) in [("416", [" 416", " 200"]), ("falscher-bereich", [" 206", " 200"]), ("umleitung", [" 302", " 206"])] {
            leeren()
            teilAnlegen(vorrat.prefix(vorrat.count / 2))
            stand = log().count
            einrichtung = Modellinstallation(manifest: art(modus, nur: name))
            einrichtung.laden(trotzUnbekanntemPlatz: true)
            await fertig(einrichtung)
            anfragen = zeilen(seit(stand), name)
            let folge = anfragen.map { zeile in erwartet.first { zeile.hasSuffix($0) } ?? zeile }
            bericht.pruefen("Teilstand mit \(modus)", einrichtung.bereit && alleAmZiel() && folge == erwartet
                            && (try? Data(contentsOf: aktivGross)) == vorrat, "\(anfragen)")
        }

        // 14: Falscher Hash: nichts wird aktiviert, die übrigen geladenen Dateien bleiben für den nächsten Versuch.
        leeren()
        einrichtung = Modellinstallation(manifest: art("ok", nur: name, sha256: String(repeating: "0", count: 64)))
        einrichtung.laden(trotzUnbekanntemPlatz: true)
        await fertig(einrichtung)
        let falsch = einrichtung.zustand
        einrichtung = Modellinstallation(manifest: basis)
        let danach = einrichtung.zustand
        stand = log().count
        einrichtung.laden(trotzUnbekanntemPlatz: true)
        await fertig(einrichtung)
        anfragen = seit(stand)
        bericht.pruefen("Falscher Hash wird verworfen", falsch.fehlerText.contains("stimmt nicht") && danach.vorhanden > 0
                        && einrichtung.bereit && alleAmZiel()
                        && anfragen.count == 1 + basis.dateien.drop { $0.pfad != name }.dropFirst().count,
                        "\(falsch), danach \(danach), \(anfragen.count) Anfragen")

        // 15: Zu grosse Antwort bricht ab.
        leeren()
        einrichtung = Modellinstallation(manifest: art("zu-gross", nur: name))
        einrichtung.laden(trotzUnbekanntemPlatz: true)
        await fertig(einrichtung)
        bericht.pruefen("Zu grosse Datei", einrichtung.zustand.fehlerText.contains("grösser")
                        && !dateien.fileExists(atPath: Pfade.ordner(.moss).path), "\(einrichtung.zustand)")

        // 16: Platz geht unterwegs aus: anhalten mit Meldung, später an derselben Stelle weiter.
        leeren()
        final class Zaehler: @unchecked Sendable {
            private let schloss = NSLock()
            private var wert = 0
            func weiter() -> Int { schloss.lock(); defer { schloss.unlock() }; wert += 1; return wert }
        }
        let zaehler = Zaehler()
        einrichtung = Modellinstallation(manifest: art("langsam", nur: name))
        einrichtung.pruefAbstand = 64 * 1024
        einrichtung.freierPlatz = { _ in zaehler.weiter() <= 1 ? 1 << 40 : 1_000 }
        einrichtung.laden()
        await fertig(einrichtung)
        let knapp = einrichtung.zustand
        teil = groesse(ladeTeil)
        einrichtung = Modellinstallation(manifest: basis)
        einrichtung.freierPlatz = { _ in 1 << 40 }
        einrichtung.laden()
        await fertig(einrichtung)
        bericht.pruefen("Platz geht unterwegs aus", knapp.fehlerText.contains("Platz") && einrichtung.bereit && alleAmZiel(),
                        "\(knapp), Teil danach \(teil)")

        // 17: Ohne Prüfvermerk liegen alle Dateien vollständig da: Die Reparatur verlangt dafür keinen Platz und lädt nichts.
        try? dateien.removeItem(at: Pfade.modelle.appendingPathComponent(".einrichtung-geprueft.json"))
        einrichtung = Modellinstallation(manifest: basis)
        let ohneVermerk = einrichtung.zustand
        stand = log().count
        einrichtung.freierPlatz = { _ in Modellinstallation.reserve + 1_000 }
        einrichtung.laden()
        await fertig(einrichtung)
        bericht.pruefen("Reparatur ohne Prüfvermerk braucht keinen Platz", ohneVermerk == .ungeprueft && einrichtung.bereit
                        && alleAmZiel() && seit(stand).isEmpty,
                        "vorher \(ohneVermerk), danach \(einrichtung.zustand), \(seit(stand).count) Anfragen")

        // 18: Unterwegs gilt dieselbe Reserve wie beim Start, nicht nur ein kleiner Rest.
        leeren()
        let zaehler2 = Zaehler()
        einrichtung = Modellinstallation(manifest: art("langsam", nur: name))
        einrichtung.pruefAbstand = 64 * 1024
        einrichtung.freierPlatz = { _ in zaehler2.weiter() <= 1 ? 1 << 40 : Modellinstallation.reserve + 1_000 }
        einrichtung.laden()
        await fertig(einrichtung)
        let unterReserve = einrichtung.zustand
        einrichtung = Modellinstallation(manifest: basis)
        einrichtung.freierPlatz = { _ in 1 << 40 }
        einrichtung.laden()
        await fertig(einrichtung)
        bericht.pruefen("Reserve gilt auch unterwegs", unterReserve.fehlerText.contains("Platz") && einrichtung.bereit && alleAmZiel(),
                        "\(unterReserve)")

        // 19: Eine Modelldatei ändert sich nach der Prüfung: Auffrischen nimmt die Bereitschaft zurück, ohne zu hashen.
        let geaendert = Pfade.ordner(.moss).appendingPathComponent(name)
        try? dateien.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: geaendert.path)
        einrichtung.auffrischen()
        let nachAenderung = einrichtung.zustand
        einrichtung.pruefen()
        await fertig(einrichtung)
        bericht.pruefen("Veränderte Datei nimmt Bereitschaft zurück", nachAenderung == .ungeprueft && einrichtung.bereit,
                        "nach Änderung \(nachAenderung), nach Prüfung \(einrichtung.zustand)")
    }

    /// Erster Teil der Prüfung eines echten Neustarts: lädt die grösste Datei langsam an und bleibt dann stehen,
    /// bis testlauf.sh den Prozess hart beendet. Die Zeile «lädt» in neustart.txt sagt, dass es so weit ist.
    static func neustartBeginnen() async {
        let basis = Modellmanifest.aktuell
        guard let gross = basis.dateien.filter({ $0.ziel == .modell }).max(by: { $0.bytes < $1.bytes }) else { return }
        let langsam = Modellmanifest(kennung: basis.kennung, dateien: basis.dateien.map { d in
            d.pfad != gross.pfad ? d : Manifestdatei(ziel: d.ziel, pfad: d.pfad, bytes: d.bytes, sha256: d.sha256, adresse:
                URL(string: d.adresse.absoluteString.replacingOccurrences(of: "/ok/", with: "/langsam/"))!)
        })
        let einrichtung = Modellinstallation(manifest: langsam)
        einrichtung.freierPlatz = { _ in 1 << 40 }
        einrichtung.laden()
        let teil = Pfade.modelle.appendingPathComponent(".einrichtung/modell/\(gross.pfad).part")
        await Hilfe.warten(20) {
            ((try? FileManager.default.attributesOfItem(atPath: teil.path)[.size] as? NSNumber)?.int64Value ?? 0) >= 200_000
        }
        try? "lädt\n".write(to: Testumgebung.ordner.appendingPathComponent("neustart.txt"), atomically: true, encoding: .utf8)
        // Bleibt mitten im Laden stehen, bis der Prozess beendet wird.
        while true { try? await Task.sleep(for: .seconds(1)) }
    }

    /// Zweiter Teil: dieselbe Einrichtung nach dem harten Ende. Sie setzt mit Range an der Stelle des Abbruchs fort.
    static func neustartFortsetzen(_ bericht: Pruefbericht) async {
        let basis = Modellmanifest.aktuell
        guard let gross = basis.dateien.filter({ $0.ziel == .modell }).max(by: { $0.bytes < $1.bytes }) else { return }
        let begonnen = FileManager.default.fileExists(atPath: Testumgebung.ordner.appendingPathComponent("neustart.txt").path)
        let einrichtung = Modellinstallation.gemeinsam
        let vorher = einrichtung.zustand
        let stand = Hilfe.serverLog().count
        einrichtung.freierPlatz = { _ in 1 << 40 }
        einrichtung.laden()
        await Hilfe.warten(30) { !einrichtung.beschaeftigt }
        let anfragen = Array(Hilfe.serverLog().dropFirst(stand)).filter { $0.contains(gross.pfad) }
        bericht.pruefen("Nach hartem Ende ist der Teilstand da", begonnen && vorher.vorhanden > 0, "\(vorher)")
        bericht.pruefen("Fortsetzen mit Range und 206 nach Neustart", einrichtung.bereit && anfragen.count == 1
                        && anfragen[0].contains("range=bytes=") && !anfragen[0].contains("range=bytes=0-")
                        && anfragen[0].hasSuffix(" 206"), "danach \(einrichtung.zustand), Anfragen \(anfragen)")
    }
}
