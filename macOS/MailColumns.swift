import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

/// Mail in kolommen: het hele venster toont de inboxen van een paar mailboxen naast elkaar. Klik op een mailbox bovenin
/// toont alleen die, ⌘-klik zet er een bij of haalt hem weg (wordt onthouden). Een klik kiest een mail, dubbelklik
/// opent hem als paneel; een mail naar een andere kolom slepen verhuist het gesprek naar die mailbox.
@MainActor
@Observable
final class MailColumnsStore {
    static let shared = MailColumnsStore()
    static let accountsKey = "mailColumns.accounts"
    /// Gesprekken met een ster: alleen in Werkbank (Gmail krijgt geen ster), gaat mee naar je andere Macs.
    nonisolated static let starredKey = "mailColumns.starred"

    private(set) var isActive = false
    /// De gekozen mailboxen (leeg: de eerste drie).
    private(set) var chosen: [String] = UserDefaults.standard.stringArray(forKey: MailColumnsStore.accountsKey) ?? []
    private(set) var lists: [String: [GmailMailItem]] = [:]
    private(set) var loading: Set<String> = []
    private(set) var errors: [String: String] = [:]
    /// De gekozen mails, over alle kolommen. Klik: één mail; ⌘-klik: erbij of eraf (ook in een andere kolom);
    /// ⇧-klik: alles in die kolom tussen de vorige klik en deze.
    private(set) var chosenIDs: Set<String> = []
    @ObservationIgnored private var anchor: (id: String, account: String)?
    private(set) var starredThreads: Set<String> = Set(UserDefaults.standard.stringArray(forKey: MailColumnsStore.starredKey) ?? [])

    private init() {
        // Van een andere Mac binnengekomen (PreferencesSync): de sterren bijwerken.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let stored = Set(UserDefaults.standard.stringArray(forKey: MailColumnsStore.starredKey) ?? [])
                if stored != MailColumnsStore.shared.starredThreads { MailColumnsStore.shared.starredThreads = stored }
            }
        }
    }
    /// De kolom waar een mail boven hangt tijdens het slepen.
    var dropTarget: String?

    private let gmail = GmailSession.shared

    /// De kolommen in de gekozen volgorde (⌘3 zet GH, Support, Info, Notify); klikken in de balk sorteert ze weer zoals
    /// de mailboxen.
    var shown: [String] {
        let all = gmail.accounts
        let picked = chosen.filter { all.contains($0) }
        return picked.isEmpty ? Array(all.prefix(3)) : picked
    }

    /// De vaste vier van ⌘3, op de korte naam van de mailbox (of het deel voor de @).
    static let defaultColumns = ["gh", "support", "info", "notify"]

    /// ⌘3: de kolommen GH, Support, Info en Notify openen; een naam die niet bestaat valt weg. Vindt hij er geen, dan
    /// blijven de kolommen zoals ze waren.
    func showDefaultColumns() {
        let all = gmail.accounts
        let matched = Self.defaultColumns.compactMap { name in
            all.first { gmail.displayName($0).lowercased() == name }
                ?? all.first { GmailSession.shortName($0).lowercased() == name }
        }
        if !matched.isEmpty {
            chosen = matched
            UserDefaults.standard.set(chosen, forKey: Self.accountsKey)
        }
        if isActive {
            Task { await reloadAll() }
        } else {
            open()
        }
    }

    var unreadCount: Int { shown.reduce(0) { $0 + (lists[$1]?.filter(\.isUnread).count ?? 0) } }

    func toggle() { isActive ? close() : open() }

    func open() {
        if MailModeStore.shared.isActive { MailModeStore.shared.close() }
        withAnimation(.easeOut(duration: 0.2)) { isActive = true }
        Task { await reloadAll() }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.2)) { isActive = false }
        chosenIDs = []
    }

    /// Klik op een mailbox: alleen die. ⌘-klik: erbij of eraf (de laatste blijft staan).
    func tap(_ account: String) {
        var current = shown
        if NSEvent.modifierFlags.contains(.command) {
            if let index = current.firstIndex(of: account) {
                guard current.count > 1 else { return }
                current.remove(at: index)
            } else {
                current.append(account)
            }
        } else {
            current = [account]
        }
        chosen = gmail.accounts.filter { current.contains($0) }
        UserDefaults.standard.set(chosen, forKey: Self.accountsKey)
        if lists[account] == nil, shown.contains(account) { Task { await reload(account) } }
    }

    // MARK: Lijsten

    func reloadAll() async {
        await withTaskGroup(of: Void.self) { group in
            for account in shown { group.addTask { await self.reload(account) } }
        }
    }

    func reload(_ account: String) async {
        loading.insert(account)
        defer { loading.remove(account) }
        do {
            let items = try await gmail.mailItems(MailSearch.request(text: "", folder: .inbox), account: account,
                                                  maxResults: 50)
            for item in items {
                gmail.note(account: account, forMessageID: item.id)
                gmail.note(account: account, forMessageID: item.threadID)
            }
            lists[account] = items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            errors[account] = nil
        } catch {
            errors[account] = error.localizedDescription
        }
    }

    /// Gearchiveerd of verplaatst (waar dan ook in de app): uit de kolommen. Een ster gaat mee weg: gearchiveerd is klaar.
    func removeThread(_ threadID: String) {
        for key in Array(lists.keys) { lists[key]?.removeAll { $0.threadID == threadID } }
        if starredThreads.contains(threadID) { setStarred(false, threadIDs: [threadID]) }
    }

    /// Gelezen of ongelezen gezet (waar dan ook in de app).
    func noteUnread(_ unread: Bool, threadID: String) {
        for key in Array(lists.keys) {
            guard let index = lists[key]?.firstIndex(where: { $0.threadID == threadID }) else { continue }
            var labels = lists[key]?[index].labels.filter { $0 != "UNREAD" } ?? []
            if unread { labels.append("UNREAD") }
            lists[key]?[index].labels = labels
        }
    }

    func account(of threadID: String) -> String? {
        lists.first { $0.value.contains { $0.threadID == threadID } }?.key
    }

    // MARK: Kiezen

    /// De mails van een kolom zoals ze onder elkaar staan: eerst die met een ster.
    func order(_ account: String) -> [GmailMailItem] {
        let items = lists[account] ?? []
        return items.filter { isStarred($0) } + items.filter { !isStarred($0) }
    }

    func click(_ item: GmailMailItem, in account: String) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if chosenIDs.contains(item.id) { chosenIDs.remove(item.id) } else { chosenIDs.insert(item.id) }
            anchor = (item.id, account)
        } else if flags.contains(.shift), let anchor, anchor.account == account {
            let ids = order(account).map(\.id)
            if let from = ids.firstIndex(of: anchor.id), let to = ids.firstIndex(of: item.id) {
                chosenIDs.formUnion(ids[min(from, to)...max(from, to)])
            }
        } else {
            chosenIDs = [item.id]
            anchor = (item.id, account)
        }
    }

    /// De gekozen mails die nog in de kolommen staan.
    var chosenMails: [GmailMailItem] {
        shown.flatMap { order($0) }.filter { chosenIDs.contains($0.id) }
    }

    func clearChoice() { chosenIDs = [] }

    // MARK: Handelingen

    func archive(_ item: GmailMailItem) {
        chosenIDs.remove(item.id)
        Task { await gmail.archiveMessage(item.summary, appState: AppState.shared) }
    }

    // MARK: Ster (alleen in Werkbank)

    func isStarred(_ item: GmailMailItem) -> Bool { starredThreads.contains(item.threadID) }

    func setStarred(_ starred: Bool, threadIDs: [String]) {
        withAnimation(.easeOut(duration: 0.2)) {
            if starred { starredThreads.formUnion(threadIDs) } else { starredThreads.subtract(threadIDs) }
        }
        UserDefaults.standard.set(starredThreads.sorted(), forKey: Self.starredKey)
    }

    func toggleStar(_ item: GmailMailItem) {
        setStarred(!isStarred(item), threadIDs: [item.threadID])
    }

    /// De gekozen gesprekken (elk één keer).
    private func chosenThreads() -> [(threadID: String, account: String?)] {
        var seen: Set<String> = []
        return chosenMails.compactMap { item in
            guard seen.insert(item.threadID).inserted else { return nil }
            return (threadID: item.threadID, account: account(of: item.threadID))
        }
    }

    func archiveChosen() {
        let threads = chosenThreads()
        chosenIDs = []
        Task {
            let done = await gmail.archiveBulk(threadIDs: threads.map(\.threadID))
            AppState.shared.showToast(done.count == 1 ? "Mail gearchiveerd in Gmail" : "\(done.count) mails gearchiveerd in Gmail")
        }
    }

    func trashChosen() {
        let threads = chosenThreads()
        chosenIDs = []
        Task {
            let done = await gmail.trashBulk(threadIDs: threads.map(\.threadID))
            AppState.shared.showToast(done.count == 1 ? "Mail in de prullenbak" : "\(done.count) mails in de prullenbak")
        }
    }

    /// Staat er één ongelezen tussen, dan alles gelezen; anders alles ongelezen.
    func toggleUnreadChosen() {
        let unread = !chosenMails.contains(where: \.isUnread)
        let threads = chosenThreads()
        Task {
            let done = await gmail.setUnread(unread, threads: threads)
            AppState.shared.showToast("\(done) \(done == 1 ? "mail" : "mails") \(unread ? "ongelezen" : "gelezen")")
        }
    }

    /// Hebben ze allemaal een ster, dan gaan die eraf; anders krijgen ze er allemaal een.
    func toggleStarChosen() {
        setStarred(!chosenMails.allSatisfy { isStarred($0) }, threadIDs: chosenThreads().map(\.threadID))
    }

    /// Een mail op een andere kolom laten vallen: het gesprek verhuist naar die mailbox.
    func move(threadID: String, messageID: String, to target: String) {
        guard let source = account(of: threadID), source != target else { return }
        PanelStore.shared.closeMail(messageID: messageID, snapshot: false)
        lists[source]?.removeAll { $0.threadID == threadID }
        Task {
            await gmail.moveThread(threadID: threadID, messageID: messageID, from: source, to: target,
                                   appState: AppState.shared)
            await reload(target)
            await reload(source)
        }
    }
}

// MARK: - Weergave

struct MailColumnsView: View {
    private let store = MailColumnsStore.shared
    private let gmail = GmailSession.shared
    private let mailMode = MailModeStore.shared
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HStack(alignment: .top, spacing: 10) {
                ForEach(store.shown, id: \.self) { account in
                    MailColumn(account: account)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(ThingsColor.mailBackground)
        // ⌘F: het uitgebreide zoeken van de mailmodus, over de kolommen.
        .overlay {
            if mailMode.sheet == .search {
                MailModeSheetHost(sheet: .search, item: nil)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: mailMode.sheet)
        .task { await store.reloadAll() }
        .onAppear(perform: installKeys)
        .onDisappear {
            removeKeys()
            if mailMode.sheet == .search, !mailMode.isActive { mailMode.closeSheet() }
        }
    }

    /// ⌘F opent het zoeken (ook vanuit een veld); Esc sluit het weer, en niet de kolommen.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) } ? nil : event
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard store.isActive, !mailMode.isActive, event.window === DuoWindowFold.shared.mainWindow,
              !PanelStore.shared.hasFocusPanels else { return false }
        if mailMode.sheet == .search {
            guard event.keyCode == 53 else { return false }
            mailMode.closeSheet()
            return true
        }
        // Esc met meer gekozen mails: eerst de keuze weg, niet de kolommen.
        if event.keyCode == 53, store.chosenMails.count > 1 {
            store.clearChoice()
            return true
        }
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            mailMode.openSheet(.search)
            return true
        }
        return false
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            // Terug naar de werkbank (ook met Esc of ⌘1).
            Button {
                store.close()
            } label: {
                Image(systemName: "rectangle.split.3x1.fill")
                    .font(.werk(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(ThingsColor.onAccent)
                    .background(RoundedRectangle(cornerRadius: min(6, ThingsMetrics.cardRadius), style: .continuous)
                        .fill(ThemeStore.shared.look == .etiket ? Etiket.lime : ThingsColor.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Kolommen sluiten (Esc)")
            MailHeaderTitle(title: "Mail", unread: store.unreadCount, total: 0, mailbox: "")
                .lineLimit(1)
                .fixedSize()
            if store.chosenMails.count > 1 {
                ColumnsChoiceBar()
            } else {
                HStack(spacing: 4) {
                    ForEach(gmail.accounts, id: \.self) { account in
                        MailboxTab(title: gmail.displayName(account), isOn: store.shown.contains(account), fitsContent: true) {
                            store.tap(account)
                        }
                        .help("\(account) · ⌘-klik om erbij te zetten of weg te halen")
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await store.reloadAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Verversen")
            Button {
                DefaultMailApp.composeNew()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("Nieuwe mail (⌘N)")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

/// Eén mailbox: de naam, het aantal ongelezen en de inbox.
private struct MailColumn: View {
    let account: String
    private let store = MailColumnsStore.shared
    private let gmail = GmailSession.shared

    private var items: [GmailMailItem] { store.lists[account] ?? [] }
    private var starred: [GmailMailItem] { items.filter { store.isStarred($0) } }
    private var others: [GmailMailItem] { items.filter { !store.isStarred($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                ThemedHeading(title: gmail.displayName(account))
                Spacer(minLength: 6)
                let unread = items.filter(\.isUnread).count
                if unread > 0 {
                    Text(unread == 1 ? "1 ongelezen" : "\(unread) ongelezen")
                        .font(.werk(size: 11, weight: .semibold))
                        .foregroundStyle(Color.fieldLabel)
                }
                if store.loading.contains(account) { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            if let error = store.errors[account], items.isEmpty {
                Text(error)
                    .font(.werk(size: 11.5))
                    .foregroundStyle(ThingsColor.deadline)
                    .padding(12)
            }
            if !starred.isEmpty { starredBand }
            ScrollView {
                LazyVStack(spacing: MailLook.cardRows ? 2 : 0) {
                    ForEach(others) { item in
                        GmailRow(message: item.summary,
                                 isBusy: gmail.busyMessageIDs.contains(item.id),
                                 isSelected: store.chosenIDs.contains(item.id),
                                 showsActionsWhenSelected: store.chosenMails.count <= 1,
                                 onStar: { store.toggleStar(item) },
                                 onSelect: { store.click(item, in: account) },
                                 onArchive: { store.archive(item) },
                                 onDragStarted: {})
                        if !MailLook.cardRows {
                            Rectangle().fill(ThingsColor.separator).frame(height: 1).padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.horizontal, MailLook.cardRows ? 6 : 0)
                .padding(.vertical, MailLook.cardRows ? 4 : 0)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ThingsColor.mailHeaderBackground)
        .overlay {
            if store.dropTarget == account {
                RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                    .fill(ThingsColor.accent.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous))
        // Verplaatsen, geen kopie: de cursor toont ook verplaatsen (geen groen plusje).
        .onDrop(of: [.gmailMessage], delegate: ColumnMoveDrop(account: account))
    }
}

/// Een mail op een kolom laten vallen: het gesprek verhuist naar die mailbox (verplaatsen, nooit kopiëren).
struct ColumnMoveDrop: DropDelegate {
    let account: String

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.gmailMessage]) }

    func dropEntered(info: DropInfo) { MailColumnsStore.shared.dropTarget = account }

    func dropExited(info: DropInfo) {
        if MailColumnsStore.shared.dropTarget == account { MailColumnsStore.shared.dropTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        MailColumnsStore.shared.dropTarget = nil
        guard let provider = info.itemProviders(for: [.gmailMessage]).first else { return false }
        let target = account
        provider.loadDataRepresentation(forTypeIdentifier: UTType.gmailMessage.identifier) { data, _ in
            guard let data, let payload = try? JSONDecoder().decode(GmailDragPayload.self, from: data) else { return }
            Task { @MainActor in
                MailColumnsStore.shared.move(threadID: payload.threadID, messageID: payload.messageID, to: target)
            }
        }
        return true
    }
}

// MARK: - Ster

extension ThingsColor {
    /// De datum van een mail met een ster die al meer dan 4 dagen ligt: knaloranje.
    static let starLate = Color(red: 1, green: 0x6A / 255, blue: 0)
    /// Meer dan 6 dagen: knalrood/fuchsia.
    static let starOverdue = Color(red: 1, green: 0, blue: 0x55 / 255)
}

extension MailColumn {
    /// De mails met een ster: bovenin, elk op een compacte regel. Meer dan vijf: die scrollen binnen de band.
    @ViewBuilder var starredBand: some View {
        let etiket = ThemeStore.shared.look == .etiket
        let rows = VStack(spacing: 0) {
            ForEach(starred) { item in
                StarredMailRow(item: item, account: account)
                if item.id != starred.last?.id {
                    Rectangle().fill(ThingsColor.separator.opacity(0.6)).frame(height: 1)
                }
            }
        }
        Group {
            if starred.count > 5 {
                ScrollView { rows }
                    .scrollIndicators(.never)
                    .frame(height: 5 * 44)
            } else {
                rows
            }
        }
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .bottom) {
            Rectangle().fill(etiket ? ThingsColor.textPrimary : ThingsColor.separator).frame(height: etiket ? 2 : 1)
        }
    }
}

/// Eén mail met een ster: ster, datum (dag/maand, oranje of rood als hij blijft liggen), voornaam en onderwerp; daaronder
/// de inhoud op één regel. Klik kiest, dubbelklik opent, slepen verhuist hem naar een andere kolom.
private struct StarredMailRow: View {
    let item: GmailMailItem
    let account: String
    private let store = MailColumnsStore.shared
    @State private var isHovering = false

    var body: some View {
        let selected = store.chosenIDs.contains(item.id)
        HStack(alignment: .top, spacing: 8) {
            StarButton { store.toggleStar(item) }
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if let date = item.date { dateText(date) }
                    Text(StarredMail.firstName(item.fromName, address: item.fromAddress))
                        .font(.werk(size: 13, weight: item.isUnread ? .semibold : .medium))
                        .foregroundStyle(ThingsColor.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(item.subject)
                        .font(.werk(size: 13))
                        .foregroundStyle(ThingsColor.textPrimary)
                        .lineLimit(1)
                }
                if !item.snippet.isEmpty {
                    Text(StarredMail.oneLine(item.snippet))
                        .font(.werk(size: 11.5))
                        .foregroundStyle(ThingsColor.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Eerst dubbelklik, dan enkele klik: anders wint de enkele klik altijd.
            .onTapGesture(count: 2) { PanelStore.shared.open(.mail(MailRef(message: item.summary))) }
            .onTapGesture { store.click(item, in: account) }
            .onDrag { GmailSession.shared.dragProvider(for: item.summary) }
            .contextMenu {
                Button("Openen") { PanelStore.shared.open(.mail(MailRef(message: item.summary))) }
                Button(item.isUnread ? "Markeer als gelezen" : "Markeer als ongelezen") {
                    Task { await GmailSession.shared.toggleUnread(item.summary, appState: AppState.shared) }
                }
                Button("Ster eraf") { store.toggleStar(item) }
                Button("Archiveren") { store.archive(item) }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background {
            if selected {
                Rectangle().fill(ThingsColor.selection).overlay(Color.primary.opacity(0.06))
            } else if isHovering {
                Rectangle().fill(ThingsColor.selection.opacity(0.5))
            }
        }
        .opacity(GmailSession.shared.busyMessageIDs.contains(item.id) ? 0.5 : 1)
        .onHover { isHovering = $0 }
    }

    private func dateText(_ date: Date) -> some View {
        let age = StarredMail.age(of: date, now: .now)
        let color: Color = switch age {
        case .fresh: ThingsColor.textSecondary
        case .late: ThingsColor.starLate
        case .overdue: ThingsColor.starOverdue
        }
        return Text(StarredMail.dayMonth(date))
            .font(.werk(size: 12, weight: age == .fresh ? .regular : .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

/// De ster voor een mail met een ster: verzonken (schaduw aan de binnenkant), bij aanwijzen komt hij omhoog met een
/// schaduw eronder. Geen lijn erom: de schaduw houdt hem ook in licht leesbaar.
private struct StarButton: View {
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let fill = ThemeStore.shared.look == .etiket ? Etiket.lime : ThingsColor.accent
        let light = scheme == .light
        let inner = light ? ThingsColor.textSecondary : Color.black.opacity(0.9)
        let drop = light ? ThingsColor.textSecondary.opacity(0.6) : Color.black.opacity(0.8)
        Button(action: action) {
            Image(systemName: "star.fill")
                .font(.werk(size: 14))
                .foregroundStyle(fill.shadow(.inner(color: isHovering ? .clear : inner, radius: 0.6, x: 0.35, y: 0.9)))
            .offset(y: isHovering ? -1.5 : 0)
            .shadow(color: isHovering ? drop : .clear, radius: 0.8, y: 1.5)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.2)) { isHovering = hovering }
        }
        .help("Ster eraf")
        .accessibilityLabel("Ster eraf")
    }
}

// MARK: - Keuze over de kolommen

/// Zolang er meer mails gekozen zijn (⌘-klik, ook in verschillende kolommen): in plaats van de mailboxknoppen.
private struct ColumnsChoiceBar: View {
    private let store = MailColumnsStore.shared

    var body: some View {
        let chosen = store.chosenMails
        let etiket = ThemeStore.shared.look == .etiket
        let anyUnread = chosen.contains(where: \.isUnread)
        let allStarred = chosen.allSatisfy { store.isStarred($0) }
        HStack(spacing: 6) {
            Text(caption("\(chosen.count) gekozen"))
                .font(.werk(size: 12, weight: .semibold))
                .tracking(etiket ? 1.8 : 0)
                .foregroundStyle(ThingsColor.backgroundContent)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: etiket ? 0 : min(6, ThingsMetrics.cardRadius), style: .continuous)
                    .fill(ThingsColor.textPrimary))
            Button { store.archiveChosen() } label: {
                Label(caption("Archiveer"), systemImage: "archivebox")
            }
            .buttonStyle(ChoiceButtonStyle(kind: .primary))
            Button { store.toggleUnreadChosen() } label: {
                Label(caption(anyUnread ? "Gelezen" : "Ongelezen"), systemImage: anyUnread ? "envelope.open" : "envelope.badge")
            }
            .buttonStyle(ChoiceButtonStyle(kind: .plain))
            Button { store.toggleStarChosen() } label: {
                Label(caption(allStarred ? "Ster eraf" : "Ster"), systemImage: allStarred ? "star.slash" : "star")
            }
            .buttonStyle(ChoiceButtonStyle(kind: .plain))
            Button { store.trashChosen() } label: {
                Label(caption("Verwijder"), systemImage: "trash")
            }
            .buttonStyle(ChoiceButtonStyle(kind: .danger))
            .help("Naar de prullenbak in Gmail (⌘Z zet ze terug)")
            Button { store.clearChoice() } label: {
                Image(systemName: "xmark")
                    .font(.werk(size: 11, weight: .semibold))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Niets meer gekozen (Esc)")
        }
    }

    private func caption(_ text: String) -> String {
        ThemeStore.shared.look == .etiket ? text.uppercased() : text
    }
}

private struct ChoiceButtonStyle: ButtonStyle {
    enum Kind { case primary, plain, danger }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        let etiket = ThemeStore.shared.look == .etiket
        let shape = RoundedRectangle(cornerRadius: etiket ? 0 : min(6, ThingsMetrics.cardRadius), style: .continuous)
        let tint: Color = kind == .danger ? ThingsColor.deadline : ThingsColor.textPrimary
        return configuration.label
            .labelStyle(.titleAndIcon)
            .font(.werk(size: 12, weight: .semibold))
            .tracking(etiket ? 1.8 : 0)
            .foregroundStyle(kind == .primary ? (etiket ? Etiket.ink : ThingsColor.onAccent) : tint)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(shape.fill(kind == .primary ? (etiket ? Etiket.lime : ThingsColor.accent) : Color.clear))
            .overlay {
                if kind != .primary { shape.strokeBorder(tint, lineWidth: 1) }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
