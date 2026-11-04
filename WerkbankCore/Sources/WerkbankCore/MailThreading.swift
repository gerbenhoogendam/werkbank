import Foundation

/// Citaatniveaus in platte tekst (regels met ">", ">>" of "> >") als geneste citaatblokken, zodat de weergave ze per
/// niveau kan kleuren en laten inspringen, zoals bij HTML-mail (`blockquote type="cite"`).
public enum QuoteLevels {
    /// Platte tekst (`<pre class="plain">`) en citaten van platte tekst met `<br>` (zoals Werkbank en veel doorgestuurde
    /// mail ze maken) krijgen hun niveaus als geneste citaten; de rest van de HTML blijft zoals hij is.
    public static func nest(_ html: String) -> String {
        html.contains(#"<pre class="plain">"#) ? nestPlainQuotes(html) : nestFlatQuotes(nestOutlookHistory(html))
    }

    // MARK: Outlook

    /// De kop van een ouder bericht in Outlook-HTML: een blok met een lijn erboven (Word, Outlook voor Mac) of
    /// `divRplyFwdMsg` (Outlook op het web en de nieuwe Outlook).
    private static let outlookHeader = try! NSRegularExpression(
        pattern: #"<div\b[^>]*(?:\bid\s*=\s*["']?divRplyFwdMsg\b|style\s*=\s*["'][^"']*border-top\s*:\s*solid)[^>]*>"#,
        options: [.caseInsensitive])
    /// De tags die een blok openen of sluiten (om het einde van het blok rond een kop te vinden).
    private static let blockTag = try! NSRegularExpression(
        pattern: #"<(/?)(div|blockquote|table|tbody|thead|tr|td|th|ul|ol|li|body|html)\b[^>]*?(/?)>"#,
        options: [.caseInsensitive])

    /// Outlook zet oudere berichten niet in een citaat maar plat onder elkaar, elk onder een kop ("Van: … Verzonden: …").
    /// Vanaf elke kop tot het einde van het blok eromheen wordt het een citaat (`openTag`), zodat de berichten per niveau
    /// gekleurd worden en inspringen. Zonder zo'n kop blijft de HTML zoals hij is.
    public static func nestOutlookHistory(_ html: String, openTag: String = #"<blockquote type="cite">"#) -> String {
        guard html.range(of: "border-top", options: .caseInsensitive) != nil
                || html.range(of: "divRplyFwdMsg", options: .caseInsensitive) != nil else { return html }
        let text = html as NSString
        var inserts: [(at: Int, tag: String)] = []
        for match in outlookHeader.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            guard isOutlookHeader(text, after: NSMaxRange(match.range)) else { continue }
            let start = wrapperStart(text, header: match.range) ?? match.range.location
            guard let end = blockEnd(text, from: start) else { continue }
            inserts.append((start, openTag))
            inserts.append((end, "</blockquote>"))
        }
        guard !inserts.isEmpty else { return html }
        // Van achteren naar voren invoegen, zodat de plaatsen ervoor blijven kloppen.
        let result = NSMutableString(string: html)
        for insert in inserts.sorted(by: { $0.at > $1.at }) { result.insert(insert.tag, at: insert.at) }
        return result as String
    }

    /// Begint de tekst na de tag met "Van:" of "From:", met kort daarna "Verzonden:", "Sent:", "Datum:" of "Date:"?
    private static func isOutlookHeader(_ text: NSString, after offset: Int) -> Bool {
        let length = min(2_000, text.length - offset)
        guard length > 0 else { return false }
        let visible = plainText(text.substring(with: NSRange(location: offset, length: length))
            .replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard visible.range(of: #"(?i)^(van|from)\s*:"#, options: .regularExpression) != nil else { return false }
        return String(visible.prefix(600)).range(of: #"(?i)\b(verzonden|sent|datum|date)\s*:"#, options: .regularExpression) != nil
    }

    /// Staat de kop als enige in een kaal `<div>` (zo doet Word het), dan begint het citaat bij dat `<div>`: anders
    /// zou het `</div>` erna het citaat al sluiten.
    private static func wrapperStart(_ text: NSString, header: NSRange) -> Int? {
        let lookBack = min(200, header.location)
        let before = text.substring(with: NSRange(location: header.location - lookBack, length: lookBack))
        guard let open = before.range(of: #"<div\b[^>]*>\s*$"#, options: [.regularExpression, .caseInsensitive]),
              let close = elementEnd(text, openTag: header) else { return nil }
        // Na het einde van de kop meteen het `</div>` van de omhulling?
        let rest = text.substring(with: NSRange(location: close, length: min(40, text.length - close)))
        guard rest.range(of: #"^\s*</div\s*>"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return header.location - (String(before[open.lowerBound...]) as NSString).length
    }

    /// Het einde (na de sluittag) van het element dat met `openTag` begint.
    private static func elementEnd(_ text: NSString, openTag: NSRange) -> Int? {
        var depth = 1
        var end: Int?
        let from = NSMaxRange(openTag)
        blockTag.enumerateMatches(in: text as String, range: NSRange(location: from, length: text.length - from)) { match, _, stop in
            guard let match else { return }
            if match.range(at: 1).length > 0 { depth -= 1 } else if match.range(at: 3).length == 0 { depth += 1 }
            if depth == 0 {
                end = NSMaxRange(match.range)
                stop.pointee = true
            }
        }
        return end
    }

    /// Waar het blok eindigt waarin `start` staat: de eerste sluittag zonder bijbehorende opening vanaf daar, of
    /// `</body>`, of het einde van de HTML.
    private static func blockEnd(_ text: NSString, from start: Int) -> Int? {
        var depth = 0
        var end = text.length
        blockTag.enumerateMatches(in: text as String, range: NSRange(location: start, length: text.length - start)) { match, _, stop in
            guard let match else { return }
            let closing = match.range(at: 1).length > 0
            let name = text.substring(with: match.range(at: 2)).lowercased()
            let outer = name == "body" || name == "html"
            if closing, outer || depth == 0 {
                end = match.range.location
                stop.pointee = true
            } else if closing {
                depth -= 1
            } else if match.range(at: 3).length == 0, !outer {
                depth += 1
            }
        }
        return end
    }

    /// Werkt alleen binnen `<pre class="plain">…</pre>` (de weergave van platte tekst); de tekens zijn daar al als
    /// `&gt;` geschreven. Regels met ">" gaan een niveau dieper per ">", en een ouder bericht zonder ">" (na
    /// "On … wrote:", vanaf "-----Oorspronkelijk bericht-----") ook. De rest van de HTML blijft zoals hij is.
    public static func nestPlainQuotes(_ html: String) -> String {
        let open = #"<pre class="plain">"#
        guard let start = html.range(of: open), let end = html.range(of: "</pre>", options: .backwards),
              start.upperBound <= end.lowerBound else { return html }
        let text = String(html[start.upperBound..<end.lowerBound])
        let lines = text.components(separatedBy: "\n").map { split($0) }
        let extra = headerLevels(lines.map { plainText($0.rest) }, depths: lines.map(\.depth))
        guard lines.contains(where: { $0.depth > 0 }) || extra.contains(where: { $0 > 0 }) else { return html }
        var output = ""
        var level = 0
        var segment: [String] = []
        for (line, more) in zip(lines, extra) {
            let target = line.depth + more
            if target != level {
                output += segment.joined(separator: "\n")
                segment = []
                while level < target { output += #"<blockquote type="cite">"#; level += 1 }
                while level > target { output += "</blockquote>"; level -= 1 }
            }
            segment.append(line.rest)
        }
        output += segment.joined(separator: "\n")
        output += String(repeating: "</blockquote>", count: level)
        return String(html[..<start.upperBound]) + output + String(html[end.lowerBound...])
    }

    /// Een citaat dat platte tekst met `<br>` is (geen eigen blokken erin): de oudere berichten erin een niveau dieper,
    /// elk in een eigen `openTag`. Andere citaten blijven zoals ze zijn.
    public static func nestFlatQuotes(_ html: String, openTag: String = #"<blockquote type="cite">"#) -> String {
        guard html.range(of: "<blockquote", options: .caseInsensitive) != nil else { return html }
        var output = ""
        var cursor = html.startIndex
        var search = html.startIndex
        while let open = html.range(of: "<blockquote", options: .caseInsensitive, range: search..<html.endIndex) {
            guard let tagEnd = html.range(of: ">", range: open.upperBound..<html.endIndex),
                  let close = html.range(of: "</blockquote", options: .caseInsensitive,
                                         range: tagEnd.upperBound..<html.endIndex) else { break }
            // Alleen het binnenste citaat: staat er nog een in, dan daar verder.
            if let inner = html.range(of: "<blockquote", options: .caseInsensitive, range: tagEnd.upperBound..<close.lowerBound) {
                search = inner.lowerBound
                continue
            }
            if let nested = nestedFlat(String(html[tagEnd.upperBound..<close.lowerBound]), openTag: openTag) {
                output += String(html[cursor..<tagEnd.upperBound]) + nested
                cursor = close.lowerBound
            }
            search = close.upperBound
        }
        guard cursor != html.startIndex else { return html }
        return output + String(html[cursor...])
    }

    private static let blockTags = #"(?i)<(div|p|table|ul|ol|pre|blockquote|h[1-6])\b"#

    private static func nestedFlat(_ inner: String, openTag: String) -> String? {
        guard inner.range(of: blockTags, options: .regularExpression) == nil else { return nil }
        let lines = inner.replacingOccurrences(of: #"(?i)<br\s*/?>\n?"#, with: "\u{1}", options: .regularExpression)
            .components(separatedBy: "\u{1}")
        let levels = headerLevels(lines.map(plainText))
        guard let top = levels.max(), top > 0 else { return nil }
        var output = ""
        var level = 0
        var segment: [String] = []
        for (line, target) in zip(lines, levels) {
            if target != level {
                output += segment.joined(separator: "<br>\n")
                segment = []
                while level < target { output += openTag; level += 1 }
                while level > target { output += "</blockquote>"; level -= 1 }
            }
            segment.append(line)
        }
        output += segment.joined(separator: "<br>\n")
        output += String(repeating: "</blockquote>", count: level)
        return output
    }

    // MARK: Waar een ouder bericht begint

    /// Per regel (platte tekst) hoeveel niveaus dieper hij hoort omdat er een ouder bericht begint: na een aanhef
    /// ("On … wrote:", "Op … heeft … het volgende geschreven:") en vanaf een kop ("-----Oorspronkelijk bericht-----",
    /// "---------- Doorgestuurd bericht ----------", "Van: … Verzonden: …"). `depths`: het niveau dat een regel al heeft
    /// (">" in platte tekst); staat de tekst na een aanhef al dieper, dan telt de aanhef niet nog eens.
    static func headerLevels(_ lines: [String], depths: [Int]? = nil) -> [Int] {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        func depth(_ index: Int) -> Int { depths.map { $0[index] } ?? 0 }
        func nextContent(after index: Int) -> Int? {
            (index + 1..<trimmed.count).first { !trimmed[$0].isEmpty }
        }
        var result = Array(repeating: 0, count: lines.count)
        var extra = 0
        var extraDepth = 0
        var index = 0
        while index < trimmed.count {
            let current = depth(index)
            // Terug op een lager ">"-niveau dan waar de kop stond: die kop geldt daar niet.
            if extra > 0, current < extraDepth { extra = 0 }
            if isBlockStart(trimmed, at: index), let next = nextContent(after: index), depth(next) == current {
                extra += 1
                extraDepth = current
                result[index] = extra
                index += 1
                // De rest van de kop (Van, Verzonden, Aan, Onderwerp …) hoort erbij.
                while index < trimmed.count, isHeaderField(trimmed[index]) {
                    result[index] = extra
                    index += 1
                }
                continue
            }
            if let span = attributionSpan(trimmed, at: index), let next = nextContent(after: index + span - 1),
               depth(next) == current {
                for line in index..<index + span { result[line] = extra }
                extra += 1
                extraDepth = current
                index += span
                continue
            }
            result[index] = extra
            index += 1
        }
        return result
    }

    private static let attribution = #"(?i)^(op|on|am|le)\s.{0,300}?\b(schreef|wrote|geschreven|schrieb|écrit)\b.{0,160}:$"#
    private static let marker = #"(?i)^(-{2,}\s*(original message|oorspronkelijk bericht|doorgestuurd bericht|forwarded message)|begin (forwarded message|doorgestuurd bericht)\s*:)"#
    private static let fromField = #"(?i)^\*?(van|from)\s*:\*?\s*\S"#
    private static let sentField = #"(?i)^\*?(verzonden|sent|datum|date)\s*:"#
    private static let headerField = #"(?i)^\*?(van|from|verzonden|sent|datum|date|aan|to|cc|bcc|onderwerp|subject|beantwoorden aan|reply-to)\s*:"#

    /// "-----Oorspronkelijk bericht-----", of een kop van Outlook: "Van: …" met binnen vier regels "Verzonden: …".
    private static func isBlockStart(_ lines: [String], at index: Int) -> Bool {
        let line = lines[index]
        if line.range(of: marker, options: .regularExpression) != nil { return true }
        guard line.range(of: fromField, options: .regularExpression) != nil else { return false }
        return lines[(index + 1)..<min(lines.count, index + 5)].contains {
            $0.range(of: sentField, options: .regularExpression) != nil
        }
    }

    private static func isHeaderField(_ line: String) -> Bool {
        line.range(of: headerField, options: .regularExpression) != nil
    }

    /// Een aanhef op één regel, of over twee regels (lange aanheffen worden in platte tekst afgebroken).
    private static func attributionSpan(_ lines: [String], at index: Int) -> Int? {
        let line = lines[index]
        guard line.count < 500 else { return nil }
        if line.range(of: attribution, options: .regularExpression) != nil { return 1 }
        guard index + 1 < lines.count, line.range(of: #"(?i)^(op|on|am|le)\s"#, options: .regularExpression) != nil,
              (line + " " + lines[index + 1]).range(of: attribution, options: .regularExpression) != nil else { return nil }
        return 2
    }

    /// De tekst van een regel HTML, voor het herkennen van een aanhef of kop.
    private static func plainText(_ html: String) -> String {
        guard html.contains("<") || html.contains("&") else { return html }
        return html.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Hoeveel ">" er voor de regel staan (spaties ertussen mogen), en de regel zonder die tekens en de spatie erna.
    private static func split(_ line: String) -> (depth: Int, rest: String) {
        var rest = Substring(line)
        var depth = 0
        while true {
            let trimmed = rest.drop { $0 == " " }
            guard trimmed.hasPrefix("&gt;") else { break }
            rest = trimmed.dropFirst(4)
            depth += 1
        }
        guard depth > 0 else { return (0, line) }
        if rest.hasPrefix(" ") { rest = rest.dropFirst() }
        return (depth, String(rest))
    }
}

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
            // Het vroegste begin telt: na een eerste vondst alleen nog het stuk ervoor doorzoeken (een mail met
            // ingesloten afbeeldingen is soms megabytes groot).
            // (Met wat marge: een vondst die vóór de eerste begint, mag erna nog doorlopen.)
            let end = cut.flatMap { html.index($0, offsetBy: 4_000, limitedBy: html.endIndex) } ?? html.endIndex
            let searchRange = html.startIndex..<end
            if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive], range: searchRange),
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
        // Eerst het goedkope: een afbeelding telt ook (dan hoeft de hele HTML niet naar tekst).
        if html.range(of: "<img", options: .caseInsensitive) != nil { return true }
        return !MIMEBody.htmlToText(html).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
