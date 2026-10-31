import Foundation

/// Webadressen in de tekst van een mail klikbaar maken, zoals Spark en Apple Mail dat doen: alleen in gewone tekst,
/// niet in tags, bestaande links, stijlen of scripts. De invoer is al HTML (platte tekst is eerst ge-escapet), dus een
/// adres stopt bij een tag, een aanhalingsteken, witruimte of een ge-escapet teken als `&lt;`, `&gt;` en `&quot;`.
enum MailLinks {
    /// Commentaar, blokken waar niets in mag veranderen, en losse tags.
    private static let markup = try! NSRegularExpression(
        pattern: #"<!--[\s\S]*?-->|<(script|style|title|textarea)\b[\s\S]*?</\1\s*>|<[^>]*>"#,
        options: [.caseInsensitive])

    private static let address = try! NSRegularExpression(
        pattern: #"\b(?:https?://|mailto:|www\.)(?:(?!&(?:lt|gt|quot|apos|nbsp|#34|#39|#60|#62|#160);)[^\s<>"'])+"#,
        options: [.caseInsensitive])

    private static let anchorOpen = try! NSRegularExpression(pattern: #"^<a[\s>]"#, options: [.caseInsensitive])
    private static let anchorClose = try! NSRegularExpression(pattern: #"^</a\s*>"#, options: [.caseInsensitive])

    /// Haakjes die bij een adres horen als het openingshaakje er ook in staat ("…/Foo_(bar)").
    private static let openingBracket: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    static func linkify(html: String) -> String {
        let ns = html as NSString
        var result = ""
        var cursor = 0
        var openAnchors = 0
        for match in markup.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let text = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += openAnchors > 0 ? text : linkify(text: text)
            let tag = ns.substring(with: match.range)
            if matches(anchorOpen, tag) {
                openAnchors += 1
            } else if matches(anchorClose, tag) {
                openAnchors = max(0, openAnchors - 1)
            }
            result += tag
            cursor = match.range.location + match.range.length
        }
        let rest = ns.substring(from: cursor)
        result += openAnchors > 0 ? rest : linkify(text: rest)
        return result
    }

    /// Adressen in een stuk HTML-tekst zonder tags.
    static func linkify(text: String) -> String {
        let ns = text as NSString
        let found = address.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !found.isEmpty else { return text }
        var result = ""
        var cursor = 0
        for match in found {
            var shown = ns.substring(with: match.range)
            // Leestekens aan het eind horen bij de zin; een sluithaakje alleen bij het adres als het openingshaakje
            // er ook in staat.
            while let last = shown.last,
                  ".,;:!?".contains(last) || (openingBracket[last].map { !shown.contains($0) } ?? false) {
                shown.removeLast()
            }
            let length = (shown as NSString).length
            guard length > 0, !["http://", "https://", "mailto:", "www."].contains(shown.lowercased()) else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let href = shown.lowercased().hasPrefix("www.") ? "https://" + shown : shown
            result += "<a href=\"\(href)\">\(shown)</a>"
            cursor = match.range.location + length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }
}
