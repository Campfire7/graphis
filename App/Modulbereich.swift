import AppKit
import SwiftUI

/// Der Laden für Module: Katalog mit Beschreibung und Download, darunter eigene Dateien.
struct ModulBereich: View {
    @EnvironmentObject private var vorgaben: Vorgaben
    @State private var zugeklappt = Set<String>()

    private var eigene: [Modul] {
        vorgaben.module.filter { Katalog.eintrag($0.datei) == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Modules").font(.title2.weight(.semibold))
                    Text("Modules extend MOSS-Image with styles, light and details. All modules here are under the Apache 2.0 license. For modules, the app only goes online when you click Download, and then fetches exactly this one file from Hugging Face.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Katalogeintrag.Kategorie.allCases) { kategorie in
                    kategorieKarte(kategorie)
                }
                eigeneKarte
            }
            .frame(maxWidth: kartenBreite)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .onAppear { vorgaben.moduleLaden() }
    }

    private func kategorieKarte(_ kategorie: Katalogeintrag.Kategorie) -> some View {
        let eintraege = Katalog.alle.filter { $0.kategorie == kategorie }
        let offen = !zugeklappt.contains(kategorie.rawValue)
        return Karte {
            VStack(alignment: .leading, spacing: 12) {
                AufklappTitel(titel: kategorie.anzeigeName, symbol: kategorie.symbol, offen: offen,
                              zusatz: String(eintraege.count)) {
                    if offen {
                        zugeklappt.insert(kategorie.rawValue)
                    } else {
                        zugeklappt.remove(kategorie.rawValue)
                    }
                }
                if offen {
                    ForEach(eintraege) { eintrag in
                        if eintrag.id != eintraege.first?.id { Divider() }
                        KatalogZeile(eintrag: eintrag)
                    }
                }
            }
        }
    }

    private var eigeneKarte: some View {
        Karte {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    KartenTitel(text: "Your Modules", symbol: "folder", farbe: .secondary)
                    Spacer()
                    Button("Add Module …") { moduleWaehlen(vorgaben) }
                        .buttonStyle(.link).font(.caption)
                }
                if let meldung = vorgaben.modulMeldung {
                    Text(verbatim: meldung).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if eigene.isEmpty {
                    Text("You can add files ending in .safetensors yourself, for example from Hugging Face. Check first whether their license allows your use.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(eigene) { modul in
                    if modul != eigene.first { Divider() }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: modul.anzeigeName).font(.callout.weight(.medium))
                            if let hinweis = modul.hinweis {
                                Text(verbatim: hinweis).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 8)
                        ModulSchalter(modul: modul)
                    }
                }
            }
        }
    }
}

private struct KatalogZeile: View {
    @EnvironmentObject private var vorgaben: Vorgaben
    @ObservedObject private var lader = Modullader.gemeinsam
    let eintrag: Katalogeintrag

    private var modul: Modul? {
        vorgaben.module.first { $0.datei == eintrag.datei }
    }

    private var stand: Modullader.Stand? {
        lader.staende[eintrag.datei]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: eintrag.anzeigeName).font(.callout.weight(.medium))
                Text(verbatim: eintrag.beschreibung).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let hinweis = modul?.hinweis ?? eintrag.hinweis {
                    Text(verbatim: hinweis).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .fehler(let text) = stand {
                    Text(verbatim: text).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 4) {
                    Text(verbatim: "\(eintrag.groesse) • Hugging Face • \(eintrag.lizenz)")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    Text(verbatim: "•").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
                    Button("View Page") { NSWorkspace.shared.open(eintrag.seite) }
                        .buttonStyle(.link).font(.caption2)
                }
            }
            Spacer(minLength: 8)
            aktion
        }
    }

    @ViewBuilder
    private var aktion: some View {
        if let modul {
            ModulSchalter(modul: modul)
        } else if case .laedt(let anteil) = stand {
            HStack(spacing: 6) {
                ProgressView(value: anteil).frame(width: 70)
                Text(anteil, format: .percent.precision(.fractionLength(0)))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button {
                    lader.abbrechen(eintrag)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Cancel download")
                .accessibilityLabel("Cancel download of \(eintrag.anzeigeName)")
            }
        } else if stand == .prueft {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Button("Download") { lader.laden(eintrag) }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
    }
}

/// Schaltet ein vorhandenes Modul ein und legt es bei Bedarf in den Papierkorb.
private struct ModulSchalter: View {
    @EnvironmentObject private var generator: Generator
    @EnvironmentObject private var vorgaben: Vorgaben
    let modul: Modul

    private var beschaeftigt: Bool {
        generator.laeuft || !generator.warteschlange.isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle(modul.anzeigeName, isOn: vorgaben.modulSchalter(modul))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .disabled(modul.format == .unbrauchbar)
                .help("Use for the next image")
            Button {
                vorgaben.modulEntfernen(modul)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .disabled(beschaeftigt)
            .help(beschaeftigt ? "While images are being created or waiting, the modules stay in place." : "Move to Trash")
            .accessibilityLabel("Move \(modul.anzeigeName) to Trash")
        }
    }
}
