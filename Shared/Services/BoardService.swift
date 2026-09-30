import Foundation
import SwiftData
import UniformTypeIdentifiers
import WerkbankCore

@MainActor
enum BoardService {
    // MARK: Kaarten

    static func allCards(in context: ModelContext) -> [TodoCard] {
        (try? context.fetch(FetchDescriptor<TodoCard>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    /// Nieuwe kaart bovenaan een kolom (standaard de Inbox).
    @discardableResult
    static func addCard(title: String, column: BoardColumn = .inbox, label: String? = nil,
                        logoDomain: String? = nil, sender: String? = nil, body: String? = nil,
                        in context: ModelContext) -> TodoCard {
        let top = allCards(in: context).filter { $0.column == column }.map(\.sortOrder).min() ?? 0
        let card = TodoCard(title: title, clientLabel: label, logoDomain: logoDomain, senderLine: sender,
                            column: column, sortOrder: top - 1, isNew: column == .inbox)
        card.bodyText = body
        context.insert(card)
        try? context.save()
        return card
    }

    /// Snelle invoer: `#woord` wordt het klantlabel.
    @discardableResult
    static func addQuickEntry(_ input: String, column: BoardColumn = .inbox, in context: ModelContext) -> TodoCard? {
        let parsed = QuickEntryParser.parse(input)
        guard !parsed.title.isEmpty else { return nil }
        return addCard(title: parsed.title, column: column, label: parsed.label, in: context)
    }

    /// Verplaatst een kaart naar `column` op positie `index` binnen de andere kaarten van die kolom.
    static func move(_ card: TodoCard, to column: BoardColumn, index: Int, in context: ModelContext) {
        let others = allCards(in: context).filter { $0.column == column && $0.id != card.id }
        let i = min(max(index, 0), others.count)
        let newOrder: Double
        switch (i > 0 ? others[i - 1].sortOrder : nil, i < others.count ? others[i].sortOrder : nil) {
        case let (before?, after?): newOrder = (before + after) / 2
        case let (before?, nil):    newOrder = before + 1
        case let (nil, after?):     newOrder = after - 1
        default:                    newOrder = 0
        }
        card.column = column
        card.sortOrder = newOrder
        if column != .inbox { card.isNew = false }
        try? context.save()
    }

    static func delete(_ card: TodoCard, in context: ModelContext) {
        context.delete(card)
        try? context.save()
    }

    // MARK: Klant en logo

    static func mappingTable(in context: ModelContext) -> [String: String] {
        let mappings = (try? context.fetch(FetchDescriptor<ClientMapping>())) ?? []
        return Dictionary(mappings.map { ($0.domain.lowercased(), $0.client) }, uniquingKeysWith: { _, last in last })
    }

    /// Past label/logo van een kaart aan. Wijzigt de gebruiker het label van een kaart met logodomein,
    /// dan wordt de koppeltabel domein → klant automatisch aangevuld.
    static func update(_ card: TodoCard, title: String, label: String, logoDomain: String, in context: ModelContext) {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty { card.title = newTitle }

        let newLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldLabel = card.clientLabel ?? ""
        card.clientLabel = newLabel.isEmpty ? nil : newLabel

        let domain = logoDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        card.logoDomain = domain.isEmpty ? nil : ClientNaming.registrableDomain(of: domain)

        if !newLabel.isEmpty, newLabel != oldLabel, let mapped = card.logoDomain {
            upsertMapping(domain: mapped, client: newLabel, in: context)
        }
        try? context.save()
    }

    static func upsertMapping(domain: String, client: String, in context: ModelContext) {
        let key = domain.lowercased()
        let existing = (try? context.fetch(FetchDescriptor<ClientMapping>())) ?? []
        if let found = existing.first(where: { $0.domain == key }) {
            found.client = client
        } else {
            context.insert(ClientMapping(domain: key, client: client))
        }
    }

    // MARK: Mail

    @discardableResult
    static func addMail(_ mail: ParsedMail, column: BoardColumn = .inbox, in context: ModelContext) -> TodoCard {
        let resolution = ClientNaming.resolve(displayName: mail.fromName, address: mail.fromAddress,
                                              mapping: mappingTable(in: context))
        return addCard(title: mail.subject, column: column, label: resolution?.name,
                       logoDomain: resolution?.logoDomain, sender: mail.senderLine, body: mail.bodyText, in: context)
    }
}

// MARK: - Mail droppen (.eml)

/// Verwerkt gesleepte of geïmporteerde .eml-bestanden. Wordt door macOS (slepen) en iOS (slepen op iPad,
/// bestandskiezer) gedeeld.
@MainActor
enum MailImporter {
    static let unsupportedMessage = "Alleen .eml-bestanden worden ondersteund."

    static func isEML(_ url: URL) -> Bool { url.pathExtension.lowercased() == "eml" }

    /// - Parameter column: kolom waar de kaarten in komen (bij slepen op een kolom; anders de Inbox).
    /// - Returns: `true` als er iets te verwerken lijkt (voor `onDrop`).
    static func handle(providers: [NSItemProvider], column: BoardColumn = .inbox,
                       context: ModelContext, appState: AppState) -> Bool {
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var imported: [TodoCard] = []
            var unsupported = 0
            for provider in providers {
                if let data = await loadData(provider, type: .emailMessage) {
                    imported.append(BoardService.addMail(EMLParser.parse(data), column: column, in: context))
                } else if let url = await loadFileURL(provider) {
                    if let card = importFile(url, column: column, context: context) { imported.append(card) } else { unsupported += 1 }
                } else {
                    unsupported += 1
                }
            }
            report(imported: imported, unsupported: unsupported, column: column, appState: appState)
        }
        return true
    }

    static func handle(urls: [URL], column: BoardColumn = .inbox, context: ModelContext, appState: AppState) {
        var imported: [TodoCard] = []
        var unsupported = 0
        for url in urls {
            if let card = importFile(url, column: column, context: context) { imported.append(card) } else { unsupported += 1 }
        }
        report(imported: imported, unsupported: unsupported, column: column, appState: appState)
    }

    private static func importFile(_ url: URL, column: BoardColumn, context: ModelContext) -> TodoCard? {
        guard isEML(url) else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return BoardService.addMail(EMLParser.parse(data), column: column, in: context)
    }

    private static func report(imported: [TodoCard], unsupported: Int, column: BoardColumn, appState: AppState) {
        if imported.count == 1, let card = imported.first {
            appState.showToast("Mail van \(card.clientLabel ?? "onbekende afzender") toegevoegd aan \(column.title)")
        } else if imported.count > 1 {
            appState.showToast("\(imported.count) mails toegevoegd aan \(column.title)")
        } else if unsupported > 0 {
            appState.showToast(unsupportedMessage)
        }
        // De titel van een nieuwe mailkaart wil je altijd nakijken: open hem direct om te bewerken
        // (met de mogelijkheid om al bestede tijd in te vullen).
        if let newest = imported.last { InlineEditing.pendingEditID = newest.id }
    }

    private static func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Export

extension TimeEntry {
    var billingLine: BillingLine {
        BillingLine(date: finishedAt ?? createdAt,
                    client: client,
                    title: title,
                    workDescription: workDescription,
                    minutes: Int((accumulated / 60).rounded()),
                    billedHours: Billing.billedHours(seconds: max(0, accumulated - correctionSeconds), unitMinutes: AppSettings.roundingMinutes),
                    source: source.title)
    }
}
