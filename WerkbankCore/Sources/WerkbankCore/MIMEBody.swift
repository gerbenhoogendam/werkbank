import Foundation

/// Haalt de leesbare tekst uit een RFC 822/MIME-bericht: text/plain heeft voorrang, anders wordt HTML
/// omgezet naar platte tekst. Bijlagen worden overgeslagen.
public enum MIMEBody {
    /// Maximale lengte van de bewaarde tekst (tekens).
    public static let maxLength = 60_000

    private struct Part {
        var text: String
        var isHTML: Bool
    }

    public static func text(from data: Data) -> String? {
        // Latin-1 is een 1-op-1 afbeelding van bytes naar tekens: zo gaat er niets verloren en kunnen
        // we de bytes van elk deel later met het juiste tekenset opnieuw decoderen.
        guard let raw = String(data: data, encoding: .isoLatin1) else { return nil }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard let part = extract(entity: normalized, depth: 0) else { return nil }
        let cleaned = tidy(part.text)
        guard !cleaned.isEmpty else { return nil }
        return cleaned.count > maxLength ? String(cleaned.prefix(maxLength)) + "…" : cleaned
    }

    // MARK: - Structuur

    private static func extract(entity: String, depth: Int) -> Part? {
        guard depth < 8 else { return nil }
        let (headerText, body) = split(entity)
        let headers = EMLParser.headers(from: headerText)
        func header(_ name: String) -> String {
            headers.first { $0.name.lowercased() == name }?.value ?? ""
        }

        let contentType = header("content-type").lowercased()
        let disposition = header("content-disposition").lowercased()
        if disposition.hasPrefix("attachment") { return nil }

        if contentType.hasPrefix("multipart/"), let boundary = parameter("boundary", in: header("content-type")) {
            var plain: String?
            var html: String?
            for piece in parts(of: body, boundary: boundary) {
                guard let result = extract(entity: piece, depth: depth + 1) else { continue }
                if result.isHTML { html = html ?? result.text } else { plain = plain ?? result.text }
            }
            if let plain { return Part(text: plain, isHTML: false) }
            if let html { return Part(text: html, isHTML: true) }
            return nil
        }

        let isPlain = contentType.isEmpty || contentType.hasPrefix("text/plain")
        let isHTML = contentType.hasPrefix("text/html")
        guard isPlain || isHTML else { return nil }

        let charset = parameter("charset", in: header("content-type")) ?? "utf-8"
        let bytes = decodeTransfer(body, encoding: header("content-transfer-encoding").lowercased())
        guard let text = EMLParser.string(from: bytes, charset: charset) else { return nil }
        return isHTML ? Part(text: htmlToText(text), isHTML: true) : Part(text: text, isHTML: false)
    }

    /// Scheidt headers en inhoud bij de eerste lege regel. Een deel zonder headers begint met een lege regel.
    private static func split(_ entity: String) -> (String, String) {
        if entity.hasPrefix("\n") { return ("", String(entity.dropFirst())) }
        guard let range = entity.range(of: "\n\n") else { return (entity, "") }
        return (String(entity[entity.startIndex..<range.lowerBound]), String(entity[range.upperBound...]))
    }

    private static func parts(of body: String, boundary: String) -> [String] {
        let pieces = body.components(separatedBy: "--" + boundary)
        var result: [String] = []
        for piece in pieces.dropFirst() {            // het eerste stuk is de preambule
            if piece.hasPrefix("--") { break }        // sluitgrens
            // Na de grens staat (spaties en) een regeleinde.
            var text = Substring(piece)
            while let first = text.first, first == " " || first == "\t" { text = text.dropFirst() }
            if text.first == "\n" { text = text.dropFirst() }
            result.append(String(text))
        }
        return result
    }

    private static func parameter(_ name: String, in header: String) -> String? {
        let pattern = name + #"\s*=\s*(?:"([^"]*)"|([^;\s]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = NSString(string: header)
        guard let match = regex.firstMatch(in: header, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for group in 1...2 where match.range(at: group).location != NSNotFound {
            return ns.substring(with: match.range(at: group))
        }
        return nil
    }

    // MARK: - Decoderen

    private static func decodeTransfer(_ body: String, encoding: String) -> Data {
        let bytes = body.data(using: .isoLatin1) ?? Data()
        switch encoding {
        case "base64":
            let stripped = body.filter { !$0.isWhitespace }
            var padded = stripped
            if padded.count % 4 != 0 { padded += String(repeating: "=", count: 4 - padded.count % 4) }
            return Data(base64Encoded: padded) ?? bytes
        case "quoted-printable":
            return decodeQuotedPrintable(bytes)
        default:
            return bytes
        }
    }

    static func decodeQuotedPrintable(_ input: Data) -> Data {
        let chars = [UInt8](input)
        var out = [UInt8]()
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            guard c == UInt8(ascii: "=") else { out.append(c); i += 1; continue }
            if i + 1 < chars.count, chars[i + 1] == 10 {                 // zacht regeleinde: "=\n"
                i += 2
            } else if i + 2 < chars.count,
                      let byte = UInt8(String(decoding: chars[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                out.append(byte)
                i += 3
            } else {
                out.append(c)
                i += 1
            }
        }
        return Data(out)
    }

    // MARK: - Opschonen

    private static func htmlToText(_ html: String) -> String {
        var text = html
        let removals = [#"(?is)<style.*?</style>"#, #"(?is)<script.*?</script>"#, #"(?is)<head[\s>].*?</head>"#, #"(?s)<!--.*?-->"#]
        for pattern in removals { text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression) }
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</(p|div|tr|li|h[1-6]|table)>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, replacement) in entities { text = text.replacingOccurrences(of: entity, with: replacement) }
        return text
    }

    /// Verwijdert regelafsluitende spaties en maakt van meer dan twee lege regels er twee.
    private static func tidy(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }
        var result: [String] = []
        var blanks = 0
        for line in lines {
            if line.isEmpty {
                blanks += 1
                if blanks <= 1 { result.append(line) }
            } else {
                blanks = 0
                result.append(line)
            }
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
