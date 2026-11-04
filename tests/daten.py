"""Legt kleine Testdateien für den Testserver und das passende Manifest an.
Aufruf: daten.py DATENORDNER PORT MANIFEST. Die Dateien sind Zufallsdaten, die Module kleine erfundene safetensors.
Dazu kommen Antworten zur neusten Version wie von GitHub."""
import hashlib, json, os, struct, sys
from pathlib import Path

daten = Path(sys.argv[1]); port = sys.argv[2]; manifest = Path(sys.argv[3])
dateien = [("modell", "README.md", 3000), ("modell", "mflux_model.json", 500), ("modell", "text_encoder/0.safetensors", 1_500_000),
           ("modell", "transformer/0.safetensors", 3_000_000), ("modell", "vae/0.safetensors", 800_000),
           ("modul", "turbo-8-schritte.safetensors", 1_000_000)]


def adresse(pfad):
    return f"http://127.0.0.1:{port}/ok/{pfad}"


def safetensors(namen):
    """Kopf mit Lage jedes Tensors, danach die Gewichte. Jeder Tensor hat 512 Bytes."""
    kopf, stelle = {}, 0
    for name in namen:
        kopf[name] = {"dtype": "F16", "shape": [4, 64], "data_offsets": [stelle, stelle + 512]}
        stelle += 512
    kopf["__metadata__"] = {"format": "pt"}
    text = json.dumps(kopf, sort_keys=True).encode()
    return struct.pack("<Q", len(text)) + text + os.urandom(stelle)


eintraege = []
for ziel, pfad, bytes_ in dateien:
    datei = daten / ziel / pfad
    datei.parent.mkdir(parents=True, exist_ok=True)
    if not datei.exists():
        datei.write_bytes(os.urandom(bytes_))
    inhalt = datei.read_bytes()
    eintraege.append({"ziel": ziel, "pfad": pfad, "bytes": len(inhalt), "sha256": hashlib.sha256(inhalt).hexdigest(),
                      "adresse": adresse(f"{ziel}/{pfad}")})

# Module zum Laden wie aus dem Katalog: eines mit Ebenen wie bei MOSS, eines mit Ebenen eines anderen Modells.
module = []
for name, namen in [("moss-modul.safetensors", [f"diffusion_model.layers.{i}.proj.{e}.lora_{t}.weight"
                                                 for i in range(2) for e in "qk" for t in "AB"]),
                    ("fremdes-modul.safetensors", [f"diffusion_model.layers.0.text_fusion.{e}.lora_{t}.weight"
                                                    for e in "qk" for t in "AB"])]:
    datei = daten / "extra" / name
    datei.parent.mkdir(parents=True, exist_ok=True)
    if not datei.exists():
        datei.write_bytes(safetensors(namen))
    inhalt = datei.read_bytes()
    module.append({"name": name, "bytes": len(inhalt), "sha256": hashlib.sha256(inhalt).hexdigest(),
                   "adresse": adresse(f"extra/{name}")})

# Antworten wie von GitHub zur neusten Version, gute und unbrauchbare.
seite = "https://github.com/Campfire7/graphis/releases/tag/"
versionen = {
    "neuer.json": {"tag_name": "v1.1", "html_url": seite + "v1.1", "draft": False, "prerelease": False},
    "gleich.json": {"tag_name": "v1.0", "html_url": seite + "v1.0", "draft": False, "prerelease": False},
    "aelter.json": {"tag_name": "v0.9", "html_url": seite + "v0.9"},
    "vorab.json": {"tag_name": "v2.0", "html_url": seite + "v2.0", "prerelease": True},
    "entwurf.json": {"tag_name": "v2.0", "html_url": seite + "v2.0", "draft": True},
    "muell.json": {"tag_name": "latest", "html_url": seite + "latest"},
    "ohne-seite.json": {"tag_name": "v2.0"},
    "keinobjekt.json": ["v2.0", seite + "v2.0"],
    "fremd.json": {"tag_name": "v2.0", "html_url": "https://evil.example/Campfire7/graphis/releases/tag/v2.0"},
    "fremdes-projekt.json": {"tag_name": "v2.0", "html_url": "https://github.com/Campfire7/anderes/releases/tag/v2.0"},
    "unsicher.json": {"tag_name": "v2.0", "html_url": "http://github.com/Campfire7/graphis/releases/tag/v2.0"},
    "ausbruch.json": {"tag_name": "v2.0", "html_url": "https://github.com/Campfire7/graphis/../../evil/graphis"},
    "anmeldung.json": {"tag_name": "v2.0", "html_url": "https://name:wort@github.com/Campfire7/graphis/releases/tag/v2.0"},
    "gross.json": {"tag_name": "v2.0", "html_url": seite + "v2.0", "fuell": "x" * 1_200_000},
}
(daten / "versionen").mkdir(parents=True, exist_ok=True)
for name, inhalt in versionen.items():
    (daten / "versionen" / name).write_text(json.dumps(inhalt))
(daten / "versionen" / "kaputt.json").write_text('{"tag_name": "v2.0", "html_url": "' + seite)

manifest.write_text(json.dumps({"kennung": "testmanifest-1", "dateien": eintraege, "module": module}, indent=1))
print(manifest)
