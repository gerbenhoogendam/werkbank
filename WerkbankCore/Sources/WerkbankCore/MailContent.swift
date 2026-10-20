import Foundation

/// Een bijlage of inline afbeelding uit een mail.
public struct MailAttachment: Equatable {
    public var name: String
    /// Kleine letters, zonder parameters (`image/png`).
    public var mediaType: String
    public var data: Data
    /// Zonder `<` en `>`; inline afbeeldingen verwijzen hiernaar met `cid:`.
    public var contentID: String?
}

/// Een stuk van een mail, in de volgorde waarin het in de mail staat.
public enum MailBlock: Equatable {
    case text(String)
    case image(mediaType: String, data: Data, name: String)
    case pdf(data: Data, name: String)
    /// Een bijlage die niet wordt meegestuurd (te groot, onbekend of niet te lezen), met de reden.
    case omitted(name: String, note: String)
}

/// De inhoud van een mail als reeks stukken (tekst en afbeeldingen op hun plek), bedoeld om te laten analyseren.
public struct MailContent: Equatable {
    public var subject: String
    public var from: String
    public var to: String
    public var cc: String
    public var date: String
    public var blocks: [MailBlock]

    /// Kop van de mail als platte tekst (alleen ingevulde regels).
    public var headerText: String {
        [("Van", from), ("Aan", to), ("Cc", cc), ("Datum", date), ("Onderwerp", subject)]
            .filter { !$0.1.isEmpty }
            .map { "\($0.0): \($0.1)" }
            .joined(separator: "\n")
    }

    public var imageCount: Int { blocks.filter { if case .image = $0 { return true } else { return false } }.count }
    public var pdfCount: Int { blocks.filter { if case .pdf = $0 { return true } else { return false } }.count }
    public var omitted: [(name: String, note: String)] {
        blocks.compactMap { if case let .omitted(name, note) = $0 { return (name, note) } else { return nil } }
    }
}

public enum MailContentParser {
    public static let supportedImageTypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp"]
    /// Kleiner dan dit is vrijwel altijd een handtekeningicoontje of tracking-pixel.
    public static let minImageBytes = 3_000
    /// De API weigert afbeeldingen boven 5 MB.
    public static let maxImageBytes = 5_000_000
    public static let maxPDFBytes = 20_000_000
    public static let maxImages = 20
    public static let maxTextAttachmentChars = 30_000

    private struct Walked {
        var plain: String?
        var html: String?
        var attachments: [MailAttachment] = []
    }

    public static func parse(_ data: Data) -> MailContent {
        guard let raw = String(data: data, encoding: .isoLatin1) else {
            return MailContent(subject: "", from: "", to: "", cc: "", date: "", blocks: [])
        }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let (headerText, _) = MIMEBody.split(normalized)
        let headers = EMLParser.headers(from: headerText)
        func field(_ name: String) -> String {
            let value = headers.first { $0.name.lowercased() == name }?.value ?? ""
            return EMLParser.decodeEncodedWords(value).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let walked = walk(entity: normalized, depth: 0)
        let attachments = walked.attachments
        var used = Set<Int>()
        var blocks: [MailBlock] = []

        if let html = walked.html, walked.plain == nil || hasInlineImage(html) {
            blocks = blocksFromHTML(html, attachments: attachments, used: &used)
        } else if let plain = walked.plain {
            let text = MIMEBody.tidy(plain)
            if !text.isEmpty { blocks.append(.text(cap(text))) }
        } else if let html = walked.html {
            let text = MIMEBody.tidy(MIMEBody.htmlToText(html))
            if !text.isEmpty { blocks.append(.text(cap(text))) }
        }

        // Bijlagen die niet inline in de tekst stonden, achteraan.
        for index in attachments.indices where !used.contains(index) {
            blocks.append(contentsOf: block(for: attachments[index]))
        }

        return MailContent(subject: field("subject"), from: field("from"), to: field("to"), cc: field("cc"),
                           date: field("date"), blocks: limitImages(blocks))
    }

    // MARK: - Structuur

    private static func walk(entity: String, depth: Int) -> Walked {
        guard depth < 8 else { return Walked() }
        let (headerText, body) = MIMEBody.split(entity)
        let headers = EMLParser.headers(from: headerText)
        func header(_ name: String) -> String { headers.first { $0.name.lowercased() == name }?.value ?? "" }

        let contentTypeHeader = header("content-type")
        let contentType = contentTypeHeader.lowercased()
        let mediaType = contentType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let disposition = header("content-disposition").lowercased()

        if mediaType.hasPrefix("multipart/"), let boundary = MIMEBody.parameter("boundary", in: contentTypeHeader) {
            let isAlternative = mediaType == "multipart/alternative"
            var result = Walked()
            var plains: [String] = []
            var htmls: [String] = []
            for piece in MIMEBody.parts(of: body, boundary: boundary) {
                let child = walk(entity: piece, depth: depth + 1)
                if let plain = child.plain { plains.append(plain) }
                if let html = child.html { htmls.append(html) }
                result.attachments.append(contentsOf: child.attachments)
            }
            // Bij alternatieven is elke versie dezelfde inhoud: de eerste volstaat. Anders komt alles achter elkaar.
            result.plain = plains.isEmpty ? nil : (isAlternative ? plains[0] : plains.joined(separator: "\n\n"))
            result.html = htmls.isEmpty ? nil : (isAlternative ? htmls[0] : htmls.joined(separator: "\n"))
            return result
        }

        let name = attachmentName(contentType: contentTypeHeader, disposition: header("content-disposition"))
        let isAttachment = disposition.hasPrefix("attachment") || (name != nil && !mediaType.hasPrefix("text/html") && !mediaType.hasPrefix("text/plain"))
        let isPlain = mediaType.isEmpty || mediaType == "text/plain"
        let isHTML = mediaType == "text/html"

        if (isPlain || isHTML) && !isAttachment {
            let charset = MIMEBody.parameter("charset", in: contentTypeHeader) ?? "utf-8"
            let bytes = MIMEBody.decodeTransfer(body, encoding: header("content-transfer-encoding").lowercased())
            guard let text = EMLParser.string(from: bytes, charset: charset) else { return Walked() }
            return isHTML ? Walked(plain: nil, html: text) : Walked(plain: text, html: nil)
        }

        let bytes = MIMEBody.decodeTransfer(body, encoding: header("content-transfer-encoding").lowercased())
        let cid = header("content-id").trimmingCharacters(in: CharacterSet(charactersIn: "<> \t"))
        let fallbackName = mediaType.hasPrefix("image/") ? "afbeelding" : "bijlage"
        let attachment = MailAttachment(name: name ?? fallbackName, mediaType: mediaType, data: bytes,
                                        contentID: cid.isEmpty ? nil : cid)
        return Walked(plain: nil, html: nil, attachments: [attachment])
    }

    private static func attachmentName(contentType: String, disposition: String) -> String? {
        for (header, key) in [(disposition, "filename"), (contentType, "name")] {
            if let extended = MIMEBody.parameter(key + "*", in: header) {
                // RFC 2231: charset'taal'procentcodering
                let pieces = extended.components(separatedBy: "'")
                let encoded = pieces.count >= 3 ? pieces[2...].joined(separator: "'") : extended
                if let decoded = encoded.removingPercentEncoding, !decoded.isEmpty { return decoded }
            }
            if let plain = MIMEBody.parameter(key, in: header), !plain.isEmpty {
                return EMLParser.decodeEncodedWords(plain)
            }
        }
        return nil
    }

    // MARK: - HTML met inline afbeeldingen

    private static let imgTag = try! NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let srcAttribute = try! NSRegularExpression(pattern: #"\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)')"#, options: [.caseInsensitive])

    static func hasInlineImage(_ html: String) -> Bool {
        html.range(of: #"src\s*=\s*["']cid:"#, options: [.regularExpression, .caseInsensitive]) != nil
            || html.range(of: #"src\s*=\s*["']data:image"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func blocksFromHTML(_ html: String, attachments: [MailAttachment], used: inout Set<Int>) -> [MailBlock] {
        let ns = NSString(string: html)
        var blocks: [MailBlock] = []
        var cursor = 0

        func appendText(_ html: String) {
            let text = MIMEBody.tidy(MIMEBody.htmlToText(html))
            if !text.isEmpty { blocks.append(.text(cap(text))) }
        }

        for match in imgTag.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            appendText(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = match.range.location + match.range.length

            let tag = ns.substring(with: match.range)
            let tagNS = NSString(string: tag)
            guard let srcMatch = srcAttribute.firstMatch(in: tag, range: NSRange(location: 0, length: tagNS.length)) else { continue }
            let group = srcMatch.range(at: 1).location != NSNotFound ? 1 : 2
            let src = tagNS.substring(with: srcMatch.range(at: group))

            if src.lowercased().hasPrefix("cid:") {
                let wanted = (String(src.dropFirst(4)).removingPercentEncoding ?? String(src.dropFirst(4)))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "<> ")).lowercased()
                if let index = attachments.firstIndex(where: { $0.contentID?.lowercased() == wanted }) {
                    used.insert(index)
                    blocks.append(contentsOf: block(for: attachments[index]))
                }
            } else if src.lowercased().hasPrefix("data:image/"), let comma = src.firstIndex(of: ",") {
                let header = src[src.startIndex..<comma].lowercased()
                let type = header.dropFirst(5).split(separator: ";").first.map(String.init) ?? ""
                if header.contains("base64"), let data = Data(base64Encoded: String(src[src.index(after: comma)...])) {
                    blocks.append(contentsOf: block(for: MailAttachment(name: "afbeelding", mediaType: type, data: data, contentID: nil)))
                }
            }
            // Afbeeldingen van het web (http/https) worden bewust niet opgehaald: tracking en geen inhoud van de mail zelf.
        }
        appendText(ns.substring(from: cursor))
        return blocks
    }

    // MARK: - Bijlage naar stuk

    private static func block(for attachment: MailAttachment) -> [MailBlock] {
        let type = attachment.mediaType
        let name = attachment.name
        if type.hasPrefix("image/") {
            if !supportedImageTypes.contains(type) {
                return [.omitted(name: name, note: "afbeeldingsformaat \(type) wordt niet ondersteund")]
            }
            if attachment.data.count < minImageBytes { return [] }   // handtekeningicoon of tracking-pixel
            if attachment.data.count > maxImageBytes {
                return [.omitted(name: name, note: "te groot (\(attachment.data.count / 1_000_000) MB, maximaal 5 MB)")]
            }
            return [.image(mediaType: type, data: attachment.data, name: name)]
        }
        if type == "application/pdf" {
            if attachment.data.count > maxPDFBytes {
                return [.omitted(name: name, note: "pdf te groot (\(attachment.data.count / 1_000_000) MB)")]
            }
            return [.pdf(data: attachment.data, name: name)]
        }
        if isTextLike(type: type, name: name) {
            let text = EMLParser.string(from: attachment.data, charset: "utf-8") ?? ""
            if text.isEmpty { return [.omitted(name: name, note: "leeg of niet te lezen als tekst")] }
            let clipped = text.count > maxTextAttachmentChars ? String(text.prefix(maxTextAttachmentChars)) + "\n… (ingekort)" : text
            return [.text("[Inhoud van bijlage \(name)]\n\(clipped)")]
        }
        return [.omitted(name: name, note: "\(type.isEmpty ? "onbekend type" : type) wordt niet gelezen")]
    }

    private static func isTextLike(type: String, name: String) -> Bool {
        if type.hasPrefix("text/") || type == "application/json" || type == "application/xml" { return true }
        let lower = name.lowercased()
        return [".log", ".txt", ".csv", ".json", ".xml", ".ini", ".conf", ".yaml", ".yml"].contains { lower.hasSuffix($0) }
    }

    private static func limitImages(_ blocks: [MailBlock]) -> [MailBlock] {
        var count = 0
        return blocks.map { block in
            guard case let .image(_, _, name) = block else { return block }
            count += 1
            return count > maxImages ? .omitted(name: name, note: "meer dan \(maxImages) afbeeldingen; deze is weggelaten") : block
        }
    }

    private static func cap(_ text: String) -> String {
        text.count > MIMEBody.maxLength ? String(text.prefix(MIMEBody.maxLength)) + "…" : text
    }
}
