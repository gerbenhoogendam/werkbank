import Foundation

/// Splitst de HTML van een mail in het nieuwe deel en de geciteerde geschiedenis (Gmail, Apple Mail, Outlook,
/// platte tekst met ">"). Het is een schatting: bij onbekende opmaak blijft alles in het nieuwe deel.
public enum QuoteSplitter {
    private static let markers: [String] = [
        #"<div[^>]*class\s*=\s*["'][^"']*\bgmail_quote\b"#,              // Gmail
        #"<div[^>]*id\s*=\s*["']?(appendonsend|divRplyFwdMsg)\b"#,       // Outlook
        #"<hr[^>]*id\s*=\s*["']?stopSpelling"#,                          // Outlook (oud)
        #"<div[^>]*class\s*=\s*["'][^"']*\bmoz-cite-prefix\b"#,          // Thunderbird
        #"<blockquote[^>]*type\s*=\s*["']?cite"#,                        // Apple Mail en anderen
    ]

    /// Aanhef vlak voor een citaat ("Op … schreef …:", "On … wrote:").
    private static let attribution = #"(?is)<div[^>]*>\s*(?:<[^>]+>\s*)*(Op|On|Am|Le)\s[^<]{0,300}?(schreef|wrote|geschreven|schrieb|écrit)[^<]{0,40}:?\s*(?:<[^>]+>\s*)*$"#

    /// Onderwerp als doorgestuurde mail ("Fwd:", "FW:", "Doorgestuurd:"): het "citaat" is dan de inhoud zelf.
    public static func isForward(subject: String) -> Bool {
        let lower = subject.trimmingCharacters(in: .whitespaces).lowercased()
        return ["fwd:", "fw:", "doorgestuurd:", "wg:", "tr:"].contains { lower.hasPrefix($0) }
    }

    /// Tekst die een doorgestuurd bericht aankondigt (Gmail, Apple Mail, Outlook in NL en EN).
    private static let forwardMarker = #"(?i)(-{3,}\s*(forwarded message|doorgestuurd bericht|oorspronkelijk bericht)|begin (forwarded message|doorgestuurd bericht))"#

    /// Splitst, behalve bij een doorgestuurde mail: daar hoort het doorgestuurde bericht gewoon bij de inhoud.
    public static func split(html: String, subject: String) -> (main: String, history: String?) {
        if isForward(subject: subject) { return (html, nil) }
        let result = split(html: html)
        if let history = result.history {
            let start = MIMEBody.htmlToText(String(history.prefix(3_000)))
            if start.range(of: forwardMarker, options: .regularExpression) != nil { return (html, nil) }
        }
        return result
    }

    public static func split(html: String) -> (main: String, history: String?) {
        if let plain = splitPlain(html) { return plain }
        var cut: String.Index?
        for pattern in markers {
            if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
               cut == nil || range.lowerBound < cut! {
                cut = range.lowerBound
            }
        }
        guard var index = cut else { return (html, nil) }
        // Neem de aanhefregel vlak voor het citaat mee in de geschiedenis.
        let windowStart = html.index(index, offsetBy: -600, limitedBy: html.startIndex) ?? html.startIndex
        let before = String(html[windowStart..<index])
        if let match = before.range(of: attribution, options: .regularExpression) {
            index = html.index(windowStart, offsetBy: before.distance(from: before.startIndex, to: match.lowerBound))
        }
        let main = String(html[..<index])
        let history = String(html[index...])
        guard hasVisibleText(main) else { return (html, nil) }   // alleen citaat: dan niets inklappen
        return (main, history)
    }

    /// Platte tekst (`<pre class="plain">`): knip bij de eerste aanhef- of citaatregel.
    private static func splitPlain(_ html: String) -> (main: String, history: String?)? {
        guard let open = html.range(of: #"<pre class="plain">"#),
              let close = html.range(of: "</pre>", options: .backwards), open.upperBound <= close.lowerBound else { return nil }
        let text = String(html[open.upperBound..<close.lowerBound])
        let lines = text.components(separatedBy: "\n")
        let isStart: (String) -> Bool = { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("&gt;") || t.hasPrefix(">") { return true }
            if t.range(of: #"^(Op|On) .{0,300}(schreef|wrote|geschreven).{0,40}:?$"#, options: .regularExpression) != nil { return true }
            if t.range(of: #"^-{2,}\s*(Original Message|Oorspronkelijk bericht|Doorgestuurd bericht|Forwarded message)"#,
                       options: [.regularExpression, .caseInsensitive]) != nil { return true }
            return t.range(of: #"^(Van|From):\s.+"#, options: .regularExpression) != nil
        }
        guard let first = lines.firstIndex(where: isStart) else { return (html, nil) }
        let main = lines[..<first].joined(separator: "\n")
        guard !main.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (html, nil) }
        let history = lines[first...].joined(separator: "\n")
        return (#"<pre class="plain">"# + main + "</pre>", #"<pre class="plain">"# + history + "</pre>")
    }

    private static func hasVisibleText(_ html: String) -> Bool {
        let text = MIMEBody.htmlToText(html).trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty || html.range(of: "<img", options: .caseInsensitive) != nil
    }

    /// Het nieuwe deel van een mail als platte tekst (voor de analyse van een heel gesprek).
    public static func mainText(of content: MailContent) -> String {
        let (main, _) = split(html: content.displayHTML)
        return MIMEBody.tidy(MIMEBody.htmlToText(main))
    }
}

/// Korte samenvatting uit een analyse van Claude: de tekst onder "## Samenvatting", zonder Markdown.
public enum ClaudeSummary {
    public static func extract(from answer: String) -> String? {
        let lines = answer.components(separatedBy: "\n")
        let start = lines.firstIndex {
            let t = $0.trimmingCharacters(in: .whitespaces).lowercased()
            return t.hasPrefix("#") && t.contains("samenvatting")
        }
        var body: [String] = []
        if let start {
            for line in lines[(start + 1)...] {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("#") { break }
                if !t.isEmpty { body.append(t) }
            }
        } else if let first = lines.first(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && !t.hasPrefix("#")
        }) {
            body = [first.trimmingCharacters(in: .whitespaces)]
        }
        let text = body.joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-*• ").union(.whitespaces))
        return text.isEmpty ? nil : text
    }
}

/// Haalt het conceptantwoord uit een analyse van Claude (het kopje "## Conceptantwoord").
public enum ClaudeDraft {
    public static func extract(from answer: String) -> String? {
        let lines = answer.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: {
            let t = $0.trimmingCharacters(in: .whitespaces).lowercased()
            return t.hasPrefix("#") && t.contains("conceptantwoord")
        }) else { return nil }
        var body: [String] = []
        for line in lines[(start + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("## ") || t.hasPrefix("# ") { break }
            body.append(line)
        }
        var text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Een eventueel codeblok of citaat eromheen weghalen.
        if text.hasPrefix("```") {
            text = text.components(separatedBy: "\n").dropFirst().filter { !$0.hasPrefix("```") }.joined(separator: "\n")
        }
        text = text.components(separatedBy: "\n").map { $0.hasPrefix("> ") ? String($0.dropFirst(2)) : $0 }.joined(separator: "\n")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
