#!/bin/zsh
# Prüft Graphis ohne App-Fenster, ohne Grafikchip und ohne Internet. Baut ein Prüfprogramm aus den Quellen der App,
# aber ohne deren Einstieg, und lässt es gegen einen lokalen Testserver und ein Scheinprogramm laufen, das statt des
# Rechenmotors aufgerufen wird. Jede Art läuft in einem eigenen, frischen Ordner im Ordner für temporäre Dateien.
#   zsh tests/testlauf.sh            alle Arten
#   zsh tests/testlauf.sh module     nur die genannten Arten
# Exitstatus 0 nur, wenn jede Prüfung ok ist. Mit GRAPHIS_TEST_BEHALTEN=1 bleibt der Arbeitsordner auch dann liegen.
cd "$(dirname "$0")/.."
PY="${PYTHON:-/usr/bin/python3}"
ARBEIT="$(mktemp -d "${${TMPDIR:-/tmp}%/}/graphis-test.XXXXXX")" || exit 2
BIN="$ARBEIT/graphis-test"
ARTEN=("$@")
[ ${#ARTEN} = 0 ] && ARTEN=(einrichtung neustart warteschlange referenzen module daten)
echo "Arbeitsordner: $ARBEIT"

# Das Prüfprogramm: alle Quellen der App ausser GraphisApp.swift, dazu tests/*.swift. Nur hier gilt TESTLAUF.
QUELLEN=()
for datei in App/*.swift; do [ "$datei" != "App/GraphisApp.swift" ] && QUELLEN+=("$datei"); done
echo "Baue das Prüfprogramm …"
swiftc -O -swift-version 5 -D TESTLAUF -target arm64-apple-macos26.2 -module-name GraphisTest \
  -o "$BIN" "${QUELLEN[@]}" tests/*.swift || { echo "FEHLER Das Prüfprogramm liess sich nicht bauen."; exit 2 }

# Der Testserver läuft nur für diesen Lauf und wird am Ende über seine eigene Nummer beendet.
mkdir -p "$ARBEIT/server-daten"
"$PY" -I tests/server.py "$ARBEIT/server-daten" "$ARBEIT/server.log" "$ARBEIT/port.txt" > "$ARBEIT/server-ausgabe.txt" 2>&1 &
SERVER=$!
LAUFEND=""
# Beendet ein Prüfprogramm samt dem Scheinprogramm, das es gerade aufgerufen hat.
beenden() { pkill -P $1 2>/dev/null; kill $1 2>/dev/null }
# Auch bei Ctrl-C oder einem Signal von aussen: Testserver und laufendes Prüfprogramm enden mit.
trap 'kill $SERVER 2>/dev/null' EXIT
trap '[ -n "$LAUFEND" ] && beenden $LAUFEND; kill $SERVER 2>/dev/null; echo; echo "Abgebrochen. Arbeitsordner bleibt: $ARBEIT"; exit 130' INT TERM HUP
for i in {1..100}; do [ -s "$ARBEIT/port.txt" ] && break; sleep 0.1; done
[ -s "$ARBEIT/port.txt" ] || { echo "FEHLER Der Testserver startet nicht."; exit 2 }
"$PY" -I tests/daten.py "$ARBEIT/server-daten" "$(cat "$ARBEIT/port.txt")" "$ARBEIT/manifest.json" > /dev/null \
  || { echo "FEHLER Die Testdaten liessen sich nicht anlegen."; exit 2 }

# Ein frischer Testordner mit Kennzeichen und eigenem Scheinprogramm.
testordner() {
  mkdir -p "$1/schein"
  : > "$1/.graphis-testordner"
  cp tests/schein.sh "$1/schein/schein.sh"
  chmod +x "$1/schein/schein.sh"
}

# Startet das Prüfprogramm mit allen Angaben für den Testordner $1, weitere Argumente gehen an das Programm.
# Nur im Hintergrund aufrufen: exec ersetzt dort die Hilfsshell, so ist $! die Nummer des Prüfprogramms selbst.
pruefprogramm() {
  local test="$1"; shift
  GRAPHIS_TESTORDNER="$test" GRAPHIS_TESTCLI="$test/schein/schein.sh" GRAPHIS_TESTMANIFEST="$ARBEIT/manifest.json" \
    GRAPHIS_TESTSERVERLOG="$ARBEIT/server.log" exec "$BIN" "$@"
}

# Wartet höchstens $2 Sekunden auf den Prozess $1. Liefert dessen Exitstatus, 124 nach dem Zeitlimit.
warten() {
  local pid=$1 ende=$((SECONDS + $2)) rc
  LAUFEND=$pid
  while kill -0 $pid 2>/dev/null; do
    if [ $SECONDS -ge $ende ]; then
      beenden $pid
      wait $pid 2>/dev/null
      LAUFEND=""
      return 124
    fi
    sleep 0.2
  done
  wait $pid
  rc=$?
  LAUFEND=""
  return $rc
}

GESAMT=0; FEHLER=0; STATUS=0
# lauf ART FRIST [ORDNER]: eine Art in ihrem Testordner, mit Zeitlimit und Auswertung.
lauf() {
  local art=$1 frist=$2 test="${3:-$ARBEIT/$1}" ergebnis
  [ -d "$test" ] || testordner "$test"
  echo; echo "== $art"
  pruefprogramm "$test" "$art" > "$ARBEIT/$art.txt" 2>&1 &
  warten $! $frist
  ergebnis=$?
  cat "$ARBEIT/$art.txt"
  [ $ergebnis = 124 ] && echo "FEHLER $art hat das Zeitlimit von $frist s überschritten"
  local anzahl=$(grep -cE '^(ok|FEHLER) ' "$ARBEIT/$art.txt") falsch=$(grep -c '^FEHLER ' "$ARBEIT/$art.txt")
  GESAMT=$((GESAMT + anzahl)); FEHLER=$((FEHLER + falsch))
  [ $ergebnis = 0 ] && [ $falsch = 0 ] && [ $anzahl -gt 0 ] || STATUS=1
}

for art in $ARTEN; do
  case $art in
    neustart)
      # Lädt an, wird mitten im Laden hart beendet und setzt danach in einem neuen Prozess fort.
      test="$ARBEIT/neustart"
      testordner "$test"
      pruefprogramm "$test" neustart-beginnen > "$ARBEIT/neustart-beginnen.txt" 2>&1 &
      pid=$!
      LAUFEND=$pid
      ende=$((SECONDS + 30))
      while [ ! -s "$test/neustart.txt" ] && kill -0 $pid 2>/dev/null && [ $SECONDS -lt $ende ]; do sleep 0.1; done
      kill -9 $pid 2>/dev/null
      wait $pid 2>/dev/null
      LAUFEND=""
      lauf neustart-fortsetzen 60 "$test" ;;
    einrichtung) lauf einrichtung 300 ;;
    warteschlange) lauf warteschlange 180 ;;
    referenzen|module) lauf $art 120 ;;
    daten) lauf daten 60 ;;
    *) echo "FEHLER Unbekannte Art: $art"; STATUS=1 ;;
  esac
done

echo
echo "$GESAMT Prüfungen, $FEHLER fehlgeschlagen"
if [ $STATUS = 0 ] && [ "${GRAPHIS_TEST_BEHALTEN:-0}" != 1 ]; then
  kill $SERVER 2>/dev/null
  wait $SERVER 2>/dev/null
  rm -rf "$ARBEIT"
else
  echo "Arbeitsordner bleibt: $ARBEIT"
fi
exit $STATUS
