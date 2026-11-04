import Foundation

/// Prüft die Modulerkennung mit kleinen, erfundenen safetensors-Dateien: passende MOSS-Module, Angleichen der
/// Ebenennamen, Aufteilen verschmolzener Ebenen, fremde und kaputte Dateien. Dazu das Laden vom Testserver.
@MainActor
enum ModulPruefung {
    /// Ebenen, wie mflux sie bei MOSS kennt.
    private static func moss(_ praefix: String = "diffusion_model.") -> [(String, [Int], Int)] {
        [("\(praefix)layers.0.proj.q.lora_A.weight", [4, 64], 512), ("\(praefix)layers.0.proj.q.lora_B.weight", [64, 4], 512),
         ("\(praefix)layers.0.proj.q.alpha", [], 2),
         ("\(praefix)layers.1.proj.ffn_down.lora_down.weight", [4, 64], 512),
         ("\(praefix)layers.1.proj.ffn_down.lora_up.weight", [64, 4], 512)]
    }

    static func ausfuehren(_ bericht: Pruefbericht) async {
        let proben = Testumgebung.ordner.appendingPathComponent("Modulproben", isDirectory: true)
        func format(_ url: URL) -> String { Modul.dateiformat(url).map { "\($0)" } ?? "kein Modul" }

        let passend = Hilfe.safetensors("passend.safetensors", moss(), in: proben)
        let ohnePraefix = Hilfe.safetensors("ohne-praefix.safetensors", moss(""), in: proben)
        bericht.pruefen("MOSS-Modul passt", Modul.dateiformat(passend) == .passt && Modul.dateiformat(ohnePraefix) == .passt,
                        "\(format(passend)), ohne Präfix \(format(ohnePraefix))")

        let teilweise = Hilfe.safetensors("teilweise.safetensors",
                                          moss() + [("text_encoder.layers.0.mlp.lora_A.weight", [4, 64], 512)], in: proben)
        bericht.pruefen("MOSS-Modul mit zusätzlichen Ebenen wirkt teilweise", Modul.dateiformat(teilweise) == .teilweise,
                        format(teilweise))

        // Namen wie lora_unet_layers_0_proj_q werden zu diffusion_model.layers.0.proj.q, die Gewichte bleiben gleich.
        let benannt = Hilfe.safetensors("benannt.safetensors", [
            ("lora_unet_layers_0_proj_q.lora_down.weight", [4, 64], 512), ("lora_unet_layers_0_proj_q.lora_up.weight", [64, 4], 512),
            ("lora_unet_layers_0_proj_q.alpha", [], 2)], in: proben)
        let vorherBenannt = try? Data(contentsOf: benannt)
        Modul.angleichen(benannt)
        let kopfBenannt = Hilfe.kopf(benannt)
        bericht.pruefen("Ebenennamen angleichen", Modul.dateiformat(benannt) == .passt
                        && kopfBenannt["diffusion_model.layers.0.proj.q.lora_down.weight"] != nil
                        && !kopfBenannt.keys.contains { $0.hasPrefix("lora_unet_") }
                        && (try? Data(contentsOf: benannt))?.suffix(1026) == vorherBenannt?.suffix(1026),
                        "\(kopfBenannt.keys.sorted())")

        // Verschmolzene Ebene qkv: lora_B wird zeilenweise in q, k und v geteilt, lora_A und alpha gelten für alle drei.
        let verschmolzen = Hilfe.safetensors("verschmolzen.safetensors", [
            ("diffusion_model.layers.0.proj.qkv.lora_A.weight", [4, 64], 512),
            ("diffusion_model.layers.0.proj.qkv.lora_B.weight", [192, 4], 1536),
            ("diffusion_model.layers.0.proj.qkv.alpha", [], 2)], in: proben)
        let roh = (try? Data(contentsOf: verschmolzen)) ?? Data()
        let rohKopf = Hilfe.kopf(verschmolzen)
        func stueck(_ datei: Data, _ kopf: [String: Any], _ name: String) -> Data? {
            guard let lage = (kopf[name] as? [String: Any])?["data_offsets"] as? [Int], lage.count == 2,
                  datei.count >= 8 else { return nil }
            let laenge = datei.prefix(8).withUnsafeBytes { Int(UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self))) }
            let anfang = 8 + laenge
            guard anfang + lage[1] <= datei.count else { return nil }
            return datei.subdata(in: anfang + lage[0]..<anfang + lage[1])
        }
        Modul.angleichen(verschmolzen)
        let neu = (try? Data(contentsOf: verschmolzen)) ?? Data()
        let neuKopf = Hilfe.kopf(verschmolzen)
        let b = stueck(roh, rohKopf, "diffusion_model.layers.0.proj.qkv.lora_B.weight") ?? Data()
        let a = stueck(roh, rohKopf, "diffusion_model.layers.0.proj.qkv.lora_A.weight") ?? Data()
        let geteilt = ["q", "k", "v"].enumerated().allSatisfy { nummer, ebene in
            let teilB = stueck(neu, neuKopf, "diffusion_model.layers.0.proj.\(ebene).lora_B.weight")
            let form = (neuKopf["diffusion_model.layers.0.proj.\(ebene).lora_B.weight"] as? [String: Any])?["shape"] as? [Int]
            return b.count == 1536 && teilB == b.subdata(in: b.startIndex + nummer * 512..<b.startIndex + (nummer + 1) * 512)
                && form == [64, 4] && stueck(neu, neuKopf, "diffusion_model.layers.0.proj.\(ebene).lora_A.weight") == a
                && neuKopf["diffusion_model.layers.0.proj.\(ebene).alpha"] != nil
        }
        bericht.pruefen("Verschmolzene Ebenen aufteilen", geteilt && Modul.dateiformat(verschmolzen) == .passt
                        && !neuKopf.keys.contains { $0.contains(".qkv.") }, "\(neuKopf.keys.sorted())")

        // Module anderer Modelle passen nie, auch wenn einzelne Namen wie bei MOSS aussehen.
        let fremdA = Hilfe.safetensors("fremd-a.safetensors", moss() + [
            ("diffusion_model.layers.0.text_fusion.proj.lora_A.weight", [4, 64], 512),
            ("diffusion_model.layers.0.attn.gate.lora_B.weight", [64, 4], 512)], in: proben)
        let fremdB = Hilfe.safetensors("fremd-b.safetensors", [
            ("transformer.transformer_blocks.0.attn.to_q.lora_A.weight", [4, 64], 512),
            ("transformer.transformer_blocks.0.attn.to_q.lora_B.weight", [64, 4], 512),
            ("transformer.single_transformer_blocks.0.attn.to_k.lora_A.weight", [4, 64], 512)], in: proben)
        let fremdC = Hilfe.safetensors("fremd-c.safetensors", [
            ("double_blocks.0.img_attn.qkv.lora_A.weight", [4, 64], 512),
            ("double_blocks.0.img_attn.qkv.lora_B.weight", [192, 4], 1536)], in: proben)
        Modul.angleichen(fremdC)
        bericht.pruefen("Module anderer Modelle passen nicht", [fremdA, fremdB, fremdC].allSatisfy { Modul.dateiformat($0) == .unbrauchbar },
                        "\(format(fremdA)), \(format(fremdB)), \(format(fremdC))")

        let lokr = Hilfe.safetensors("lokr.safetensors", [
            ("diffusion_model.layers.0.proj.q.lokr_w1", [4, 4], 32), ("diffusion_model.layers.0.proj.q.lokr_w2", [16, 16], 512)],
                                     in: proben)
        bericht.pruefen("LoKr-Module passen nicht", Modul.dateiformat(lokr) == .unbrauchbar, format(lokr))

        let abgeschnitten = Hilfe.safetensors("abgeschnitten.safetensors", moss(), in: proben, abschneiden: 10)
        let keinModul = proben.appendingPathComponent("kein-modul.safetensors")
        try? Data("kein Modul, nur Text".utf8).write(to: keinModul)
        let riesenkopf = proben.appendingPathComponent("riesenkopf.safetensors")
        try? withUnsafeBytes(of: UInt64(200_000_000).littleEndian, { Data($0) }).write(to: riesenkopf)
        bericht.pruefen("Kaputte Dateien sind keine Module", Modul.dateiformat(abgeschnitten) == nil
                        && Modul.dateiformat(keinModul) == nil && Modul.dateiformat(riesenkopf) == nil,
                        "\(format(abgeschnitten)), \(format(keinModul)), \(format(riesenkopf))")

        // Eigene Module hinzufügen: passende werden eingeschaltet, fremde bleiben aus und werden gemeldet.
        let ergebnis = Modul.hinzufuegen([passend, fremdA])
        let doppelt = Modul.hinzufuegen([passend])
        bericht.pruefen("Eigene Module hinzufügen", ergebnis.neu == ["passend.safetensors"]
                        && ergebnis.meldung == "fremd-a.safetensors passt zu keinem Modell der App und bleibt ausgeschaltet."
                        && doppelt.neu.isEmpty && doppelt.meldung == "Ein Modul namens passend.safetensors ist schon vorhanden."
                        && FileManager.default.fileExists(atPath: Pfade.module.appendingPathComponent("fremd-a.safetensors").path),
                        "\(ergebnis.neu), \(ergebnis.meldung ?? "-"), \(doppelt.meldung ?? "-")")

        // Ein Auftrag nimmt nur eingeschaltete, brauchbare Module, das Turbo-Modul steuert die App selbst.
        try? FileManager.default.copyItem(at: passend, to: Pfade.module.appendingPathComponent(Modul.turboDatei))
        let vorgaben = Vorgaben.gemeinsam
        await vorgaben.moduleNeuLaden()
        vorgaben.stufeAnwenden(.standard)
        vorgaben.modulAktiv = Set(vorgaben.module.map(\.datei))
        let namen = vorgaben.module.map(\.datei)
        let gewaehlt = vorgaben.muster(.moss).module.map(\.name)
        bericht.pruefen("Auftrag nimmt nur brauchbare Module", namen == ["fremd-a.safetensors", "passend.safetensors"]
                        && vorgaben.module.first { $0.datei == "fremd-a.safetensors" }?.format == .unbrauchbar
                        && gewaehlt == ["Turbo", "passend"], "Module \(namen), im Auftrag \(gewaehlt)")

        await laden(bericht)
    }

    /// Lädt Module vom Testserver wie aus dem Katalog: richtige Datei, falscher Fingerabdruck, fremdes Modul, Umleitung.
    private static func laden(_ bericht: Pruefbericht) async {
        guard let pfad = ProcessInfo.processInfo.environment["GRAPHIS_TESTMANIFEST"],
              let daten = try? Data(contentsOf: URL(fileURLWithPath: pfad)),
              let manifest = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any],
              let module = manifest["module"] as? [[String: Any]] else {
            bericht.pruefen("Testmodule im Manifest", false)
            return
        }
        func eintrag(_ name: String, datei: String, modus: String = "ok", sha256: String? = nil) -> Katalogeintrag? {
            guard let angaben = module.first(where: { $0["name"] as? String == name }),
                  let adresse = (angaben["adresse"] as? String)?.replacingOccurrences(of: "/ok/", with: "/\(modus)/"),
                  let url = URL(string: adresse), let hash = angaben["sha256"] as? String,
                  let bytes = (angaben["bytes"] as? NSNumber)?.int64Value else { return nil }
            return Katalogeintrag(datei: datei, name: "Testmodul", beschreibung: "", kategorie: .werkzeug,
                                  download: url, seite: url, sha256: sha256 ?? hash, bytes: bytes)
        }
        let lader = Modullader.gemeinsam
        func laden(_ eintrag: Katalogeintrag?) async -> (vorhanden: Bool, stand: String) {
            guard let eintrag else { return (false, "kein Eintrag") }
            lader.laden(eintrag)
            await Hilfe.warten(20) { !lader.laeuft(eintrag) }
            let ziel = Pfade.module.appendingPathComponent(eintrag.datei)
            let stand = lader.staende[eintrag.datei].map { "\($0)" } ?? "ohne Fehler"
            return (FileManager.default.fileExists(atPath: ziel.path), stand)
        }
        let gut = await laden(eintrag("moss-modul.safetensors", datei: "geladen.safetensors"))
        let format = Modul.dateiformat(Pfade.module.appendingPathComponent("geladen.safetensors"))
        bericht.pruefen("Modul laden und prüfen", gut.vorhanden && gut.stand == "ohne Fehler" && format == .passt,
                        "\(gut.stand), Format \(format.map { "\($0)" } ?? "fehlt")")
        let falsch = await laden(eintrag("moss-modul.safetensors", datei: "falscher-hash.safetensors",
                                         sha256: String(repeating: "0", count: 64)))
        bericht.pruefen("Falscher Fingerabdruck wird nicht übernommen", !falsch.vorhanden && falsch.stand.contains("stimmt nicht"),
                        falsch.stand)
        let fremd = await laden(eintrag("fremdes-modul.safetensors", datei: "fremd-geladen.safetensors"))
        bericht.pruefen("Fremdes Modul wird nicht übernommen", !fremd.vorhanden && fremd.stand.contains("passt zu keinem Modell"),
                        fremd.stand)
        let umgeleitet = await laden(eintrag("moss-modul.safetensors", datei: "umgeleitet.safetensors", modus: "umleitung"))
        bericht.pruefen("Modul über eine Umleitung laden", umgeleitet.vorhanden && umgeleitet.stand == "ohne Fehler", umgeleitet.stand)
    }
}
