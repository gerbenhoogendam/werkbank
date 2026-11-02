import AppKit
import ImageIO
import UniformTypeIdentifiers
import WerkbankCore

/// Een afbeelding in de tekst van een mail die je opstelt: getekend op de gekozen grootte. Klik erop en er komen vier
/// hoekjes; sleep aan een hoekje om hem groter of kleiner te maken (de verhouding blijft), zoals in Outlook. De klikken
/// vangt het tekstvak zelf af (`RichNSTextView.mouseDown`). De grootte gaat mee naar de mail (`width` en `height`).
final class InlineImageCell: NSTextAttachmentCell {
    /// De getoonde grootte, in punten.
    var displaySize: NSSize
    /// De grootte van de afbeelding zelf (in punten; een scherm-afbeelding op 2× is half zo groot als in pixels).
    let naturalSize: NSSize
    private static let handle: CGFloat = 10
    private static let minimumWidth: CGFloat = 24

    init(image: NSImage, displaySize: NSSize) {
        self.displaySize = displaySize
        naturalSize = image.size
        super.init(imageCell: image)
    }

    required init(coder: NSCoder) {
        displaySize = .zero
        naturalSize = .zero
        super.init(coder: coder)
    }

    override func cellSize() -> NSSize { displaySize }

    override func cellBaselineOffset() -> NSPoint { .zero }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        drawImage(in: cellFrame)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int,
                       layoutManager: NSLayoutManager) {
        drawImage(in: cellFrame)
        guard let textView = controlView as? NSTextView, Self.isSelected(charIndex, in: textView) else { return }
        // Gekozen: een kader met vier hoekjes om aan te slepen.
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: cellFrame.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        for corner in Self.corners(of: cellFrame) {
            let rect = NSRect(x: corner.x - Self.handle / 2, y: corner.y - Self.handle / 2,
                              width: Self.handle, height: Self.handle)
            NSColor.white.setFill()
            NSBezierPath(rect: rect).fill()
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    private func drawImage(in frame: NSRect) {
        image?.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    /// Sleept aan hoekje `corner` (0 linksboven, dan met de klok mee) tot de muis loslaat; de verhouding blijft. Hoekjes
    /// rechts groeien naar rechts, links naar links. `frame`: waar de afbeelding nu staat (in het tekstvak).
    func resize(in textView: NSTextView, at charIndex: Int, frame: NSRect, corner: Int) {
        guard let window = textView.window else { return }
        let growsRight = corner == 1 || corner == 2
        let ratio = naturalSize.width > 0 ? naturalSize.height / naturalSize.width : 1
        let maximum = Self.maximumWidth(in: textView)
        let range = NSRange(location: charIndex, length: 1)
        NSCursor.crosshair.push()
        defer { NSCursor.pop() }
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = textView.convert(event.locationInWindow, from: nil)
            let dragged = growsRight ? point.x - frame.minX : frame.maxX - point.x
            let width = min(max(Self.minimumWidth, dragged), maximum)
            displaySize = NSSize(width: width.rounded(), height: (width * ratio).rounded())
            textView.layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            textView.layoutManager?.invalidateDisplay(forCharacterRange: range)
            textView.needsDisplay = true
            textView.invalidateIntrinsicContentSize()
            if event.type == .leftMouseUp { break }
        }
        // Gewijzigd: het tekstvak (en de hoogte eromheen) bijwerken.
        textView.didChangeText()
    }

    // MARK: Hulp

    static func isSelected(_ charIndex: Int, in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        return selection.length > 0 && NSLocationInRange(charIndex, selection)
    }

    /// Het hoekje bij `point` (ruim genomen: ook net ernaast, waar het hoekje buiten de afbeelding uitsteekt).
    static func corner(near point: NSPoint, of frame: NSRect) -> Int? {
        corners(of: frame).firstIndex { hypot($0.x - point.x, $0.y - point.y) <= 12 }
    }

    /// Linksboven, rechtsboven, rechtsonder, linksonder (het tekstvak is omgedraaid: y loopt naar beneden).
    private static func corners(of frame: NSRect) -> [NSPoint] {
        [NSPoint(x: frame.minX, y: frame.minY), NSPoint(x: frame.maxX, y: frame.minY),
         NSPoint(x: frame.maxX, y: frame.maxY), NSPoint(x: frame.minX, y: frame.maxY)]
    }

    /// Niet breder dan het tekstvak.
    static func maximumWidth(in textView: NSTextView) -> CGFloat {
        guard let container = textView.textContainer else { return 600 }
        return max(minimumWidth, min(container.size.width, textView.bounds.width) - container.lineFragmentPadding * 2)
    }
}

/// Afbeeldingen in de tekst van een mail: maken uit een bestand of het klembord, en bij versturen als `cid:`-bijlage.
@MainActor
enum InlineImages {
    /// Groter wordt het geen afbeelding in de tekst (Gmail neemt tot 25 MB per mail, alles samen).
    static let maximumBytes = 10_000_000

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// Een plaatje op het klembord of in een sleepactie zonder bestand (bijvoorbeeld een schermafbeelding).
    static func imageData(from pasteboard: NSPasteboard) -> Data? {
        pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
    }

    /// Een afbeelding om in de tekst te zetten, niet breder dan `maxWidth`; `nil` als het geen (bruikbare) afbeelding is.
    static func attachment(data: Data, name: String, maxWidth: CGFloat) -> NSTextAttachment? {
        guard data.count <= maximumBytes, let image = NSImage(data: data), image.size.width > 0,
              let ready = mailReady(data, name: name) else { return nil }
        let wrapper = FileWrapper(regularFileWithContents: ready.data)
        wrapper.preferredFilename = ready.name
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.attachmentCell = cell(for: image, maxWidth: maxWidth)
        return attachment
    }

    /// Op ware grootte, maar niet breder dan `maxWidth`.
    private static func cell(for image: NSImage, maxWidth: CGFloat) -> InlineImageCell {
        let width = min(image.size.width, maxWidth)
        let height = width * image.size.height / image.size.width
        return InlineImageCell(image: image, displaySize: NSSize(width: width.rounded(), height: height.rounded()))
    }

    /// Na het laden van opgemaakte tekst (eigen venster): afbeeldingen weer schaalbaar maken.
    static func adopt(in storage: NSTextStorage, maxWidth: CGFloat) {
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment, !(attachment.attachmentCell is InlineImageCell),
                  let data = attachment.fileWrapper?.regularFileContents, let image = NSImage(data: data),
                  image.size.width > 0 else { return }
            attachment.attachmentCell = cell(for: image, maxWidth: maxWidth)
        }
    }

    /// De afbeelding voor in de mail, met een eigen Content-ID, en de grootte waarop hij in de tekst staat.
    static func mailImage(from attachment: NSTextAttachment, number: Int) -> (image: MailAttachment, size: NSSize)? {
        guard let data = attachment.fileWrapper?.regularFileContents,
              let ready = mailReady(data, name: attachment.fileWrapper?.preferredFilename ?? "afbeelding.png") else { return nil }
        let size = (attachment.attachmentCell as? InlineImageCell)?.displaySize
            ?? NSImage(data: data)?.size ?? NSSize(width: 300, height: 200)
        let contentID = "afbeelding-\(number)-\(UUID().uuidString.prefix(8).lowercased())@werkbank"
        return (MailAttachment(name: ready.name, mediaType: ready.type, data: ready.data, contentID: contentID), size)
    }

    /// PNG, JPEG en GIF blijven zoals ze zijn; al het andere (TIFF van het klembord, HEIC …) wordt PNG, dat elk
    /// mailprogramma toont.
    private static func mailReady(_ data: Data, name: String) -> (data: Data, type: String, name: String)? {
        let base = (name as NSString).deletingPathExtension.isEmpty ? "afbeelding" : (name as NSString).deletingPathExtension
        if let source = CGImageSourceCreateWithData(data as CFData, nil), let kind = CGImageSourceGetType(source) as String? {
            switch kind {
            case UTType.png.identifier: return (data, "image/png", base + ".png")
            case UTType.jpeg.identifier: return (data, "image/jpeg", base + ".jpg")
            case UTType.gif.identifier: return (data, "image/gif", base + ".gif")
            default: break
            }
        }
        guard let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return (png, "image/png", base + ".png")
    }
}
