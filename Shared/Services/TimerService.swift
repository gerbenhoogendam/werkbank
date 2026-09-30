import Foundation
import SwiftData
import WerkbankCore

/// Alle timerlogica. Er loopt maximaal één timer tegelijk; alles rekent met tijdstempels.
@MainActor
enum TimerService {
    static let noClient = "Geen klant"

    // MARK: Opvragen

    static func allEntries(in context: ModelContext) -> [TimeEntry] {
        (try? context.fetch(FetchDescriptor<TimeEntry>())) ?? []
    }

    static func runningEntry(in context: ModelContext) -> TimeEntry? {
        allEntries(in: context).first { $0.status == .running }
    }

    // MARK: Start / pauze / hervat

    /// Start een timer, of hervat hem. Een eventueel lopende andere timer gaat op pauze.
    static func start(_ entry: TimeEntry, in context: ModelContext, now: Date = .now) {
        guard entry.status != .finished, entry.status != .running else { return }

        for other in allEntries(in: context) where other.status == .running && other.id != entry.id {
            pause(other, in: context, now: now)
        }

        if entry.status == .paused, let pausedAt = entry.pausedAt {
            entry.pausedTotal += max(0, now.timeIntervalSince(pausedAt))
        }
        entry.pausedAt = nil
        entry.runningSince = now
        entry.lastStart = now
        if entry.firstStart == nil { entry.firstStart = now }
        entry.status = .running
        save(context)
    }

    static func pause(_ entry: TimeEntry, in context: ModelContext, now: Date = .now) {
        guard entry.status == .running, let since = entry.runningSince else { return }
        entry.accumulated += max(0, now.timeIntervalSince(since))
        entry.runningSince = nil
        entry.pausedAt = now
        entry.interruptions += 1
        entry.status = .paused
        save(context)
    }

    // MARK: Stoppen

    /// Bevriest de timer voor de stopsheet en geeft de standaard-eindtijd terug:
    /// "nu", of het pauzemoment als de timer al gepauzeerd was. Dit telt niet als onderbreking.
    /// Annuleren van de sheet laat de regel dus gepauzeerd achter.
    static func freezeForStop(_ entry: TimeEntry, in context: ModelContext, now: Date = .now) -> Date {
        switch entry.status {
        case .running:
            if let since = entry.runningSince {
                entry.accumulated += max(0, now.timeIntervalSince(since))
            }
            entry.runningSince = nil
            entry.pausedAt = now
            entry.status = .paused
            save(context)
            return now
        case .paused:
            return entry.pausedAt ?? now
        default:
            return now
        }
    }

    /// Rondt de regel af. `subtracted` is de eindtijdcorrectie uit `EndTimeCorrection`.
    /// - Parameters:
    ///   - subtracted: eindtijdcorrectie (tijd die er aan het eind af gaat).
    ///   - startAdjust: begintijdcorrectie (positief = eerder begonnen, negatief = later); `newFirstStart` wordt dan de begintijd.
    ///   - correction: aftrek op de te factureren tijd; de gemeten tijd blijft staan.
    static func finish(_ entry: TimeEntry, description: String, end: Date, subtracted: TimeInterval,
                       startAdjust: TimeInterval = 0, newFirstStart: Date? = nil, correction: TimeInterval = 0,
                       in context: ModelContext) {
        entry.accumulated = max(0, entry.accumulated - subtracted + startAdjust)
        if let newFirstStart { entry.firstStart = newFirstStart }
        entry.correctionSeconds = max(0, correction)
        entry.workDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.runningSince = nil
        entry.pausedAt = nil
        entry.finishedAt = end
        entry.status = .finished
        save(context)
    }

    // MARK: Aanmaken

    /// Timerknop op een kaart: hervat een bestaande, niet-afgeronde regel voor die kaart, anders nieuw.
    @discardableResult
    static func startTimer(for card: TodoCard, in context: ModelContext) -> TimeEntry {
        let existing = allEntries(in: context).first { $0.todoID == card.id && $0.status != .finished }
        let entry = existing ?? {
            let e = TimeEntry(title: card.title, client: card.clientLabel ?? noClient, source: .todo, todoID: card.id)
            context.insert(e)
            return e
        }()
        start(entry, in: context)
        return entry
    }

    @discardableResult
    static func startSupport(client: String, description: String, in context: ModelContext) -> TimeEntry {
        let entry = TimeEntry(title: description, client: normalized(client), source: .support)
        context.insert(entry)
        start(entry, in: context)
        return entry
    }

    /// Direct een afgeronde supportregel met vaste duur.
    @discardableResult
    static func logSupport(client: String, description: String, minutes: Int,
                           in context: ModelContext, now: Date = .now) -> TimeEntry {
        let entry = TimeEntry(title: description, client: normalized(client), source: .support)
        let start = now.addingTimeInterval(-Double(minutes) * 60)
        entry.accumulated = Double(minutes) * 60
        entry.firstStart = start
        entry.lastStart = start
        entry.finishedAt = now
        entry.workDescription = description
        entry.status = .finished
        context.insert(entry)
        save(context)
        return entry
    }

    /// Tijd die al aan een to-do besteed is voordat de kaart in Werkbank kwam (bijv. een gesprek over de mail):
    /// direct een afgeronde regel met die duur, gekoppeld aan de kaart.
    @discardableResult
    static func logPriorTime(for card: TodoCard, minutes: Int, in context: ModelContext,
                             now: Date = .now) -> TimeEntry {
        let entry = TimeEntry(title: card.title, client: normalized(card.clientLabel ?? ""),
                              source: .todo, todoID: card.id)
        let start = now.addingTimeInterval(-Double(minutes) * 60)
        entry.accumulated = Double(minutes) * 60
        entry.firstStart = start
        entry.lastStart = start
        entry.finishedAt = now
        entry.workDescription = card.title
        entry.status = .finished
        context.insert(entry)
        save(context)
        return entry
    }

    /// Agenda-afspraak als afgeronde tijdregel. Geeft `nil` terug als de afspraak al is toegevoegd.
    @discardableResult
    static func addCalendarEvent(_ event: AgendaEvent, in context: ModelContext) -> TimeEntry? {
        if allEntries(in: context).contains(where: { $0.externalID == event.id }) { return nil }
        let entry = TimeEntry(title: event.title, client: normalized(event.calendarTitle), source: .calendar)
        entry.accumulated = max(0, event.end.timeIntervalSince(event.start))
        entry.firstStart = event.start
        entry.lastStart = event.start
        entry.finishedAt = event.end
        entry.workDescription = event.title
        entry.externalID = event.id
        entry.status = .finished
        context.insert(entry)
        save(context)
        return entry
    }

    static func setWritten(_ entry: TimeEntry, _ value: Bool, in context: ModelContext) {
        guard entry.status == .finished else { return }
        entry.isWritten = value
        save(context)
    }

    // MARK: Hulpjes

    static func validDescription(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    static func normalized(_ client: String) -> String {
        let trimmed = client.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? noClient : trimmed
    }

    static func save(_ context: ModelContext) {
        try? context.save()
    }

    /// Te factureren uren van een afgeronde regel.
    static func billedHours(_ entry: TimeEntry) -> Double {
        Billing.billedHours(seconds: max(0, entry.accumulated - entry.correctionSeconds),
                            unitMinutes: AppSettings.roundingMinutes)
    }

    /// Verwijdert een tijdregel zonder die te bewaren (bijv. vanuit de stopsheet).
    static func discard(_ entry: TimeEntry, in context: ModelContext) {
        context.delete(entry)
        save(context)
    }

    /// Som van afgeronde, niet-geschreven regels.
    static func outstandingHours(_ entries: [TimeEntry]) -> Double {
        entries.filter { $0.status == .finished && !$0.isWritten }.reduce(0) { $0 + billedHours($1) }
    }
}
