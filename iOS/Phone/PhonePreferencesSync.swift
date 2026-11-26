import Foundation
import Observation
import UIKit

/// Voorkeuren via iCloud: hetzelfde bestand als de Mac (Voorkeuren.plist in de map Werkbank in iCloud Drive). De iPhone
/// neemt alles over wat nieuwer is, behalve agenda-id's (die verschillen per toestel). Wat de iPhone zelf wijzigt gaat
/// erin terug, samen met wat er al stond, zodat de Mac niets kwijtraakt.
@MainActor
@Observable
final class PhonePreferencesSync {
    static let shared = PhonePreferencesSync()
    static let fileName = "Voorkeuren.plist"
    private static let lastAppliedKey = "sync.lastApplied"
    private static let deviceKey = "sync.deviceID"
    /// Agenda-id's zijn per toestel anders: niet overnemen.
    private static let skipped: Set<String> = [SettingsKey.hiddenCalendars, SettingsKey.agendaHidden,
                                               SettingsKey.defaultCalendar, "calendar.colors"]

    private(set) var lastSync: Date?
    private(set) var lastSource: String?
    private(set) var isAvailable = false

    @ObservationIgnored private var changed: Set<String> = []
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    private let deviceID: String = {
        if let id = UserDefaults.standard.string(forKey: PhonePreferencesSync.deviceKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: PhonePreferencesSync.deviceKey)
        return id
    }()

    /// Een voorkeur zetten die ook naar de Mac moet.
    func set(_ value: Any?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        changed.insert(key)
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    private func readFile() async -> [String: Any]? {
        await WerkbankFolder.prepare()
        guard let folder = WerkbankFolder.iCloud else { return nil }
        let url = folder.appendingPathComponent(Self.fileName)
        let data = await Task.detached(priority: .utility) { CloudFile.read(url) }.value
        guard let data else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// Neemt over wat een Mac nieuwer heeft weggeschreven.
    func pull() async {
        await WerkbankFolder.prepare()
        isAvailable = WerkbankFolder.iCloud != nil
        guard let file = await readFile(), let values = file["values"] as? [String: Any],
              let updatedAt = file["updatedAt"] as? Date else { return }
        lastSync = updatedAt
        lastSource = file["deviceName"] as? String
        guard (file["device"] as? String) != deviceID else { return }
        let lastApplied = UserDefaults.standard.object(forKey: Self.lastAppliedKey) as? Date ?? .distantPast
        guard updatedAt > lastApplied else { return }
        for (key, value) in values where !Self.skipped.contains(key) && !changed.contains(key) {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.set(updatedAt, forKey: Self.lastAppliedKey)
    }

    private func push() async {
        guard !changed.isEmpty else { return }
        await WerkbankFolder.prepare()
        guard let folder = WerkbankFolder.iCloud else { return }
        let existing = await readFile()
        var values = existing?["values"] as? [String: Any] ?? [:]
        for key in changed {
            if let value = UserDefaults.standard.object(forKey: key) { values[key] = value } else { values[key] = nil }
        }
        let updatedAt = Date()
        var file: [String: Any] = ["device": deviceID, "deviceName": UIDevice.current.name, "updatedAt": updatedAt,
                                   "values": values]
        if let calendars = existing?["calendars"] { file["calendars"] = calendars }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: file, format: .binary, options: 0) else { return }
        let url = folder.appendingPathComponent(Self.fileName)
        let written = await Task.detached(priority: .utility) { CloudFile.write(data, to: url) }.value
        guard written else { return }
        changed = []
        lastSync = updatedAt
        lastSource = UIDevice.current.name
        UserDefaults.standard.set(updatedAt, forKey: Self.lastAppliedKey)
    }
}
