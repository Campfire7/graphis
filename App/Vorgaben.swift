import Foundation

/// Hält den aktuellen Entwurf. Einstellungen bleiben erhalten, Prompts nie.
@MainActor
final class Vorgaben: ObservableObject {
    static let gemeinsam = Vorgaben()

    private let speicher = Pfade.speicher

    @Published var prompt = ""
    @Published var negativ = ""
    /// Das Referenzbild gehört zum Entwurf und wird wie der Prompt nie gespeichert. Die Liste hält nie mehr als
    /// hoechstensReferenzen Bilder, egal auf welchem Weg sie gefüllt wird.
    @Published var referenzen: [URL] = [] {
        didSet {
            if referenzen.count > Self.hoechstensReferenzen {
                referenzen = Array(referenzen.prefix(Self.hoechstensReferenzen))
                return
            }
            masseAktualisieren()
        }
    }
    /// Meldung zum Referenzbild, etwa wenn eine Datei kein Bild ist. Sie steht immer sichtbar in der Karte.
    @Published var referenzMeldung: String?
    @Published var referenzStaerke: Double { didSet { sichern() } }
    /// Grösse mit Vorlage, im Seitenverhältnis des Referenzbildes.
    @Published private(set) var vorlageMasse: (breite: Int, hoehe: Int)?

    /// MOSS baut auf genau einem Referenzbild auf.
    nonisolated static let hoechstensReferenzen = 1

    @Published var aktiv: Set<ModellID> { didSet { sichern() } }
    @Published var einstellungen: [ModellID: ModellEinstellung] { didSet { sichern() } }
    @Published var stufe: Stufe { didSet { sichern() } }
    @Published var laengeSeite: Int { didSet { masseAktualisieren(); sichern() } }
    @Published var format: Bildformat { didSet { masseAktualisieren(); sichern() } }
    @Published var anzahl: Int { didSet { sichern() } }
    @Published var festerStartwert: Bool { didSet { sichern() } }
    @Published var startwert: Int { didSet { sichern() } }
    @Published var module: [Modul] = []
    /// Meldung, wenn sich ein eigenes Modul nicht hinzufügen liess.
    @Published var modulMeldung: String?
    @Published var modulAktiv: Set<String> { didSet { sichern() } }
    @Published var modulStaerke: [String: Double] { didSet { sichern() } }
    /// Aufgeklappte Modulgruppen unter Neues Bild.
    @Published var offeneGruppen: Set<String> { didSet { sichern() } }
    /// Zeigt unter Neues Bild an, dass die Werte von einem fertigen Bild stammen.
    @Published var vonBildUebernommen = false
    /// Was sich beim Übernehmen nicht wiederherstellen liess.
    @Published var uebernahmeLuecken: [String] = []

    init() {
        let s = Pfade.speicher
        // Unbekannte Modellnamen in gespeicherten Einstellungen fallen weg.
        let gespeichertAktiv = (s.array(forKey: "aktiv") as? [String])?.compactMap(ModellID.init(rawValue:)) ?? []
        aktiv = gespeichertAktiv.isEmpty ? Set(ModellID.allCases) : Set(gespeichertAktiv)
        let startStufe = Stufe(rawValue: s.string(forKey: "stufe") ?? "") ?? .standard
        stufe = startStufe
        var werte = Dictionary(uniqueKeysWithValues: ModellID.allCases.map { ($0, $0.vorgabe(startStufe)) })
        if s.integer(forKey: "einstellungsstand") >= 2, let daten = s.data(forKey: "einstellungen") {
            werte.merge(ModellEinstellung.lesen(daten)) { _, gespeichert in gespeichert }
        }
        einstellungen = werte
        let seite = s.integer(forKey: "laengeSeite")
        laengeSeite = seite == 0 ? startStufe.laengeSeite : seite
        format = Bildformat(rawValue: s.string(forKey: "format") ?? "") ?? .quadrat
        let menge = s.integer(forKey: "anzahl")
        anzahl = menge == 0 ? 1 : menge
        festerStartwert = s.bool(forKey: "festerStartwert")
        let wert = s.integer(forKey: "startwert")
        startwert = wert == 0 ? 42 : wert
        modulAktiv = Set(s.stringArray(forKey: "modulAktiv") ?? [Modul.streifenDatei])
        modulStaerke = (s.dictionary(forKey: "modulStaerke") as? [String: Double]) ?? [:]
        offeneGruppen = Set(s.stringArray(forKey: "offeneGruppen") ?? [])
        let staerke = s.double(forKey: "referenzStaerke")
        referenzStaerke = staerke == 0 ? 0.625 : staerke
        s.set(2, forKey: "einstellungsstand")
        masseAktualisieren()
        moduleLaden()
    }

    var promptLeer: Bool { prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hatNegativ: Bool { !negativ.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var modelle: [ModellID] {
        ModellID.allCases.filter { aktiv.contains($0) }
    }

    /// Das Referenzbild, auf dem MOSS aufbaut.
    var vorlage: URL? { referenzen.first }

    /// Eine Rechnung für Auftrag, Schätzung und Anzeige. Mit Vorlage gilt deren Seitenverhältnis,
    /// sonst das gewählte Format.
    func masse(fuer modell: ModellID) -> (breite: Int, hoehe: Int) {
        if let vorlageMasse { return vorlageMasse }
        return format.masse(laengeSeite: laengeSeite)
    }

    /// Die Formatwahl zählt nur ohne Vorlage.
    var formatGenutzt: Bool {
        vorlageMasse == nil || modelle.isEmpty
    }

    func einstellung(_ modell: ModellID) -> ModellEinstellung {
        einstellungen[modell] ?? modell.vorgabe(.standard)
    }

    /// Die Stufe, zu der die aktuellen Werte passen. Nach eigenen Änderungen gibt es keine.
    var aktuelleStufe: Stufe? {
        Stufe.allCases.first { stufe in
            laengeSeite == stufe.laengeSeite
                && ModellID.allCases.allSatisfy { einstellung($0) == $0.vorgabe(stufe) }
        }
    }

    /// Ein Auftrag nur zum Schätzen, ohne zufälligen Startwert.
    func muster(_ modell: ModellID) -> Auftrag {
        auftrag(modell, gruppe: UUID(), seed: 1)
    }

    /// Alle Bilder eines Klicks gehören zu einer Gruppe.
    func auftragsliste() -> [Auftrag] {
        let gruppe = UUID()
        return (0..<anzahl).flatMap { nummer -> [Auftrag] in
            // Die CLI erwartet 32 Bit, darum bleibt der Startwert samt Serie in diesem Bereich.
            let basis = min(max(startwert, 0), Int(UInt32.max) - 20)
            let seed = festerStartwert ? basis + nummer : Int.random(in: 1...2_147_483_647)
            return modelle.map { auftrag($0, gruppe: gruppe, seed: seed) }
        }
    }

    func moduleLaden() {
        Task { await moduleNeuLaden() }
    }

    /// Dateien werden im Hintergrund gelesen, damit die Oberfläche nicht stockt.
    func moduleNeuLaden() async {
        module = await Task.detached { Modul.vorhandene() }.value
    }

    func moduleHinzufuegen(_ urls: [URL]) {
        Task {
            let ergebnis = await Task.detached { Modul.hinzufuegen(urls) }.value
            modulAktiv.formUnion(ergebnis.neu)
            modulMeldung = ergebnis.meldung
            await moduleNeuLaden()
        }
    }

    /// Hängt Bilder an, solange Platz ist. Nur lesbare Bilddateien auf diesem Mac zählen,
    /// eine Web-Adresse würde die App ins Netz schicken. Was nicht dazukommt, nennt die Meldung.
    func referenzenHinzufuegen(_ urls: [URL]) {
        var neu = referenzen
        var unlesbar = 0, doppelt = 0, zuViele = 0
        // Platz und Doppelte zuerst, so liest die App nur Dateien, die wirklich dazukommen können.
        // Gelesen wird nur der Dateikopf.
        for url in urls {
            guard neu.count < Self.hoechstensReferenzen else { zuViele += 1; continue }
            guard !neu.contains(url) else { doppelt += 1; continue }
            guard url.isFileURL, Vorschau.masse(url) != nil else { unlesbar += 1; continue }
            neu.append(url)
        }
        if neu != referenzen { referenzen = neu }
        var teile = [String]()
        if zuViele > 0 {
            if zuViele == urls.count {
                teile.append(String(localized: "Only one reference image is possible. Replace it with Other Image, or remove it first."))
            } else {
                teile.append(zuViele == 1
                    ? String(localized: "Only one reference image is possible, 1 more image was not added.")
                    : String(localized: "Only one reference image is possible, \(zuViele) more images were not added."))
            }
        }
        if unlesbar > 0 {
            teile.append(unlesbar == 1 ? String(localized: "One file is not a readable image.")
                : String(localized: "\(unlesbar) files are not readable images."))
        }
        if doppelt > 0 { teile.append(String(localized: "This image is already the reference image.")) }
        referenzMeldung = teile.isEmpty ? nil : teile.joined(separator: " ")
    }

    /// Setzt das Referenzbild, auf dem MOSS aufbaut. Ein vorhandenes wird ersetzt.
    func vorlageSetzen(_ url: URL) {
        guard url.isFileURL, Vorschau.masse(url) != nil else {
            referenzMeldung = String(localized: "This file is not a readable image.")
            return
        }
        referenzMeldung = nil
        referenzen = [url]
    }

    func referenzEntfernen(_ stelle: Int) {
        guard referenzen.indices.contains(stelle) else { return }
        referenzen.remove(at: stelle)
        referenzMeldung = nil
    }

    func referenzenLeeren() {
        referenzen = []
        referenzMeldung = nil
    }

    /// Stellt alles ein wie beim gewählten Bild, auch die Zufallszahl.
    /// So lässt sich gezielt eine einzige Sache ändern und ihre Wirkung vergleichen.
    func uebernehmen(_ ergebnis: Ergebnis) {
        uebernehmen([ergebnis])
    }

    /// Stellt alles ein wie bei einer ganzen Generierung: Text, Zufallszahlen, Werte, Module und Referenzbild.
    func uebernehmen(_ bilder: [Ergebnis]) {
        guard let erstes = bilder.first else { return }
        var luecken = [String]()
        defer {
            uebernahmeLuecken = luecken.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
            vonBildUebernommen = true
        }
        prompt = erstes.prompt
        negativ = bilder.first { !$0.negativ.isEmpty }?.negativ ?? erstes.negativ
        var zahlen = [Int]()
        for bild in bilder where !zahlen.contains(bild.seed) { zahlen.append(bild.seed) }
        festerStartwert = true
        startwert = zahlen[0]
        anzahl = zahlen.count
        // Eine feste Serie zählt von der ersten Zufallszahl hoch, freie Zufallszahlen lassen sich so nicht nachstellen.
        if zahlen != zahlen.indices.map({ zahlen[0] + $0 }) {
            luecken.append(String(localized: "These images had random seeds. Only the first one comes out exactly the same, the others will be new."))
        }
        referenzen = []
        referenzMeldung = nil
        if let staerke = bilder.first(where: { $0.referenzStaerke != nil })?.referenzStaerke { referenzStaerke = staerke }
        referenzUebernehmen(bilder, &luecken)
        let vorhandene = ModellID.allCases.filter { modell in bilder.contains { $0.modell == modell } }
        if !vorhandene.isEmpty { aktiv = Set(vorhandene) }
        for modell in vorhandene {
            if let bild = bilder.first(where: { $0.modell == modell }) { modellUebernehmen(bild, &luecken) }
        }
        // Das Format stammt von einem Bild ohne Vorlage. Mit Vorlage gilt deren Grösse.
        let formatBild = bilder.first { $0.referenzen == 0 } ?? erstes
        if formatBild.breite > 0, formatBild.hoehe > 0 {
            let seite = max(formatBild.breite, formatBild.hoehe)
            laengeSeite = seite
            if let name = formatBild.formatName, let passend = Bildformat(rawValue: name) {
                format = passend
            } else if let passend = Bildformat.allCases.first(where: {
                let masse = $0.masse(laengeSeite: seite)
                return masse.breite == formatBild.breite && masse.hoehe == formatBild.hoehe
            }) {
                format = passend
            }
        }
        if vorlage != nil, let mitVorlage = bilder.first(where: { $0.referenzen > 0 }),
           mitVorlage.breite > 0, mitVorlage.hoehe > 0 {
            vorlageMasse = (mitVorlage.breite, mitVorlage.hoehe)
        }
        if bilder.contains(where: { $0.auftrag == nil }) {
            luecken.append(String(localized: "The image comes from an earlier version and probably cannot be recreated exactly."))
        }
    }

    /// MOSS hat nur das erste Referenzbild genutzt, darum kommt nur dieses zurück, als Kopie aus dem Bildordner.
    private func referenzUebernehmen(_ bilder: [Ergebnis], _ luecken: inout [String]) {
        var namen = [String]()
        for name in bilder.compactMap(\.referenzNamen.first) where !namen.contains(name) { namen.append(name) }
        guard let name = namen.first else {
            if bilder.contains(where: { $0.referenzen > 0 }) {
                luecken.append(String(localized: "The reference image of this image is no longer available."))
            }
            return
        }
        guard namen.count == 1 else {
            luecken.append(String(localized: "The images of this generation had different reference images. Choose the reference image again."))
            return
        }
        guard let kopie = Pfade.referenzKopie(name), FileManager.default.fileExists(atPath: kopie.path) else {
            luecken.append(String(localized: "The reference image of this image is no longer available."))
            return
        }
        referenzen = [kopie]
    }

    /// Werte und Module eines Modells.
    private func modellUebernehmen(_ ergebnis: Ergebnis, _ luecken: inout [String]) {
        var wert = einstellung(ergebnis.modell)
        if ergebnis.schritte > 0 { wert.schritte = ergebnis.schritte }
        // Die 2 kam nur vom Negativprompt. Der Grundwert bleibt 1, sonst rechnet es ohne Negativprompt unnötig doppelt.
        wert.textfuehrung = !ergebnis.negativ.isEmpty && ergebnis.textfuehrung == 2 ? 1 : ergebnis.textfuehrung
        wert.turbo = ergebnis.turbo ?? ergebnis.module?.contains("Turbo") ?? false
        einstellungen[ergebnis.modell] = wert
        // Manche Angaben kennen nur die Modulnamen, dort gelten die aktuellen Stärken.
        let genau = (ergebnis.modulDaten ?? []).filter { $0.name != "Turbo" }
        let namen = (ergebnis.module ?? []).filter { $0 != "Turbo" }
        var aktive = Set<String>()
        var fehlend = [String]()
        for name in namen {
            guard let modul = module.first(where: { $0.name == name }) else {
                fehlend.append(name)
                continue
            }
            aktive.insert(modul.datei)
            if let daten = genau.first(where: { $0.name == name }) { modulStaerke[modul.datei] = daten.staerke }
        }
        // Gewählte Module, die gerade nicht im Ordner liegen, bleiben gewählt.
        modulAktiv = modulAktiv.subtracting(module.map(\.datei)).union(aktive)
        if ergebnis.modulDaten == nil && !namen.isEmpty {
            luecken.append(String(localized: "The module strengths of this image are not saved, the current ones apply."))
        }
        if !fehlend.isEmpty {
            // Gespeichert sind die festen Namen. Module aus dem Katalog erscheinen mit ihrem Titel in der Sprache des Mac.
            let titel = fehlend.map { name in Katalog.alle.first { $0.name == name }?.anzeigeName ?? name }
            luecken.append(String(localized: "These modules are missing now: \(titel.joined(separator: ", "))."))
        }
    }

    func modulEntfernen(_ modul: Modul) {
        Modul.entfernen(modul)
        modulAktiv.remove(modul.datei)
        modulStaerke[modul.datei] = nil
        moduleLaden()
    }

    /// Der Streifen-Fix braucht bei 1024 Pixeln mehr Stärke als bei 768, solange niemand sie selbst setzt.
    func staerke(_ modul: Modul) -> Double {
        if let eigene = modulStaerke[modul.datei] { return eigene }
        if modul.datei == Modul.streifenDatei {
            let groesse = masse(fuer: .moss)
            return max(groesse.breite, groesse.hoehe) >= 1024 ? 1.5 : 1.0
        }
        return modul.standardStaerke
    }

    private func auftrag(_ modell: ModellID, gruppe: UUID, seed: Int) -> Auftrag {
        let wert = einstellung(modell)
        let aktive = module.filter { modulAktiv.contains($0.datei) && $0.format != .unbrauchbar }
        var gewaehlt = aktive.map { GewaehltesModul(name: $0.name, pfad: $0.pfad.path, staerke: staerke($0)) }
        if wert.turbo {
            let turbo = Pfade.module.appendingPathComponent(Modul.turboDatei)
            gewaehlt.insert(GewaehltesModul(name: "Turbo", pfad: turbo.path, staerke: 0.7), at: 0)
        }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        // Auslöser gehen nur ans Modell. Im Verlauf bleibt der Text, den der Nutzer eingegeben hat.
        let ausloeser = aktive.compactMap(\.ausloeser)
            .filter { !text.localizedCaseInsensitiveContains($0) }.joined(separator: ", ")
        let bilder = Array(referenzen.prefix(Self.hoechstensReferenzen))
        let groesse = masse(fuer: modell)
        return Auftrag(
            gruppe: gruppe, prompt: text, negativ: negativ.trimmingCharacters(in: .whitespacesAndNewlines),
            modell: modell, schritte: wert.schritte, textfuehrung: wert.wirksameTextfuehrung(negativ: negativ),
            breite: groesse.breite, hoehe: groesse.hoehe, seed: seed, referenzen: bilder,
            turbo: wert.turbo, module: gewaehlt, ausloeser: ausloeser.isEmpty ? nil : ausloeser,
            referenzStaerke: bilder.isEmpty ? nil : referenzStaerke, formatName: format.rawValue)
    }

    func stufeAnwenden(_ neu: Stufe) {
        // Übernommene Bilder setzen die Stärke des Streifen-Fix fest, die Stufe gibt sie wieder frei.
        modulStaerke[Modul.streifenDatei] = nil
        stufe = neu
        laengeSeite = neu.laengeSeite
        einstellungen = Dictionary(uniqueKeysWithValues: ModellID.allCases.map { ($0, $0.vorgabe(neu)) })
    }

    /// Liest die Masse der Vorlage einmal, statt bei jedem Neuzeichnen.
    private func masseAktualisieren() {
        if let vorlage, let bild = Vorschau.masse(vorlage) {
            let faktor = Double(laengeSeite) / Double(max(bild.breite, bild.hoehe, 1))
            vorlageMasse = (runde16(Double(bild.breite) * faktor), runde16(Double(bild.hoehe) * faktor))
        } else {
            vorlageMasse = nil
        }
    }

    private func sichern() {
        speicher.set(aktiv.map(\.rawValue), forKey: "aktiv")
        speicher.set(try? JSONEncoder().encode(einstellungen), forKey: "einstellungen")
        speicher.set(stufe.rawValue, forKey: "stufe")
        speicher.set(laengeSeite, forKey: "laengeSeite")
        speicher.set(format.rawValue, forKey: "format")
        speicher.set(anzahl, forKey: "anzahl")
        speicher.set(festerStartwert, forKey: "festerStartwert")
        speicher.set(startwert, forKey: "startwert")
        speicher.set(Array(modulAktiv), forKey: "modulAktiv")
        speicher.set(modulStaerke, forKey: "modulStaerke")
        speicher.set(Array(offeneGruppen), forKey: "offeneGruppen")
        speicher.set(referenzStaerke, forKey: "referenzStaerke")
    }
}
