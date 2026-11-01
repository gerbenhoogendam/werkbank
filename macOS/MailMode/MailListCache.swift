import Foundation
import WerkbankCore

/// De lijsten van de mailmodus van de vorige keer (per mailbox, map, zoekopdracht en filters), zodat de mailmodus meteen
/// iets laat zien terwijl Gmail wordt bijgewerkt. In het geheugen, en de laatste twaalf in Application Support (alleen op
/// deze Mac); bewaren gebeurt even later en buiten de hoofdthread.
@MainActor
final class MailListCache {
    static let shared = MailListCache()

    private struct Stored: Codable {
        var order: [String]
        var lists: [String: [GmailMailItem]]
    }

    private var lists: [String: [GmailMailItem]] = [:]
    /// Oudste eerst.
    private var order: [String] = []
    private var loaded = false
    private var saveTask: Task<Void, Never>?
    private static let limit = 12

    func items(for key: String) -> [GmailMailItem]? {
        loadIfNeeded()
        return lists[key]
    }

    func store(_ items: [GmailMailItem], for key: String) {
        loadIfNeeded()
        lists[key] = items
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.limit { lists[order.removeFirst()] = nil }
        scheduleSave()
    }

    /// Een gesprek is gearchiveerd: ook uit wat bewaard is, anders staat het er de volgende keer weer even.
    func remove(threadID: String) {
        loadIfNeeded()
        var changed = false
        for key in Array(lists.keys) {
            let before = lists[key]?.count ?? 0
            lists[key]?.removeAll { $0.threadID == threadID }
            if (lists[key]?.count ?? 0) != before { changed = true }
        }
        if changed { scheduleSave() }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let file = Self.file, let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        lists = stored.lists
        order = stored.order.filter { stored.lists[$0] != nil }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let stored = Stored(order: order, lists: lists)
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let file = MailListCache.file,
                  let data = try? JSONEncoder().encode(stored) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }

    private nonisolated static var file: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("Werkbank", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("MailModeLists.json")
    }
}
