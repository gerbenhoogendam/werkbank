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

    var body: some View {
        VStack(spacing: 0) {
            MailModeToolbar()
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            HStack(spacing: 0) {
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
              !PanelStore.shared.hasFocusPanels else { return false }
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
        case .task, .time, .plan, .follow, .claude: return false
        }
        return true
    }
}

// MARK: - Werkbalk

private struct MailModeToolbar: View {
    private let store = MailModeStore.shared
    private let gmail = GmailSession.shared

    var body: some View {
        HStack(spacing: 12) {
            Button { store.close() } label: {
                Label("Werkbank", systemImage: "chevron.left")
            }
            .buttonStyle(MailModeButtonStyle())
            .help("Terug naar Werkbank (Esc)")

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
                    TextField("Zoeken in \(store.client ?? store.title(of: store.scope))",
                              text: Binding(get: { store.query }, set: { store.setQuery($0) }))
                        .textFieldStyle(.plain)
                        .font(.werk(size: 13))
                        .focused($searchFocused)
                        .onExitCommand { searchFocused = false }
                    KeyCap(key: MailModeKeys.key(for: .search))
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).fill(ThingsColor.cardBackground))
                .overlay(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).strokeBorder(ThingsColor.separator))

                WrapStack(spacing: 6) {
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

            ThemedHeading(title: store.client ?? store.title(of: store.scope), count: store.listed.count)
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
        GmailRow(message: item.summary,
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
        if store.client == nil, let client = store.clientName(for: item) { tags.append(MailRowTag(text: client)) }
        let kind = store.kind(of: item)
        if kind != .person { tags.append(MailRowTag(text: kind.title)) }
        if store.hasTask(item) { tags.append(MailRowTag(text: "Taak", systemImage: "checkmark.circle", highlighted: true)) }
        if item.mayHaveAttachment { tags.append(MailRowTag(text: "Bijlage", systemImage: "paperclip")) }
        if !item.isInInbox && !item.isSent { tags.append(MailRowTag(text: "Gearchiveerd", systemImage: "archivebox")) }
        return tags
    }

    /// Nieuwsbrieven en meldingen samen in één rij; openklappen zet ze in de lijst.
    private var bundleRow: some View {
        let bundle = store.bundle
        return Button {
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
        .padding(.horizontal, MailLook.cardRows ? 0 : 8)
        .padding(.vertical, 6)
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
                Rectangle().fill(ThingsColor.separator).frame(height: 1)
                MailWindowView(ref: MailRef(message: item.summary), embedded: true, trigger: store.replyTrigger,
                               onReplySent: { store.archiveAfterSending(threadID: item.threadID, appState: appState) })
                    .id(item.threadID)
            }
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
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(ThingsColor.backgroundSidebar)
    }
}

// MARK: - Klanten

private struct MailModeClients: View {
    private let store = MailModeStore.shared
    private let directory = ClientDirectory.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ThemedHeading(title: "Klanten", detail: "Meeste mail · 30 dagen")
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
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(ThingsColor.backgroundContent)
        .onChange(of: directory.domainMap) { _, _ in store.refreshRanking() }
    }
}

/// Een klant met hoeveel mail er de laatste dertig dagen was, een balk en de vier weken als staafjes.
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
                HStack(alignment: .bottom, spacing: 2) {
                    let top = max(1, rank.weeks.max() ?? 1)
                    ForEach(Array(rank.weeks.enumerated()), id: \.offset) { index, value in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(index == rank.weeks.count - 1 ? ThingsColor.accent : ThingsColor.accent.opacity(0.35))
                            .frame(width: 4, height: max(2, 20 * CGFloat(value) / CGFloat(top)))
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
        .accessibilityLabel("\(rank.name), \(rank.count) mails in dertig dagen")
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
