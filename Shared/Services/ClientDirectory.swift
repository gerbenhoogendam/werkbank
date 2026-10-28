import Foundation
import Observation
import SwiftData
import WerkbankCore

/// De klantenlijst van Werkbank (`Client` in de database, via iCloud op al je apparaten): ingelezen uit een .csv en in
/// de app aangevuld. Voor de suggesties bij het klantveld, de logo's en het herkennen van de klant bij een mail.
@MainActor
@Observable
final class ClientDirectory {
    static let shared = ClientDirectory()
    /// Bladwijzer naar het .csv-bestand dat vroeger in Voorkeuren was aangewezen (alleen nog voor het overnemen).
    static let bookmarkKey = "clients.fileBookmark"
    /// De .csv-bestanden die de app vroeger las, zijn één keer overgenomen.
    private static let migratedKey = "clients.filesImported"

    private(set) var records: [ClientRecord] = []
    /// Domein → klantnaam (zie `ClientList.domainMap`).
    private(set) var domainMap: [String: String] = [:]
    /// Klantnaam (kleine letters) → domein voor het logo: klantenlijst, dan koppeltabel, dan kaarten.
    private(set) var logoDomains: [String: String] = [:]
    /// Klanten met FAILLIET, GEEN KLANT MEER of NIET GEBRUIKEN: komen nergens meer voor, ook niet als ze nog in oude
    /// tijdregels staan.
    @ObservationIgnored private var removedNames: Set<String> = []
    /// Domeinen waarvan het logo al is opgehaald of wordt opgehaald (in deze sessie).
    @ObservationIgnored private var prefetched: Set<String> = []

    struct ImportResult {
        var added = 0
        var updated = 0
        var removed = 0
    }

    /// Leest de lijst uit de database (snel genoeg om bij elke weergave van het klantveld te doen) en voegt dubbelen
    /// samen, bijvoorbeeld als twee Macs dezelfde lijst tegelijk inlazen.
    func refresh() async {
        let context = Persistence.container.mainContext
        await importOldFilesIfNeeded()
        let all = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        let clients = Self.merged(all, in: context)
        records = clients.filter { !$0.isRemoved }
            .map { ClientRecord(name: $0.name, details: $0.details, domains: $0.domains) }
        removedNames = Set(clients.filter(\.isRemoved).map { $0.name.lowercased() })
        domainMap = ClientList.domainMap(records)
        rebuildLogoDomains()
        prefetchLogos()
    }

    // MARK: Inlezen en aanpassen

    /// Leest een .csv in. Nieuwe klanten komen erbij; een klant die er al is (zelfde naam) krijgt de nieuwe domeinen
    /// erbij. Failliet, geen klant meer en niet gebruiken: verborgen. Van e-mailadressen blijft alleen het eigen
    /// domein over.
    @discardableResult
    func importCSV(_ text: String) async -> ImportResult {
        let result = await merge(text)
        await refresh()
        return result
    }

    private func merge(_ text: String) async -> ImportResult {
        let parsed = await Task.detached(priority: .userInitiated) { ClientList.parseCSV(text) }.value
        let context = Persistence.container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        var byKey = Dictionary(existing.map { (ClientList.key($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        var result = ImportResult()
        for record in parsed {
            let key = ClientList.key(record.name)
            if let client = byKey[key] {
                let extra = record.domains.filter { !client.domains.contains($0) }
                if !extra.isEmpty {
                    client.domains += extra
                    result.updated += 1
                }
                if record.isInactive, !client.isRemoved {
                    client.isRemoved = true
                    result.removed += 1
                }
            } else {
                let client = Client(name: record.name, domains: record.domains, details: record.details,
                                    isRemoved: record.isInactive)
                context.insert(client)
                byKey[key] = client
                if record.isInactive { result.removed += 1 } else { result.added += 1 }
            }
        }
        try? context.save()
        return result
    }

    /// Een klant zelf toevoegen; `domain` mag ook een website of e-mailadres zijn (freemail telt niet). Geeft false
    /// als de klant er al is.
    @discardableResult
    func add(name: String, domain: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let context = Persistence.container.mainContext
        let key = ClientList.key(trimmed)
        let existing = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        if let match = existing.first(where: { ClientList.key($0.name) == key }) {
            guard match.isRemoved else { return false }
            // Was weggehaald: weer terug.
            match.isRemoved = false
            match.domains = ClientList.customDomains(in: domain)
        } else {
            context.insert(Client(name: trimmed, domains: ClientList.customDomains(in: domain)))
        }
        try? context.save()
        await refresh()
        return true
    }

    /// Naam of domeinen van een klant aangepast (Voorkeuren › Klanten).
    func update(_ client: Client, name: String, domains: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { client.name = trimmed }
        client.domains = ClientList.customDomains(in: domains)
        try? Persistence.container.mainContext.save()
        await refresh()
    }

    func delete(_ client: Client) async {
        let context = Persistence.container.mainContext
        context.delete(client)
        try? context.save()
        await refresh()
    }

    /// Dezelfde klant meer dan eens: samenvoegen tot de oudste, met alle domeinen.
    private static func merged(_ clients: [Client], in context: ModelContext) -> [Client] {
        var kept: [String: Client] = [:]
        var changed = false
        for client in clients.sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = ClientList.key(client.name)
            if let first = kept[key] {
                first.domains += client.domains.filter { !first.domains.contains($0) }
                if client.isRemoved { first.isRemoved = true }
                context.delete(client)
                changed = true
            } else {
                kept[key] = client
            }
        }
        if changed { try? context.save() }
        return Array(kept.values)
    }

    // MARK: Logo's

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

    /// De logo's van alle klanten alvast ophalen (van de website, anders het favicon), zodat de suggesties bij het
    /// typen meteen een logo hebben. Alleen op de Mac; op de iPhone komt een logo pas als het in beeld is.
    private func prefetchLogos() {
        #if os(macOS)
        let domains = Set(records.compactMap(\.domains.first)).subtracting(prefetched)
        guard !domains.isEmpty else { return }
        prefetched.formUnion(domains)
        Task.detached(priority: .background) {
            await LogoService.shared.prefetch(Array(domains))
        }
        #endif
    }

    // MARK: Suggesties

    /// Treffers uit de lijst, aangevuld met klantnamen die al in Werkbank voorkomen.
    func suggestions(for query: String, known: [String], limit: Int = 6) -> [ClientRecord] {
        var all = records
        let listed = Set(records.map { $0.name.lowercased() })
        for name in known where !listed.contains(name.lowercased()) && !removedNames.contains(name.lowercased()) {
            all.append(ClientRecord(name: name))
        }
        return ClientList.search(query, in: all, limit: limit)
    }

    // MARK: Overnemen van vroeger

    /// Eén keer: de .csv-bestanden die de app vroeger las (iCloud Drive/Werkbank en het in Voorkeuren aangewezen
    /// bestand) komen in de lijst. Daarna is de lijst in de app de bron.
    private func importOldFilesIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.migratedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.migratedKey)
        await WerkbankFolder.prepare()
        let folder = WerkbankFolder.url
        let chosen = Self.resolveChosenFile()
        let texts = await Task.detached(priority: .utility) { () -> [String] in
            var files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension.lowercased() == "csv" } ?? []
            if let chosen, !files.contains(chosen) { files.insert(chosen, at: 0) }
            return files.compactMap { file in
                let access = file == chosen && file.startAccessingSecurityScopedResource()
                defer { if access { file.stopAccessingSecurityScopedResource() } }
                return CloudFile.read(file).flatMap(CloudFile.text)
            }
        }.value
        for text in texts { _ = await merge(text) }
    }

    private static func resolveChosenFile() -> URL? {
        #if os(macOS)
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                        bookmarkDataIsStale: &stale)
        #else
        return nil
        #endif
    }
}
