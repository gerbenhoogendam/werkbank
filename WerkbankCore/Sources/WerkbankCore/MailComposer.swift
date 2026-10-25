import Foundation

/// Een adres met optionele naam, uit een invoerveld ("Jan <jan@x.nl>, piet@y.nl").
public struct MailAddress: Equatable {
    public var name: String?
    public var address: String

    public init(name: String? = nil, address: String) {
        self.name = name
        self.address = address
    }

    /// Splitst op komma's en puntkomma's (niet binnen aanhalingstekens of <>). Ongeldige stukken komen in `invalid`.
    public static func parse(_ text: String) -> (valid: [MailAddress], invalid: [String]) {
        var pieces: [String] = []
        var current = ""
        var inQuotes = false
        var inAngle = false
        for character in text {
            switch character {
            case "\"": inQuotes.toggle(); current.append(character)
            case "<" where !inQuotes: inAngle = true; current.append(character)
            case ">" where !inQuotes: inAngle = false; current.append(character)
            case "," where !inQuotes && !inAngle, ";" where !inQuotes && !inAngle:
                pieces.append(current); current = ""
            default: current.append(character)
            }
        }
        pieces.append(current)

        var valid: [MailAddress] = []
        var invalid: [String] = []
        for raw in pieces.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !raw.isEmpty {
            var name: String?
            var address = raw
            if let open = raw.lastIndex(of: "<"), let close = raw.lastIndex(of: ">"), open < close {
                address = String(raw[raw.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
                let label = String(raw[..<open]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
                if !label.isEmpty { name = label }
            }
            if isPlausible(address) {
                valid.append(MailAddress(name: name, address: address))
            } else {
                invalid.append(raw)
            }
        }
        return (valid, invalid)
    }

    static func isPlausible(_ address: String) -> Bool {
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
            && !address.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" || $0 == "," })
    }

    /// Zoals het in een invoerveld staat: "Naam <adres>" of alleen het adres.
    public var displayString: String {
        guard let name, !name.isEmpty else { return address }
        return "\(name) <\(address)>"
    }

    /// Het adres in de vorm voor een kopregel (naam met codering waar nodig).
    var headerValue: String {
        guard let name, !name.isEmpty else { return address }
        return "\(MailComposer.encodePhrase(name)) <\(address)>"
    }
}

/// Wat er in een uitgaande mail komt.
public struct ComposedMail {
    public var from: MailAddress
    public var to: [MailAddress] = []
    public var cc: [MailAddress] = []
    public var bcc: [MailAddress] = []
    public var subject: String
    public var bodyText: String
    /// De tekst met opmaak (alinea's als div, lijsten, links); zonder: `bodyText` als gewone alinea's.
    public var bodyHTML: String?
    /// Het oorspronkelijke bericht bij beantwoorden of doorsturen, met de aanhef ("Op … schreef …:").
    public var quote: String?
    public var quoteIntro: String?
    public var signatureHTML: String?
    /// Het plaatje dat de handtekening als `cid:` aanroept.
    public var signatureImage: MailAttachment?
    public var attachments: [MailAttachment] = []
    public var inReplyTo: String?
    public var references: String?
    public var date = Date()

    public init(from: MailAddress, subject: String, bodyText: String) {
        self.from = from
        self.subject = subject
        self.bodyText = bodyText
    }
}

/// Bouwt de ruwe mail (RFC 5322 / MIME) voor de Gmail API. Alles wordt als UTF-8 en base64 verstuurd.
public enum MailComposer {
    /// Het Content-ID waaronder het handtekeningplaatje meegaat.
    public static let signatureContentID = "signature-logo@werkbank"

    public static func build(_ mail: ComposedMail) -> Data {
        let signatureText = mail.signatureHTML.map { MIMEBody.tidy(MIMEBody.htmlToText($0)) }
        let html = htmlBody(mail)

        // Leesbare tekstversie
        var text = mail.bodyText
        if let signatureText, !signatureText.isEmpty { text += "\n\n-- \n" + signatureText }
        if let quote = mail.quote, !quote.isEmpty {
            text += "\n\n"
            if let intro = mail.quoteIntro { text += intro + "\n" }
            text += quote.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
                .map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
        }

        let hasInline = mail.signatureImage != nil && (mail.signatureHTML?.contains("cid:") ?? false)
        let alternativeBoundary = boundary("alt")
        let relatedBoundary = boundary("rel")
        let mixedBoundary = boundary("mix")

        // multipart/alternative( text, [multipart/related( html, logo )] )
        var htmlEntity: Data
        if hasInline, let image = mail.signatureImage {
            var related = Data()
            related.append(line("Content-Type: multipart/related; boundary=\"\(relatedBoundary)\"; type=\"text/html\""))
            related.append(line(""))
            related.append(line("--\(relatedBoundary)"))
            related.append(textPart(html, type: "text/html"))
            related.append(line("--\(relatedBoundary)"))
            related.append(filePart(image, contentID: signatureContentID, inline: true))
            related.append(line("--\(relatedBoundary)--"))
            htmlEntity = related
        } else {
            htmlEntity = textPart(html, type: "text/html")
        }

        var alternative = Data()
        alternative.append(line("Content-Type: multipart/alternative; boundary=\"\(alternativeBoundary)\""))
        alternative.append(line(""))
        alternative.append(line("--\(alternativeBoundary)"))
        alternative.append(textPart(text, type: "text/plain"))
        alternative.append(line("--\(alternativeBoundary)"))
        alternative.append(htmlEntity)
        alternative.append(line("--\(alternativeBoundary)--"))

        var message = Data()
        for header in headers(for: mail) { message.append(line(header)) }
        if mail.attachments.isEmpty {
            message.append(alternative)
        } else {
            message.append(line("Content-Type: multipart/mixed; boundary=\"\(mixedBoundary)\""))
            message.append(line(""))
            message.append(line("--\(mixedBoundary)"))
            message.append(alternative)
            for attachment in mail.attachments {
                message.append(line("--\(mixedBoundary)"))
                message.append(filePart(attachment, contentID: nil, inline: false))
            }
            message.append(line("--\(mixedBoundary)--"))
        }
        return message
    }

    // MARK: Kop

    private static func headers(for mail: ComposedMail) -> [String] {
        var result = ["MIME-Version: 1.0",
                      "Date: \(dateString(mail.date))",
                      "From: \(mail.from.headerValue)"]
        if !mail.to.isEmpty { result.append(fold("To: " + mail.to.map(\.headerValue).joined(separator: ", "))) }
        if !mail.cc.isEmpty { result.append(fold("Cc: " + mail.cc.map(\.headerValue).joined(separator: ", "))) }
        if !mail.bcc.isEmpty { result.append(fold("Bcc: " + mail.bcc.map(\.headerValue).joined(separator: ", "))) }
        result.append(fold("Subject: " + encodeText(mail.subject)))
        if let inReplyTo = mail.inReplyTo, !inReplyTo.isEmpty { result.append("In-Reply-To: \(inReplyTo)") }
        if let references = mail.references, !references.isEmpty { result.append(fold("References: \(references)")) }
        let domain = mail.from.address.split(separator: "@").last.map(String.init) ?? "werkbank.local"
        result.append("Message-ID: <\(UUID().uuidString.lowercased())@\(domain)>")
        return result
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    /// Vouwt lange kopregels (max. 78 tekens) op spaties.
    static func fold(_ header: String) -> String {
        guard header.count > 76 else { return header }
        var lines: [String] = []
        var current = ""
        for word in header.split(separator: " ", omittingEmptySubsequences: false) {
            if !current.isEmpty, current.count + 1 + word.count > 76 {
                lines.append(current)
                current = " " + word
            } else {
                current += (current.isEmpty ? "" : " ") + word
            }
        }
        lines.append(current)
        return lines.joined(separator: "\r\n")
    }

    // MARK: Codering van kopregels (RFC 2047)

    private static func isPlainASCII(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value < 127 }
    }

    /// Onderwerp en dergelijke: ASCII blijft staan, de rest wordt in stukken van `=?UTF-8?B?…?=`.
    static func encodeText(_ text: String) -> String {
        if isPlainASCII(text) { return text }
        var chunks: [String] = []
        var current = Data()
        for character in text {
            let bytes = Data(String(character).utf8)
            if current.count + bytes.count > 42 {
                chunks.append("=?UTF-8?B?\(current.base64EncodedString())?=")
                current = Data()
            }
            current.append(bytes)
        }
        if !current.isEmpty { chunks.append("=?UTF-8?B?\(current.base64EncodedString())?=") }
        return chunks.joined(separator: " ")
    }

    /// Weergavenaam in een adres: tussen aanhalingstekens als er speciale tekens in staan.
    static func encodePhrase(_ name: String) -> String {
        if !isPlainASCII(name) { return encodeText(name) }
        let specials = CharacterSet(charactersIn: "()<>[]:;@\\,.\"")
        if name.unicodeScalars.contains(where: { specials.contains($0) }) {
            return "\"" + name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return name
    }

    // MARK: Delen

    private static func boundary(_ tag: String) -> String {
        "=_werkbank_\(tag)_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    private static func line(_ text: String) -> Data { Data((text + "\r\n").utf8) }

    private static func base64Lines(_ data: Data) -> Data {
        var encoded = data.base64EncodedData(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        encoded.append(Data("\r\n".utf8))
        return encoded
    }

    private static func textPart(_ text: String, type: String) -> Data {
        var part = Data()
        part.append(line("Content-Type: \(type); charset=UTF-8"))
        part.append(line("Content-Transfer-Encoding: base64"))
        part.append(line(""))
        part.append(base64Lines(Data(text.utf8)))
        return part
    }

    private static func filePart(_ attachment: MailAttachment, contentID: String?, inline: Bool) -> Data {
        let type = attachment.mediaType.isEmpty ? "application/octet-stream" : attachment.mediaType
        var part = Data()
        part.append(line("Content-Type: \(type); \(parameter("name", attachment.name))"))
        part.append(line("Content-Transfer-Encoding: base64"))
        if let contentID { part.append(line("Content-ID: <\(contentID)>")) }
        part.append(line("Content-Disposition: \(inline ? "inline" : "attachment"); \(parameter("filename", attachment.name))"))
        part.append(line(""))
        part.append(base64Lines(attachment.data))
        return part
    }

    /// `name="x.pdf"`, of voor andere tekens RFC 2231 (`name*=UTF-8''…`).
    static func parameter(_ key: String, _ value: String) -> String {
        if isPlainASCII(value) {
            return "\(key)=\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return "\(key)*=UTF-8''\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "bijlage")"
    }

    // MARK: HTML

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func paragraphs(_ text: String) -> String {
        escape(text.replacingOccurrences(of: "\r\n", with: "\n")).replacingOccurrences(of: "\n", with: "<br>\n")
    }

    private static func htmlBody(_ mail: ComposedMail) -> String {
        var html = "<html><body><div style=\"font-family: Helvetica, Arial, sans-serif; font-size: 13px;\">"
        html += (mail.bodyHTML ?? paragraphs(mail.bodyText)) + "</div>"
        if var signature = mail.signatureHTML, !signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if mail.signatureImage != nil {
                signature = signature.replacingOccurrences(of: #"cid:[^"'\s>)]+"#, with: "cid:\(signatureContentID)",
                                                           options: .regularExpression)
            } else {
                // Zonder plaatje geen kapot beeld achterlaten.
                signature = signature.replacingOccurrences(of: #"(?is)<img\b[^>]*src\s*=\s*["']cid:[^>]*>"#, with: "",
                                                           options: .regularExpression)
            }
            html += "<br>" + signature
        }
        if let quote = mail.quote, !quote.isEmpty {
            html += "<br><div style=\"font-family: Helvetica, Arial, sans-serif; font-size: 13px;\">"
            if let intro = mail.quoteIntro { html += escape(intro) + "<br>" }
            html += "<blockquote type=\"cite\" style=\"margin: 6px 0 0 0; padding-left: 10px; border-left: 2px solid #c8c8cc; color: #55555a;\">"
            html += paragraphs(quote) + "</blockquote></div>"
        }
        html += "</body></html>"
        return html
    }
}

/// Afleiden van onderwerp, ontvangers en aanhef bij beantwoorden en doorsturen.
public enum ReplyBuilder {
    public static func subject(_ original: String, forward: Bool) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        if forward {
            return ["fwd:", "fw:", "doorgestuurd:"].contains { lower.hasPrefix($0) } ? trimmed : "Fwd: " + trimmed
        }
        return ["re:", "aw:"].contains { lower.hasPrefix($0) } ? trimmed : "Re: " + trimmed
    }

    /// Ontvangers van een antwoord. Bij "allen" gaat de rest van Aan en Cc mee, zonder jezelf en zonder dubbelen.
    /// Is de mail door jezelf verstuurd, dan gaat het antwoord naar de oorspronkelijke ontvangers (zoals in Mail).
    public static func recipients(from: String, replyTo: String, to: String, cc: String, myAddresses: [String],
                                  replyAll: Bool) -> (to: [MailAddress], cc: [MailAddress]) {
        let mine = Set(myAddresses.map { $0.lowercased() })
        let sender = MailAddress.parse(replyTo.isEmpty ? from : replyTo).valid
        let fromMe = !sender.isEmpty && sender.allSatisfy { mine.contains($0.address.lowercased()) }
        let primary = fromMe ? MailAddress.parse(to).valid : sender
        var seen = Set(mine)
        func unique(_ list: [MailAddress]) -> [MailAddress] {
            list.filter { seen.insert($0.address.lowercased()).inserted }
        }
        guard replyAll else { return (unique(primary), []) }
        let toList = unique(primary)
        let ccList = unique((fromMe ? [] : MailAddress.parse(to).valid) + MailAddress.parse(cc).valid)
        return (toList, ccList)
    }

    public static func quoteIntro(date: String, from: String, forward: Bool, subject: String = "") -> String {
        if forward {
            return "---------- Doorgestuurd bericht ----------\nVan: \(from)\nDatum: \(date)\nOnderwerp: \(subject)\n"
        }
        return date.isEmpty ? "\(from) schreef:" : "Op \(date) schreef \(from):"
    }

    /// `References` voor het antwoord: de oude lijst plus het Message-ID van de mail waarop wordt geantwoord.
    public static func references(old: String, messageID: String) -> String {
        [old, messageID].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
