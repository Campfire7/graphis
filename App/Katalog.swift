import Foundation

/// Ein Modul, das die App auf Wunsch von Hugging Face herunterladen kann.
struct Katalogeintrag: Identifiable, Sendable {
    enum Kategorie: String, CaseIterable, Identifiable, Sendable {
        case foto = "Foto und Realismus"
        case licht = "Licht und Details"
        case kunst = "Malerei und Illustration"
        case werkzeug = "Werkzeuge"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .foto: "camera"
            case .licht: "sun.max"
            case .kunst: "paintpalette"
            case .werkzeug: "wrench.adjustable"
            }
        }
    }

    /// Name auf dem Mac, nie der Name, den der Server nennt.
    let datei: String
    let name: String
    let beschreibung: String
    let kategorie: Kategorie
    let download: URL
    let seite: URL
    let sha256: String
    let bytes: Int64
    var staerke = 1.0
    var ausloeser: String? = nil
    var hinweis: String? = nil
    /// Lizenz laut Modellkarte am festen Stand. Der Katalog nimmt nur Module mit geprüfter Lizenz auf.
    var lizenz = "Apache 2.0"

    var id: String { datei }
    var groesse: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

/// Von Hand ausgewählt, mit festem Stand und Fingerabdruck. Die App fragt keine Liste im Netz ab.
/// Aufgenommen sind MOSS-Module für Stil, Licht und Bildqualität von Hugging Face, alle laut Modellkarte unter
/// Apache 2.0 (geprüft am 3.11.2026). Verschmolzene Ebenen teilt die App beim Laden auf.
enum Katalog {
    static func eintrag(_ datei: String) -> Katalogeintrag? {
        alle.first { $0.datei == datei }
    }

    private static func huggingFace(
        _ datei: String, _ name: String, _ beschreibung: String, _ kategorie: Katalogeintrag.Kategorie,
        ablage: String, stand: String, pfad: String, sha256: String, bytes: Int64,
        staerke: Double = 1, ausloeser: String? = nil, hinweis: String? = nil
    ) -> Katalogeintrag {
        Katalogeintrag(
            datei: datei, name: name, beschreibung: beschreibung, kategorie: kategorie,
            download: URL(string: "https://huggingface.co/\(ablage)/resolve/\(stand)/\(pfad)")!,
            seite: URL(string: "https://huggingface.co/\(ablage)")!,
            sha256: sha256, bytes: bytes, staerke: staerke, ausloeser: ausloeser, hinweis: hinweis)
    }

    static let alle: [Katalogeintrag] = [
        huggingFace("lenovo_moss.safetensors", "Altes Handy",
                    "Billiges Handyfoto um 2010: wenig Auflösung, ungestellt, echte Alltagsstimmung.",
                    .foto, ablage: "Danrisi/lenovo_moss",
                    stand: "993996c9bd62a773c54f8c36b3e8da3d15dacf78", pfad: "lenovo_moss.safetensors",
                    sha256: "f28ab12e33e60146c8740a86730385cf5ba488e9f6eda50b14383d6ddbf300fb", bytes: 64_527_960,
                    staerke: 0.7, ausloeser: "l3n0v0"),
        huggingFace("canon_moss.safetensors", "Spiegelreflex",
                    "Amateurfoto aus der Spiegelreflexkamera, natürlich und leicht unterbelichtet.",
                    .foto, ablage: "Danrisi/canon_moss",
                    stand: "d8533df2238d42b690d362a67035e86ef4d59f3f", pfad: "canon_moss.safetensors",
                    sha256: "49804d73f98dd110216efbbb82d769ed4872f8bdd28bc2e256ca76bae06628ef", bytes: 64_527_960,
                    staerke: 0.7, ausloeser: "c2n0n"),
        huggingFace("grainscape_moss.safetensors", "Starkes Filmkorn",
                    "Analoger Film mit kräftigem Korn und dunkler Stimmung.",
                    .foto, ablage: "Danrisi/grainscape_moss",
                    stand: "ed91a40844f70ba68b531c580d7a87e48372fbf9", pfad: "grainscape_moss.safetensors",
                    sha256: "94461edf19cd7f0b70120e8bde98a68738c857c9cceebf3802089addf91a41a5", bytes: 64_527_968,
                    staerke: 0.7),
        huggingFace("beauty.safetensors", "Beauty",
                    "Porträts mit Beauty-Look, gepflegte Haut und Haare. Auf erwachsene Frauen trainiert.",
                    .foto, ablage: "axiomofmind/Moss-image-beauty-lora",
                    stand: "aedbb91f12ebce6d30e73ca76cccf81feff4b414", pfad: "pytorch_lora_weights.safetensors",
                    sha256: "f40ee2bd2b915266a0b70697590edb21885664727b48f90f0014e6de43d7dcdc", bytes: 74_377_208,
                    ausloeser: "moss_beauty_style"),

        huggingFace("moss-sharp-v1_000000400.safetensors", "Schärfe", "Macht das Bild schärfer.",
                    .licht, ablage: "aoleg/MOSS-Sharpness-Slider",
                    stand: "5a98472a70bbb10cec78a79274df5f86f403493d", pfad: "moss-sharp-v1_000000400.safetensors",
                    sha256: "81beddc3e50e045bae4316b7188124a1b73bbd56b6659b971567a7800b2cb04b", bytes: 18_200_000,
                    hinweis: "Wirkt vor allem in der Stufe Beste, mit Turbo kaum."),

        huggingFace("impressionismus.safetensors", "Impressionismus", "Malerischer Ölbild-Stil.",
                    .kunst, ablage: "Kandoo/MOSS-Image-Impressionism-LoRA",
                    stand: "5941252a5095f9be551b708419f7df2078d57864", pfad: "moss-image-impressionism-lora.safetensors",
                    sha256: "c8cff3df16db40b1f17daa195c2d18256085d728394533c0a6c958d43b08ea17", bytes: 74_475_088,
                    hinweis: "Bei Fotomotiven wirkt oft eine Stärke von 1,4 bis 1,6 besser."),
        huggingFace("gouache.safetensors", "Gouache", "Farbenfrohe Illustration im Stil alter Gouache-Bilder.",
                    .kunst, ablage: "axiomofmind/Moss-image-gouache-lora",
                    stand: "63f1d3fa77623c5198714f43f33be30632b9cb44", pfad: "pytorch_lora_weights.safetensors",
                    sha256: "9ad483c8b68addb8afe7770864193f48cf35b0efc74d00ab0b9336daeef5b4e9", bytes: 74_400_000,
                    ausloeser: "moss_vgouache_style"),
        huggingFace("psychedelic.safetensors", "Psychedelic Pop", "Bunte Plakatkunst im psychedelischen Stil.",
                    .kunst, ablage: "axiomofmind/Moss-image-psychedelic-lora",
                    stand: "3482e5226f462b7c14319cc79167ed6d894ded71", pfad: "pytorch_lora_weights.safetensors",
                    sha256: "a25912672b0f1bac018ba68d1c855c2151979b35216540db92680a5295c9622d", bytes: 74_400_000,
                    ausloeser: "moss_psychpop_style"),
        huggingFace("anime.safetensors", "Seinen-Anime", "Actiongeladener Anime mit filmischem Licht und erwachsenen Figuren.",
                    .kunst, ablage: "axiomofmind/Moss-image-anime-lora",
                    stand: "38fa56fa567b70412828ac67c050a4c2c1a5c40a", pfad: "pytorch_lora_weights.safetensors",
                    sha256: "e4705ef662dcd305130dec5e888b46122d773d278e34129d4fbe7b3d0a31c09c", bytes: 74_400_000),
        huggingFace("animationsfilm.safetensors", "Animationsfilm", "Gepflegter 3D-Trickfilm-Look für Menschen, Tiere und Szenen.",
                    .kunst, ablage: "axiomofmind/Moss-image-animated-lora",
                    stand: "b2ba71a4b0e773209603d13b8fc603d4b0ea319b", pfad: "pytorch_lora_weights.safetensors",
                    sha256: "c1b89db0effba7f994be59b7291166e270b63cc00383da204dc469e0f2964db9", bytes: 74_400_000,
                    ausloeser: "moss_ac_style"),

        huggingFace(Modul.streifenDatei, "Streifen-Fix",
                    "Entfernt feine Farbstreifen in ruhigen Flächen wie Himmel oder Wänden.",
                    .werkzeug, ablage: "nynxz/MOSS-Image",
                    stand: "59d3547a788ca6ebc4f5005a82d461904628df26", pfad: "loras/moss_sft_destripe_top64_bf16.safetensors",
                    sha256: "fcd0d025f6a62dfe3171ab11fe9b3119eac735e22b94913c4efe45d8c69c2da9", bytes: 1_900_586)
    ]
}
