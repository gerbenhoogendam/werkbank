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
    // Alle velden hebben een standaardwaarde en niets is `unique`: dat is vereist voor CloudKit-synchronisatie.
    var id: UUID = UUID()
    var title: String = ""
    var clientLabel: String?
    /// Domein waarvoor een logo geladen wordt (nil = geen logo).
    var logoDomain: String?
    /// "Naam · adres@domein.nl" bij kaarten die uit een mail komen.
    var senderLine: String?
    /// Alleen de tekst van de mail, om in de kaart te kunnen lezen.
    var bodyText: String?
    var columnRaw: String = BoardColumn.inbox.rawValue
    var sortOrder: Double = 0
    /// Blauwe stip tot de kaart uit de Inbox is gesleept.
    var isNew: Bool = true
    var createdAt: Date = Date()

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
    var id: UUID = UUID()
    var title: String = ""
    var client: String = ""
    var sourceRaw: String = TimeSource.todo.rawValue
    var statusRaw: String = TimerStatus.notStarted.rawValue

    /// Gemeten tijd tot en met de laatste pauze of stop. Een lopende timer komt daar
    /// `now - runningSince` bovenop: we rekenen met tijdstempels, niet met een tikkende teller,
    /// zodat slaapstand en herstart de tijd niet beïnvloeden.
    var accumulated: TimeInterval = 0
    var runningSince: Date?
    var pausedAt: Date?
    /// Totale tijd in pauze (tussen pauze en hervatten).
    var pausedTotal: TimeInterval = 0
    var interruptions: Int = 0
    var firstStart: Date?
    var lastStart: Date?
    var finishedAt: Date?

    var workDescription: String = ""
    /// Vinkje "geschreven" (in het facturatiesysteem).
    var isWritten: Bool = false
    var todoID: UUID?
    /// Voorkomt dat dezelfde agenda-afspraak dubbel wordt toegevoegd.
    var externalID: String?
    var createdAt: Date = Date()

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
    // Niet `unique` (CloudKit): dubbelen worden bij het opslaan via `BoardService.upsertMapping` voorkomen.
    var domain: String = ""
    var client: String = ""

    init(domain: String, client: String) {
        self.domain = domain.lowercased()
        self.client = client
    }
}

// MARK: - Opslag

enum Persistence {
    static let cloudToggleKey = "iCloudSyncEnabled"

    /// iCloud-synchronisatie is alleen mogelijk in een build met de iCloud-entitlements. Die build zet
    /// de compilatievlag `ICLOUD` (zie project.yml).
    static let isCloudBuild: Bool = {
        #if ICLOUD
        return true
        #else
        return false
        #endif
    }()

    /// Voorkeur van de gebruiker (standaard aan). Een wijziging geldt na herstarten.
    static var syncPreferred: Bool {
        UserDefaults.standard.object(forKey: cloudToggleKey) as? Bool ?? true
    }

    /// Of de database bij deze start met iCloud gesynchroniseerd wordt: build met iCloud, voorkeur aan
    /// en een ingelogd iCloud-account.
    static let isSyncing: Bool = isCloudBuild && syncPreferred && FileManager.default.ubiquityIdentityToken != nil

    static let container: ModelContainer = {
        let schema = Schema([TodoCard.self, TimeEntry.self, ClientMapping.self])

        #if ICLOUD
        if isSyncing {
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(for: schema, configurations: cloud) {
                return container
            }
            // CloudKit niet beschikbaar (bijv. schemafout): liever lokaal verder dan een app die niet start.
        }
        #endif

        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: local) {
            return container
        }

        // Een oudere database die niet migreert (bijv. na het verwijderen van unieke velden voor iCloud):
        // bewaar hem als back-up naast het origineel en begin met een lege database.
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-shm", "-wal"] {
            let file = local.url.path + suffix
            if fm.fileExists(atPath: file) {
                try? fm.moveItem(atPath: file, toPath: file + ".backup-\(stamp)")
            }
        }
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Kan de database niet openen: \(error)")
        }
    }()
}
