import AppKit
import Observation
import SwiftUI

/// Opmaak in het opstelveld (`ReplyTextView`): de werkbalk (`RichTextToolbar`) stuurt dit aan, en bij versturen levert
/// het de HTML (`RichHTML`). Opsommingen en nummering zijn eigen alinea's met een teken ("•" of "1.") en een tab
/// ervoor, gemarkeerd met `listKey`; Return zet de lijst voort, Return op een lege regel of Backspace aan het begin
/// stopt hem.
@MainActor
@Observable
final class RichTextController {
    enum ListKind: String {
        case bullet, number
    }

    /// Wat de cursor of selectie nu heeft, voor de werkbalk.
    struct State: Equatable {
        var isBold = false
        var isItalic = false
        var isUnderline = false
        var isStrikethrough = false
        var list: ListKind?
        var family = RichTextController.defaultFamily
        var size: CGFloat = RichTextController.defaultSize
    }

    nonisolated static let defaultFamily = "Helvetica"
    nonisolated static let defaultSize: CGFloat = 13
    nonisolated static let listKey = NSAttributedString.Key("werkbank.list")
    /// Inspringen per stap, en de ruimte voor het lijstteken.
    nonisolated static let indentStep: CGFloat = 30
    nonisolated static let markerWidth: CGFloat = 20

    nonisolated static var defaultFont: NSFont {
        NSFont(name: defaultFamily, size: defaultSize) ?? .systemFont(ofSize: defaultSize)
    }

    nonisolated static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: defaultFont, .foregroundColor: NSColor.textColor]
    }

    private(set) var state = State()
    /// ⌘K in het tekstvak: de werkbalk opent het linkveld.
    private(set) var linkRequest = 0
    @ObservationIgnored weak var textView: NSTextView?
    /// Opmaak die geladen wordt zodra het tekstvak er is (losgehaald opstelvenster).
    @ObservationIgnored var pendingRTF: Data?
    @ObservationIgnored private var renumberScheduled = false

    func attach(_ textView: NSTextView) {
        self.textView = textView
        if let pendingRTF, let rich = NSAttributedString(rtf: pendingRTF, documentAttributes: nil),
           rich.string == textView.string {
            textView.textStorage?.setAttributedString(rich)
        }
        pendingRTF = nil
        refreshState()
    }

    /// Tekst met opmaak terugzetten (losgehaald opstelvenster). `text`: dezelfde tekst zonder opmaak, zodat het
    /// tekstvak hem niet daarna nog eens zonder opmaak neerzet.
    func load(rtf: Data, text: String) {
        guard let textView, let storage = textView.textStorage else {
            pendingRTF = rtf
            return
        }
        guard let rich = NSAttributedString(rtf: rtf, documentAttributes: nil), rich.string == text else { return }
        storage.setAttributedString(rich)
        refreshState()
    }

    func requestLink() {
        linkRequest += 1
    }

    /// Klik onder de tekst: cursor achteraan.
    func focusEnd() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    // MARK: Tekens

    func toggleBold() {
        let bold = !state.isBold
        change { $0[.font] = Self.font($0[.font] as? NSFont, bold: bold) }
    }

    func toggleItalic() {
        let italic = !state.isItalic
        change { $0[.font] = Self.font($0[.font] as? NSFont, italic: italic) }
    }

    func toggleUnderline() {
        let on = !state.isUnderline
        change { $0[.underlineStyle] = on ? NSUnderlineStyle.single.rawValue : nil }
    }

    func toggleStrikethrough() {
        let on = !state.isStrikethrough
        change { $0[.strikethroughStyle] = on ? NSUnderlineStyle.single.rawValue : nil }
    }

    func setFamily(_ family: String) {
        change { $0[.font] = Self.font($0[.font] as? NSFont, family: family) }
    }

    func setSize(_ size: CGFloat) {
        change { $0[.font] = Self.font($0[.font] as? NSFont, size: size) }
    }

    /// nil: de standaardkleur.
    func setColor(_ color: NSColor?) {
        change { $0[.foregroundColor] = color ?? NSColor.textColor }
    }

    /// nil: geen markering.
    func setHighlight(_ color: NSColor?) {
        change { $0[.backgroundColor] = color }
    }

    /// De link onder de cursor of in de selectie.
    var currentLink: String? {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return nil }
        let location = min(textView.selectedRange().location, storage.length - 1)
        switch storage.attribute(.link, at: location, effectiveRange: nil) {
        case let url as URL: return url.absoluteString
        case let text as String: return text
        default: return nil
        }
    }

    /// Link op de selectie; zonder selectie komt het adres zelf als link in de tekst. Leeg: link weghalen.
    func setLink(_ address: String) {
        guard let textView, let storage = textView.textStorage else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: trimmed.contains("://") || trimmed.hasPrefix("mailto:") ? trimmed : "https://" + trimmed)
        let selection = textView.selectedRange()
        if selection.length == 0 {
            guard !trimmed.isEmpty, let url else { return }
            var attributes = textView.typingAttributes
            attributes[.link] = url
            replace(selection, with: NSAttributedString(string: trimmed, attributes: attributes))
            textView.typingAttributes.removeValue(forKey: .link)
            return
        }
        guard textView.shouldChangeText(in: selection, replacementString: nil) else { return }
        storage.beginEditing()
        if trimmed.isEmpty || url == nil {
            storage.removeAttribute(.link, range: selection)
        } else if let url {
            storage.addAttribute(.link, value: url, range: selection)
        }
        storage.endEditing()
        textView.didChangeText()
        refreshState()
    }

    /// Lettertype, stijl, kleuren en links terug naar standaard (lijsten en inspringen blijven).
    func clearFormatting() {
        change { attributes in
            attributes[.font] = Self.defaultFont
            attributes[.foregroundColor] = NSColor.textColor
            for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle, .backgroundColor, .link] {
                attributes[key] = nil
            }
        }
    }

    /// Past de tekenopmaak aan in de selectie, of zonder selectie in wat je hierna typt. ⌘Z draait het terug.
    private func change(_ transform: (inout [NSAttributedString.Key: Any]) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        let ranges = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        if ranges.isEmpty {
            var attributes = textView.typingAttributes
            transform(&attributes)
            textView.typingAttributes = attributes
        } else {
            guard textView.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: nil)
            else { return }
            storage.beginEditing()
            for range in ranges {
                storage.enumerateAttributes(in: range) { attributes, run, _ in
                    var updated = attributes
                    transform(&updated)
                    storage.setAttributes(updated, range: run)
                }
            }
            storage.endEditing()
            textView.didChangeText()
        }
        refreshState()
    }

    private static func font(_ font: NSFont?, bold: Bool? = nil, italic: Bool? = nil, family: String? = nil,
                             size: CGFloat? = nil) -> NSFont {
        let manager = NSFontManager.shared
        var font = font ?? defaultFont
        if let family { font = manager.convert(font, toFamily: family) }
        if let size { font = manager.convert(font, toSize: size) }
        if let bold {
            font = bold ? manager.convert(font, toHaveTrait: .boldFontMask)
                : manager.convert(font, toNotHaveTrait: .boldFontMask)
        }
        if let italic {
            font = italic ? manager.convert(font, toHaveTrait: .italicFontMask)
                : manager.convert(font, toNotHaveTrait: .italicFontMask)
        }
        return font
    }

    // MARK: Alinea's

    func toggleList(_ kind: ListKind) {
        guard let textView else { return }
        let paragraphs = selectedParagraphs()
        guard let first = paragraphs.first, let last = paragraphs.last else { return }
        let allSame = paragraphs.allSatisfy { listKind(at: $0.location) == kind }
        let selection = textView.selectedRange()
        let delta = edit(textView) { text in
            // Van achter naar voren, zodat de eerdere bereiken kloppen.
            for paragraph in paragraphs.reversed() {
                self.removeMarker(in: paragraph, text: text)
                if !allSame { self.addMarker(kind, at: paragraph.location, text: text) }
            }
        }
        if selection.length > 0 {
            textView.setSelectedRange(NSRange(location: first.location,
                                              length: max(0, NSMaxRange(last) + delta - first.location)))
        } else {
            textView.setSelectedRange(NSRange(location: max(first.location, selection.location + delta), length: 0))
        }
        renumber()
        refreshState()
    }

    /// Inspringen (+1) of terug (-1), per alinea in de selectie.
    func indent(_ steps: Int) {
        guard let textView, let storage = textView.textStorage else { return }
        let paragraphs = selectedParagraphs().filter { $0.length > 0 }
        guard !paragraphs.isEmpty else {
            // Lege laatste regel: geldt voor wat je hierna typt.
            let style = (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle) ?? .default
            let level = max(0, style.firstLineHeadIndent + CGFloat(steps) * Self.indentStep)
            textView.typingAttributes[.paragraphStyle] = Self.paragraphStyle(level: level, list: false)
            return
        }
        // Alleen opmaak: het tekstvak registreert dat zelf voor ⌘Z.
        guard textView.shouldChangeText(inRanges: paragraphs.map { NSValue(range: $0) }, replacementStrings: nil)
        else { return }
        storage.beginEditing()
        for paragraph in paragraphs {
            let style = (storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
                as? NSParagraphStyle) ?? .default
            let level = max(0, style.firstLineHeadIndent + CGFloat(steps) * Self.indentStep)
            let isList = listKind(at: paragraph.location) != nil
            storage.addAttribute(.paragraphStyle, value: Self.paragraphStyle(level: level, list: isList),
                                 range: paragraph)
        }
        storage.endEditing()
        textView.didChangeText()
        refreshState()
    }

    /// Return in een lijst: nieuw punt, of op een leeg punt de lijst stoppen. `true`: afgehandeld.
    func handleNewline() -> Bool {
        guard let textView, let storage = textView.textStorage, textView.selectedRange().length == 0 else {
            return false
        }
        let cursor = textView.selectedRange().location
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: cursor, length: 0))
        guard let kind = listKind(at: paragraph.location) else { return false }
        let marker = markerLength(at: paragraph.location, text: storage)
        let content = (storage.string as NSString).substring(with: paragraph)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if content.count <= marker || markerText(content) == content {
            // Leeg punt: geen lijst meer.
            edit(textView) { self.removeMarker(in: paragraph, text: $0) }
            textView.setSelectedRange(NSRange(location: paragraph.location, length: 0))
            renumber()
            refreshState()
            return true
        }
        var attributes = storage.attributes(at: paragraph.location, effectiveRange: nil)
        attributes[.link] = nil
        let addition = NSMutableAttributedString(string: "\n", attributes: attributes)
        addition.append(NSAttributedString(string: kind == .bullet ? "•\t" : "0.\t", attributes: attributes))
        replace(NSRange(location: cursor, length: 0), with: addition)
        renumber()
        refreshState()
        return true
    }

    /// Backspace direct na het lijstteken: de alinea wordt weer gewone tekst. `true`: afgehandeld.
    func handleDeleteBackward() -> Bool {
        guard let textView, let storage = textView.textStorage, textView.selectedRange().length == 0 else {
            return false
        }
        let cursor = textView.selectedRange().location
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: cursor, length: 0))
        guard listKind(at: paragraph.location) != nil,
              cursor == paragraph.location + markerLength(at: paragraph.location, text: storage) else { return false }
        edit(textView) { self.removeMarker(in: paragraph, text: $0) }
        textView.setSelectedRange(NSRange(location: paragraph.location, length: 0))
        renumber()
        refreshState()
        return true
    }

    /// Na typen of plakken: de nummering bijwerken (een beeld later, niet midden in een wijziging).
    func textDidChange() {
        guard !renumberScheduled else { return }
        renumberScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.renumberScheduled = false
            self?.renumber()
        }
    }

    /// Opeenvolgende genummerde alinea's krijgen 1., 2., 3. …
    private func renumber() {
        guard let textView, let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        var changes: [(range: NSRange, marker: String)] = []
        var number = 0
        var location = 0
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            if listKind(at: paragraph.location) == .number {
                number += 1
                let length = markerLength(at: paragraph.location, text: storage)
                let expected = "\(number).\t"
                if length > 0, text.substring(with: NSRange(location: paragraph.location, length: length)) != expected {
                    changes.append((NSRange(location: paragraph.location, length: length), expected))
                }
            } else {
                number = 0
            }
            location = NSMaxRange(paragraph)
        }
        guard !changes.isEmpty else { return }
        let selection = textView.selectedRanges
        edit(textView) { copy in
            for change in changes.reversed() {
                copy.replaceCharacters(in: change.range, with: change.marker)
            }
        }
        // De cursor schuift mee met de lengteverschillen ervoor.
        let shift = { (location: Int) -> Int in
            changes.reduce(location) { result, change in
                change.range.location < location ? result + (change.marker as NSString).length - change.range.length
                    : result
            }
        }
        textView.selectedRanges = selection.map {
            let range = $0.rangeValue
            return NSValue(range: NSRange(location: shift(range.location), length: range.length))
        }
    }

    private func selectedParagraphs() -> [NSRange] {
        guard let textView, let storage = textView.textStorage else { return [] }
        let text = storage.string as NSString
        let selection = textView.selectedRange()
        let whole = text.paragraphRange(for: selection)
        var result: [NSRange] = []
        var location = whole.location
        repeat {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            result.append(paragraph)
            location = NSMaxRange(paragraph)
        } while location < NSMaxRange(whole)
        return result
    }

    private func listKind(at location: Int) -> ListKind? {
        guard let storage = textView?.textStorage, location < storage.length else { return nil }
        return (storage.attribute(Self.listKey, at: location, effectiveRange: nil) as? String).flatMap(ListKind.init)
    }

    /// Lengte van "•\t" of "12.\t" aan het begin van de alinea (0 als het er niet staat).
    private func markerLength(at location: Int, text: NSAttributedString) -> Int {
        let string = text.string as NSString
        let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
        return (markerText(string.substring(with: paragraph)) as NSString).length
    }

    private func markerText(_ text: String) -> String {
        guard let range = text.range(of: #"^(•|\d+\.)\t"#, options: .regularExpression) else { return "" }
        return String(text[range])
    }

    private func addMarker(_ kind: ListKind, at location: Int, text: NSMutableAttributedString) {
        var attributes = location < text.length
            ? text.attributes(at: location, effectiveRange: nil) : (textView?.typingAttributes ?? [:])
        attributes[.link] = nil
        let marker = NSAttributedString(string: kind == .bullet ? "•\t" : "0.\t", attributes: attributes)
        text.insert(marker, at: location)
        let paragraph = (text.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        let style = (attributes[.paragraphStyle] as? NSParagraphStyle) ?? .default
        text.addAttribute(.paragraphStyle, value: Self.paragraphStyle(level: style.firstLineHeadIndent, list: true),
                          range: paragraph)
        text.addAttribute(Self.listKey, value: kind.rawValue, range: paragraph)
    }

    private func removeMarker(in paragraph: NSRange, text: NSMutableAttributedString) {
        let length = markerLength(at: paragraph.location, text: text)
        if length > 0 { text.deleteCharacters(in: NSRange(location: paragraph.location, length: length)) }
        let rest = (text.string as NSString).paragraphRange(for: NSRange(location: paragraph.location, length: 0))
        guard rest.length > 0 else { return }
        text.removeAttribute(Self.listKey, range: rest)
        let style = (text.attribute(.paragraphStyle, at: rest.location, effectiveRange: nil) as? NSParagraphStyle)
            ?? .default
        text.addAttribute(.paragraphStyle, value: Self.paragraphStyle(level: style.firstLineHeadIndent, list: false),
                          range: rest)
    }

    /// Inspringen op `level`; een lijst krijgt een hangende inspringing zodat de tekst naast het teken uitlijnt.
    static func paragraphStyle(level: CGFloat, list: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = level
        style.headIndent = list ? level + markerWidth : level
        style.tabStops = list ? [NSTextTab(textAlignment: .left, location: level + markerWidth)] : []
        style.defaultTabInterval = 28
        return style
    }

    // MARK: Wijzigen met ongedaan maken

    /// Wijzigt een kopie en zet die in één keer terug, met de nieuwe tekst erbij: zo kan ⌘Z het precies
    /// terugzetten, ook als er tekens (lijsttekens) bij of af gaan. Geeft het lengteverschil terug.
    @discardableResult
    private func edit(_ textView: NSTextView, _ body: (NSMutableAttributedString) -> Void) -> Int {
        guard let storage = textView.textStorage else { return 0 }
        let updated = NSMutableAttributedString(attributedString: storage)
        body(updated)
        let whole = NSRange(location: 0, length: storage.length)
        let selection = textView.selectedRange()
        guard textView.shouldChangeText(in: whole, replacementString: updated.string) else { return 0 }
        storage.replaceCharacters(in: whole, with: updated)
        textView.didChangeText()
        let location = min(selection.location, storage.length)
        textView.setSelectedRange(NSRange(location: location, length: min(selection.length, storage.length - location)))
        return updated.length - whole.length
    }

    private func replace(_ range: NSRange, with text: NSAttributedString) {
        guard let textView, let storage = textView.textStorage,
              textView.shouldChangeText(in: range, replacementString: text.string) else { return }
        storage.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + text.length, length: 0))
    }

    /// Vervangt de eerste keer dat `quote` voorkomt (verbetering van Claude), met de opmaak van wat er stond.
    func replaceFirst(_ quote: String, with replacement: String) -> Bool {
        guard let textView, let storage = textView.textStorage else { return false }
        let range = (storage.string as NSString).range(of: quote)
        guard range.location != NSNotFound else { return false }
        let attributes = storage.attributes(at: range.location, effectiveRange: nil)
        replace(range, with: NSAttributedString(string: replacement, attributes: attributes))
        return true
    }

    /// Plakt tekst achteraan, in de standaardopmaak (suggestie van Claude).
    func append(_ text: String) -> Bool {
        guard let textView, let storage = textView.textStorage else { return false }
        replace(NSRange(location: storage.length, length: 0),
                with: NSAttributedString(string: text, attributes: Self.defaultAttributes))
        return true
    }

    // MARK: Uitvoer

    func html() -> String? {
        guard let storage = textView?.textStorage else { return nil }
        return RichHTML.html(from: storage)
    }

    func rtf() -> Data? {
        guard let storage = textView?.textStorage else { return nil }
        return storage.rtf(from: NSRange(location: 0, length: storage.length), documentAttributes: [:])
    }

    func refreshState() {
        guard let textView else { return }
        let attributes: [NSAttributedString.Key: Any]
        if let storage = textView.textStorage, textView.selectedRange().length > 0 {
            attributes = storage.attributes(at: textView.selectedRange().location, effectiveRange: nil)
        } else {
            attributes = textView.typingAttributes
        }
        let font = (attributes[.font] as? NSFont) ?? Self.defaultFont
        let traits = NSFontManager.shared.traits(of: font)
        var next = State()
        next.isBold = traits.contains(.boldFontMask)
        next.isItalic = traits.contains(.italicFontMask)
        next.isUnderline = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
        next.isStrikethrough = ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0
        next.list = (attributes[Self.listKey] as? String).flatMap(ListKind.init)
        next.family = font.familyName ?? Self.defaultFamily
        next.size = font.pointSize
        if next != state { state = next }
    }
}

// MARK: - HTML

/// Opgemaakte tekst naar eenvoudige HTML die mailprogramma's goed tonen: per alinea een div (of een li in een lijst),
/// stijlen inline. Alleen wat afwijkt van de standaard (Helvetica 13, tekstkleur) komt erin.
enum RichHTML {
    @MainActor
    static func html(from text: NSAttributedString) -> String {
        let string = text.string as NSString
        var output = ""
        var openList: (tag: String, level: Int)?
        var location = 0
        while location < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(paragraph)
            var content = paragraph
            while content.length > 0, isLineBreak(string.character(at: NSMaxRange(content) - 1)) { content.length -= 1 }
            let attributes = text.attributes(at: paragraph.location, effectiveRange: nil)
            let level = Int(((attributes[.paragraphStyle] as? NSParagraphStyle)?.firstLineHeadIndent ?? 0).rounded())
            if let kind = attributes[RichTextController.listKey] as? String {
                let tag = kind == RichTextController.ListKind.number.rawValue ? "ol" : "ul"
                if openList?.tag != tag || openList?.level != level {
                    if let openList { output += "</\(openList.tag)>" }
                    output += "<\(tag) style=\"margin: 0 0 0 \(level)px; padding-left: 24px;\">"
                    openList = (tag, level)
                }
                // Het teken ("•\t", "3.\t") maakt de lijst zelf.
                let marker = (string.substring(with: content) as NSString)
                    .range(of: #"^(•|\d+\.)\t"#, options: .regularExpression)
                let skip = marker.location == NSNotFound ? 0 : marker.length
                let item = NSRange(location: content.location + skip, length: max(0, content.length - skip))
                output += "<li>" + inline(text, range: item) + "</li>"
            } else {
                if let openList { output += "</\(openList.tag)>" }
                openList = nil
                let inner = inline(text, range: content)
                let style = level > 0 ? " style=\"margin-left: \(level)px;\"" : ""
                output += "<div\(style)>" + (inner.isEmpty ? "<br>" : inner) + "</div>"
            }
        }
        if let openList { output += "</\(openList.tag)>" }
        return output
    }

    @MainActor
    private static func inline(_ text: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        var html = ""
        text.enumerateAttributes(in: range) { attributes, run, _ in
            var piece = escape((text.string as NSString).substring(with: run))
            var styles: [String] = []
            var bold = false, italic = false
            if let font = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                bold = traits.contains(.boldFontMask)
                italic = traits.contains(.italicFontMask)
                if let family = font.familyName, family != RichTextController.defaultFamily, !family.hasPrefix(".") {
                    styles.append("font-family: '\(family.replacingOccurrences(of: "'", with: ""))', sans-serif")
                }
                if abs(font.pointSize - RichTextController.defaultSize) > 0.1 {
                    styles.append("font-size: \(Int(font.pointSize.rounded()))px")
                }
            }
            if let color = hex(attributes[.foregroundColor] as? NSColor) { styles.append("color: \(color)") }
            if let color = hex(attributes[.backgroundColor] as? NSColor) { styles.append("background-color: \(color)") }
            if !styles.isEmpty { piece = "<span style=\"\(styles.joined(separator: "; "))\">\(piece)</span>" }
            if ((attributes[.underlineStyle] as? Int) ?? 0) != 0 { piece = "<u>\(piece)</u>" }
            if ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0 { piece = "<s>\(piece)</s>" }
            if italic { piece = "<i>\(piece)</i>" }
            if bold { piece = "<b>\(piece)</b>" }
            let link: String? = switch attributes[.link] {
            case let url as URL: url.absoluteString
            case let string as String: string
            default: nil
            }
            if let link { piece = "<a href=\"\(escape(link))\">\(piece)</a>" }
            html += piece
        }
        return html
    }

    /// Alleen een gekozen kleur; de standaardtekstkleur (wit in donkere weergave) niet.
    private static func hex(_ color: NSColor?) -> String? {
        guard let color, color.type != .catalog, let rgb = color.usingColorSpace(.sRGB), rgb.alphaComponent > 0.01
        else { return nil }
        let value = { (component: CGFloat) in Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", value(rgb.redComponent), value(rgb.greenComponent),
                      value(rgb.blueComponent))
    }

    private static func isLineBreak(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x2029
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\u{2028}", with: "<br>")
            .replacingOccurrences(of: "\t", with: "&nbsp;&nbsp;&nbsp;&nbsp;")
            .replacingOccurrences(of: "  ", with: " &nbsp;")
    }
}

// MARK: - Tekstvak

/// Het opstelveld zelf: vangt ⌘B, ⌘I, ⌘U en ⌘K op als het de cursor heeft, zodat ze bij het juiste veld
/// uitkomen (er kunnen twee opstelvelden open staan).
final class RichNSTextView: NSTextView {
    weak var controller: RichTextController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, let controller,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "b": controller.toggleBold()
        case "i": controller.toggleItalic()
        case "u": controller.toggleUnderline()
        case "k": controller.requestLink()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

// MARK: - Werkbalk

/// Opmaakknoppen boven het opstelveld, zoals in Spark.
struct RichTextToolbar: View {
    let controller: RichTextController
    @State private var linkText = ""
    @State private var editingLink = false

    private static let families = ["Helvetica", "Arial", "Verdana", "Georgia", "Times New Roman", "Courier New"]
    private static let sizes: [CGFloat] = [10, 11, 12, 13, 14, 16, 18, 24]
    private static let colors: [(name: String, hex: Int)] = [
        ("Zwart", 0x000000), ("Grijs", 0x6E6E73), ("Rood", 0xD70015), ("Oranje", 0xC93400), ("Groen", 0x248A3D),
        ("Blauw", 0x0A60FF), ("Paars", 0x8944AB),
    ]
    private static let highlights: [(name: String, hex: Int)] = [
        ("Geel", 0xFFF3A3), ("Groen", 0xC9F2C7), ("Blauw", 0xCFE8FF), ("Roze", 0xFFD6E8),
    ]

    var body: some View {
        let state = controller.state
        HStack(spacing: 2) {
            toggle("bold", on: state.isBold, label: "Vet (⌘B)") { controller.toggleBold() }
            toggle("italic", on: state.isItalic, label: "Cursief (⌘I)") { controller.toggleItalic() }
            toggle("underline", on: state.isUnderline, label: "Onderstreept (⌘U)") { controller.toggleUnderline() }
            toggle("strikethrough", on: state.isStrikethrough, label: "Doorgehaald") {
                controller.toggleStrikethrough()
            }
            separator
            Menu {
                ForEach(Self.families, id: \.self) { family in
                    Button(family) { controller.setFamily(family) }
                }
            } label: {
                Text(state.family)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 128, alignment: .leading)
            .help("Lettertype")
            Menu {
                ForEach(Self.sizes, id: \.self) { size in
                    Button("\(Int(size))") { controller.setSize(size) }
                }
            } label: {
                Text("\(Int(state.size.rounded()))").monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .frame(width: 46, alignment: .leading)
            .help("Grootte")
            separator
            Menu {
                Button("Standaard") { controller.setColor(nil) }
                ForEach(Self.colors, id: \.name) { item in
                    Button(item.name) { controller.setColor(Self.color(item.hex)) }
                }
            } label: {
                Image(systemName: "paintbrush.pointed")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Tekstkleur")
            Menu {
                Button("Geen") { controller.setHighlight(nil) }
                ForEach(Self.highlights, id: \.name) { item in
                    Button(item.name) { controller.setHighlight(Self.color(item.hex)) }
                }
            } label: {
                Image(systemName: "highlighter")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Markeren")
            separator
            toggle("list.bullet", on: state.list == .bullet, label: "Opsomming") { controller.toggleList(.bullet) }
            toggle("list.number", on: state.list == .number, label: "Nummering") { controller.toggleList(.number) }
            button("decrease.indent", label: "Minder inspringen") { controller.indent(-1) }
            button("increase.indent", label: "Meer inspringen") { controller.indent(1) }
            separator
            button("link", label: "Link (⌘K)") { openLinkEditor() }
                .popover(isPresented: $editingLink, arrowEdge: .bottom) { linkEditor }
            button("eraser", label: "Opmaak wissen") { controller.clearFormatting() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: controller.linkRequest) { _, _ in openLinkEditor() }
    }

    private var separator: some View {
        Rectangle()
            .fill(ThingsColor.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 5)
    }

    private func toggle(_ symbol: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.werk(size: 13, weight: .medium))
                .foregroundStyle(on ? ThingsColor.accent : ThingsColor.textSecondary)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(on ? ThingsColor.accent.opacity(0.14) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        toggle(symbol, on: false, label: label, action: action)
    }

    private var linkEditor: some View {
        HStack(spacing: 8) {
            Text("Adres")
                .font(.werk(size: 12, weight: .semibold))
                .foregroundStyle(Color.fieldLabel)
            TextField("", text: $linkText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(applyLink)
            Button("Link", action: applyLink)
                .keyboardShortcut(.defaultAction)
            if controller.currentLink != nil {
                Button("Weg") {
                    controller.setLink("")
                    closeLinkEditor()
                }
            }
        }
        .padding(12)
    }

    private func openLinkEditor() {
        linkText = controller.currentLink ?? ""
        editingLink = true
    }

    private func applyLink() {
        controller.setLink(linkText)
        closeLinkEditor()
    }

    private func closeLinkEditor() {
        editingLink = false
        if let textView = controller.textView { textView.window?.makeFirstResponder(textView) }
    }

    private static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
