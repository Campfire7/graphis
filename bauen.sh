#!/bin/zsh
# Baut Graphis: Rechenmotor zusammenstellen, App übersetzen, von innen nach aussen ad hoc signieren, als ZIP packen.
# Ergebnis: dist/Graphis.app und dist/Graphis-VERSION.zip. Gebaut wird nur dort, nie in einen Programmordner.
# GRAPHIS_VERSION und GRAPHIS_BUILD setzen Version und Buildnummer, sonst gilt 1.0 und 1.
# Braucht die Xcode Command Line Tools, uv und beim ersten Bau Internet für Python und die Pakete (alle mit SHA-256).
set -e
cd "$(dirname "$0")"
NAME=Graphis           # muss zu Fassung.name passen
KENNUNG=local.graphis  # muss zu Fassung.kennung passen
VERSION="${GRAPHIS_VERSION:-1.0}"
BUILD="${GRAPHIS_BUILD:-1}"
[[ "$VERSION" =~ '^[0-9]+(\.[0-9]+){0,2}$' && "$BUILD" =~ '^[0-9]+$' ]] \
  || { echo "GRAPHIS_VERSION braucht die Form 1.2 oder 1.2.3, GRAPHIS_BUILD eine Zahl." >&2; exit 1 }
# Fester Zeitpunkt für alle Dateien im Paket und im ZIP, damit es weder Bauzeit noch Bauort verrät.
ZEITPUNKT=202601010000
ZWISCHEN="$(mktemp -d)"
# Auch bei Ctrl-C bleibt kein halber Bau mit dem ganzen Motor im Ordner für temporäre Dateien liegen.
trap 'rm -rf "$ZWISCHEN"' EXIT
trap 'exit 130' INT TERM HUP
APP="$ZWISCHEN/$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ ! -f App/AppIcon.icns ]; then
  SET="$ZWISCHEN/AppIcon.iconset"; mkdir -p "$SET"
  swift werkzeug/icon.swift "$ZWISCHEN/icon.png"
  for g in 16 32 128 256 512; do
    sips -z $g $g "$ZWISCHEN/icon.png" --out "$SET/icon_${g}x${g}.png" >/dev/null
    d=$((g * 2)); sips -z $d $d "$ZWISCHEN/icon.png" --out "$SET/icon_${g}x${g}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o App/AppIcon.icns
fi
cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Reihenfolge: Motor fertig zusammenstellen samt Bytecode, dann nichts mehr ändern und von innen nach aussen
# signieren, zuletzt das ganze Paket.
DIST="$PWD/dist"
LAGER="$PWD/.build/downloads"
MOTOR="$APP/Contents/Resources/Motor"
zsh motor/bereitstellen.sh "$MOTOR" "$LAGER"
PY="$MOTOR/python/bin/python3.12"
HILFE=(-I -B)

# Die Mindestversion folgt der anspruchsvollsten Datei im Motor, aber nie unter 26.2: Das verlangt MLX.
MINOS="$("$PY" $HILFE motor/macho.py minos "$MOTOR")"
MINOS="$(printf '%s\n%s\n' "$MINOS" 26.2 | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
"$PY" $HILFE motor/macho.py pruefen "$MOTOR" > "$ZWISCHEN/macho.txt" || { cat "$ZWISCHEN/macho.txt"; exit 1 }

# Die Quellen kommen relativ und mit neutralem Bauordner hinein, so steht kein Pfad dieses Macs im Programm.
swiftc -O -parse-as-library -swift-version 5 -target "arm64-apple-macos$MINOS" -module-name "$NAME" \
  -file-prefix-map "$PWD=." -o "$APP/Contents/MacOS/$NAME" App/*.swift
# Prüfcode gehört nur ins Prüfprogramm von tests/testlauf.sh, nie in die App.
if strings -a "$APP/Contents/MacOS/$NAME" | grep -q -e GRAPHIS_ -e Testumgebung -e Pruefbericht; then
  echo "Die App enthält Prüfcode. Ist irgendwo TESTLAUF gesetzt?" >&2
  exit 1
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$KENNUNG</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>LSMinimumSystemVersion</key><string>$MINOS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppSleepDisabled</key><true/>
</dict></plist>
PLIST
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
"$PY" $HILFE motor/lizenzen.py "$MOTOR" "$LAGER/python-lizenzen" > "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt" THIRD_PARTY_NOTICES.txt

# Keine erweiterten Attribute ins Paket, etwa Herkunftsangaben von Downloads.
xattr -cr "$APP" 2>/dev/null || true

# Jede Mach-O-Datei einzeln, tiefste zuerst. --deep nur zum Prüfen, nie zum Signieren.
"$PY" $HILFE motor/macho.py liste "$MOTOR" | while IFS= read -r datei; do
  codesign --force --sign - --timestamp=none "$datei" 2>/dev/null || { echo "Signieren fehlgeschlagen: $datei" >&2; exit 1 }
done
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null

# Dateizeiten gehören nicht zur Signatur. Alle bekommen denselben festen Zeitpunkt, dann wird nochmals geprüft.
find "$APP" -exec touch -h -t "$ZEITPUNKT" {} +
codesign --verify --deep --strict "$APP"
"$PY" $HILFE motor/macho.py liste "$MOTOR" | while IFS= read -r datei; do
  codesign --verify --strict "$datei"
done

mkdir -p "$DIST"
rm -rf "$DIST/$NAME.app" "$DIST/$NAME-$VERSION.zip"
mv "$APP" "$DIST/$NAME.app"
# Info-ZIP ohne Zusatzfelder (-X): keine Benutzer- und Gruppennummern, keine erweiterten Attribute, kein __MACOSX.
# Verknüpfungen bleiben Verknüpfungen (-y). Die Rechte bleiben, damit die Programme ausführbar sind.
(cd "$DIST" && zip -q -r -X -y "$NAME-$VERSION.zip" "$NAME.app")
echo "Gebaut: dist/$NAME.app (macOS ab $MINOS)"
echo "Paket: dist/$NAME-$VERSION.zip"
if grep -q "example.org" App/Fassung.swift; then
  echo "Hinweis: Die Adresse für Projekt unterstützen ist noch ein Platzhalter (App/Fassung.swift)." >&2
fi
