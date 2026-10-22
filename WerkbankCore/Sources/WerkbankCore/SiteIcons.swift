import Foundation

/// Logo of favicon van een website kiezen uit de HTML van de homepage, zonder de standaardicoontjes van
/// websitebouwers (WordPress, Wix, Squarespace, ...).
public enum SiteIcons {
    /// Kandidaten in volgorde van voorkeur: apple-touch-icon (meestal het logo, groot en vierkant), daarna
    /// `icon`-links van groot naar klein. SVG en maskericonen (eenkleurig) vallen af.
    public static func candidates(html: String, baseURL: URL) -> [URL] {
        let ns = html as NSString
        guard let linkTag = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: [.caseInsensitive]) else { return [] }
        var scored: [(URL, Int)] = []
        for match in linkTag.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            guard let rel = attribute("rel", in: tag)?.lowercased(), rel.contains("icon"), !rel.contains("mask"),
                  let href = attribute("href", in: tag), !href.isEmpty,
                  let url = URL(string: href.trimmingCharacters(in: .whitespaces), relativeTo: baseURL)?.absoluteURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  !url.path.lowercased().hasSuffix(".svg"),
                  !isGeneric(url) else { continue }
            let size = attribute("sizes", in: tag).flatMap { sizes in
                sizes.lowercased().split(separator: " ").compactMap { Int($0.split(separator: "x").first ?? "") }.max()
            } ?? 0
            let score = (rel.contains("apple-touch-icon") ? 10_000 : 0) + size
            scored.append((url, score))
        }
        var seen = Set<URL>()
        return scored.sorted { $0.1 > $1.1 }.map(\.0).filter { seen.insert($0).inserted }
    }

    /// Standaardicoontjes van websitebouwers en parkeerpagina's: die zeggen niets over de afzender.
    public static func isGeneric(_ url: URL) -> Bool {
        let text = url.absoluteString.lowercased()
        let patterns = ["wp-includes", "s.w.org", "w-logo", "wordpress.com/i/", "wix.com/favicon", "parastorage.com",
                        "squarespace.com/universal", "default-favicon", "defaultfavicon", "favicon-default",
                        "jimdo", "strikingly", "weebly.com", "sedoparking", "parkingcrew", "bodis.com",
                        "hostinger", "one.com/favicon", "transip", "godaddy", "website-builder"]
        return patterns.contains { text.contains($0) }
    }

    /// Waarde van een attribuut in één HTML-tag (met of zonder aanhalingstekens).
    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) else { return nil }
        for group in 1...3 where match.range(at: group).location != NSNotFound {
            return (tag as NSString).substring(with: match.range(at: group))
        }
        return nil
    }
}
