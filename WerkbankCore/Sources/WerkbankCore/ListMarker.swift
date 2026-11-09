import Foundation

/// Opsommingstekens aan het begin van een geplakte alinea (uit Werkbank, Pages, Word of een webpagina): wat voor lijst
/// het is en hoeveel tekens (UTF-16, zoals `NSString`) het teken met de tab erachter beslaat.
public enum ListMarker {
    public enum Kind: Equatable {
        case bullet, number
    }

    /// Een gangbaar lijstteken met een tab erachter, eventueel na tabs of spaties: "•\t", "\t•\t", "\t12.\t", "3)\t",
    /// en de tekens die Word en Outlook gebruiken (U+F0B7 in Symbol, "·", "◦", "▪"). Zonder tab (zoals "1. Inleiding")
    /// is het gewone tekst.
    public static func leading(_ paragraph: String) -> (kind: Kind, length: Int)? {
        let ns = paragraph as NSString
        guard let match = leadingPattern.firstMatch(in: paragraph, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        let isNumber = match.range(at: 2).location != NSNotFound
        return (isNumber ? .number : .bullet, match.range.length)
    }

    /// In een alinea die de bron als lijst markeerde (`NSTextList`): het teken tot en met de eerste tab, wat het ook is
    /// ("\ta.\t", "\t◦\t", "\tiv.\t"). 0 als er geen teken staat.
    public static func listed(_ paragraph: String) -> Int {
        let ns = paragraph as NSString
        return listedPattern.firstMatch(in: paragraph, range: NSRange(location: 0, length: ns.length))?.range.length ?? 0
    }

    private static let leadingPattern = try! NSRegularExpression(
        pattern: "^[\\t ]*(?:([•·◦▪▫●○■□‣⁃\u{F0B7}\u{F0A7}\u{F076}\u{F0D8}\u{2013}\\-])|(\\d{1,3}[.)]))\\t")

    private static let listedPattern = try! NSRegularExpression(pattern: "^\\t*[^\\t\\n]{1,10}\\t")
}
