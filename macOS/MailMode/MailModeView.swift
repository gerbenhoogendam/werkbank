import AppKit
import SwiftUI
import WerkbankCore

/// De mailmodus: het hele venster als mailclient (dubbelklik op Mail). Links de lijst met zoeken en filters, in het
/// midden de gekozen mail (altijd wit), rechts de klanten op volgorde van contact. Elke handeling heeft een toets.
struct MailModeView: View {
    @Environment(AppState.self) private var appState
    private let store = MailModeStore.shared
    private let gmail = GmailSession.shared

    @State private var window: NSWindow?
    @State private var keyMonitor: Any?
    @AppStorage(MailModeFolders.visibleKey) private var showsFolders = true

    var body: some View {
        VStack(spacing: 0) {
            MailModeToolbar()
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            HStack(spacing: 0) {
                if showsFolders {
                    MailModeFolders()
                        .frame(width: 200)
                    Rectangle().fill(ThingsColor.separator).frame(width: 1)
                }
                MailModeList()
                    .frame(width: 380)
                Rectangle().fill(ThingsColor.separator).frame(width: 1)
                MailModeReader()
                    .frame(maxWidth: .infinity)
                Rectangle().fill(ThingsColor.separator).frame(width: 1)
                MailModeClients()
                    .frame(width: 290)
            }
        }
        .background(ThingsColor.backgroundSidebar)
        .overlay {
            if let sheet = store.sheet, !sheet.needsMail || store.selected != nil {
                MailModeSheetHost(sheet: sheet, item: store.selected)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: store.sheet)
        .background(WindowReader(window: $window))
        .onAppear(perform: installKeys)
        .onDisappear(perform: removeKeys)
    }

    // MARK: Toetsen

    /// Toetsen zonder ⌘ werken overal in de mailmodus, behalve in een tekstveld (zoeken, antwoord) of als er een
    /// paneel open staat.
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
        guard store.isActive, let window, event.window === window, window.attachedSheet == nil,
              !PanelStore.shared.hasFocusPanels, !FeedbackOverlay.shared.isShown else { return false }
        if store.sheet != nil {
            // In een blad gaan alle toetsen naar het blad; Esc sluit het.
            guard event.keyCode == 53 else { return false }
            store.closeSheet()
            return true
        }
        // ⌘F: uitgebreid zoeken, ook vanuit een tekstveld.
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            store.openSheet(.search)
            return true
        }
        if window.firstResponder is NSText { return false }
        if event.keyCode == 53 {
            store.close()
            return true
        }
        guard let action = MailModeKeys.action(for: event) else { return false }
        return perform(action)
    }

    private func perform(_ action: MailModeAction) -> Bool {
        switch action {
        case .archive: store.archiveSelected(appState: appState)
        case .reply:
            guard store.selected != nil else { return false }
            store.replyTrigger.reply()
        case .scope: store.cycleScope()
        case .search: store.requestSearchFocus()
        case .next: store.selectNext()
        case .previous: store.selectPrevious()
        case .task, .time, .plan, .follow, .claude:
            guard store.selected != nil else { return false }
            store.openSheet(Self.sheet(for: action))
        }
        return true
    }

    static func sheet(for action: MailModeAction) -> MailModeSheet {
        switch action {
        case .time: .time
        case .plan: .plan
        case .follow: .follow
        case .claude: .concept
        default: .task
        }
    }
}

// MARK: - Werkbalk

private struct MailModeToolbar: View {
    private let store = MailModeStore.shared
    private let gmail = GmailSession.shared
    @AppStorage(MailModeFolders.visibleKey) private var showsFolders = true

    var body: some View {
        HStack(spacing: 12) {
            Button { store.close() } label: {
                Label("Werkbank", systemImage: "chevron.left")
            }
            .buttonStyle(MailModeButtonStyle())
            .help("Terug naar Werkbank (Esc)")

            Button { showsFolders.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(MailModeButtonStyle(prominent: false))
            .accessibilityLabel("Mappen")

            MailHeaderTitle(title: "Mail", unread: store.items.filter(\.isUnread).count, total: store.items.count,
                            mailbox: store.title(of: store.scope))
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { store.close() }

            if store.scopes.count > 1 {
                HStack(spacing: 6) {
                    ForEach(store.scopes, id: \.self) { scope in
                        MailboxTab(title: store.title(of: scope), isOn: store.client == nil && scope == store.scope) {
                            store.select(scope: scope)
                        }
                        .fixedSize()
                    }
                    Button { store.cycleScope() } label: {
                        KeyCap(key: MailModeKeys.key(for: .scope))
                    }
                    .buttonStyle(.plain)
                    .help("Volgende mailbox of combinatie")
                    .accessibilityLabel("Volgende mailbox of combinatie")
                }
                .padding(.leading, 8)
            }
            Spacer(minLength: 8)
            if store.isLoading { ProgressView().controlSize(.small) }
            Button {
                PanelStore.shared.open(.compose(ComposeRef(mode: .new, source: nil)))
            } label: {
                Label("Nieuwe mail", systemImage: "square.and.pencil")
            }
            .buttonStyle(MailModeButtonStyle(prominent: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .background(ThingsColor.mailHeaderBackground)
        .darkScheme(ThemeStore.shared.theme.darkMailHeader)
    }
}

// MARK: - Lijst

private struct MailModeList: View {
    @Environment(AppState.self) private var appState
    private let store = MailModeStore.shared
    private let gmail = GmailSession.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.werk(size: 12, weight: .medium))
                        .foregroundStyle(ThingsColor.textSecondary)
                    TextField("Zoeken in \(store.searchTitle)",
                              text: Binding(get: { store.query }, set: { store.setQuery($0) }))
                        .textFieldStyle(.plain)
                        .font(.werk(size: 13))
                        .focused($searchFocused)
                        .onExitCommand { searchFocused = false }
                    KeyCap(key: MailModeKeys.key(for: .search))
                    Button { store.openSheet(.search) } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.werk(size: 12, weight: .medium))
                            .foregroundStyle(ThingsColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Uitgebreid zoeken (⌘F)")
                    .accessibilityLabel("Uitgebreid zoeken")
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).fill(ThingsColor.cardBackground))
                .overlay(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).strokeBorder(ThingsColor.separator))

                WrapStack(spacing: 6) {
                    if let mailboxes = store.searchAccounts {
                        Button { store.clearSearchAccounts() } label: {
                            HStack(spacing: 5) {
                                Text(mailboxes.count == 1 ? GmailSession.shared.displayName(mailboxes[0])
                                     : "\(mailboxes.count) mailboxen")
                                Image(systemName: "xmark").font(.werk(size: 8, weight: .bold))
                            }
                        }
                        .buttonStyle(MailFilterChipStyle(isOn: true))
                    }
                    if let client = store.client {
                        Button { store.showClient(nil) } label: {
                            HStack(spacing: 5) {
                                Text(client)
                                Image(systemName: "xmark").font(.werk(size: 8, weight: .bold))
                            }
                        }
                        .buttonStyle(MailFilterChipStyle(isOn: true))
                        .help("Klantfilter wissen")
                    }
                    ForEach(MailModeStore.Filter.allCases) { filter in
                        Button(filter.title) { store.toggle(filter) }
                            .buttonStyle(MailFilterChipStyle(isOn: store.filters.contains(filter)))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle().fill(ThingsColor.separator).frame(height: 1)

            ThemedHeading(title: store.listTitle, count: store.listed.count)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            content
        }
        .background(ThingsColor.mailBackground)
        .darkScheme(ThemeStore.shared.theme.darkMail)
        .onChange(of: store.searchFocusRequest) { _, _ in searchFocused = true }
    }

    @ViewBuilder private var content: some View {
        if let error = store.loadError {
            Text(error)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.deadline)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if store.listed.isEmpty && store.bundle.isEmpty {
            Text(store.isLoading ? "Mail ophalen…" : "Geen mail")
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: MailLook.cardRows ? 2 : 0) {
                        if !store.bundle.isEmpty { bundleRow }
                        ForEach(store.sections) { section in
                            Text(section.id)
                                .font(.werk(size: 11, weight: .semibold))
                                .foregroundStyle(ThingsColor.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                            ForEach(section.items) { item in
                                row(item).id(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, MailLook.cardRows ? 8 : 0)
                    .padding(.bottom, 12)
                }
                .onChange(of: store.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func row(_ item: GmailMailItem) -> some View {
        GmailRow(message: store.rowSummary(item),
                 isBusy: gmail.busyMessageIDs.contains(item.id),
                 isSelected: store.selectedID == item.id,
                 accountLabel: store.showsAccounts ? gmail.account(for: item.id).map(gmail.displayName) : nil,
                 tags: tags(for: item),
                 onOpen: { store.select(item) },
                 onSelect: { store.select(item) },
                 onArchive: {
                     store.select(item)
                     store.archiveSelected(appState: appState)
                 },
                 onDragStarted: { MailDragState.shared.begin(account: gmail.account(for: item.id)) })
    }

    private func tags(for item: GmailMailItem) -> [MailRowTag] {
        var tags: [MailRowTag] = []
        if let returned = FollowUpStore.shared.returned[item.threadID] {
            tags.append(MailRowTag(text: "Terug · \(returned)", systemImage: "arrow.uturn.backward", highlighted: true))
        }
        if FollowUpStore.shared.items.contains(where: { $0.threadID == item.threadID }) {
            tags.append(MailRowTag(text: "Opvolgen", systemImage: "clock.arrow.circlepath"))
        }
        if store.client == nil, let client = store.clientName(for: item) { tags.append(MailRowTag(text: client)) }
        let kind = store.kind(of: item)
        if kind != .person { tags.append(MailRowTag(text: kind.title)) }
        if store.hasTask(item) { tags.append(MailRowTag(text: "Taak", systemImage: "checkmark.circle", highlighted: true)) }
        if item.mayHaveAttachment { tags.append(MailRowTag(text: "Bijlage", systemImage: "paperclip")) }
        if store.folder == .inbox, !item.isInInbox, !item.isSent {
            tags.append(MailRowTag(text: "Gearchiveerd", systemImage: "archivebox"))
        }
        return tags
    }

    /// Nieuwsbrieven en meldingen samen in één rij; openklappen zet ze in de lijst.
    private var bundleRow: some View {
        let bundle = store.bundle
        return HStack(spacing: 6) {
            bundleToggle(bundle)
            Button("Archiveren…") { store.openSheet(.bulk) }
                .buttonStyle(MailModeButtonStyle())
        }
        .padding(.horizontal, MailLook.cardRows ? 0 : 8)
        .padding(.vertical, 6)
    }

    private func bundleToggle(_ bundle: [GmailMailItem]) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { store.bundleOpen.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "tray.full")
                    .font(.werk(size: 14))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).fill(ThingsColor.cardBackground))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nieuwsbrieven en meldingen · \(bundle.count)")
                        .font(.werk(size: 12.5, weight: .semibold))
                        .foregroundStyle(ThingsColor.textPrimary)
                    Text(Array(Set(bundle.map(\.senderDisplay))).sorted().joined(separator: ", "))
                        .font(.werk(size: 11.5))
                        .foregroundStyle(ThingsColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: store.bundleOpen ? "chevron.up" : "chevron.down")
                    .font(.werk(size: 10, weight: .semibold))
                    .foregroundStyle(ThingsColor.textSecondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).fill(ThingsColor.tagBackground.opacity(0.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mappen

/// De mappen van Gmail voor het bereik (Postvak IN, Verstuurd …) en per mailbox de eigen labels, als boom.
struct MailModeFolders: View {
    static let visibleKey = "mailMode.showsFolders"
    private let store = MailModeStore.shared
    private let gmail = GmailSession.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(MailFolder.standard, id: \.self) { folder in
                    row(folder, depth: 0)
                }
                ForEach(store.scopeAccounts, id: \.self) { account in
                    let labels = store.labelsByAccount[account] ?? []
                    if !labels.isEmpty {
                        ThemedHeading(title: gmail.displayName(account))
                            .padding(.horizontal, 8)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                        ForEach(labels) { label in
                            row(.label(account: account, id: label.id, name: label.name), depth: label.depth)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.never)
        .background(ThingsColor.backgroundSidebar)
    }

    private func row(_ folder: MailFolder, depth: Int) -> some View {
        let isOn = store.client == nil && store.folder == folder
        return Button { store.select(folder: folder) } label: {
            HStack(spacing: 7) {
                Image(systemName: Self.icon(folder))
                    .font(.werk(size: 12, weight: .medium))
                    .foregroundStyle(isOn ? ThingsColor.accent : ThingsColor.textSecondary)
                    .frame(width: 16)
                Text(folder.title)
                    .font(.werk(size: 12.5, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 8 + CGFloat(depth) * 14)
            .padding(.trailing, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous)
                .fill(isOn ? ThingsColor.selection : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func icon(_ folder: MailFolder) -> String {
        switch folder {
        case .inbox: "tray"
        case .starred: "star"
        case .sent: "paperplane"
        case .all: "archivebox"
        case .spam: "xmark.bin"
        case .trash: "trash"
        case .label: "folder"
        }
    }
}

// MARK: - Gekozen mail

private struct MailModeReader: View {
    @Environment(AppState.self) private var appState
    private let store = MailModeStore.shared

    var body: some View {
        if let item = store.selected {
            VStack(alignment: .leading, spacing: 0) {
                header(item)
                if let proposal = store.proposalsByID[item.id]?.first {
                    proposalBanner(proposal)
                }
                Rectangle().fill(ThingsColor.separator).frame(height: 1)
                MailWindowView(ref: MailRef(message: item.summary), embedded: true, trigger: store.replyTrigger,
                               onReplySent: { store.archiveAfterSending(threadID: item.threadID, appState: appState) })
                    .id(item.threadID)
            }
            .task(id: item.id) { await store.proposals(for: item) }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.werk(size: 34, weight: .light))
                    .foregroundStyle(ThingsColor.textTertiary)
                Text(store.isLoading ? "Mail ophalen…" : "Geen mail gekozen")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ item: GmailMailItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.subject.isEmpty ? "(geen onderwerp)" : item.subject)
                        .font(.werk(size: 20, weight: .semibold))
                        .foregroundStyle(ThingsColor.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        if let account = GmailSession.shared.account(for: item.id), !account.isEmpty {
                            Text(GmailSession.shared.displayName(account))
                                .font(.werk(size: 11, weight: .medium))
                                .foregroundStyle(ThingsColor.tagText)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ThingsColor.tagBackground))
                        }
                        if let client = store.clientName(for: item) {
                            HStack(spacing: 5) {
                                ClientLogo(name: client, size: 14)
                                Text(client)
                            }
                            .font(.werk(size: 11, weight: .medium))
                            .foregroundStyle(ThingsColor.textPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(ThingsColor.separator))
                        }
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Button { store.selectPrevious() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                            KeyCap(key: MailModeKeys.key(for: .previous))
                        }
                    }
                    .buttonStyle(MailModeButtonStyle())
                    .accessibilityLabel("Vorige mail")
                    Button { store.selectNext() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                            KeyCap(key: MailModeKeys.key(for: .next))
                        }
                    }
                    .buttonStyle(MailModeButtonStyle())
                    .accessibilityLabel("Volgende mail")
                }
            }
            WrapStack(spacing: 6) {
                MailActionButton(title: "Archiveren", systemImage: "archivebox", action: .archive, prominent: true) {
                    store.archiveSelected(appState: appState)
                }
                MailActionButton(title: "Beantwoorden", systemImage: "arrowshape.turn.up.left", action: .reply) {
                    store.replyTrigger.reply()
                }
                MailActionButton(title: "Taak", systemImage: "checkmark.circle", action: .task) { store.openSheet(.task) }
                MailActionButton(title: "Tijd schrijven", systemImage: "clock", action: .time) { store.openSheet(.time) }
                MailActionButton(title: "Inplannen", systemImage: "calendar", action: .plan) { store.openSheet(.plan) }
                MailActionButton(title: "Opvolgen", systemImage: "arrow.uturn.backward.circle", action: .follow) {
                    store.openSheet(.follow)
                }
                MailActionButton(title: "Concept", systemImage: "sparkles", action: .claude) { store.openSheet(.concept) }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(ThingsColor.backgroundSidebar)
    }

    /// Een datum of tijd uit de mail, met Inplannen ernaast.
    private func proposalBanner(_ proposal: DateProposal) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.werk(size: 13, weight: .medium))
                .foregroundStyle(ThingsColor.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Voorstel in deze mail")
                    .font(.werk(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fieldLabel)
                Text(proposal.hasTime
                     ? "\(DutchDate.weekdayAndDay(proposal.start)) · \(DutchDate.time(proposal.start))–\(DutchDate.time(proposal.end))"
                     : DutchDate.weekdayAndDay(proposal.start))
                    .font(.werk(size: 13, weight: .medium))
                    .foregroundStyle(ThingsColor.textPrimary)
            }
            Spacer(minLength: 8)
            MailActionButton(title: "Inplannen", systemImage: "calendar", action: .plan) { store.openSheet(.plan) }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
        .background(ThingsColor.selection.opacity(0.35))
    }
}

// MARK: - Klanten

private struct MailModeClients: View {
    private let store = MailModeStore.shared
    private let directory = ClientDirectory.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ThemedHeading(title: "Klanten", detail: updatedDetail)
                    if MailActivityStore.shared.isSyncing {
                        ProgressView().controlSize(.mini)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.werk(size: 11, weight: .medium))
                        .foregroundStyle(ThingsColor.textSecondary)
                    TextField("Klant zoeken", text: Binding(get: { store.clientQuery }, set: { store.clientQuery = $0 }))
                        .textFieldStyle(.plain)
                        .font(.werk(size: 12.5))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).fill(ThingsColor.cardBackground))
                .overlay(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).strokeBorder(ThingsColor.separator))
            }
            .padding(14)

            Rectangle().fill(ThingsColor.separator).frame(height: 1)

            let rows = store.clientRows
            if rows.isEmpty {
                Text(directory.records.isEmpty ? "Nog geen klantenlijst" : "Geen klanten")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxCount = max(1, store.ranking.first?.count ?? 1)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.name) { index, rank in
                            ClientActivityRow(rank: rank, position: index + 1, maxCount: maxCount,
                                              isOn: store.client == rank.name) {
                                store.showClient(rank.name)
                            }
                            .contextMenu {
                                Button("Geen klant") { store.excludeClient(rank.name) }
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(ThingsColor.backgroundContent)
        .onChange(of: directory.domainMap) { _, _ in store.refreshRanking() }
    }

    /// "3 maanden · vandaag 08:12": hoe ver terug en wanneer de lijst is bijgewerkt.
    private var updatedDetail: String {
        guard let date = MailActivityStore.shared.lastUpdate(for: GmailSession.shared.accounts) else { return "3 maanden" }
        let day = Calendar.current.isDateInToday(date) ? "vandaag" : DutchDate.short(date)
        return "3 maanden · \(day) \(DutchDate.time(date))"
    }
}

/// Een klant met hoeveel mail er de laatste drie maanden was, een balk en de weken als staafjes.
private struct ClientActivityRow: View {
    let rank: ClientActivity.Rank
    let position: Int
    let maxCount: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(position)")
                    .font(.werk(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(ThingsColor.textTertiary)
                    .frame(width: 18, alignment: .trailing)
                ClientLogo(name: rank.name, size: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(rank.name)
                        .font(.werk(size: 12.5, weight: .semibold))
                        .foregroundStyle(ThingsColor.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ThingsColor.separator)
                                Capsule().fill(ThingsColor.accent)
                                    .frame(width: geo.size.width * CGFloat(rank.count) / CGFloat(maxCount))
                            }
                        }
                        .frame(height: 4)
                        Text(rank.count == 1 ? "1 mail" : "\(rank.count) mails")
                            .font(.werk(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(ThingsColor.textSecondary)
                            .fixedSize()
                    }
                }
                HStack(alignment: .bottom, spacing: 1.5) {
                    let top = max(1, rank.weeks.max() ?? 1)
                    ForEach(Array(rank.weeks.enumerated()), id: \.offset) { index, value in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(index == rank.weeks.count - 1 ? ThingsColor.accent : ThingsColor.accent.opacity(0.35))
                            .frame(width: 3, height: max(2, 20 * CGFloat(value) / CGFloat(top)))
                    }
                }
                .frame(height: 20, alignment: .bottom)
                .accessibilityHidden(true)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous)
                .fill(isOn ? ThingsColor.selection : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rank.name), \(rank.count) mails in drie maanden")
    }
}

// MARK: - Onderdelen

enum MailModeMetrics {
    /// Afronding van velden, knoppen en rijen: volgt het thema (Karmijn recht), hooguit 8.
    static var radius: CGFloat { min(8, max(2, ThingsMetrics.cardRadius)) }
}

/// Een toets zoals op het toetsenbord, naast een knop.
struct KeyCap: View {
    let key: String
    var inverted = false

    var body: some View {
        Text(key)
            .font(.werk(size: 10, weight: .semibold))
            .foregroundStyle(inverted ? ThingsColor.backgroundContent : ThingsColor.textSecondary)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(inverted ? Color.white.opacity(0.14) : ThingsColor.backgroundContent))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(inverted ? Color.white.opacity(0.28) : ThingsColor.separator))
            .accessibilityHidden(true)
    }
}

/// Een handeling op de gekozen mail: naam, en de toets erachter. Archiveren is de volle knop.
struct MailActionButton: View {
    let title: String
    let systemImage: String
    let action: MailModeAction
    var prominent = false
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.werk(size: 12, weight: .medium))
                Text(title).font(.werk(size: 12.5, weight: prominent ? .semibold : .medium))
                KeyCap(key: MailModeKeys.key(for: action), inverted: prominent)
            }
            .foregroundStyle(prominent ? ThingsColor.backgroundContent : ThingsColor.textPrimary)
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous)
                .fill(prominent ? ThingsColor.textPrimary : ThingsColor.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous)
                .strokeBorder(prominent ? Color.clear : ThingsColor.separator))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) (\(MailModeKeys.key(for: action)))")
    }
}

/// Knoppen in de werkbalk van de mailmodus, in de kleuren van het thema.
struct MailModeButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.werk(size: 12.5, weight: prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? Color.white : ThingsColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous)
                .fill(prominent ? ThingsColor.accent : ThingsColor.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous)
                .strokeBorder(prominent ? Color.clear : ThingsColor.separator))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// Een filter onder het zoekveld: aan is vol in de accentkleur.
struct MailFilterChipStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.werk(size: 11.5, weight: .medium))
            .foregroundStyle(isOn ? Color.white : ThingsColor.textPrimary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: min(6, MailModeMetrics.radius), style: .continuous)
                .fill(isOn ? ThingsColor.accent : ThingsColor.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: min(6, MailModeMetrics.radius), style: .continuous)
                .strokeBorder(isOn ? Color.clear : ThingsColor.separator))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Zet knoppen naast elkaar en begint een nieuwe regel als het niet meer past.
struct WrapStack: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Het venster van een view, om toetsen alleen in dat venster af te vangen.
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if window !== view.window {
            DispatchQueue.main.async { window = view.window }
        }
    }
}
