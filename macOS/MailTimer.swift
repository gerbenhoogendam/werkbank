import SwiftData
import SwiftUI
import WerkbankCore

/// Timer per mailgesprek. Eén tijdregel per gesprek: opnieuw starten (ook bij een vervolgmail) telt erbij op, tot de
/// regel als geschreven is afgevinkt; daarna begint een nieuwe. Starten gaat altijd met de hand.
@MainActor
enum MailTimer {
    /// De regel van dit gesprek die nog niet geschreven is.
    static func openEntry(threadID: String, in context: ModelContext) -> TimeEntry? {
        TimerService.allEntries(in: context)
            .filter { $0.mailThreadID == threadID && !$0.isWritten }
            .max { $0.createdAt < $1.createdAt }
    }

    /// Start, pauzeert of hervat de timer van het gesprek. `senders`: afzenders ("Naam <adres>") om de klant te bepalen.
    static func toggle(threadID: String, subject: String, senders: [String], in context: ModelContext) {
        if let entry = openEntry(threadID: threadID, in: context) {
            switch entry.status {
            case .running:
                TimerService.pause(entry, in: context)
                AppState.shared.announce("Timer gepauzeerd")
            case .finished:
                // Al gestopt maar nog niet geschreven: verder tellen in dezelfde regel.
                entry.status = .paused
                entry.pausedAt = .now
                entry.finishedAt = nil
                TimerService.start(entry, in: context)
                AppState.shared.announce("Timer loopt weer: \(entry.title)")
            case .paused, .notStarted:
                TimerService.start(entry, in: context)
                AppState.shared.announce("Timer loopt weer: \(entry.title)")
            }
            return
        }

        // Hoort het gesprek bij een kaart, dan telt de tijd ook voor die kaart.
        let card = BoardService.allCards(in: context)
            .first { $0.mailThreadID == threadID && $0.columnRaw != BoardColumn.doneID }
        let title = card?.title ?? caseTitle(from: subject)
        let client = card?.clientLabel.map(TimerService.normalized) ?? self.client(from: senders, in: context)
        let entry = TimeEntry(title: title, client: client, source: .mail, todoID: card?.id)
        entry.mailThreadID = threadID
        context.insert(entry)
        TimerService.start(entry, in: context)
        AppState.shared.announce("Timer gestart: \(title)")
    }

    /// Onderwerp zonder "Re:", "Fw:" en dergelijke.
    static func caseTitle(from subject: String) -> String {
        let stripped = subject.replacingOccurrences(of: #"^\s*((re|fw|fwd|aw|wg|antw|doorst)\s*:\s*)+"#, with: "",
                                                    options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? "(geen onderwerp)" : stripped
    }

    /// De klant van de eerste afzender die niet een van de eigen mailboxen is.
    private static func client(from senders: [String], in context: ModelContext) -> String {
        let own = Set(GmailSession.shared.accounts.map { $0.lowercased() })
        let mapping = BoardService.mappingTable(in: context)
        for sender in senders {
            guard let address = MailAddress.parse(sender).valid.first,
                  !own.contains(address.address.lowercased()),
                  let resolution = ClientNaming.resolve(displayName: address.name, address: address.address,
                                                        mapping: mapping) else { continue }
            return resolution.name
        }
        return TimerService.noClient
    }
}

/// Timerknop voor een gesprek: in de kop van het gesprek en onder het opstelvenster.
struct MailTimerButton: View {
    let threadID: String
    let subject: String
    let senders: [String]

    @Environment(\.modelContext) private var context
    @Query private var entries: [TimeEntry]

    init(threadID: String, subject: String, senders: [String]) {
        self.threadID = threadID
        self.subject = subject
        self.senders = senders
        let id: String? = threadID
        _entries = Query(filter: #Predicate<TimeEntry> { $0.mailThreadID == id && !$0.isWritten },
                         sort: \TimeEntry.createdAt, order: .reverse)
    }

    var body: some View {
        let entry = entries.first
        let isRunning = entry?.status == .running
        Button {
            MailTimer.toggle(threadID: threadID, subject: subject, senders: senders, in: context)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isRunning ? "pause.circle.fill" : "play.circle")
                    .foregroundStyle(isRunning ? ThingsColor.running : ThingsColor.accent)
                if let entry, isRunning {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(Billing.formatHMS(entry.elapsed(at: timeline.date)))
                    }
                    .monospacedDigit()
                } else if let entry {
                    Text(Billing.formatHMS(entry.elapsed())).monospacedDigit()
                } else {
                    Text("Timer")
                }
            }
        }
        .help(isRunning ? "Timer pauzeren" : "Timer starten")
    }
}
