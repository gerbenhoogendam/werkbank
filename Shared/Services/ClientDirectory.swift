import Foundation
import Observation
import SwiftData
import WerkbankCore

/// De klantenlijst: het bestand dat in Voorkeuren is aangewezen, plus alle .csv-bestanden in iCloud Drive/Werkbank.
/// Wordt opnieuw gelezen als een bestand is gewijzigd (bijvoorbeeld aangevuld op een andere Mac).
@MainActor
@Observable
final class ClientDirectory {
    static let shared = ClientDirectory()
    /// Bladwijzer naar het aangewezen bestand (per Mac: een bladwijzer werkt alleen op de Mac die hem maakte).
    static let bookmarkKey = "clients.fileBookmark"

    private(set) var records: [ClientRecord] = []
    /// Domein → klantnaam uit de kolom Domeinnaam (zie `ClientList.domainMap`).
    private(set) var domainMap: [String: String] = [:]
    /// Naam van het aangewezen bestand, voor Voorkeuren.
    private(set) var chosenFileName: String?
    /// Klantnaam (kleine letters) → domein voor het logo: klantenlijst, dan koppeltabel, dan kaarten.
    private(set) var logoDomains: [String: String] = [:]
    /// Klanten met FAILLIET, GEEN KLANT MEER of NIET GEBRUIKEN: komen nergens meer voor, ook niet als ze nog in oude
    /// tijdregels staan.
    @ObservationIgnored private var removedNames: Set<String> = []
    @ObservationIgnored private var stamps: [String: Date] = [:]
    @ObservationIgnored private var isRefreshing = false

    init() {
        chosenFileName = Self.resolveChosenFile()?.lastPathComponent
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await WerkbankFolder.prepare()
        let folder = WerkbankFolder.url
        let chosen = Self.resolveChosenFile()
        chosenFileName = chosen?.lastPathComponent
        defer { rebuildLogoDomains() }   // ook als de lijst niet veranderde: koppeltabel en kaarten wel
        let known = force ? [:] : stamps
        let result = await Task.detached(priority: .utility) { () -> (records: [ClientRecord], stamps: [String: Date])? in
            let fm = FileManager.default
            var csvs: [URL] = []
            if let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) {
                for file in files {
                    let name = file.lastPathComponent
                    if file.pathExtension.lowercased() == "csv" {
                        csvs.append(file)
                    } else if name.hasPrefix("."), name.lowercased().hasSuffix(".csv.icloud") {
                        // Staat nog alleen in iCloud: ophalen, de volgende keer is hij er.
                        let real = folder.appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
                        try? fm.startDownloadingUbiquitousItem(at: real)
                    }
                }
            }
            csvs.sort { $0.lastPathComponent < $1.lastPathComponent }
            if let chosen, !csvs.contains(chosen) { csvs.insert(chosen, at: 0) }

            var stamps: [String: Date] = [:]
            for file in csvs {
                let access = file == chosen && file.startAccessingSecurityScopedResource()
                stamps[file.path] = CloudFile.modificationDate(file) ?? .distantPast
                if access { file.stopAccessingSecurityScopedResource() }
            }
            guard stamps != known else { return nil }   // niets veranderd

            var seen = Set<String>()
            var records: [ClientRecord] = []
            for file in csvs {
                let access = file == chosen && file.startAccessingSecurityScopedResource()
                defer { if access { file.stopAccessingSecurityScopedResource() } }
                guard let data = CloudFile.read(file), let text = CloudFile.text(data) else { continue }
                for record in ClientList.parseCSV(text) where seen.insert(record.name.lowercased()).inserted {
                    records.append(record)
                }
            }
            return (records, stamps)
        }.value
        guard let result else { return }
        records = result.records.filter { !$0.isInactive }
        removedNames = Set(result.records.filter(\.isInactive).map { $0.name.lowercased() })
        domainMap = ClientList.domainMap(records)
        stamps = result.stamps
    }

    /// Domein voor het logo van een klant, als dat bekend is.
    func logoDomain(for name: String) -> String? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.isEmpty ? nil : logoDomains[key]
    }

    private func rebuildLogoDomains() {
        let context = Persistence.container.mainContext
        var map: [String: String] = [:]
        for card in BoardService.allCards(in: context) {
            if let label = card.clientLabel, let domain = card.logoDomain { map[label.lowercased()] = domain }
        }
        for mapping in (try? context.fetch(FetchDescriptor<ClientMapping>())) ?? []
        where !ClientNaming.freemailDomains.contains(mapping.domain.lowercased()) {
            map[mapping.client.lowercased()] = mapping.domain.lowercased()
        }
        for record in records {
            if let domain = record.domains.first(where: { !ClientNaming.freemailDomains.contains($0) }) {
                map[record.name.lowercased()] = domain
            }
        }
        if map != logoDomains { logoDomains = map }
    }

    /// Treffers uit de lijst, aangevuld met klantnamen die al in Werkbank voorkomen.
    func suggestions(for query: String, known: [String], limit: Int = 6) -> [ClientRecord] {
        var all = records
        let listed = Set(records.map { $0.name.lowercased() })
        for name in known where !listed.contains(name.lowercased()) && !removedNames.contains(name.lowercased()) {
            all.append(ClientRecord(name: name))
        }
        return ClientList.search(query, in: all, limit: limit)
    }

    // MARK: Aangewezen bestand

    /// Bewaart het gekozen bestand (uit een bestandskiezer) als bladwijzer en leest het in.
    func choose(_ url: URL) async {
        #if os(macOS)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        }
        #endif
        await refresh(force: true)
    }

    func forgetChosenFile() async {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        await refresh(force: true)
    }

    private static func resolveChosenFile() -> URL? {
        #if os(macOS)
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        if stale, url.startAccessingSecurityScopedResource() {
            // Verplaatst of hernoemd: de bladwijzer vernieuwen.
            if let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                 relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
            url.stopAccessingSecurityScopedResource()
        }
        return url
        #else
        return nil
        #endif
    }
}
