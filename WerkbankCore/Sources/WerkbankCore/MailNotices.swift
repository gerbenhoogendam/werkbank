import Foundation

/// Meldingen van nieuwe mail: welke mails een melding krijgen en wat erin staat (`MailNotifier` in de Mac-app).
public enum MailNotices {
    /// Speling voor het verschil tussen de klok van Gmail en die van de Mac.
    public static let margin: TimeInterval = 120

    /// De mails waarvoor nu een melding hoort, oudste eerst: nog niet eerder gemeld en binnengekomen na de vorige
    /// controle (`since`, met `margin` speling). Een oudere mail die weer op ongelezen is gezet is geen nieuwe mail;
    /// een mail zonder datum ook niet.
    public static func fresh(_ items: [GmailMailItem], notified: Set<String>, since: Date) -> [GmailMailItem] {
        let threshold = since.addingTimeInterval(-margin)
        return items
            .filter { item in
                guard !notified.contains(item.id), let date = item.date else { return false }
                return date >= threshold
            }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// De melding bij één mail: de afzender (met de mailbox erachter als er meer mailboxen meldingen geven), het
    /// onderwerp en het begin van de tekst.
    public static func text(for item: GmailMailItem, mailbox: String?) -> (title: String, subtitle: String, body: String) {
        let sender = item.senderDisplay
        let title = mailbox.map { $0.isEmpty ? sender : "\(sender) · \($0)" } ?? sender
        return (title, item.subject.isEmpty ? "(geen onderwerp)" : item.subject, item.snippet)
    }

    /// Eén melding voor veel mails tegelijk (na de slaapstand): het aantal, en de afzenders van de nieuwste drie.
    public static func summary(_ items: [GmailMailItem], mailbox: String) -> (title: String, body: String) {
        var names: [String] = []
        for item in items.sorted(by: { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) })
        where !names.contains(item.senderDisplay) && names.count < 3 {
            names.append(item.senderDisplay)
        }
        let more = Set(items.map(\.senderDisplay)).count > names.count ? " en anderen" : ""
        let title = mailbox.isEmpty ? "\(items.count) nieuwe mails" : "\(items.count) nieuwe mails · \(mailbox)"
        return (title, names.joined(separator: ", ") + more)
    }

    /// Het getal op het Dock-icoon: niets bij nul, "99+" boven de 99.
    public static func badge(_ count: Int) -> String? {
        count <= 0 ? nil : (count > 99 ? "99+" : String(count))
    }
}
