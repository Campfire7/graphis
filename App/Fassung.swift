import Foundation

/// Feste Angaben der App. Name und Kennung müssen zu bauen.sh passen. Der Ordnername bestimmt, wo Bilder,
/// Warteschlange, Einstellungen und Modelle liegen.
enum Fassung {
    /// Graphis, griechisch γραφίς: Griffel, Pinsel.
    static let name = "Graphis"
    static let kennung = "local.graphis"
    static let ordnerName = name

    /// PLATZHALTER für die Seite, über die man das Projekt unterstützen kann. bauen.sh warnt, solange hier
    /// example.org steht. Die App öffnet sie nur nach einem Klick, im Browser.
    static let unterstuetzen = URL(string: "https://example.org/graphis-unterstuetzen")!
}
