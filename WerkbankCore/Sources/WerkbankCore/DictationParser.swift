import Foundation

/// Een ingesproken tijdregel, verdeeld over de velden van de snelle invoer.
public struct DictatedTimeEntry: Equatable, Sendable {
    public var client: String
    public var caseTitle: String
    public var performed: String
    public var minutes: Int?

    public init(client: String = "", caseTitle: String = "", performed: String = "", minutes: Int? = nil) {
        self.client = client
        self.caseTitle = caseTitle
        self.performed = performed
        self.minutes = minutes
    }
}

/// Verdeelt ingesproken tekst op trefwoorden: "klant Willegom, case printer doet het niet, uitgevoerd driver opnieuw
/// geïnstalleerd, kwartier". Zonder trefwoorden: nil (dan verdeelt Claude het).
public enum DictationParser {
    enum Field: CaseIterable {
        case client, caseTitle, performed, duration
    }

    /// Per veld de trefwoorden. Een latere groep telt alleen als de eerdere er niet is: Whisper schrijft "case" soms
    /// als "Kees", maar "Kees" kan ook gewoon een naam zijn.
    private static let keywords: [Field: [[String]]] = [
        .client: [["klant", "klantnaam"]],
        .caseTitle: [["case", "casus"], ["kees", "keys", "cees", "kays"]],
        .performed: [["uitgevoerd"]],
        .duration: [["duur"]],
    ]

    public static func parse(_ text: String) -> DictatedTimeEntry? {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        // Uitgevoerd is vrije tekst ("klant gebeld"): klant en case eerst ervóór zoeken.
        let performed = firstWord(of: ["uitgevoerd"], in: text, range: whole)
        let before = performed.map { NSRange(location: 0, length: $0.location) } ?? whole
        var marks: [(field: Field, range: NSRange)] = []
        for field in Field.allCases {
            if field == .performed {
                if let performed { marks.append((field, performed)) }
                continue
            }
            let ranges = field == .duration ? [whole] : [before, whole]
            search: for range in ranges {
                for group in keywords[field] ?? [] {
                    if let found = firstWord(of: group, in: text, range: range) {
                        marks.append((field, found))
                        break search
                    }
                }
            }
        }
        guard marks.contains(where: { $0.field != .duration }) else { return nil }
        marks.sort { $0.range.location < $1.range.location }

        var values: [Field: String] = [:]
        for (index, mark) in marks.enumerated() {
            let start = mark.range.location + mark.range.length
            let end = index + 1 < marks.count ? marks[index + 1].range.location : ns.length
            values[mark.field] = clean(ns.substring(with: NSRange(location: start, length: max(0, end - start))))
        }
        // Tekst vóór het eerste trefwoord hoort bij het eerste veld dat nog ontbreekt ("Willegom, case …").
        let preamble = clean(ns.substring(to: marks[0].range.location))
        if !preamble.isEmpty,
           let field = [Field.client, .caseTitle, .performed].first(where: { (values[$0] ?? "").isEmpty }) {
            values[field] = preamble
        }

        var minutes: Int?
        if let spoken = values[.duration], let found = DurationPhrase.find(in: spoken, atEnd: false) {
            minutes = found.minutes
        } else {
            // Een duur aan het eind van een veld ("…, kwartier") hoort er niet bij.
            for field in [Field.performed, .caseTitle, .client] {
                guard let value = values[field],
                      let found = DurationPhrase.find(in: value, atEnd: true) else { continue }
                minutes = found.minutes
                values[field] = clean(found.remainder)
                break
            }
        }

        return DictatedTimeEntry(client: values[.client] ?? "",
                                 caseTitle: capitalized(values[.caseTitle] ?? ""),
                                 performed: capitalized(values[.performed] ?? ""),
                                 minutes: minutes)
    }

    /// Eerste hele woord uit `words` binnen `range`, ongeacht hoofdletters.
    private static func firstWord(of words: [String], in text: String, range: NSRange) -> NSRange? {
        let pattern = "\\b(?:" + words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return regex.firstMatch(in: text, range: range)?.range
    }

    /// Zonder leestekens en opvulwoorden aan de randen ("klant is Willegom," → "Willegom").
    static func clean(_ text: String) -> String {
        let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.:;-–!?"))
        var result = text.trimmingCharacters(in: edges)
        for filler in ["is ", "was ", "naam "] where result.lowercased().hasPrefix(filler) {
            result = String(result.dropFirst(filler.count)).trimmingCharacters(in: edges)
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

/// Een gesproken duur: "kwartier", "drie kwartier", "half uur", "anderhalf uur", "20 minuten", "1,5 uur", "twee uur".
enum DurationPhrase {
    private static let numbers: [String: Double] = [
        "een": 1, "één": 1, "twee": 2, "drie": 3, "vier": 4, "vijf": 5, "zes": 6, "zeven": 7, "acht": 8,
        "tien": 10, "vijftien": 15, "twintig": 20, "vijfentwintig": 25, "dertig": 30, "vijfendertig": 35,
        "veertig": 40, "vijfenveertig": 45, "vijftig": 50, "zestig": 60, "negentig": 90,
    ]

    /// Meest specifiek eerst ("drie kwartier" voor "kwartier", "twee en een half uur" voor "half uur").
    private static let patterns: [(pattern: String, minutes: @Sendable (String?) -> Double?)] = [
        ("(\\d+(?:[.,]\\d+)?)\\s*uur", { text in
            text.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }.map { $0 * 60 }
        }),
        ("(\\d+)\\s*(?:minuten|minuut|min)", { text in text.flatMap { Double($0) } }),
        ("(een|één|twee|drie|vier)\\s+en\\s+een\\s+half\\s+uur", { text in
            text.flatMap { DurationPhrase.numbers[$0] }.map { ($0 + 0.5) * 60 }
        }),
        ("anderhalf\\s+uur", { _ in 90 }),
        ("drie\\s*kwartier", { _ in 45 }),
        ("(?:een\\s+)?half\\s*uur|halfuur", { _ in 30 }),
        ("(?:een\\s+)?kwartier", { _ in 15 }),
        ("(één|een|twee|drie|vier|vijf|zes|zeven|acht)\\s+uur", { text in
            text.flatMap { DurationPhrase.numbers[$0] }.map { $0 * 60 }
        }),
        ("(vijfentwintig|vijfendertig|vijfenveertig|vijftien|twintig|dertig|veertig|vijftig|zestig|negentig|tien|vijf)"
         + "\\s+minuten", { text in text.flatMap { DurationPhrase.numbers[$0] } }),
    ]

    /// `atEnd`: alleen als de duur het laatste is in `text`. `remainder`: wat ervoor staat.
    static func find(in text: String, atEnd: Bool) -> (minutes: Int, remainder: String)? {
        let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.:;!?"))
        let trimmed = text.trimmingCharacters(in: edges)
        let ns = trimmed as NSString
        for (pattern, minutes) in patterns {
            let full = "\\b(?:" + pattern + ")\\b"
            guard let regex = try? NSRegularExpression(pattern: full, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length)) {
                guard !atEnd || match.range.location + match.range.length == ns.length else { continue }
                let captured = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                    ? ns.substring(with: match.range(at: 1)).lowercased() : nil
                guard let value = minutes(captured), value > 0 else { continue }
                return (Int(value.rounded()), ns.substring(to: match.range.location))
            }
        }
        return nil
    }
}
