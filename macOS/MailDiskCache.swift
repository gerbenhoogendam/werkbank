import Foundation
import WerkbankCore

/// Geopende mails op schijf, zodat een mail die je eerder opende er na opnieuw starten meteen staat (en ook zonder
/// internet te lezen is). Per mail de ruwe mail zoals Gmail hem geeft, per gesprek de lijst van zijn mails.
///
/// - Alleen op deze Mac, in de map Caches: die gaat niet mee in Time Machine en macOS mag hem opruimen.
/// - Niet versleuteld, zoals bij Mail van Apple (afgesproken met de eigenaar): de bescherming is je login en FileVault.
/// - Hooguit dertig dagen sinds het laatste openen en hooguit `maxTotal` bij elkaar; een mail groter dan `maxRaw`
///   (grote bijlagen) blijft niet op schijf en wordt bij openen opnieuw opgehaald.
/// - Een mailbox loskoppelen of een gesprek weggooien haalt ook hier weg wat erbij hoort.
///
/// Alles hier leest en schrijft bestanden: aanroepen buiten de hoofdthread.
enum MailDiskCache {
    static let maxAge: TimeInterval = 30 * 24 * 3600
    static let maxTotal = 400 * 1024 * 1024
    static let maxRaw = 4 * 1024 * 1024

    private static var root: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Werkbank", isDirectory: true)
            .appendingPathComponent("Mail", isDirectory: true)
    }

    /// Alleen letters, cijfers en een paar leestekens: een naam kan zo nooit buiten de map uitkomen.
    private static func safe(_ text: String) -> String? {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._-")
        let name = String(text.map { allowed.contains($0) ? $0 : "_" })
        return name.isEmpty || name.allSatisfy({ $0 == "." }) ? nil : name
    }

    private static func folder(_ account: String) -> URL? {
        root?.appendingPathComponent(safe(account) ?? "_", isDirectory: true)
    }

    private static func file(_ name: String, kind: String, account: String) -> URL? {
        guard let name = safe(name) else { return nil }
        return folder(account)?.appendingPathComponent(name + "." + kind)
    }

    private static func read(_ url: URL?) -> Data? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        // Gelezen is gebruikt: zo blijft bij opruimen staan wat je nog opent.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    private static func write(_ data: Data, to url: URL?) {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Mails

    static func raw(id: String, account: String) -> Data? {
        read(file(id, kind: "eml", account: account))
    }

    static func store(raw: Data, id: String, account: String) {
        guard raw.count <= maxRaw else { return }
        write(raw, to: file(id, kind: "eml", account: account))
    }

    // MARK: Gesprekken

    static func thread(id: String, account: String) -> [GmailThreadMessage]? {
        guard let data = read(file(id, kind: "json", account: account)) else { return nil }
        return try? JSONDecoder().decode([GmailThreadMessage].self, from: data)
    }

    /// Zonder "ongelezen": wie het gesprek opent, heeft het gelezen.
    static func store(thread messages: [GmailThreadMessage], id: String, account: String) {
        let read = messages.map { message -> GmailThreadMessage in
            var copy = message
            copy.labels.removeAll { $0 == "UNREAD" }
            return copy
        }
        guard let data = try? JSONEncoder().encode(read) else { return }
        write(data, to: file(id, kind: "json", account: account))
    }

    // MARK: Weghalen

    /// Een gesprek is weggegooid: de lijst en de mails ervan.
    static func remove(thread id: String, account: String) {
        let list = file(id, kind: "json", account: account)
        let messages = list.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([GmailThreadMessage].self, from: $0) } ?? []
        for message in messages {
            if let url = file(message.id, kind: "eml", account: account) { try? FileManager.default.removeItem(at: url) }
        }
        if let list { try? FileManager.default.removeItem(at: list) }
    }

    /// Een mailbox is losgekoppeld.
    static func remove(account: String) {
        if let folder = folder(account) { try? FileManager.default.removeItem(at: folder) }
    }

    /// Wat te oud is weg, en daarna het langst niet geopende tot het geheel onder `maxTotal` zit.
    static func prune() {
        guard let root else { return }
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
        var files: [(url: URL, date: Date, size: Int)] = []
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            files.append((url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0))
        }
        let oldest = Date().addingTimeInterval(-maxAge)
        var total = 0
        var kept: [(url: URL, date: Date, size: Int)] = []
        for file in files {
            if file.date < oldest {
                try? FileManager.default.removeItem(at: file.url)
            } else {
                kept.append(file)
                total += file.size
            }
        }
        for file in kept.sorted(by: { $0.date < $1.date }) {
            guard total > maxTotal else { break }
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
    }
}
