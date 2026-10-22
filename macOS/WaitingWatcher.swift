import Foundation
import SwiftData
import WerkbankCore

/// Wacht op klant voor kaarten die uit een mail komen. Antwoord je in het gesprek van een kaart, dan gaat die naar
/// Wacht op klant. Komt er daarna een mail van iemand anders in dat gesprek, dan gaat hij terug naar Te doen met een
/// blauwe stip. Kijkt elke drie minuten, ook als het Mail-paneel dicht is.
@MainActor
final class WaitingWatcher {
    static let shared = WaitingWatcher()

    /// Vaste sleutels van de standaardkolommen (zie `BoardService.defaultColumns`); de namen kun je wijzigen.
    private static let waitingKey = "waiting"
    private static let backKey = "todo"

    private var task: Task<Void, Never>?
    private var context: ModelContext { Persistence.container.mainContext }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(180))
            }
        }
    }

    /// Na het versturen van een antwoord in `threadID`. Geeft de naam van Wacht op klant terug als er een kaart heen ging.
    @discardableResult
    func didReply(threadID: String) -> String? {
        let cards = linkedCards(threadID: threadID)
        guard !cards.isEmpty, let waiting = column(Self.waitingKey) else { return nil }
        var moved = false
        for card in cards {
            card.waitingSince = .now
            if card.columnRaw != waiting.id {
                BoardService.move(card, to: waiting, index: 0, undoable: true, in: context)
                moved = true
            }
        }
        try? context.save()
        return moved ? waiting.title : nil
    }

    /// Een gesprek is naar een andere mailbox verplaatst (en heeft daar een ander id): de kaarten volgen.
    func relink(threadID: String, to newThreadID: String, account: String?) {
        for card in linkedCards(threadID: threadID, includeDone: true) {
            card.mailThreadID = newThreadID
            card.mailAccount = account
        }
        try? context.save()
    }

    private func linkedCards(threadID: String, includeDone: Bool = false) -> [TodoCard] {
        BoardService.allCards(in: context).filter {
            $0.mailThreadID == threadID && (includeDone || $0.columnRaw != BoardColumn.doneID)
        }
    }

    private func column(_ key: String) -> BoardColumn? {
        BoardService.columns(in: context).first { $0.id == key }
    }

    /// Terug na een antwoord: Te doen, anders de eerste kolom die geen Inbox of Wacht op klant is.
    private func backColumn() -> BoardColumn? {
        let all = BoardService.columns(in: context)
        return all.first { $0.id == Self.backKey }
            ?? all.first { $0.id != BoardColumn.inboxID && $0.id != Self.waitingKey }
            ?? all.first
    }

    func check() async {
        let gmail = GmailSession.shared
        guard gmail.state == .signedIn, let waiting = column(Self.waitingKey) else { return }

        // Uit Wacht op klant gehaald: wacht nergens meer op. Met de hand erheen gesleept: wacht vanaf nu.
        let all = BoardService.allCards(in: context)
        for card in all where card.waitingSince != nil && card.columnRaw != waiting.id { card.waitingSince = nil }
        let cards = all.filter { $0.columnRaw == waiting.id && $0.mailThreadID != nil }
        for card in cards where card.waitingSince == nil { card.waitingSince = .now }
        try? context.save()

        let own = Set(gmail.accounts.map { $0.lowercased() })
        let items = cards.compactMap { card -> (id: UUID, threadID: String, account: String?, since: Date)? in
            guard let threadID = card.mailThreadID, let since = card.waitingSince else { return nil }
            return (card.id, threadID, card.mailAccount, since)
        }
        for item in items {
            if let account = item.account, !gmail.accounts.contains(account) { continue }   // losgekoppeld
            guard let messages = try? await gmail.threadMessages(threadID: item.threadID, account: item.account) else {
                continue
            }
            let answered = messages.contains { message in
                guard message.date > item.since, !message.isSent, !message.labels.contains("TRASH") else { return false }
                let sender = MailAddress.parse(message.from).valid.first?.address.lowercased() ?? ""
                return !sender.isEmpty && !own.contains(sender)
            }
            // Intussen kan de kaart verplaatst of afgerond zijn.
            guard answered, let card = BoardService.card(withID: item.id, in: context), card.columnRaw == waiting.id,
                  let back = backColumn() else { continue }
            BoardService.move(card, to: back, index: 0, in: context)
            card.isNew = true
            card.waitingSince = nil
            try? context.save()
            AppState.shared.announce("Antwoord: \(card.title)", seconds: 4)
        }
    }
}
