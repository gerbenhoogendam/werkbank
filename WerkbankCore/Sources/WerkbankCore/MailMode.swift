import Foundation

// De mailmodus: een mail met alle koppen die de lijst, de bundel en de klanten nodig hebben, de soort mail, de
// zoekopdracht voor Gmail en de klanten op volgorde van hoeveel mail er met ze was.

// MARK: - Soort mail

/// Persoonlijke mail, nieuwsbrief of melding. Nieuwsbrieven en meldingen staan in de mailmodus samen in de bundel en
/// kunnen in één keer weg.
public enum MailKind: String, Codable, CaseIterable {
    case person, newsletter, notification

    public var title: String {
        switch self {
        case .person: "Persoonlijk"
        case .newsletter: "Nieuwsbrief"
        case .notification: "Melding"
        }
    }

    /// Een afzender die een machine is (noreply, notificaties, mailer-daemon).
    public static func isAutomatedSender(_ address: String?) -> Bool {
        guard let local = address?.lowercased().split(separator: "@").first else { return false }
        return ["noreply", "no-reply", "donotreply", "do-not-reply", "notification", "notify", "alert", "mailer-daemon",
                "bounce", "newsletter", "nieuwsbrief", "info-noreply"].contains { local.contains($0) }
    }

    /// Mail van een bekende klant is altijd persoonlijk. Daarna: de categorie van Gmail, een afmeldlink of
    /// bulk-kop (nieuwsbrief) en een afzender die een machine is (melding).
    public static func classify(labels: [String], fromAddress: String?, listUnsubscribe: Bool, bulk: Bool,
                                isKnownClient: Bool) -> MailKind {
        if isKnownClient { return .person }
        if labels.contains("CATEGORY_PROMOTIONS") { return .newsletter }
        if labels.contains("CATEGORY_UPDATES") || labels.contains("CATEGORY_SOCIAL") || labels.contains("CATEGORY_FORUMS") {
            return .notification
        }
        if listUnsubscribe || bulk { return .newsletter }
        if isAutomatedSender(fromAddress) { return .notification }
        return .person
    }
}

// MARK: - Mail in de mailmodus

/// Eén mail uit `messages.get` (format=metadata): koppen, labels en het MIME-type (voor "met bijlage").
public struct GmailMailItem: Equatable, Identifiable {
    public var id: String
    public var threadID: String
    public var fromName: String?
    public var fromAddress: String?
    /// Adressen in Aan en Cc, in kleine letters.
    public var recipients: [String]
    public var subject: String
    public var snippet: String
    public var date: Date?
    public var labels: [String]
    public var mimeType: String
    /// Heeft een kop `List-Unsubscribe` (nieuwsbrieven en mailinglijsten).
    public var listUnsubscribe: Bool
    /// `Precedence: bulk` of `list`.
    public var bulk: Bool

    public init(id: String, threadID: String, fromName: String? = nil, fromAddress: String? = nil, recipients: [String] = [],
                subject: String, snippet: String = "", date: Date? = nil, labels: [String] = [], mimeType: String = "",
                listUnsubscribe: Bool = false, bulk: Bool = false) {
        self.id = id
        self.threadID = threadID
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.recipients = recipients
        self.subject = subject
        self.snippet = snippet
        self.date = date
        self.labels = labels
        self.mimeType = mimeType
        self.listUnsubscribe = listUnsubscribe
        self.bulk = bulk
    }

    public var isUnread: Bool { labels.contains("UNREAD") }
    public var isInInbox: Bool { labels.contains("INBOX") }
    public var isSent: Bool { labels.contains("SENT") }
    /// Een mail met bijlagen is `multipart/mixed`; zonder de onderdelen op te halen is dit de beste aanwijzing.
    public var mayHaveAttachment: Bool { mimeType.lowercased() == "multipart/mixed" }

    public var senderDisplay: String {
        if let fromName, !fromName.isEmpty { return fromName }
        return fromAddress ?? "Onbekende afzender"
    }

    /// Alle adressen in de mail (afzender, Aan, Cc), in kleine letters.
    public var addresses: [String] {
        ([fromAddress?.lowercased()].compactMap { $0 } + recipients)
    }

    public var summary: GmailMessageSummary {
        GmailMessageSummary(id: id, threadID: threadID, fromName: fromName, fromAddress: fromAddress, subject: subject,
                            snippet: snippet, date: date, isUnread: isUnread)
    }

    public func kind(isKnownClient: Bool) -> MailKind {
        MailKind.classify(labels: labels, fromAddress: fromAddress, listUnsubscribe: listUnsubscribe, bulk: bulk,
                          isKnownClient: isKnownClient)
    }
}

extension GmailAPI {
    /// De koppen die de mailmodus opvraagt bij `messages.get` (format=metadata).
    public static let mailItemHeaders = ["From", "To", "Cc", "Subject", "List-Unsubscribe", "Precedence"]

    /// Antwoord van `users.messages.get` met `format=metadata`.
    public static func mailItem(fromMessageJSON data: Data) -> GmailMailItem? {
        struct Header: Decodable { let name: String; let value: String }
        struct Message: Decodable {
            struct Payload: Decodable { let mimeType: String?; let headers: [Header]? }
            let id: String
            let threadId: String
            let labelIds: [String]?
            let snippet: String?
            let internalDate: String?
            let payload: Payload?
        }
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return nil }
        let headers = message.payload?.headers ?? []
        func value(_ name: String) -> String {
            headers.first { $0.name.lowercased() == name }?.value ?? ""
        }
        // Afzender en onderwerp via dezelfde parser als een .eml-bestand: die decodeert ook "=?UTF-8?...?=".
        let headerText = headers
            .filter { ["from", "subject"].contains($0.name.lowercased()) }
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\r\n")
        let parsed = EMLParser.parse(headerText)
        let recipients = (MailAddress.parse(EMLParser.decodeEncodedWords(value("to"))).valid
            + MailAddress.parse(EMLParser.decodeEncodedWords(value("cc"))).valid).map { $0.address.lowercased() }
        let precedence = value("precedence").lowercased()
        let date = message.internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
        return GmailMailItem(id: message.id, threadID: message.threadId, fromName: parsed.fromName,
                             fromAddress: parsed.fromAddress, recipients: recipients, subject: parsed.subject,
                             snippet: decodeEntities(message.snippet ?? ""), date: date, labels: message.labelIds ?? [],
                             mimeType: message.payload?.mimeType ?? "",
                             listUnsubscribe: !value("list-unsubscribe").isEmpty,
                             bulk: precedence.contains("bulk") || precedence.contains("list"))
    }
}

// MARK: - Zoeken

/// De zoekopdracht voor Gmail (`q`). Zonder zoektekst en klant: de inbox. Met zoektekst of klant: alle mail (Gmail
/// laat spam en prullenbak dan zelf weg), zodat je ook gearchiveerde mail terugvindt.
public enum MailSearch {
    public static func query(text: String, attachment: Bool = false, unread: Bool = false,
                             clientDomains: [String] = []) -> String {
        var parts: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && clientDomains.isEmpty { parts.append("in:inbox") }
        if !trimmed.isEmpty { parts.append(trimmed) }
        if attachment { parts.append("has:attachment") }
        if unread { parts.append("is:unread") }
        let domains = clientDomains.map { $0.lowercased() }.filter { !$0.isEmpty && !$0.contains(" ") }
        if !domains.isEmpty {
            // {a b c} is OF in Gmail: mail van, aan of in cc bij een van de domeinen.
            let terms = ["from", "to", "cc"].flatMap { field in domains.map { "\(field):\($0)" } }
            parts.append("{" + terms.joined(separator: " ") + "}")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Klanten op volgorde van contact

/// Eén mail zoals de mailmodus hem onthoudt om de klanten te rangschikken: wanneer en met welke adressen.
public struct MailActivityRecord: Codable, Equatable {
    public var id: String
    public var date: Date
    /// Afzender, Aan en Cc, in kleine letters.
    public var addresses: [String]
    public var isSent: Bool

    public init(id: String, date: Date, addresses: [String], isSent: Bool) {
        self.id = id
        self.date = date
        self.addresses = addresses
        self.isSent = isSent
    }

    public init?(_ item: GmailMailItem) {
        guard let date = item.date else { return nil }
        self.init(id: item.id, date: date, addresses: item.addresses, isSent: item.isSent)
    }
}

public enum ClientActivity {
    public struct Rank: Equatable {
        public var name: String
        /// Aantal mails met deze klant in de periode.
        public var count: Int
        /// Mails per week, oudste eerst (vier weken).
        public var weeks: [Int]
        public var lastContact: Date

        public init(name: String, count: Int, weeks: [Int], lastContact: Date) {
            self.name = name
            self.count = count
            self.weeks = weeks
            self.lastContact = lastContact
        }
    }

    /// De klant bij een adres via de klantenlijst (volledig domein, dan registreerbaar domein); `nil` als onbekend.
    public static func client(forAddress address: String, domainMap: [String: String]) -> String? {
        guard let host = ClientNaming.domain(ofAddress: address) else { return nil }
        return domainMap[host] ?? domainMap[ClientNaming.registrableDomain(of: host)]
    }

    /// Klanten met de meeste mail in de laatste `days` dagen bovenaan; elke mail telt één keer per klant. Eigen
    /// adressen tellen niet mee.
    public static func ranking(records: [MailActivityRecord], domainMap: [String: String], ownAddresses: Set<String>,
                               now: Date, days: Int = 30) -> [Rank] {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        var counts: [String: Int] = [:]
        var weeks: [String: [Int]] = [:]
        var last: [String: Date] = [:]
        var seen = Set<String>()
        for record in records where record.date >= start && record.date <= now.addingTimeInterval(3600) {
            guard seen.insert(record.id).inserted else { continue }
            let clients = Set(record.addresses.filter { !ownAddresses.contains($0) }
                .compactMap { client(forAddress: $0, domainMap: domainMap) })
            let age = max(0, now.timeIntervalSince(record.date))
            let week = 3 - min(3, Int(age / (7 * 86_400)))
            for name in clients {
                counts[name, default: 0] += 1
                var row = weeks[name] ?? [0, 0, 0, 0]
                row[week] += 1
                weeks[name] = row
                last[name] = max(last[name] ?? .distantPast, record.date)
            }
        }
        return counts.map { Rank(name: $0.key, count: $0.value, weeks: weeks[$0.key] ?? [0, 0, 0, 0],
                                 lastContact: last[$0.key] ?? .distantPast) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}
