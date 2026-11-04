"""Schreibt THIRD_PARTY_NOTICES aus dem, was tatsächlich im App-Paket liegt.

Aufruf: python3.12 -I -B lizenzen.py MOTOR PYTHON_LIZENZEN > THIRD_PARTY_NOTICES.txt
MOTOR ist Contents/Resources/Motor, PYTHON_LIZENZEN der ausgepackte Teil (PYTHON.json, licenses/) des vollen
python-build-standalone-Archivs desselben Stands. Paketlizenzen stammen aus den dist-info-Ordnern der Wheels.
Die Bibliotheken, die in die Rust-Teile der Pakete eingebaut sind, stehen in rust-lizenzen.json. Passt die Datei
nicht mehr zu den Programmdateien im Motor, bricht das Skript ab, bevor es etwas schreibt. Erneuern mit
rust_lizenzen.py, siehe README unter Bauen.
"""

import csv
import json
import sys
from email.parser import Parser
from pathlib import Path

MOTOR = Path(sys.argv[1])
PBS = Path(sys.argv[2]) / "python"
SITE = MOTOR / "python/lib/python3.12/site-packages"
RUST = Path(__file__).with_name("rust-lizenzen.json")
LIZENZDATEIEN = ("LICEN", "COPYING", "NOTICE", "AUTHORS")
STRICH = "=" * 100

# Modelle und Module lädt die App erst auf Klick des Nutzers. Sie liegen nicht im ZIP, Herkunft und Lizenz stehen hier.
MODELLE = [
    ("MOSS-Image SFT, 8-bit quantized for mflux", "mflux-community/moss-image-sft-mflux-q8",
     "c7c9f94ad909beee13d70a9358ed961e86aa35c9", "Apache-2.0",
     "Quantization of OpenMOSS-Team/MOSS-Image-SFT (Apache-2.0) by mflux-community. Downloaded on first start, "
     "only after a click."),
    ("Turbo module (8 steps, DMD LoRA)", "lodestones/MOSS-Image-SFT-8-steps-dmd",
     "f95df83b5e90ae91ea412434b3f9b7f1c8c6314f", "Apache-2.0",
     "File lora_latest.safetensors, saved unchanged as turbo-8-schritte.safetensors."),
]
KATALOG = [
    ("Danrisi/lenovo_moss", "993996c9bd62a773c54f8c36b3e8da3d15dacf78"),
    ("Danrisi/canon_moss", "d8533df2238d42b690d362a67035e86ef4d59f3f"),
    ("Danrisi/grainscape_moss", "ed91a40844f70ba68b531c580d7a87e48372fbf9"),
    ("axiomofmind/Moss-image-beauty-lora", "aedbb91f12ebce6d30e73ca76cccf81feff4b414"),
    ("aoleg/MOSS-Sharpness-Slider", "5a98472a70bbb10cec78a79274df5f86f403493d"),
    ("Kandoo/MOSS-Image-Impressionism-LoRA", "5941252a5095f9be551b708419f7df2078d57864"),
    ("axiomofmind/Moss-image-gouache-lora", "63f1d3fa77623c5198714f43f33be30632b9cb44"),
    ("axiomofmind/Moss-image-psychedelic-lora", "3482e5226f462b7c14319cc79167ed6d894ded71"),
    ("axiomofmind/Moss-image-anime-lora", "38fa56fa567b70412828ac67c050a4c2c1a5c40a"),
    ("axiomofmind/Moss-image-animated-lora", "b2ba71a4b0e773209603d13b8fc603d4b0ea319b"),
    ("nynxz/MOSS-Image", "59d3547a788ca6ebc4f5005a82d461904628df26"),
]


def abschnitt(titel: str) -> None:
    print(f"\n{STRICH}\n{titel}\n{STRICH}\n")


def rust_pakete() -> dict[str, tuple[str, Path, dict[Path, str]]]:
    """Wheels mit Programmteilen aus Rust: Name -> (Version, dist-info, Programmdatei -> Prüfsumme laut RECORD).
    Die Prüfsumme aus RECORD stammt aus dem Wheel und bleibt gleich, wenn bauen.sh die Datei signiert.
    Gleich wie in rust_lizenzen.py."""
    pakete = {}
    for dist in sorted(SITE.glob("*.dist-info")):
        meta = Parser().parsestr((dist / "METADATA").read_text(errors="replace"))
        zeilen = sorted(z for z in csv.reader((dist / "RECORD").read_text().splitlines()) if z)
        rust = {SITE / z[0]: z[1] for z in zeilen if Path(z[0]).suffix in (".so", ".dylib")
                and (SITE / z[0]).is_file() and b"/rustc/" in (SITE / z[0]).read_bytes()}
        if rust:
            pakete[meta["Name"]] = (meta["Version"], dist, rust)
    return pakete


def stueckliste(dist: Path) -> set[str]:
    """Bibliotheken von crates.io laut Stückliste im Wheel, ohne die eigenen des Pakets. Leer ohne Stückliste."""
    return {f"{teil['name']} {teil['version']}" for liste in sorted(dist.glob("sboms/*.json"))
            for teil in json.loads(liste.read_text()).get("components", [])
            if "download_url=file://" not in teil.get("purl", "")}


def rust_daten() -> dict:
    """rust-lizenzen.json, aber nur, wenn sie zu den Rust-Programmdateien (SHA-256 laut RECORD) und zur Stückliste
    im Wheel passt und für jede Bibliothek einen Text hat."""
    daten = json.loads(RUST.read_text())
    gefunden = rust_pakete()
    falsch = [f"{name} {version}" for name, (version, dist, programme) in sorted(gefunden.items())
              if name not in daten["pakete"] or daten["pakete"][name]["version"] != version
              or daten["pakete"][name]["programme"] != {str(p.relative_to(SITE)): s for p, s in programme.items()}
              or not stueckliste(dist) <= set(daten["pakete"][name]["crates"])]
    falsch += [f"{name} (nicht mehr im Motor)" for name in sorted(daten["pakete"]) if name not in gefunden]
    falsch += [crate for paket in daten["pakete"].values() for crate in paket["crates"]
               if not daten["crates"].get(crate, {}).get("texte")]
    if falsch:
        sys.exit(f"motor/rust-lizenzen.json passt nicht zu {', '.join(falsch)}. Neu erzeugen, siehe README unter Bauen.")
    return daten


def rust_bibliotheken(daten: dict) -> None:
    pakete = sorted(daten["pakete"].items(), key=lambda p: p[0].lower())
    abschnitt("Rust libraries in " + ", ".join(f"{name} {paket['version']}" for name, paket in pakete))
    print("These packages contain Rust code with libraries from crates.io and the Rust standard library statically")
    print("linked in. The list comes from motor/rust-lizenzen.json. Identical license texts appear only once below.\n")
    for name, paket in pakete:
        print(f"{name} {paket['version']} ({len(paket['crates'])} libraries, from {paket['quelle']}):")
        for crate in paket["crates"]:
            print(f"  {crate} – {daten['crates'][crate]['lizenz']}")
        print()
    # Jeder Text einmal, mit allen Dateien, in denen er vorkommt.
    fundorte: dict[str, list[str]] = {}
    for crate, info in sorted(daten["crates"].items()):
        for datei, schluessel in sorted(info["texte"].items()):
            fundorte.setdefault(schluessel, []).append(f"{crate}: {datei}")
    for nummer, (schluessel, orte) in enumerate(sorted(fundorte.items(), key=lambda e: e[1][0]), 1):
        abschnitt(f"Rust license text {nummer} of {len(fundorte)}")
        print("Found in:\n" + "\n".join(f"  {ort}" for ort in orte) + "\n")
        print(daten["texte"][schluessel])


def main() -> None:
    rust = rust_daten()
    print("THIRD_PARTY_NOTICES – Graphis")
    print("Generated automatically by motor/lizenzen.py from the files in the app bundle.")
    print("The app's own code is under the license in LICENSE.")

    # Python mit den Bibliotheken, die python-build-standalone in den Interpreter und seine Module einbaut.
    info = json.loads((PBS / "PYTHON.json").read_text())
    abschnitt(f"Python {info['python_version']} (python-build-standalone, {info['target_triple']})")
    print(f"License: {' AND '.join(info['licenses'])}")
    texte: dict[str, set[str]] = {}
    for name, varianten in sorted(info["build_info"]["extensions"].items()):
        for variante in varianten:
            # Tk ist aus dem Paket entfernt, alle anderen Module sind eingebaut oder liegen in lib-dynload.
            if not variante.get("licenses") or name == "_tkinter":
                continue
            for pfad in variante.get("license_paths", []):
                texte.setdefault(pfad, set()).add(f"{name} ({', '.join(variante['licenses'])})")
    print("Built-in libraries:")
    for pfad, module in sorted(texte.items()):
        print(f"  {Path(pfad).name}: {', '.join(sorted(module))}")
    for pfad in [info["license_path"], *sorted(texte)]:
        abschnitt(f"Python: {Path(pfad).name}")
        print((PBS / pfad).read_text(errors="replace").strip())

    # Jedes Wheel mit Version, Lizenzangabe und den Lizenztexten aus seinem dist-info-Ordner.
    apache = ""
    for dist in sorted(SITE.glob("*.dist-info"), key=lambda p: p.name.lower()):
        meta = Parser().parsestr((dist / "METADATA").read_text(errors="replace"))
        lizenz = meta.get("License-Expression") or ""
        if not lizenz:
            klassen = [k.split("::")[-1].strip() for k in meta.get_all("Classifier", []) if k.startswith("License ::")]
            feld = (meta.get("License") or "").strip()
            lizenz = ", ".join(klassen) or (feld.splitlines()[0] if feld else "not specified")
        abschnitt(f"{meta['Name']} {meta['Version']} – {lizenz}")
        adressen = [meta.get("Home-page")] + [u.split(",", 1)[-1].strip() for u in meta.get_all("Project-URL", [])]
        if quelle := next((a for a in adressen if a), None):
            print(f"Source: {quelle}\n")
        dateien = sorted(p for p in dist.rglob("*") if p.is_file() and p.name.upper().startswith(LIZENZDATEIEN))
        if dateien:
            for datei in dateien:
                text = datei.read_text(errors="replace").strip()
                if "Apache License" in text and "Version 2.0" in text and not apache:
                    apache = f"{meta['Name']}: {datei.relative_to(dist)}"
                print(f"--- {datei.relative_to(dist)} ---\n{text}\n")
        elif len((meta.get("License") or "").splitlines()) > 3:
            print(f"--- License text from the package metadata ---\n{meta['License'].strip()}\n")
        else:
            print(f"The wheel contains no license text. {lizenz} applies; for the full Apache-2.0 text see {apache or 'above'}.\n")

    rust_bibliotheken(rust)

    abschnitt("Models and modules (not in the app bundle, downloaded only on click)")
    for name, ablage, stand, lizenz, hinweis in MODELLE:
        print(f"{name}\n  https://huggingface.co/{ablage} (revision {stand})\n  License: {lizenz}. {hinweis}\n")
    print("Module catalog, all Apache-2.0 according to their model cards (checked on 2026-11-03):")
    for ablage, stand in KATALOG:
        print(f"  https://huggingface.co/{ablage} (revision {stand})")
    print(f"\nThe full text of the Apache License 2.0 appears above with the package {apache.split(':')[0] or 'transformers'}.")


if __name__ == "__main__":
    main()
