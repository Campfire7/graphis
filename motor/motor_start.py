"""Startet den Rechenmotor von Graphis.

Die App ruft immer `python3.12 -I -B motor_start.py ART ...` auf, beides mit vollem Pfad im App-Paket.
-I schottet Python von PYTHON*-Variablen, Benutzerordnern und dem aktuellen Ordner ab, -B verhindert Bytecode-Dateien
im schreibgeschützten Paket. ART ist bild (Text zu Bild, wie mflux-generate-moss-image) oder referenz (mit
Referenzbild über moss_referenz.py). Alle weiteren Argumente gehen unverändert an mflux.
"""

import runpy
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in ("bild", "referenz"):
        print("Rechenmotor: Aufruf mit bild oder referenz.", file=sys.stderr)
        sys.exit(2)
    art = sys.argv.pop(1)
    if art == "referenz":
        # Unter -I liegt der Ordner dieses Skripts nicht im Importpfad, darum über den vollen Pfad daneben.
        skript = Path(__file__).with_name("moss_referenz.py")
        sys.argv[0] = str(skript)
        runpy.run_path(str(skript), run_name="__main__")
        return
    from mflux.models.moss_image.cli.moss_image_generate import main as erzeugen

    sys.argv[0] = "mflux-generate-moss-image"
    erzeugen()


if __name__ == "__main__":
    main()
