import Foundation

/// Bestaande HTML van een handtekening omzetten naar blokken: tekst met vet, cursief, onderstreept, kleur en links;
/// het eerste `cid:`-plaatje als logo; ruimtes (lege regels, lege cellen met een hoogte, marges en padding) als ruimte
/// boven het volgende blok. Wat niet als blok te lezen is (een plaatje van internet, een lijn) blijft als HTML staan.
/// Vergevingsgezind: kapotte HTML levert wat er te lezen viel.
public enum SignatureImport {
    public static func document(fromHTML html: String) -> SignatureDocument {
        var reader = Reader()
        reader.read(html)
        return reader.finish()
    }

    // MARK: - Lezen

    private struct Style {
        var bold = false
        var italic = false
        var underline = false
        /// Kleur van gewone tekst.
        var color: String?
        var link: String?
        /// Kleur en onderstreping die op of in een link zijn gezet.
        var linkColor: String?
        var linkUnderline: Bool?
        var family: String?
        var size: Double?
        var lineHeightPixels: Double?
        var lineHeightFactor: Double?
        var align: SignatureAlignment?
    }

    private struct Element {
        let name: String
        var style: Style
        /// Een lege cel met deze hoogte is ruimte.
        var heightHint: Double?
        var spaceAfter: Double
        let serial: Int
    }

    private struct Piece {
        var run: SignatureRun
        var style: Style
    }

    private struct Reader {
        var stack: [Element] = []
        var pieces: [Piece] = []
        var blocks: [SignatureBlock] = []
        /// Blokken met hun lettertype, grootte, kleur en regelafstand zoals gelezen (voor de standaard van het geheel).
        var measured: [(family: String?, size: Double?, color: String?, lineHeight: Double?)] = []
        var pendingSpace: Double = 0
        var serial = 0
        var hasLogo = false
        var skipUntil: String?

        var style: Style { stack.last?.style ?? Style() }

        static let blockTags: Set<String> = ["p", "div", "tr", "td", "th", "table", "tbody", "thead", "tfoot", "h1",
                                             "h2", "h3", "h4", "h5", "h6", "li", "ul", "ol", "blockquote", "center",
                                             "section", "article", "header", "footer", "body", "html", "pre", "dl",
                                             "dt", "dd"]
        static let voidTags: Set<String> = ["br", "img", "hr", "meta", "link", "input", "col", "wbr", "area", "base",
                                            "source"]
        static let skippedTags: Set<String> = ["style", "script", "head", "title", "xml"]

        mutating func read(_ html: String) {
            let pattern = #"<!--[\s\S]*?-->|<(/?)([a-zA-Z][a-zA-Z0-9:]*)((?:[^>"']|"[^"]*"|'[^']*')*)>"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let ns = html as NSString
            var location = 0
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                if match.range.location > location, skipUntil == nil {
                    text(ns.substring(with: NSRange(location: location, length: match.range.location - location)))
                }
                location = match.range.location + match.range.length
                guard match.range(at: 2).location != NSNotFound else { continue }  // commentaar
                let closing = ns.substring(with: match.range(at: 1)) == "/"
                let name = ns.substring(with: match.range(at: 2)).lowercased()
                let attributes = match.range(at: 3).location == NSNotFound ? "" : ns.substring(with: match.range(at: 3))
                if let skip = skipUntil {
                    if closing, name == skip { skipUntil = nil }
                    continue
                }
                if closing {
                    close(name)
                } else {
                    open(name, attributes: Attributes(attributes),
                         raw: ns.substring(with: match.range), selfClosing: attributes.hasSuffix("/"))
                }
            }
            if location < ns.length, skipUntil == nil { text(ns.substring(from: location)) }
        }

        // MARK: Tags

        mutating func open(_ name: String, attributes: Attributes, raw: String, selfClosing: Bool) {
            if Self.skippedTags.contains(name) {
                if !selfClosing { skipUntil = name }
                return
            }
            switch name {
            case "br":
                append("\n")
                return
            case "img":
                image(attributes, raw: raw)
                return
            case "hr":
                flush()
                blocks.append(SignatureBlock(kind: .html, spaceAbove: takeSpace(), rawHTML: raw))
                measured.append((nil, nil, nil, nil))
                serial += 1
                return
            default:
                break
            }
            if Self.voidTags.contains(name) || selfClosing { return }

            var next = style
            let isBlock = Self.blockTags.contains(name)
            if isBlock { flush() }
            switch name {
            case "b", "strong": next.bold = true
            case "i", "em": next.italic = true
            case "u", "ins": next.underline = true
            case "h1", "h2", "h3", "h4", "h5", "h6": next.bold = true
            case "a":
                if let href = attributes["href"], !href.isEmpty, !href.hasPrefix("#") {
                    next.link = Self.decode(href)
                    next.linkColor = nil
                    next.linkUnderline = nil
                }
            case "font":
                if let color = attributes["color"].flatMap(Self.color) { setColor(color, in: &next) }
                if let face = attributes["face"] { next.family = Self.family(face) }
                if let size = attributes["size"].flatMap(Int.init) {
                    let sizes: [Int: Double] = [1: 10, 2: 13, 3: 16, 4: 18, 5: 24, 6: 32, 7: 48]
                    next.size = sizes[size] ?? next.size
                }
            case "center":
                next.align = .center
            default:
                break
            }
            if let align = attributes["align"].flatMap(Self.alignment) { next.align = align }
            var marginTop: Double = 0
            var marginBottom: Double = 0
            if let css = attributes["style"] {
                let declarations = Self.css(css)
                apply(declarations, to: &next)
                if isBlock {
                    let size = next.size ?? 13
                    marginTop = Self.edge(declarations, "margin", top: true, size: size)
                        + Self.edge(declarations, "padding", top: true, size: size)
                    marginBottom = Self.edge(declarations, "margin", top: false, size: size)
                        + Self.edge(declarations, "padding", top: false, size: size)
                }
            }
            // Een alinea heeft van zichzelf een lege regel ruimte erboven en eronder; één keer meetellen.
            let ownMargin = attributes["style"].map { Self.css($0)["margin"] != nil || Self.css($0)["margin-bottom"] != nil }
            if name == "p", ownMargin != true {
                marginBottom += ((next.size ?? 13) * 1.0).rounded()
            }
            pendingSpace += marginTop
            var height: Double?
            if name == "td" || name == "th" || name == "tr" || name == "div" || name == "p" {
                height = attributes["height"].flatMap(Self.pixels)
                    ?? attributes["style"].flatMap { Self.css($0)["height"] }.flatMap(Self.pixels)
            }
            stack.append(Element(name: name, style: next, heightHint: height, spaceAfter: marginBottom, serial: serial))
        }

        mutating func close(_ name: String) {
            guard let index = stack.lastIndex(where: { $0.name == name }) else { return }
            let element = stack[index]
            if Self.blockTags.contains(name) {
                if let height = element.heightHint, element.serial == serial, isBlank {
                    // Een lege cel of div met een hoogte: ruimte.
                    pieces.removeAll()
                    pendingSpace += height
                } else {
                    flush()
                }
                pendingSpace += element.spaceAfter
            }
            stack.removeSubrange(index...)
        }

        // MARK: Tekst

        mutating func text(_ raw: String) {
            // Witruimte samenvoegen zoals een browser; harde spaties blijven.
            var collapsed = ""
            var lastWasSpace = false
            for scalar in raw.unicodeScalars {
                if scalar == " " || scalar == "\n" || scalar == "\r" || scalar == "\t" {
                    if !lastWasSpace { collapsed.append(" ") }
                    lastWasSpace = true
                } else {
                    collapsed.unicodeScalars.append(scalar)
                    lastWasSpace = false
                }
            }
            append(Self.decode(collapsed))
        }

        mutating func append(_ text: String) {
            var text = text
            // Geen spatie aan het begin van een regel.
            let previous = pieces.last?.run.text.last
            if previous == nil || previous == "\n" || previous == " " {
                while text.first == " " { text.removeFirst() }
            }
            guard !text.isEmpty else { return }
            let current = style
            let isLink = current.link != nil
            let run = SignatureRun(text: text, bold: current.bold, italic: current.italic,
                                   underline: isLink ? (current.linkUnderline ?? true) : current.underline,
                                   color: isLink ? current.linkColor : current.color, link: current.link)
            pieces.append(Piece(run: run, style: current))
        }

        var isBlank: Bool {
            pieces.allSatisfy { $0.run.text.allSatisfy { $0 == " " || $0 == "\u{00A0}" || $0 == "\n" } }
        }

        mutating func takeSpace() -> Int {
            defer { pendingSpace = 0 }
            return Int(pendingSpace.rounded())
        }

        /// Wat er gelezen is wordt een tekstblok (of ruimte als het leeg is).
        mutating func flush() {
            defer { pieces.removeAll() }
            guard !pieces.isEmpty else { return }
            let first = pieces.first { !$0.run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let size = first?.style.size ?? 13
            let lineHeight = Self.lineHeight(first?.style, size: size)
            let linePixels = (size * (lineHeight ?? 1.2)).rounded()
            var runs = pieces.map { piece -> SignatureRun in
                var run = piece.run
                run.text = run.text.replacingOccurrences(of: "\u{00A0}", with: " ")
                return run
            }
            runs = SignatureBlock.merged(runs)
            // Witregels aan het begin en eind worden ruimte.
            var leading = 0
            while let firstRun = runs.first, let character = firstRun.text.first, character == "\n" || character == " " {
                if character == "\n" { leading += 1 }
                runs[0].text.removeFirst()
                if runs[0].text.isEmpty { runs.removeFirst() }
            }
            var trailing = 0
            while let lastRun = runs.last, let character = lastRun.text.last, character == "\n" || character == " " {
                if character == "\n" { trailing += 1 }
                runs[runs.count - 1].text.removeLast()
                if runs[runs.count - 1].text.isEmpty { runs.removeLast() }
            }
            // Spaties voor een regeleinde weg.
            for index in runs.indices {
                while runs[index].text.contains(" \n") {
                    runs[index].text = runs[index].text.replacingOccurrences(of: " \n", with: "\n")
                }
            }
            runs = SignatureBlock.merged(runs)
            if runs.isEmpty {
                // Alleen lege regels: elke regel is ruimte.
                pendingSpace += Double(max(leading, 1)) * linePixels
                return
            }
            pendingSpace += Double(leading) * linePixels
            let plainColors = pieces.filter { $0.run.link == nil }.compactMap(\.style.color)
            let blockColor = Self.mode(plainColors)
            runs = runs.map { run in
                var run = run
                if run.link == nil, run.color == blockColor { run.color = nil }
                return run
            }
            var block = SignatureBlock(kind: .text, spaceAbove: takeSpace(), alignment: first?.style.align ?? .left,
                                       runs: runs)
            block.color = blockColor
            blocks.append(block)
            // Zonder kleur: de tekstkleur van het mailprogramma (zwart).
            measured.append((first?.style.family, first?.style.size, blockColor ?? "#1D1D1F", lineHeight))
            serial += 1
            pendingSpace += Double(max(trailing - 1, 0)) * linePixels
        }

        mutating func image(_ attributes: Attributes, raw: String) {
            flush()
            let source = attributes["src"] ?? ""
            let css = attributes["style"].map(Self.css) ?? [:]
            let width = attributes["width"].flatMap(Self.pixels) ?? css["width"].flatMap(Self.pixels) ?? 0
            let height = attributes["height"].flatMap(Self.pixels) ?? css["height"].flatMap(Self.pixels) ?? 0
            let current = style
            if !hasLogo, source.lowercased().hasPrefix("cid:") || source.lowercased().hasPrefix("data:") {
                hasLogo = true
                var block = SignatureBlock.logo(width: Int(width.rounded()), height: Int(height.rounded()),
                                                spaceAbove: takeSpace(), link: current.link,
                                                alt: Self.decode(attributes["alt"] ?? ""))
                block.alignment = current.align ?? .left
                blocks.append(block)
            } else {
                var html = raw
                if let link = current.link {
                    html = "<a href=\"\(SignatureDocument.escapeAttribute(link))\">\(raw)</a>"
                }
                blocks.append(SignatureBlock(kind: .html, spaceAbove: takeSpace(), alignment: current.align ?? .left,
                                             rawHTML: html))
            }
            measured.append((nil, nil, nil, nil))
            serial += 1
        }

        // MARK: Stijl

        mutating func setColor(_ color: String, in style: inout Style) {
            if style.link != nil { style.linkColor = color } else { style.color = color }
        }

        mutating func apply(_ css: [String: String], to style: inout Style) {
            if let color = css["color"].flatMap(Self.color) { setColor(color, in: &style) }
            if let weight = css["font-weight"] {
                let value = weight.lowercased()
                style.bold = value == "bold" || value == "bolder" || (Int(value) ?? 400) >= 600
            }
            if let fontStyle = css["font-style"] { style.italic = fontStyle.lowercased() == "italic" }
            if let decoration = css["text-decoration"] ?? css["text-decoration-line"] {
                let underline = decoration.lowercased().contains("underline")
                if style.link != nil { style.linkUnderline = underline } else { style.underline = underline }
            }
            if let family = css["font-family"] { style.family = Self.family(family) }
            if let size = css["font-size"].flatMap(Self.fontSize) { style.size = size }
            if let font = css["font"] {
                // "13px/1.5 Helvetica, Arial"
                for part in font.split(separator: " ") {
                    let pieces = part.split(separator: "/")
                    if let size = pieces.first.flatMap({ Self.fontSize(String($0)) }) {
                        style.size = size
                        if pieces.count > 1 { setLineHeight(String(pieces[1]), in: &style) }
                        break
                    }
                }
            }
            if let lineHeight = css["line-height"] { setLineHeight(lineHeight, in: &style) }
            if let align = css["text-align"].flatMap(Self.alignment) { style.align = align }
        }

        func setLineHeight(_ value: String, in style: inout Style) {
            let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
            if lower.hasSuffix("px") || lower.hasSuffix("pt") {
                style.lineHeightPixels = Self.pixels(lower)
                style.lineHeightFactor = nil
            } else if lower.hasSuffix("%"), let percent = Double(lower.dropLast()) {
                style.lineHeightFactor = percent / 100
                style.lineHeightPixels = nil
            } else if let factor = Double(lower) {
                style.lineHeightFactor = factor
                style.lineHeightPixels = nil
            } else if lower == "normal" {
                style.lineHeightFactor = nil
                style.lineHeightPixels = nil
            }
        }

        static func lineHeight(_ style: Style?, size: Double) -> Double? {
            guard let style else { return nil }
            if let pixels = style.lineHeightPixels, pixels > 0, size > 0 { return (pixels / size * 100).rounded() / 100 }
            if let factor = style.lineHeightFactor, factor > 0 { return factor }
            return nil
        }

        // MARK: Afronden

        mutating func finish() -> SignatureDocument {
            flush()
            var document = SignatureDocument()
            document.spaceBelow = Int(pendingSpace.rounded())
            let text = measured.indices.filter { blocks[$0].kind == .text }
            document.fontFamily = Self.mode(text.compactMap { measured[$0].family }) ?? "Helvetica"
            document.fontSize = Self.mode(text.compactMap { measured[$0].size }) ?? 13
            document.color = Self.mode(text.compactMap { measured[$0].color }) ?? "#1D1D1F"
            // Zonder regelafstand toont een mailprogramma "normal": ongeveer 1,2.
            document.lineHeight = Self.mode(text.map { measured[$0].lineHeight ?? 1.2 }) ?? 1.2
            let linkColors = blocks.flatMap(\.runs).filter { $0.link != nil }.compactMap(\.color)
            if let linkColor = Self.mode(linkColors) { document.linkColor = linkColor }
            for index in text {
                let measure = measured[index]
                var block = blocks[index]
                let family = measure.family ?? document.fontFamily
                block.fontFamily = family == document.fontFamily ? nil : family
                let size = measure.size ?? document.fontSize
                block.fontSize = size == document.fontSize ? nil : size
                let color = measure.color ?? document.color
                block.color = color == document.color ? nil : color
                let lineHeight = measure.lineHeight ?? 1.2
                block.lineHeight = lineHeight == document.lineHeight ? nil : lineHeight
                block.runs = block.runs.map { run in
                    var run = run
                    if run.link != nil, run.color == document.linkColor { run.color = nil }
                    return run
                }
                blocks[index] = block
            }
            document.blocks = blocks
            return document
        }

        static func mode<T: Hashable>(_ values: [T]) -> T? {
            var counts: [T: Int] = [:]
            var order: [T] = []
            for value in values {
                if counts[value] == nil { order.append(value) }
                counts[value, default: 0] += 1
            }
            return order.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
        }

        // MARK: Waarden

        static func css(_ text: String) -> [String: String] {
            var result: [String: String] = [:]
            for declaration in decode(text).split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if let important = value.range(of: "!important", options: .caseInsensitive) {
                    value = value[..<important.lowerBound].trimmingCharacters(in: .whitespaces)
                }
                result[key] = value
            }
            return result
        }

        /// margin/padding boven of onder (in px), ook uit de korte schrijfwijze.
        static func edge(_ css: [String: String], _ property: String, top: Bool, size: Double) -> Double {
            if let value = css["\(property)-\(top ? "top" : "bottom")"] { return length(value, size: size) ?? 0 }
            guard let short = css[property] else { return 0 }
            let parts = short.split(separator: " ").map(String.init)
            switch parts.count {
            case 1: return length(parts[0], size: size) ?? 0
            case 2, 3: return length(top ? parts[0] : parts[parts.count == 2 ? 0 : 2], size: size) ?? 0
            case 4: return length(top ? parts[0] : parts[2], size: size) ?? 0
            default: return 0
            }
        }

        static func length(_ value: String, size: Double) -> Double? {
            let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
            if lower.hasSuffix("em"), let number = Double(lower.dropLast(2)) { return max(0, number * size) }
            return pixels(lower).map { max(0, $0) }
        }

        static func pixels(_ value: String) -> Double? {
            let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
            if lower.hasSuffix("px") { return Double(lower.dropLast(2).trimmingCharacters(in: .whitespaces)) }
            if lower.hasSuffix("pt") {
                return Double(lower.dropLast(2).trimmingCharacters(in: .whitespaces)).map { ($0 * 4 / 3).rounded() }
            }
            if lower.hasSuffix("%") { return nil }
            return Double(lower)
        }

        static func fontSize(_ value: String) -> Double? {
            let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
            switch lower {
            case "xx-small": return 9
            case "x-small": return 10
            case "small": return 13
            case "medium": return 16
            case "large": return 18
            case "x-large": return 24
            default: break
            }
            guard lower.hasSuffix("px") || lower.hasSuffix("pt"), let pixels = pixels(lower) else { return nil }
            return (pixels * 2).rounded() / 2
        }

        static func family(_ value: String) -> String? {
            guard let first = decode(value).split(separator: ",").first else { return nil }
            let name = first.trimmingCharacters(in: CharacterSet(charactersIn: " '\"\t"))
            guard !name.isEmpty else { return nil }
            if let known = SignatureDocument.fonts.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                return known
            }
            switch name.lowercased() {
            case "sans-serif", "-apple-system", "system-ui": return "Helvetica"
            case "serif": return "Times New Roman"
            case "monospace": return "Courier New"
            default: return name
            }
        }

        static func alignment(_ value: String) -> SignatureAlignment? {
            switch value.lowercased().trimmingCharacters(in: .whitespaces) {
            case "left", "start", "justify": .left
            case "center", "middle": .center
            case "right", "end": .right
            default: nil
            }
        }

        static func color(_ value: String) -> String? {
            let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
            let names = ["black": "#000000", "white": "#FFFFFF", "gray": "#808080", "grey": "#808080",
                         "red": "#FF0000", "blue": "#0000FF", "navy": "#000080", "green": "#008000",
                         "silver": "#C0C0C0", "darkgray": "#A9A9A9", "darkgrey": "#A9A9A9", "orange": "#FFA500"]
            if let named = names[lower] { return named }
            if lower.hasPrefix("#") {
                let hex = lower.dropFirst()
                guard hex.allSatisfy(\.isHexDigit) else { return nil }
                if hex.count == 3 { return "#" + hex.map { "\($0)\($0)" }.joined().uppercased() }
                if hex.count == 6 { return "#" + hex.uppercased() }
                return nil
            }
            if lower.hasPrefix("rgb") {
                let numbers = lower.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
                    .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard numbers.count >= 3 else { return nil }
                return String(format: "#%02X%02X%02X", Int(min(255, max(0, numbers[0]))),
                              Int(min(255, max(0, numbers[1]))), Int(min(255, max(0, numbers[2]))))
            }
            return nil
        }

        static let entities: [String: String] = [
            "nbsp": "\u{00A0}", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "copy": "©",
            "reg": "®", "trade": "™", "middot": "·", "bull": "•", "ndash": "–", "mdash": "—", "hellip": "…",
            "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "euml": "ë", "eacute": "é", "egrave": "è",
            "ecirc": "ê", "ouml": "ö", "oacute": "ó", "uuml": "ü", "iuml": "ï", "auml": "ä", "aacute": "á",
            "agrave": "à", "ccedil": "ç", "euro": "€", "shy": "",
        ]

        static func decode(_ text: String) -> String {
            guard text.contains("&") else { return text }
            var result = ""
            var index = text.startIndex
            while index < text.endIndex {
                let character = text[index]
                guard character == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                    result.append(character)
                    index = text.index(after: index)
                    continue
                }
                let name = String(text[text.index(after: index)..<semicolon])
                var replacement: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
                } else if name.hasPrefix("#") {
                    replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
                } else {
                    replacement = entities[name.lowercased()]
                }
                if let replacement {
                    result += replacement
                    index = text.index(after: semicolon)
                } else {
                    result.append(character)
                    index = text.index(after: index)
                }
            }
            return result
        }
    }

    /// De attributen van een tag ("name=value", met of zonder aanhalingstekens).
    struct Attributes {
        private var values: [String: String] = [:]

        init(_ text: String) {
            let pattern = #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: match.range(at: 1)).lowercased()
                var value = ""
                for group in 2...4 where match.range(at: group).location != NSNotFound {
                    value = ns.substring(with: match.range(at: group))
                    break
                }
                if values[name] == nil { values[name] = value }
            }
        }

        subscript(_ name: String) -> String? { values[name] }
    }
}
