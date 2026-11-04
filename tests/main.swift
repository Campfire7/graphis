import Foundation

// Prüfprogramm für Graphis, ohne App-Fenster und ohne Grafikchip. tests/testlauf.sh baut es aus den Quellen der App
// ohne deren Einstieg und ruft es je Art einmal mit einem eigenen, frischen Testordner auf: graphis-test ART
// Exitstatus: 0 alle Prüfungen ok, 1 mindestens eine fehlgeschlagen, 2 falsche Angaben, 3 Zeitlimit überschritten.

// Zuerst die Angaben, noch bevor irgendein Teil der App startet.
Testumgebung.pruefen()

let arten: [String: (frist: Double, lauf: @MainActor (Pruefbericht) async -> Void)] = [
    "einrichtung": (300, EinrichtungPruefung.ausfuehren),
    "neustart-fortsetzen": (60, EinrichtungPruefung.neustartFortsetzen),
    "warteschlange": (180, WarteschlangePruefung.ausfuehren),
    "referenzen": (120, ReferenzPruefung.ausfuehren),
    "module": (120, ModulPruefung.ausfuehren),
    "daten": (60, DatenPruefung.ausfuehren),
    "updates": (60, VersionenPruefung.ausfuehren),
    "ansichten": (90, AnsichtenZeichnen.ausfuehren),
    "screenshots": (120, Bildschirmfotos.ausfuehren),
]
let art = CommandLine.arguments.dropFirst().first ?? ""

func zeitlimit(_ sekunden: Double) {
    DispatchQueue.global().asyncAfter(deadline: .now() + sekunden) {
        print("FEHLER Zeitlimit von \(Int(sekunden)) s überschritten")
        fflush(stdout)
        // Ein laufendes Scheinprogramm endet mit, sonst liefe es verwaist weiter.
        let ende = Process()
        ende.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        ende.arguments = ["-P", String(getpid())]
        try? ende.run()
        ende.waitUntilExit()
        exit(3)
    }
}

if art == "neustart-beginnen" {
    // Bleibt stehen, bis testlauf.sh den Prozess beendet. Das Zeitlimit fängt ab, falls das nie geschieht.
    zeitlimit(60)
    Task { @MainActor in await EinrichtungPruefung.neustartBeginnen() }
} else if let gewaehlt = arten[art] {
    zeitlimit(gewaehlt.frist)
    Task { @MainActor in
        let bericht = Pruefbericht()
        await gewaehlt.lauf(bericht)
        print("\(bericht.anzahl) Prüfungen, \(bericht.fehler) fehlgeschlagen")
        fflush(stdout)
        exit(bericht.fehler == 0 && bericht.anzahl > 0 ? 0 : 1)
    }
} else {
    Testumgebung.abbrechen("Unbekannte Art \(art). Bekannt: \((arten.keys + ["neustart-beginnen"]).sorted().joined(separator: ", ")).")
}
// dispatchMain gibt den Hauptthread auf, die Hauptwarteschlange läuft danach auf einem anderen Thread. Zum Zeichnen
// braucht AppKit aber den echten Hauptthread, dort läuft dann die Hauptschleife.
if art == "ansichten" || art == "screenshots" {
    RunLoop.main.run()
} else {
    dispatchMain()
}
