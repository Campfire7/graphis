import Foundation

/// Feste Angaben der App. Name und Kennung müssen zu bauen.sh passen. Der Ordnername bestimmt, wo Bilder,
/// Warteschlange, Einstellungen und Modelle liegen.
enum Fassung {
    /// Graphis, griechisch γραφίς: Griffel, Pinsel.
    static let name = "Graphis"
    static let kennung = "local.graphis"
    static let ordnerName = name

    /// Abschnitt Donate im README auf der Projektseite, dort stehen die Spendenadressen. Die App öffnet ihn nur
    /// nach einem Klick, im Browser.
    static let unterstuetzen = URL(string: "https://github.com/Campfire7/graphis#donate")!

    /// Besitzer und Name des Projekts auf GitHub. Eine Seite zu einer neuen Version öffnet die App nur, wenn sie dort liegt.
    static let projektBesitzer = "Campfire7"
    static let projektName = "graphis"

    /// Die neuste veröffentlichte Version. Die App fragt sie nur ab, wenn das erlaubt ist, beim Start und höchstens
    /// einmal am Tag. Sie schickt dabei nichts über den Nutzer mit und lädt nie etwas herunter.
    static let neusteVersion = URL(string: "https://api.github.com/repos/Campfire7/graphis/releases/latest")!

    /// Die Version dieser App, etwa 1.0.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
