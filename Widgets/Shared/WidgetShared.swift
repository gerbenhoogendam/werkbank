import AppIntents
import Foundation

/// Wat de app voor de widgets klaarzet in de gedeelde map (App Group): de uren van vandaag, wat er loopt, verborgen
/// agenda's en de afspraken van vandaag en morgen (voor als de widget de agenda niet zelf mag lezen).
/// Dit bestand zit in de app én in de widget-extensie.
struct WidgetSnapshot: Codable {
    struct Event: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var location: String

        /// Afspraken die met "GH" beginnen zijn persoonlijk (net als in Agenda).
        var isPersonal: Bool { title.hasPrefix("GH") }
    }

    struct Running: Codable, Hashable {
        var client: String
        var accumulated: TimeInterval
        /// Nil als de timer gepauzeerd is.
        var runningSince: Date?

        func elapsed(at date: Date) -> TimeInterval {
            accumulated + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
        }
    }

    var writtenAt: Date
    /// Het begin van de dag waar de uren bij horen.
    var day: Date
    var finishedSeconds: TimeInterval
    var running: [Running]
    var hiddenCalendarIDs: [String]
    var events: [Event]

    /// Het dagdoel: 8 uur.
    static let dayGoal: TimeInterval = 8 * 3600

    func secondsToday(at date: Date, calendar: Calendar = .current) -> TimeInterval {
        guard calendar.isDate(day, inSameDayAs: date) else { return 0 }
        return finishedSeconds + running.reduce(0) { $0 + $1.elapsed(at: date) }
    }
}

enum WidgetShare {
    /// `group.<APP_BUNDLE_ID>`, uit de Info.plist van de app en van de extensie.
    static var groupID: String? { Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String }
    static var defaults: UserDefaults? { groupID.flatMap { UserDefaults(suiteName: $0) } }

    static var fileURL: URL? {
        guard let groupID,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { return nil }
        return folder.appendingPathComponent("Widgets.json")
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Tijd schrijven vanuit een widget of het bedieningspaneel

    static let requestKey = "widget.timeEntryRequest"
    static let requestAtKey = "widget.timeEntryRequestAt"
    static let requestNotification = Notification.Name("ZwoegBank.timeEntryRequest")

    /// "voice", "keyboard" of "stop", met het moment van de tik (stoppen rekent tot dan). De app pakt het op als hij
    /// actief wordt, of meteen via de melding als het verzoek in de app zelf wordt uitgevoerd.
    static func request(_ mode: String) {
        defaults?.set(mode, forKey: requestKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: requestAtKey)
        NotificationCenter.default.post(name: requestNotification, object: nil)
    }

    static func takeRequest() -> (mode: String, at: Date)? {
        guard let defaults, let mode = defaults.string(forKey: requestKey) else { return nil }
        let stamp = defaults.double(forKey: requestAtKey)
        defaults.removeObject(forKey: requestKey)
        defaults.removeObject(forKey: requestAtKey)
        return (mode, stamp > 0 ? Date(timeIntervalSince1970: stamp) : Date())
    }
}

/// Opent Zwoeg Bank met de tijdinvoer, inspreken.
struct SpeakTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Tijd inspreken"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetShare.request("voice")
        return .result()
    }
}

/// Opent Zwoeg Bank met de tijdinvoer, typen.
struct TypeTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Tijd typen"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetShare.request("keyboard")
        return .result()
    }
}

/// Stopt de lopende timer: opent Zwoeg Bank met de stopsheet, gerekend tot het moment van de tik.
struct StopTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Timer stoppen"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetShare.request("stop")
        return .result()
    }
}
