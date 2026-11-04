import AppKit
import SwiftUI

struct Einstellungsfenster: View {
    var body: some View {
        TabView {
            AllgemeinTab().tabItem { Label("General", systemImage: "gear") }
            ModelleTab().tabItem { Label("Models", systemImage: "slider.horizontal.3") }
            ZeitTab().tabItem { Label("Time Estimate", systemImage: "timer") }
            DatenschutzTab().tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 480, idealHeight: 540)
    }
}

private struct AllgemeinTab: View {
    @ObservedObject private var versionen = Versionspruefung.gemeinsam

    /// Der Schalter gilt auch als Antwort auf die Frage beim Start.
    private var versionenSuchen: Binding<Bool> {
        Binding(get: { versionen.erlaubt == true }, set: { versionen.erlauben($0) })
    }

    var body: some View {
        Form {
            Section("Images") {
                LabeledContent("Location") {
                    Text(verbatim: Pfade.bilder.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            ModellAbschnitt()
            Section("Technology") {
                Label {
                    Text("Images are made 100 % locally, without internet")
                } icon: {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                }
                .foregroundStyle(.secondary)
                Label("Optimized for Apple Silicon", systemImage: "apple.logo")
                    .foregroundStyle(.secondary)
            }
            Section("New Versions") {
                Toggle("Check for new versions automatically", isOn: versionenSuchen)
                Text("At startup, at most once a day, \(Fassung.name) asks GitHub whether a new version is out, and then shows a note at the bottom right of the window. The app never downloads or installs anything by itself.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Project") {
                // Öffnet nur nach einem Klick den Browser. Die App selbst schickt dabei nichts.
                Button("Support the Project") { NSWorkspace.shared.open(Fassung.unterstuetzen) }
                Text("\(Fassung.name) is free software. If the app is useful to you, you can support its development. The button opens the page in the browser.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let hinweise = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt") {
                    Button("Show Licenses") { NSWorkspace.shared.open(hinweise) }
                }
            }
            Section {
                HStack {
                    Spacer()
                    Text(verbatim: "\(Fassung.name) \(Fassung.version)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Stand des Modells, mit einer Prüfung auf Wunsch.
private struct ModellAbschnitt: View {
    @ObservedObject private var installation = Modellinstallation.gemeinsam

    private var stand: String {
        switch installation.zustand {
        case .bereit: String(localized: "Set up and checked")
        case .laedt: String(localized: "Downloading")
        case .prueft(let datei, let von): String(localized: "Checking, file \(datei) of \(von)")
        case .ungeprueft: String(localized: "Not checked yet")
        case .beschaedigt(let anzahl): anzahl == 1 ? String(localized: "1 file is missing or damaged")
            : String(localized: "\(anzahl) files are missing or damaged")
        case .fehlt(let vorhanden): vorhanden > 0 ? String(localized: "Partly downloaded") : String(localized: "Not downloaded yet")
        case .fehler: String(localized: "Download interrupted")
        }
    }

    var body: some View {
        Section("Model") {
            LabeledContent(ModellID.moss.name, value: stand)
            LabeledContent("Location") {
                Text(verbatim: Pfade.ordner(.moss).path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if FileManager.default.fileExists(atPath: Pfade.ordner(.moss).path) {
                Button("Check Model Files") { installation.pruefen(erzwingen: true) }
                    .disabled(installation.beschaeftigt)
                Text("Checks all files again, which takes about a minute. Faulty ones can then be repaired under New Image.")
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
                Button("Restore Defaults") { vorgaben.stufeAnwenden(vorgaben.stufe) }
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
                Text("The app measures every image and uses it to improve the next estimate. Only times are saved, no prompts or images.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Measured Values") {
                ForEach(zeilen) { zeile in
                    LabeledContent(zeile.titel) {
                        Text(verbatim: zeile.wert).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Section {
                Button("Reset Measurements", role: .destructive) { bestaetigen = true }
            }
        }
        .formStyle(.grouped)
        .onAppear { zeilen = generator.schaetzer.uebersicht() }
        .confirmationDialog("Reset all measurements?", isPresented: $bestaetigen) {
            Button("Reset", role: .destructive) {
                generator.schaetzer.zuruecksetzen()
                zeilen = generator.schaetzer.uebersicht()
            }
        } message: {
            Text("The estimate then starts again from the initial values.")
        }
    }
}

private struct DatenschutzTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy").font(.title3.weight(.semibold))
                abschnitt("lock.shield.fill", .green, "Everything stays on this Mac",
                          "Prompts and created images are only processed here. The calculation always runs without internet and never in a cloud.")
                abschnitt("network.slash", .blue, "No data goes out",
                          "The app only goes online when you click Download: on first start for the model, under Modules for a module. It then fetches exactly these files from Hugging Face. If you allowed the search for new versions, it also asks GitHub at startup, at most once a day, for the latest version. Nothing about you goes along, and like any website, GitHub only sees your IP address. Donate and Support the Project only open the browser. Prompts and images are never involved. There are no statistics or logs.")
                abschnitt("person.crop.circle.badge.xmark", .orange, "No account",
                          "You need neither an account nor a sign-in for your images.")
                abschnitt("doc.on.doc", .teal, "Your files",
                          "Images, their settings and the queue are in the folder Downloads/\(Fassung.ordnerName), the copy of a reference image there in the hidden folder .referenzen. These copies stay there, even if you move an image to the Trash. The model is in Library/Application Support/\(Fassung.ordnerName).")
            }
            .padding(20)
        }
    }

    private func abschnitt(_ symbol: String, _ farbe: Color, _ titel: LocalizedStringKey,
                           _ text: LocalizedStringKey) -> some View {
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
