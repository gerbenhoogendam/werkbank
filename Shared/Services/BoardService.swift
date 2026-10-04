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
        let column = resolve(column, in: context)
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

    // MARK: Archief (afgeronde taken)

    /// Rondt een taak af: hij verdwijnt van het board en staat in het archief.
    static func complete(_ card: TodoCard, in context: ModelContext) {
        card.columnRaw = BoardColumn.doneID
        card.completedAt = .now
        card.isNew = false
        try? context.save()
    }

    /// Zet een afgeronde taak terug bovenaan de Inbox (of de eerste kolom).
    static func reopen(_ card: TodoCard, in context: ModelContext) {
        card.completedAt = nil
        move(card, to: resolve(.inbox, in: context), index: 0, in: context)
    }

    static func delete(_ card: TodoCard, in context: ModelContext) {
        for subtask in subtasks(of: card, in: context) { context.delete(subtask) }
        context.delete(card)
        try? context.save()
    }

    // MARK: Subtaken

    static func subtasks(of card: TodoCard, in context: ModelContext) -> [Subtask] {
        let id = card.id
        let descriptor = FetchDescriptor<Subtask>(predicate: #Predicate { $0.cardID == id },
                                                  sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Nieuwe subtaak onderaan; een lege titel geeft `nil`.
    @discardableResult
    static func addSubtask(to card: TodoCard, title: String, in context: ModelContext) -> Subtask? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let last = subtasks(of: card, in: context).map(\.sortOrder).max() ?? -1
        let subtask = Subtask(cardID: card.id, title: name, sortOrder: last + 1)
        context.insert(subtask)
        try? context.save()
        return subtask
    }

    static func toggle(_ subtask: Subtask, in context: ModelContext) {
        subtask.isDone.toggle()
        try? context.save()
    }

    static func delete(_ subtask: Subtask, in context: ModelContext) {
        context.delete(subtask)
        try? context.save()
    }

    // MARK: Kolommen

    /// De standaardkolommen. De sleutels zijn vast, zodat kaarten uit oudere versies er direct aan blijven hangen
    /// en twee apparaten dezelfde kolommen aanmaken (dubbelen worden opgeruimd).
    private static let defaultColumns: [(key: String, title: String, symbol: String)] = [
        (BoardColumn.inboxID, "Inbox", "tray.fill"),
        ("todo", "Te doen", "square.stack.3d.up.fill"),
        ("doing", "Bezig", "star.fill"),
        ("waiting", "Wacht op klant", "hourglass"),
    ]

    static func columnRecords(in context: ModelContext) -> [ColumnRecord] {
        (try? context.fetch(FetchDescriptor<ColumnRecord>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]))) ?? []
    }

    static func columns(in context: ModelContext) -> [BoardColumn] {
        columnRecords(in: context).map(\.column)
    }

    /// Zorgt dat er kolommen zijn: maakt de standaardkolommen aan op een lege database, ruimt dubbele kolommen
    /// (zelfde sleutel) op en zet kaarten waarvan de kolom niet meer bestaat in de eerste kolom.
    static func ensureColumns(in context: ModelContext) {
        var kept: [ColumnRecord] = []
        var seen = Set<String>()
        for record in columnRecords(in: context).sorted(by: { $0.createdAt < $1.createdAt }) {
            if seen.insert(record.key).inserted { kept.append(record) } else { context.delete(record) }
        }
        // "Klaar" is geen kolom meer maar het archief: de oude kolom verdwijnt, de kaarten erin blijven staan
        // (columnRaw "done") en zijn nu afgeronde taken.
        for record in kept where record.key == BoardColumn.doneID { context.delete(record) }
        var records = kept.filter { $0.key != BoardColumn.doneID }.sorted { $0.sortOrder < $1.sortOrder }

        if records.isEmpty {
            for (index, column) in defaultColumns.enumerated() {
                let record = ColumnRecord(key: column.key, title: column.title, sortOrder: Double(index),
                                          colorIndex: index, symbol: column.symbol)
                context.insert(record)
                records.append(record)
            }
        }

        let keys = Set(records.map(\.key))
        if let first = records.first {
            for card in allCards(in: context) where !keys.contains(card.columnRaw) && card.columnRaw != BoardColumn.doneID {
                card.columnRaw = first.key
            }
        }
        try? context.save()
    }

    /// De kolom zelf als die bestaat; anders de eerste kolom (bijv. als de Inbox is verwijderd).
    static func resolve(_ column: BoardColumn, in context: ModelContext) -> BoardColumn {
        let all = columns(in: context)
        if all.contains(column) { return column }
        return all.first ?? column
    }

    /// Actuele naam van een kolom (de waarde die views doorgeven kan een verouderde titel hebben).
    static func title(of column: BoardColumn, in context: ModelContext) -> String {
        columns(in: context).first { $0 == column }?.title ?? column.title
    }

    /// Nieuwe kolom aan de rechterkant.
    @discardableResult
    static func addColumn(title: String, in context: ModelContext) -> ColumnRecord? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let records = columnRecords(in: context)
        let record = ColumnRecord(key: UUID().uuidString, title: name,
                                  sortOrder: (records.map(\.sortOrder).max() ?? -1) + 1,
                                  colorIndex: records.count)
        context.insert(record)
        try? context.save()
        return record
    }

    static func renameColumn(_ record: ColumnRecord, to title: String, in context: ModelContext) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        record.title = name
        try? context.save()
    }

    /// Icoon (SF Symbol-naam of emoji) van een kolom.
    static func setIcon(_ record: ColumnRecord, symbol: String, in context: ModelContext) {
        guard !symbol.isEmpty else { return }
        record.symbol = symbol
        try? context.save()
    }

    static func setColor(_ record: ColumnRecord, index: Int, in context: ModelContext) {
        record.colorIndex = index
        try? context.save()
    }

    /// Zet een kolom op positie `index` onder de overige kolommen en nummert de volgorde opnieuw.
    static func moveColumn(key: String, toIndex index: Int, in context: ModelContext) {
        let records = columnRecords(in: context)
        let order = ColumnOrdering.moving(records.map(\.key), key: key, toIndex: index)
        guard order != records.map(\.key) else { return }
        for (position, key) in order.enumerated() {
            records.first { $0.key == key }?.sortOrder = Double(position)
        }
        try? context.save()
    }

    /// Verwijdert een kolom; de kaarten gaan onderaan de eerste andere kolom. De laatste kolom blijft altijd staan.
    /// - Returns: de kolom waar de kaarten heen zijn gegaan en hoeveel het er waren, of `nil` als verwijderen niet kan.
    @discardableResult
    static func deleteColumn(_ record: ColumnRecord, in context: ModelContext) -> (destination: String, moved: Int)? {
        let others = columnRecords(in: context).filter { $0.key != record.key }
        guard let destination = others.first else { return nil }

        let cards = allCards(in: context)
        var next = (cards.filter { $0.columnRaw == destination.key }.map(\.sortOrder).max() ?? -1) + 1
        let moving = cards.filter { $0.columnRaw == record.key }.sorted { $0.sortOrder < $1.sortOrder }
        for card in moving {
            card.columnRaw = destination.key
            card.sortOrder = next
            next += 1
            if destination.key != BoardColumn.inboxID { card.isNew = false }
        }
        context.delete(record)
        try? context.save()
        return (destination.title, moving.count)
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
            report(imported: imported, unsupported: unsupported, column: column, context: context, appState: appState)
        }
        return true
    }

    static func handle(urls: [URL], column: BoardColumn = .inbox, context: ModelContext, appState: AppState) {
        var imported: [TodoCard] = []
        var unsupported = 0
        for url in urls {
            if let card = importFile(url, column: column, context: context) { imported.append(card) } else { unsupported += 1 }
        }
        report(imported: imported, unsupported: unsupported, column: column, context: context, appState: appState)
    }

    private static func importFile(_ url: URL, column: BoardColumn, context: ModelContext) -> TodoCard? {
        guard isEML(url) else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return BoardService.addMail(EMLParser.parse(data), column: column, in: context)
    }

    private static func report(imported: [TodoCard], unsupported: Int, column: BoardColumn,
                               context: ModelContext, appState: AppState) {
        let columnTitle = BoardService.title(of: BoardService.resolve(column, in: context), in: context)
        if imported.count == 1, let card = imported.first {
            appState.showToast("Mail van \(card.clientLabel ?? "onbekende afzender") toegevoegd aan \(columnTitle)")
        } else if imported.count > 1 {
            appState.showToast("\(imported.count) mails toegevoegd aan \(columnTitle)")
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
