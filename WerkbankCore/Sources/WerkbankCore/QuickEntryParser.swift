import Foundation

public struct QuickEntry: Equatable {
    public var title: String
    public var label: String?
}

public enum QuickEntryParser {
    private static let hashtag = try! NSRegularExpression(pattern: #"(?:^|(?<=\s))#([\p{L}\p{N}_-]+)"#)

    /// "SSL vernieuwen #Acme" → titel "SSL vernieuwen", label "Acme".
    /// Het eerste `#woord` wordt het label en verdwijnt uit de titel; verdere hashtags blijven staan.
    public static func parse(_ input: String) -> QuickEntry {
        let ns = NSString(string: input)
        guard let match = hashtag.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)) else {
            return QuickEntry(title: collapse(input), label: nil)
        }
        let label = ns.substring(with: match.range(at: 1))
        let remaining = ns.replacingCharacters(in: match.range, with: "")
        return QuickEntry(title: collapse(remaining), label: label)
    }

    private static func collapse(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
