import AppKit
import Observation
import SwiftUI
import WerkbankCore

// MARK: - Omzetten

/// Een tekstblok van de handtekening als opgemaakte tekst (om te bewerken) en terug.
enum SignatureText {
    static func font(family: String, size: Double, bold: Bool = false, italic: Bool = false) -> NSFont {
        var font = NSFont(name: family, size: size) ?? NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
        if bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    static func paragraph(_ block: SignatureBlock, in document: SignatureDocument) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let height = document.lineHeightPixels(of: block)
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        style.alignment = switch block.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        return style
    }

    /// Wat een nieuw getypte letter krijgt.
    static func baseAttributes(_ block: SignatureBlock, in document: SignatureDocument) -> [NSAttributedString.Key: Any] {
        let font = font(family: document.fontFamily(of: block), size: document.fontSize(of: block))
        return [.font: font, .foregroundColor: color(document.color(of: block)),
                .paragraphStyle: paragraph(block, in: document),
                .baselineOffset: baseline(font, lineHeight: document.lineHeightPixels(of: block))]
    }

    /// De letters midden in de regel, zoals in een browser (anders staan ze onderaan een hoge regel).
    static func baseline(_ font: NSFont, lineHeight: Double) -> Double {
        max(0, (lineHeight - (font.ascender - font.descender)) / 2)
    }

    static func attributed(_ block: SignatureBlock, in document: SignatureDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let family = document.fontFamily(of: block)
        let size = document.fontSize(of: block)
        let paragraph = paragraph(block, in: document)
        let lineHeight = document.lineHeightPixels(of: block)
        for run in block.runs {
            let font = font(family: family, size: size, bold: run.bold, italic: run.italic)
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph,
                                                             .baselineOffset: baseline(font, lineHeight: lineHeight)]
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = color(run.color ?? document.linkColor)
            } else {
                attributes[.foregroundColor] = color(run.color ?? document.color(of: block))
            }
            if run.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }

    static func runs(_ text: NSAttributedString, block: SignatureBlock, in document: SignatureDocument) -> [SignatureRun] {
        var runs: [SignatureRun] = []
        let blockColor = document.color(of: block).uppercased()
        let linkColor = document.linkColor.uppercased()
        let string = text.string as NSString
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length), options: []) { attributes, range, _ in
            let font = attributes[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let link: String? = switch attributes[.link] {
            case let url as URL: url.absoluteString
            case let value as String: value
            default: nil
            }
            let underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
            let hex = (attributes[.foregroundColor] as? NSColor).flatMap(hex)?.uppercased()
            let color: String? = if let hex, hex != (link == nil ? blockColor : linkColor) { hex } else { nil }
            runs.append(SignatureRun(text: string.substring(with: range), bold: traits.contains(.boldFontMask),
                                     italic: traits.contains(.italicFontMask), underline: underline, color: color,
                                     link: link))
        }
        return SignatureBlock.merged(runs)
    }

    static func color(_ hex: String) -> NSColor {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }

    static func hex(_ color: Color) -> String? { hex(NSColor(color)) }
}

// MARK: - Het tekstvak met de cursor

/// Welk tekstblok de cursor heeft, voor het opmaakbalkje boven het blok: vet, cursief, onderstreept, kleur en links
/// gelden voor de selectie (of het hele blok als er niets geselecteerd is).
@MainActor
@Observable
final class SignatureTextFocus {
    @ObservationIgnored weak var textView: NSTextView?
    var blockID: UUID?
    /// Opnieuw tekenen na een wijziging in de opmaak (de knoppen tonen wat er geldt).
    var revision = 0

    enum Trait { case bold, italic, underline }

    /// Waar de opmaak voor geldt: de selectie, anders het hele blok.
    private var targetRange: NSRange {
        guard let textView, let storage = textView.textStorage else { return NSRange(location: 0, length: 0) }
        let selection = textView.selectedRange()
        return selection.length > 0 ? selection : NSRange(location: 0, length: storage.length)
    }

    func has(_ trait: Trait) -> Bool {
        _ = revision
        guard let storage = textView?.textStorage, storage.length > 0 else { return false }
        let range = targetRange
        guard range.length > 0 else { return false }
        var all = true
        switch trait {
        case .bold, .italic:
            let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask
            storage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
                guard let font = value as? NSFont, NSFontManager.shared.traits(of: font).contains(mask) else {
                    all = false
                    stop.pointee = true
                    return
                }
            }
        case .underline:
            storage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, stop in
                if (value as? Int ?? 0) == 0 {
                    all = false
                    stop.pointee = true
                }
            }
        }
        return all
    }

    func toggle(_ trait: Trait) {
        let on = !has(trait)
        edit { storage, range in
            switch trait {
            case .bold, .italic:
                let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask
                storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
                    guard let font = value as? NSFont else { return }
                    let changed = on ? NSFontManager.shared.convert(font, toHaveTrait: mask)
                        : NSFontManager.shared.convert(font, toNotHaveTrait: mask)
                    storage.addAttribute(.font, value: changed, range: sub)
                }
            case .underline:
                if on {
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                } else {
                    storage.removeAttribute(.underlineStyle, range: range)
                }
            }
        }
    }

    /// De kleur waar de selectie mee begint.
    var color: NSColor? {
        _ = revision
        guard let storage = textView?.textStorage, storage.length > 0 else { return nil }
        let location = min(targetRange.location, storage.length - 1)
        return storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    func setColor(_ color: NSColor) {
        edit { storage, range in storage.addAttribute(.foregroundColor, value: color, range: range) }
    }

    // MARK: Links

    struct LinkInfo {
        var range: NSRange
        var text: String
        var href: String
        var color: NSColor?
        var underline: Bool
    }

    /// De link onder de cursor (helemaal), of de selectie voor een nieuwe link.
    func linkInfo() -> LinkInfo? {
        guard let textView, let storage = textView.textStorage else { return nil }
        let selection = textView.selectedRange()
        let full = NSRange(location: 0, length: storage.length)
        for location in [selection.location, selection.location - 1] where location >= 0 && location < storage.length {
            var range = NSRange()
            if let value = storage.attribute(.link, at: location, longestEffectiveRange: &range, in: full) {
                let href = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
                return LinkInfo(range: range, text: (storage.string as NSString).substring(with: range), href: href,
                                color: storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor,
                                underline: (storage.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int ?? 0) != 0)
            }
        }
        return LinkInfo(range: selection, text: (storage.string as NSString).substring(with: selection), href: "",
                        color: nil, underline: true)
    }

    func applyLink(_ info: LinkInfo, text: String, href: String, color: NSColor, underline: Bool) {
        guard let textView, let storage = textView.textStorage, !text.isEmpty,
              info.range.location + info.range.length <= storage.length else { return }
        var attributes = storage.length == 0 ? textView.typingAttributes
            : storage.attributes(at: min(info.range.location, storage.length - 1), effectiveRange: nil)
        attributes[.foregroundColor] = color
        if href.isEmpty { attributes.removeValue(forKey: .link) } else { attributes[.link] = href }
        if underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attributes.removeValue(forKey: .underlineStyle)
        }
        let replacement = NSAttributedString(string: text, attributes: attributes)
        guard textView.shouldChangeText(in: info.range, replacementString: text) else { return }
        storage.replaceCharacters(in: info.range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: info.range.location, length: (text as NSString).length))
        revision += 1
    }

    func removeLink(_ info: LinkInfo, color: NSColor) {
        guard let textView, let storage = textView.textStorage,
              info.range.location + info.range.length <= storage.length,
              textView.shouldChangeText(in: info.range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.removeAttribute(.link, range: info.range)
        storage.removeAttribute(.underlineStyle, range: info.range)
        storage.addAttribute(.foregroundColor, value: color, range: info.range)
        storage.endEditing()
        textView.didChangeText()
        revision += 1
    }

    private func edit(_ body: (NSTextStorage, NSRange) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = targetRange
        guard range.length > 0, textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        body(storage, range)
        storage.endEditing()
        textView.didChangeText()
        revision += 1
    }
}

/// Eén tekstblok in het voorbeeld van de handtekening, op ware grootte en direct te bewerken.
struct SignatureTextView: NSViewRepresentable {
    let block: SignatureBlock
    let document: SignatureDocument
    let focus: SignatureTextFocus
    var onChange: ([SignatureRun]) -> Void
    var onFocus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SignatureNSTextView {
        let textView = SignatureNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        // Links in de eigen kleur en onderstreping (zoals in de mail), niet die van macOS.
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        textView.onFocus = { [weak textView] in
            guard let textView else { return }
            context.coordinator.focused(textView)
        }
        context.coordinator.load(textView)
        return textView
    }

    func updateNSView(_ textView: SignatureNSTextView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.needsReload(for: self) { context.coordinator.load(textView) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: SignatureNSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, let storage = textView.textStorage else { return nil }
        let copy = NSTextStorage(attributedString: storage)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        copy.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let lineHeight = document.lineHeightPixels(of: block)
        let height = max(layout.usedRect(for: container).height, lineHeight)
        return CGSize(width: width, height: ceil(height))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SignatureTextView
        private var lastRuns: [SignatureRun] = []
        private var lastStyle = ""

        init(_ parent: SignatureTextView) { self.parent = parent }

        static func styleKey(_ view: SignatureTextView) -> String {
            let document = view.document
            let block = view.block
            return [document.fontFamily(of: block), "\(document.fontSize(of: block))", document.color(of: block),
                    "\(document.lineHeightPixels(of: block))", block.alignment.rawValue, document.linkColor]
                .joined(separator: "|")
        }

        func needsReload(for view: SignatureTextView) -> Bool {
            SignatureBlock.merged(view.block.runs) != lastRuns || Self.styleKey(view) != lastStyle
        }

        func load(_ textView: NSTextView) {
            let selection = textView.selectedRanges
            textView.textStorage?.setAttributedString(SignatureText.attributed(parent.block, in: parent.document))
            textView.typingAttributes = SignatureText.baseAttributes(parent.block, in: parent.document)
            let length = textView.textStorage?.length ?? 0
            let clamped = selection.map { value -> NSValue in
                let range = value.rangeValue
                let location = min(range.location, length)
                return NSValue(range: NSRange(location: location, length: min(range.length, length - location)))
            }
            if !clamped.isEmpty { textView.selectedRanges = clamped }
            lastRuns = SignatureBlock.merged(parent.block.runs)
            lastStyle = Self.styleKey(parent)
            textView.invalidateIntrinsicContentSize()
        }

        @MainActor func focused(_ textView: NSTextView) {
            parent.focus.textView = textView
            parent.focus.blockID = parent.block.id
            parent.focus.revision += 1
            parent.onFocus()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let storage = textView.textStorage else { return }
            let runs = SignatureText.runs(storage, block: parent.block, in: parent.document)
            lastRuns = runs
            // Een leeg blok krijgt weer de standaardopmaak.
            if storage.length == 0 {
                textView.typingAttributes = SignatureText.baseAttributes(parent.block, in: parent.document)
            }
            parent.onChange(runs)
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            MainActor.assumeIsolated {
                if parent.focus.blockID == parent.block.id { parent.focus.revision += 1 }
            }
        }

        /// Klikken op een link zet de cursor erin; openen kan in het linkvenster.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool { true }
    }
}

final class SignatureNSTextView: NSTextView {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let container = textContainer, abs(container.containerSize.width - newSize.width) > 0.5 else { return }
        container.containerSize = NSSize(width: newSize.width, height: .greatestFiniteMagnitude)
    }
}
