"""Prüft die Übersetzung der App: Jeder übersetzbare Text im Code braucht einen deutschen Eintrag, und die deutsche
Datei darf keine veralteten oder doppelten Einträge haben. Die Texte im Code liefert der Swift-Compiler selbst
(swiftc -emit-localized-strings), er kennt jede Stelle, an der ein Text übersetzt wird.
Aufruf: texte_pruefen.py STRINGSDATA-ORDNER DE-STRINGS EN-STRINGS
Gibt je Prüfung eine Zeile mit ok oder FEHLER aus. Exitstatus 0 nur, wenn alles stimmt."""
import json
import re
import subprocess
import sys
from pathlib import Path

ORDNER, DEUTSCH, ENGLISCH = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
fehler = 0


def melden(name, gut, angaben="", immer=False):
    """Angaben erscheinen nur bei einem Fehler, ausser immer ist gesetzt."""
    global fehler
    if not gut:
        fehler += 1
    zusatz = f": {angaben}" if angaben and (immer or not gut) else ""
    print(f"{'ok' if gut else 'FEHLER'} {name}{zusatz}", flush=True)


def kurz(text, laenge=90):
    text = text.replace("\n", "\\n")
    return text if len(text) <= laenge else text[:laenge - 1] + "…"


ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "'": "'", "0": "\0"}


def strings_lesen(pfad):
    """Liest eine .strings-Datei Eintrag für Eintrag. Liefert Paare in ihrer Reihenfolge und Syntaxfehler."""
    text = pfad.read_text(encoding="utf-8")
    paare, probleme, i = [], [], 0

    def leer_ueberspringen(i):
        while i < len(text):
            if text[i].isspace():
                i += 1
            elif text.startswith("/*", i):
                ende = text.find("*/", i + 2)
                if ende < 0:
                    raise ValueError("Kommentar ohne Ende")
                i = ende + 2
            elif text.startswith("//", i):
                ende = text.find("\n", i)
                i = len(text) if ende < 0 else ende + 1
            else:
                break
        return i

    def zeichenkette(i):
        if i >= len(text) or text[i] != '"':
            raise ValueError(f"Anführungszeichen erwartet bei Zeichen {i}")
        i += 1
        teile = []
        while i < len(text):
            zeichen = text[i]
            if zeichen == '"':
                return "".join(teile), i + 1
            if zeichen == "\\":
                folge = text[i + 1:i + 2]
                if folge == "U" or folge == "u":
                    teile.append(chr(int(text[i + 2:i + 6], 16)))
                    i += 6
                    continue
                if folge not in ESCAPES:
                    raise ValueError(f"unbekannte Escape-Folge \\{folge} bei Zeichen {i}")
                teile.append(ESCAPES[folge])
                i += 2
                continue
            teile.append(zeichen)
            i += 1
        raise ValueError("Zeichenkette ohne Ende")

    try:
        while True:
            i = leer_ueberspringen(i)
            if i >= len(text):
                break
            schluessel, i = zeichenkette(i)
            i = leer_ueberspringen(i)
            if text[i:i + 1] != "=":
                raise ValueError(f"= erwartet nach {kurz(schluessel)}")
            i = leer_ueberspringen(i + 1)
            wert, i = zeichenkette(i)
            i = leer_ueberspringen(i)
            if text[i:i + 1] != ";":
                raise ValueError(f"; erwartet nach {kurz(schluessel)}")
            i += 1
            paare.append((schluessel, wert))
    except (ValueError, IndexError) as grund:
        probleme.append(str(grund))
    return paare, probleme


PLATZHALTER = re.compile(r"%(?:(\d+)\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfeEgGcCsSpaAF%])")


def platzhalter(text):
    """Die Platzhalter als Stelle und Art, etwa {1: 'lld', 2: '@'}. Positionsangaben wie %2$@ zählen mit."""
    gefunden, stelle = {}, 0
    for treffer in PLATZHALTER.finditer(text):
        position, laenge, art = treffer.groups()
        if art == "%":
            continue
        stelle += 1
        nummer = int(position) if position else stelle
        gefunden.setdefault(nummer, set()).add((laenge or "") + art)
    return gefunden


# Texte im Code, mit ihren Fundstellen.
im_code = {}
andere_tabellen = []
dateien = sorted(ORDNER.glob("*.stringsdata"))
for datei in dateien:
    daten = json.loads(datei.read_text(encoding="utf-8"))
    for tabelle, eintraege in daten.get("tables", {}).items():
        for eintrag in eintraege:
            ort = f"{Path(daten.get('source', datei.stem)).name}:{eintrag['location']['startingLine']}"
            if tabelle != "Localizable":
                andere_tabellen.append(f"{tabelle} {ort}")
            im_code.setdefault(eintrag["key"], []).append(ort)
melden("Texte aus dem Code gelesen", bool(dateien) and bool(im_code), f"{len(im_code)} Texte aus {len(dateien)} Dateien", immer=True)
melden("Alle Texte in der Tabelle Localizable", not andere_tabellen, ", ".join(andere_tabellen[:5]))

# Ein Text ohne Buchstaben, etwa nur Punkte oder Platzhalter, gehört in Text(verbatim:), nicht in die Übersetzung.
ohne_buchstaben = [f"{kurz(k)!r} ({orte[0]})" for k, orte in im_code.items()
                   if not any(z.isalpha() for z in re.sub(PLATZHALTER, "", k))]
melden("Jeder übersetzte Text enthält Wörter", not ohne_buchstaben, "; ".join(ohne_buchstaben[:5]))

for pfad in (DEUTSCH, ENGLISCH):
    pruefung = subprocess.run(["/usr/bin/plutil", "-lint", str(pfad)], capture_output=True, text=True)
    melden(f"{pfad.parent.name}/{pfad.name} ist für macOS lesbar", pruefung.returncode == 0,
           (pruefung.stdout + pruefung.stderr).strip())

deutsch, probleme = strings_lesen(DEUTSCH)
melden("Deutsche Datei ohne Syntaxfehler", not probleme, "; ".join(probleme))
gesehen, doppelt = set(), []
for schluessel, _ in deutsch:
    if schluessel in gesehen:
        doppelt.append(kurz(schluessel))
    gesehen.add(schluessel)
melden("Deutsche Datei ohne doppelte Einträge", not doppelt, "; ".join(doppelt))
uebersetzt = dict(deutsch)

fehlend = [f"{kurz(k)!r} ({im_code[k][0]})" for k in sorted(im_code) if k not in uebersetzt]
melden("Jeder Text im Code hat einen deutschen Eintrag", not fehlend, f"{len(fehlend)} fehlen: " + "; ".join(fehlend))
veraltet = [kurz(k) for k in uebersetzt if k not in im_code]
melden("Kein veralteter deutscher Eintrag", not veraltet, f"{len(veraltet)} veraltet: " + "; ".join(veraltet))
leer = [kurz(k) for k, wert in uebersetzt.items() if not wert.strip()]
melden("Kein deutscher Eintrag ist leer", not leer, "; ".join(leer))
falsche_platzhalter = [f"{kurz(k)!r}" for k, wert in uebersetzt.items() if k in im_code and platzhalter(k) != platzhalter(wert)]
melden("Platzhalter stimmen überein", not falsche_platzhalter, "; ".join(falsche_platzhalter))

# Englisch ist die Sprache im Code. Die Datei macht Englisch für macOS sichtbar und darf nur gültige Einträge haben.
englisch, probleme = strings_lesen(ENGLISCH)
fremd = [kurz(k) for k, _ in englisch if k not in im_code]
melden("Englische Datei gültig und ohne fremde Einträge", not probleme and not fremd
       and len({k for k, _ in englisch}) == len(englisch), "; ".join(probleme + fremd))

print(f"{len(im_code)} Texte, {len(uebersetzt)} deutsche Einträge", flush=True)
sys.exit(1 if fehler else 0)
