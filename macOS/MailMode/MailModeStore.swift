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
        case attachment, unread, noTask, waiting
        var id: String { rawValue }
        var title: String {
            switch self {
            case .attachment: "Met bijlage"
            case .unread: "Ongelezen"
            case .noTask: "Zonder taak"
            case .waiting: "Wacht op antwoord"
            }
        }
    }

    struct Section: Identifiable {
        let id: String
        let items: [GmailMailItem]
    }

    private(set) var isActive = false
    private(set) var scope: Scope = .all
    /// De map uit de kolom links (Postvak IN, Verstuurd, een label …); een klant gaat erboven.
    private(set) var folder: MailFolder = .inbox
    /// De eigen labels per mailbox, als boom.
    private(set) var labelsByAccount: [String: [GmailLabel]] = [:]
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
    /// Het blad dat open staat (taak, tijd, inplannen, opvolgen, concept).
    private(set) var sheet: MailModeSheet?
    /// Datums en tijden in een mail (zonder het geciteerde deel), per mail.
    private(set) var proposalsByID: [String: [DateProposal]] = [:]
    /// Het laatste uitgebreide zoeken (⌘F), om het zoekvenster weer mee te openen.
    private(set) var searchForm = MailSearchForm()
    /// Uitgebreid zoeken in een eigen keuze van mailboxen (nil: het gekozen bereik).
    private(set) var searchAccounts: [String]?
    /// Afzenders, domeinen en soorten mail die nooit mee gaan bij archiveren in één keer (gaat mee naar je andere Macs).
    private(set) var bulkRules: [BulkRule] = MailBulk.decode(UserDefaults.standard.data(forKey: MailModeStore.bulkRulesKey))
    static let bulkRulesKey = "mailMode.bulkRules"

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
        folder = .inbox
        selectedID = message?.id
        isActive = true
        Task {
            await reload()
            await refreshLabels()
            await refreshClients()
        }
    }

    func close() {
        isActive = false
        sheet = nil
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
    var showsAccounts: Bool { client != nil || (folder.account == nil && accounts(of: scope).count > 1) }

    /// De mailboxen van het bereik, voor hun labels in de kolom met mappen.
    var scopeAccounts: [String] { accounts(of: scope).compactMap { $0 } }

    func select(scope newScope: Scope) {
        scope = newScope
        client = nil
        if let account = folder.account, !accounts(of: newScope).contains(account) { folder = .inbox }
        selectedID = nil
        Task { await reload() }
    }

    func select(folder newFolder: MailFolder) {
        folder = newFolder
        client = nil
        bundleOpen = false
        selectedID = nil
        Task { await reload() }
    }

    func refreshLabels() async {
        for account in gmail.accounts {
            if let labels = try? await gmail.userLabels(account: account) { labelsByAccount[account] = labels }
        }
    }

    /// De kop boven de lijst.
    var listTitle: String { client ?? folder.title }

    /// Waar het zoekveld in zoekt: in Postvak IN alle mail van het bereik, anders de map.
    var searchTitle: String {
        if let client { return client }
        return folder == .inbox ? title(of: scope) : folder.title
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
        if text.trimmingCharacters(in: .whitespaces).isEmpty { searchAccounts = nil }
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
        var found: [GmailMailItem] = []
        var failure: String?
        var activityChanged = false
        if filters.contains(.waiting) {
            found = await waitingItems()
        } else {
            let request = MailSearch.request(text: query, folder: folder, attachment: filters.contains(.attachment),
                                             unread: filters.contains(.unread), clientDomains: domains)
            var targets: [String?] = client != nil ? accounts(of: .all) : (folder.account.map { [$0] } ?? accounts(of: scope))
            if let searchAccounts, client == nil { targets = searchAccounts.map { $0 } }
            for account in targets {
                do {
                    let items = try await gmail.mailItems(request, account: account)
                    found += items
                    if MailActivityStore.shared.add(items, account: account) { activityChanged = true }
                } catch {
                    failure = failure ?? error.localizedDescription
                }
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
        if activityChanged { refreshRanking() }
    }

    /// De gesprekken waarop een antwoord wordt verwacht (opvolgen), met de nieuwste mail van elk.
    private func waitingItems() async -> [GmailMailItem] {
        var result: [GmailMailItem] = []
        for entry in FollowUpStore.shared.waiting {
            guard let messages = try? await gmail.threadMessages(threadID: entry.threadID, account: entry.account),
                  let newest = messages.max(by: { $0.date < $1.date }) else { continue }
            result += await gmail.mailItems(messageIDs: [newest.id], account: entry.account)
        }
        return result
    }

    func refreshTasks() { refreshTaskThreads() }

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

    /// Nieuwsbrieven en meldingen; alleen als er niet gezocht of gefilterd wordt. Wat je uitsloot van archiveren in
    /// één keer wil je lezen: dat staat gewoon in de lijst.
    var bundle: [GmailMailItem] {
        isFiltering || folder != .inbox ? [] : filtered.filter(isBundled)
    }

    /// De mails in de lijst, in volgorde: zonder zoeken en filters staat de bundel apart (tenzij opengeklapt).
    var listed: [GmailMailItem] {
        if isFiltering || bundleOpen || folder != .inbox { return filtered }
        return filtered.filter { !isBundled($0) }
    }

    private func isBundled(_ item: GmailMailItem) -> Bool {
        let kind = kind(of: item)
        return kind != .person && !MailBulk.isExcluded(item, kind: kind, rules: bulkRules)
    }

    // MARK: Archiveren in één keer

    func addBulkRule(_ rule: BulkRule) {
        guard !bulkRules.contains(rule) else { return }
        bulkRules.append(rule)
        saveBulkRules()
    }

    func removeBulkRule(_ rule: BulkRule) {
        bulkRules.removeAll { $0 == rule }
        saveBulkRules()
    }

    func reloadBulkRules() {
        bulkRules = MailBulk.decode(UserDefaults.standard.data(forKey: Self.bulkRulesKey))
    }

    private func saveBulkRules() {
        UserDefaults.standard.set(MailBulk.encode(bulkRules), forKey: Self.bulkRulesKey)
    }

    /// Archiveert de gekozen nieuwsbrieven en meldingen; één keer ⌘Z zet ze terug.
    func archiveBulk(_ chosen: [GmailMailItem], appState: AppState) {
        let threads = chosen.map(\.threadID)
        guard !threads.isEmpty else { return }
        for thread in threads { takeOut(threadID: thread) }
        bundleOpen = false
        Task {
            let done = await gmail.archiveBulk(threadIDs: threads)
            let failed = threads.count - done.count
            if failed > 0 {
                appState.showToast("\(done.count) gearchiveerd; \(failed) mislukt", seconds: 5)
                await reload()
            } else {
                appState.announce(done.count == 1 ? "1 mail gearchiveerd" : "\(done.count) mails gearchiveerd", seconds: 3)
            }
        }
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

    /// De lijst toont de inbox: archiveren haalt een mail er dan uit.
    private var listIsInbox: Bool {
        folder == .inbox && query.trimmingCharacters(in: .whitespaces).isEmpty && client == nil && !filters.contains(.waiting)
    }

    /// Na archiveren (of een handeling die archiveert): uit de inbox weg; in een andere map, bij zoeken of een klant
    /// blijft de mail staan (zonder inbox) en gaat de selectie naar de volgende.
    func takeOut(threadID: String) {
        guard !listIsInbox else {
            remove(threadID: threadID)
            return
        }
        let wasSelected = selected?.threadID == threadID
        for index in items.indices where items[index].threadID == threadID {
            items[index].labels.removeAll { $0 == "INBOX" }
        }
        if wasSelected { selectNext() }
    }

    /// In de lijst: bij je eigen mail de ontvanger ("Aan: …") in plaats van jezelf.
    func rowSummary(_ item: GmailMailItem) -> GmailMessageSummary {
        var summary = item.summary
        let own = gmail.ownAddresses
        let others = item.recipients.filter { !own.contains($0) }
        guard let from = item.fromAddress?.lowercased(), own.contains(from), let first = others.first else { return summary }
        MailActivityStore.shared.loadIfNeeded()
        let name = MailActivityStore.shared.names[first] ?? first
        summary.fromName = "Aan: " + name + (others.count > 1 ? " +\(others.count - 1)" : "")
        summary.fromAddress = first
        return summary
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
        archive(item, announcing: nil, appState: appState)
    }

    /// Na versturen in de mailmodus: het gesprek archiveren en de volgende mail openen (de melding komt van het versturen).
    func archiveAfterSending(threadID: String, appState: AppState) {
        guard let item = items.first(where: { $0.threadID == threadID }) else { return }
        archive(item, announcing: "", appState: appState)
    }

    /// Archiveert een gesprek na een handeling en opent de volgende mail. `announcing`: de melding (leeg: geen,
    /// `nil`: de gewone van archiveren).
    func archive(_ item: GmailMailItem, announcing text: String?, appState: AppState) {
        takeOut(threadID: item.threadID)
        FollowUpStore.shared.clearReturned(threadID: item.threadID)
        if let text, !text.isEmpty { appState.announce(text, seconds: 3) }
        Task { await gmail.archiveMessage(item.summary, appState: appState, announce: text == nil) }
    }

    // MARK: Bladen

    func openSheet(_ kind: MailModeSheet) {
        guard selected != nil || !kind.needsMail else { return }
        sheet = kind
    }

    func closeSheet() { sheet = nil }

    /// Datums en tijden die in de mail worden voorgesteld en nog moeten komen (zonder het geciteerde deel). "Morgen"
    /// telt vanaf de dag dat de mail is verstuurd.
    @discardableResult
    func proposals(for item: GmailMailItem) async -> [DateProposal] {
        if let cached = proposalsByID[item.id] { return cached }
        guard let raw = try? await gmail.rawMessageData(id: item.id) else { return [] }
        let reference = item.date ?? .now
        let found = await Task.detached(priority: .utility) {
            DateProposals.find(in: QuoteSplitter.mainText(of: MailContentParser.parse(raw)), reference: reference)
        }.value.filter { $0.start > .now }
        proposalsByID[item.id] = found
        return found
    }

    // MARK: Klanten

    /// Aantal weken (staafjes) in de klantenlijst: drie maanden.
    static let clientWeeks = 13

    /// De klanten in de lijst rechts: op volgorde van contact; met een zoekterm alle klanten uit de klantenlijst die
    /// erbij passen, ook zonder mail in de laatste drie maanden.
    var clientRows: [ClientActivity.Rank] {
        let term = clientQuery.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return ranking }
        let byName = Dictionary(ranking.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let excluded = Set(MailClientSettings.excluded)
        return ClientList.search(term, in: ClientDirectory.shared.records, limit: 40)
            .filter { !excluded.contains($0.name) }
            .map { record in
                byName[record.name] ?? ClientActivity.Rank(name: record.name, count: 0,
                                                           weeks: Array(repeating: 0, count: Self.clientWeeks),
                                                           lastContact: .distantPast)
            }
    }

    /// De klantenlijst uit wat er bewaard is; bijwerken bij Gmail hooguit één keer per dag.
    func refreshClients() async {
        await ClientDirectory.shared.refresh()
        refreshRanking()
        if await MailActivityStore.shared.syncIfStale() { refreshRanking() }
    }

    /// Drie maanden, alleen uit de gekozen mailboxen; het eigen bedrijf (de domeinen van je mailboxen) en klanten die je
    /// hebt weggezet tellen niet.
    func refreshRanking() {
        MailActivityStore.shared.loadIfNeeded()
        let counted = Set(MailClientSettings.accounts)
        let records = MailActivityStore.shared.records.filter { record in record.account.map { counted.contains($0) } ?? false }
        ranking = ClientActivity.ranking(records: records, domainMap: ClientDirectory.shared.domainMap,
                                         ownAddresses: gmail.ownAddresses,
                                         ownDomains: ClientActivity.ownDomains(of: gmail.accounts),
                                         excluded: Set(MailClientSettings.excluded), now: .now,
                                         days: Int(MailActivityStore.historyDays) - 1, weekCount: Self.clientWeeks)
    }

    /// Rechtermuisknop op een klant: geen klant (bijvoorbeeld een leverancier).
    func excludeClient(_ name: String) {
        MailClientSettings.setExcluded(name, true)
        if client == name { showClient(nil) }
        refreshRanking()
    }

    // MARK: Uitgebreid zoeken

    /// Zoeken uit het zoekvenster (⌘F): de zoekopdracht komt in het zoekveld, in alle mail van de gekozen mailboxen.
    func applySearch(_ form: MailSearchForm, mailboxes: [String]) {
        searchForm = form
        let inScope = accounts(of: scope).compactMap { $0 }
        searchAccounts = Set(mailboxes) == Set(inScope) ? nil : mailboxes
        folder = .inbox
        client = nil
        bundleOpen = false
        query = form.query()
        searchTask?.cancel()
        selectedID = nil
        sheet = nil
        Task { await reload() }
    }

    /// De mailboxen waarin nu wordt gezocht (voor het zoekvenster).
    var searchAccountChoice: [String] { searchAccounts ?? accounts(of: scope).compactMap { $0 } }

    func clearSearchAccounts() {
        searchAccounts = nil
        Task { await reload() }
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
        var attachments: [MailAttachment] = []

        static func == (lhs: Request, rhs: Request) -> Bool { lhs.id == rhs.id }
    }

    private(set) var request: Request?

    func reply(_ mode: ComposeRef.Mode = .replyAll, text: String? = nil, attachments: [MailAttachment] = []) {
        request = Request(mode: mode, text: text, attachments: attachments)
    }
}

/// Welke mailboxen meetellen voor de klanten rechts in de mailmodus, en welke klanten geen klant zijn. Gaat mee naar je
/// andere Macs.
@MainActor
enum MailClientSettings {
    static let accountsKey = "mailMode.clientAccounts"
    static let excludedKey = "mailMode.excludedClients"

    /// De gekozen mailboxen. Zolang je niets kiest: GH, Support en Info als die er zijn, anders alle.
    static var accounts: [String] {
        let gmail = GmailSession.shared
        if let stored = UserDefaults.standard.stringArray(forKey: accountsKey) {
            return gmail.accounts.filter { stored.contains($0) }
        }
        let named = gmail.accounts.filter { ["gh", "support", "info"].contains(gmail.displayName($0).lowercased()) }
        return named.isEmpty ? gmail.accounts : named
    }

    static func setCounts(_ account: String, _ counts: Bool) {
        var list = accounts
        list.removeAll { $0 == account }
        if counts { list.append(account) }
        UserDefaults.standard.set(list, forKey: accountsKey)
    }

    static var excluded: [String] { UserDefaults.standard.stringArray(forKey: excludedKey) ?? [] }

    static func setExcluded(_ name: String, _ isExcluded: Bool) {
        var list = excluded.filter { $0 != name }
        if isExcluded { list.append(name) }
        UserDefaults.standard.set(list, forKey: excludedKey)
    }
}
