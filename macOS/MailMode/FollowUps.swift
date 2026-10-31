import Foundation
import Observation
import WerkbankCore

/// Opvolgen vanuit de mailmodus. Een gesprek wordt gearchiveerd en komt terug in de inbox als er binnen de termijn
/// geen antwoord kwam (geen antwoord), of op een gekozen moment (later terug). Gaat via de voorkeuren mee naar je
/// andere Macs; terugzetten twee keer is onschuldig.
struct FollowUp: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case noReply, snooze }

    var id = UUID()
    var threadID: String
    var account: String?
    var subject: String
    var kind: Kind
    /// Wanneer het gesprek terugkomt (of, bij geen antwoord, uiterlijk).
    var due: Date
    /// Vanaf wanneer een antwoord telt.
    var since: Date
}

@MainActor
@Observable
final class FollowUpStore {
    static let shared = FollowUpStore()
    static let itemsKey = "mailMode.followUps"
    /// Gesprekken die terugkwamen omdat er geen antwoord was: gesprek → wat er onder de mail staat.
    static let returnedKey = "mailMode.returned"

    private(set) var items: [FollowUp] = []
    private(set) var returned: [String: String] = [:]

    @ObservationIgnored private var task: Task<Void, Never>?

    private init() { reload() }

    /// Opnieuw lezen (bij het starten en na synchroniseren met een andere Mac).
    func reload() {
        let defaults = UserDefaults.standard
        items = defaults.data(forKey: Self.itemsKey).flatMap { try? JSONDecoder().decode([FollowUp].self, from: $0) } ?? []
        returned = defaults.dictionary(forKey: Self.returnedKey) as? [String: String] ?? [:]
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(items), forKey: Self.itemsKey)
        defaults.set(returned, forKey: Self.returnedKey)
    }

    func add(threadID: String, account: String?, subject: String, kind: FollowUp.Kind, due: Date) {
        items.removeAll { $0.threadID == threadID }
        items.append(FollowUp(threadID: threadID, account: account, subject: subject, kind: kind, due: due, since: .now))
        returned[threadID] = nil
        save()
    }

    func remove(threadID: String) {
        items.removeAll { $0.threadID == threadID }
        save()
    }

    /// Het gesprek is weer verwerkt: het label "terug" mag weg.
    func clearReturned(threadID: String) {
        guard returned[threadID] != nil else { return }
        returned[threadID] = nil
        save()
    }

    /// Gesprekken waar nog op een antwoord wordt gewacht.
    var waiting: [FollowUp] { items.filter { $0.kind == .noReply }.sorted { $0.due < $1.due } }

    // MARK: Controleren

    /// Kijkt elke vijf minuten, ook als de mailmodus dicht is.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func check() async {
        let gmail = GmailSession.shared
        guard gmail.state == .signedIn, !items.isEmpty else { return }
        let own = gmail.ownAddresses
        var changed = false
        for entry in items {
            if let account = entry.account, !account.isEmpty, !gmail.accounts.contains(account) { continue }   // losgekoppeld
            let now = Date()
            switch entry.kind {
            case .snooze:
                guard entry.due <= now else { continue }
                guard (try? await gmail.moveToInbox(threadID: entry.threadID, account: entry.account)) != nil else { continue }
                remove(threadID: entry.threadID)
                returned[entry.threadID] = "Later terug"
                AppState.shared.announce("Terug in de inbox: \(entry.subject)", seconds: 4)
                changed = true
            case .noReply:
                guard let messages = try? await gmail.threadMessages(threadID: entry.threadID, account: entry.account) else { continue }
                let answered = messages.contains { message in
                    guard message.date > entry.since, !message.isSent, !message.labels.contains("TRASH") else { return false }
                    let sender = MailAddress.parse(message.from).valid.first?.address.lowercased() ?? ""
                    return !sender.isEmpty && !own.contains(sender)
                }
                if answered {
                    // Gmail zet het antwoord zelf in de inbox.
                    remove(threadID: entry.threadID)
                    changed = true
                } else if entry.due <= now {
                    guard (try? await gmail.moveToInbox(threadID: entry.threadID, account: entry.account)) != nil else { continue }
                    remove(threadID: entry.threadID)
                    returned[entry.threadID] = "Geen antwoord sinds \(DutchDate.short(entry.since))"
                    AppState.shared.announce("Geen antwoord: \(entry.subject)", seconds: 4)
                    changed = true
                }
            }
        }
        guard changed else { return }
        save()
        await gmail.reload()
        if MailModeStore.shared.isActive { await MailModeStore.shared.reload() }
    }
}
