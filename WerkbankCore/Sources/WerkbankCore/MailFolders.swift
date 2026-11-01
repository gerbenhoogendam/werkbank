import Foundation

// Mappen in de mailmodus: de vaste mappen van Gmail (Postvak IN, Verstuurd, Alle mail …) en je eigen labels, met de
// zoekopdracht die daarbij hoort.

/// Een label uit `users.labels.list`.
public struct GmailLabel: Equatable, Hashable, Identifiable {
    public var id: String
    /// De volledige naam; Gmail nest met "/" ("Klanten/Van Dijk").
    public var name: String
    public var isSystem: Bool
    /// In Gmail verborgen in de lijst met labels.
    public var isHidden: Bool

    public init(id: String, name: String, isSystem: Bool = false, isHidden: Bool = false) {
        self.id = id
        self.name = name
        self.isSystem = isSystem
        self.isHidden = isHidden
    }

    public var path: [String] { name.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) } }
    /// Het laatste deel van de naam ("Van Dijk").
    public var leaf: String { path.last ?? name }
    public var depth: Int { max(0, path.count - 1) }
}

extension GmailAPI {
    public static func labels(fromJSON data: Data) -> [GmailLabel] {
        struct Label: Decodable {
            let id: String
            let name: String
            let type: String?
            let labelListVisibility: String?
        }
        struct List: Decodable { let labels: [Label]? }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else { return [] }
        return (list.labels ?? []).map {
            GmailLabel(id: $0.id, name: $0.name, isSystem: $0.type == "system", isHidden: $0.labelListVisibility == "labelHide")
        }
    }
}

/// Een map in de mailmodus.
public enum MailFolder: Hashable {
    case inbox, starred, sent, all, spam, trash
    /// Een eigen label van één mailbox.
    case label(account: String, id: String, name: String)

    /// De vaste mappen, in de volgorde van de kolom.
    public static let standard: [MailFolder] = [.inbox, .starred, .sent, .all, .spam, .trash]

    public var title: String {
        switch self {
        case .inbox: "Postvak IN"
        case .starred: "Met ster"
        case .sent: "Verstuurd"
        case .all: "Alle mail"
        case .spam: "Spam"
        case .trash: "Prullenbak"
        case .label(_, _, let name): name.split(separator: "/").last.map(String.init) ?? name
        }
    }

    public var labelID: String? {
        switch self {
        case .inbox: "INBOX"
        case .starred: "STARRED"
        case .sent: "SENT"
        case .all: nil
        case .spam: "SPAM"
        case .trash: "TRASH"
        case .label(_, let id, _): id
        }
    }

    public var includesSpamTrash: Bool { self == .spam || self == .trash }

    /// Het label van een mailbox: alleen die mailbox; de vaste mappen gelden voor het hele bereik.
    public var account: String? {
        if case .label(let account, _, _) = self { return account }
        return nil
    }
}

/// Wat `users.messages.list` krijgt: de zoektekst (`q`), labels en of spam en prullenbak meetellen.
public struct MailListRequest: Equatable {
    public var query: String
    public var labelIDs: [String]
    public var includeSpamTrash: Bool
}

/// De zoekopdracht voor Gmail bij een map, zoektekst, filters en klant.
public enum MailSearch {
    /// Zonder zoektekst en klant: de map. Zoeken in Postvak IN zoekt in alle mail (je archiveert alles, dus daar staat
    /// wat je zoekt); in een andere map zoek je in die map. Een klant toont al zijn mail, welke map ook open staat.
    public static func request(text: String, folder: MailFolder, attachment: Bool = false, unread: Bool = false,
                               clientDomains: [String] = []) -> MailListRequest {
        var parts: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        if attachment { parts.append("has:attachment") }
        if unread { parts.append("is:unread") }
        let domains = clientDomains.map { $0.lowercased() }.filter { !$0.isEmpty && !$0.contains(" ") }
        if !domains.isEmpty {
            let terms = ["from", "to", "cc"].flatMap { field in domains.map { "\(field):\($0)" } }
            parts.append("{" + terms.joined(separator: " ") + "}")
        }
        let wholeMailbox = !domains.isEmpty || (!trimmed.isEmpty && folder == .inbox)
        let labels = wholeMailbox ? [] : [folder.labelID].compactMap { $0 }
        // "in:anywhere" (uitgebreid zoeken, ook spam en prullenbak) werkt alleen als Gmail die meeneemt.
        let anywhere = trimmed.range(of: "in:anywhere", options: .caseInsensitive) != nil
        return MailListRequest(query: parts.joined(separator: " "), labelIDs: labels,
                               includeSpamTrash: anywhere || (!wholeMailbox && folder.includesSpamTrash))
    }
}

public enum MailFolders {
    /// Eigen labels als boom: op naam (ook per niveau), kinderen direct onder hun ouder. Systeemlabels (categorieën,
    /// Belangrijk, Ongelezen …) en in Gmail verborgen labels vallen weg.
    public static func userTree(_ labels: [GmailLabel]) -> [GmailLabel] {
        labels.filter { !$0.isSystem && !$0.isHidden }.sorted { lhs, rhs in
            let left = lhs.path, right = rhs.path
            for (a, b) in zip(left, right) where a.caseInsensitiveCompare(b) != .orderedSame {
                return a.localizedStandardCompare(b) == .orderedAscending
            }
            return left.count < right.count
        }
    }
}

// MARK: - Uitgebreid zoeken (⌘F in de mailmodus)

/// Het zoekvenster: velden die samen een zoekopdracht in de zoektaal van Gmail worden.
public struct MailSearchForm: Codable, Equatable {
    public enum Period: String, Codable, CaseIterable, Identifiable {
        case any, week, month, quarter, year

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .any: "Altijd"
            case .week: "7 dagen"
            case .month: "30 dagen"
            case .quarter: "3 maanden"
            case .year: "1 jaar"
            }
        }

        var days: Int? {
            switch self {
            case .any: nil
            case .week: 7
            case .month: 30
            case .quarter: 91
            case .year: 365
            }
        }
    }

    /// Woorden die erin moeten staan (Gmail-zoektaal mag ook).
    public var words = ""
    /// Woorden die er niet in mogen staan.
    public var exclude = ""
    /// Namen of adressen van de afzender, gescheiden door komma's.
    public var from = ""
    /// Namen of adressen in Aan of Cc, gescheiden door komma's.
    public var to = ""
    public var subject = ""
    public var hasAttachment = false
    /// Naam of soort van een bijlage ("offerte", "pdf").
    public var attachmentName = ""
    public var unread = false
    public var starred = false
    public var period: Period = .any
    /// Ook spam en prullenbak.
    public var includeSpamTrash = false

    public init() {}

    public var isEmpty: Bool { self == MailSearchForm() }

    public func query(now: Date = Date(), calendar: Calendar = .current) -> String {
        var parts: [String] = []
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { parts.append(words) }
        parts += Self.tokens(exclude).map { "-" + $0 }
        let senders = Self.people(from)
        if senders.count == 1 { parts.append("from:" + senders[0]) }
        if senders.count > 1 { parts.append("{" + senders.map { "from:" + $0 }.joined(separator: " ") + "}") }
        let receivers = Self.people(to)
        if !receivers.isEmpty {
            parts.append("{" + receivers.flatMap { ["to:" + $0, "cc:" + $0] }.joined(separator: " ") + "}")
        }
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subject.isEmpty { parts.append("subject:(\(subject))") }
        let file = attachmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasAttachment || !file.isEmpty { parts.append("has:attachment") }
        if !file.isEmpty { parts.append("filename:" + Self.quoted(file)) }
        if unread { parts.append("is:unread") }
        if starred { parts.append("is:starred") }
        if let days = period.days, let start = calendar.date(byAdding: .day, value: -days, to: now) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy/MM/dd"
            parts.append("after:" + formatter.string(from: start))
        }
        if includeSpamTrash { parts.append("in:anywhere") }
        return parts.joined(separator: " ")
    }

    /// Losse woorden, of woorden tussen aanhalingstekens als één geheel.
    static func tokens(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #""[^"]+"|[^\s,]+"#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// Namen of adressen, gescheiden door komma's; een naam met spaties tussen aanhalingstekens.
    static func people(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map(quoted)
    }

    static func quoted(_ text: String) -> String {
        guard text.contains(" "), !text.hasPrefix("\"") else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "") + "\""
    }
}
