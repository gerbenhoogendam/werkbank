import Foundation

/// Wat er in een mailbox veranderde sinds een bepaald punt (`users.history.list`). Genoeg om de labels bij te werken
/// van mails waarvan de koppen al bekend zijn: afzender, onderwerp en datum van een mail veranderen nooit, alleen zijn
/// labels (gelezen, inbox, map). Zo hoeft verversen alleen de koppen van nieuwe mails op te halen.
public enum GmailHistory {
    public enum Change: Equatable {
        case labelsAdded(id: String, labels: [String])
        case labelsRemoved(id: String, labels: [String])
        case deleted(id: String)
    }

    public struct Page: Equatable {
        public var changes: [Change]
        public var nextPageToken: String?
        /// Tot waar de mailbox nu is bijgewerkt: het beginpunt van de volgende vraag.
        public var historyID: String?

        public init(changes: [Change], nextPageToken: String? = nil, historyID: String? = nil) {
            self.changes = changes
            self.nextPageToken = nextPageToken
            self.historyID = historyID
        }
    }

    /// Wat er gevraagd wordt (`historyTypes`). Nieuwe mails staan er niet bij: die komen uit de lijst zelf.
    public static let types = ["labelAdded", "labelRemoved", "messageDeleted"]

    /// Een nummer dat Gmail als tekst stuurt (en voor de zekerheid ook als getal gelezen wordt).
    private struct Number: Decodable {
        let text: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self.text = text
            } else {
                self.text = String(try container.decode(UInt64.self))
            }
        }
    }

    /// Antwoord van `users.history.list`, de wijzigingen in de volgorde waarin ze gebeurden.
    public static func page(fromJSON data: Data) -> Page? {
        struct Response: Decodable {
            struct Message: Decodable { let id: String }
            struct Labels: Decodable {
                let message: Message
                let labelIds: [String]?
            }
            struct Deleted: Decodable { let message: Message }
            struct Record: Decodable {
                let labelsAdded: [Labels]?
                let labelsRemoved: [Labels]?
                let messagesDeleted: [Deleted]?
            }
            let history: [Record]?
            let nextPageToken: String?
            let historyId: Number?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        var changes: [Change] = []
        for record in response.history ?? [] {
            for entry in record.labelsRemoved ?? [] {
                changes.append(.labelsRemoved(id: entry.message.id, labels: entry.labelIds ?? []))
            }
            for entry in record.labelsAdded ?? [] {
                changes.append(.labelsAdded(id: entry.message.id, labels: entry.labelIds ?? []))
            }
            for entry in record.messagesDeleted ?? [] {
                changes.append(.deleted(id: entry.message.id))
            }
        }
        return Page(changes: changes, nextPageToken: response.nextPageToken, historyID: response.historyId?.text)
    }

    /// Het huidige punt van een mailbox (`users.getProfile`): het begin als er nog niets bekend is.
    public static func historyID(fromProfileJSON data: Data) -> String? {
        struct Profile: Decodable { let historyId: Number? }
        return (try? JSONDecoder().decode(Profile.self, from: data))?.historyId?.text
    }

    /// Werkt de labels van bekende mails bij, in volgorde. Een mail die niet bekend is, wordt overgeslagen: die krijgt
    /// zijn labels als zijn kop wordt opgehaald.
    public static func apply(_ changes: [Change], to items: inout [String: GmailMailItem]) {
        for change in changes {
            switch change {
            case let .labelsAdded(id, labels):
                guard var item = items[id] else { continue }
                for label in labels where !item.labels.contains(label) { item.labels.append(label) }
                items[id] = item
            case let .labelsRemoved(id, labels):
                guard var item = items[id] else { continue }
                item.labels.removeAll { labels.contains($0) }
                items[id] = item
            case let .deleted(id):
                items[id] = nil
            }
        }
    }
}
