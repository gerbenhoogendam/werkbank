import Foundation
import SwiftData
import SwiftUI

// MARK: - Board

enum BoardColumn: String, CaseIterable, Identifiable {
    case inbox, todo, doing, waiting, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox:   return "Inbox"
        case .todo:    return "Te doen"
        case .doing:   return "Bezig"
        case .waiting: return "Wacht op klant"
        case .done:    return "Klaar"
        }
    }

    /// Kolomkleuren hergebruiken de Things-lijstkleuren (kleur = betekenis).
    var color: Color {
        switch self {
        case .inbox:   return ThingsColor.inbox
        case .todo:    return ThingsColor.anytime
        case .doing:   return ThingsColor.today
        case .waiting: return ThingsColor.someday
        case .done:    return ThingsColor.logbook
        }
    }

    var symbol: String {
        switch self {
        case .inbox:   return "tray.fill"
        case .todo:    return "square.stack.3d.up.fill"
        case .doing:   return "star.fill"
        case .waiting: return "hourglass"
        case .done:    return "checkmark.square.fill"
        }
    }
}

@Model
final class TodoCard {
    @Attribute(.unique) var id: UUID
    var title: String
    var clientLabel: String?
    /// Domein waarvoor een logo geladen wordt (nil = geen logo).
    var logoDomain: String?
    /// "Naam · adres@domein.nl" bij kaarten die uit een mail komen.
    var senderLine: String?
    var columnRaw: String
    var sortOrder: Double
    /// Blauwe stip tot de kaart uit de Inbox is gesleept.
    var isNew: Bool
    var createdAt: Date

    init(title: String,
         clientLabel: String? = nil,
         logoDomain: String? = nil,
         senderLine: String? = nil,
         column: BoardColumn = .inbox,
         sortOrder: Double,
         isNew: Bool = true) {
        self.id = UUID()
        self.title = title
        self.clientLabel = clientLabel
        self.logoDomain = logoDomain
        self.senderLine = senderLine
        self.columnRaw = column.rawValue
        self.sortOrder = sortOrder
        self.isNew = isNew
        self.createdAt = .now
    }

    var column: BoardColumn {
        get { BoardColumn(rawValue: columnRaw) ?? .inbox }
        set { columnRaw = newValue.rawValue }
    }
}

// MARK: - Tijd schrijven

enum TimeSource: String {
    case todo, support, calendar

    var title: String {
        switch self {
        case .todo:     return "To-do"
        case .support:  return "Support"
        case .calendar: return "Agenda"
        }
    }
}

enum TimerStatus: String {
    case notStarted, running, paused, finished
}

@Model
final class TimeEntry {
    @Attribute(.unique) var id: UUID
    var title: String
    var client: String
    var sourceRaw: String
    var statusRaw: String

    /// Gemeten tijd tot en met de laatste pauze of stop. Een lopende timer komt daar
    /// `now - runningSince` bovenop: we rekenen met tijdstempels, niet met een tikkende teller,
    /// zodat slaapstand en herstart de tijd niet beïnvloeden.
    var accumulated: TimeInterval
    var runningSince: Date?
    var pausedAt: Date?
    /// Totale tijd in pauze (tussen pauze en hervatten).
    var pausedTotal: TimeInterval
    var interruptions: Int
    var firstStart: Date?
    var lastStart: Date?
    var finishedAt: Date?

    var workDescription: String
    /// Vinkje "geschreven" (in het facturatiesysteem).
    var isWritten: Bool
    var todoID: UUID?
    /// Voorkomt dat dezelfde agenda-afspraak dubbel wordt toegevoegd.
    var externalID: String?
    var createdAt: Date

    init(title: String, client: String, source: TimeSource, todoID: UUID? = nil) {
        self.id = UUID()
        self.title = title
        self.client = client
        self.sourceRaw = source.rawValue
        self.statusRaw = TimerStatus.notStarted.rawValue
        self.accumulated = 0
        self.pausedTotal = 0
        self.interruptions = 0
        self.workDescription = ""
        self.isWritten = false
        self.todoID = todoID
        self.createdAt = .now
    }

    var source: TimeSource {
        get { TimeSource(rawValue: sourceRaw) ?? .todo }
        set { sourceRaw = newValue.rawValue }
    }

    var status: TimerStatus {
        get { TimerStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    func elapsed(at now: Date = .now) -> TimeInterval {
        accumulated + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}

// MARK: - Koppeltabel domein → klant

@Model
final class ClientMapping {
    @Attribute(.unique) var domain: String
    var client: String

    init(domain: String, client: String) {
        self.domain = domain.lowercased()
        self.client = client
    }
}

// MARK: - Opslag

enum Persistence {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: TodoCard.self, TimeEntry.self, ClientMapping.self)
        } catch {
            fatalError("Kan de database niet openen: \(error)")
        }
    }()
}
