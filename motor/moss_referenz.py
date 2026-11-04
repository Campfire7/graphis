"""MOSS-Image mit Referenzbild.

Startet die unveränderte Rechnung von mflux bei einem verrauschten Referenzbild statt bei reinem Rauschen.
Aufruf wie mflux-generate-moss-image, dazu --image PFAD NAEHE. NAEHE liegt zwischen 0 und 1, hoch bleibt nah an der Vorlage.
Alle Schritte laufen, nur auf einem kürzeren Weg zum fertigen Bild. So bleibt der Regler auch mit Turbo fein abgestuft.
Das Skript greift in mflux ein und prüft darum zuerst Version und Aufbau. Passt etwas nicht, bricht es mit Meldung ab.
"""

import hashlib
import importlib.metadata
import sys
from pathlib import Path

GEPRUEFT = "0.24.0"
# Die Dateien von mflux, auf die sich das Skript verlässt, mit dem Anfang ihres SHA-256 in der geprüften Fassung.
FINGERABDRUECKE = {
    "models/moss_image/variants/txt2img/moss_image.py": "28695ff5c7ca1952",
    "models/moss_image/cli/moss_image_generate.py": "46e894c16debb302",
    "models/moss_image/model/moss_image_scheduler/moss_image_scheduler.py": "e1984c828d091cc6",
    "models/moss_image/latent_creator/moss_image_latent_creator.py": "8cbd447292c50e9e",
    "models/flux2/model/flux2_vae/vae.py": "ba22d88b3dbabd7d",
    "models/common/latent_creator/latent_creator.py": "bb09fe69eb6e1a6e",
    "models/flux2/latent_creator/flux2_latent_creator.py": "eec77a06180ffb83",
}
# MOSS hält sehr stark an der Vorlage fest: Ab einem Anteil von etwa 0.3 bleibt das Bild fast gleich (gemessen mit
# Turbo, 768 Pixel, Stilwechsel Foto zu Aquarell). Der Regler der App verteilt sich darum auf den wirksamen Bereich.
WIRKSAM = 0.45
KRUEMMUNG = 1.3
ZUSTAND = {}


def abbrechen(text: str) -> None:
    print(f"Rechenmotor: {text}", file=sys.stderr)
    sys.exit(2)


def vorlage_lesen(argumente: list[str]) -> tuple[str, float]:
    if "--image" not in argumente:
        abbrechen("--image PFAD NAEHE fehlt.")
    stelle = argumente.index("--image")
    try:
        pfad, naehe = argumente[stelle + 1], float(argumente[stelle + 2])
    except (IndexError, ValueError):
        abbrechen("--image braucht einen Pfad und eine Zahl zwischen 0 und 1.")
    del argumente[stelle : stelle + 3]
    if not Path(pfad).is_file():
        abbrechen("Das Referenzbild fehlt.")
    return pfad, min(max(naehe, 0.0), 1.0)


def main() -> None:
    argumente = sys.argv[1:]
    pfad, regler = vorlage_lesen(argumente)
    # 0.125 lässt viel Freiheit, 0.375 wechselt den Stil und behält den Aufbau, 0.875 bleibt sehr nah an der Vorlage.
    naehe = WIRKSAM * regler**KRUEMMUNG
    version = importlib.metadata.version("mflux")
    if version != GEPRUEFT:
        abbrechen(f"mflux {version} ist nicht geprüft, erwartet ist {GEPRUEFT}. Der Rechenmotor muss neu eingerichtet werden.")

    import mflux

    wurzel = Path(mflux.__file__).parent
    for datei, abdruck in FINGERABDRUECKE.items():
        pfad_mflux = wurzel / datei
        if not pfad_mflux.is_file() or hashlib.sha256(pfad_mflux.read_bytes()).hexdigest()[:16] != abdruck:
            abbrechen("mflux ist anders aufgebaut als geprüft. Der Rechenmotor muss neu eingerichtet werden.")

    import mlx.core as mx
    import numpy as np

    from mflux.models.common.latent_creator.latent_creator import LatentCreator
    from mflux.models.common.schedulers import register_contrib
    from mflux.models.flux2.latent_creator.flux2_latent_creator import Flux2LatentCreator
    from mflux.models.moss_image.cli import moss_image_generate as befehl
    from mflux.models.moss_image.latent_creator.moss_image_latent_creator import MOSSImageLatentCreator
    from mflux.models.moss_image.model.moss_image_scheduler import MOSSImageScheduler
    from mflux.models.moss_image.variants.txt2img import moss_image

    class ReferenzPlan(MOSSImageScheduler):
        """Der Plan von MOSS, aber er beginnt beim Rauschanteil der Vorlage statt bei reinem Rauschen."""

        def __init__(self, config):
            self.config = config
            self._sigmas = ReferenzPlan.berechnen(config.num_inference_steps, 1.0 - naehe)
            self._timesteps = self._sigmas[:-1] * MOSSImageScheduler.NUM_TRAIN_TIMESTEPS

        @staticmethod
        def berechnen(schritte: int, anteil: float) -> mx.array:
            """Startet beim gegebenen Anteil des MOSS-Plans: 1 ist reines Rauschen, 0.25 das letzte Viertel.

            MOSS verschiebt seinen Plan stark ins Rauschen. Ein Anteil statt eines Rauschwerts verteilt den Regler darum
            gleichmässig auf die Wirkung, wie mflux es bei anderen Modellen mit der Stärke tut."""
            gesamt = MOSSImageScheduler.NUM_TRAIN_TIMESTEPS
            k = MOSSImageScheduler.SHIFT
            werte = np.linspace(anteil, k / (gesamt + k - 1), schritte)
            sigmas = k * werte / (1 + (k - 1) * werte)
            # MOSS rechnet nur auf den Punkten seines Trainingsrasters.
            raster = np.linspace(1.0, 1.0 / gesamt, gesamt)
            sigmas = raster[np.abs(raster[None, :] - sigmas[:, None]).argmin(axis=1)]
            return mx.array(np.concatenate([sigmas, [0.0]]).astype(np.float32))

    class ReferenzStart(MOSSImageLatentCreator):
        @staticmethod
        def create_noise(seed: int, height: int, width: int) -> mx.array:
            rauschen = MOSSImageLatentCreator.create_noise(seed=seed, height=height, width=width)
            # Kachelung richtet mflux erst nach dem Laden ein, darum gilt der Stand beim Rechnen.
            modell = ZUSTAND["modell"]
            vae = modell.vae
            bild = LatentCreator.encode_image(
                vae=vae, image_path=pfad, height=height, width=width, tiling_config=modell.tiling_config
            )
            if bild.ndim == 5:
                bild = bild[:, :, 0, :, :]
            # Dieselbe Form wie die Latents von MOSS: 2x2 zusammengefasst und mit den Werten des VAE normiert.
            bild = Flux2LatentCreator.patchify_latents(bild.astype(mx.float32))
            mittel = vae.bn.running_mean.astype(mx.float32).reshape(1, -1, 1, 1)
            streuung = mx.sqrt(vae.bn.running_var.astype(mx.float32).reshape(1, -1, 1, 1) + vae.bn.eps)
            sauber = (bild - mittel) / streuung
            start = float(ReferenzPlan.berechnen(1, 1.0 - naehe)[0])
            return LatentCreator.add_noise_by_interpolation(clean=sauber, noise=rauschen, sigma=start)

    laden = befehl.MOSSImageCommand.load

    def laden_und_merken(args):
        modell = laden(args)
        ZUSTAND["modell"] = modell
        return modell

    befehl.MOSSImageCommand.load = staticmethod(laden_und_merken)
    moss_image.MOSSImageLatentCreator = ReferenzStart
    register_contrib(ReferenzPlan, "moss_image")

    sys.argv = [sys.argv[0], *argumente]
    befehl.main()


if __name__ == "__main__":
    main()
