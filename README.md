# Graphis

**English:** Graphis is a native macOS app that turns text prompts into images entirely on your Mac. It runs the open MOSS-Image model (Apache 2.0) through mflux and Apple's MLX. Prompts and images never leave the computer: the app only goes online when you click to download the model or a module. It needs a Mac with Apple Silicon and macOS 26.2 or later. The app and this documentation are in German. Graphis is free software under the MIT licence; the bundled third-party components are listed in `THIRD_PARTY_NOTICES.txt`.

## Was ist Graphis?

Graphis (griechisch γραφίς, Griffel, Pinsel) macht aus einer Beschreibung ein Bild, ganz auf deinem Mac. Es rechnet mit dem Modell MOSS-Image, das unter der Lizenz Apache 2.0 frei verfügbar ist. Der Rechenmotor liegt fertig im App-Paket, das Modell lädt die App beim ersten Start auf deinen Klick.

Was die App kann:

- Bilder aus Prompt und Negativprompt, in fünf Formaten und bis 1280 Pixel
- Drei Stufen von Schnell (mit Turbo-Modul) bis Beste, oder eigene Werte für Schritte und Textführung
- Ein Referenzbild als Vorlage, mit einem Regler für die Nähe zur Vorlage
- Module (LoRA-Dateien) für Stil, Licht und Details: ein kleiner Katalog geprüfter Module oder eigene Dateien
- Eine Warteschlange, die nach einem Neustart weiterläuft, und eine Zeitschätzung, die mit jedem Bild genauer wird
- Die Einstellungen eines fertigen Bildes übernehmen, um gezielt eine Sache zu ändern

## Voraussetzungen

- Mac mit Apple Silicon (M1 oder neuer)
- macOS 26.2 oder neuer. Die Rechenbibliothek MLX verlangt diese Version.
- Rund 17 GB freier Speicher: 15,2 GB für Modell und Turbo-Modul, dazu eine Reserve
- Arbeitsspeicher: 24 GB oder mehr empfohlen. Das Modell belegt rund 14 GB, mit 16 GB ist es ungeprüft.

## Installieren

1. `Graphis-<Version>.zip` herunterladen und mit Doppelklick entpacken.
2. `Graphis.app` in den Ordner Programme ziehen.
3. Graphis ist nur ad hoc signiert und nicht von Apple beglaubigt. Beim ersten Öffnen meldet macOS darum, dass es die App nicht prüfen kann. Öffne dann **Systemeinstellungen > Datenschutz & Sicherheit**, klicke ganz unten bei der Meldung zu Graphis auf **Trotzdem öffnen** und bestätige.
4. Klappt das nicht, gib im Terminal nur diese eine App frei und öffne sie danach normal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Graphis.app
   ```

## Erster Start

Unter **Neues Bild** erscheint die Karte «MOSS-Image einrichten» mit der Grösse des Downloads und dem freien Platz. Erst ein Klick auf **Laden** holt das Modell (mflux-community/moss-image-sft-mflux-q8) und das Turbo-Modul (lodestones/MOSS-Image-SFT-8-steps-dmd) von Hugging Face, beide zu einem festen Stand. Jede Datei wird mit ihrem SHA-256 geprüft. Bricht das Laden ab oder schliesst du die App, geht es mit **Fortsetzen** an derselben Stelle weiter. Erst wenn alles stimmt, wird das Modell aktiv. Danach rechnet Graphis ohne Internet.

Unter **Einstellungen > Allgemein** lassen sich die Modelldateien jederzeit neu prüfen. Beschädigte Dateien lädt **Reparieren** unter Neues Bild neu, die guten bleiben.

## Datenschutz

- Prompts und Bilder bleiben auf deinem Mac. Es gibt kein Konto, keine Cloud, keine Statistik und keine Protokolle.
- Ins Netz geht die App nur nach einem Klick: beim Laden des Modells und beim Laden eines Moduls, jeweils genau diese Dateien von Hugging Face. «Projekt unterstützen» öffnet nur den Browser.
- Der Prompt geht über eine Datei an den Rechenmotor, nicht über die Prozessliste. Die Bilder enthalten keine eingebetteten Angaben zu Prompt oder Einstellungen.

| Was | Ort |
|---|---|
| Bilder, ihre Angaben und die Warteschlange | `~/Downloads/Graphis/` |
| Modell, Module und Messwerte der Zeitschätzung | `~/Library/Application Support/Graphis/` |
| Lizenzen der mitgelieferten Teile | in der App unter Einstellungen > Allgemein > Lizenzen anzeigen |

## Aus dem Quellcode bauen

Du brauchst einen Mac mit Apple Silicon, die Xcode Command Line Tools (`xcode-select --install`), [uv](https://docs.astral.sh/uv/) und beim ersten Bau Internet.

```bash
zsh bauen.sh
```

Das baut `dist/Graphis.app` und `dist/Graphis-<Version>.zip`, nie in einen Programmordner. Python (python-build-standalone 3.12.16, Release 20261026) und die 42 Pakete aus `motor/anforderungen-moss.txt` sind mit SHA-256 festgelegt und landen beim ersten Bau in `.build/downloads`. Bewusst weggelassen sind torch, OpenCV und matplotlib, der Weg von MOSS-Image braucht sie nicht. Jede Mach-O-Datei wird einzeln ad hoc signiert, von innen nach aussen. Alle Dateien im Paket bekommen denselben festen Zeitpunkt, und das ZIP enthält keine erweiterten Attribute und keine Benutzernummern. `THIRD_PARTY_NOTICES.txt` entsteht dabei neu aus dem, was tatsächlich im Paket liegt. Eine andere Version setzt `GRAPHIS_VERSION=1.1 zsh bauen.sh`.

Vier Pakete (hf-xet, hf-transfer, safetensors, tokenizers) enthalten Programmteile aus Rust, in die weitere Bibliotheken und die Rust-Standardbibliothek fest eingebaut sind. Deren Liste und Lizenztexte stehen in `motor/rust-lizenzen.json`, jede Bibliothek mit SHA-256 von crates.io geprüft. Ändert sich eine dieser Programmdateien, bricht der Bau ab, bis die Datei erneuert ist. Das geht mit einem frisch zusammengestellten Motor und braucht Internet und cargo:

```bash
ARBEIT="$(mktemp -d)" && zsh motor/bereitstellen.sh "$ARBEIT/Motor" "$PWD/.build/downloads" \
  && /usr/bin/python3 -I -B motor/rust_lizenzen.py "$ARBEIT/Motor" .build/downloads motor/rust-lizenzen.json
[ -n "$ARBEIT" ] && rm -rf "$ARBEIT"
```

Aufbau des Projekts:

| Ordner | Inhalt |
|---|---|
| `App/` | Quellen der App in Swift und SwiftUI, ohne Xcode-Projekt |
| `motor/` | Startskript und Referenzweg für mflux, Paketliste, Werkzeuge für Bau, Lizenzen und Prüfung des Motors |
| `tests/` | Prüfprogramm, Testserver, Testdaten und Scheinprogramm |
| `werkzeug/` | Zeichnet das App-Symbol, falls `App/AppIcon.icns` fehlt |

## Prüfen

```bash
zsh tests/testlauf.sh
```

Das baut aus den Quellen der App ein eigenes Prüfprogramm ohne den Einstieg der App und lässt es gegen einen lokalen Testserver laufen. Statt des Rechenmotors ruft es ein Scheinprogramm auf, das die Argumente festhält. Es öffnet kein Fenster, braucht weder Grafikchip noch Internet und arbeitet nur in eigenen Ordnern im Ordner für temporäre Dateien. Geprüft werden die Einrichtung des Modells (19 Fälle wie Fortsetzen, Reparatur, falsche Antworten des Servers und Platzmangel, dazu ein Neustart mitten im Laden), die Warteschlange, das Referenzbild, die Erkennung und das Laden von Modulen sowie gespeicherte Daten mit unbekannten oder fehlenden Werten. Der Exitstatus ist nur 0, wenn alles stimmt. Einzelne Teile prüft etwa `zsh tests/testlauf.sh module`. Der Testserver läuft mit `/usr/bin/python3`, ein anderes Python setzt `PYTHON=…`.

Die Prüfhaken gibt es nur im Prüfprogramm (Schalter `TESTLAUF`), die App selbst hat keinen Testmodus.

Den Rechenmotor im fertigen Paket prüft `motor/motorpruefung.py`, ohne ein Bild zu rechnen. Es lädt MLX nur auf dem Prozessor und braucht den Ordner `tokenizer/` des Modells:

```bash
dist/Graphis.app/Contents/Resources/Motor/python/bin/python3.12 -I -B motor/motorpruefung.py \
  dist/Graphis.app/Contents/Resources/Motor <Ordner mit tokenizer/ des Modells> <Testbild.png>
```

Echte Bilder entstehen nur in der App selbst.

## Lizenzen

- Der Code von Graphis steht unter der MIT-Lizenz, siehe `LICENSE`.
- Python und die mitgelieferten Pakete stehen unter ihren eigenen Lizenzen, siehe `THIRD_PARTY_NOTICES.txt`. Das gilt auch für die Rust-Bibliotheken, die in einige Pakete fest eingebaut sind. Die Datei liegt auch im App-Paket.
- Modell und Module liegen nicht im ZIP. Die App lädt sie erst auf deinen Klick von Hugging Face, alle zu einem festen Stand und laut Modellkarte unter Apache 2.0. Die Liste steht ebenfalls in `THIRD_PARTY_NOTICES.txt`.
- Für Module, die du selbst hinzufügst, gilt deren eigene Lizenz. Prüfe sie vor der Nutzung.

## Unterstützen

Graphis ist freie Software und kostet nichts. Wenn du die Entwicklung unterstützen möchtest, freut sich das Projekt über eine Spende:

| Währung | Adresse |
|---|---|
| Bitcoin | `bc1qkgj6wl5sv3yel0v34mexalcesms580367slk9h` |
| Monero | `4AbFvwrC5oEDfZQZoXBMBKia3njagBYeTTbx9sXj7mRCYFxNxnSCDFmVtqRkHvSbUZ8u1xiQDghKv5d7iCd8heu9JcLDc1H` |

Bei Bitcoin sind alle Zahlungen öffentlich einsehbar, Monero hält Absender und Betrag privat.

## Verantwortung

Graphis ist ein Werkzeug. Für die Bilder, die du damit erstellst, und für ihre Verwendung bist du selbst verantwortlich. Achte auf die Rechte anderer, etwa an Personen, Marken und Werken, und auf die Lizenzen der Modelle und Module. Die Software kommt ohne Gewähr, siehe `LICENSE`.
