"""Prüft den Rechenmotor von Graphis, ohne Grafikchip und ohne ein Bild zu rechnen.

Aufruf mit dem Python aus dem App-Paket, so wie die App es startet:
  <App>/Contents/Resources/Motor/python/bin/python3.12 -I -B motorpruefung.py MOTOR MODELLDATEIEN TESTBILD
MOTOR ist Contents/Resources/Motor, MODELLDATEIEN ein Ordner mit tokenizer/ des gepinnten Modells (die grossen
Gewichte braucht es nicht), TESTBILD ein beliebiges PNG. Jede Zeile beginnt mit ok oder FEHLER.
MLX rechnet hier nur auf dem Prozessor, der Grafikchip bleibt frei.
"""

import ast
import importlib.metadata
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

MOTOR = Path(sys.argv[1]).resolve()
MODELL = Path(sys.argv[2])
TESTBILD = Path(sys.argv[3])
LISTE = Path(__file__).with_name("anforderungen-moss.txt")
# Bewusst nicht im Motor. Ein Import davon wäre ein Fehler.
WEGGELASSEN = ["torch", "cv2", "matplotlib", "fontTools", "sympy", "networkx", "dateutil", "setuptools", "pip"]
# Diese Stellen von mflux laden ausgelassene Pakete nur in Zweigen, die die App nie nimmt.
ERLAUBT = {
    ("torch", "mflux.models.common.weights.loading.weight_loader"): "nur für PyTorch-Checkpoints, MOSS lädt safetensors",
    ("torch", "mflux.models.fibo_vlm.tokenizer.qwen2vl_processor"): "Bildprozessor von FIBO-VLM, MOSS braucht ihn nicht",
}
fehler = 0


def pruefen(name: str, ok: bool, angaben: str = "") -> None:
    global fehler
    fehler += not ok
    print(f"{'ok' if ok else 'FEHLER'} {name}{': ' + angaben if angaben else ''}", flush=True)


# Wie die App: offline, Zwischenspeicher ausserhalb des Pakets.
zwischen = Path(tempfile.mkdtemp(prefix="motorpruefung-"))
umgebung = {
    "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "HF_HUB_DISABLE_TELEMETRY": "1",
    "HF_HOME": str(zwischen / "huggingface"), "MFLUX_CACHE_DIR": str(zwischen / "mflux"),
}
os.environ.update(umgebung)

pruefen("Start mit -I -B", sys.flags.isolated == 1 and sys.dont_write_bytecode,
        f"isolated {sys.flags.isolated}, dont_write_bytecode {sys.dont_write_bytecode}")
prefix = Path(sys.prefix).resolve()
pruefen("Python aus dem Motor", prefix == MOTOR / "python", str(prefix))
fremd = [p for p in sys.path if p and not Path(p).resolve().is_relative_to(MOTOR)]
pruefen("Importpfad nur im Motor", not fremd, ", ".join(fremd) or f"{len(sys.path)} Einträge")

# Jedes Paket in genau der Version der Liste, und nichts darüber hinaus.
soll = dict(re.findall(r"^([a-z0-9-]+)==(\S+)", LISTE.read_text(), re.M))
ist = {re.sub(r"[-_.]+", "-", d.metadata["Name"]).lower(): d.version for d in importlib.metadata.distributions()}
pruefen("Paketversionen wie anforderungen-moss.txt", soll == ist,
        f"fehlt {sorted(set(soll) - set(ist))}, zusätzlich {sorted(set(ist) - set(soll))}, "
        f"anders {sorted(k for k in soll if k in ist and soll[k] != ist[k])}" if soll != ist else f"{len(ist)} Pakete")
vorhanden = [m for m in WEGGELASSEN if importlib.util.find_spec(m) is not None]
pruefen("Ausgelassene Pakete fehlen", not vorhanden, ", ".join(vorhanden))

import mlx.core as mx  # noqa: E402

mx.set_default_device(mx.cpu)
liste = sorted(p.name for p in (MOTOR / "python/lib/python3.12/site-packages/mlx/lib").iterdir())
pruefen("MLX mit metallib", "mlx.metallib" in liste and "libmlx.dylib" in liste, ", ".join(liste))

# Alles, was moss_referenz.py und der Befehl für MOSS laden.
EINSTIEGE = [
    "mflux.models.moss_image.cli.moss_image_generate",
    "mflux.models.moss_image.moss_image_initializer",
    "mflux.models.moss_image.variants.txt2img.moss_image",
    "mflux.models.moss_image.latent_creator.moss_image_latent_creator",
    "mflux.models.moss_image.model.moss_image_scheduler",
    "mflux.models.common.latent_creator.latent_creator",
    "mflux.models.common.schedulers",
    "mflux.models.flux2.latent_creator.flux2_latent_creator",
    "mflux.models.common.tokenizer",
    "mflux.utils.image_util",
]
for name in EINSTIEGE:
    try:
        importlib.import_module(name)
        pruefen(f"Import {name}", True)
    except Exception as fehlschlag:  # noqa: BLE001
        pruefen(f"Import {name}", False, f"{type(fehlschlag).__name__}: {fehlschlag}")
geladen = [m for m in WEGGELASSEN if m in sys.modules]
pruefen("Kein ausgelassenes Paket geladen", not geladen, ", ".join(geladen))

# Auch Importe in Funktionen zählen: Sie laufen erst beim Rechnen. Verfolgt wird jeder mflux-Modul, den die Einstiege
# erreichen. Was ausserhalb von mflux fehlt, muss in ERLAUBT stehen.
WURZEL = Path(importlib.util.find_spec("mflux").origin).parent


def datei(modul: str) -> Path | None:
    teile = WURZEL.parent.joinpath(*modul.split("."))
    for kandidat in (teile.with_suffix(".py"), teile / "__init__.py"):
        if kandidat.is_file():
            return kandidat
    return None


offen, gesehen, aussen = list(EINSTIEGE), set(), {}
while offen:
    modul = offen.pop()
    pfad = datei(modul)
    if modul in gesehen or pfad is None:
        continue
    gesehen.add(modul)
    paket = modul if pfad.name == "__init__.py" else modul.rpartition(".")[0]
    for knoten in ast.walk(ast.parse(pfad.read_text(encoding="utf-8"))):
        namen = []
        if isinstance(knoten, ast.Import):
            namen = [a.name for a in knoten.names]
        elif isinstance(knoten, ast.ImportFrom):
            basis = knoten.module or ""
            if knoten.level:
                stufen = paket.split(".")[: len(paket.split(".")) - knoten.level + 1]
                basis = ".".join(stufen + ([basis] if basis else []))
            namen = [basis] + [f"{basis}.{a.name}" for a in knoten.names]
        for name in namen:
            if name.startswith("mflux"):
                offen.append(name)
            elif name and name.split(".")[0] not in sys.stdlib_module_names:
                aussen.setdefault(name.split(".")[0], set()).add(modul)
fehlend = {n: sorted(m) for n, m in aussen.items() if importlib.util.find_spec(n) is None}
unerklaert = {n: [m for m in module if (n, m) not in ERLAUBT] for n, module in fehlend.items()}
unerklaert = {n: m for n, m in unerklaert.items() if m}
pruefen("Importe aller erreichten mflux-Module vorhanden", not unerklaert,
        f"{len(gesehen)} Module, fehlend {unerklaert}" if unerklaert
        else f"{len(gesehen)} Module, nur erlaubte Lücken: " + "; ".join(f"{n} in {m} ({ERLAUBT[(n, m)]})" for n, ms in fehlend.items() for m in ms))

# Tokenizer mit Chat-Template aus den Modelldateien, wie MOSS ihn lädt. Braucht Jinja2.
from mflux.models.common.tokenizer import TokenizerLoader  # noqa: E402
from mflux.models.moss_image.weights.moss_image_weight_definition import MOSSImageWeightDefinition  # noqa: E402

try:
    tokenizer = TokenizerLoader.load_all(MOSSImageWeightDefinition.get_tokenizers(), str(MODELL))["qwen3_5"]
    ausgabe = tokenizer.tokenize("Ein rotes Haus an einem See", keep_empty=True)
    leer = tokenizer.tokenize("", keep_empty=True)
    text = tokenizer.tokenizer.decode(ausgabe.input_ids.tolist()[0])
    pruefen("Tokenizer mit Chat-Template", ausgabe.input_ids.shape[1] > 8 and leer.input_ids.shape[1] > 0
            and "<|im_start|>" in text and "rotes Haus" in text,
            f"{ausgabe.input_ids.shape[1]} Token, leerer Prompt {leer.input_ids.shape[1]} Token")
except Exception as fehlschlag:  # noqa: BLE001
    pruefen("Tokenizer mit Chat-Template", False, f"{type(fehlschlag).__name__}: {fehlschlag}")

# Vorlage aufbereiten wie LatentCreator.encode_image, bis direkt vor den VAE.
from mflux.utils.image_util import ImageUtil  # noqa: E402

try:
    bild = ImageUtil.scale_to_dimensions(ImageUtil.load_image(TESTBILD).convert("RGB"), target_width=688, target_height=1024)
    feld = ImageUtil.to_array(bild)
    mx.eval(feld)
    pruefen("Referenzbild aufbereitet", tuple(feld.shape) == (1, 3, 1024, 688) and -1.01 <= feld.min().item() <= feld.max().item() <= 1.01,
            f"Form {tuple(feld.shape)}")
except Exception as fehlschlag:  # noqa: BLE001
    pruefen("Referenzbild aufbereitet", False, f"{type(fehlschlag).__name__}: {fehlschlag}")

# Die beiden Aufrufe der App, nur mit --help: Argumente, Versions- und Fingerabdruckprüfung, Einhängen in mflux.
grund = [sys.executable, "-I", "-B", str(MOTOR / "motor_start.py")]
for art, zusatz in [("bild", []), ("referenz", ["--image", str(TESTBILD), "0.5"])]:
    lauf = subprocess.run(grund + [art, *zusatz, "--help"], capture_output=True, text=True, timeout=300,
                          env={"PATH": "/usr/bin:/bin", "HOME": os.environ.get("HOME", "/tmp"), **umgebung})
    pruefen(f"Aufruf {art} --help", lauf.returncode == 0 and "--prompt-file" in lauf.stdout and "--lora" in lauf.stdout
            and "--no-exif" in lauf.stdout, f"Code {lauf.returncode} {lauf.stderr.strip()[-300:]}")
falsch = subprocess.run(grund + ["referenz", "--help"], capture_output=True, text=True, timeout=300,
                        env={"PATH": "/usr/bin:/bin", **umgebung})
pruefen("Referenz ohne Bild meldet sich verständlich", falsch.returncode == 2 and "Rechenmotor: --image" in falsch.stderr,
        falsch.stderr.strip()[-200:])

print("Alle Prüfungen ok" if fehler == 0 else f"{fehler} Prüfungen fehlgeschlagen")
sys.exit(1 if fehler else 0)
