import AppKit
import Foundation

/// Prüft das Referenzbild: Auf jedem Weg bleibt es bei höchstens einem Bild, beim Hinzufügen, bei der Dateiauswahl,
/// beim Ablegen, beim direkten Setzen, in den Aufträgen, beim Rechnen und beim Übernehmen.
@MainActor
enum ReferenzPruefung {
    static func ausfuehren(_ bericht: Pruefbericht) async {
        let generator = Generator()
        let vorgaben = Vorgaben.gemeinsam
        await vorgaben.moduleNeuLaden()
        vorgaben.stufeAnwenden(.standard)
        let ablage = Testumgebung.ordner.appendingPathComponent("Testvorlagen", isDirectory: true)
        let hoch = Hilfe.testbild("hoch.png", 600, 900, .systemRed, in: ablage)
        let quer = Hilfe.testbild("quer.png", 900, 600, .systemGreen, in: ablage)
        let quadrat = Hilfe.testbild("quadrat.png", 500, 500, .systemBlue, in: ablage)
        let keinBild = ablage.appendingPathComponent("kein-bild.png")
        try? "kein Bild".write(to: keinBild, atomically: true, encoding: .utf8)

        // Hinzufügen nimmt höchstens ein Bild, ein volles Referenzbild nimmt keines mehr.
        vorgaben.referenzenLeeren()
        vorgaben.referenzenHinzufuegen([hoch, quer, quadrat])
        let erstes = vorgaben.referenzen
        let meldungMehrere = vorgaben.referenzMeldung ?? ""
        vorgaben.referenzenHinzufuegen([quer])
        let meldungVoll = vorgaben.referenzMeldung ?? ""
        bericht.pruefen("Hinzufügen nimmt höchstens ein Bild", erstes == [hoch] && vorgaben.referenzen == [hoch]
                        && meldungMehrere.contains("2 more images were not added")
                        && meldungVoll.hasPrefix("Only one reference image is possible."), "\(meldungMehrere) | \(meldungVoll)")

        // Dateiauswahl und Ablegen setzen das Bild über vorlageSetzen: Es ersetzt das bisherige.
        vorgaben.vorlageSetzen(quer)
        let ersetzt = vorgaben.referenzen == [quer] && vorgaben.referenzMeldung == nil
        vorgaben.vorlageSetzen(keinBild)
        let unlesbarGesetzt = vorgaben.referenzen == [quer] && vorgaben.referenzMeldung == "This file is not a readable image."
        vorgaben.referenzenLeeren()
        vorgaben.referenzenHinzufuegen([keinBild])
        let unlesbarHinzu = vorgaben.referenzen.isEmpty && vorgaben.referenzMeldung == "One file is not a readable image."
        vorgaben.referenzenHinzufuegen([URL(string: "https://example.org/bild.png")!])
        let adresse = vorgaben.referenzen.isEmpty
        bericht.pruefen("Anderes Bild ersetzt, Unlesbares und Web-Adressen kommen nicht dazu",
                        ersetzt && unlesbarGesetzt && unlesbarHinzu && adresse,
                        "ersetzt \(ersetzt), unlesbar gesetzt \(unlesbarGesetzt), unlesbar hinzu \(unlesbarHinzu), Adresse \(adresse)")

        // Auch eine direkt gesetzte Liste hält nie mehr als ein Bild.
        vorgaben.referenzen = [hoch, quer, quadrat]
        let direkt = vorgaben.referenzen
        vorgaben.referenzEntfernen(0)
        bericht.pruefen("Liste hält nie mehr als ein Bild", direkt == [hoch] && vorgaben.referenzen.isEmpty, "\(direkt.count) Bilder")

        // Aufträge mit Vorlage: ein Bild, Nähe und Seitenverhältnis der Vorlage.
        vorgaben.vorlageSetzen(hoch)
        vorgaben.referenzStaerke = 0.5
        vorgaben.anzahl = 2
        vorgaben.festerStartwert = true
        vorgaben.startwert = 4711
        vorgaben.laengeSeite = 1024
        vorgaben.format = .quer
        vorgaben.negativ = ""
        vorgaben.prompt = "Prüfbild mit Vorlage"
        let liste = vorgaben.auftragsliste()
        bericht.pruefen("Aufträge mit Vorlage", liste.count == 2 && liste.allSatisfy { $0.referenzen == [hoch]
                        && $0.referenzStaerke == 0.5 && $0.breite == 688 && $0.hoehe == 1024 } && liste.map(\.seed) == [4711, 4712]
                        && !vorgaben.formatGenutzt,
                        "\(liste.map { "\($0.referenzen.count) Bild, \($0.breite)x\($0.hoehe), Startwert \($0.seed)" })")

        let bereit = await Hilfe.einrichten()
        bericht.pruefen("Einrichtung vom Testserver", bereit, "\(Modellinstallation.gemeinsam.zustand)")
        guard bereit else { return }

        // Rechnen: Das Referenzbild wird einmal kopiert, und jeder Aufruf nennt genau diese Kopie.
        var stand = Hilfe.aufrufe().count
        await generator.starten(liste, laengeSeite: 1024)
        await Hilfe.fertig(generator)
        let neue = Array(Hilfe.aufrufe().dropFirst(stand))
        let kopien = ((try? FileManager.default.contentsOfDirectory(atPath: Pfade.referenzen.path)) ?? []).sorted()
        // So wie der Verlauf sie zeigt: in der Reihenfolge, in der sie entstanden.
        let lauf = generator.laeufe.first { $0.id == liste[0].gruppe }?.ergebnisse ?? []
        guard kopien.count == 1, let kopie = Pfade.referenzKopie(kopien[0]) else {
            bericht.pruefen("Referenzbild eingefroren", false, "Kopien \(kopien), Fehler \(generator.fehler ?? "keiner")")
            return
        }
        bericht.pruefen("Referenzbild einmal eingefroren", kopie != hoch && lauf.count == 2
                        && lauf.allSatisfy { $0.referenzDateien == [kopie.lastPathComponent] && $0.referenzen == 1
                            && $0.referenzStaerke == 0.5 },
                        "Kopien \(kopien.count), Bilder \(lauf.count)")
        bericht.pruefen("Aufruf mit genau einem Referenzbild", neue.count == 2 && neue.allSatisfy { zeile in
            zeile.contains("/Motor/motor_start.py referenz --model ") && zeile.contains(" --image \(kopie.path) 0.5")
                && zeile.components(separatedBy: " --image ").count == 2 && !zeile.contains("--image-paths")
                && !zeile.contains(hoch.path) && zeile.contains("--width 688 --height 1024")
        }, neue.first ?? "kein Aufruf")

        // Lässt sich das Bild nicht lesen, reiht sich nichts ein, und keine Kopie bleibt liegen.
        let weg = Hilfe.testbild("weg.png", 300, 300, .systemTeal, in: ablage)
        vorgaben.anzahl = 1
        vorgaben.vorlageSetzen(weg)
        try? FileManager.default.removeItem(at: weg)
        let kopienVorher = Set((try? FileManager.default.contentsOfDirectory(atPath: Pfade.referenzen.path)) ?? [])
        stand = Hilfe.aufrufe().count
        generator.fehler = nil
        await generator.starten(vorgaben.auftragsliste(), laengeSeite: 1024)
        let kopienNachher = Set((try? FileManager.default.contentsOfDirectory(atPath: Pfade.referenzen.path)) ?? [])
        bericht.pruefen("Fehlendes Referenzbild hält den Start auf",
                        generator.fehler == "The reference image could not be read. Is it still in the same place?"
                        && kopienNachher == kopienVorher && generator.warteschlange.isEmpty && !generator.laeuft
                        && Hilfe.aufrufe().count == stand, generator.fehler ?? "kein Fehler")
        generator.fehler = nil

        // Übernehmen: Nur das erste Referenzbild kommt zurück, und nur als Kopie aus dem Bildordner.
        let zweite = Hilfe.testbild("zweite.png", 500, 500, .systemPurple, in: Pfade.referenzen)
        func bild(_ namen: [String]?, alt: String? = nil, anzahl: Int, seed: Int = 1) -> Ergebnis {
            Ergebnis(datei: "u\(seed).png", gruppe: UUID(), prompt: "Übernahme", negativ: "", modell: .moss, seed: seed,
                     breite: 688, hoehe: 1024, schritte: 8, textfuehrung: 1, sekunden: 1, geschaetzt: 1, referenzen: anzahl,
                     auftrag: UUID(), referenzStaerke: 0.375, referenzDatei: alt ?? namen?.first, formatName: "Quadrat",
                     referenzDateien: namen)
        }
        vorgaben.uebernehmen(bild([kopie.lastPathComponent, zweite.lastPathComponent], anzahl: 2))
        let zwei = vorgaben.referenzen == [kopie] && vorgaben.uebernahmeLuecken.isEmpty && vorgaben.referenzStaerke == 0.375
        vorgaben.uebernehmen(bild(nil, alt: zweite.lastPathComponent, anzahl: 1))
        let nurDatei = vorgaben.referenzen == [zweite] && vorgaben.uebernahmeLuecken.isEmpty
        bericht.pruefen("Übernahme nimmt nur das erste Referenzbild", zwei && nurDatei,
                        "zwei gespeichert \(zwei), nur referenzDatei \(nurDatei), Lücken \(vorgaben.uebernahmeLuecken)")

        let fehlt = "The reference image of this image is no longer available."
        vorgaben.uebernehmen(bild(["fehlt-\(UUID().uuidString).png"], anzahl: 1))
        let fehlend = vorgaben.referenzen.isEmpty && vorgaben.uebernahmeLuecken.contains(fehlt)
        vorgaben.uebernehmen(bild(["../hoch.png"], anzahl: 1))
        let ausserhalb = vorgaben.referenzen.isEmpty && vorgaben.uebernahmeLuecken.contains(fehlt)
        vorgaben.uebernehmen(bild(nil, anzahl: 1))
        let ohneName = vorgaben.referenzen.isEmpty && vorgaben.uebernahmeLuecken.contains(fehlt)
        bericht.pruefen("Fehlende oder fremde Kopie kommt nicht zurück", fehlend && ausserhalb && ohneName,
                        "fehlt \(fehlend), ausserhalb \(ausserhalb), ohne Namen \(ohneName)")

        vorgaben.uebernehmen([bild([kopie.lastPathComponent], anzahl: 1, seed: 1), bild([zweite.lastPathComponent], anzahl: 1, seed: 2)])
        bericht.pruefen("Verschiedene Referenzbilder in einer Generierung", vorgaben.referenzen.isEmpty
                        && vorgaben.uebernahmeLuecken.contains { $0.contains("different reference images") }, "\(vorgaben.uebernahmeLuecken)")

        // Ein ganzer Lauf mit Vorlage kommt mit Kopie, Grösse, Nähe und Serie zurück.
        vorgaben.referenzenLeeren()
        vorgaben.anzahl = 1
        vorgaben.startwert = 1
        vorgaben.format = .quadrat
        vorgaben.laengeSeite = 768
        vorgaben.uebernehmen(lauf)
        let wieder = vorgaben.auftragsliste()
        bericht.pruefen("Übernahme eines Laufs mit Vorlage", vorgaben.referenzen == [kopie] && vorgaben.anzahl == 2
                        && vorgaben.startwert == 4711 && vorgaben.referenzStaerke == 0.5 && wieder.count == 2
                        && wieder.allSatisfy { $0.referenzen == [kopie] && $0.breite == 688 && $0.hoehe == 1024 },
                        "Referenzen \(vorgaben.referenzen.count), Anzahl \(vorgaben.anzahl), Lücken \(vorgaben.uebernahmeLuecken)")
    }
}
