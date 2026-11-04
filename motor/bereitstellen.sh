#!/bin/zsh
# Stellt den Rechenmotor von Graphis zusammen, Aufruf: bereitstellen.sh ZIELORDNER LAGER
# Python kommt als festes Archiv von python-build-standalone, die Pakete als feste Wheels aus anforderungen-moss.txt,
# beide mit SHA-256. ZIELORDNER (endet auf /Motor) wird neu angelegt, LAGER hält die Downloads für den nächsten Bau.
# Danach ist der Motor fertig: Er wird nur noch signiert, nie mehr verändert.
set -euo pipefail
cd "$(dirname "$0")"
ZIEL="$1"
LAGER="$2"
[[ "$ZIEL" == */Motor ]] || { echo "Der Zielordner muss auf /Motor enden: $ZIEL" >&2; exit 1 }

# Fester Stand von python-build-standalone. Der SHA-256 stimmt mit SHA256SUMS des Releases überein.
PYTHON_RELEASE=20261026
PYTHON_VERSION=3.12.16
PYTHON_DATEI="cpython-${PYTHON_VERSION}+${PYTHON_RELEASE}-aarch64-apple-darwin-install_only_stripped.tar.gz"
PYTHON_SHA256=353d5f1b4fd2715e7053f12f068435d5bbad16b91e057006b5d01e0925709a7e
PYTHON_ADRESSE="https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_RELEASE}/${PYTHON_DATEI//+/%2B}"
# Das volle Archiv desselben Stands liefert nur die Lizenzangaben (PYTHON.json und licenses/), es kommt nicht in die App.
LIZENZ_DATEI="cpython-${PYTHON_VERSION}+${PYTHON_RELEASE}-aarch64-apple-darwin-pgo+lto-full.tar.zst"
LIZENZ_SHA256=016758f4881e5f71d63eddfbcdd53f25c5a9152435a863e4dc0770758eae32c3
LIZENZ_ADRESSE="https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_RELEASE}/${LIZENZ_DATEI//+/%2B}"
UV="${UV:-$(command -v uv || echo /opt/homebrew/bin/uv)}"

pruefsumme() { shasum -a 256 "$1" | cut -d' ' -f1 }

# Lädt ein Archiv nur, wenn es fehlt oder nicht stimmt, und bricht ab, wenn der SHA-256 nicht passt.
holen() {
  local datei="$1" adresse="$2" soll="$3"
  if [ ! -f "$datei" ] || [ "$(pruefsumme "$datei")" != "$soll" ]; then
    curl -fsSL --retry 3 -o "$datei.part" "$adresse"
    mv "$datei.part" "$datei"
  fi
  if [ "$(pruefsumme "$datei")" != "$soll" ]; then
    echo "$datei hat nicht den erwarteten SHA-256." >&2
    exit 1
  fi
}

mkdir -p "$LAGER/python" "$LAGER/python-voll" "$LAGER/wheels" "$LAGER/uv"
ARCHIV="$LAGER/python/$PYTHON_DATEI"
holen "$ARCHIV" "$PYTHON_ADRESSE" "$PYTHON_SHA256"
holen "$LAGER/python-voll/$LIZENZ_DATEI" "$LIZENZ_ADRESSE" "$LIZENZ_SHA256"
rm -rf "$LAGER/python-lizenzen"
mkdir -p "$LAGER/python-lizenzen"
tar -xf "$LAGER/python-voll/$LIZENZ_DATEI" -C "$LAGER/python-lizenzen" python/PYTHON.json python/licenses

rm -rf "$ZIEL"
mkdir -p "$ZIEL"
tar -xzf "$ARCHIV" -C "$ZIEL"
PY="$ZIEL/python/bin/python3.12"

# Wheels zuerst aus dem Lager, nur wenn eines fehlt aus dem Netz. pip prüft dabei jeden Hash.
# Ohne den Zwischenspeicher von pip: Jeder Bau holt die Wheels nur aus dem eigenen Lager oder aus dem Netz.
LADEN=(--quiet --disable-pip-version-check --no-cache-dir --no-deps --require-hashes --only-binary=:all:
       --platform macosx_26_0_arm64 --python-version 3.12 --implementation cp --abi cp312
       -d "$LAGER/wheels" -r anforderungen-moss.txt)
"$PY" -I -m pip download --no-index --find-links "$LAGER/wheels" "${LADEN[@]}" 2>/dev/null \
  || "$PY" -I -m pip download "${LADEN[@]}"
"$UV" pip install --quiet --python "$PY" --no-deps --require-hashes --no-index --find-links "$LAGER/wheels" \
  --link-mode copy --cache-dir "$LAGER/uv" -r anforderungen-moss.txt

# Was zur Laufzeit nie gebraucht wird: Tk, Entwicklerdateien, Paketwerkzeuge, Tests und Startskripte mit festen Pfaden.
# Paketmetadaten, libpython und mlx.metallib bleiben: mflux und transformers lesen Versionen über importlib.metadata.
P="$ZIEL/python"
rm -rf "$P/include" "$P/share" "$P/lib/pkgconfig" "$P/lib/itcl"* "$P/lib/tcl"* "$P/lib/tk"* "$P/lib/thread"* \
  "$P/lib/libtcl"* "$P/lib/python3.12/config-3.12-darwin" "$P/lib/python3.12/lib-dynload/_tkinter"* \
  "$P/lib/python3.12/"{tkinter,idlelib,turtledemo,ensurepip,test,lib2to3} \
  "$P/lib/python3.12/site-packages/"pip "$P/lib/python3.12/site-packages/"pip-*.dist-info
find "$P/bin" -mindepth 1 ! -name python3.12 -exec rm -f {} +
find "$P" -name __pycache__ -type d -prune -exec rm -rf {} +
# uv legt einen Zeitstempel ab, der jeden Bau anders machte.
rm -f "$P/lib/python3.12/site-packages/"*.dist-info/uv_cache.json

cp motor_start.py moss_referenz.py "$ZIEL/"
# Bytecode vorab, mit Hash statt Zeitstempel: Python liest ihn unverändert, auch wenn ZIP oder Kopie die Zeiten ändern.
# Der Bauordner kommt nicht in die Dateien, nur der Ort im Paket. Python setzt beim Laden ohnehin den echten Pfad ein.
"$PY" -I -m compileall -q -j 0 -f --invalidation-mode unchecked-hash -s "$ZIEL" -p /Graphis.app/Contents/Resources/Motor \
  "$ZIEL" >/dev/null 2>&1 || "$PY" -I -m compileall -q -j 0 -f --invalidation-mode unchecked-hash \
  -s "$ZIEL" -p /Graphis.app/Contents/Resources/Motor "$ZIEL"
"$PY" -I -c "import importlib.metadata as m; assert m.version('mflux') == '0.24.0', m.version('mflux')"
echo "Rechenmotor bereit: $ZIEL"
