import Foundation

/// Een bijlage of inline afbeelding uit een mail.
public struct MailAttachment: Equatable {
    public var name: String
    /// Kleine letters, zonder parameters (`image/png`).
    public var mediaType: String
    public var data: Data
    /// Zonder `<` en `>`; inline afbeeldingen verwijzen hiernaar met `cid:`.
    public var contentID: String?
    /// Content-Location: sommige mailprogramma's verwijzen daarmee (of met de bestandsnaam) vanuit de HTML, zonder cid.
    public var contentLocation: String?
    /// Content-Disposition: inline (bedoeld om in de tekst te staan, niet als bijlage).
    public var isInline: Bool

    public init(name: String, mediaType: String, data: Data, contentID: String? = nil, contentLocation: String? = nil,
                isInline: Bool = false) {
        self.name = name
        self.mediaType = mediaType
        self.data = data
        self.contentID = contentID
        self.contentLocation = contentLocation
        self.isInline = isInline
    }
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
    /// De mail zoals hij op het scherm getoond wordt: de HTML met inline afbeeldingen als data-URL (of de platte tekst
    /// als `<pre>`). Zonder omhulsel: het weergavevenster zet er stijl en een beveiligingsregel omheen.
    public var displayHTML: String = ""
    /// Voor beantwoorden: het Message-ID, de References, het Reply-To-adres en de tekst om uit te citeren.
    public var messageID: String = ""
    public var references: String = ""
    public var replyTo: String = ""
    public var quotableText: String = ""
    /// Echte bijlagen: alles wat niet als afbeelding in de tekst staat (`cid:`), in de volgorde van de mail.
    public var files: [MailAttachment] = []
    /// Voor doorsturen: de HTML van de mail om in een andere mail te zetten (de inhoud van `<body>`, met de stijlen
    /// en zonder scripts; afbeeldingen als `cid:`), en de afbeeldingen waar die naar verwijst. `nil` bij platte tekst.
    public var forwardHTML: String?
    public var forwardImages: [MailAttachment] = []

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

        let forward = walked.html.map { forwardable(html: $0, attachments: attachments) }
        let quotable: String
        if let plain = walked.plain {
            quotable = MIMEBody.tidy(plain)
        } else if let html = walked.html {
            quotable = MIMEBody.tidy(MIMEBody.htmlToText(html))
        } else {
            quotable = ""
        }
        return MailContent(subject: field("subject"), from: field("from"), to: field("to"), cc: field("cc"),
                           date: field("date"), blocks: limitImages(blocks),
                           displayHTML: displayHTML(html: walked.html, plain: walked.plain, attachments: attachments),
                           messageID: field("message-id"), references: field("references"),
                           replyTo: field("reply-to"), quotableText: quotable,
                           files: files(attachments, html: walked.html),
                           forwardHTML: forward?.html, forwardImages: forward?.images ?? [])
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
        let location = header("content-location").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = mediaType.hasPrefix("image/") ? "afbeelding" : "bijlage"
        let attachment = MailAttachment(name: name ?? fallbackName, mediaType: mediaType, data: bytes,
                                        contentID: cid.isEmpty ? nil : cid,
                                        contentLocation: location.isEmpty ? nil : location,
                                        isInline: disposition.hasPrefix("inline"))
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

    // MARK: - Weergave

    private static let cidReference = try! NSRegularExpression(pattern: #"cid:([^"'\s)>]+)"#, options: [.caseInsensitive])

    /// De mail als HTML voor de weergave, met losse webadressen in de tekst klikbaar (`MailLinks`).
    static func displayHTML(html: String?, plain: String?, attachments: [MailAttachment]) -> String {
        if let html {
            return inlineNamedImages(in: inlineCIDImages(in: MailLinks.linkify(html: html), attachments: attachments),
                                     attachments: attachments)
        }
        if let plain { return "<pre class=\"plain\">" + MailLinks.linkify(text: escapeHTML(plain)) + "</pre>" }
        return "<p><i>(Geen inhoud)</i></p>"
    }

    /// Vervangt `cid:`-verwijzingen door data-URL's, zodat de afbeeldingen zonder netwerk op hun plek verschijnen.
    static func inlineCIDImages(in html: String, attachments: [MailAttachment]) -> String {
        let ns = NSString(string: html)
        var result = html
        for match in cidReference.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
            let raw = ns.substring(with: match.range(at: 1))
            let wanted = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: CharacterSet(charactersIn: "<> ")).lowercased()
            guard let attachment = attachments.first(where: { $0.contentID?.lowercased() == wanted }),
                  attachment.mediaType.hasPrefix("image/"),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: "data:\(attachment.mediaType);base64,\(attachment.data.base64EncodedString())")
        }
        return result
    }

    /// Bijlagen die niet via `cid:` in de HTML staan (en niet leeg zijn).
    /// Echte bijlagen: zonder de afbeeldingen waar de HTML naar verwijst (met cid, Content-Location of bestandsnaam),
    /// en zonder kleine ingesloten afbeeldingen waar de tekst niet (meer) naar verwijst: een handtekening of icoon die
    /// bij doorsturen of beantwoorden zijn plek in de tekst kwijt is.
    static func files(_ attachments: [MailAttachment], html: String?) -> [MailAttachment] {
        let references: (cids: Set<String>, names: Set<String>) = html.map { imageReferences(in: $0) } ?? ([], [])
        return attachments.filter { attachment in
            guard !attachment.data.isEmpty else { return false }
            if isReferenced(attachment, references) { return false }
            if html != nil, attachment.mediaType.hasPrefix("image/"), attachment.isInline, attachment.contentID != nil,
               attachment.data.count <= embeddedImageLimit {
                return false
            }
            return true
        }
    }

    /// Kleiner dan dit, ingesloten en nergens in de tekst: een plaatje uit een handtekening, geen bijlage.
    static let embeddedImageLimit = 100_000

    /// Waar de HTML afbeeldingen vandaan haalt: cid-verwijzingen, en losse namen zonder adres ervoor (Content-Location
    /// of bestandsnaam), in kleine letters.
    static func imageReferences(in html: String) -> (cids: Set<String>, names: Set<String>) {
        let ns = NSString(string: html)
        var cids = Set<String>()
        for match in cidReference.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range(at: 1))
            cids.insert((raw.removingPercentEncoding ?? raw).trimmingCharacters(in: CharacterSet(charactersIn: "<> ")).lowercased())
        }
        var names = Set<String>()
        for match in srcAttribute.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let group = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard group.location != NSNotFound else { continue }
            let value = ns.substring(with: group).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, !value.contains(":") else { continue }   // http:, https:, cid:, data:
            let decoded = (value.removingPercentEncoding ?? value).lowercased()
            names.insert(decoded)
            names.insert((decoded as NSString).lastPathComponent)
        }
        return (cids, names)
    }

    static func isReferenced(_ attachment: MailAttachment, _ references: (cids: Set<String>, names: Set<String>)) -> Bool {
        if let cid = attachment.contentID?.lowercased(), references.cids.contains(cid) { return true }
        guard attachment.mediaType.hasPrefix("image/") else { return false }
        var candidates = [attachment.name.lowercased()]
        if let location = attachment.contentLocation?.lowercased() {
            candidates += [location, (location as NSString).lastPathComponent]
        }
        return candidates.contains { !$0.isEmpty && references.names.contains($0) }
    }

    /// Afbeeldingen waar de HTML met hun naam naar verwijst (Content-Location of bestandsnaam, zonder cid): als
    /// data-URL op hun plek.
    static func inlineNamedImages(in html: String, attachments: [MailAttachment]) -> String {
        let images = attachments.filter { $0.mediaType.hasPrefix("image/") }
        guard !images.isEmpty else { return html }
        let ns = NSString(string: html)
        var result = html
        for match in srcAttribute.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
            let group = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard group.location != NSNotFound else { continue }
            let value = ns.substring(with: group).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, !value.contains(":") else { continue }
            let decoded = (value.removingPercentEncoding ?? value).lowercased()
            let names: Set<String> = [decoded, (decoded as NSString).lastPathComponent]
            let references: (cids: Set<String>, names: Set<String>) = ([], names)
            guard let image = images.first(where: { isReferenced($0, references) }),
                  let range = Range(group, in: result) else { continue }
            result.replaceSubrange(range, with: "data:\(image.mediaType);base64,\(image.data.base64EncodedString())")
        }
        return result
    }

    // MARK: Doorsturen

    /// De HTML om in een doorgestuurde mail te zetten en de afbeeldingen erbij: met `cid:` aangeroepen afbeeldingen gaan
    /// mee, en een afbeelding die met zijn naam wordt aangeroepen (Content-Location) krijgt een Content-ID.
    static func forwardable(html: String, attachments: [MailAttachment]) -> (html: String, images: [MailAttachment]) {
        var result = embeddable(html)
        var images: [MailAttachment] = []
        let references = imageReferences(in: result)
        for attachment in attachments where attachment.mediaType.hasPrefix("image/") && !attachment.data.isEmpty {
            if let cid = attachment.contentID?.lowercased(), references.cids.contains(cid) { images.append(attachment) }
        }
        // Afbeeldingen met een naam in plaats van cid: een eigen Content-ID en `cid:` in de HTML.
        var named = attachments.filter { $0.mediaType.hasPrefix("image/") && !$0.data.isEmpty }
        if !named.isEmpty {
            let ns = NSString(string: result)
            for match in srcAttribute.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
                let group = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                guard group.location != NSNotFound else { continue }
                let value = ns.substring(with: group).trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty, !value.contains(":") else { continue }
                let decoded = (value.removingPercentEncoding ?? value).lowercased()
                let names: Set<String> = [decoded, (decoded as NSString).lastPathComponent]
                guard let index = named.firstIndex(where: { isReferenced($0, ([], names)) }),
                      let range = Range(group, in: result) else { continue }
                // Eén Content-ID per afbeelding, ook als hij vaker in de tekst staat.
                if named[index].contentID == nil { named[index].contentID = "doorgestuurd-\(index + 1)@werkbank" }
                let image = named[index]
                if !images.contains(where: { $0.contentID == image.contentID }) { images.append(image) }
                result.replaceSubrange(range, with: "cid:" + (image.contentID ?? ""))
            }
        }
        return (result, images)
    }

    /// De inhoud van `<body>`, met de `<style>`-blokken uit de kop ervoor en zonder scripts: om in een andere mail te
    /// zetten.
    static func embeddable(_ html: String) -> String {
        let ns = NSString(string: html)
        let all = NSRange(location: 0, length: ns.length)
        var styles = ""
        if let head = headBlock.firstMatch(in: html, range: all) {
            let headText = ns.substring(with: head.range)
            let headNS = NSString(string: headText)
            styles = styleBlock.matches(in: headText, range: NSRange(location: 0, length: headNS.length))
                .map { headNS.substring(with: $0.range) }.joined()
        }
        var body: String
        if let match = bodyBlock.firstMatch(in: html, range: all), match.range(at: 1).location != NSNotFound {
            body = ns.substring(with: match.range(at: 1))
        } else {
            body = headBlock.stringByReplacingMatches(in: html, range: all, withTemplate: "")
                .replacingOccurrences(of: #"(?is)<!doctype[^>]*>|</?html\b[^>]*>"#, with: "", options: .regularExpression)
        }
        body = body.replacingOccurrences(of: #"(?is)<script\b.*?</script\s*>"#, with: "", options: .regularExpression)
        return styles + body
    }

    private static let headBlock = try! NSRegularExpression(pattern: #"<head\b.*?</head\s*>"#,
                                                            options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let styleBlock = try! NSRegularExpression(pattern: #"<style\b.*?</style\s*>"#,
                                                             options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let bodyBlock = try! NSRegularExpression(pattern: #"<body\b[^>]*>(.*)</body\s*>"#,
                                                            options: [.caseInsensitive, .dotMatchesLineSeparators])

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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
