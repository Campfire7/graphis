import AppKit

// Zeichnet das App-Symbol: dunkle Kachel, Bildsymbol und Funken in Weiss.
let kante: CGFloat = 1024
let bild = NSImage(size: NSSize(width: kante, height: kante))
bild.lockFocus()
let rand: CGFloat = 100
let flaeche = NSRect(x: rand, y: rand, width: kante - 2 * rand, height: kante - 2 * rand)
let form = NSBezierPath(roundedRect: flaeche, xRadius: 186, yRadius: 186)
NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.95, alpha: 1),
           ending: NSColor(calibratedRed: 0.28, green: 0.20, blue: 0.78, alpha: 1))!.draw(in: form, angle: -60)
func symbol(_ name: String, _ groesse: CGFloat, _ mitte: NSPoint) {
    let konfig = NSImage.SymbolConfiguration(pointSize: groesse, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    guard let s = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(konfig) else { return }
    s.draw(in: NSRect(x: mitte.x - s.size.width / 2, y: mitte.y - s.size.height / 2,
                      width: s.size.width, height: s.size.height))
}
symbol("photo", 440, NSPoint(x: kante / 2 - 20, y: kante / 2 - 30))
symbol("sparkle", 210, NSPoint(x: kante / 2 + 220, y: kante / 2 + 220))
bild.unlockFocus()
let daten = NSBitmapImageRep(data: bild.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try! daten.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
