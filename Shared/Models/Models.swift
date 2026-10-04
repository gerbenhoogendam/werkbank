import Foundation
import SwiftData
import SwiftUI

// MARK: - Board

/// Verwijzing naar een kolom van het board. Gelijkheid gaat op `id`: de kolommen zelf staan in `ColumnRecord`
/// (naam en volgorde zijn aanpasbaar); deze waarde is wat de views en het slepen doorgeven.
struct BoardColumn: Hashable, Identifiable {
    /// De Inbox heeft een vaste sleutel: daar komen nieuwe mails en snelle invoer terecht.
    static let inboxID = "inbox"
    /// De standaardkolom "Klaar": kaarten daarin tellen niet mee als openstaand (menubalk).
    static let doneID = "done"
    static let inbox = BoardColumn(id: inboxID, title: "Inbox", color: ThingsColor.inbox, symbol: "tray.fill")

    let id: String
    var title: String = ""
    var color: Color = ThingsColor.textSecondary
    var symbol: String = "rectangle.stack.fill"

    static func == (lhs: BoardColumn, rhs: BoardColumn) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Kleuren voor kolommen (Things-lijstkleuren); een nieuwe kolom krijgt de volgende in de rij.
enum ColumnPalette {
    static let colors: [Color] = [ThingsColor.inbox, ThingsColor.anytime, ThingsColor.today, ThingsColor.someday,
                                  ThingsColor.logbook, ThingsColor.upcoming, ThingsColor.evening, ThingsColor.trash]

    static func color(at index: Int) -> Color { colors[((index % colors.count) + colors.count) % colors.count] }
}

/// Een kolom van het board. Kaarten verwijzen ernaar via `TodoCard.columnRaw` (= `key`).
@Model
final class ColumnRecord {
    // Niet `unique` (CloudKit): dubbelen (twee apparaten die tegelijk de standaardkolommen aanmaken) worden
    // door `BoardService.ensureColumns` opgeruimd.
    var key: String = ""
    var title: String = ""
    var sortOrder: Double = 0
    var colorIndex: Int = 0
    var symbol: String = "rectangle.stack.fill"
    var createdAt: Date = Date()

    init(key: String, title: String, sortOrder: Double, colorIndex: Int, symbol: String = "rectangle.stack.fill") {
        self.key = key
        self.title = title
        self.sortOrder = sortOrder
        self.colorIndex = colorIndex
        self.symbol = symbol
        self.createdAt = .now
    }

    var column: BoardColumn {
        BoardColumn(id: key, title: title, color: ColumnPalette.color(at: colorIndex), symbol: symbol)
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
    /// Eigen notities bij de taak (los van de mailtekst).
    var notes: String = ""
    /// Sleutel van de kolom (`ColumnRecord.key`).
    var columnRaw: String = BoardColumn.inboxID
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
        self.columnRaw = column.id
        self.sortOrder = sortOrder
        self.isNew = isNew
        self.createdAt = .now
    }

    var column: BoardColumn {
        // Alleen de sleutel: titel en kleur komen uit `ColumnRecord` (zie `BoardService.columns`).
        get { BoardColumn(id: columnRaw) }
        set { columnRaw = newValue.id }
    }
}

// MARK: - Subtaken

/// Een subtaak van een kaart. Verwijst met `cardID` naar de kaart (zoals `TimeEntry.todoID`); bij het verwijderen
/// van een kaart ruimt `BoardService.delete` de subtaken op.
@Model
final class Subtask {
    var id: UUID = UUID()
    var cardID: UUID = UUID()
    var title: String = ""
    var isDone: Bool = false
    var sortOrder: Double = 0
    var createdAt: Date = Date()

    init(cardID: UUID, title: String, sortOrder: Double) {
        self.id = UUID()
        self.cardID = cardID
        self.title = title
        self.isDone = false
        self.sortOrder = sortOrder
        self.createdAt = .now
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
    /// Aftrek op de te factureren tijd (bijv. een kwartier dat niet telt). De gemeten tijd blijft ongewijzigd.
    var correctionSeconds: TimeInterval = 0
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
        let schema = Schema([TodoCard.self, TimeEntry.self, ClientMapping.self, ColumnRecord.self, Subtask.self])

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
