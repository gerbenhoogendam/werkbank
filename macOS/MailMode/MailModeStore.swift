import Foundation
import Observation
import SwiftData
import WerkbankCore

/// De mailmodus: het hele venster als mailclient. Bereik (één mailbox, de combinatie of alle mail), zoeken met filters,
/// de lijst met de bundel nieuwsbrieven en meldingen, de gekozen mail en rechts de klanten op volgorde van contact.
/// Elke handeling eindigt in archiveren; mappen spelen geen rol.
@MainActor
@Observable
final class MailModeStore {
    static let shared = MailModeStore()

    enum Scope: Hashable {
        case account(String)
        case combination([String])
        case all
    }

    enum Filter: String, CaseIterable, Identifiable {
        case attachment, unread, noTask
        var id: String { rawValue }
        var title: String {
            switch self {
            case .attachment: "Met bijlage"
            case .unread: "Ongelezen"
            case .noTask: "Zonder taak"
            }
        }
    }

    struct Section: Identifiable {
        let id: String
        let items: [GmailMailItem]
    }

    private(set) var isActive = false
    private(set) var scope: Scope = .all
    private(set) var query = ""
    private(set) var filters: Set<Filter> = []
    /// Alle mail van één klant, uit alle mailboxen.
    private(set) var client: String?
    private(set) var items: [GmailMailItem] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    var selectedID: String?
    var bundleOpen = false
    var clientQuery = ""
    private(set) var ranking: [ClientActivity.Rank] = []
    /// Gesprekken waar een kaart bij hoort (voor "Zonder taak" en het label in de lijst).
    private(set) var taskThreadIDs: Set<String> = []
    /// Telt op bij `/`: het zoekveld krijgt dan de focus.
    private(set) var searchFocusRequest = 0
    /// Het gesprek rechts opent een antwoord (toets R, of het Claude-concept).
    let replyTrigger = MailReplyTrigger()

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var loadToken = 0
    private let gmail = GmailSession.shared

    // MARK: Openen en sluiten

    /// Opent de mailmodus in het bereik van het Mail-paneel; `message` wordt de gekozen mail.
    func open(selecting message: GmailMessageSummary? = nil) {
        if gmail.isAllCombined {
            scope = .all
        } else if gmail.isCombined {
            scope = .combination(gmail.combinedAccounts)
        } else if let active = gmail.activeAccount {
            scope = .account(active)
        } else {
            scope = .all
        }
        client = nil
        selectedID = message?.id
        isActive = true
        Task {
            await reload()
            await refreshClients()
        }
    }

    func close() {
        isActive = false
        searchTask?.cancel()
    }

    // MARK: Bereik, zoeken en filters

    /// Elke mailbox, de combinatie uit het Mail-paneel (als die er is) en alle mail.
    var scopes: [Scope] {
        let accounts = gmail.accounts
        var list: [Scope] = accounts.map { .account($0) }
        if gmail.isCombined, !gmail.isAllCombined { list.append(.combination(gmail.combinedAccounts)) }
        if accounts.count != 1 { list.append(.all) }
        return list
    }

    func title(of scope: Scope) -> String {
        switch scope {
        case .account(let email): gmail.displayName(email)
        case .combination(let emails): emails.map(gmail.displayName).joined(separator: " + ")
        case .all: "Alle mail"
        }
    }

    private func accounts(of scope: Scope) -> [String?] {
        switch scope {
        case .account(let email): [email]
        case .combination(let emails): emails.map { $0 }
        case .all: gmail.accounts.isEmpty ? [gmail.activeAccount] : gmail.accounts.map { $0 }
        }
    }

    /// Meer dan één mailbox in de lijst: dan staat bij elke mail uit welke.
    var showsAccounts: Bool { client != nil || accounts(of: scope).count > 1 }

    func select(scope newScope: Scope) {
        scope = newScope
        client = nil
        selectedID = nil
        Task { await reload() }
    }

    /// Tab: de volgende mailbox, de combinatie, alle mail en weer van voren af.
    func cycleScope() {
        let list = scopes
        guard !list.isEmpty else { return }
        let index = list.firstIndex(of: scope) ?? -1
        select(scope: list[(index + 1) % list.count])
    }

    func setQuery(_ text: String) {
        query = text
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            selectedID = nil
            await reload()
        }
    }

    func requestSearchFocus() { searchFocusRequest += 1 }

    func toggle(_ filter: Filter) {
        if filters.contains(filter) { filters.remove(filter) } else { filters.insert(filter) }
        selectedID = nil
        if filter != .noTask { Task { await reload() } }
    }

    func showClient(_ name: String?) {
        client = client == name ? nil : name
        selectedID = nil
        Task { await reload() }
    }

    var isFiltering: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty || client != nil || !filters.isEmpty }

    // MARK: Lijst

    func reload() async {
        guard gmail.state == .signedIn else { return }
        loadToken += 1
        let token = loadToken
        isLoading = true
        let domains = client.map(clientDomains) ?? []
        if client != nil, domains.isEmpty {
            items = []
            isLoading = false
            loadError = "Bij deze klant staat geen domein in de klantenlijst."
            return
        }
        let q = MailSearch.query(text: query, attachment: filters.contains(.attachment), unread: filters.contains(.unread),
                                 clientDomains: domains)
        let targets = accounts(of: client != nil ? .all : scope)
        var found: [GmailMailItem] = []
        var failure: String?
        for account in targets {
            do {
                found += try await gmail.mailItems(query: q, account: account)
            } catch {
                failure = failure ?? error.localizedDescription
            }
        }
        guard token == loadToken else { return }
        var seen = Set<String>()
        items = found.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .filter { seen.insert($0.threadID).inserted }
        loadError = items.isEmpty ? failure : nil
        refreshTaskThreads()
        isLoading = false
        if selected == nil { selectedID = listed.first?.id }
        if MailActivityStore.shared.add(found) { refreshRanking() }
    }

    private func refreshTaskThreads() {
        taskThreadIDs = Set(BoardService.allCards(in: Persistence.container.mainContext).compactMap(\.mailThreadID))
    }

    private func clientDomains(_ name: String) -> [String] {
        ClientDirectory.shared.records.first { $0.name == name }?.domains ?? []
    }

    /// De klant bij een mail: de afzender, of bij verzonden mail de eerste ontvanger die een klant is.
    func clientName(for item: GmailMailItem) -> String? {
        let map = ClientDirectory.shared.domainMap
        let own = gmail.ownAddresses
        for address in item.addresses where !own.contains(address) {
            if let name = ClientActivity.client(forAddress: address, domainMap: map) { return name }
        }
        return nil
    }

    func kind(of item: GmailMailItem) -> MailKind {
        item.kind(isKnownClient: clientName(for: item) != nil)
    }

    func hasTask(_ item: GmailMailItem) -> Bool { taskThreadIDs.contains(item.threadID) }

    /// Wat de filters overlaten (zonder de bundel eruit te halen).
    private var filtered: [GmailMailItem] {
        filters.contains(.noTask) ? items.filter { !hasTask($0) } : items
    }

    /// Nieuwsbrieven en meldingen; alleen als er niet gezocht of gefilterd wordt.
    var bundle: [GmailMailItem] {
        isFiltering ? [] : filtered.filter { kind(of: $0) != .person }
    }

    /// De mails in de lijst, in volgorde: zonder zoeken en filters staat de bundel apart (tenzij opengeklapt).
    var listed: [GmailMailItem] {
        if isFiltering || bundleOpen { return filtered }
        return filtered.filter { kind(of: $0) == .person }
    }

    var sections: [Section] {
        let calendar = Calendar.current
        let now = Date()
        func label(_ date: Date?) -> String {
            guard let date else { return "Eerder" }
            if calendar.isDateInToday(date) { return "Vandaag" }
            if calendar.isDateInYesterday(date) { return "Gisteren" }
            if let week = calendar.dateInterval(of: .weekOfYear, for: now), week.contains(date) { return "Deze week" }
            return "Eerder"
        }
        var result: [Section] = []
        for item in listed {
            let name = label(item.date)
            if result.last?.id == name {
                result[result.count - 1] = Section(id: name, items: result[result.count - 1].items + [item])
            } else {
                result.append(Section(id: name, items: [item]))
            }
        }
        return result
    }

    // MARK: Gekozen mail

    var selected: GmailMailItem? {
        guard let selectedID else { return nil }
        return items.first { $0.id == selectedID }
    }

    func select(_ item: GmailMailItem) {
        selectedID = item.id
    }

    func selectNext() { step(1) }
    func selectPrevious() { step(-1) }

    private func step(_ delta: Int) {
        let order = listed
        guard !order.isEmpty else { return }
        guard let current = order.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = order.first?.id
            return
        }
        let next = min(max(current + delta, 0), order.count - 1)
        selectedID = order[next].id
    }

    /// Haalt een gesprek uit de lijst en kiest de mail die er nu staat (de volgende, of de laatste).
    func remove(threadID: String) {
        let order = listed
        let index = order.firstIndex { $0.threadID == threadID }
        items.removeAll { $0.threadID == threadID }
        guard selected == nil else { return }
        let rest = listed
        if let index, !rest.isEmpty {
            selectedID = rest[min(index, rest.count - 1)].id
        } else {
            selectedID = rest.first?.id
        }
    }

    /// Archiveert het gekozen gesprek en opent de volgende mail.
    func archiveSelected(appState: AppState) {
        guard let item = selected else { return }
        remove(threadID: item.threadID)
        Task { await gmail.archiveMessage(item.summary, appState: appState) }
    }

    /// Na versturen in de mailmodus: het gesprek archiveren en de volgende mail openen (de melding komt van het versturen).
    func archiveAfterSending(threadID: String, appState: AppState) {
        guard let item = items.first(where: { $0.threadID == threadID }) else { return }
        remove(threadID: threadID)
        Task { await gmail.archiveMessage(item.summary, appState: appState, announce: false) }
    }

    // MARK: Klanten

    /// De klanten in de lijst rechts: op volgorde van contact; met een zoekterm alle klanten uit de klantenlijst die
    /// erbij passen, ook zonder mail in de laatste dertig dagen.
    var clientRows: [ClientActivity.Rank] {
        let term = clientQuery.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return ranking }
        let byName = Dictionary(ranking.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return ClientList.search(term, in: ClientDirectory.shared.records, limit: 40).map { record in
            byName[record.name] ?? ClientActivity.Rank(name: record.name, count: 0, weeks: [0, 0, 0, 0], lastContact: .distantPast)
        }
    }

    func refreshClients() async {
        await ClientDirectory.shared.refresh()
        refreshRanking()
        if await MailActivityStore.shared.sync() { refreshRanking() }
    }

    func refreshRanking() {
        ranking = ClientActivity.ranking(records: MailActivityStore.shared.records, domainMap: ClientDirectory.shared.domainMap,
                                         ownAddresses: gmail.ownAddresses, now: .now)
    }
}

/// Vraagt het gesprek in de mailmodus een antwoord te openen (toets R), eventueel met tekst erin (Claude-concept).
@MainActor
@Observable
final class MailReplyTrigger {
    struct Request: Equatable {
        let id = UUID()
        var mode: ComposeRef.Mode
        var text: String?
    }

    private(set) var request: Request?

    func reply(_ mode: ComposeRef.Mode = .replyAll, text: String? = nil) {
        request = Request(mode: mode, text: text)
    }
}
