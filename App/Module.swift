import Foundation

/// Ein Zusatzmodul im Ordner Module. Module aus dem Katalog bringen Beschreibung und Startwerte mit.
struct Modul: Identifiable, Equatable {
    enum Format {
        /// Alle Ebenen passen zu MOSS.
        case passt
        /// Nur ein Teil der Ebenen passt, mflux lädt den Rest nicht.
        case teilweise
        case unbrauchbar
    }

    let datei: String
    /// Fester Name, so steht das Modul in Aufträgen und Bildangaben. Er bleibt in jeder Sprache gleich.
    let name: String
    /// Der Name zur Anzeige, bei Modulen aus dem Katalog in der Sprache des Mac.
    let anzeigeName: String
    let beschreibung: String
    let standardStaerke: Double
    let ausloeser: String?
    let format: Format

    var id: String { datei }
    var pfad: URL { Pfade.module.appendingPathComponent(datei) }

    var hinweis: String? {
        switch format {
        case .passt: nil
        case .teilweise: String(localized: "Only partly works in this app, the file format does not quite fit.")
        case .unbrauchbar: String(localized: "This file does not fit any model in the app and stays off.")
        }
    }

    static let turboDatei = "turbo-8-schritte.safetensors"
    static let streifenDatei = "streifen-fix.safetensors"
    /// Feste Kennung der Gruppe mit eigenen Modulen unter Neues Bild, so ist ihr Zustand gespeichert.
    static let eigeneGruppe = "Eigene Module"

    /// Alle Module im Ordner, das Turbo-Modul steuert die App selbst. Liest Dateien, gehört also nicht in den Hauptthread.
    static func vorhandene() -> [Modul] {
        let dateien = (try? FileManager.default.contentsOfDirectory(atPath: Pfade.module.path)) ?? []
        return dateien.filter { $0.hasSuffix(".safetensors") && $0 != turboDatei }
            .map { datei in
                let pfad = Pfade.module.appendingPathComponent(datei)
                angleichen(pfad)
                let art = dateiformat(pfad) ?? .unbrauchbar
                if let eintrag = Katalog.eintrag(datei) {
                    return Modul(datei: datei, name: eintrag.name, anzeigeName: eintrag.anzeigeName,
                                 beschreibung: eintrag.beschreibung, standardStaerke: eintrag.staerke,
                                 ausloeser: eintrag.ausloeser, format: art)
                }
                let name = (datei as NSString).deletingPathExtension.replacingOccurrences(of: "-", with: " ")
                return Modul(datei: datei, name: name, anzeigeName: name,
                             beschreibung: String(localized: "Module you added yourself."),
                             standardStaerke: 1, ausloeser: nil, format: art)
            }
            .sorted { $0.anzeigeName < $1.anzeigeName }
    }

    /// Liest den Dateikopf einer safetensors-Datei.
    private static func kopfLesen(_ griff: FileHandle) -> Data? {
        guard let anfang = try? griff.read(upToCount: 8), anfang.count == 8 else { return nil }
        let laenge = anfang.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
        guard laenge < 100_000_000, let kopf = try? griff.read(upToCount: Int(laenge)),
              kopf.count == Int(laenge) else { return nil }
        return kopf
    }

    /// Jeder Tensor nennt seine Lage in der Datei, so fallen abgeschnittene oder kaputte Dateien auf.
    private static func stimmig(_ tensoren: [String: Any], nutzlast: UInt64) -> Bool {
        var ende: UInt64 = 0
        for wert in tensoren.values {
            guard let lage = (wert as? [String: Any])?["data_offsets"] as? [Int], lage.count == 2,
                  let anfang = UInt64(exactly: lage[0]), let schluss = UInt64(exactly: lage[1]),
                  anfang <= schluss else { return false }
            ende = max(ende, schluss)
        }
        return !tensoren.isEmpty && ende == nutzlast
    }

    /// Die Ebenennamen, die mflux bei MOSS kennt.
    private static let bekannteEbene = try! Regex(
        #"^(diffusion_model\.|transformer\.|base_model\.model\.)?layers\.\d+\.proj\.(q|k|v|o|ffn_up_gate|ffn_down)\.(alpha|(lora_A|lora_B|lora_down|lora_up)(\.default)?(\.weight)?)$"#)

    /// Ebenen, die es bei MOSS nicht gibt. Ein Modul mit solchen Ebenen gehört zu einem anderen Modell,
    /// auch wenn einzelne seiner Namen zufällig wie bei MOSS aussehen.
    private static func fremd(_ name: String) -> Bool {
        ["text_fusion.", "txtfusion.", ".to_gate.", ".attn.gate."].contains { name.contains($0) }
    }

    /// Erkennt am Dateikopf, ob ein Modul zu MOSS passt und ob mflux es lesen kann.
    /// Ohne gültigen Kopf ist es kein Modul.
    static func dateiformat(_ url: URL) -> Format? {
        guard let griff = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? griff.close() }
        guard let daten = kopfLesen(griff),
              let kopf = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any],
              let groesse = try? griff.seekToEnd(), groesse >= 8 + UInt64(daten.count) else { return nil }
        let tensoren = kopf.filter { $0.key != "__metadata__" }
        guard stimmig(tensoren, nutzlast: groesse - 8 - UInt64(daten.count)) else { return nil }
        let namen = tensoren.keys
        if namen.contains(where: { $0.contains("lokr_") || $0.contains("hada_") }) { return .unbrauchbar }
        if namen.contains(where: fremd) { return .unbrauchbar }
        let passend = namen.filter { $0.wholeMatch(of: bekannteEbene) != nil }.count
        if passend == 0 { return .unbrauchbar }
        return passend == namen.count ? .passt : .teilweise
    }

    /// Bringt eine Moduldatei in die Form, die mflux vollständig lesen kann. Gerechnet wird im Speicher,
    /// geschrieben höchstens einmal am Schluss. Bei Unklarheit bleibt die Datei, wie sie ist.
    static func angleichen(_ url: URL) {
        guard let griff = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? griff.close() }
        guard let kopfDaten = kopfLesen(griff),
              let alt = (try? JSONSerialization.jsonObject(with: kopfDaten)) as? [String: Any],
              alt.keys.contains(where: { $0.hasPrefix("lora_unet_layers_") || $0.contains(".proj.qkv.") }),
              let kopf = namenAngleichen(alt), let gewichte = try? griff.readToEnd(),
              stimmig(alt.filter { $0.key != "__metadata__" }, nutzlast: UInt64(gewichte.count)),
              let neu = ebenenAufteilen(kopf, gewichte), Set(neu.kopf.keys) != Set(alt.keys),
              let neuerKopf = try? JSONSerialization.data(withJSONObject: neu.kopf) else { return }
        var inhalt = withUnsafeBytes(of: UInt64(neuerKopf.count).littleEndian) { Data($0) }
        inhalt.append(neuerKopf)
        inhalt.append(neu.gewichte)
        try? inhalt.write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }

    /// Viele Module nennen ihre Ebenen lora_unet_layers_0_proj_q, mflux erwartet diffusion_model.layers.0.proj.q.
    /// Geändert werden nur die Namen, nie Gewichte oder Metadaten.
    private static func namenAngleichen(_ kopf: [String: Any]) -> [String: Any]? {
        guard let muster = try? Regex(#"lora_unet_layers_(\d+)_proj_(qkv|q|k|v|o|ffn_up_gate|ffn_down)\.(.+)"#) else { return nil }
        var neu = [String: Any]()
        for (schluessel, wert) in kopf {
            var ziel = schluessel
            if let treffer = schluessel.wholeMatch(of: muster),
               let ebene = treffer[1].substring, let teil = treffer[2].substring, let rest = treffer[3].substring {
                ziel = "diffusion_model.layers.\(ebene).proj.\(teil).\(rest)"
            }
            guard neu[ziel] == nil else { return nil }
            neu[ziel] = wert
        }
        return neu
    }

    /// Manche Module fassen q, k und v zu einer Ebene qkv zusammen, die mflux nicht kennt. Die drei Teile
    /// liegen zeilenweise hintereinander und lassen sich ohne Verlust trennen, wie ai-toolkit es beim Speichern tut.
    private static func ebenenAufteilen(_ kopf: [String: Any], _ gewichte: Data) -> (kopf: [String: Any], gewichte: Data)? {
        guard kopf.keys.contains(where: { $0.contains(".proj.qkv.") }) else { return (kopf, gewichte) }
        var neuerKopf = [String: Any]()
        var neueGewichte = Data()
        neueGewichte.reserveCapacity(gewichte.count + gewichte.count / 4)
        func ablegen(_ name: String, _ vorlage: [String: Any], form: [Int], _ inhalt: Data) {
            var eintrag = vorlage
            eintrag["shape"] = form
            eintrag["data_offsets"] = [neueGewichte.count, neueGewichte.count + inhalt.count]
            neuerKopf[name] = eintrag
            neueGewichte.append(inhalt)
        }
        var verschmolzen = 0
        for (name, wert) in kopf.sorted(by: { $0.key < $1.key }) where name != "__metadata__" {
            guard let info = wert as? [String: Any], let form = info["shape"] as? [Int],
                  let lage = info["data_offsets"] as? [Int], lage.count == 2,
                  lage[0] >= 0, lage[0] <= lage[1], lage[1] <= gewichte.count else { return nil }
            let teile = name.components(separatedBy: ".proj.qkv.")
            guard teile.count == 2 else {
                ablegen(name, info, form: form, gewichte[lage[0]..<lage[1]])
                continue
            }
            verschmolzen += 1
            let (basis, rest) = (teile[0], teile[1])
            if rest.hasPrefix("lora_B") || rest.hasPrefix("lora_up") {
                let breite = (lage[1] - lage[0]) / 3
                guard form.count == 2, form[0] % 3 == 0, (lage[1] - lage[0]) % 3 == 0 else { return nil }
                for (nummer, ebene) in ["q", "k", "v"].enumerated() {
                    let anfang = lage[0] + nummer * breite
                    ablegen("\(basis).proj.\(ebene).\(rest)", info, form: [form[0] / 3, form[1]],
                            gewichte[anfang..<anfang + breite])
                }
            } else if rest.hasPrefix("lora_A") || rest.hasPrefix("lora_down") || rest == "alpha" {
                for ebene in ["q", "k", "v"] {
                    ablegen("\(basis).proj.\(ebene).\(rest)", info, form: form, gewichte[lage[0]..<lage[1]])
                }
            } else {
                return nil
            }
        }
        if let metadaten = kopf["__metadata__"] { neuerKopf["__metadata__"] = metadaten }
        // Stimmt die Zahl nicht, gab es q, k oder v schon.
        guard neuerKopf.count == kopf.count + 2 * verschmolzen else { return nil }
        return (neuerKopf, neueGewichte)
    }

    /// Kopiert Dateien in den Modulordner. Liefert die brauchbaren Namen und eine Meldung, falls etwas nicht ging.
    static func hinzufuegen(_ quellen: [URL]) -> (neu: [String], meldung: String?) {
        var neu = [String]()
        var meldung: String?
        try? FileManager.default.createDirectory(at: Pfade.module, withIntermediateDirectories: true)
        for quelle in quellen {
            let name = quelle.lastPathComponent
            let ziel = Pfade.module.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: ziel.path) {
                meldung = String(localized: "A module named \(name) already exists.")
                continue
            }
            guard (try? FileManager.default.copyItem(at: quelle, to: ziel)) != nil else {
                meldung = String(localized: "The module could not be added. Is the disk full?")
                continue
            }
            angleichen(ziel)
            if let art = dateiformat(ziel), art != .unbrauchbar {
                neu.append(name)
            } else {
                meldung = String(localized: "\(name) does not fit any model in the app and stays off.")
            }
        }
        return (neu, meldung)
    }

    static func entfernen(_ modul: Modul) {
        try? FileManager.default.trashItem(at: modul.pfad, resultingItemURL: nil)
    }
}
