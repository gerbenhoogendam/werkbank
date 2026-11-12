import AppKit
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
    /// Tijdens het slepen van een mail: de mailmodus is naar beneden weggezwiept en de werkbank staat ervoor (board,
    /// agenda, Tijd schrijven). Esc haalt de mail terug.
    private(set) var isReceded = false
    /// De mail komt terug omhoog: de werkbank blijft bruikbaar tot hij er weer helemaal voor staat.
    private(set) var isReturning = false
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
    /// Meer mails tegelijk gekozen (⌘-klik, ⇧-klik); leeg als er één mail gekozen is (`selectedID`).
    private(set) var markedIDs: Set<String> = []
    /// Waar een reeks met ⇧-klik begint: de laatst aangeklikte mail.
    private var markAnchor: String?
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
    /// Welke lijst er nu staat (mailbox, map, zoekopdracht, filters); bij een andere lijst komt eerst wat er de vorige
    /// keer stond.
    @ObservationIgnored private var shownKey: String?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored private var rankingTask: Task<Void, Never>?
    /// Bijwerken mislukte en is gemeld: niet bij elke volgende poging opnieuw.
    @ObservationIgnored private var reportedFailure = false
    /// Gesprekken waarin een antwoord met tekst openstaat (de mailweergave meldt het): die gaan niet weg bij een
    /// handeling die archiveert, anders is het concept kwijt. Versturen archiveert daarna gewoon.
    @ObservationIgnored private var openReplies: Set<String> = []
    /// Antwoorden die nog openstonden toen je naar een andere mail ging (of de mailmodus sloot), per gesprek.
    @ObservationIgnored private var keptReplies: [String: KeptReply] = [:]

    struct KeptReply {
        var ref: ComposeRef
        var body: String
        var attachments: [MailAttachment]
    }
    /// De klant bij een mail, onthouden per mail (met de grootte van de klantenlijst, om te zien of die veranderde).
    @ObservationIgnored private var clientCache: [String: (mapSize: Int, name: String?)] = [:]
    @ObservationIgnored private var returnTask: Task<Void, Never>?
    @ObservationIgnored private var escapeMonitor: Any?
    @ObservationIgnored private var loadToken = 0
    /// Wanneer de lijst het laatst is opgevraagd (gelukt of niet) en wanneer het laden begon.
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var loadStarted: Date?
    /// Terug in de app of na de slaapstand: meteen verversen (`refreshIfStale`).
    @ObservationIgnored private var wakeObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
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
        isReceded = false
        isReturning = false
        watchEscape(false)
        // Direct de bewaarde lijst van dit bereik en de eerste mail, al in het eerste beeld.
        showStoredList()
        if selectedID == nil { selectedID = listed.first?.id }
        // De klantenkolom meteen uit wat bewaard is (de eerste keer na het starten stond die leeg tot Gmail antwoordde).
        if ranking.isEmpty { refreshRanking() }
        isActive = true
        // De mappen (één aanvraag per mailbox) tegelijk met de lijst; de klanten pas daarna, want die halen soms veel op
        // bij dezelfde mailboxen en Gmail begrenst het aantal aanvragen per seconde.
        Task { await refreshLabels() }
        Task {
            await reload()
            await refreshClients()
        }
        startRefreshing()
    }

    func close() {
        refreshLoop?.cancel()
        refreshLoop = nil
        for observer in wakeObservers { observer.center.removeObserver(observer.token) }
        wakeObservers = []
        isActive = false
        isReceded = false
        isReturning = false
        watchEscape(false)
        sheet = nil
        searchTask?.cancel()
    }

    /// Zolang de mailmodus open is komt nieuwe mail vanzelf binnen: elke twee minuten (zoals het Mail-paneel), en
    /// meteen als je terugkomt in Werkbank of de Mac uit de slaapstand komt. Niet tijdens een blad of het slepen.
    private func startRefreshing() {
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard let self, !Task.isCancelled else { return }
                self.refreshIfStale(after: 100)
            }
        }
        guard wakeObservers.isEmpty else { return }
        let refresh: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { MailModeStore.shared.refreshIfStale(after: 20) }
        }
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        wakeObservers = [
            (app, app.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main,
                                  using: refresh)),
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
                                              using: refresh)),
        ]
    }

    /// Een laadbeurt die na anderhalve minuut nog niet klaar is, telt niet meer: dan mag een nieuwe ervoor in de
    /// plaats (die van toen wordt genegeerd als hij alsnog terugkomt). Zo kan een verbinding die bleef hangen (na de
    /// slaapstand, ander netwerk) het verversen niet tegenhouden tot je de app opnieuw start.
    private var loadIsStuck: Bool {
        guard isLoading, let loadStarted else { return false }
        return Date().timeIntervalSince(loadStarted) > 90
    }

    /// Ververst als de lijst langer dan `seconds` geleden is opgevraagd.
    func refreshIfStale(after seconds: TimeInterval) {
        guard isActive, !isReceded, sheet == nil, !isLoading || loadIsStuck else { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < seconds { return }
        Task { await reload() }
    }

    /// De knop Verversen: de lijst, de mappen en het Mail-paneel opnieuw, ook als er nog iets aan het laden is.
    func refreshNow() {
        guard isActive else { return }
        Task { await reload() }
        Task { await refreshLabels() }
        Task { await gmail.reload(force: true) }
    }

    /// Een mail wordt gesleept: de werkbank naar voren, zodat je hem op een kolom, de agenda of Tijd schrijven kunt
    /// laten vallen.
    func recede() {
        guard isActive, !isReceded else { return }
        sheet = nil
        returnTask?.cancel()
        isReturning = false
        isReceded = true
        watchEscape(true)
    }

    func restore() {
        guard isReceded else { return }
        isReceded = false
        isReturning = true
        watchEscape(false)
        returnTask?.cancel()
        returnTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.isReturning = false
        }
    }

    /// Zolang de mail weg is haalt Esc hem terug, in elk venster van de app en wat er ook de focus heeft; alleen een
    /// blad of de aanwijsmodus gaat voor. Tijdens het slepen breekt dezelfde Esc ook het slepen af.
    private func watchEscape(_ on: Bool) {
        guard on else {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            return
        }
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            let consumed = MainActor.assumeIsolated { MailModeStore.shared.escapePressed() }
            return consumed ? nil : event
        }
    }

    /// - Returns: `true` als Esc hier is afgehandeld.
    private func escapePressed() -> Bool {
        guard isReceded, NSApp.keyWindow?.attachedSheet == nil, !FeedbackOverlay.shared.isShown else { return false }
        if MailDragState.shared.isDragging {
            // Het slepen loopt nog: macOS breekt het af met deze toets, dus die moet er wel door.
            MailDragState.shared.cancel()
            return false
        }
        restore()
        return true
    }

    // MARK: Bereik, zoeken en filters

    /// Elke mailbox, de combinatie uit het Mail-paneel (als die er is) en alle mail.
    var scopes: [Scope] {
        let accounts = gmail.accounts
        var list: [Scope] = accounts.map { .account($0) }
        // De eigen combinatie (⌘-klik hier), anders die van het Mail-paneel.
        if case .combination(let emails) = scope {
            list.append(.combination(emails))
        } else if gmail.isCombined, !gmail.isAllCombined {
            list.append(.combination(gmail.combinedAccounts))
        }
        if accounts.count != 1 { list.append(.all) }
        return list
    }

    /// Staat deze mailbox aan: als enige, of in de combinatie.
    func includes(_ email: String) -> Bool {
        switch scope {
        case .account(let current): current == email
        case .combination(let emails): emails.contains(email)
        case .all: false
        }
    }

    /// ⌘-klik op een mailbox: erbij zetten of eruit halen, zoals in het Mail-paneel. Blijft er één over, dan is dat
    /// gewoon die mailbox; staan ze allemaal aan, dan is het Alle mail.
    func toggleInScope(_ email: String) {
        let accounts = gmail.accounts
        guard accounts.contains(email) else { return }
        var selection: [String]
        switch scope {
        case .account(let current): selection = [current]
        case .combination(let emails): selection = emails
        case .all: selection = accounts
        }
        if selection.contains(email) { selection.removeAll { $0 == email } } else { selection.append(email) }
        selection = accounts.filter(selection.contains)   // vaste volgorde, zoals de knoppen
        if selection.count > 1, selection.count == accounts.count {
            select(scope: .all)
        } else if selection.count > 1 {
            select(scope: .combination(selection))
        } else if let only = selection.first {
            select(scope: .account(only))
        }
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
        switchList()
    }

    func select(folder newFolder: MailFolder) {
        folder = newFolder
        client = nil
        bundleOpen = false
        selectedID = nil
        switchList()
    }

    func refreshLabels() async {
        await withTaskGroup(of: (String, [GmailLabel]?).self) { group in
            for account in gmail.accounts {
                group.addTask { [gmail] in (account, try? await gmail.userLabels(account: account)) }
            }
            for await (account, labels) in group {
                if let labels, labelsByAccount[account] != labels { labelsByAccount[account] = labels }
            }
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
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            // Geen zoekopdracht meer: ook de eigen keuze van mailboxen en wat er in het zoekvenster stond.
            searchAccounts = nil
            searchForm = MailSearchForm()
        }
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
        markedIDs = []
        if filter != .noTask { Task { await reload() } }
    }

    func showClient(_ name: String?) {
        client = client == name ? nil : name
        selectedID = nil
        switchList()
    }

    /// Een andere lijst gekozen: meteen de bewaarde lijst en de eerste mail (geen leeg leesvlak tot de taak loopt),
    /// daarna bijwerken bij Gmail.
    private func switchList() {
        showStoredList()
        if selectedID == nil { selectedID = listed.first?.id }
        Task { await reload() }
    }

    /// Toont wat er de vorige keer in deze lijst stond, als er een andere lijst gevraagd is dan er nu staat.
    private func showStoredList() {
        let key = listKey
        guard key != shownKey else { return }
        shownKey = key
        markedIDs = []
        items = MailListCache.shared.items(for: key) ?? []
        loadError = nil
    }

    var isFiltering: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty || client != nil || !filters.isEmpty }

    // MARK: Lijst

    /// Laadt de lijst opnieuw. Een andere lijst dan net toont meteen wat er de vorige keer stond (ook na opnieuw
    /// starten), anders komt wat binnen is per mailbox erbij; de mailboxen worden tegelijk opgehaald.
    func reload() async {
        guard gmail.state == .signedIn else { return }
        loadToken += 1
        let token = loadToken
        let key = listKey
        showStoredList()
        // Meteen een mail open als er al een lijst staat (bij opnieuw openen is dat die van de vorige keer).
        if selectedID == nil { selectedID = listed.first?.id }
        let growsWhileLoading = items.isEmpty
        isLoading = true
        loadStarted = Date()
        lastAttempt = Date()
        let domains = client.map(clientDomains) ?? []
        if client != nil, domains.isEmpty {
            items = []
            isLoading = false
            loadError = "Bij deze klant staat geen domein in de klantenlijst."
            return
        }
        var result: (items: [GmailMailItem], error: String?, activityChanged: Bool)
        if filters.contains(.waiting) {
            result = (Self.newestFirst(await waitingItems()), nil, false)
        } else {
            let request = MailSearch.request(text: query, folder: folder, attachment: filters.contains(.attachment),
                                             unread: filters.contains(.unread), clientDomains: domains)
            var targets: [String?] = client != nil ? accounts(of: .all) : (folder.account.map { [$0] } ?? accounts(of: scope))
            if let searchAccounts, client == nil { targets = searchAccounts.map { $0 } }
            result = await fetchAll(request, accounts: targets) { [weak self] partial in
                guard let self, growsWhileLoading, token == self.loadToken else { return }
                self.items = partial
                if self.selectedID == nil { self.selectedID = self.listed.first?.id }
            }
        }
        guard token == loadToken else { return }
        if let error = result.error, result.items.isEmpty, !items.isEmpty {
            // Gmail niet bereikbaar: de lijst die er staat (ook die van de vorige keer) laten staan en het één keer melden.
            isLoading = false
            if !reportedFailure { AppState.shared.announce("Mail bijwerken mislukt: \(error)", seconds: 4) }
            reportedFailure = true
            return
        }
        reportedFailure = false
        // Alleen toewijzen als er iets veranderde: elke twee minuten verversen tekent anders de hele lijst opnieuw.
        if items != result.items {
            items = result.items
            keepMarks(in: items)
        }
        if result.error == nil { MailListCache.shared.store(result.items, for: key) }
        loadError = items.isEmpty ? result.error : nil
        refreshTaskThreads()
        isLoading = false
        if selected == nil { selectedID = listed.first?.id }
        if result.activityChanged { refreshRanking() }
    }

    /// Welke lijst er gevraagd wordt: bereik, map, zoektekst, filters, klant en eigen keuze van mailboxen.
    private var listKey: String {
        [String(describing: scope), String(describing: folder), query.trimmingCharacters(in: .whitespacesAndNewlines),
         // "Zonder taak" filtert alleen wat er al is (geen nieuwe aanvraag), dus hoort niet bij de lijst.
         filters.filter { $0 != .noTask }.map(\.rawValue).sorted().joined(separator: ","), client ?? "",
         (searchAccounts ?? []).joined(separator: ",")].joined(separator: "|")
    }

    /// Haalt een lijst uit meerdere mailboxen tegelijk. `progress` krijgt na elke mailbox wat er tot dan toe binnen is.
    private func fetchAll(_ request: MailListRequest, accounts targets: [String?], maxResults: Int = 50,
                          progress: (([GmailMailItem]) -> Void)? = nil) async
        -> (items: [GmailMailItem], error: String?, activityChanged: Bool) {
        var found: [GmailMailItem] = []
        var failure: String?
        var activityChanged = false
        await withTaskGroup(of: (String?, Result<[GmailMailItem], Error>).self) { group in
            for account in targets {
                group.addTask { [gmail] in
                    do {
                        return (account, .success(try await gmail.mailItems(request, account: account, maxResults: maxResults)))
                    } catch {
                        return (account, .failure(error))
                    }
                }
            }
            for await (account, outcome) in group {
                switch outcome {
                case .success(let items):
                    found += items
                    if MailActivityStore.shared.add(items, account: account) { activityChanged = true }
                    progress?(Self.newestFirst(found))
                case .failure(let error):
                    failure = failure ?? error.localizedDescription
                }
            }
        }
        return (Self.newestFirst(found), found.isEmpty ? failure : nil, activityChanged)
    }

    /// Nieuwste eerst, één mail per gesprek.
    private static func newestFirst(_ found: [GmailMailItem]) -> [GmailMailItem] {
        var seen = Set<String>()
        return found.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .filter { seen.insert($0.threadID).inserted }
    }

    /// De gesprekken waarop een antwoord wordt verwacht (opvolgen), met de nieuwste mail van elk.
    private func waitingItems() async -> [GmailMailItem] {
        let gmail = self.gmail
        let fetch: @Sendable (String, String?) async -> [GmailMailItem] = { threadID, account in
            guard let messages = try? await gmail.threadMessages(threadID: threadID, account: account),
                  let newest = messages.max(by: { $0.date < $1.date }) else { return [] }
            return await gmail.mailItems(messageIDs: [newest.id], account: account)
        }
        // Zes gesprekken tegelijk; de volgorde maakt niet uit, de lijst wordt daarna gesorteerd.
        var pending = FollowUpStore.shared.waiting.map { (threadID: $0.threadID, account: $0.account) }.makeIterator()
        return await withTaskGroup(of: [GmailMailItem].self) { group in
            for _ in 0..<6 {
                guard let entry = pending.next() else { break }
                group.addTask { await fetch(entry.threadID, entry.account) }
            }
            var result: [GmailMailItem] = []
            for await items in group {
                result += items
                if let entry = pending.next() { group.addTask { await fetch(entry.threadID, entry.account) } }
            }
            return result
        }
    }

    func refreshTasks() { refreshTaskThreads() }

    private func refreshTaskThreads() {
        // Alleen kaarten uit een mail (niet het hele archief; dit gebeurt na elke verversing).
        let fromMail = FetchDescriptor<TodoCard>(predicate: #Predicate { $0.mailThreadID != nil })
        let ids = Set(((try? Persistence.container.mainContext.fetch(fromMail)) ?? []).compactMap(\.mailThreadID))
        if ids != taskThreadIDs { taskThreadIDs = ids }
    }

    private func clientDomains(_ name: String) -> [String] {
        ClientDirectory.shared.records.first { $0.name == name }?.domains ?? []
    }

    /// De klant bij een mail: de afzender, of bij verzonden mail de eerste ontvanger die een klant is.
    func clientName(for item: GmailMailItem) -> String? {
        let map = ClientDirectory.shared.domainMap
        // Per mail onthouden: de lijst, de bundel, de labels en de toetsen vragen dit bij elke weergave opnieuw.
        if let hit = clientCache[item.id], hit.mapSize == map.count { return hit.name }
        let own = gmail.ownAddresses
        var name: String?
        for address in item.addresses where !own.contains(address) {
            if let found = ClientActivity.client(forAddress: address, domainMap: map) {
                name = found
                break
            }
        }
        if clientCache.count > 4000 { clientCache.removeAll() }
        clientCache[item.id] = (map.count, name)
        return name
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
            await report(done.count, of: threads.count, "gearchiveerd", appState: appState)
        }
    }

    // MARK: Gelezen en ongelezen

    /// Gelezen wordt ongelezen en andersom (toets U, de knop in de mail): de gekozen mail, of alle gekozen mails
    /// tegelijk (is er daarvan één ongelezen, dan worden ze allemaal gelezen). Archiveert niet; de mail blijft gekozen.
    func toggleUnread(appState: AppState) {
        let targets = isMarking ? marked : [selected].compactMap { $0 }
        guard !targets.isEmpty else { return }
        let unread = !targets.contains(where: \.isUnread)
        let changing = targets.filter { $0.isUnread != unread }
        Task {
            let done = await gmail.setUnread(unread, threads: changing.map { ($0.threadID, gmail.account(for: $0.id)) })
            await report(done, of: Set(changing.map(\.threadID)).count,
                         unread ? "gemarkeerd als ongelezen" : "gemarkeerd als gelezen", appState: appState)
        }
    }

    /// Na het markeren in Gmail (`GmailSession.setUnread`): de lijst hier meteen bijwerken, zonder opnieuw op te halen.
    func noteUnread(_ unread: Bool, threadID: String) {
        guard let index = items.firstIndex(where: { $0.threadID == threadID }), items[index].isUnread != unread
        else { return }
        var labels = items[index].labels.filter { $0 != "UNREAD" }
        if unread { labels.append("UNREAD") }
        items[index].labels = labels
        if let shownKey { MailListCache.shared.store(items, for: shownKey) }
    }

    /// Meldt hoe het ging met een handeling op meer gesprekken; mislukte er een, dan wordt de lijst opnieuw geladen.
    private func report(_ done: Int, of total: Int, _ what: String, appState: AppState) async {
        let failed = total - done
        if failed > 0 {
            appState.showToast("\(done) \(what); \(failed) mislukt", seconds: 5)
            await reload()
        } else {
            appState.announce(done == 1 ? "1 mail \(what)" : "\(done) mails \(what)", seconds: 3)
        }
    }

    /// `listed` in groepen naar dag (Vandaag, Gisteren, Deze week, Eerder).
    func sections(of listed: [GmailMailItem]) -> [Section] {
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: Date())
        func label(_ date: Date?) -> String {
            guard let date else { return "Eerder" }
            if calendar.isDateInToday(date) { return "Vandaag" }
            if calendar.isDateInYesterday(date) { return "Gisteren" }
            if let week, week.contains(date) { return "Deze week" }
            return "Eerder"
        }
        var groups: [(name: String, items: [GmailMailItem])] = []
        for item in listed {
            let name = label(item.date)
            if groups.last?.name == name {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append((name, [item]))
            }
        }
        return groups.map { Section(id: $0.name, items: $0.items) }
    }

    // MARK: Gekozen mail

    var selected: GmailMailItem? {
        guard let selectedID else { return nil }
        return items.first { $0.id == selectedID }
    }

    func select(_ item: GmailMailItem) {
        markedIDs = []
        markAnchor = item.id
        selectedID = item.id
    }

    // MARK: Meer mails tegelijk

    /// Meer dan één mail gekozen: de balk boven de lijst geldt dan voor allemaal.
    var isMarking: Bool { markedIDs.count > 1 }

    /// Of de mail in de lijst gekozen staat (alleen, of samen met andere).
    func isChosen(_ item: GmailMailItem) -> Bool {
        isMarking ? markedIDs.contains(item.id) : selectedID == item.id
    }

    /// De gekozen mails, in de volgorde van de lijst.
    var marked: [GmailMailItem] {
        guard isMarking else { return [] }
        return listed.filter { markedIDs.contains($0.id) }
    }

    /// Een klik in de lijst: met ⌘ gaat de mail erbij (of eraf), met ⇧ alles vanaf de vorige klik; zonder toets alleen
    /// deze mail.
    func click(_ item: GmailMailItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = markAnchor ?? selectedID {
            let order = listed.map(\.id)
            if let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: item.id) {
                let range = Set(order[min(from, to)...max(from, to)])
                markedIDs = flags.contains(.command) ? markedIDs.union(range) : range
                settleMarks(focus: item.id)
                return
            }
        }
        if flags.contains(.command) {
            if markedIDs.isEmpty, let selectedID { markedIDs = [selectedID] }
            if markedIDs.contains(item.id) { markedIDs.remove(item.id) } else { markedIDs.insert(item.id) }
            markAnchor = item.id
            settleMarks(focus: item.id)
            return
        }
        select(item)
    }

    /// Nog maar één mail over: dan is dat gewoon de gekozen mail. Anders volgt de lijst de laatst aangeklikte.
    private func settleMarks(focus id: String) {
        switch markedIDs.count {
        case 0: break
        case 1:
            selectedID = markedIDs.first
            markAnchor = selectedID
            markedIDs = []
        default:
            if markedIDs.contains(id) {
                selectedID = id
            } else if let current = selectedID, !markedIDs.contains(current) {
                selectedID = listed.first { markedIDs.contains($0.id) }?.id
            }
        }
    }

    /// Terug naar één mail (Esc, j/k): de laatst aangeklikte.
    func clearMarks() {
        markedIDs = []
    }

    /// Eén mail uit de selectie (hij wordt los gearchiveerd).
    func unmark(_ item: GmailMailItem) {
        markedIDs.remove(item.id)
        if markedIDs.count < 2 {
            if let only = markedIDs.first { selectedID = only }
            markedIDs = []
        } else if selectedID == item.id {
            selectedID = listed.first { markedIDs.contains($0.id) }?.id
        }
    }

    /// Na bijwerken: gekozen mails die er niet meer zijn vallen weg.
    private func keepMarks(in list: [GmailMailItem]) {
        guard !markedIDs.isEmpty else { return }
        markedIDs.formIntersection(list.map(\.id))
        if markedIDs.count < 2 { markedIDs = [] }
    }

    /// De gesprekken van de gekozen mails, elk één keer (in de volgorde van de lijst); daarna is er weer één mail
    /// gekozen. `except`: gesprekken die niet meegaan.
    private func takeMarked(except skip: (GmailMailItem) -> Bool = { _ in false }) -> [GmailMailItem] {
        var seen = Set<String>()
        let chosen = marked.filter { !skip($0) && seen.insert($0.threadID).inserted }
        markedIDs = []
        return chosen
    }

    /// Archiveert de gekozen mails; één keer ⌘Z zet ze terug.
    func archiveMarked(appState: AppState) { archiveAll(takeMarked(), appState: appState) }

    /// De gekozen mails naar de prullenbak (het hele gesprek, zoals in Gmail); één keer ⌘Z haalt ze er weer uit.
    func trashMarked(appState: AppState) { trashAll(takeMarked(), appState: appState) }

    private func archiveAll(_ chosen: [GmailMailItem], appState: AppState) {
        guard !chosen.isEmpty else { return }
        let threads = chosen.map(\.threadID)
        for thread in threads {
            takeOut(threadID: thread)
            FollowUpStore.shared.clearReturned(threadID: thread)
        }
        Task {
            let done = await gmail.archiveBulk(threadIDs: threads)
            await report(done.count, of: threads.count, "gearchiveerd", appState: appState)
        }
    }

    private func trashAll(_ chosen: [GmailMailItem], appState: AppState) {
        guard !chosen.isEmpty else { return }
        let threads = chosen.map(\.threadID)
        for thread in threads {
            remove(threadID: thread)
            FollowUpStore.shared.clearReturned(threadID: thread)
        }
        Task {
            let done = await gmail.trashBulk(threadIDs: threads)
            await report(done.count, of: threads.count, "naar de prullenbak", appState: appState)
        }
    }

    /// De mappen (labels) waar de gekozen mails heen kunnen: van hun mailboxen, op naam (dezelfde naam in twee
    /// mailboxen is één keuze); de map die open staat niet.
    func labelNames(for marked: [GmailMailItem]) -> [String] {
        let accounts = Set(marked.compactMap { gmail.account(for: $0.id) })
        var current: String?
        if case .label(_, _, let name) = folder { current = name }
        var seen = Set<String>()
        return MailFolders.userTree(accounts.sorted().flatMap { labelsByAccount[$0] ?? [] })
            .map(\.name)
            .filter { $0 != current && seen.insert($0).inserted }
    }

    /// Verplaatst de gekozen mails naar de map `name`, zoals "Verplaatsen naar" in Gmail: het label erbij, Postvak IN
    /// (en de map waar ze nu staan) eraf. Mails uit een mailbox zonder die map blijven staan.
    func moveMarked(toLabel name: String, appState: AppState) {
        var changes: [GmailSession.LabelChange] = []
        var missing = 0
        for item in takeMarked() {
            guard let account = gmail.account(for: item.id),
                  let label = labelsByAccount[account]?.first(where: { $0.name == name }) else {
                missing += 1
                continue
            }
            if let change = labelChange(item, account: account, labelID: label.id) { changes.append(change) }
        }
        let leaf = Self.leaf(name)
        guard !changes.isEmpty else {
            if missing > 0 { appState.announce("Geen map \(leaf) in die mailbox", seconds: 3) }
            return
        }
        moveToLabel(changes, leaf: leaf, missing: missing, appState: appState)
    }

    /// Naar map `labelID` van `account`: het label erbij, Postvak IN en de map die open staat eraf. `nil`: niets te doen.
    private func labelChange(_ item: GmailMailItem, account: String, labelID: String) -> GmailSession.LabelChange? {
        var leaving = item.labels.filter { $0 == "INBOX" }
        if case .label(let owner, let id, _) = folder, owner == account, id != labelID { leaving.append(id) }
        let adding = item.labels.contains(labelID) ? [] : [labelID]
        guard !adding.isEmpty || !leaving.isEmpty else { return nil }
        return GmailSession.LabelChange(threadID: item.threadID, account: account, add: adding, remove: leaving)
    }

    /// Voert de verplaatsing naar een map uit: uit een map of Postvak IN weg; in Alle mail, Verstuurd of bij zoeken
    /// blijft de mail staan.
    private func moveToLabel(_ changes: [GmailSession.LabelChange], leaf: String, missing: Int = 0, appState: AppState) {
        guard !changes.isEmpty else { return }
        for change in changes {
            if folder.account != nil { remove(threadID: change.threadID) } else { takeOut(threadID: change.threadID) }
        }
        Task {
            let done = await gmail.relabelBulk(changes)
            await report(done.count, of: changes.count, "verplaatst naar \(leaf)", appState: appState)
            if missing > 0 { appState.announce("\(missing) niet verplaatst: geen map \(leaf) in die mailbox", seconds: 4) }
        }
    }

    private static func leaf(_ name: String) -> String { name.split(separator: "/").last.map(String.init) ?? name }

    /// De mailboxen waar de gekozen mails heen kunnen: alle gekoppelde, behalve als ze er allemaal al in staan.
    func targetMailboxes(for marked: [GmailMailItem]) -> [String] {
        let sources = Set(marked.compactMap { gmail.account(for: $0.id) })
        return gmail.accounts.filter { sources != [$0] }
    }

    /// Verplaatst de gekozen mails naar een andere gekoppelde mailbox (één voor één ingevoegd, daarna in de oude
    /// mailbox naar de prullenbak); één keer ⌘Z zet ze terug. Mails die er al staan blijven staan.
    func moveMarked(toMailbox target: String, appState: AppState) {
        moveAll(takeMarked(), toMailbox: target, label: nil, appState: appState)
    }

    /// Naar een andere mailbox, in de inbox of (`label`) in een map daar.
    private func moveAll(_ chosen: [GmailMailItem], toMailbox target: String, label: (id: String, name: String)?,
                         appState: AppState) {
        let moving = chosen.filter { gmail.account(for: $0.id) != target }
        guard !moving.isEmpty else { return }
        let name = label.map { "\(gmail.displayName(target)) › \(Self.leaf($0.name))" } ?? gmail.displayName(target)
        Task {
            let done = await gmail.moveThreads(moving.map { (threadID: $0.threadID, messageID: $0.id) }, to: target,
                                               label: label?.id) { [weak self] thread in
                self?.remove(threadID: thread)
            }
            await report(done.count, of: moving.count, "verplaatst naar \(name)", appState: appState)
        }
    }

    // MARK: Slepen naar een map of mailbox

    /// De mails die meegaan als `payload` wordt losgelaten: alle gekozen mails als hij daarbij hoort, anders alleen hij.
    private func dragged(_ payload: GmailDragPayload) -> [GmailMailItem] {
        if isMarking, markedIDs.contains(payload.messageID) { return takeMarked() }
        guard let item = items.first(where: { $0.id == payload.messageID }) else { return [] }
        return [item]
    }

    /// Of een map een gesleepte mail aanneemt: Postvak IN, Alle mail (archiveren), Prullenbak en de eigen mappen.
    static func acceptsDrop(_ folder: MailFolder) -> Bool {
        switch folder {
        case .inbox, .all, .trash, .label: true
        default: false
        }
    }

    /// Een mail (of de gekozen mails) losgelaten op een map in de kolom links. Een map van een andere mailbox: de mail
    /// verhuist naar die mailbox, in die map.
    func drop(_ payload: GmailDragPayload, on target: MailFolder, appState: AppState) {
        guard Self.acceptsDrop(target), target != folder else { return }
        let chosen = dragged(payload)
        guard !chosen.isEmpty else { return }
        switch target {
        case .all: archiveAll(chosen, appState: appState)
        case .trash: trashAll(chosen, appState: appState)
        case .inbox: backToInbox(chosen, appState: appState)
        case .label(let account, let id, let name):
            let here = chosen.filter { gmail.account(for: $0.id) == account }
            moveToLabel(here.compactMap { labelChange($0, account: account, labelID: id) }, leaf: Self.leaf(name),
                        appState: appState)
            moveAll(chosen.filter { gmail.account(for: $0.id) != account }, toMailbox: account, label: (id, name),
                    appState: appState)
        default: break
        }
    }

    /// Een mail (of de gekozen mails) losgelaten op een mailbox: naar de inbox daar.
    func drop(_ payload: GmailDragPayload, onMailbox account: String, appState: AppState) {
        moveAll(dragged(payload), toMailbox: account, label: nil, appState: appState)
    }

    /// Terug in Postvak IN; uit een map komend gaat die map eraf.
    private func backToInbox(_ chosen: [GmailMailItem], appState: AppState) {
        let changes = chosen.compactMap { item -> GmailSession.LabelChange? in
            let account = gmail.account(for: item.id)
            var leaving: [String] = []
            if case .label(let owner, let id, _) = folder, owner == account { leaving.append(id) }
            let adding = item.labels.contains("INBOX") ? [] : ["INBOX"]
            guard !adding.isEmpty || !leaving.isEmpty else { return nil }
            return GmailSession.LabelChange(threadID: item.threadID, account: account, add: adding, remove: leaving)
        }
        guard !changes.isEmpty else { return }
        if folder.account != nil { for change in changes { remove(threadID: change.threadID) } }
        Task {
            let done = await gmail.relabelBulk(changes)
            await report(done.count, of: changes.count, "terug in Postvak IN", appState: appState)
        }
    }

    /// Na het kiezen van een mail: de volgende twee alvast ophalen en klaarzetten, zodat j/k direct is.
    func prefetchAfterSelection() {
        prefetchTask?.cancel()
        let order = listed
        guard let index = order.firstIndex(where: { $0.id == selectedID }) else { return }
        let upcoming = Array(order.dropFirst(index + 1).prefix(2))
        guard !upcoming.isEmpty else { return }
        prefetchTask = Task { [gmail] in
            try? await Task.sleep(for: .milliseconds(350))
            for item in upcoming {
                guard !Task.isCancelled else { return }
                await MailPrefetch.warm(threadID: item.threadID, messageID: item.id, account: gmail.account(for: item.id))
            }
        }
    }

    func selectNext() { step(1) }
    func selectPrevious() { step(-1) }

    private func step(_ delta: Int) {
        markedIDs = []
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
        if !markedIDs.isEmpty { keepMarks(in: items.filter { $0.threadID != threadID }) }
        items.removeAll { $0.threadID == threadID }
        MailListCache.shared.remove(threadID: threadID)
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
        if isMarking {
            archiveMarked(appState: appState)
            return
        }
        guard let item = selected else { return }
        archive(item, announcing: nil, appState: appState)
    }

    /// Na versturen in de mailmodus: het gesprek archiveren en de volgende mail openen (de melding komt van het versturen).
    func archiveAfterSending(threadID: String, appState: AppState) {
        openReplies.remove(threadID)   // verstuurd: er staat geen antwoord meer open
        guard let item = items.first(where: { $0.threadID == threadID }) else { return }
        if folder == .drafts {
            // Een concept verstuurd: weg uit Concepten; het gesprek (als dat in de inbox stond) ook uit de inbox.
            remove(threadID: threadID)
            Task { await gmail.archiveMessage(item.summary, appState: appState, announce: false) }
            return
        }
        archive(item, announcing: "", appState: appState)
    }

    /// Archiveert een gesprek na een handeling en opent de volgende mail. `announcing`: de melding (leeg: geen,
    /// `nil`: de gewone van archiveren).
    func archive(_ item: GmailMailItem, announcing text: String?, appState: AppState) {
        if hasOpenReply(item.threadID) {
            appState.announce(Self.keepingReply(text), seconds: 4)
            return
        }
        takeOut(threadID: item.threadID)
        FollowUpStore.shared.clearReturned(threadID: item.threadID)
        if let text, !text.isEmpty { appState.announce(text, seconds: 3) }
        Task { await gmail.archiveMessage(item.summary, appState: appState, announce: text == nil) }
    }

    /// Een concept weggegooid: in Concepten staat het dan niet meer.
    func draftDiscarded(threadID: String) {
        openReplies.remove(threadID)
        if folder == .drafts { remove(threadID: threadID) }
    }

    // MARK: Open antwoorden

    func replyChanged(threadID: String, open: Bool) {
        if open { openReplies.insert(threadID) } else { openReplies.remove(threadID) }
    }

    func hasOpenReply(_ threadID: String) -> Bool { openReplies.contains(threadID) }

    /// De mailweergave gaat weg (andere mail, mailmodus dicht): een antwoord met tekst bewaren voor als je terugkomt.
    func leaveReply(threadID: String, keeping reply: KeptReply?) {
        openReplies.remove(threadID)
        keptReplies[threadID] = reply
        if keptReplies.count > 30, let any = keptReplies.keys.first(where: { $0 != threadID }) { keptReplies[any] = nil }
    }

    /// Het bewaarde antwoord van een gesprek, één keer (daarna staat het weer in de weergave).
    func takeKeptReply(threadID: String) -> KeptReply? {
        keptReplies.removeValue(forKey: threadID)
    }

    /// De melding als een gesprek blijft staan omdat er een antwoord openstaat: wat er gedaan is, zonder "gearchiveerd".
    private static func keepingReply(_ text: String?) -> String {
        let note = "niet gearchiveerd: je antwoord staat nog open"
        let done = (text ?? "")
            .replacingOccurrences(of: " · gearchiveerd", with: "")
            .replacingOccurrences(of: "Gearchiveerd · ", with: "")
        guard !done.isEmpty else { return "Niet gearchiveerd: je antwoord staat nog open" }
        return String(done.prefix(1)).uppercased() + String(done.dropFirst()) + " · " + note
    }

    // MARK: Bladen

    func openSheet(_ kind: MailModeSheet) {
        // Een blad voor één mail niet als er meer gekozen zijn.
        guard !kind.needsMail || (selected != nil && !isMarking) else { return }
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
        let domainMap = ClientDirectory.shared.domainMap
        let own = gmail.ownAddresses
        let ownDomains = ClientActivity.ownDomains(of: gmail.accounts)
        let excluded = Set(MailClientSettings.excluded)
        let days = Int(MailActivityStore.historyDays) - 1
        let weeks = Self.clientWeeks
        // Drie maanden mail doorlopen: buiten de hoofdthread, anders hapert het openen van de mailmodus.
        rankingTask?.cancel()
        rankingTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                ClientActivity.ranking(records: records, domainMap: domainMap, ownAddresses: own, ownDomains: ownDomains,
                                       excluded: excluded, now: .now, days: days, weekCount: weeks)
            }.value
            guard !Task.isCancelled, result != ranking else { return }
            ranking = result
        }
    }

    /// Rechtermuisknop op een klant: geen klant (bijvoorbeeld een leverancier).
    func excludeClient(_ name: String) {
        MailClientSettings.setExcluded(name, true)
        if client == name { showClient(nil) }
        refreshRanking()
    }

    // MARK: Uitgebreid zoeken

    /// Zoeken uit het zoekvenster (⌘F): de zoekopdracht komt in het zoekveld, in alle mail van de gekozen mailboxen.
    /// `selecting`: een resultaat uit het zoekvenster dat meteen open moet.
    func applySearch(_ form: MailSearchForm, mailboxes: [String], selecting: String? = nil) {
        searchForm = form
        let inScope = accounts(of: scope).compactMap { $0 }
        searchAccounts = Set(mailboxes) == Set(inScope) ? nil : mailboxes
        folder = .inbox
        client = nil
        bundleOpen = false
        query = form.query()
        searchTask?.cancel()
        selectedID = selecting
        sheet = nil
        Task {
            await reload()
            if let selecting, items.contains(where: { $0.id == selecting }) { selectedID = selecting }
        }
    }

    /// De mailboxen voor het zoekvenster: de laatst gekozen, anders info@, support@ en gh@ (als die er zijn).
    var searchAccountChoice: [String] { searchAccounts ?? MailClientSettings.preferred }

    /// De resultaten in het zoekvenster zelf, zonder de lijst te veranderen: nieuwste eerst, één per gesprek.
    func searchPreview(_ form: MailSearchForm, mailboxes: [String]) async -> (items: [GmailMailItem], error: String?) {
        let request = MailSearch.request(text: form.query(), folder: .inbox)
        let result = await fetchAll(request, accounts: mailboxes.map { $0 }, maxResults: 40)
        if result.activityChanged { refreshRanking() }
        return (result.items, result.error)
    }

    /// Het kruisje (in het zoekveld en op het knopje van de mailboxen): de zoekopdracht helemaal weg. De tekst, de
    /// eigen keuze van mailboxen en wat er in het zoekvenster stond; dat opent daarna leeg. De gewone lijst komt terug.
    func clearSearch() {
        searchTask?.cancel()
        query = ""
        searchAccounts = nil
        searchForm = MailSearchForm()
        selectedID = nil
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

    /// De gekozen mailboxen. Zolang je niets kiest: `preferred`.
    static var accounts: [String] {
        let gmail = GmailSession.shared
        if let stored = UserDefaults.standard.stringArray(forKey: accountsKey) {
            return gmail.accounts.filter { stored.contains($0) }
        }
        return preferred
    }

    /// De werkmailboxen gh@, support@ en info@ (op het deel voor de @ of de naam van de tab), als die er zijn;
    /// anders alle.
    static var preferred: [String] {
        let gmail = GmailSession.shared
        let names: Set<String> = ["gh", "support", "info"]
        let found = gmail.accounts.filter { account in
            let local = account.lowercased().split(separator: "@").first.map(String.init) ?? ""
            return names.contains(local) || names.contains(gmail.displayName(account).lowercased())
        }
        return found.isEmpty ? gmail.accounts : found
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
