"""Findet Mach-O-Dateien am Dateiformat, nicht an der Endung, und liest ihre Angaben.

  macho.py liste ORDNER     alle Mach-O-Dateien, tiefste zuerst (Reihenfolge fürs Signieren von innen nach aussen)
  macho.py minos ORDNER     die höchste verlangte macOS-Version aller Dateien
  macho.py pruefen ORDNER   Bericht: Art, minos, Abhängigkeiten ausserhalb des Systems und des Pakets
Läuft mit dem Python aus dem Motor: python3.12 -I -B macho.py ...
"""

import struct
import sys
from pathlib import Path

MAGIE_64 = (0xFEEDFACF, 0xCFFAEDFE)
MAGIE_32 = (0xFEEDFACE, 0xCEFAEDFE)
MAGIE_FAT = (0xCAFEBABE, 0xBEBAFECA, 0xCAFEBABF, 0xBFBAFECA)
ARTEN = {1: "Objektdatei", 2: "Programm", 6: "Bibliothek", 8: "Bündel"}
LADEN = {0xC, 0x18 | 0x80000000, 0x1F | 0x80000000, 0x20, 0x23 | 0x80000000}


def ist_macho(pfad: Path) -> bool:
    if pfad.is_symlink() or not pfad.is_file():
        return False
    with pfad.open("rb") as datei:
        kopf = datei.read(8)
    if len(kopf) < 8:
        return False
    magie, anzahl = struct.unpack(">II", kopf)
    # Java-Klassen beginnen auch mit CAFEBABE, haben dort aber eine Versionsnummer statt weniger Architekturen.
    return magie in MAGIE_64 + MAGIE_32 or (magie in MAGIE_FAT and 0 < anzahl < 10)


def scheiben(daten: bytes) -> list[int]:
    """Anfang jeder Architektur, bei Universal-Dateien mehrere."""
    magie = struct.unpack(">I", daten[:4])[0]
    if magie in MAGIE_FAT:
        anzahl = struct.unpack(">I", daten[4:8])[0]
        breit = magie in (0xCAFEBABF, 0xBFBAFECA)
        schritt = 32 if breit else 20
        return [struct.unpack(">Q" if breit else ">I", daten[8 + i * schritt + 8 : 8 + i * schritt + (16 if breit else 12)])[0]
                for i in range(anzahl)]
    return [0]


def version(wert: int) -> tuple[int, int, int]:
    return (wert >> 16, (wert >> 8) & 0xFF, wert & 0xFF)


def lesen(pfad: Path) -> dict:
    daten = pfad.read_bytes()
    ergebnis = {"art": None, "minos": None, "abhaengig": []}
    for anfang in scheiben(daten):
        magie = struct.unpack("<I", daten[anfang : anfang + 4])[0]
        ende = "<" if magie in (0xFEEDFACF, 0xFEEDFACE) else ">"
        art = struct.unpack(ende + "I", daten[anfang + 12 : anfang + 16])[0]
        anzahl = struct.unpack(ende + "I", daten[anfang + 16 : anfang + 20])[0]
        stelle = anfang + (32 if magie in (0xFEEDFACF, 0xCFFAEDFE) else 28)
        ergebnis["art"] = ARTEN.get(art, f"Art {art}")
        for _ in range(anzahl):
            befehl, groesse = struct.unpack(ende + "II", daten[stelle : stelle + 8])
            if befehl == 0x32:  # LC_BUILD_VERSION
                minos = version(struct.unpack(ende + "I", daten[stelle + 12 : stelle + 16])[0])
                ergebnis["minos"] = max(ergebnis["minos"] or minos, minos)
            elif befehl == 0x24:  # LC_VERSION_MIN_MACOSX
                minos = version(struct.unpack(ende + "I", daten[stelle + 8 : stelle + 12])[0])
                ergebnis["minos"] = max(ergebnis["minos"] or minos, minos)
            elif befehl in LADEN:
                versatz = struct.unpack(ende + "I", daten[stelle + 8 : stelle + 12])[0]
                name = daten[stelle + versatz : stelle + groesse].split(b"\0")[0].decode()
                ergebnis["abhaengig"].append(name)
            stelle += groesse
    return ergebnis


def alle(ordner: Path) -> list[Path]:
    funde = [p for p in ordner.rglob("*") if ist_macho(p)]
    # Tiefste zuerst, damit beim Signieren nichts Inneres nach dem Äusseren kommt.
    return sorted(funde, key=lambda p: (-len(p.parts), str(p)))


def main() -> None:
    befehl, ordner = sys.argv[1], Path(sys.argv[2])
    dateien = alle(ordner)
    if befehl == "liste":
        print("\n".join(map(str, dateien)))
    elif befehl == "minos":
        hoechste = max(lesen(p)["minos"] or (0, 0, 0) for p in dateien)
        print(f"{hoechste[0]}.{hoechste[1]}" + (f".{hoechste[2]}" if hoechste[2] else ""))
    elif befehl == "pruefen":
        fehler = 0
        for pfad in dateien:
            info = lesen(pfad)
            fremd = [a for a in info["abhaengig"]
                     if not a.startswith(("/usr/lib/", "/System/Library/", "@rpath/", "@loader_path/", "@executable_path/"))]
            if info["art"] == "Objektdatei" or fremd:
                fehler += 1
            minos = ".".join(map(str, info["minos"])) if info["minos"] else "-"
            print(f"{'FEHLER' if info['art'] == 'Objektdatei' or fremd else 'ok'} {info['art']} minos {minos} "
                  f"{pfad.relative_to(ordner)}{' fremd: ' + ', '.join(fremd) if fremd else ''}")
        print(f"{len(dateien)} Mach-O-Dateien, {fehler} mit Fehlern")
        sys.exit(1 if fehler else 0)


if __name__ == "__main__":
    main()
