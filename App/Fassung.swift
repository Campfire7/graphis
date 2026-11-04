import Foundation

/// Feste Angaben der App. Name und Kennung müssen zu bauen.sh passen. Der Ordnername bestimmt, wo Bilder,
/// Warteschlange, Einstellungen und Modelle liegen.
enum Fassung {
    /// Graphis, griechisch γραφίς: Griffel, Pinsel.
    static let name = "Graphis"
    static let kennung = "local.graphis"
    static let ordnerName = name

    /// Abschnitt Unterstützen im README auf der Projektseite, dort stehen die Spendenadressen. Die App öffnet ihn nur
    /// nach einem Klick, im Browser.
    static let unterstuetzen = URL(string: "https://github.com/Campfire7/graphis#unterst%C3%BCtzen")!
}
