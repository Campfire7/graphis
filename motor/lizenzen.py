"""Schreibt THIRD_PARTY_NOTICES aus dem, was tatsächlich im App-Paket liegt.

Aufruf: python3.12 -I -B lizenzen.py MOTOR PYTHON_LIZENZEN > THIRD_PARTY_NOTICES.txt
MOTOR ist Contents/Resources/Motor, PYTHON_LIZENZEN der ausgepackte Teil (PYTHON.json, licenses/) des vollen
python-build-standalone-Archivs desselben Stands. Paketlizenzen stammen aus den dist-info-Ordnern der Wheels.
"""

import json
import sys
from email.parser import Parser
from pathlib import Path

MOTOR = Path(sys.argv[1])
PBS = Path(sys.argv[2]) / "python"
SITE = MOTOR / "python/lib/python3.12/site-packages"
LIZENZDATEIEN = ("LICEN", "COPYING", "NOTICE", "AUTHORS")
STRICH = "=" * 100

# Modelle und Module lädt die App erst auf Klick des Nutzers. Sie liegen nicht im ZIP, Herkunft und Lizenz stehen hier.
MODELLE = [
    ("MOSS-Image SFT, 8 Bit quantisiert für mflux", "mflux-community/moss-image-sft-mflux-q8",
     "c7c9f94ad909beee13d70a9358ed961e86aa35c9", "Apache-2.0",
     "Quantisierung von OpenMOSS-Team/MOSS-Image-SFT (Apache-2.0) durch mflux-community. Wird beim ersten Start "
     "nach Klick auf Laden heruntergeladen."),
    ("Turbo-Modul (8 Schritte, DMD-LoRA)", "lodestones/MOSS-Image-SFT-8-steps-dmd",
     "f95df83b5e90ae91ea412434b3f9b7f1c8c6314f", "Apache-2.0",
     "Datei lora_latest.safetensors, unverändert gespeichert als turbo-8-schritte.safetensors."),
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


def main() -> None:
    print("THIRD_PARTY_NOTICES – Graphis")
    print("Automatisch erzeugt von motor/lizenzen.py aus den Dateien im App-Paket.")
    print("Der Code der App selbst steht unter der Lizenz in LICENSE.")

    # Python mit den Bibliotheken, die python-build-standalone in den Interpreter und seine Module einbaut.
    info = json.loads((PBS / "PYTHON.json").read_text())
    abschnitt(f"Python {info['python_version']} (python-build-standalone, {info['target_triple']})")
    print(f"Lizenz: {' AND '.join(info['licenses'])}")
    texte: dict[str, set[str]] = {}
    for name, varianten in sorted(info["build_info"]["extensions"].items()):
        for variante in varianten:
            # Tk ist aus dem Paket entfernt, alle anderen Module sind eingebaut oder liegen in lib-dynload.
            if not variante.get("licenses") or name == "_tkinter":
                continue
            for pfad in variante.get("license_paths", []):
                texte.setdefault(pfad, set()).add(f"{name} ({', '.join(variante['licenses'])})")
    print("Eingebaute Bibliotheken:")
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
            lizenz = ", ".join(klassen) or (feld.splitlines()[0] if feld else "nicht angegeben")
        abschnitt(f"{meta['Name']} {meta['Version']} – {lizenz}")
        adressen = [meta.get("Home-page")] + [u.split(",", 1)[-1].strip() for u in meta.get_all("Project-URL", [])]
        if quelle := next((a for a in adressen if a), None):
            print(f"Quelle: {quelle}\n")
        dateien = sorted(p for p in dist.rglob("*") if p.is_file() and p.name.upper().startswith(LIZENZDATEIEN))
        if dateien:
            for datei in dateien:
                text = datei.read_text(errors="replace").strip()
                if "Apache License" in text and "Version 2.0" in text and not apache:
                    apache = f"{meta['Name']}: {datei.relative_to(dist)}"
                print(f"--- {datei.relative_to(dist)} ---\n{text}\n")
        elif len((meta.get("License") or "").splitlines()) > 3:
            print(f"--- Lizenztext aus den Paketangaben ---\n{meta['License'].strip()}\n")
        else:
            print(f"Das Wheel enthält keinen Lizenztext. Es gilt {lizenz}, Volltext von Apache-2.0 siehe {apache or 'oben'}.\n")

    abschnitt("Modelle und Module (nicht im App-Paket, Download nur auf Klick)")
    for name, ablage, stand, lizenz, hinweis in MODELLE:
        print(f"{name}\n  https://huggingface.co/{ablage} (Stand {stand})\n  Lizenz: {lizenz}. {hinweis}\n")
    print("Katalog der Module, alle laut Modellkarte Apache-2.0 (geprüft am 3.11.2026):")
    for ablage, stand in KATALOG:
        print(f"  https://huggingface.co/{ablage} (Stand {stand})")
    print(f"\nDer Volltext der Apache License 2.0 steht oben beim Paket {apache.split(':')[0] or 'transformers'}.")


if __name__ == "__main__":
    main()
