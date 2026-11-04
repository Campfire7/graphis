import AppKit
import SwiftUI

/// Gleiche Breite auf allen Seiten, damit die Karten beim Wechsel nicht springen.
let kartenBreite: CGFloat = 640

/// Neutrale Karte: keine Tönung, Farbe nur im Symbol.
struct Karte<Inhalt: View>: View {
    @ViewBuilder let inhalt: Inhalt

    var body: some View {
        inhalt
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.08), lineWidth: 1))
    }
}

/// Überschrift mit Pfeil, der sich beim Aufklappen nach unten dreht.
struct AufklappTitel: View {
    let titel: String
    let symbol: String
    let offen: Bool
    var zusatz: String? = nil
    let umschalten: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { umschalten() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(offen ? 90 : 0))
                Label(titel, systemImage: symbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let zusatz {
                    Text(verbatim: zusatz).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(titel)
        .accessibilityValue(offen ? "aufgeklappt" : "zugeklappt")
    }
}

struct KartenTitel: View {
    let text: String
    let symbol: String
    let farbe: Color

    var body: some View {
        Label {
            Text(text).font(.caption.weight(.medium))
        } icon: {
            Image(systemName: symbol).foregroundStyle(farbe)
        }
    }
}

struct StatusKapsel: View {
    let text: String
    let farbe: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .monospacedDigit()
            .foregroundStyle(farbe)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(farbe.opacity(0.12)))
    }
}

struct InfoKnopf: View {
    let titel: String
    let beschreibung: String
    @State private var offen = false

    var body: some View {
        Button {
            offen.toggle()
        } label: {
            Image(systemName: "info.circle").foregroundStyle(.secondary).font(.callout)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Erklärung zu \(titel)")
        .popover(isPresented: $offen) {
            VStack(alignment: .leading, spacing: 8) {
                Text(titel).font(.headline)
                Text(beschreibung)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: 320)
        }
    }
}

/// Bild, das im Hintergrund geladen und im Speicher gehalten wird.
struct Vorschaubild: View {
    let url: URL
    let kante: Int
    var fuellen = false
    /// Mit dem Trackpad vergrössern und verschieben, für die Grossansicht.
    var zoombar = false
    /// Text anstelle des Bildes, wenn die Datei fehlt.
    var fehltText: String?
    @State private var bild: NSImage?
    @State private var fehlt = false

    var body: some View {
        Group {
            if let bild {
                if zoombar {
                    ZoomBild(bild: bild)
                } else if fuellen {
                    Image(nsImage: bild).resizable().scaledToFill()
                } else {
                    Image(nsImage: bild).resizable().scaledToFit()
                }
            } else if fehlt, let fehltText {
                Text(verbatim: fehltText).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                Color.secondary.opacity(0.1).aspectRatio(1, contentMode: .fit)
            }
        }
        .task(id: url) {
            if let fertig = Vorschau.gespeichert(url, kante: kante) {
                bild = fertig
                return
            }
            let pfad = url
            let groesse = kante
            let geladen = await Task.detached(priority: .utility) {
                Vorschau.laden(pfad, kante: groesse)
            }.value
            // Beim schnellen Blättern darf ein spät fertiges Bild das aktuelle nicht ersetzen.
            guard !Task.isCancelled else { return }
            bild = geladen
            fehlt = geladen == nil
        }
    }
}

/// Bild zum Hineinzoomen: mit zwei Fingern spreizen, mit der Maus oder zwei Fingern verschieben,
/// Doppelklick wechselt zwischen ganzem Bild und Vergrösserung.
struct ZoomBild: NSViewRepresentable {
    let bild: NSImage

    func makeNSView(context: Context) -> ZoomRahmen { ZoomRahmen() }

    func updateNSView(_ rahmen: ZoomRahmen, context: Context) { rahmen.zeigen(bild) }
}

final class ZoomRahmen: NSScrollView {
    let bildAnsicht = ZiehBild()
    /// Solange nicht gezoomt ist, passt sich das Bild jeder Fenstergrösse an.
    private(set) var eingepasst = true

    init() {
        super.init(frame: .zero)
        contentView = MittigerAusschnitt()
        documentView = bildAnsicht
        drawsBackground = false
        allowsMagnification = true
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
        NotificationCenter.default.addObserver(
            self, selector: #selector(zoomBeendet), name: NSScrollView.didEndLiveMagnifyNotification, object: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

    /// Zoomstufe, bei der das ganze Bild sichtbar ist.
    var passend: CGFloat {
        let bildGroesse = bildAnsicht.frame.size
        guard bildGroesse.width > 0, bildGroesse.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(bounds.width / bildGroesse.width, bounds.height / bildGroesse.height)
    }

    func zeigen(_ bild: NSImage) {
        guard bild !== bildAnsicht.image else { return }
        let gleicheGroesse = bildAnsicht.image?.size == bild.size
        bildAnsicht.image = bild
        // Gleich grosse Bilder behalten Zoom und Ausschnitt, so lassen sich beim Blättern Details vergleichen.
        guard !gleicheGroesse else { return }
        bildAnsicht.frame = NSRect(origin: .zero, size: bild.size)
        eingepasst = true
        einpassen()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        einpassen()
    }

    private func einpassen() {
        minMagnification = passend
        maxMagnification = max(passend * 2, 4)
        if eingepasst || magnification < passend {
            eingepasst = true
            magnification = passend
        }
        angleichen()
    }

    /// Doppelklick: vom ganzen Bild auf Vergrösserung an der geklickten Stelle, und wieder zurück.
    func umschalten(bei punkt: NSPoint) {
        if eingepasst {
            eingepasst = false
            setMagnification(min(passend * 2.5, maxMagnification), centeredAt: punkt)
        } else {
            eingepasst = true
            magnification = passend
        }
        angleichen()
    }

    override func smartMagnify(with event: NSEvent) {
        umschalten(bei: bildAnsicht.convert(event.locationInWindow, from: nil))
    }

    @objc private func zoomBeendet() {
        eingepasst = magnification <= passend * 1.01
        if eingepasst { magnification = passend }
        angleichen()
    }

    /// Runde Ecken wie die übrigen Bilder, und die Hand als Zeiger, sobald es etwas zu verschieben gibt.
    private func angleichen() {
        bildAnsicht.layer?.cornerRadius = 10 / max(magnification, 0.01)
        window?.invalidateCursorRects(for: bildAnsicht)
    }
}

/// Hält das Bild in der Mitte, solange es kleiner als die Fläche ist.
private final class MittigerAusschnitt: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rahmen = super.constrainBoundsRect(proposedBounds)
        guard let inhalt = documentView?.frame.size else { return rahmen }
        if rahmen.width > inhalt.width { rahmen.origin.x = (inhalt.width - rahmen.width) / 2 }
        if rahmen.height > inhalt.height { rahmen.origin.y = (inhalt.height - rahmen.height) / 2 }
        return rahmen
    }
}

/// Lässt sich mit gedrückter Maustaste packen und verschieben.
final class ZiehBild: NSImageView {
    private var start: (maus: NSPoint, ausschnitt: NSPoint)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageScaling = .scaleAxesIndependently
        isEditable = false
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

    private var rahmen: ZoomRahmen? { enclosingScrollView as? ZoomRahmen }

    override func resetCursorRects() {
        if rahmen?.eingepasst == false { addCursorRect(visibleRect, cursor: .openHand) }
    }

    override func mouseDown(with ereignis: NSEvent) {
        if ereignis.clickCount == 2 {
            rahmen?.umschalten(bei: convert(ereignis.locationInWindow, from: nil))
            return
        }
        guard let ausschnitt = superview as? NSClipView else { return }
        start = (ereignis.locationInWindow, ausschnitt.bounds.origin)
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with ereignis: NSEvent) {
        guard let start, let ausschnitt = superview as? NSClipView, let rahmen else { return }
        let faktor = max(rahmen.magnification, 0.01)
        let ziel = NSPoint(x: start.ausschnitt.x - (ereignis.locationInWindow.x - start.maus.x) / faktor,
                           y: start.ausschnitt.y - (ereignis.locationInWindow.y - start.maus.y) / faktor)
        ausschnitt.scroll(to: ausschnitt.constrainBoundsRect(NSRect(origin: ziel, size: ausschnitt.bounds.size)).origin)
        rahmen.reflectScrolledClipView(ausschnitt)
    }

    override func mouseUp(with ereignis: NSEvent) {
        if start != nil { NSCursor.pop() }
        start = nil
    }
}

/// Meldet Pfeiltasten im eigenen Fenster, egal welches Element gerade den Fokus hat, etwa nach dem Markieren von Text.
struct PfeilTasten: NSViewRepresentable {
    let gedrueckt: (Pfeil) -> Void

    final class Wache: NSView {
        var gedrueckt: (Pfeil) -> Void = { _ in }
        private var beobachter: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let beobachter { NSEvent.removeMonitor(beobachter) }
            beobachter = nil
            guard window != nil else { return }
            beobachter = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ereignis in
                guard let self, ereignis.window === self.window,
                      ereignis.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
                      let pfeil = Self.pfeil(ereignis.keyCode) else { return ereignis }
                self.gedrueckt(pfeil)
                return nil
            }
        }

        private static func pfeil(_ taste: UInt16) -> Pfeil? {
            switch taste {
            case 123: return .links
            case 124: return .rechts
            case 125: return .runter
            case 126: return .hoch
            default: return nil
            }
        }
    }

    func makeNSView(context: Context) -> Wache { Wache() }
    func updateNSView(_ wache: Wache, context: Context) { wache.gedrueckt = gedrueckt }
}

extension Vorgaben {
    /// Schalter eines Moduls, gemeinsam für die Karte unter Neues Bild und den Modulbereich.
    func modulSchalter(_ modul: Modul) -> Binding<Bool> {
        Binding(get: { self.modulAktiv.contains(modul.datei) }, set: { neu in
            if neu { self.modulAktiv.insert(modul.datei) } else { self.modulAktiv.remove(modul.datei) }
        })
    }
}

extension ModellID {
    var symbol: String { "textformat" }
    var farbe: Color { .purple }
}
