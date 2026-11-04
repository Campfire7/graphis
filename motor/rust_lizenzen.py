"""Hält fest, welche Rust-Bibliotheken in den Paketen des Motors stecken, samt ihren Lizenztexten.

Aufruf (braucht Internet, curl und cargo): /usr/bin/python3 -I -B rust_lizenzen.py MOTOR LAGER AUSGABE
MOTOR ist ein frisch zusammengestellter Motor (siehe README), LAGER der Ordner für Downloads des Baus
(.build/downloads), AUSGABE die Datei motor/rust-lizenzen.json. Sie wird erst am Schluss ersetzt, ein Fehler lässt
die alte stehen. Neu erzeugen, sobald sich ein Paket mit Rust-Teil ändert, sonst bricht lizenzen.py den Bau ab.
Welche Bibliotheken eingebaut sind, steht in der Stückliste im Wheel (CycloneDX). Fehlt sie, gilt Cargo.lock aus dem
Quellpaket auf PyPI, aufgelöst für Apple Silicon. Dazu kommen die Rust-Standardbibliothek und deren Bibliotheken,
abgelesen aus der Programmdatei. Jede Bibliothek, deren Pfad in der Programmdatei steht, muss in der Liste sein.
Jede kommt von crates.io und wird mit der SHA-256 aus dem Index von crates.io geprüft. Die Ausgabe hat keinen
Zeitstempel, gleiche Pakete ergeben dieselbe Datei.
"""

import csv
import hashlib
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile
from concurrent.futures import ThreadPoolExecutor
from email.parser import Parser
from pathlib import Path

MOTOR = Path(sys.argv[1])
LAGER = Path(sys.argv[2])
AUSGABE = Path(sys.argv[3])
SITE = MOTOR / "python/lib/python3.12/site-packages"
ZIEL = "aarch64-apple-darwin"
CRATES_IO = "registry+https://github.com/rust-lang/crates.io-index"
LIZENZDATEIEN = ("LICEN", "COPYING", "COPYRIGHT", "NOTICE", "UNLICENSE", "THIRD_PARTY", "THIRD-PARTY")
# Lizenzdateien in diesen Ordnern gehören zu Tests, Beispielen oder Werkzeugen für den Bau, nicht zum eingebauten Code.
NICHT_EINGEBAUT = {"test", "tests", "testdata", "fixtures", "examples", "benches", "doc", "docs", "perl"}
QUELLCODE = {".rs", ".pm", ".py", ".c", ".h"}
# Bibliotheken ohne Lizenzdatei im Paket: Die Texte kommen aus ihrem Repository, zu festem Stand und mit SHA-256.
AUS_REPOSITORY = {
    "https://github.com/madsmtm/objc2": ("8a5abacd90d5403fc0463459a35826f892b9142e", {
        "LICENSE.md": "e489d07e5496be274efcbeaa31ce7267779e3fe3fbf2d6195d74750d7e9ac288",
        "LICENSE-MIT.txt": "f6a2e783669a0dd7a2c3b8a4f76db40ae49033e66e1bdc30f3aa25fe5577b070",
        "LICENSE-APACHE.txt": "0c9a5f6fe28e27015e12506ffe58c9e007cead169af9670ec15c1df0d14e4f2a",
        "LICENSE-ZLIB.txt": "fced3e7fedc235fa83ed0108b0df74d86b435d06436356f46917a903cbadd80a"}),
    "https://github.com/knurling-rs/defmt": ("d4e04b65a7b89d5f394397f25e259ba500ca98b6", {
        "LICENSE-MIT": "2710a622a896bba67356913d4d0492cab5465f61b2ecce6d880aeb483834fb50",
        "LICENSE-APACHE": "8173d5c29b4f956d532781d2b86e4e30f83e6b7878dce18c919451d6ba707c90"}),
}
# Die Standardbibliothek steht unter den Lizenzen des Rust-Projekts, zum Stand des Compilers, der das Paket gebaut hat.
RUST_PROJEKT = "https://github.com/rust-lang/rust"
RUST_DATEIEN = ("COPYRIGHT", "LICENSE-APACHE", "LICENSE-MIT")
VERSION = rb"(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]*)?)"
# Pfade von Bibliotheken, die beim Bau in die Programmdatei geraten: von crates.io und aus der Standardbibliothek.
PFAD_CRATE = re.compile(rb"(?:index\.crates\.io|github\.com)-[0-9a-f]+/([A-Za-z0-9_-]+)-" + VERSION + rb"/")
PFAD_STD = re.compile(rb"/rust/deps/([A-Za-z0-9_-]+)-" + VERSION + rb"/")


def rust_pakete() -> dict[str, tuple[str, Path, dict[Path, str]]]:
    """Wheels mit Programmteilen aus Rust: Name -> (Version, dist-info, Programmdatei -> Prüfsumme laut RECORD).
    Die Prüfsumme aus RECORD stammt aus dem Wheel und bleibt gleich, wenn bauen.sh die Datei signiert.
    Gleich wie in lizenzen.py."""
    pakete = {}
    for dist in sorted(SITE.glob("*.dist-info")):
        meta = Parser().parsestr((dist / "METADATA").read_text(errors="replace"))
        zeilen = sorted(z for z in csv.reader((dist / "RECORD").read_text().splitlines()) if z)
        rust = {SITE / z[0]: z[1] for z in zeilen if Path(z[0]).suffix in (".so", ".dylib")
                and (SITE / z[0]).is_file() and b"/rustc/" in (SITE / z[0]).read_bytes()}
        if rust:
            pakete[meta["Name"]] = (meta["Version"], dist, rust)
    return pakete


def lizenz(teil: dict) -> str:
    angaben = [a.get("expression") or a.get("license", {}).get("id") or a.get("license", {}).get("name", "")
               for a in teil.get("licenses", [])]
    return " AND ".join(a for a in angaben if a) or "nicht angegeben"


def stueckliste(dist: Path):
    """Bibliotheken von crates.io laut Stückliste im Wheel, ohne die eigenen des Pakets. None ohne Stückliste."""
    listen = sorted(dist.glob("sboms/*.json"))
    if not listen:
        return None
    crates = {}
    for liste in listen:
        for teil in json.loads(liste.read_text()).get("components", []):
            purl = teil.get("purl", "")
            if "download_url=file://" in purl:
                continue
            if not re.fullmatch(r"pkg:cargo/[^@?]+@[^?]+", purl):
                sys.exit(f"Unbekannte Herkunft in {liste.name}: {purl}")
            crates[f"{teil['name']} {teil['version']}"] = lizenz(teil)
    return crates


def holen(adresse: str) -> str:
    return subprocess.run(["curl", "-fsSL", "--retry", "3", "--retry-all-errors", adresse], stdout=subprocess.PIPE, check=True,
                          text=True).stdout


def pruefsumme(datei: Path) -> str:
    return hashlib.sha256(datei.read_bytes()).hexdigest()


def laden(datei: Path, adresse: str, sha256: str = "") -> Path:
    """Lädt in den LAGER und prüft die SHA-256. Ohne SHA-256 nur, wenn die Adresse einen festen Stand enthält."""
    if not (datei.is_file() and (not sha256 or pruefsumme(datei) == sha256)):
        datei.parent.mkdir(parents=True, exist_ok=True)
        griff, teil = tempfile.mkstemp(dir=datei.parent, prefix=f"{datei.name}.", suffix=".part")
        os.close(griff)
        subprocess.run(["curl", "-fsSL", "--retry", "3", "--retry-all-errors", "-o", teil, adresse], check=True)
        if sha256 and pruefsumme(Path(teil)) != sha256:
            os.unlink(teil)
            sys.exit(f"Falsche Prüfsumme: {adresse}")
        os.replace(teil, datei)
    return datei


def aus_quellpaket(name: str, version: str) -> dict[str, str]:
    """Bibliotheken von crates.io im Quellpaket auf PyPI, die für Apple Silicon ins Programm gehen."""
    info = json.loads(holen(f"https://pypi.org/pypi/{name}/{version}/json"))
    sdist = next(u for u in info["urls"] if u["packagetype"] == "sdist")
    archiv = laden(LAGER / "rust-quellen" / sdist["filename"], sdist["url"], sdist["digests"]["sha256"])
    with tempfile.TemporaryDirectory() as ordner:
        subprocess.run(["tar", "-xf", str(archiv), "-C", ordner], check=True)
        manifest = next(Path(ordner).glob("*/Cargo.toml"))
        umgebung = {**os.environ, "CARGO_HOME": str(LAGER / "cargo")}
        daten = json.loads(subprocess.run(
            ["cargo", "metadata", "--locked", "--format-version", "1", "--filter-platform", ZIEL,
             "--manifest-path", str(manifest)], env=umgebung, stdout=subprocess.PIPE, check=True, text=True).stdout)
    pakete = {p["id"]: p for p in daten["packages"]}
    knoten = {k["id"]: k for k in daten["resolve"]["nodes"]}
    # Normale Abhängigkeiten und solche für den Bau, keine für Tests.
    offen, gesehen = [daten["resolve"]["root"]], set()
    while offen:
        kennung = offen.pop()
        if kennung in gesehen:
            continue
        gesehen.add(kennung)
        offen += [d["pkg"] for d in knoten[kennung]["deps"]
                  if any(a["kind"] in (None, "build") for a in d["dep_kinds"])]
    return {f"{p['name']} {p['version']}": p.get("license") or
            (f"eigene Lizenz, siehe {p['license_file']}" if p.get("license_file") else "nicht angegeben")
            for p in (pakete[k] for k in gesehen) if p.get("source") == CRATES_IO}


def index_eintraege(name: str) -> dict[str, str]:
    n = name.lower()
    pfad = {1: f"1/{n}", 2: f"2/{n}", 3: f"3/{n[0]}/{n}"}.get(len(n), f"{n[:2]}/{n[2:4]}/{n}")
    return {e["vers"]: e["cksum"] for e in map(json.loads, holen(f"https://index.crates.io/{pfad}").splitlines())}


def lizenztexte(crate: str) -> dict:
    """Lädt eine Bibliothek von crates.io, prüft sie und liest ihre Lizenzdateien, ohne etwas auszupacken."""
    name, version = crate.split(" ")
    sha256 = index_eintraege(name)[version]
    archiv = laden(LAGER / "crates" / f"{name}-{version}.crate",
                   f"https://static.crates.io/crates/{name}/{name}-{version}.crate", sha256)
    dateien = {}
    with tarfile.open(archiv, "r:gz") as tar:
        eintraege = {"/".join(Path(e.name).parts[1:]): e for e in tar.getmembers() if e.isfile()}
        manifest = tar.extractfile(eintraege["Cargo.toml"]).read().decode("utf-8", "replace")
        eigene = re.search(r'^license-file\s*=\s*"([^"]+)"', manifest, re.M)
        angabe = re.search(r'^license\s*=\s*"([^"]+)"', manifest, re.M)
        for pfad, eintrag in sorted(eintraege.items()):
            teile = pfad.split("/")
            treffer = teile[-1].upper().startswith(LIZENZDATEIEN) and not (
                NICHT_EINGEBAUT & {t.lower() for t in teile[:-1]} or Path(pfad).suffix.lower() in QUELLCODE)
            if treffer or (eigene and pfad == eigene.group(1).lstrip("./")):
                dateien[pfad] = tar.extractfile(eintrag).read().decode("utf-8", "replace")
    if not dateien:
        repository = re.search(r'^repository\s*=\s*"([^"]+)"', manifest, re.M)
        repository = repository.group(1).rstrip("/").removesuffix(".git") if repository else ""
        if repository in AUS_REPOSITORY:
            stand, liste = AUS_REPOSITORY[repository]
            for datei, summe in liste.items():
                ablage = laden(LAGER / "rust-quellen" / repository.split("/", 3)[3] / stand / datei,
                               f"{repository.replace('github.com', 'raw.githubusercontent.com')}/{stand}/{datei}", summe)
                dateien[f"{repository}/blob/{stand}/{datei}"] = ablage.read_text(errors="replace")
    texte = {d: t.replace("\r\n", "\n").strip() for d, t in dateien.items()}
    return {"sha256": sha256, "lizenz": angabe.group(1) if angabe else "nicht angegeben",
            "dateien": {d: t for d, t in texte.items() if t}}


def standardbibliothek(stand: str) -> dict:
    """Lizenztexte des Rust-Projekts zum Stand des Compilers. Der Stand in der Adresse legt den Inhalt fest."""
    dateien = {}
    for datei in RUST_DATEIEN:
        ablage = laden(LAGER / "rust-quellen/rust-lang/rust" / stand / datei,
                       f"https://raw.githubusercontent.com/rust-lang/rust/{stand}/{datei}")
        dateien[f"{RUST_PROJEKT}/blob/{stand}/{datei}"] = ablage.read_text(errors="replace").replace("\r\n", "\n").strip()
    return {"sha256": "", "dateien": dateien}


def main() -> None:
    pakete, alle, staende = {}, {}, set()
    for name, (version, dist, programme) in sorted(rust_pakete().items(), key=lambda p: p[0].lower()):
        crates = stueckliste(dist)
        quelle = "Stückliste im Wheel"
        if crates is None:
            crates, quelle = aus_quellpaket(name, version), f"Cargo.lock aus dem Quellpaket, aufgelöst für {ZIEL}"
        inhalt = b"".join(p.read_bytes() for p in programme)
        # Was die Standardbibliothek mitbringt, steht in keiner Stückliste, nur in der Programmdatei.
        for treffer in PFAD_STD.findall(inhalt):
            crates.setdefault(" ".join(t.decode() for t in treffer), "")
        im_programm = {" ".join(t.decode() for t in treffer) for treffer in PFAD_CRATE.findall(inhalt)}
        if not im_programm or not all(programme.values()):
            sys.exit(f"{name}: Pfade der Bibliotheken oder Prüfsumme in RECORD fehlen, so lässt sich nichts prüfen.")
        fehlt = sorted(im_programm - set(crates))
        if fehlt:
            sys.exit(f"{name}: Bibliotheken in der Programmdatei, aber nicht in der Liste: {', '.join(fehlt)}")
        compiler = sorted({s.decode() for s in re.findall(rb"/rustc/([0-9a-f]{40})/", inhalt)})
        staende.update(compiler)
        std = {f"Rust-Standardbibliothek, Compiler-Stand {s[:12]}": "MIT OR Apache-2.0" for s in compiler}
        pakete[name] = {"version": version, "quelle": f"{quelle}, Standardbibliothek aus der Programmdatei",
                        "programme": {str(p.relative_to(SITE)): summe for p, summe in programme.items()},
                        "crates": sorted(crates) + sorted(std)}
        alle.update(crates)
        print(f"{name} {version}: {len(crates)} Bibliotheken ({quelle}), Compiler {', '.join(compiler)}",
              file=sys.stderr)

    with ThreadPoolExecutor(8) as pool:
        # Gemeinsame Dateien aus Repositories zuerst einzeln, damit keine zwei Läufe dieselbe Datei laden.
        for stand in sorted(staende):
            alle[f"Rust-Standardbibliothek, Compiler-Stand {stand[:12]}"] = "MIT OR Apache-2.0"
        gelesen = {f"Rust-Standardbibliothek, Compiler-Stand {s[:12]}": standardbibliothek(s) for s in sorted(staende)}
        for repository, (stand, liste) in AUS_REPOSITORY.items():
            for datei, summe in liste.items():
                laden(LAGER / "rust-quellen" / repository.split("/", 3)[3] / stand / datei,
                      f"{repository.replace('github.com', 'raw.githubusercontent.com')}/{stand}/{datei}", summe)
        crates_io = sorted(c for c in alle if c not in gelesen)
        gelesen.update(zip(crates_io, pool.map(lizenztexte, crates_io)))
    texte, crates = {}, {}
    for crate, daten in sorted(gelesen.items()):
        verweise = {}
        for datei, text in sorted(daten["dateien"].items()):
            schluessel = hashlib.sha256(text.encode()).hexdigest()[:16]
            texte[schluessel] = text
            verweise[datei] = schluessel
        # Bibliotheken der Standardbibliothek stehen in keiner Liste, ihre Lizenz kommt aus ihrem Cargo.toml.
        crates[crate] = {"lizenz": alle[crate] or daten["lizenz"], "sha256": daten["sha256"], "texte": verweise}
    if ohne := [c for c, d in crates.items() if not d["texte"]]:
        sys.exit(f"Ohne Lizenztext, Repository in AUS_REPOSITORY ergänzen: {', '.join(ohne)}")
    print(f"{len(crates)} Bibliotheken, {len(texte)} verschiedene Texte", file=sys.stderr)
    teil = Path(f"{AUSGABE}.part")
    teil.write_text(json.dumps({"pakete": pakete, "crates": crates, "texte": texte}, ensure_ascii=False, indent=1,
                               sort_keys=True) + "\n")
    os.replace(teil, AUSGABE)


if __name__ == "__main__":
    main()
