import Foundation

/// De map Werkbank in iCloud Drive (de Documents-map van de iCloud-container van de app). Daar staan de voorkeuren
/// voor andere Macs, het geheugen van Claude en de klantenlijst (.csv). Zonder iCloud: een lokale map.
@MainActor
enum WerkbankFolder {
    private(set) static var iCloud: URL?
    private(set) static var isReady = false

    static let local: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Werkbank", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var url: URL { iCloud ?? local }

    /// Zoekt de iCloud-map op (niet op de hoofdthread: dat kan even duren). Daarna is `url` definitief.
    static func prepare() async {
        guard !isReady else { return }
        iCloud = await Task.detached(priority: .utility) { () -> URL? in
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            return documents
        }.value
        isReady = true
    }
}

/// Lezen en schrijven in iCloud Drive met coördinatie, zodat iCloud niet halverwege een bestand vervangt.
/// Niet op de hoofdthread aanroepen: een bestand dat nog niet op deze Mac staat, wordt eerst opgehaald.
enum CloudFile {
    static func read(_ url: URL) -> Data? {
        let fm = FileManager.default
        try? fm.startDownloadingUbiquitousItem(at: url)
        guard fm.fileExists(atPath: url.path) else { return nil }
        var result: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { url in
            result = try? Data(contentsOf: url)
        }
        return result
    }

    @discardableResult
    static func write(_ data: Data, to url: URL) -> Bool {
        var ok = false
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { url in
            ok = (try? data.write(to: url, options: .atomic)) != nil
        }
        return ok
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Tekst uit een bestand van Excel of Numbers: UTF-8, anders Windows- of Mac-codering.
    static func text(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .macOSRoman)
    }
}
