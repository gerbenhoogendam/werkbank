import Foundation

/// Wat een nieuw opstelvenster al ingevuld krijgt (een mailto-link).
public struct MailPrefill: Codable, Hashable {
    public var to: String
    public var cc: String
    public var bcc: String
    public var subject: String
    public var body: String

    public init(to: String = "", cc: String = "", bcc: String = "", subject: String = "", body: String = "") {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
    }
}

/// Een `mailto:`-link (RFC 6068): adressen voor het vraagteken, daarna to, cc, bcc, subject en body. Een plus blijft
/// een plus (in mailto is een spatie %20).
public enum MailtoLink {
    public static func parse(_ link: String) -> MailPrefill? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("mailto:") else { return nil }
        let rest = trimmed.dropFirst("mailto:".count)
        let path: Substring
        let query: Substring
        if let mark = rest.firstIndex(of: "?") {
            path = rest[..<mark]
            query = rest[rest.index(after: mark)...]
        } else {
            path = rest
            query = ""
        }
        var to = addresses(path)
        var cc: [String] = []
        var bcc: [String] = []
        var subject = ""
        var body = ""
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = decode(parts[0]).lowercased()
            let value = parts.count > 1 ? parts[1] : ""
            switch key {
            case "to": to += addresses(value)
            case "cc": cc += addresses(value)
            case "bcc": bcc += addresses(value)
            case "subject": subject = decode(value)
            case "body": body = decode(value).replacingOccurrences(of: "\r\n", with: "\n")
            default: break
            }
        }
        return MailPrefill(to: to.joined(separator: ", "), cc: cc.joined(separator: ", "),
                           bcc: bcc.joined(separator: ", "), subject: subject, body: body)
    }

    private static func decode(_ text: Substring) -> String {
        String(text).removingPercentEncoding ?? String(text)
    }

    private static func addresses(_ text: Substring) -> [String] {
        decode(text).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
