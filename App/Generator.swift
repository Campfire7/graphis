import AppKit
import SwiftUI

/// Arbeitet die Aufträge nacheinander ab. Nichts wird protokolliert, die CLI läuft immer offline.
@MainActor
final class Generator: ObservableObject {
    static let gemeinsam = Generator()

    @Published var laeuft = false
    @Published var statusText = ""
    @Published var fortschritt = 0.0
    @Published var restSekunden = 0.0
    @Published var fehler: String?
    /// Der Lauf, zu dem der Fehler gehört, und die rohe Ausgabe des Rechenprogramms zum Aufklappen.
    @Published var fehlerLauf: UUID?
    @Published var fehlerDetails: String?
    @Published var ergebnisse: [Ergebnis] = []
    @Published var letzteAbweichung: String?
    @Published var aktiveGruppe: UUID?
    @Published var warteschlange: [Stapel] = []
    /// Nur ein Start aus dem Leerlauf springt zur Ergebnisansicht, nachrückende Läufe nicht.
    @Published var sprungZu: UUID?
    /// Das Bild in der Grossansicht.
    @Published var grossBild: Ergebnis?
    @Published var restGesamt = 0.0
    /// Nach einem Neustart wartet die gespeicherte Warteschlange auf ein Weiterrechnen.
    @Published var pausiert = false
    private var aktiverPrompt = ""
    /// Rest des laufenden Stapels. Wird gespeichert, damit nach Absturz nichts verloren geht.
    private var offen: Stapel?
    private var wirdBeendet = false
    private var uhrLaeuft = false
    /// Hält die App auch im Hintergrund wach, sonst bremst macOS sie und die Warteschlange stockt.
    private var wachhalter: NSObjectProtocol?
    /// Der zuletzt angenommene Stapel mit Referenzbildern, solange sie noch kopiert werden.
    private var vorbereitung: Task<Void, Never>?
    /// Zählt das Leeren der Warteschlange. Ein Stapel, der beim Leeren noch vorbereitet wurde, reiht sich nicht mehr ein.
    private var leerungen = 0

    let schaetzer = Zeitschaetzer()
    private var prozess: Process?
    private var abgebrochen = false
    private let uhr = SuspendingClock()
    private var aktuellerStart = SuspendingClock().now
    private var ersterSchritt: SuspendingClock.Instant?
    private var schritt = 0
    private var schritte = 0
    private var aktuelleSchaetzung = 0.0
    private var spaetereSchaetzung = 0.0
    private var gesamtSchaetzung = 0.0
    private var erledigt = 0.0

    private static let schrittMuster = try! Regex(#"(\d+)/(\d+) \["#)
    private static let modulMuster = try! Regex(#"\((\d+)/(\d+) keys matched\)"#)

    init() {
        try? FileManager.default.createDirectory(at: Pfade.bilder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: Pfade.arbeit)
        ergebnisseLaden()
        warteschlangeLaden()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.beendenBeimSchliessen()
                try? FileManager.default.removeItem(at: Pfade.arbeit)
            }
        }
    }

    /// Wartende Läufe zuoberst, dann der aktive, dann der Verlauf.
    var laeufe: [Lauf] {
        var reihenfolge = warteschlange.reversed().map(\.id)
        var gruppen = [UUID: [Ergebnis]]()
        for id in reihenfolge { gruppen[id] = [] }
        if let aktiveGruppe {
            reihenfolge.append(aktiveGruppe)
            gruppen[aktiveGruppe] = []
        }
        for ergebnis in ergebnisse {
            if gruppen[ergebnis.gruppe] == nil { reihenfolge.append(ergebnis.gruppe) }
            gruppen[ergebnis.gruppe, default: []].append(ergebnis)
        }
        return reihenfolge.map { id in
            let eintraege = Array((gruppen[id] ?? []).reversed())
            let wartend = warteschlange.first { $0.id == id }?.prompt
            return Lauf(id: id, prompt: eintraege.first?.prompt ?? wartend ?? aktiverPrompt, ergebnisse: eintraege)
        }
    }

    func platz(_ id: UUID) -> Int? {
        warteschlange.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    func gesamtDauer(_ auftraege: [Auftrag]) -> Double {
        auftraege.map(schaetzer.schaetzung).reduce(0, +)
    }

    /// Läuft schon etwas, reiht sich der neue Stapel hinten ein. Referenzbilder werden vorher im Hintergrund kopiert,
    /// die Stapel kommen trotzdem in der Reihenfolge der Klicks an. Ohne Referenzbilder geht es sofort.
    func starten(_ auftraege: [Auftrag], laengeSeite: Int) async {
        guard !auftraege.isEmpty else { return }
        try? FileManager.default.createDirectory(at: Pfade.bilder, withIntermediateDirectories: true)
        guard FileManager.default.isWritableFile(atPath: Pfade.bilder.path) else {
            fehler = String(localized: "\(Fassung.name) is not allowed to write to the Downloads folder. Allow this in System Settings under Privacy & Security, Files and Folders.")
            return
        }
        guard vorbereitung != nil || auftraege.contains(where: { !$0.referenzen.isEmpty }) else {
            einreihen(auftraege, laengeSeite: laengeSeite)
            return
        }
        let davor = vorbereitung
        let stand = leerungen
        let aufgabe = Task {
            await davor?.value
            switch await Task.detached(priority: .userInitiated, operation: { Self.referenzenEinfrieren(auftraege) }).value {
            case .fertig(let bereit):
                guard leerungen == stand else {
                    // Verworfen: Die eben geschriebenen Kopien braucht niemand.
                    let neu = Set(bereit.flatMap(\.referenzen)).subtracting(auftraege.flatMap(\.referenzen))
                    for kopie in neu { try? FileManager.default.removeItem(at: kopie) }
                    return
                }
                einreihen(bereit, laengeSeite: laengeSeite)
            case .fehlgeschlagen(let nummer, let von):
                fehler = von == 1 ? String(localized: "The reference image could not be read. Is it still in the same place?")
                    : String(localized: "Reference image \(nummer) could not be read. Is it still in the same place?")
            }
        }
        vorbereitung = aufgabe
        await aufgabe.value
        if vorbereitung == aufgabe { vorbereitung = nil }
    }

    private func einreihen(_ auftraege: [Auftrag], laengeSeite: Int) {
        guard let erster = auftraege.first else { return }
        let stapel = Stapel(id: erster.gruppe, prompt: erster.prompt, auftraege: auftraege, laengeSeite: laengeSeite)
        if laeuft || pausiert {
            warteschlange.append(stapel)
            warteschlangeSichern()
        } else {
            fehlerLoeschen()
            letzteAbweichung = nil
            sprungZu = stapel.id
            stapelStarten(stapel)
        }
    }

    private enum Einfrieren: Sendable {
        case fertig([Auftrag])
        case fehlgeschlagen(nummer: Int, von: Int)
    }

    /// Jedes Referenzbild wird einmal als PNG in den Bildordner kopiert, die Kopie gilt für alle Bilder des Stapels.
    /// So stört es die Warteschlange nicht, wenn das Original verschoben wird, und die Einstellungen lassen sich
    /// später übernehmen. Die Reihenfolge bleibt, denn der Prompt nennt die Bilder mit Nummer. Scheitert eine Kopie,
    /// gehen die schon geschriebenen wieder weg. Liest und schreibt Dateien, gehört also in den Hintergrund.
    nonisolated private static func referenzenEinfrieren(_ auftraege: [Auftrag]) -> Einfrieren {
        var quellen = [URL]()
        for quelle in auftraege.flatMap(\.referenzen) where !quellen.contains(quelle) { quellen.append(quelle) }
        guard !quellen.isEmpty else { return .fertig(auftraege) }
        try? FileManager.default.createDirectory(at: Pfade.referenzen, withIntermediateDirectories: true)
        var kopien = [URL: URL]()
        for (stelle, quelle) in quellen.enumerated() {
            let kopie = Pfade.referenzen.appendingPathComponent(UUID().uuidString + ".png")
            guard Vorschau.referenzSchreiben(von: quelle, nach: kopie, kante: 2048) else {
                for neu in kopien.values + [kopie] { try? FileManager.default.removeItem(at: neu) }
                return .fehlgeschlagen(nummer: stelle + 1, von: quellen.count)
            }
            kopien[quelle] = kopie
        }
        return .fertig(auftraege.map { auftrag in
            var neu = auftrag
            neu.referenzen = auftrag.referenzen.map { kopien[$0] ?? $0 }
            return neu
        })
    }

    func weiterrechnen() {
        guard !laeuft, !warteschlange.isEmpty else { return }
        pausiert = false
        fehlerLoeschen()
        let naechster = warteschlange.removeFirst()
        sprungZu = naechster.id
        stapelStarten(naechster)
    }

    /// Überspringt das Bild, an dem die Warteschlange hängt. Der Rest läuft weiter.
    func bildUeberspringen() {
        guard !laeuft, !warteschlange.isEmpty else { return }
        warteschlange[0].auftraege.removeFirst()
        if warteschlange[0].auftraege.isEmpty { warteschlange.removeFirst() }
        fehlerLoeschen()
        if warteschlange.isEmpty {
            pausiert = false
            warteschlangeSichern()
        } else {
            weiterrechnen()
        }
    }

    private func fehlerLoeschen() {
        fehler = nil
        fehlerLauf = nil
        fehlerDetails = nil
    }

    private func stapelStarten(_ stapel: Stapel) {
        if wachhalter == nil {
            wachhalter = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled], reason: String(localized: "Creating images"))
        }
        laeuft = true
        offen = stapel
        warteschlangeSichern()
        aktiveGruppe = stapel.id
        aktiverPrompt = stapel.prompt
        abgebrochen = false
        erledigt = 0
        gesamtSchaetzung = gesamtDauer(stapel.auftraege)
        restSekunden = gesamtSchaetzung
        Task {
            let fehlgeschlagen = await abarbeiten(stapel.auftraege)
            if wirdBeendet { return }
            if fehlgeschlagen, let rest = offen, !rest.auftraege.isEmpty {
                // Der Rest geht nicht verloren: Er wartet vorne, bis weitergerechnet wird.
                warteschlange.insert(rest, at: 0)
                pausiert = true
            }
            offen = nil
            if !warteschlange.isEmpty && !pausiert {
                stapelStarten(warteschlange.removeFirst())
            } else {
                warteschlangeSichern()
                if let aktiv = wachhalter {
                    ProcessInfo.processInfo.endActivity(aktiv)
                    wachhalter = nil
                }
            }
        }
        if !uhrLaeuft { Task { await uhrLaufenLassen() } }
    }

    func ausWarteschlangeEntfernen(_ id: UUID) {
        warteschlange.removeAll { $0.id == id }
        if warteschlange.isEmpty { pausiert = false }
        if fehlerLauf == id { fehlerLoeschen() }
        warteschlangeSichern()
    }

    func warteschlangeLeeren() {
        leerungen += 1
        warteschlange.removeAll()
        pausiert = false
        fehlerLoeschen()
        warteschlangeSichern()
    }

    /// Der Rest des laufenden Stapels steht vorne, damit er nach einem Neustart zuerst weiterläuft.
    private func warteschlangeSichern() {
        let alles = (offen.map { [$0] } ?? []) + warteschlange
        do {
            if alles.isEmpty {
                if FileManager.default.fileExists(atPath: Pfade.warteDatei.path) {
                    try FileManager.default.removeItem(at: Pfade.warteDatei)
                }
            } else {
                try JSONEncoder().encode(alles).write(to: Pfade.warteDatei, options: .atomic)
            }
        } catch {
            fehler = String(localized: "The queue could not be saved, is the disk full? It would be lost in a crash.")
        }
    }

    /// Sicherungen tragen Datum und Uhrzeit im Namen, so ersetzt keine eine frühere.
    private func sicherung(_ art: String) -> URL {
        let stempel = DateFormatter()
        stempel.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return Pfade.bilder.appendingPathComponent(".warteschlange-\(art)-\(stempel.string(from: Date())).json")
    }

    private func warteschlangeLaden() {
        guard let daten = try? Data(contentsOf: Pfade.warteDatei) else { return }
        guard let gespeichert = try? JSONDecoder().decode([Nachsichtig<GespeicherterStapel>].self, from: daten) else {
            // Eine unlesbare Datei wird nie überschrieben, sondern beiseitegelegt.
            try? FileManager.default.moveItem(at: Pfade.warteDatei, to: sicherung("unlesbar"))
            fehler = String(localized: "The saved queue could not be read. It is in the image folder as a backup.")
            return
        }
        guard !gespeichert.isEmpty else { return }
        // Was sich nicht lesen lässt, etwa ein Auftrag für ein Modell, das Graphis nicht kennt, würde nur scheitern.
        // Es fällt weg. Die ganze Datei kommt vorher als Sicherung beiseite. Verschieben braucht keinen freien Platz.
        // Geht auch das nicht, bleibt sie unverändert liegen und Graphis lädt nichts daraus.
        let ausgelassen = gespeichert.map { $0.wert?.ausgelassen ?? 1 }.reduce(0, +)
        if ausgelassen > 0 {
            do {
                try FileManager.default.moveItem(at: Pfade.warteDatei, to: sicherung("nicht-lesbar"))
            } catch {
                fehler = String(localized: "Entries of the saved queue cannot be read, and the file could not be set aside as a backup. It stays unchanged.")
                return
            }
            fehler = ausgelassen == 1
                ? String(localized: "1 entry of the saved queue could not be read and was removed. The whole queue is in the image folder as a backup.")
                : String(localized: "\(ausgelassen) entries of the saved queue could not be read and were removed. The whole queue is in the image folder as a backup.")
        }
        // Stürzt die App direkt nach dem Speichern eines Bildes ab, zählt es trotzdem als erledigt.
        let fertig = Set(ergebnisse.compactMap(\.auftrag))
        let offeneStapel = gespeichert.compactMap { eintrag -> Stapel? in
            guard var rest = eintrag.wert?.stapel else { return nil }
            rest.auftraege.removeAll { fertig.contains($0.id) }
            return rest.auftraege.isEmpty ? nil : rest
        }
        // Auch wenn nichts mehr offen ist: Speichern löscht dann die alte Datei samt Prompt.
        warteschlange = offeneStapel
        pausiert = !offeneStapel.isEmpty
        warteschlangeSichern()
    }

    func abbrechen() {
        abgebrochen = true
        guard let laufend = prozess else { return }
        laufend.terminate()
        // Reagiert die CLI nicht, wird sie nach wenigen Sekunden hart beendet.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if laufend.isRunning { kill(laufend.processIdentifier, SIGKILL) }
        }
    }

    /// Die Warteschlange bleibt gespeichert, das angefangene Bild wird beim nächsten Mal neu gerechnet.
    private func beendenBeimSchliessen() {
        abgebrochen = true
        wirdBeendet = true
        guard let laufend = prozess else { return }
        laufend.terminate()
        let frist = Date().addingTimeInterval(3)
        while laufend.isRunning && Date() < frist { usleep(50_000) }
        if laufend.isRunning { kill(laufend.processIdentifier, SIGKILL) }
    }

    /// Schlafpausen des Mac zählen nicht mit, sonst springen Anzeige und Lernwerte.
    private func sekunden(seit start: SuspendingClock.Instant) -> Double {
        let teile = start.duration(to: uhr.now).components
        return Double(teile.seconds) + Double(teile.attoseconds) / 1e18
    }

    func zeitBisher() {
        let verstrichen = sekunden(seit: aktuellerStart)
        var rest = aktuelleSchaetzung - verstrichen
        if let ersterSchritt, schritt >= 2 {
            let jeSchritt = sekunden(seit: ersterSchritt) / Double(schritt - 1)
            rest = jeSchritt * Double(schritte - schritt) + 6
        }
        restSekunden = max(rest, 1) + spaetereSchaetzung
        restGesamt = restSekunden + warteschlange.map { gesamtDauer($0.auftraege) }.reduce(0, +)
        if gesamtSchaetzung > 0 {
            fortschritt = min((erledigt + verstrichen) / max(erledigt + verstrichen + restSekunden, 1), 0.99)
        }
    }

    private func uhrLaufenLassen() async {
        uhrLaeuft = true
        defer { uhrLaeuft = false }
        while laeuft || !warteschlange.isEmpty {
            if laeuft { zeitBisher() }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Liefert true, wenn ein Bild fehlgeschlagen ist.
    private func abarbeiten(_ auftraege: [Auftrag]) async -> Bool {
        let ordner = Pfade.arbeit.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: ordner)
            laeuft = false
            aktiveGruppe = nil
            statusText = ""
            fortschritt = 0
        }
        for (index, auftrag) in auftraege.enumerated() {
            if abgebrochen { return false }
            aktuelleSchaetzung = schaetzer.schaetzung(auftrag)
            spaetereSchaetzung = auftraege[(index + 1)...].map(schaetzer.schaetzung).reduce(0, +)
            let stand = auftraege.count > 1 ? String(localized: "Image \(index + 1) of \(auftraege.count): ") : ""
            do {
                try await rechnen(auftrag, ordner: ordner, stand: stand)
                if abgebrochen { return false }
                offen?.auftraege.removeFirst()
                warteschlangeSichern()
            } catch {
                if abgebrochen { return false }
                fehler = error.localizedDescription
                fehlerLauf = auftrag.gruppe
                fehlerDetails = (error as NSError).userInfo[NSLocalizedFailureReasonErrorKey] as? String
                return true
            }
        }
        return false
    }

    private static func fehlschlag(_ text: String, details: String) -> NSError {
        NSError(domain: Fassung.name, code: 1, userInfo: [
            NSLocalizedDescriptionKey: text, NSLocalizedFailureReasonErrorKey: details,
        ])
    }

    /// Übersetzt die häufigen Fälle, die rohe Ausgabe bleibt unter Technische Angaben.
    private static func verstaendlich(_ ausgabe: String, mitModulen: Bool) -> String {
        // Das Zusatzprogramm für MOSS mit Referenzbild meldet sich mit eigenen Sätzen auf Deutsch. Der bekannte Fall
        // kommt in der Sprache des Mac, alle anderen heissen, dass Motor und App nicht zusammenpassen.
        if let meldung = ausgabe.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("Rechenmotor: ") }) {
            if meldung.dropFirst("Rechenmotor: ".count) == "Das Referenzbild fehlt." {
                return String(localized: "The reference image is missing.")
            }
            return String(localized: "The engine in the app bundle is missing or damaged. Download the app again.")
        }
        let text = ausgabe.lowercased()
        if text.contains("no lora layers were applied") {
            return String(localized: "An active module does not fit MOSS. Skip this image, turn the module off and start the image again.")
        }
        if text.contains("no space left") {
            return String(localized: "There is not enough space on the Mac. Free up some space, then click Try Again.")
        }
        if text.contains("out of memory") || text.contains("insufficient memory") || text.contains("failed to allocate") {
            return String(localized: "There was not enough memory. Close large apps or choose fewer pixels, then click Try Again.")
        }
        let grund = String(localized: "The image could not be created. Click Try Again.")
        return mitModulen ? grund + " " + String(localized: "If that does not help, turn off the modules.") : grund
    }

    private func rechnen(_ auftrag: Auftrag, ordner: URL, stand: String) async throws {
        let stempel = DateFormatter()
        stempel.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "\(stempel.string(from: Date()))_\(auftrag.modell.rawValue)_\(auftrag.seed).png"
        let ausgabe = Pfade.bilder.appendingPathComponent(name)
        let promptDatei = ordner.appendingPathComponent("prompt.txt")
        let text = auftrag.ausloeser.map { "\($0), \(auftrag.prompt)" } ?? auftrag.prompt
        try text.write(to: promptDatei, atomically: true, encoding: .utf8)

        // Prompts bleiben aus der Prozessliste und aus dem Bild: Sie gehen über Dateien, und --no-exif hält das PNG frei.
        let modell = auftrag.modell
        // Dateiangaben frisch lesen: Wurde eine Modelldatei seit der Prüfung verändert, rechnet die App nicht damit.
        Modellinstallation.gemeinsam.auffrischen()
        guard Modellinstallation.gemeinsam.bereit else {
            throw Self.fehlschlag(String(localized: "MOSS-Image is not fully set up or has changed. Check or download it under New Image, then click Continue."), details: "")
        }
        let module = auftrag.module
        let negativ = auftrag.negativ
        let textfuehrung = auftrag.textfuehrung
        var argumente = [
            "--model", Pfade.ordner(modell).path, "--base-model", modell.basisModell,
            "--prompt-file", promptDatei.path,
            "--seed", String(auftrag.seed),
            "--steps", String(auftrag.schritte),
            "--guidance", String(textfuehrung),
            "--width", String(auftrag.breite),
            "--height", String(auftrag.hoehe),
            "--output", ausgabe.path,
            "--no-exif",
        ]
        // Bei Textführung 1 beachtet das Modell den Negativprompt nicht, dann geht er gar nicht erst mit.
        if !negativ.isEmpty && textfuehrung > 1 {
            let konfiguration = ordner.appendingPathComponent("negativ.json")
            try JSONSerialization.data(withJSONObject: ["negative_prompt": negativ]).write(to: konfiguration)
            argumente += ["--config-from-conf", konfiguration.path]
        }
        // MOSS baut auf genau einem Referenzbild auf, auch wenn eine gespeicherte Angabe mehr nennt.
        let bilder = Array(auftrag.referenzen.prefix(Vorgaben.hoechstensReferenzen))
        if bilder.contains(where: { !FileManager.default.fileExists(atPath: $0.path) }) {
            throw Self.fehlschlag(String(localized: "The reference image is no longer in the image folder."), details: "")
        }
        if let vorlage = bilder.first {
            argumente += ["--image", vorlage.path, String(auftrag.referenzStaerke ?? 0.625)]
        }
        for modul in module { argumente += ["--lora", modul.pfad, String(modul.staerke)] }

        let neuerProzess = Process()
        let aufruf = Pfade.aufruf(mitReferenz: !bilder.isEmpty)
        neuerProzess.executableURL = URL(fileURLWithPath: aufruf.programm)
        neuerProzess.arguments = aufruf.vorweg + argumente
        // Offline erzwingen: mflux darf nach der Einrichtung nichts mehr aus dem Netz holen.
        var umgebung = ProcessInfo.processInfo.environment
        umgebung["HF_HUB_OFFLINE"] = "1"
        umgebung["TRANSFORMERS_OFFLINE"] = "1"
        umgebung["HF_HUB_DISABLE_TELEMETRY"] = "1"
        // Das App-Paket ist schreibgeschützt. Was mflux und Hugging Face zwischenspeichern, liegt im eigenen Ordner.
        umgebung["HF_HOME"] = Pfade.zwischenspeicher.appendingPathComponent("huggingface").path
        umgebung["MFLUX_CACHE_DIR"] = Pfade.zwischenspeicher.appendingPathComponent("mflux").path
        umgebung["TRANSFORMERS_VERBOSITY"] = "error"
        neuerProzess.environment = umgebung
        let rohr = Pipe()
        neuerProzess.standardOutput = rohr
        neuerProzess.standardError = rohr
        let ende = AsyncStream<Int32> { fortsetzung in
            neuerProzess.terminationHandler = { fertig in
                fortsetzung.yield(fertig.terminationStatus)
                fortsetzung.finish()
            }
        }

        let startzeit = uhr.now
        aktuellerStart = startzeit
        ersterSchritt = nil
        schritt = 0
        schritte = auftrag.rechenSchritte
        statusText = stand + String(localized: "Loading \(auftrag.modell.name)")
        do {
            try neuerProzess.run()
        } catch {
            throw Self.fehlschlag(String(localized: "The engine in the app bundle is missing or damaged. Download the app again."),
                                  details: error.localizedDescription)
        }
        prozess = neuerProzess

        var letzteZeilen = [String]()
        var schrittzeitGesamt: Double?
        var teilweise = 0
        var lesefehler: Error?
        var puffer = [UInt8]()
        // Der Fortschrittsbalken schreibt seine Zeile immer neu. Darum zählt schon die schliessende Klammer,
        // sonst hinkt die Anzeige einen Schritt nach und die gemessene Schrittzeit stimmt nicht.
        func zeileAuswerten(abgeschlossen: Bool) {
            let zeile = String(decoding: puffer, as: UTF8.self)
            if let treffer = zeile.firstMatch(of: Self.schrittMuster),
               let aktuell = treffer[1].substring.flatMap({ Int($0) }),
               let gesamt = treffer[2].substring.flatMap({ Int($0) }), gesamt == auftrag.rechenSchritte {
                if aktuell > schritt {
                    schritt = aktuell
                    schritte = gesamt
                    if ersterSchritt == nil { ersterSchritt = uhr.now }
                    if let beginn = ersterSchritt, aktuell > 1 {
                        schrittzeitGesamt = sekunden(seit: beginn) / Double(aktuell - 1)
                    }
                    statusText = stand + String(localized: "\(auftrag.modell.name), step \(aktuell) of \(gesamt)")
                }
            } else if abgeschlossen {
                if let treffer = zeile.firstMatch(of: Self.modulMuster),
                   let passend = treffer[1].substring.flatMap({ Int($0) }),
                   let alle = treffer[2].substring.flatMap({ Int($0) }) {
                    if passend < alle { teilweise += 1 }
                } else if !zeile.trimmingCharacters(in: .whitespaces).isEmpty {
                    letzteZeilen = Array((letzteZeilen + [zeile]).suffix(4))
                }
            }
        }
        do {
            for try await byte in rohr.fileHandleForReading.bytes {
                if byte == 10 || byte == 13 {
                    zeileAuswerten(abgeschlossen: true)
                    puffer.removeAll(keepingCapacity: true)
                } else {
                    puffer.append(byte)
                    if byte == 93 { zeileAuswerten(abgeschlossen: false) }
                }
            }
            zeileAuswerten(abgeschlossen: true)
        } catch {
            // Ohne Ausgabe lässt sich nichts mehr verfolgen, also die CLI sauber stoppen.
            lesefehler = error
            neuerProzess.terminate()
        }
        var code: Int32 = -1
        for await status in ende { code = status }
        prozess = nil
        if abgebrochen {
            try? FileManager.default.removeItem(at: ausgabe)
            return
        }
        guard lesefehler == nil, code == 0, FileManager.default.fileExists(atPath: ausgabe.path) else {
            try? FileManager.default.removeItem(at: ausgabe)
            if let lesefehler { throw lesefehler }
            let meldung = letzteZeilen.joined(separator: " ")
            throw Self.fehlschlag(Self.verstaendlich(meldung, mitModulen: !module.isEmpty),
                                  details: String(meldung.suffix(400)))
        }
        // Der Hinweis wird mit dem Bild gespeichert, in der Sprache, die der Mac beim Rechnen hatte.
        let hinweis = teilweise == 0 ? nil : teilweise == 1
            ? String(localized: "1 module only partly worked, the file format does not quite fit.")
            : String(localized: "\(teilweise) modules only partly worked, the file format does not quite fit.")

        let dauer = sekunden(seit: startzeit)
        let geschaetzt = aktuelleSchaetzung
        schaetzer.lernen(auftrag, gesamt: dauer, schrittzeit: schrittzeitGesamt, geschaetzt: geschaetzt)
        erledigt += dauer
        letzteAbweichung = String(localized: "\(auftrag.modell.name): estimated \(dauerText(geschaetzt)), took \(dauerText(dauer))")
        // Gespeichert wird, was wirklich gerechnet wurde, damit Angaben und Übernahme stimmen.
        let ergebnis = Ergebnis(
            datei: name, gruppe: auftrag.gruppe, prompt: auftrag.prompt, negativ: negativ,
            modell: auftrag.modell, seed: auftrag.seed, breite: auftrag.breite, hoehe: auftrag.hoehe,
            schritte: auftrag.schritte, textfuehrung: textfuehrung, sekunden: dauer,
            geschaetzt: geschaetzt, referenzen: bilder.count, module: module.map(\.name),
            auftrag: auftrag.id, hinweis: hinweis, turbo: auftrag.turbo, modulDaten: module,
            referenzStaerke: bilder.isEmpty ? nil : auftrag.referenzStaerke, referenzDatei: bilder.first?.lastPathComponent,
            formatName: auftrag.formatName, ausloeser: auftrag.ausloeser,
            referenzDateien: bilder.isEmpty ? nil : bilder.map(\.lastPathComponent))
        do {
            let daten = try JSONEncoder().encode(ergebnis)
            try daten.write(to: ausgabe.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
        } catch {
            fehler = String(localized: "The image is saved, but its details are not. It will be missing from the history after a restart.")
        }
        ergebnisse.insert(ergebnis, at: 0)
    }

    func ergebnisseLaden() {
        let dateien = (try? FileManager.default.contentsOfDirectory(
            at: Pfade.bilder, includingPropertiesForKeys: nil)) ?? []
        ergebnisse = dateien.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(300)
            .compactMap(ergebnisLesen)
            .filter { FileManager.default.fileExists(atPath: Pfade.bilder.appendingPathComponent($0.datei).path) }
    }

    /// Angaben, die sich nicht lesen lassen, etwa zu einem Modell, das Graphis nicht kennt, übergeht die App.
    private func ergebnisLesen(_ url: URL) -> Ergebnis? {
        guard let daten = try? Data(contentsOf: url),
              let ergebnis = try? JSONDecoder().decode(Ergebnis.self, from: daten) else { return nil }
        // Nur das Bild mit gleichem Namen zählt, damit die App nie Dateien ausserhalb anfasst.
        return ergebnis.datei == url.deletingPathExtension().lastPathComponent + ".png" ? ergebnis : nil
    }

    func inPapierkorb(_ lauf: Lauf) {
        lauf.ergebnisse.forEach(inPapierkorb)
    }

    /// Die Kopien der Referenzbilder bleiben in .referenzen. Andere Bilder, die Warteschlange oder ein übernommener
    /// Entwurf können sie noch brauchen, und sicher aufräumen lässt sich erst mit einem Blick auf alle Bilder.
    func inPapierkorb(_ ergebnis: Ergebnis) {
        let bild = Pfade.bilder.appendingPathComponent(ergebnis.datei)
        NSWorkspace.shared.recycle([bild, bild.deletingPathExtension().appendingPathExtension("json")])
        ergebnisse.removeAll { $0.datei == ergebnis.datei }
    }
}
