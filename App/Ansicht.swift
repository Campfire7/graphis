import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Auswahl: Hashable {
    case neu
    case module
    case lauf(UUID)
}

struct Hauptansicht: View {
    @EnvironmentObject private var generator: Generator
    @State private var auswahl: Auswahl? = .neu
    @State private var flaeche = CGSize(width: 1180, height: 820)

    /// Bleibt beim Schliessen stehen, damit das Blatt nicht leer wegfährt.
    @State private var letztesGrossBild: Ergebnis?

    /// Am Bild hängt nur der Inhalt: Mit sheet(item:) ginge das Blatt bei jedem Wechsel neu auf.
    private var grossOffen: Binding<Bool> {
        Binding(get: { generator.grossBild != nil }, set: { if !$0 { generator.grossBild = nil } })
    }

    var body: some View {
        NavigationSplitView {
            Seitenleiste(auswahl: $auswahl)
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 400)
        } detail: {
            detail
                .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(Fassung.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) { werkzeuge }
        }
        .onChange(of: generator.sprungZu) { _, gruppe in
            if let gruppe { auswahl = .lauf(gruppe) }
        }
        .onChange(of: generator.laeufe.map(\.id)) { _, ids in
            // Abgebrochen, entfernt oder fehlgeschlagen, bevor ein Bild entstand.
            if case .lauf(let id) = auswahl, !ids.contains(id) { auswahl = .neu }
        }
        .onChange(of: generator.grossBild) { _, bild in
            guard let bild else { return }
            letztesGrossBild = bild
            // Der Verlauf läuft beim Blättern mit, nach dem Schliessen steht man bei der zuletzt gezeigten Generierung.
            auswahl = .lauf(bild.gruppe)
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { flaeche = $0 }
        .sheet(isPresented: grossOffen) {
            if let bild = generator.grossBild ?? letztesGrossBild {
                BildDetail(ergebnis: bild, neuBeginnen: { auswahl = .neu })
                    .frame(width: max(860, flaeche.width - 40), height: max(600, flaeche.height - 40))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch auswahl {
        case .lauf(let gruppe):
            LaufAnsicht(gruppe: gruppe, neuBeginnen: { auswahl = .neu })
        case .module:
            ModulBereich()
        default:
            NeuAnsicht(zeigeModule: { auswahl = .module }, zeigeLauf: { auswahl = .lauf($0) })
        }
    }

    @ViewBuilder
    private var werkzeuge: some View {
        Button {
            auswahl = .neu
        } label: {
            Label("Neues Bild", systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
        .help("Neues Bild (⌘N)")

        Button {
            NSWorkspace.shared.open(Pfade.bilder)
        } label: {
            Label("Bildordner", systemImage: "folder")
        }
        .help("Bildordner im Finder öffnen")

        SettingsLink {
            Label("Einstellungen", systemImage: "gearshape")
        }
        .help("Einstellungen (⌘,)")
    }
}

/// Fügt eigene Moduldateien hinzu und schaltet sie gleich ein.
@MainActor
func moduleWaehlen(_ vorgaben: Vorgaben) {
    let dialog = NSOpenPanel()
    dialog.allowsMultipleSelection = true
    dialog.allowedContentTypes = [UTType(filenameExtension: "safetensors") ?? .data]
    guard dialog.runModal() == .OK else { return }
    vorgaben.moduleHinzufuegen(dialog.urls)
}

// MARK: Seitenleiste

struct Seitenleiste: View {
    @EnvironmentObject private var generator: Generator
    @Binding var auswahl: Auswahl?
    @State private var leerenFragen = false

    var body: some View {
        VStack(spacing: 0) {
            liste
            if !generator.warteschlange.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: generator.pausiert ? "pause.circle" : "clock")
                            .foregroundStyle(.blue).font(.caption)
                        Text(generator.pausiert ? "\(generator.warteschlange.count) angehalten"
                             : "\(generator.warteschlange.count) in der Warteschlange")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button("Leeren") { leerenFragen = true }
                            .buttonStyle(.link).font(.caption)
                    }
                    if generator.pausiert {
                        Button("Weiterrechnen") { generator.weiterrechnen() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .confirmationDialog("Warteschlange leeren?", isPresented: $leerenFragen) {
            Button("Leeren", role: .destructive) { generator.warteschlangeLeeren() }
        } message: {
            Text("Die Prompts in der Warteschlange gehen dabei verloren.")
        }
    }

    private var liste: some View {
        ScrollViewReader { rolle in
            eintraege.onChange(of: auswahl) { _, neu in
                if case .lauf(let id) = neu { rolle.scrollTo(id) }
            }
        }
    }

    private var eintraege: some View {
        List(selection: $auswahl) {
            Section {
                SeitenZeile(titel: "Neues Bild", symbol: "sparkles", aktiv: auswahl == .neu).tag(Auswahl.neu)
                SeitenZeile(titel: "Module", symbol: "puzzlepiece.extension", aktiv: auswahl == .module)
                    .tag(Auswahl.module)
            }
            if generator.laeufe.isEmpty && generator.aktiveGruppe == nil {
                Section {
                    VStack(spacing: 6) {
                        Text("Noch keine Bilder").font(.subheadline).foregroundStyle(.secondary)
                        Text("Fertige Bilder erscheinen hier.").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(generator.laeufe) { lauf in
                        LaufZeile(lauf: lauf, aktiv: auswahl == .lauf(lauf.id))
                            .tag(Auswahl.lauf(lauf.id))
                            .id(lauf.id)
                            .contextMenu {
                                if generator.platz(lauf.id) != nil {
                                    Button {
                                        generator.ausWarteschlangeEntfernen(lauf.id)
                                    } label: {
                                        Label("Aus Warteschlange entfernen", systemImage: "xmark.circle")
                                    }
                                } else {
                                    Button(role: .destructive) {
                                        if auswahl == .lauf(lauf.id) { auswahl = .neu }
                                        generator.inPapierkorb(lauf)
                                    } label: {
                                        Label("In den Papierkorb", systemImage: "trash")
                                    }
                                    .disabled(lauf.id == generator.aktiveGruppe)
                                }
                            }
                    }
                } header: {
                    Text("Verlauf").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SeitenZeile: View {
    let titel: String
    let symbol: String
    let aktiv: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 28, height: 28)
                Image(systemName: symbol).foregroundStyle(Color.accentColor).font(.system(size: 11))
            }
            Text(titel)
                .font(.callout)
                .fontWeight(aktiv ? .semibold : .regular)
                .foregroundStyle(aktiv ? .primary : .secondary)
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct LaufZeile: View {
    @EnvironmentObject private var generator: Generator
    let lauf: Lauf
    let aktiv: Bool

    private var rechnet: Bool { lauf.id == generator.aktiveGruppe }
    private var platz: Int? { generator.platz(lauf.id) }
    private var fehlgeschlagen: Bool { generator.fehlerLauf == lauf.id }

    private var status: String {
        if fehlgeschlagen { return "Fehlgeschlagen" }
        if let platz {
            return generator.pausiert ? "Angehalten, Platz \(platz)" : "In Warteschlange, Platz \(platz)"
        }
        return rechnet ? "Wird erzeugt" : lauf.untertitel
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if fehlgeschlagen {
                    Circle().fill(Color.red.opacity(0.2)).frame(width: 32, height: 32)
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red).font(.system(size: 14))
                } else if platz != nil {
                    Circle().fill(Color.blue.opacity(0.2)).frame(width: 32, height: 32)
                    Image(systemName: "clock").foregroundStyle(.blue).font(.system(size: 14))
                } else if rechnet && lauf.ergebnisse.isEmpty {
                    Circle().fill(Color.orange.opacity(0.2)).frame(width: 32, height: 32)
                    ProgressView().controlSize(.mini)
                } else if let erstes = lauf.ergebnisse.first {
                    Vorschaubild(url: Pfade.bilder.appendingPathComponent(erstes.datei), kante: 96, fuellen: true)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(lauf.prompt)
                    .font(.callout)
                    .fontWeight(aktiv ? .semibold : .regular)
                    .lineLimit(1)
                    .foregroundStyle(aktiv ? .primary : .secondary)
                HStack(spacing: 4) {
                    Text(status)
                        .font(.caption2).foregroundStyle(.secondary)
                    if !rechnet && platz == nil {
                        Text("• \(dauerText(lauf.dauer))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lauf.prompt), \(status)")
    }
}

// MARK: Neues Bild

struct NeuAnsicht: View {
    @EnvironmentObject private var generator: Generator
    @EnvironmentObject private var vorgaben: Vorgaben
    @ObservedObject private var installation = Modellinstallation.gemeinsam
    @FocusState private var promptFokus: Bool
    @FocusState private var negativFokus: Bool
    @State private var lokalInfo = false
    /// Grund, warum gerade nichts gerechnet werden kann.
    @State private var stoerung: String?
    /// Sperrt den Knopf kurz nach einem Klick, damit ein Doppelklick nicht zwei Aufträge anlegt.
    @State private var klickGesperrt = false
    /// Platz des zuletzt eingereihten Auftrags, solange die Bestätigung sichtbar ist.
    @State private var eingereiht: Int?
    @State private var klickAufgabe: Task<Void, Never>?
    var zeigeModule: () -> Void = {}
    var zeigeLauf: (UUID) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if !installation.bereit { EinrichtungKarte() }
                if vorgaben.vonBildUebernommen { uebernahmeHinweis }
                eingabeKarte
                referenzKarte
                qualitaetKarte
                modellKarte
                modulKarte
                bildKarte
                if let abweichung = generator.letzteAbweichung {
                    Text(abweichung).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(maxWidth: kartenBreite)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { startBereich }
        .onAppear {
            promptFokus = true
            bereitschaftPruefen()
        }
        .onChange(of: vorgaben.aktuelleStufe) { bereitschaftPruefen() }
        .onChange(of: turboNoetig) { bereitschaftPruefen() }
        .onChange(of: vorgaben.aktiv) { bereitschaftPruefen() }
        .onChange(of: vorgaben.referenzen) { bereitschaftPruefen() }
        .onChange(of: installation.zustand) { bereitschaftPruefen() }
    }

    private var turboNoetig: Bool {
        vorgaben.modelle.contains { vorgaben.einstellung($0).turbo }
    }

    /// Liest Dateien, darum nur beim Erscheinen und bei einem Wechsel der Stufe, nie bei jedem Neuzeichnen.
    private func bereitschaftPruefen() {
        let dateien = FileManager.default
        let turbo = Pfade.module.appendingPathComponent(Modul.turboDatei)
        installation.auffrischen()
        // Derselbe Aufruf wie im Generator, mit Referenzbild über das Zusatzprogramm. Beides muss im Paket liegen.
        let aufruf = Pfade.aufruf(mitReferenz: !vorgaben.referenzen.isEmpty)
        if !installation.bereit {
            // Die Karte oben sagt, was zu tun ist. Hier steht nur, warum der Knopf gesperrt ist.
            stoerung = "MOSS-Image ist noch nicht eingerichtet. Lade es oben in der Karte."
        } else if !dateien.isExecutableFile(atPath: aufruf.programm)
                    || aufruf.vorweg.contains(where: { $0.hasSuffix(".py") && !dateien.fileExists(atPath: $0) }) {
            stoerung = "Der Rechenmotor im App-Paket fehlt oder ist beschädigt. Lade die App neu herunter."
        } else if turboNoetig && !dateien.fileExists(atPath: turbo.path) {
            stoerung = "Das Turbo-Modul fehlt. Wähle die Stufe Beste, dann rechnet die App ohne Turbo."
        } else {
            stoerung = nil
        }
    }

    private var uebernahmeHinweis: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Die Einstellungen stammen von der gewählten Generierung, auch die Zufallszahl. Ändere eine Sache, der Rest bleibt gleich.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(vorgaben.uebernahmeLuecken, id: \.self) { luecke in
                    Text(verbatim: luecke).font(.caption).foregroundStyle(.orange)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                vorgaben.vonBildUebernommen = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Hinweis schliessen")
        }
        .padding(.horizontal, 4)
    }

    private var referenzKarte: some View {
        Karte {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    KartenTitel(text: "Referenzbild (optional)", symbol: "photo.on.rectangle", farbe: .orange)
                    InfoKnopf(titel: "Referenzbild", beschreibung: Self.referenzInfo)
                    Spacer()
                    if !vorgaben.referenzen.isEmpty {
                        Button("Alle entfernen") { vorgaben.referenzenLeeren() }
                            .buttonStyle(.link).font(.caption)
                        // Mit nur einem Platz ersetzt ein neues Bild das alte.
                        Button("Anderes Bild …", action: referenzWaehlen)
                            .buttonStyle(.link).font(.caption)
                    } else {
                        Button("Bild hinzufügen …", action: referenzWaehlen)
                            .buttonStyle(.link).font(.caption)
                    }
                }
                if let bild = vorgaben.vorlage {
                    referenzVorschau(bild)
                    referenzHinweise
                } else {
                    Text("Ziehe ein Bild hierher, oder wähle es aus.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let meldung = vorgaben.referenzMeldung {
                    Text(verbatim: meldung).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // Kommen mehrere Bilder an, zählt das erste.
        .dropDestination(for: URL.self) { urls, _ in
            guard let erstes = urls.first else { return false }
            vorgaben.vorlageSetzen(erstes)
            return vorgaben.referenzen.first == erstes
        }
    }

    private static let referenzInfo = "MOSS-Image baut das neue Bild auf dem Referenzbild auf: Aufbau, Farben und Formen bleiben je nach Nähe zur Vorlage erhalten, das Format kommt vom Referenzbild. Module gehen dazu auch.\n\nDas Bild bleibt auf diesem Mac. Die App merkt sich eine Kopie im Bildordner, damit du die Einstellungen später übernehmen kannst."

    private func referenzVorschau(_ bild: URL) -> some View {
        VStack(spacing: 4) {
            Vorschaubild(url: bild, kante: 200, fuellen: true)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Referenzbild")
            Text("Vorlage").font(.caption.weight(.medium))
            vorschauKnopf("xmark", "Referenzbild entfernen") { vorgaben.referenzEntfernen(0) }
        }
    }

    private func vorschauKnopf(_ symbol: String, _ titel: String, _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(titel)
        .accessibilityLabel(titel)
    }

    /// Wie nah das neue Bild am Referenzbild bleibt.
    private var referenzHinweise: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Nähe zur Vorlage").font(.caption).foregroundStyle(.secondary)
                Slider(value: $vorgaben.referenzStaerke, in: 0.125...0.875, step: 0.125)
                    .accessibilityLabel("Nähe zur Vorlage")
                Text(vorgaben.referenzStaerke, format: .number.precision(.fractionLength(2)))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            hinweis("\(ModellID.moss.name) baut auf dem Referenzbild auf. Hoch bleibt nah an der Vorlage, tief lässt mehr Freiheit. Das Format kommt vom Referenzbild.")
        }
    }

    private func hinweis(_ text: String) -> some View {
        Text(verbatim: text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Ein gewähltes Bild ersetzt das bisherige Referenzbild.
    private func referenzWaehlen() {
        let dialog = NSOpenPanel()
        dialog.allowedContentTypes = [.image]
        dialog.allowsMultipleSelection = false
        guard dialog.runModal() == .OK, let bild = dialog.urls.first else { return }
        vorgaben.vorlageSetzen(bild)
    }

    private var eingabeKarte: some View {
        Karte {
            VStack(alignment: .leading, spacing: 10) {
                KartenTitel(text: "Was soll auf dem Bild sein?", symbol: "text.quote", farbe: .accentColor)
                eingabeFeld($vorgaben.prompt, hoehe: 96, fokussiert: promptFokus).focused($promptFokus)
                HStack(spacing: 6) {
                    KartenTitel(text: "Was soll nicht auf dem Bild sein? (optional)",
                                symbol: "minus.circle", farbe: .orange)
                    InfoKnopf(titel: "Negativprompt",
                              beschreibung: "Hier stehen Dinge, die das Modell vermeiden soll. Das lenkt das Bild, ist aber kein sicheres Verbot.\n\nMit Turbo stellt die App dafür Textführung 2 ein, das Bild dauert dann rund doppelt so lange, und der Negativprompt wirkt nur schwach. Stark wirkt er erst in der Stufe Beste.")
                }
                .padding(.top, 4)
                eingabeFeld($vorgaben.negativ, hoehe: 52, fokussiert: negativFokus).focused($negativFokus)
            }
        }
    }

    private func eingabeFeld(_ text: Binding<String>, hoehe: CGFloat, fokussiert: Bool) -> some View {
        TextEditor(text: text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: hoehe)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(fokussiert ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1))
    }

    /// Ein Klick auf eine Stufe wendet sie an. Passen die Werte zu keiner Stufe, ist keine gewählt.
    private var stufeWahl: Binding<Stufe?> {
        Binding(get: { vorgaben.aktuelleStufe }, set: { neu in
            if let neu { vorgaben.stufeAnwenden(neu) }
        })
    }

    private var qualitaetKarte: some View {
        Karte {
            HStack(spacing: 6) {
                KartenTitel(text: "Qualität", symbol: "speedometer", farbe: .accentColor)
                InfoKnopf(titel: "Qualität", beschreibung: Stufe.erklaerung)
                Spacer()
                if vorgaben.aktuelleStufe == nil {
                    Text("Eigene Werte").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Qualität", selection: stufeWahl) {
                    ForEach(Stufe.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    private var modulKarte: some View {
        Karte {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    KartenTitel(text: "Module", symbol: "puzzlepiece.extension", farbe: .teal)
                    InfoKnopf(titel: "Module",
                              beschreibung: "Module verändern den Stil oder die Stärken eines Modells, zum Beispiel realistischere Haut oder ein Malstil. Du kannst mehrere gleichzeitig nutzen. Die Stärke sagt, wie stark ein Modul wirkt: 1 ist der Normalwert, über 1,5 kippt das Bild oft.\n\nEin Modul passt nur zu dem Modell, für das es gemacht ist, hier zu MOSS-Image. Neue Module findest du links unter Module.")
                    Spacer()
                    Button("Weitere Module …", action: zeigeModule)
                        .buttonStyle(.link).font(.caption)
                }
                if let meldung = vorgaben.modulMeldung {
                    Text(verbatim: meldung).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if modulGruppen.isEmpty {
                    Text("Noch keine Module für \(ModellID.moss.name) geladen. Du findest sie unter Weitere Module.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(modulGruppen, id: \.titel) { gruppe in
                    let offen = vorgaben.offeneGruppen.contains(gruppe.titel)
                    let eingeschaltet = gruppe.module.filter { vorgaben.modulAktiv.contains($0.datei) }.count
                    VStack(alignment: .leading, spacing: 10) {
                        AufklappTitel(titel: gruppe.titel, symbol: gruppe.symbol, offen: offen,
                                      zusatz: eingeschaltet > 0 ? "\(eingeschaltet) von \(gruppe.module.count) an" : "\(gruppe.module.count)") {
                            if offen {
                                vorgaben.offeneGruppen.remove(gruppe.titel)
                            } else {
                                vorgaben.offeneGruppen.insert(gruppe.titel)
                            }
                        }
                        .padding(.top, 6)
                        if offen {
                            ForEach(gruppe.module) { modul in
                                if modul != gruppe.module.first { Divider() }
                                ModulZeile(modul: modul)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Dieselben Gruppen wie im Bereich Module, leere Gruppen fallen weg.
    private var modulGruppen: [(titel: String, symbol: String, module: [Modul])] {
        let passende = vorgaben.module
        let katalog = Katalogeintrag.Kategorie.allCases.map { kategorie in
            (kategorie.rawValue, kategorie.symbol, passende.filter { Katalog.eintrag($0.datei)?.kategorie == kategorie })
        }
        let eigene = passende.filter { Katalog.eintrag($0.datei) == nil }
        return (katalog + [("Eigene Module", "folder", eigene)]).filter { !$0.2.isEmpty }
    }

    private var modellKarte: some View {
        Karte {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    KartenTitel(text: "Modelle", symbol: "cpu", farbe: .accentColor)
                    InfoKnopf(titel: "Modelle",
                              beschreibung: "Die Zeit daneben ist die Schätzung für ein Bild. Sie wird mit jedem Bild genauer.\n\nÜber die Regler neben der Zeit stellst du Turbo, Schritte und Textführung ein. Weitere Modelle können später dazukommen.")
                    Spacer()
                }
                ForEach(ModellID.allCases) { modell in
                    if modell != ModellID.allCases.first { Divider() }
                    ModellZeile(modell: modell)
                }
            }
        }
    }

    private var bildKarte: some View {
        Karte {
            VStack(alignment: .leading, spacing: 10) {
                KartenTitel(text: "Bild", symbol: "photo", farbe: .green)
                einstellZeile("Längste Seite", info: "So viele Pixel misst die längste Bildkante. Mehr Pixel zeigen mehr Details, kosten aber deutlich mehr Zeit und Speicher: 1024 dauert rund doppelt so lange wie 768. Bei 1280 wird der Arbeitsspeicher knapp, schliesse dann grosse Programme.") {
                    Picker("Längste Seite", selection: $vorgaben.laengeSeite) {
                        ForEach([512, 768, 1024, 1280], id: \.self) { Text(verbatim: "\($0) Pixel").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                einstellZeile("Format", info: "Das Seitenverhältnis des Bildes. Die längste Seite bleibt gleich, darum sind Hoch- und Querformate kleiner als das Quadrat und schneller fertig.\n\nMit Referenzbild nimmt MOSS-Image das Format des Referenzbildes.") {
                    Picker("Format", selection: $vorgaben.format) {
                        ForEach(Bildformat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!vorgaben.formatGenutzt)
                    .help(!vorgaben.formatGenutzt ? "Mit Referenzbild gilt das Format des Referenzbildes." : "")
                }
                Divider()
                einstellZeile("Anzahl Bilder", info: "So viele Varianten erzeugt die App mit demselben Prompt. Die Dauer wächst entsprechend: 4 Bilder dauern viermal so lange wie eines.") {
                    Stepper(value: $vorgaben.anzahl, in: 1...20) {
                        Text(verbatim: "\(vorgaben.anzahl)").monospacedDigit()
                    }
                    .accessibilityLabel("Anzahl Bilder")
                    .accessibilityValue(Text(verbatim: "\(vorgaben.anzahl)"))
                }
                Divider()
                HStack(spacing: 6) {
                    Text("Feste Zufallszahl").font(.callout)
                    InfoKnopf(titel: "Zufallszahl",
                              beschreibung: "Gleiche Zufallszahl, gleicher Prompt und gleiche Einstellungen ergeben wieder dasselbe Bild. Ohne feste Zufallszahl ist jedes Bild neu.")
                    Spacer()
                    if vorgaben.festerStartwert {
                        TextField("Zufallszahl", value: $vorgaben.startwert, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .labelsHidden()
                    }
                    Toggle("Feste Zufallszahl", isOn: $vorgaben.festerStartwert)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                Text(verbatim: groessenText)
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Mit Vorlage folgt die Grösse deren Seitenverhältnis, sonst dem Format.
    private var groessenText: String {
        let masse = vorgaben.modelle.first.map { vorgaben.masse(fuer: $0) }
            ?? vorgaben.format.masse(laengeSeite: vorgaben.laengeSeite)
        return "Bildgrösse: \(masse.breite) × \(masse.hoehe) Pixel"
    }

    private func einstellZeile<Regler: View>(_ titel: String, info: String, @ViewBuilder _ regler: () -> Regler) -> some View {
        HStack(spacing: 6) {
            Text(titel).font(.callout)
            InfoKnopf(titel: titel, beschreibung: info)
            Spacer()
            regler()
        }
    }

    private func meldung(_ text: String, farbe: Color = .secondary) -> some View {
        Text(verbatim: text).font(.caption).foregroundStyle(farbe)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func erzeugen() {
        let vorher = generator.warteschlange.count
        let auftraege = vorgaben.auftragsliste()
        vorgaben.vonBildUebernommen = false
        // Gesperrt bleibt es, bis die Referenzbilder kopiert sind, und danach noch kurz.
        klickGesperrt = true
        klickAufgabe?.cancel()
        klickAufgabe = Task {
            await generator.starten(auftraege, laengeSeite: vorgaben.laengeSeite)
            eingereiht = generator.warteschlange.count > vorher ? generator.warteschlange.count : nil
            guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            klickGesperrt = false
            guard (try? await Task.sleep(for: .seconds(3))) != nil else { return }
            eingereiht = nil
        }
    }

    private var startBereich: some View {
        VStack(spacing: 8) {
            let bilder = vorgaben.modelle.count * vorgaben.anzahl
            let dauer = vorgaben.modelle.map { generator.schaetzer.schaetzung(vorgaben.muster($0)) }.reduce(0, +)
                * Double(vorgaben.anzahl)
            let warten = generator.laeuft || generator.pausiert
            Button(action: erzeugen) {
                Label(warten ? "In die Warteschlange" : (bilder > 1 ? "\(bilder) Bilder erzeugen" : "Bild erzeugen"),
                      systemImage: warten ? "text.badge.plus" : "sparkles")
                    .frame(minWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(vorgaben.promptLeer || bilder == 0 || stoerung != nil || klickGesperrt)
            .help("Bild erzeugen (⌘↩)")

            if let stoerung {
                meldung(stoerung, farbe: .red)
            } else if bilder == 0 {
                meldung("Schalte mindestens ein Modell ein.")
            } else if vorgaben.promptLeer {
                meldung("Beschreibe oben, was auf dem Bild sein soll.")
            }
            if generator.pausiert && !generator.laeuft {
                meldung("Die Warteschlange ist angehalten. Klicke auf Weiterrechnen, dann geht es beim nächsten Bild weiter.")
                HStack(spacing: 10) {
                    Button("Weiterrechnen") { generator.weiterrechnen() }
                        .controlSize(.small)
                    if let lauf = generator.fehlerLauf {
                        Button("Fehler ansehen") { zeigeLauf(lauf) }
                            .buttonStyle(.link).font(.caption)
                    }
                }
            } else if warten {
                Text("Startet in etwa \(dauerText(generator.restGesamt)), sobald alles davor fertig ist.")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let eingereiht {
                meldung("Zur Warteschlange hinzugefügt, Platz \(eingereiht)")
            }
            if let fehler = generator.fehler, generator.fehlerLauf == nil {
                meldung(fehler, farbe: .red).textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if bilder > 0 {
                    Text("Geschätzte Dauer: \(dauerText(dauer))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Text("•").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                lokalKnopf
            }
        }
        .frame(maxWidth: kartenBreite)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var lokalKnopf: some View {
        Button {
            lokalInfo.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                Text("100 % lokal, ohne Internet")
            }
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .popover(isPresented: $lokalInfo, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Label("100 % lokal", systemImage: "lock.shield.fill").font(.callout.weight(.semibold))
                Text("Prompts und Bilder bleiben auf diesem Mac. Die Berechnung läuft ohne Internet, ohne Konto und ohne Cloud. Nur wenn du auf Laden klickst, holt die App das Modell oder ein Modul aus dem Netz.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 320)
        }
    }
}

private struct ModulZeile: View {
    @EnvironmentObject private var vorgaben: Vorgaben
    let modul: Modul

    private var aktiv: Binding<Bool> { vorgaben.modulSchalter(modul) }

    private var staerke: Binding<Double> {
        Binding(get: { vorgaben.staerke(modul) }, set: { vorgaben.modulStaerke[modul.datei] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(modul.name).font(.callout.weight(.medium))
                    Text(modul.beschreibung).font(.caption).foregroundStyle(.secondary)
                    if let hinweis = modul.hinweis {
                        Text(hinweis).font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 8)
                Toggle(modul.name, isOn: aktiv)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(modul.format == .unbrauchbar)
            }
            if aktiv.wrappedValue {
                HStack {
                    Text("Stärke").font(.caption).foregroundStyle(.secondary)
                    Slider(value: staerke, in: 0...2, step: 0.05)
                        .accessibilityLabel("Stärke von \(modul.name)")
                    Text(staerke.wrappedValue, format: .number.precision(.fractionLength(2)))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                if let tipp = Katalog.eintrag(modul.datei)?.hinweis {
                    Text(verbatim: tipp).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ModellZeile: View {
    @EnvironmentObject private var generator: Generator
    @EnvironmentObject private var vorgaben: Vorgaben
    let modell: ModellID
    @State private var offen = false

    private var aktiv: Binding<Bool> {
        Binding(get: { vorgaben.aktiv.contains(modell) }, set: { neu in
            if neu { vorgaben.aktiv.insert(modell) } else { vorgaben.aktiv.remove(modell) }
        })
    }

    private var messung: String {
        let wert = generator.schaetzer.messwert(vorgaben.muster(modell))
        guard wert.anzahl > 0 else { return "noch nicht gemessen" }
        let plusMinus = wert.abweichung.map { ", ± \(dauerText($0))" } ?? ""
        return "\(wert.anzahl) Mal gemessen\(plusMinus)"
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(modell.farbe.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: modell.symbol).foregroundStyle(modell.farbe).font(.system(size: 14))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(modell.name).font(.callout.weight(.medium))
                Text(modell.hinweis).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                StatusKapsel(text: dauerText(generator.schaetzer.schaetzung(vorgaben.muster(modell))),
                             farbe: aktiv.wrappedValue ? modell.farbe : .secondary)
                Text(messung).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Button {
                offen.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(modell.name) einstellen")
            .popover(isPresented: $offen, arrowEdge: .trailing) {
                ModellRegler(modell: modell).frame(width: 340).padding(16)
            }
            // Das einzige Modell lässt sich nicht ausschalten, sonst gäbe es nichts zu rechnen.
            if ModellID.allCases.count > 1 {
                Toggle(modell.name, isOn: aktiv)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }
}

/// Schritte und Textführung eines Modells, im Popover und im Einstellungsfenster.
struct ModellRegler: View {
    @EnvironmentObject private var vorgaben: Vorgaben
    let modell: ModellID

    private var wert: Binding<ModellEinstellung> {
        Binding(get: { vorgaben.einstellung(modell) }, set: { vorgaben.einstellungen[modell] = $0 })
    }

    private var turbo: Binding<Bool> {
        Binding(get: { wert.wrappedValue.turbo }, set: { neu in
            var neuerWert = wert.wrappedValue
            neuerWert.turbo = neu
            neuerWert.schritte = neu ? 8 : 30
            neuerWert.textfuehrung = neu ? 1 : 3
            wert.wrappedValue = neuerWert
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(modell.name).font(.headline)
            regler
        }
    }

    @ViewBuilder
    private var regler: some View {
            Toggle("Turbo-Modul", isOn: turbo)
                .toggleStyle(.switch)
                .controlSize(.small)
            Text("Rechnet mit 8 statt 30 Schritten und ohne doppelte Durchgänge, also deutlich schneller. Die Bilder können etwas weniger Feinheit haben.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text("Schritte")
                Spacer()
                Stepper(value: wert.schritte, in: modell.schrittBereich(turbo: wert.wrappedValue.turbo)) {
                    Text(verbatim: "\(wert.wrappedValue.schritte)").monospacedDigit()
                }
                .accessibilityLabel("Schritte")
                .accessibilityValue(Text(verbatim: "\(wert.wrappedValue.schritte)"))
            }
            Text("So oft überarbeitet das Modell das Bild. Mehr Schritte heisst mehr Feinheit, aber auch mehr Zeit. \(modell.schrittTipp)")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text("Textführung")
                Spacer()
                Text(wert.wrappedValue.textfuehrung, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: wert.textfuehrung, in: 1...7, step: 0.5)
                .accessibilityLabel("Textführung")
            Text("So streng hält sich das Modell an deinen Text. Über 1 wird jeder Schritt doppelt gerechnet, das Bild dauert also rund doppelt so lange, und erst dann wirkt ein Negativprompt. \(modell.textfuehrungTipp)")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if vorgaben.hatNegativ && wert.wrappedValue.textfuehrung <= 1 {
                Text("Wegen des Negativprompts rechnet das Modell mit Textführung 2.")
                    .font(.caption).foregroundStyle(.secondary)
            }
    }
}

// MARK: Ergebnisse

struct LaufAnsicht: View {
    @EnvironmentObject private var generator: Generator
    @EnvironmentObject private var vorgaben: Vorgaben
    let gruppe: UUID
    let neuBeginnen: () -> Void

    private var lauf: Lauf? { generator.laeufe.first { $0.id == gruppe } }
    private var rechnet: Bool { generator.aktiveGruppe == gruppe }
    /// Nur der Fehler dieses Laufs. Fehler ohne Lauf erscheinen unter Neues Bild.
    private var laufFehler: String? { generator.fehlerLauf == gruppe ? generator.fehler : nil }

    var body: some View {
        VStack(spacing: 0) {
            if let lauf, !lauf.ergebnisse.isEmpty {
                HStack(spacing: 0) {
                    GeometryReader { rahmen in bilder(lauf, rahmenHoehe: rahmen.size.height) }
                    Divider()
                    BildAngaben(bilder: lauf.ergebnisse)
                }
                fussleiste(lauf)
            } else if rechnet {
                VStack {
                    Spacer(minLength: 24)
                    fortschritt(gross: true)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let platz = generator.platz(gruppe) {
                wartet(platz)
            }
        }
    }

    private func bilder(_ lauf: Lauf, rahmenHoehe: CGFloat) -> some View {
        let einzeln = lauf.ergebnisse.count == 1
        return ScrollView {
            VStack(spacing: 16) {
                if rechnet {
                    Karte { fortschritt(gross: false) }
                }
                if let laufFehler {
                    FehlerKarte(fehler: laufFehler)
                } else if generator.pausiert && generator.platz(gruppe) != nil {
                    Karte { pausenHinweis }
                }
                LazyVGrid(columns: einzeln ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 260), spacing: 14)],
                          spacing: 14) {
                    ForEach(lauf.ergebnisse) { ergebnis in
                        // Ein einzelnes Bild bleibt ganz sichtbar, Abstand und Bildzeile gehen von der Höhe ab.
                        BildKachel(ergebnis: ergebnis,
                                   zahlZeigen: lauf.ergebnisse.filter { $0.modell == ergebnis.modell }.count > 1,
                                   maxHoehe: einzeln ? max(rahmenHoehe - 60, 240) : nil,
                                   oeffnen: { generator.grossBild = ergebnis },
                                   alsVorlage: {
                                       vorgaben.vorlageSetzen(Pfade.bilder.appendingPathComponent(ergebnis.datei))
                                       neuBeginnen()
                                   },
                                   papierkorb: { generator.inPapierkorb(ergebnis) })
                    }
                }
            }
            .padding(16)
        }
    }

    private var pausenHinweis: some View {
        VStack(spacing: 12) {
            Text("Die Warteschlange ist angehalten. Klicke auf Weiterrechnen, dann geht es beim nächsten Bild weiter.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Weiterrechnen") { generator.weiterrechnen() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }

    private func wartet(_ platz: Int) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.07)).frame(width: 96, height: 96)
                Image(systemName: "clock")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.blue.opacity(0.5))
            }
            VStack(spacing: 6) {
                Text(generator.pausiert ? "Angehalten, Platz \(platz)" : "In der Warteschlange, Platz \(platz)")
                    .font(.title3.weight(.semibold))
                Text(lauf?.prompt ?? "").font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(3).frame(maxWidth: 420)
            }
            if let laufFehler {
                FehlerKarte(fehler: laufFehler).frame(maxWidth: 420)
            } else if generator.pausiert {
                pausenHinweis.frame(maxWidth: 420)
            }
            Button(role: .destructive) {
                generator.ausWarteschlangeEntfernen(gruppe)
                neuBeginnen()
            } label: {
                Label("Aus Warteschlange entfernen", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fussleiste(_ lauf: Lauf) -> some View {
        HStack(spacing: 10) {
            // Übernimmt die ganze Generierung. Ein einzelnes Bild daraus geht über seine Grossansicht.
            Button {
                vorgaben.uebernehmen(lauf.ergebnisse)
                neuBeginnen()
            } label: {
                Label("Einstellungen übernehmen", systemImage: "arrow.uturn.backward")
            }
            // Solange Bilder fehlen, wären Modelle und Anzahl noch nicht vollständig.
            .disabled(rechnet || generator.platz(gruppe) != nil)
            .help(rechnet || generator.platz(gruppe) != nil ? "Geht, sobald alle Bilder dieser Generierung fertig sind."
                  : lauf.modelle.count > 1 ? "Schaltet alle Modelle dieser Generierung ein, jedes mit seinen Werten." : "")
            Spacer()
            Text(lauf.untertitel).font(.caption).foregroundStyle(.secondary)
            Text("• \(dauerText(lauf.dauer))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func fortschritt(gross: Bool) -> some View {
        VStack(spacing: gross ? 24 : 10) {
            if gross {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
            VStack(spacing: gross ? 12 : 8) {
                Text(generator.statusText.isEmpty ? "Wird vorbereitet" : generator.statusText)
                    .font(gross ? .title3.weight(.medium) : .callout.weight(.medium))
                ProgressView(value: generator.fortschritt)
                    .frame(maxWidth: gross ? 300 : .infinity)
                    .animation(.easeInOut(duration: 0.8), value: generator.fortschritt)
                Text("Noch etwa \(dauerText(generator.restSekunden))")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    .contentTransition(.numericText())
                Button(role: .destructive) {
                    generator.abbrechen()
                } label: {
                    Label("Abbrechen", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Fehler eines Laufs. Hängt die Warteschlange daran, lässt sich das Bild wiederholen oder überspringen.
private struct FehlerKarte: View {
    @EnvironmentObject private var generator: Generator
    let fehler: String

    var body: some View {
        Karte {
            VStack(alignment: .leading, spacing: 10) {
                Label(fehler, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if generator.pausiert && !generator.laeuft {
                    HStack(spacing: 8) {
                        Button("Nochmals versuchen") { generator.weiterrechnen() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        Button("Bild überspringen") { generator.bildUeberspringen() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                if let details = generator.fehlerDetails, !details.isEmpty {
                    DisclosureGroup("Technische Angaben") {
                        Text(verbatim: details)
                            .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

private struct BildKachel: View {
    let ergebnis: Ergebnis
    /// Rechnet ein Modell mehrere Bilder, steht die Zufallszahl unter dem Bild statt bei den Angaben.
    let zahlZeigen: Bool
    let maxHoehe: CGFloat?
    let oeffnen: () -> Void
    let alsVorlage: () -> Void
    let papierkorb: () -> Void

    private var url: URL { Pfade.bilder.appendingPathComponent(ergebnis.datei) }

    var body: some View {
        Button(action: oeffnen) {
            VStack(alignment: .leading, spacing: 6) {
                Vorschaubild(url: url, kante: 720)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1))
                    .frame(maxHeight: maxHoehe)
                HStack(spacing: 4) {
                    Image(systemName: ergebnis.modell.symbol).foregroundStyle(ergebnis.modell.farbe)
                    Text(ergebnis.modell.name)
                    Text("• \(dauerText(ergebnis.sekunden))").monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if zahlZeigen {
                    Text(verbatim: "Zufallszahl \(ergebnis.seed)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Im Finder zeigen", systemImage: "folder")
            }
            Button(action: alsVorlage) {
                Label("Als Vorlage verwenden", systemImage: "photo.on.rectangle")
            }
            Divider()
            Button(role: .destructive, action: papierkorb) {
                Label("In den Papierkorb", systemImage: "trash")
            }
        }
        .accessibilityLabel("\(ergebnis.modell.name), \(ergebnis.prompt)")
        .accessibilityHint("Öffnet das Bild gross")
    }
}

/// Wie Bilder entstanden sind: Prompt, Negativprompt, Module und alle Einstellungen, je Modell getrennt.
/// Innerhalb einer Generierung rechnet ein Modell alle Bilder gleich, nur die Zufallszahl wechselt.
private struct BildAngaben: View {
    let bilder: [Ergebnis]

    private var modelle: [ModellID] { ModellID.allCases.filter { modell in bilder.contains { $0.modell == modell } } }
    /// Bei Textführung 1 hat das Modell den Negativprompt nicht beachtet.
    private var negativ: String? {
        bilder.first { !$0.negativ.isEmpty && $0.textfuehrung > 1 }?.negativ
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let prompt = bilder.first?.prompt { AngabenText(titel: "Prompt", text: prompt) }
                if let negativ { AngabenText(titel: "Negativprompt", text: negativ) }
                ForEach(modelle) { modell in
                    let eigene = bilder.filter { $0.modell == modell }
                    if let bild = eigene.first { ModellAngaben(bild: bild, einzeln: eigene.count == 1) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 320)
    }
}

private struct AngabenText: View {
    let titel: String
    let text: String
    @State private var kopiert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: titel).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    kopiert = true
                } label: {
                    Image(systemName: kopiert ? "checkmark" : "doc.on.doc").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("\(titel) kopieren")
                .accessibilityLabel("\(titel) kopieren")
            }
            Text(verbatim: text).font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: kopiert) {
            guard kopiert else { return }
            try? await Task.sleep(for: .seconds(1.5))
            kopiert = false
        }
    }
}

private struct ModellAngaben: View {
    let bild: Ergebnis
    /// Bei mehreren Bildern stehen Zufallszahl und Dauer unter dem jeweiligen Bild.
    let einzeln: Bool
    /// Das Referenzbild ist gross offen.
    @State private var offeneReferenz = false

    /// Manche Angaben kennen nur die Modulnamen.
    private var module: [(name: String, pfad: String?, staerke: Double?)] {
        bild.modulDaten?.map { ($0.name, $0.pfad, $0.staerke) } ?? (bild.module ?? []).map { ($0, nil, nil) }
    }

    /// Das Referenzbild, auf dem MOSS aufgebaut hat. Ein ungültiger Name zeigt keines.
    private var referenzBild: URL? { bild.referenzNamen.first.flatMap(Pfade.referenzKopie) }

    private var referenzOffen: Binding<Bool> {
        Binding(get: { offeneReferenz }, set: { offeneReferenz = $0 })
    }

    private func zeile(_ name: String, _ wert: String) -> some View {
        GridRow {
            Text(verbatim: name).foregroundStyle(.secondary)
            Text(verbatim: wert).textSelection(.enabled)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusKapsel(text: bild.modell.name, farbe: bild.modell.farbe)
            moduleAbschnitt
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                // Mit Vorlage bestimmt das Referenzbild das Format, nicht die Einstellung.
                if let format = bild.referenzen > 0 ? "Wie Referenzbild" : bild.formatName {
                    zeile("Format", format)
                }
                if bild.breite > 0, bild.hoehe > 0 { zeile("Grösse", "\(bild.breite) × \(bild.hoehe) Pixel") }
                if bild.schritte > 0 { zeile("Schritte", "\(bild.schritte)") }
                zeile("Textführung", String(format: "%.1f", bild.textfuehrung))
                if einzeln {
                    zeile("Zufallszahl", "\(bild.seed)")
                    zeile("Dauer", dauerText(bild.sekunden))
                }
                if bild.referenzen > 0 {
                    zeile("Referenzbild", "Ja")
                }
                if bild.referenzen > 0, let staerke = bild.referenzStaerke {
                    zeile("Nähe zur Vorlage", String(format: "%.2f", staerke))
                }
            }
            .font(.caption)
            referenzAbschnitt
        }
        .sheet(isPresented: referenzOffen) {
            if let url = referenzBild {
                ReferenzAnsicht(url: url) { offeneReferenz = false }
            }
        }
    }

    /// Das Referenzbild erscheint klein. Ein Klick öffnet es zum Hineinzoomen.
    @ViewBuilder
    private var referenzAbschnitt: some View {
        if let url = referenzBild {
            Button { offeneReferenz = true } label: {
                Vorschaubild(url: url, kante: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: 120, maxHeight: 120, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Referenzbild gross ansehen")
            .accessibilityLabel("Referenzbild gross ansehen")
        }
    }

    private var moduleAbschnitt: some View {
        VStack(alignment: .leading, spacing: 8) {
            KartenTitel(text: "Module", symbol: "puzzlepiece.extension", farbe: .teal)
            if module.isEmpty {
                Text(bild.module == nil && bild.modulDaten == nil ? "Nicht gespeichert" : "Keine")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(module.enumerated()), id: \.offset) { _, modul in
                ModulAngabe(name: modul.name, pfad: modul.pfad, staerke: modul.staerke)
            }
            if let hinweis = bild.hinweis {
                Label(hinweis, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ausloeser = bild.ausloeser {
                Text(verbatim: "Auslöser im Prompt: \(ausloeser)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Ein Modul so, wie es in der Auswahl erscheint: Symbol der Gruppe, Name, Beschreibung und Stärke.
private struct ModulAngabe: View {
    let name: String
    let pfad: String?
    let staerke: Double?

    private var datei: String? { pfad.map { ($0 as NSString).lastPathComponent } }
    /// Das Turbo-Modul schaltet man beim Modell ein, nicht in der Modulliste.
    private var turbo: Bool { datei == Modul.turboDatei || (datei == nil && name == "Turbo") }
    /// Manche Angaben kennen nur den Namen, darum auch die Suche danach.
    private var eintrag: Katalogeintrag? { datei.flatMap(Katalog.eintrag) ?? Katalog.alle.first { $0.name == name } }

    private var symbol: String { turbo ? "hare" : eintrag?.kategorie.symbol ?? "folder" }
    private var beschreibung: String {
        if turbo { return "Rechnet mit 8 statt 30 Schritten, also deutlich schneller." }
        return eintrag?.beschreibung ?? "Selbst hinzugefügtes Modul."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.callout).foregroundStyle(.teal)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.teal.opacity(0.12)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: turbo ? "Turbo-Modul" : name).font(.callout.weight(.medium)).textSelection(.enabled)
                    Text(verbatim: beschreibung).font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let staerke, !turbo {
                HStack(spacing: 8) {
                    Text("Stärke").font(.caption).foregroundStyle(.secondary)
                    GeometryReader { flaeche in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule().fill(Color.teal)
                                .frame(width: flaeche.size.width * min(max(staerke / 2, 0), 1))
                        }
                    }
                    .frame(height: 4)
                    Text(verbatim: String(format: "%.2f", staerke))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "Stärke \(String(format: "%.2f", staerke))"))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1))
    }
}

/// Das Referenzbild einer Generierung gross, zum Hineinzoomen.
private struct ReferenzAnsicht: View {
    let url: URL
    var titel = "Referenzbild"
    let schliessen: () -> Void

    /// Ein Blatt wächst nicht von selbst, darum richtet es sich nach dem Bildschirm.
    private var groesse: CGSize {
        let flaeche = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 900)
        return CGSize(width: max(640, flaeche.width * 0.7), height: max(480, flaeche.height * 0.8))
    }

    var body: some View {
        VStack(spacing: 0) {
            Vorschaubild(url: url, kante: 1600, zoombar: true, fehltText: "Dieses Referenzbild liegt nicht mehr im Bildordner.")
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text(verbatim: titel).font(.callout.weight(.medium))
                Spacer()
                Button("Schliessen", action: schliessen).keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: groesse.width, height: groesse.height)
    }
}

private struct BildDetail: View {
    @EnvironmentObject private var generator: Generator
    @EnvironmentObject private var vorgaben: Vorgaben
    let ergebnis: Ergebnis
    let neuBeginnen: () -> Void

    private static let kante = 1600

    private var url: URL { Pfade.bilder.appendingPathComponent(ergebnis.datei) }

    private func schliessen() {
        generator.grossBild = nil
    }

    private func wechseln(_ pfeil: Pfeil) {
        // Bei schnellen Tastendrücken ist die Ansicht noch nicht nachgekommen, darum zählt der aktuelle Stand.
        if let ziel = generator.laeufe.nachbar(von: generator.grossBild ?? ergebnis, pfeil) { generator.grossBild = ziel }
    }

    /// Wo man gerade steht, und welche Tasten weiterführen.
    private var stand: String {
        let fertige = generator.laeufe.filter { !$0.ergebnisse.isEmpty }
        guard let stelle = fertige.firstIndex(where: { $0.id == ergebnis.gruppe }) else { return "" }
        let bilder = fertige[stelle].ergebnisse
        let generierung = "↑ ↓ Generierung \(stelle + 1) von \(fertige.count)"
        guard bilder.count > 1, let nummer = bilder.firstIndex(where: { $0.id == ergebnis.id }) else { return generierung }
        return "\(generierung)    ← → Bild \(nummer + 1) von \(bilder.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Vorschaubild(url: url, kante: Self.kante, zoombar: true, fehltText: "Dieses Bild liegt nicht mehr im Bildordner.")
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                BildAngaben(bilder: [ergebnis])
            }
            Divider()
            HStack(spacing: 10) {
                Button("Einstellungen übernehmen") {
                    vorgaben.uebernehmen(ergebnis)
                    schliessen()
                    neuBeginnen()
                }
                Button("Als Vorlage verwenden") {
                    vorgaben.vorlageSetzen(url)
                    schliessen()
                    neuBeginnen()
                }
                .help("Setzt das Bild als Referenzbild. MOSS-Image baut das neue Bild darauf auf. Prompt und Einstellungen bleiben, wie sie sind.")
                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("In den Papierkorb", role: .destructive) {
                    generator.inPapierkorb(ergebnis)
                    schliessen()
                }
                Spacer()
                Text(verbatim: stand).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button("Schliessen", action: schliessen).keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .background(PfeilTasten(gedrueckt: wechseln))
        .task(id: ergebnis.id) {
            // Die Nachbarn liegen bereit, damit der Wechsel mit den Pfeiltasten ohne Wartezeit klappt.
            // Die kurze Pause spart die Arbeit, solange eine Pfeiltaste gehalten wird.
            try? await Task.sleep(for: .milliseconds(150))
            let nachbarn = [Pfeil.hoch, .runter, .links, .rechts].compactMap { generator.laeufe.nachbar(von: ergebnis, $0) }
                .map { Pfade.bilder.appendingPathComponent($0.datei) }
            let groesse = Self.kante
            for pfad in nachbarn where Vorschau.gespeichert(pfad, kante: groesse) == nil {
                guard !Task.isCancelled else { return }
                await Task.detached(priority: .utility) { _ = Vorschau.laden(pfad, kante: groesse) }.value
            }
        }
    }
}
