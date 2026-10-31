import Foundation

// Nieuwsbrieven en meldingen in één keer archiveren in de mailmodus. Alles gaat mee, behalve wat je uitvinkt; met de
// rechtermuisknop sluit je een afzender, een domein of een soort mail voorgoed uit. Die mail staat dan gewoon in de
// lijst, want je wilt hem lezen.

/// Een uitsluiting voor archiveren in één keer.
public struct BulkRule: Codable, Hashable, Identifiable {
    public enum Field: String, Codable {
        case sender, domain, kind
    }

    public var field: Field
    /// Adres of domein in kleine letters, of de `MailKind` (rawValue).
    public var value: String

    public init(field: Field, value: String) {
        self.field = field
        self.value = field == .kind ? value : value.lowercased()
    }

    public static func sender(_ address: String) -> BulkRule { BulkRule(field: .sender, value: address) }
    public static func domain(_ domain: String) -> BulkRule { BulkRule(field: .domain, value: domain) }
    public static func kind(_ kind: MailKind) -> BulkRule { BulkRule(field: .kind, value: kind.rawValue) }

    public var id: String { "\(field.rawValue):\(value)" }

    public var title: String {
        switch field {
        case .sender: value
        case .domain: "Alles van \(value)"
        case .kind: MailKind(rawValue: value).map { $0 == .newsletter ? "Alle nieuwsbrieven" : "Alle meldingen" } ?? value
        }
    }

    /// Een domein telt ook voor subdomeinen (`mail.voorbeeld.nl` valt onder `voorbeeld.nl`).
    public func matches(_ item: GmailMailItem, kind: MailKind) -> Bool {
        let address = item.fromAddress?.lowercased() ?? ""
        switch field {
        case .sender:
            return address == value
        case .domain:
            guard let host = address.split(separator: "@").last.map(String.init), address.contains("@") else { return false }
            return host == value || host.hasSuffix("." + value)
        case .kind:
            return kind.rawValue == value
        }
    }
}

public enum MailBulk {
    public static func isExcluded(_ item: GmailMailItem, kind: MailKind, rules: [BulkRule]) -> Bool {
        rules.contains { $0.matches(item, kind: kind) }
    }

    /// De mails per afzender, de grootste groep eerst (bij gelijk aantal de nieuwste).
    public static func groups(_ items: [GmailMailItem]) -> [[GmailMailItem]] {
        var order: [String] = []
        var byKey: [String: [GmailMailItem]] = [:]
        for item in items {
            let key = item.fromAddress?.lowercased() ?? item.senderDisplay
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(item)
        }
        return order.compactMap { byKey[$0] }.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return (lhs.first?.date ?? .distantPast) > (rhs.first?.date ?? .distantPast)
        }
    }

    public static func encode(_ rules: [BulkRule]) -> Data? { try? JSONEncoder().encode(rules) }

    public static func decode(_ data: Data?) -> [BulkRule] {
        data.flatMap { try? JSONDecoder().decode([BulkRule].self, from: $0) } ?? []
    }
}
