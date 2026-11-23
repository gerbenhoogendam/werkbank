import Foundation

// MARK: - Model

/// Een stuk tekst in een handtekening met één opmaak.
public struct SignatureRun: Codable, Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    /// "#RRGGBB"; `nil`: de kleur van het blok (bij een link: de linkkleur van de handtekening).
    public var color: String?
    /// Het adres van een link (https:, mailto:, tel:); `nil`: geen link.
    public var link: String?

    public init(text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false,
                color: String? = nil, link: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.color = color
        self.link = link
    }

    /// Dezelfde opmaak (de tekst telt niet mee).
    public func sameStyle(as other: SignatureRun) -> Bool {
        bold == other.bold && italic == other.italic && underline == other.underline && color == other.color
            && link == other.link
    }
}

public enum SignatureAlignment: String, Codable, Sendable, CaseIterable {
    case left, center, right
}

/// Eén blok van de handtekening, van boven naar beneden: tekst, het logo, of HTML die niet als blok te lezen was.
public struct SignatureBlock: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text, logo, html
    }

    public var id: UUID
    public var kind: Kind
    /// Ruimte boven dit blok in px (bij het eerste blok: boven de hele handtekening).
    public var spaceAbove: Int
    public var alignment: SignatureAlignment

    // Tekst. `nil`: die van de hele handtekening.
    public var runs: [SignatureRun]
    public var fontFamily: String?
    public var fontSize: Double?
    public var color: String?
    /// Regelafstand als factor van de lettergrootte.
    public var lineHeight: Double?

    // Logo (de afbeelding zelf staat bij de handtekening, `cid:`).
    public var width: Int
    public var height: Int
    public var link: String?
    public var alt: String

    // HTML die als geheel blijft staan.
    public var rawHTML: String

    public init(id: UUID = UUID(), kind: Kind, spaceAbove: Int = 0, alignment: SignatureAlignment = .left,
                runs: [SignatureRun] = [], fontFamily: String? = nil, fontSize: Double? = nil, color: String? = nil,
                lineHeight: Double? = nil, width: Int = 200, height: Int = 52, link: String? = nil, alt: String = "",
                rawHTML: String = "") {
        self.id = id
        self.kind = kind
        self.spaceAbove = spaceAbove
        self.alignment = alignment
        self.runs = runs
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.color = color
        self.lineHeight = lineHeight
        self.width = width
        self.height = height
        self.link = link
        self.alt = alt
        self.rawHTML = rawHTML
    }

    public static func text(_ runs: [SignatureRun], spaceAbove: Int = 0) -> SignatureBlock {
        SignatureBlock(kind: .text, spaceAbove: spaceAbove, runs: runs)
    }

    public static func logo(width: Int, height: Int, spaceAbove: Int = 0, link: String? = nil,
                            alt: String = "") -> SignatureBlock {
        SignatureBlock(kind: .logo, spaceAbove: spaceAbove, width: width, height: height, link: link, alt: alt)
    }

    /// De platte tekst (voor de lijst met blokken).
    public var plainText: String { runs.map(\.text).joined() }

    /// Bevat een link (in de tekst, of op het logo).
    public var hasLink: Bool {
        switch kind {
        case .text: runs.contains { $0.link != nil }
        case .logo: link?.isEmpty == false
        case .html: rawHTML.range(of: "<a ", options: .caseInsensitive) != nil
        }
    }

    /// Opeenvolgende stukken met dezelfde opmaak samengevoegd, lege weg.
    public static func merged(_ runs: [SignatureRun]) -> [SignatureRun] {
        var result: [SignatureRun] = []
        for run in runs where !run.text.isEmpty {
            if let last = result.last, last.sameStyle(as: run) {
                result[result.count - 1].text += run.text
            } else {
                result.append(run)
            }
        }
        return result
    }
}

/// De hele handtekening: blokken onder elkaar met vaste ruimtes, als HTML met een tabel en inline-stijlen (zo houden
/// Gmail en Outlook de maten aan).
public struct SignatureDocument: Codable, Equatable, Sendable {
    public var fontFamily: String
    public var fontSize: Double
    public var color: String
    public var linkColor: String
    public var lineHeight: Double
    /// Hoogstens zo breed (px).
    public var width: Int
    /// Ruimte onder het laatste blok (px).
    public var spaceBelow: Int
    public var blocks: [SignatureBlock]

    public init(fontFamily: String = "Helvetica", fontSize: Double = 13, color: String = "#1D1D1F",
                linkColor: String = "#1A4FD6", lineHeight: Double = 1.45, width: Int = 600, spaceBelow: Int = 0,
                blocks: [SignatureBlock] = []) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.color = color
        self.linkColor = linkColor
        self.lineHeight = lineHeight
        self.width = width
        self.spaceBelow = spaceBelow
        self.blocks = blocks
    }

    /// Lettertypen die in elk mailprogramma bestaan.
    public static let fonts = ["Helvetica", "Arial", "Verdana", "Tahoma", "Trebuchet MS", "Georgia", "Times New Roman",
                               "Courier New"]

    /// CSS voor een lettertype, met terugval.
    public static func fontStack(_ family: String) -> String {
        switch family.lowercased() {
        case "helvetica": "Helvetica, Arial, sans-serif"
        case "arial": "Arial, Helvetica, sans-serif"
        case "verdana": "Verdana, Geneva, sans-serif"
        case "tahoma": "Tahoma, Verdana, sans-serif"
        case "trebuchet ms": "'Trebuchet MS', Helvetica, sans-serif"
        case "georgia": "Georgia, 'Times New Roman', serif"
        case "times new roman": "'Times New Roman', Times, serif"
        case "courier new": "'Courier New', Courier, monospace"
        default: "'\(family.replacingOccurrences(of: "'", with: ""))', Helvetica, Arial, sans-serif"
        }
    }

    public var hasLogo: Bool { blocks.contains { $0.kind == .logo } }

    // Wat een blok werkelijk gebruikt.
    public func fontFamily(of block: SignatureBlock) -> String { block.fontFamily ?? fontFamily }
    public func fontSize(of block: SignatureBlock) -> Double { block.fontSize ?? fontSize }
    public func color(of block: SignatureBlock) -> String { block.color ?? color }
    public func lineHeight(of block: SignatureBlock) -> Double { block.lineHeight ?? lineHeight }
    /// Regelafstand in px, op een tiende.
    public func lineHeightPixels(of block: SignatureBlock) -> Double {
        (fontSize(of: block) * lineHeight(of: block) * 10).rounded() / 10
    }

    // MARK: HTML

    /// De HTML die onder een mail komt. Het logo als `cid:logo` (bij versturen naar het echte Content-ID).
    public func html() -> String {
        guard !blocks.isEmpty else { return "" }
        var html = "<table cellpadding=\"0\" cellspacing=\"0\" border=\"0\" role=\"presentation\" style=\""
            + "border-collapse:collapse;font-family:\(Self.fontStack(fontFamily));font-size:\(Self.number(fontSize))px;"
            + "color:\(color);max-width:\(width)px\">\n"
        for block in blocks {
            if block.spaceAbove > 0 { html += Self.spacer(block.spaceAbove) }
            html += row(block)
        }
        if spaceBelow > 0 { html += Self.spacer(spaceBelow) }
        html += "</table>"
        return html
    }

    private static func spacer(_ height: Int) -> String {
        "<tr><td height=\"\(height)\" style=\"height:\(height)px;font-size:0;line-height:0\">&nbsp;</td></tr>\n"
    }

    private func row(_ block: SignatureBlock) -> String {
        let align = block.alignment.rawValue
        switch block.kind {
        case .text:
            var style = ""
            if let family = block.fontFamily { style += "font-family:\(Self.fontStack(family));" }
            style += "font-size:\(Self.number(fontSize(of: block)))px;"
            style += "line-height:\(Self.number(lineHeightPixels(of: block)))px;"
            if let color = block.color { style += "color:\(color);" }
            style += "text-align:\(align)"
            return "<tr><td align=\"\(align)\" style=\"\(style)\">\(textHTML(block))</td></tr>\n"
        case .logo:
            let margin = switch block.alignment {
            case .left: ""
            case .center: "margin:0 auto;"
            case .right: "margin:0 0 0 auto;"
            }
            // Zonder bekende maat (nog niet gemeten) geen maat: dan de echte grootte van het plaatje.
            let sized = block.width > 0 && block.height > 0
            var image = "<img src=\"cid:logo\" "
                + (sized ? "width=\"\(block.width)\" height=\"\(block.height)\" " : "")
                + "alt=\"\(Self.escapeAttribute(block.alt))\" style=\"display:block;\(margin)border:0"
                + (sized ? ";width:\(block.width)px;height:\(block.height)px\">" : "\">")
            if let link = block.link, !link.isEmpty {
                image = "<a href=\"\(Self.escapeAttribute(link))\" style=\"text-decoration:none\">\(image)</a>"
            }
            return "<tr><td align=\"\(align)\" style=\"text-align:\(align)\">\(image)</td></tr>\n"
        case .html:
            return "<tr><td align=\"\(align)\">\(block.rawHTML)</td></tr>\n"
        }
    }

    private func textHTML(_ block: SignatureBlock) -> String {
        var html = ""
        for run in SignatureBlock.merged(block.runs) {
            var piece = Self.escapeText(run.text).replacingOccurrences(of: "\n", with: "<br>")
            if run.bold { piece = "<b>\(piece)</b>" }
            if run.italic { piece = "<i>\(piece)</i>" }
            if let link = run.link {
                let color = run.color ?? linkColor
                let decoration = run.underline ? "underline" : "none"
                piece = "<a href=\"\(Self.escapeAttribute(link))\" style=\"color:\(color);"
                    + "text-decoration:\(decoration)\">\(piece)</a>"
            } else {
                if run.underline { piece = "<u>\(piece)</u>" }
                if let color = run.color { piece = "<span style=\"color:\(color)\">\(piece)</span>" }
            }
            html += piece
        }
        return html
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func escapeText(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "  ", with: " &nbsp;")
    }

    static func escapeAttribute(_ text: String) -> String {
        escapeText(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Een link zoals hij in de HTML hoort: e-mail met mailto:, telefoon met tel:, een website met https:.
    public enum LinkKind: String, CaseIterable, Sendable {
        case website, email, phone

        public static func of(_ href: String) -> LinkKind {
            let lower = href.lowercased()
            if lower.hasPrefix("mailto:") { return .email }
            if lower.hasPrefix("tel:") { return .phone }
            return .website
        }

        /// Het adres zonder mailto: of tel: (een website blijft heel).
        public static func address(of href: String) -> String {
            switch of(href) {
            case .email: String(href.dropFirst("mailto:".count))
            case .phone: String(href.dropFirst("tel:".count))
            case .website: href
            }
        }

        public func href(_ address: String) -> String {
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            switch self {
            case .email:
                return "mailto:" + (trimmed.lowercased().hasPrefix("mailto:") ? String(trimmed.dropFirst(7)) : trimmed)
            case .phone:
                let raw = trimmed.lowercased().hasPrefix("tel:") ? String(trimmed.dropFirst(4)) : trimmed
                return "tel:" + raw.filter { $0.isNumber || $0 == "+" }
            case .website:
                if trimmed.isEmpty || trimmed.contains("://") || trimmed.lowercased().hasPrefix("mailto:")
                    || trimmed.lowercased().hasPrefix("tel:") { return trimmed }
                return "https://" + trimmed
            }
        }
    }
}
