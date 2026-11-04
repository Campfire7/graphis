import AppKit
import SwiftUI

@main
struct GraphisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var generator = Generator.gemeinsam
    @StateObject private var vorgaben = Vorgaben.gemeinsam

    var body: some Scene {
        WindowGroup(id: "main") {
            Hauptansicht()
                .environmentObject(generator)
                .environmentObject(vorgaben)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 820)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .newItem) {}
            FensterBefehle()
        }

        Settings {
            Einstellungsfenster()
                .environmentObject(generator)
                .environmentObject(vorgaben)
        }
    }
}

/// Holt das Fenster zurück, falls es geschlossen wurde, während ein Lauf weitergeht.
struct FensterBefehle: Commands {
    @Environment(\.openWindow) private var fensterOeffnen

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("Open Main Window") { fensterOeffnen(id: "main") }
        }
    }
}

/// Die App bleibt beim Schliessen des Fensters aktiv, damit ein Lauf weitergeht.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ohne Aktivierung legt SwiftUI das Fenster im Hintergrund oft gar nicht an.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Startet die App im Hintergrund, legt SwiftUI manchmal kein Fenster an. Dann selbst eines öffnen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if !NSApp.windows.contains(where: { $0.styleMask.contains(.titled) }) {
                NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
