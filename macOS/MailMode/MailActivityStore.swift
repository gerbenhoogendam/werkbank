import Foundation
import WerkbankCore

/// Wie je wanneer mailde (afzender, Aan, Cc), voor de klanten op volgorde van contact in de mailmodus en later het
/// aanvullen van adressen. Alleen op deze Mac, in Application Support; elke keer komt alleen wat er sinds de vorige
/// keer bij kwam.
@MainActor
final class MailActivityStore {
    static let shared = MailActivityStore()

    private struct Stored: Codable {
        var records: [MailActivityRecord]
        var lastSync: [String: Date]
        var names: [String: String]?
    }

    private(set) var records: [MailActivityRecord] = []
    /// De naam bij een adres, zoals die in de mail stond (voor het aanvullen).
    private(set) var names: [String: String] = [:]
    private var lastSync: [String: Date] = [:]
    private var ids = Set<String>()
    private var loaded = false
    private var syncing = false

    /// Hoe ver terug bij de eerste keer, en hoe lang een mail bewaard blijft.
    private static let firstSyncDays = 31.0
    private static let keepDays = 400.0

    private static var file: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("Werkbank", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("MailActivity.json")
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let file = Self.file, let data = try? Data(contentsOf: file) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let stored = try? decoder.decode(Stored.self, from: data) else { return }
        records = stored.records
        lastSync = stored.lastSync
        names = stored.names ?? [:]
        ids = Set(records.map(\.id))
    }

    private func save() {
        guard let file = Self.file else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(Stored(records: records, lastSync: lastSync, names: names)) {
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Mails die de mailmodus toch al ophaalde (lijst, zoeken) tellen meteen mee.
    @discardableResult
    func add(_ items: [GmailMailItem]) -> Bool {
        loadIfNeeded()
        var changed = false
        for item in items where !ids.contains(item.id) {
            if let address = item.fromAddress?.lowercased(),
               let name = item.fromName?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name.lowercased() != address,
               names[address] != name {
                names[address] = name
            }
            guard let record = MailActivityRecord(item) else { continue }
            records.append(record)
            ids.insert(record.id)
            changed = true
        }
        if changed { save() }
        return changed
    }

    /// Haalt per mailbox op wat er sinds de vorige keer bij kwam (de eerste keer de laatste maand).
    @discardableResult
    func sync() async -> Bool {
        loadIfNeeded()
        let gmail = GmailSession.shared
        guard !syncing, gmail.state == .signedIn else { return false }
        syncing = true
        defer { syncing = false }
        let accounts: [String?] = gmail.accounts.isEmpty ? [gmail.activeAccount] : gmail.accounts.map { $0 }
        var changed = false
        for account in accounts {
            let key = account ?? ""
            let started = Date()
            // Een uur overlap: Gmail zoekt op dagen en mails komen soms iets later binnen.
            let since = lastSync[key].map { $0.addingTimeInterval(-3600) } ?? started.addingTimeInterval(-Self.firstSyncDays * 86_400)
            let items = await gmail.activityItems(since: since, account: account)
            if add(items) { changed = true }
            lastSync[key] = started
        }
        let cutoff = Date().addingTimeInterval(-Self.keepDays * 86_400)
        let before = records.count
        records.removeAll { $0.date < cutoff }
        if records.count != before {
            ids = Set(records.map(\.id))
            changed = true
        }
        save()
        return changed
    }
}
