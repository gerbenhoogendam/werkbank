import Foundation
import SwiftData

/// ⌘Z voor handelingen in de app (niet alleen voor tekst). Werkt via de UndoManager van het hoofdvenster, zodat
/// Wijzig › Herstel en ⇧⌘Z (opnieuw) ook werken. Na ongedaan maken verschijnt een melding in de timer-pil.
@MainActor
final class UndoCenter {
    static let shared = UndoCenter()

    /// Gezet door het hoofdvenster. Zonder (bijvoorbeeld op iOS) wordt er niets vastgelegd.
    weak var manager: UndoManager?

    /// Legt een handeling vast. `redo` mag ontbreken: dan kan hij wel ongedaan, maar niet opnieuw.
    func record(_ name: String, undo: @escaping @MainActor () -> Void, redo: (@MainActor () -> Void)? = nil) {
        guard let manager else { return }
        manager.registerUndo(withTarget: self) { [weak manager] center in
            MainActor.assumeIsolated {
                let undoing = manager?.isUndoing ?? true
                undo()
                AppState.shared.announce(undoing ? "\(name) ongedaan" : "\(name) opnieuw gedaan")
                if let redo { center.record(name, undo: redo, redo: undo) }
            }
        }
        manager.setActionName(name)
    }
}

// MARK: - Momentopnames om iets terug te zetten

/// Waar een kaart stond (kolom, volgorde, afgerond).
struct CardPlace {
    let columnRaw: String
    let sortOrder: Double
    let isNew: Bool
    let completedAt: Date?

    init(_ card: TodoCard) {
        columnRaw = card.columnRaw
        sortOrder = card.sortOrder
        isNew = card.isNew
        completedAt = card.completedAt
    }

    func restore(_ card: TodoCard) {
        card.columnRaw = columnRaw
        card.sortOrder = sortOrder
        card.isNew = isNew
        card.completedAt = completedAt
    }
}

/// Een verwijderde kaart met subtaken, om hem met hetzelfde id terug te zetten (tijdregels verwijzen ernaar).
struct CardSnapshot {
    let id: UUID
    let title: String
    let clientLabel: String?
    let logoDomain: String?
    let senderLine: String?
    let bodyText: String?
    let notes: String
    let place: CardPlace
    let createdAt: Date
    let mailThreadID: String?
    let mailAccount: String?
    let waitingSince: Date?
    let subtasks: [SubtaskSnapshot]

    @MainActor
    init(_ card: TodoCard, subtasks: [Subtask]) {
        id = card.id
        title = card.title
        clientLabel = card.clientLabel
        logoDomain = card.logoDomain
        senderLine = card.senderLine
        bodyText = card.bodyText
        notes = card.notes
        place = CardPlace(card)
        createdAt = card.createdAt
        mailThreadID = card.mailThreadID
        mailAccount = card.mailAccount
        waitingSince = card.waitingSince
        self.subtasks = subtasks.map(SubtaskSnapshot.init)
    }

    @discardableResult
    func recreate(in context: ModelContext) -> TodoCard {
        let card = TodoCard(title: title, clientLabel: clientLabel, logoDomain: logoDomain, senderLine: senderLine,
                            sortOrder: place.sortOrder)
        card.id = id
        card.bodyText = bodyText
        card.notes = notes
        card.createdAt = createdAt
        card.mailThreadID = mailThreadID
        card.mailAccount = mailAccount
        card.waitingSince = waitingSince
        place.restore(card)
        context.insert(card)
        for subtask in subtasks { subtask.recreate(in: context) }
        try? context.save()
        return card
    }
}

struct SubtaskSnapshot {
    let id: UUID
    let cardID: UUID
    let title: String
    let isDone: Bool
    let sortOrder: Double
    let createdAt: Date

    init(_ subtask: Subtask) {
        id = subtask.id
        cardID = subtask.cardID
        title = subtask.title
        isDone = subtask.isDone
        sortOrder = subtask.sortOrder
        createdAt = subtask.createdAt
    }

    func recreate(in context: ModelContext) {
        let subtask = Subtask(cardID: cardID, title: title, sortOrder: sortOrder)
        subtask.id = id
        subtask.isDone = isDone
        subtask.createdAt = createdAt
        context.insert(subtask)
    }
}

/// Een verwijderde tijdregel.
struct TimeEntrySnapshot {
    let id: UUID
    let title: String
    let client: String
    let sourceRaw: String
    let statusRaw: String
    let accumulated: TimeInterval
    let runningSince: Date?
    let pausedAt: Date?
    let pausedTotal: TimeInterval
    let interruptions: Int
    let firstStart: Date?
    let lastStart: Date?
    let finishedAt: Date?
    let workDescription: String
    let correctionSeconds: TimeInterval
    let isWritten: Bool
    let todoID: UUID?
    let externalID: String?
    let createdAt: Date

    init(_ entry: TimeEntry) {
        id = entry.id
        title = entry.title
        client = entry.client
        sourceRaw = entry.sourceRaw
        statusRaw = entry.statusRaw
        accumulated = entry.accumulated
        runningSince = entry.runningSince
        pausedAt = entry.pausedAt
        pausedTotal = entry.pausedTotal
        interruptions = entry.interruptions
        firstStart = entry.firstStart
        lastStart = entry.lastStart
        finishedAt = entry.finishedAt
        workDescription = entry.workDescription
        correctionSeconds = entry.correctionSeconds
        isWritten = entry.isWritten
        todoID = entry.todoID
        externalID = entry.externalID
        createdAt = entry.createdAt
    }

    func recreate(in context: ModelContext) {
        let entry = TimeEntry(title: title, client: client, source: TimeSource(rawValue: sourceRaw) ?? .todo, todoID: todoID)
        entry.id = id
        entry.statusRaw = statusRaw
        entry.accumulated = accumulated
        entry.runningSince = runningSince
        entry.pausedAt = pausedAt
        entry.pausedTotal = pausedTotal
        entry.interruptions = interruptions
        entry.firstStart = firstStart
        entry.lastStart = lastStart
        entry.finishedAt = finishedAt
        entry.workDescription = workDescription
        entry.correctionSeconds = correctionSeconds
        entry.isWritten = isWritten
        entry.externalID = externalID
        entry.createdAt = createdAt
        context.insert(entry)
        try? context.save()
    }
}
