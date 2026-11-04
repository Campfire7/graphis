#!/bin/zsh
# Scheinprogramm für die Prüfungen: hält die Argumente in aufrufe.txt und den Prompt in prompts.txt fest und legt am
# Zielort ein kleines Bild ab. Es rechnet nichts. Liegt neben ihm einmal-fehlschlagen, scheitert der nächste Aufruf.
# Liegt dort langsam, wartet es, bis es beendet wird.
ORT="${0:A:h}"
print -r -- "$*" >> "$ORT/aufrufe.txt"
if [ -e "$ORT/einmal-fehlschlagen" ]; then
  rm -f "$ORT/einmal-fehlschlagen"
  print -u2 "Scheinprogramm: absichtlicher Fehler"
  exit 1
fi
[ -e "$ORT/langsam" ] && exec sleep 30
while [ $# -gt 0 ]; do
  case "$1" in
    --prompt-file) cat "$2" >> "$ORT/prompts.txt"; print >> "$ORT/prompts.txt" ;;
    --output) print -r -- "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -D > "$2" ;;
  esac
  shift
done
sleep 0.3
