import Foundation

/// Lernt aus jedem Bild, wie lange ein Rechenschritt dauert, und speichert nur Zahlen.
struct Messwert: Codable {
    /// Sekunden je Schritt, normiert auf einen Durchgang und ein Megapixel.
    var schrittzeit: Double
    /// Sekunden ausserhalb der Schritte, also Laden und Fertigstellen.
    var grundzeit: Double
    /// Typische Abweichung der letzten Schätzungen in Sekunden.
    var abweichung: Double?
    var anzahl: Int
}

final class Zeitschaetzer {
    private var werte: [String: Messwert]

    /// Startwerte, gemessen im November 2026 auf einem Mac mit Apple Silicon. Danach lernt die App aus jedem Bild.
    private static let startwerte: [String: Messwert] = [
        "moss.gross": Messwert(schrittzeit: 9.7, grundzeit: 17, anzahl: 0),
        "moss.klein": Messwert(schrittzeit: 9.5, grundzeit: 12, anzahl: 0),
        "moss.turbo.gross": Messwert(schrittzeit: 11.0, grundzeit: 14, anzahl: 0),
        "moss.turbo.klein": Messwert(schrittzeit: 10.0, grundzeit: 13, anzahl: 0),
    ]

    init() {
        let gespeichert = (try? Data(contentsOf: Pfade.messwerte))
            .flatMap { try? JSONDecoder().decode([String: Messwert].self, from: $0) } ?? [:]
        werte = Self.startwerte.merging(gespeichert) { _, neu in neu }
    }

    /// Bildgrössen unter 0,75 Megapixel zählen als klein, grössere als gross.
    private func schluessel(_ auftrag: Auftrag) -> String {
        let art = auftrag.turbo ? ".turbo" : (auftrag.referenzen.isEmpty ? "" : ".ref")
        return "\(auftrag.modell.rawValue)\(art).\(megapixel(auftrag) < 0.75 ? "klein" : "gross")"
    }

    func messwert(_ auftrag: Auftrag) -> Messwert {
        werte[schluessel(auftrag)] ?? Messwert(schrittzeit: 13, grundzeit: 25, anzahl: 0)
    }

    private func megapixel(_ auftrag: Auftrag) -> Double {
        Double(auftrag.breite * auftrag.hoehe) / 1_048_576
    }

    func schaetzung(_ auftrag: Auftrag) -> Double {
        let wert = messwert(auftrag)
        let schritte = Double(auftrag.rechenSchritte * auftrag.durchgaenge) * megapixel(auftrag) * wert.schrittzeit
        return wert.grundzeit + schritte
    }

    /// Neue Messungen zählen stark, damit sich die Schätzung nach wenigen Bildern einpendelt.
    /// Ausreisser, etwa weil gleichzeitig etwas anderes rechnete, werden begrenzt.
    func lernen(_ auftrag: Auftrag, gesamt: Double, schrittzeit: Double?, geschaetzt: Double) {
        let key = schluessel(auftrag)
        var wert = werte[key] ?? messwert(auftrag)
        let gewicht = wert.anzahl == 0 ? 0.6 : 0.35
        let aufwand = Double(auftrag.durchgaenge) * megapixel(auftrag)
        let begrenzt = min(max(gesamt, geschaetzt / 3), geschaetzt * 3)
        let schritte = Double(auftrag.rechenSchritte)
        if let schrittzeit {
            let gemessen = min(schrittzeit, begrenzt / schritte)
            wert.schrittzeit += gewicht * (gemessen / aufwand - wert.schrittzeit)
            wert.grundzeit += gewicht * (max(begrenzt - gemessen * schritte, 0) - wert.grundzeit)
        } else {
            // Ohne Schrittzeit lässt sich die Messung nicht aufteilen, beide Teile wandern mit.
            let verhaeltnis = begrenzt / max(geschaetzt, 1)
            wert.schrittzeit *= 1 + gewicht * (verhaeltnis - 1)
            wert.grundzeit *= 1 + gewicht * (verhaeltnis - 1)
        }
        let fehler = abs(gesamt - geschaetzt)
        wert.abweichung = wert.abweichung.map { $0 + gewicht * (fehler - $0) } ?? fehler
        wert.anzahl += 1
        werte[key] = wert
        speichern()
    }

    func zuruecksetzen() {
        werte = Self.startwerte
        try? FileManager.default.removeItem(at: Pfade.messwerte)
    }

    func uebersicht() -> [Zeitzeile] {
        ModellID.allCases.flatMap { modell -> [Zeitzeile] in
            let fälle = [("turbo.klein", "Turbo, klein"), ("turbo.gross", "Turbo, gross"),
                         ("klein", "voll, klein"), ("gross", "voll, gross")]
            return fälle.compactMap { teil, name in
                guard let wert = werte["\(modell.rawValue).\(teil)"] else { return nil }
                let basis = wert.anzahl > 0 ? "\(wert.anzahl) Mal gemessen" : "noch nicht gemessen"
                let genauigkeit = wert.abweichung.map { ", ± \(dauerText($0))" } ?? ""
                return Zeitzeile(id: "\(modell.rawValue).\(teil)", titel: "\(modell.name), \(name)",
                                 wert: String(format: "%.1f s je Schritt, ", wert.schrittzeit) + basis + genauigkeit)
            }
        }
    }

    private func speichern() {
        let ordner = Pfade.messwerte.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        if let daten = try? JSONEncoder().encode(werte) {
            try? daten.write(to: Pfade.messwerte, options: .atomic)
        }
    }
}

struct Zeitzeile: Identifiable {
    let id: String
    let titel: String
    let wert: String
}

func dauerText(_ sekunden: Double) -> String {
    let gerundet = Int(sekunden.rounded())
    if gerundet < 60 { return "\(gerundet) s" }
    if gerundet < 3600 { return "\(gerundet / 60) Min \(String(format: "%02d", gerundet % 60)) s" }
    return "\(gerundet / 3600) Std \(String(format: "%02d", gerundet % 3600 / 60)) Min"
}
