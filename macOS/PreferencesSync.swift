import AppKit
import Foundation
import Observation

/// Voorkeuren gelijk houden tussen Macs via iCloud Drive/Werkbank/Voorkeuren.plist. Kaarten en tijdregels gaan al via
/// iCloud (CloudKit); dit is voor de instellingen. Wie het laatst iets wijzigt, wint. Mailboxen (inloggen per Mac),
/// de Claude-sleutel (sleutelhanger) en vensterposities en -maten blijven per Mac.
@MainActor
@Observable
final class PreferencesSync {
    static let shared = PreferencesSync()
    static let fileName = "Voorkeuren.plist"

    /// Wat meegaat naar andere Macs.
    private static let keys: Set<String> = [
        SettingsKey.roundingMinutes, SettingsKey.agendaMode, SettingsKey.workDays, SettingsKey.startHour,
        SettingsKey.endHour, SettingsKey.defaultCalendar, SettingsKey.hiddenCalendars, SettingsKey.agendaHidden,
        SettingsKey.googleAPIKey, SettingsKey.googleCX, SettingsKey.longRunMinutes, SettingsKey.appearance,
        SettingsKey.miniTimerSize, SettingsKey.officeAddress, SettingsKey.homeAddress, SettingsKey.eventOpacity,
        calendarColorsKey, "mail.signatureHTML", "mail.signatureLogo", "mail.senderName", MailSettings.newestAtBottomKey,
        "gmail.displayNames", ClaudeSettings.modelKey, ClaudeSettings.contextKey,
    ]
    private static let calendarColorsKey = "calendar.colors"
    /// Alleen op deze Mac.
    private static let lastAppliedKey = "sync.lastApplied"
    private static let deviceKey = "sync.deviceID"

    /// Voor Voorkeuren: wanneer en vanaf welke Mac het laatst gesynchroniseerd is.
    private(set) var lastSync: Date?
    private(set) var lastSource: String?

    @ObservationIgnored private var hasRead = false
    @ObservationIgnored private var lastSnapshot: NSDictionary?
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    private let deviceID: String = {
        if let id = UserDefaults.standard.string(forKey: PreferencesSync.deviceKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: PreferencesSync.deviceKey)
        return id
    }()
    private let deviceName = Host.current().localizedName ?? "Mac"

    var isAvailable: Bool { WerkbankFolder.iCloud != nil }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PreferencesSync.shared.defaultsChanged() }
        }
    }

    // MARK: Wegschrijven

    private func defaultsChanged() {
        guard hasRead, isAvailable else { return }
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    private func snapshot() -> [String: Any] {
        var values: [String: Any] = [:]
        for key in Self.keys {
            if let value = UserDefaults.standard.object(forKey: key) { values[key] = value }
        }
        return values
    }

    /// Instellingen die hier zijn gewijzigd sinds het laatste wegschrijven of overnemen.
    private func changedKeys() -> Set<String> {
        let base = lastSnapshot as? [String: Any] ?? [:]
        let current = snapshot()
        return Self.keys.filter { !Self.same(current[$0], base[$0]) }
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as AnyObject).isEqual(b)
        default: return false
        }
    }

    private func push() async {
        guard let folder = WerkbankFolder.iCloud else { return }
        // Eerst overnemen wat een andere Mac intussen heeft gewijzigd, behalve wat hier net is gewijzigd.
        let changed = changedKeys()
        await pull(keeping: changed)
        let values = snapshot()
        guard !changed.isEmpty || !(lastSnapshot?.isEqual(to: values) ?? false) else { return }
        let updatedAt = Date()
        let file: [String: Any] = [
            "device": deviceID, "deviceName": deviceName, "updatedAt": updatedAt, "values": values,
            "calendars": CalendarService.shared.calendarKeys(),
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: file, format: .binary, options: 0) else { return }
        let url = folder.appendingPathComponent(Self.fileName)
        let written = await Task.detached(priority: .utility) { CloudFile.write(data, to: url) }.value
        guard written else { return }
        lastSnapshot = values as NSDictionary
        lastSync = updatedAt
        lastSource = deviceName
    }

    // MARK: Inlezen

    /// Neemt de voorkeuren van een andere Mac over als die nieuwer zijn dan wat hier al is overgenomen.
    func pull(keeping kept: Set<String> = []) async {
        await WerkbankFolder.prepare()
        guard let folder = WerkbankFolder.iCloud else { hasRead = true; return }
        let url = folder.appendingPathComponent(Self.fileName)
        // Staat het bestand nog alleen in iCloud, dan bestaat het wel: niet overschrijven met dat van deze Mac.
        let placeholder = folder.appendingPathComponent(".\(Self.fileName).icloud")
        let exists = FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: placeholder.path)
        let data = await Task.detached(priority: .utility) { CloudFile.read(url) }.value
        let firstRead = !hasRead
        hasRead = true

        guard let data,
              let file = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let values = file["values"] as? [String: Any],
              let updatedAt = file["updatedAt"] as? Date else {
            // Nog geen bestand (de eerste Mac): het onze wegzetten.
            if firstRead, !exists { defaultsChanged() }
            return
        }
        lastSync = updatedAt
        lastSource = file["deviceName"] as? String
        if (file["device"] as? String) == deviceID {
            if lastSnapshot == nil { lastSnapshot = values as NSDictionary }
            return
        }
        let lastApplied = UserDefaults.standard.object(forKey: Self.lastAppliedKey) as? Date ?? .distantPast
        guard updatedAt > lastApplied else {
            if lastSnapshot == nil { lastSnapshot = snapshot() as NSDictionary }
            return
        }
        apply(values.filter { !kept.contains($0.key) }, foreignCalendars: file["calendars"] as? [String: String] ?? [:])
        UserDefaults.standard.set(updatedAt, forKey: Self.lastAppliedKey)
        if kept.isEmpty { lastSnapshot = snapshot() as NSDictionary }
        AppState.shared.announce("Voorkeuren van \(lastSource ?? "andere Mac") overgenomen")
    }

    /// Agenda-id's verschillen per Mac: vertaald via "account|agenda".
    private func apply(_ values: [String: Any], foreignCalendars: [String: String]) {
        let local = CalendarService.shared.calendarKeys()
        var localByName: [String: String] = [:]
        for (id, name) in local where localByName[name] == nil { localByName[name] = id }
        func translate(_ id: String) -> String? {
            if local[id] != nil { return id }
            return foreignCalendars[id].flatMap { localByName[$0] }
        }
        // Zonder agendatoegang kan er niets vertaald worden: dan de agenda-instellingen hier laten zoals ze zijn.
        let canTranslate = !local.isEmpty

        let defaults = UserDefaults.standard
        for (key, value) in values where Self.keys.contains(key) {
            switch key {
            case SettingsKey.hiddenCalendars, SettingsKey.agendaHidden:
                guard canTranslate else { continue }
                let ids = (value as? String ?? "").split(separator: ",").map(String.init).compactMap(translate)
                defaults.set(ids.joined(separator: ","), forKey: key)
            case SettingsKey.defaultCalendar:
                guard canTranslate, let id = (value as? String).flatMap(translate) else { continue }
                defaults.set(id, forKey: key)
            case Self.calendarColorsKey:
                guard canTranslate else { continue }
                var mapped: [String: Any] = [:]
                for (id, color) in value as? [String: Any] ?? [:] {
                    if let localID = translate(id) { mapped[localID] = color }
                }
                defaults.set(mapped, forKey: key)
            default:
                defaults.set(value, forKey: key)
            }
        }
        CalendarService.shared.settingsChanged()
        GmailSession.shared.reloadDisplayNames()
        AppearanceSetting.applyStored()
    }
}

/// Alles wat in iCloud Drive/Werkbank staat bijhouden: voorkeuren, het geheugen van Claude en de klantenlijst.
/// Bij het starten, bij terugkomen in de app en elke minuut.
@MainActor
enum WerkbankSync {
    private static var task: Task<Void, Never>?

    static func start() {
        guard task == nil else { return }
        PreferencesSync.shared.start()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { _ in
            Task { @MainActor in await WerkbankSync.refresh() }
        }
        task = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    static func refresh() async {
        await PreferencesSync.shared.pull()
        await ClaudeMemory.shared.reload()
        await ClientDirectory.shared.refresh()
    }
}
