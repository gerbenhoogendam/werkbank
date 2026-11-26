import Foundation

/// Mails met een ster (Gmail: label STARRED) staan in de kolommen bovenin, op een compacte regel: ster, datum als
/// dag/maand, de voornaam van de afzender en het onderwerp, met daaronder de inhoud op één regel.
public enum StarredMail {
    /// Hoe lang een mail met een ster al ligt: na meer dan 4 dagen oranje, na meer dan 6 dagen rood.
    public enum Age: Equatable {
        case fresh, late, overdue
    }

    public static func age(of date: Date, now: Date, calendar: Calendar = .current) -> Age {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days > 6 { return .overdue }
        if days > 4 { return .late }
        return .fresh
    }

    /// "24/6".
    public static func dayMonth(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        return "\(parts.day ?? 0)/\(parts.month ?? 0)"
    }

    /// Alleen de voornaam: wat na een | staat (meestal het bedrijf) gaat eraf, en alles na het eerste woord ook.
    /// Zonder naam: het deel van het adres voor de @.
    public static func firstName(_ name: String?, address: String?) -> String {
        var trimmed = (name ?? "").components(separatedBy: "|").first ?? ""
        trimmed = trimmed.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
        if let first = trimmed.split(whereSeparator: \.isWhitespace).first, !first.isEmpty {
            return String(first)
        }
        let local = (address ?? "").split(separator: "@").first.map(String.init) ?? ""
        return local.isEmpty ? "Onbekend" : local
    }

    /// De inhoud achter elkaar: enters en dubbele spaties worden één spatie.
    public static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}

extension GmailMailItem {
    public var isStarred: Bool { labels.contains("STARRED") }
}
