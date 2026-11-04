import AppKit
import SwiftUI

struct Einstellungsfenster: View {
    var body: some View {
        TabView {
            AllgemeinTab().tabItem { Label("Allgemein", systemImage: "gear") }
            ModelleTab().tabItem { Label("Modelle", systemImage: "slider.horizontal.3") }
            ZeitTab().tabItem { Label("Zeitschätzung", systemImage: "timer") }
            DatenschutzTab().tabItem { Label("Datenschutz", systemImage: "hand.raised") }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 480, idealHeight: 540)
    }
}

private struct AllgemeinTab: View {
    var body: some View {
        Form {
            Section("Bilder") {
                LabeledContent("Speicherort") {
                    Text(Pfade.bilder.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            ModellAbschnitt()
            Section("Technik") {
                Label {
                    Text("Bilder entstehen 100 % lokal, ohne Internet")
                } icon: {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                }
                .foregroundStyle(.secondary)
                Label("Für Apple Silicon optimiert", systemImage: "apple.logo")
                    .foregroundStyle(.secondary)
            }
            Section("Projekt") {
                // Öffnet nur nach einem Klick den Browser. Die App selbst schickt dabei nichts.
                Button("Projekt unterstützen") { NSWorkspace.shared.open(Fassung.unterstuetzen) }
                Text("\(Fassung.name) ist freie Software. Wenn die App dir nützt, kannst du die Entwicklung unterstützen. Der Knopf öffnet die Seite im Browser.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let hinweise = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt") {
                    Button("Lizenzen anzeigen") { NSWorkspace.shared.open(hinweise) }
                }
            }
            Section {
                HStack {
                    Spacer()
                    Text("\(Fassung.name) \(version)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

/// Stand des Modells, mit einer Prüfung auf Wunsch.
private struct ModellAbschnitt: View {
    @ObservedObject private var installation = Modellinstallation.gemeinsam

    private var stand: String {
        switch installation.zustand {
        case .bereit: "Eingerichtet und geprüft"
        case .laedt: "Wird geladen"
        case .prueft(let datei, let von): "Wird geprüft, Datei \(datei) von \(von)"
        case .ungeprueft: "Noch nicht geprüft"
        case .beschaedigt(let anzahl): anzahl == 1 ? "1 Datei fehlt oder ist beschädigt" : "\(anzahl) Dateien fehlen oder sind beschädigt"
        case .fehlt(let vorhanden): vorhanden > 0 ? "Teilweise geladen" : "Noch nicht geladen"
        case .fehler: "Laden unterbrochen"
        }
    }

    var body: some View {
        Section("Modell") {
            LabeledContent("MOSS-Image", value: stand)
            LabeledContent("Speicherort") {
                Text(Pfade.ordner(.moss).path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if FileManager.default.fileExists(atPath: Pfade.ordner(.moss).path) {
                Button("Modelldateien prüfen") { installation.pruefen(erzwingen: true) }
                    .disabled(installation.beschaeftigt)
                Text("Hasht alle Dateien neu, das dauert rund eine Minute. Fehlerhafte lassen sich danach unter Neues Bild reparieren.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ModelleTab: View {
    @EnvironmentObject private var vorgaben: Vorgaben

    var body: some View {
        Form {
            ForEach(ModellID.allCases) { modell in
                Section {
                    ModellRegler(modell: modell)
                }
            }
            Section {
                Button("Standardwerte wiederherstellen") { vorgaben.stufeAnwenden(vorgaben.stufe) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ZeitTab: View {
    @EnvironmentObject private var generator: Generator
    @State private var zeilen: [Zeitzeile] = []
    @State private var bestaetigen = false

    var body: some View {
        Form {
            Section {
                Text("Die App misst jedes Bild und verbessert damit die nächste Schätzung. Gespeichert werden nur Zeiten, keine Prompts oder Bilder.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Gemessene Werte") {
                ForEach(zeilen) { zeile in
                    LabeledContent(zeile.titel) {
                        Text(zeile.wert).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Section {
                Button("Messwerte zurücksetzen", role: .destructive) { bestaetigen = true }
            }
        }
        .formStyle(.grouped)
        .onAppear { zeilen = generator.schaetzer.uebersicht() }
        .confirmationDialog("Alle Messwerte zurücksetzen?", isPresented: $bestaetigen) {
            Button("Zurücksetzen", role: .destructive) {
                generator.schaetzer.zuruecksetzen()
                zeilen = generator.schaetzer.uebersicht()
            }
        } message: {
            Text("Die Schätzung beginnt dann wieder bei den ersten Werten.")
        }
    }
}

private struct DatenschutzTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Datenschutz").font(.title3.weight(.semibold))
                abschnitt("lock.shield.fill", .green, "Alles bleibt auf diesem Mac",
                          "Prompts und erzeugte Bilder werden nur hier verarbeitet. Die Berechnung läuft immer ohne Internet und nie in einer Cloud.")
                abschnitt("network.slash", .blue, "Keine Daten nach aussen",
                          "Die App geht nur ins Netz, wenn du auf Laden klickst: beim ersten Start für das Modell, unter Module für ein Modul. Dann holt sie genau diese Dateien von Hugging Face. Projekt unterstützen öffnet nur den Browser. Prompts und Bilder sind nie beteiligt. Statistik oder Protokolle gibt es nicht.")
                abschnitt("person.crop.circle.badge.xmark", .orange, "Kein Konto",
                          "Für deine Bilder brauchst du weder Konto noch Anmeldung.")
                abschnitt("doc.on.doc", .teal, "Deine Dateien",
                          "Bilder, ihre Einstellungen und die Warteschlange liegen im Ordner Downloads/\(Fassung.ordnerName), die Kopie eines Referenzbildes dort im versteckten Ordner .referenzen. Diese Kopien bleiben dort, auch wenn du ein Bild in den Papierkorb legst. Das Modell liegt unter Library/Application Support/\(Fassung.ordnerName).")
            }
            .padding(20)
        }
    }

    private func abschnitt(_ symbol: String, _ farbe: Color, _ titel: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(titel).font(.callout.weight(.semibold))
            } icon: {
                Image(systemName: symbol).foregroundStyle(farbe)
            }
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1))
    }
}
