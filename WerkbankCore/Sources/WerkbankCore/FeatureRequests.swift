import Foundation

// Verbeteringen voor een volgende build: ingesproken (sneltoets op de Mac, knop op de iPhone) of getypt, verzameld in
// Voorkeuren › Verbeteringen en als je er genoeg hebt in één prompt aan Claude gegeven, gescheiden in desktop en
// mobiel.

/// Voor welke app een verbetering is.
public enum FeaturePlatform: String, Codable, CaseIterable, Identifiable {
    case desktop, mobile

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .desktop: "Desktop"
        case .mobile: "Mobiel"
        }
    }
}

public enum FeatureRequestSplitter {
    /// Woorden waarmee een zin een nieuwe verbetering begint ("Daarnaast …", "Ten tweede …", "Nog iets: …").
    private static let newItemMarkers = [
        "daarnaast", "verder", "bovendien", "ook", "en ook", "wat ook", "nog iets", "nog een", "een andere",
        "een ander", "iets anders", "volgende", "volgend punt", "het volgende", "ten eerste", "ten tweede", "ten derde",
        "ten vierde", "ten vijfde", "ten slotte", "tenslotte", "tot slot", "als laatste", "trouwens", "o ja", "oh ja",
        "oh en", "en dan", "en verder", "en daarnaast", "en bovendien", "punt", "tweede", "derde", "vierde", "vijfde", "nummer",
    ]

    /// Opsommingswoorden die zelf geen inhoud zijn en wegvallen ("Ten tweede, de kleuren …" → "De kleuren …").
    private static let enumerator = try! NSRegularExpression(
        pattern: #"^(?:ten\s+(?:eerste|tweede|derde|vierde|vijfde|zesde)|punt\s+(?:\d+|een|één|twee|drie|vier|vijf|zes)|(?:eerste|tweede|derde|vierde|vijfde|zesde)\s+punt|nummer\s+(?:\d+|een|één|twee|drie|vier|vijf)|\d+[.)])[\s,:;.–-]*"#,
        options: [.caseInsensitive])

    /// Midden in een zin: ", ten tweede", ", daarnaast", "; verder" beginnen ook een nieuwe verbetering.
    private static let inline = try! NSRegularExpression(
        pattern: #"[,;]\s+(?=(?:en\s+)?(?:ten\s+(?:tweede|derde|vierde|vijfde|zesde)|daarnaast|bovendien|verder|punt\s+(?:\d+|twee|drie|vier|vijf))\b)"#,
        options: [.caseInsensitive])

    /// Eén keer inspreken met meerdere verbeteringen: elke zin die met een opsommings- of verbindingswoord begint, is
    /// een nieuwe verbetering; andere zinnen horen bij de vorige.
    public static func split(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return [] }
        let ns = normalized as NSString
        // Een nieuwe verbetering midden in een zin: daar een harde grens.
        let marked = inline.stringByReplacingMatches(in: normalized, range: NSRange(location: 0, length: ns.length),
                                                     withTemplate: "\n")
        var items: [String] = []
        for sentence in sentences(marked) {
            let lower = sentence.lowercased()
            let startsNew = sentence.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil
                || newItemMarkers.contains { marker in
                    lower.hasPrefix(marker) && (lower.count == marker.count || !isLetter(lower, at: marker.count))
                }
            if items.isEmpty || startsNew {
                items.append(sentence)
            } else {
                items[items.count - 1] += " " + sentence
            }
        }
        return items.map(clean).filter { !$0.isEmpty }
    }

    /// Een verbetering die over de iPhone of de Mac gaat; `nil` als de tekst het niet zegt.
    public static func platform(of text: String) -> FeaturePlatform? {
        let lower = " " + text.lowercased() + " "
        let mobile = ["iphone", "ipad", "mobiel", "mobile", "telefoon", " ios"].contains { lower.contains($0) }
        let desktop = ["op de mac", "op mijn mac", "macbook", "desktop", "macos", "mac-app", "mac app"]
            .contains { lower.contains($0) }
        if mobile == desktop { return nil }
        return mobile ? .mobile : .desktop
    }

    private static func isLetter(_ text: String, at offset: Int) -> Bool {
        let index = text.index(text.startIndex, offsetBy: offset)
        return text[index].isLetter
    }

    /// Zinnen: na . ! of ? gevolgd door een spatie en geen kleine letter (dus niet na "bijv. de"), en niet na een los
    /// nummer ("1. "). Een regeleinde is altijd een grens.
    private static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\n" {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                index += 1
                continue
            }
            current.append(character)
            if ".!?".contains(character), index + 1 < characters.count, characters[index + 1] == " " {
                let nextLetter = characters[(index + 2)...].first { !$0.isWhitespace }
                let isNumber = current.trimmingCharacters(in: .whitespaces).range(of: #"^\d+[.)]$"#, options: .regularExpression) != nil
                if !isNumber, nextLetter.map({ !$0.isLowercase }) ?? true {
                    result.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            }
            index += 1
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result.filter { !$0.isEmpty && $0 != "." }
    }

    private static func clean(_ item: String) -> String {
        var text = item.trimmingCharacters(in: .whitespaces)
        let ns = text as NSString
        if let match = enumerator.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            text = ns.replacingCharacters(in: match.range, with: "")
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:–-"))
        guard let first = text.first else { return "" }
        return first.uppercased() + text.dropFirst()
    }
}

/// De prompt voor Claude met alle verzamelde verbeteringen, desktop en mobiel apart.
public enum FeaturePrompt {
    public struct Item: Equatable {
        public var text: String
        public var platform: FeaturePlatform

        public init(text: String, platform: FeaturePlatform) {
            self.text = text
            self.platform = platform
        }
    }

    public static func build(_ items: [Item]) -> String {
        let desktop = items.filter { $0.platform == .desktop }
        let mobile = items.filter { $0.platform == .mobile }
        var lines = [
            "Hieronder staan verbeteringen voor Werkbank die ik tijdens het gebruik heb verzameld "
                + "(\(desktop.count) desktop, \(mobile.count) mobiel). Voer ze door in de volgende build.",
            "Werk volgens CLAUDE.md en OVERDRACHT.md in de repo. Is een punt onduidelijk of strijdig met een eerdere "
                + "afspraak, vraag het dan eerst. Meld per punt wat je gedaan hebt en wat (nog) niet.",
        ]
        func section(_ title: String, _ list: [Item]) {
            guard !list.isEmpty else { return }
            lines.append("")
            lines.append("## \(title)")
            for (index, item) in list.enumerated() {
                lines.append("\(index + 1). \(item.text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        section("Desktop (macOS)", desktop)
        section("Mobiel (iOS)", mobile)
        return lines.joined(separator: "\n") + "\n"
    }
}
