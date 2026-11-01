import Foundation
import Observation
import WerkbankCore

/// Wie je wanneer mailde (afzender, Aan, Cc, per mailbox), voor de klanten op volgorde van contact in de mailmodus en
/// het aanvullen van adressen. Alleen op deze Mac, in Application Support. Gaat drie maanden terug en wordt hooguit één
/// keer per dag bijgewerkt (alleen wat er sinds de vorige keer bij kwam); daartussen komt alles uit dit bestand.
@MainActor
@Observable
final class MailActivityStore {
    static let shared = MailActivityStore()

    private struct Stored: Codable {
        var records: [MailActivityRecord]
        var lastSync: [String: Date]
        var names: [String: String]?
        /// Per mailbox: vanaf wanneer alles is opgehaald.
        var coveredFrom: [String: Date]?
    }

    private(set) var records: [MailActivityRecord] = []
    /// De naam bij een adres, zoals die in de mail stond (voor het aanvullen).
    private(set) var names: [String: String] = [:]
    /// Bezig met bijwerken (de eerste keer kan dat een minuut duren).
    private(set) var isSyncing = false
    @ObservationIgnored private var lastSync: [String: Date] = [:]
    @ObservationIgnored private var coveredFrom: [String: Date] = [:]
    @ObservationIgnored private var ids = Set<String>()
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Hoe ver terug, hoe lang een mail bewaard blijft en hoe vaak er wordt bijgewerkt.
    static let historyDays = 92.0
    private static let keepDays = 400.0
    private static let refreshInterval = 86_400.0

    private nonisolated static var file: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("Werkbank", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("MailActivity.json")
    }

    /// Bij het starten: het bestand alvast buiten de hoofdthread inlezen, zodat de mailmodus en het aanvullen er niet op
    /// hoeven te wachten. Wie eerder iets nodig heeft, leest het gewoon zelf (`loadIfNeeded`).
    func preload() {
        guard !loaded else { return }
        Task.detached(priority: .utility) {
            let stored = MailActivityStore.readStored()
            await MainActor.run { MailActivityStore.shared.apply(stored) }
        }
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        apply(Self.readStored())
    }

    private nonisolated static func readStored() -> Stored? {
        guard let file = Self.file, let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Stored.self, from: data)
    }

    private func apply(_ stored: Stored?) {
        guard !loaded else { return }
        loaded = true
        guard let stored else { return }
        names = stored.names ?? [:]
        // Van vóór de mailbox per mail werd bewaard: opnieuw ophalen, zodat de klanten per mailbox kloppen.
        guard !stored.records.contains(where: { $0.account == nil }) else { return }
        records = stored.records
        lastSync = stored.lastSync
        coveredFrom = stored.coveredFrom ?? [:]
        ids = Set(records.map(\.id))
    }

    /// Bewaren gebeurt even later en buiten de hoofdthread: het bestand is groot en `add` komt per mailbox langs.
    private func save(after delay: Duration = .seconds(2)) {
        saveTask?.cancel()
        let stored = Stored(records: records, lastSync: lastSync, names: names, coveredFrom: coveredFrom)
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let file = MailActivityStore.file else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            if let data = try? encoder.encode(stored) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    /// Wanneer de mailboxen voor het laatst zijn bijgewerkt (de oudste).
    func lastUpdate(for accounts: [String]) -> Date? {
        let dates = accounts.compactMap { lastSync[$0] }
        return dates.count == accounts.count ? dates.min() : nil
    }

    /// Mails die de mailmodus toch al ophaalde (lijst, zoeken) tellen meteen mee.
    @discardableResult
    func add(_ items: [GmailMailItem], account: String?) -> Bool {
        loadIfNeeded()
        var changed = false
        for item in items where !ids.contains(item.id) {
            if let address = item.fromAddress?.lowercased(),
               let name = item.fromName?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name.lowercased() != address,
               names[address] != name {
                names[address] = name
            }
            guard let record = MailActivityRecord(item, account: account) else { continue }
            records.append(record)
            ids.insert(record.id)
            changed = true
        }
        if changed { save() }
        return changed
    }

    /// Bijwerken als het langer dan een dag geleden is (of nog geen drie maanden terug gaat).
    @discardableResult
    func syncIfStale() async -> Bool {
        loadIfNeeded()
        let gmail = GmailSession.shared
        let now = Date()
        let wanted = now.addingTimeInterval(-Self.historyDays * 86_400 + 86_400)
        let stale = gmail.accounts.contains { account in
            guard let last = lastSync[account], let covered = coveredFrom[account] else { return true }
            return now.timeIntervalSince(last) > Self.refreshInterval || covered > wanted
        }
        return stale ? await sync() : false
    }

    /// Haalt per mailbox op wat er sinds de vorige keer bij kwam, en wat er nog ontbreekt tot drie maanden terug.
    @discardableResult
    func sync() async -> Bool {
        loadIfNeeded()
        let gmail = GmailSession.shared
        guard !isSyncing, gmail.state == .signedIn else { return false }
        isSyncing = true
        defer { isSyncing = false }
        let accounts: [String?] = gmail.accounts.isEmpty ? [gmail.activeAccount] : gmail.accounts.map { $0 }
        let start = Date().addingTimeInterval(-Self.historyDays * 86_400)
        // Per mailbox vooraf bepalen wat er nodig is: wat er sinds de vorige keer bij kwam (met een uur overlap: Gmail
        // zoekt op dagen en mails komen soms iets later binnen), en wat er nog ontbreekt tot drie maanden terug.
        let plans: [(account: String?, since: Date, olderUntil: Date?)] = accounts.map { account in
            let key = account ?? ""
            guard let last = lastSync[key] else { return (account, start, nil) }
            let covered = coveredFrom[key] ?? records.filter { $0.account == account }.map(\.date).min() ?? last
            return (account, last.addingTimeInterval(-3600), covered > start ? covered : nil)
        }
        // De mailboxen tegelijk (Gmail telt per mailbox); bijwerken gebeurt daarna op de hoofdthread.
        let fetched = await withTaskGroup(of: (account: String?, started: Date, items: [GmailMailItem]).self) { group in
            for plan in plans {
                group.addTask {
                    let started = Date()
                    var items = await gmail.activityItems(since: plan.since, account: plan.account, limit: 2000)
                    if let until = plan.olderUntil {
                        items += await gmail.activityItems(since: start, until: until, account: plan.account, limit: 2000)
                    }
                    return (plan.account, started, items)
                }
            }
            var all: [(account: String?, started: Date, items: [GmailMailItem])] = []
            for await result in group { all.append(result) }
            return all
        }
        var changed = false
        for result in fetched {
            if add(result.items, account: result.account) { changed = true }
            lastSync[result.account ?? ""] = result.started
            coveredFrom[result.account ?? ""] = start
        }
        let cutoff = Date().addingTimeInterval(-Self.keepDays * 86_400)
        let before = records.count
        records.removeAll { $0.date < cutoff }
        if records.count != before {
            ids = Set(records.map(\.id))
            changed = true
        }
        save(after: .zero)
        return changed
    }
}
