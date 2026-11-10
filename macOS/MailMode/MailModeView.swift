import AppKit
import SwiftUI
import UniformTypeIdentifiers
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
    @AppStorage(MailModeClients.visibleKey) private var showsClients = true
    // De breedte van de kolommen: te verslepen aan de lijn ertussen, dubbelklik zet terug.
    @AppStorage("mailMode.foldersWidth") private var foldersWidth = Self.defaultFolders
    @AppStorage("mailMode.listWidth") private var listWidth = Self.defaultList
    @AppStorage("mailMode.clientsWidth") private var clientsWidth = Self.defaultClients
    @State private var dragStart: Double?

    private static let defaultFolders = 200.0
    private static let defaultList = 380.0
    private static let defaultClients = 290.0
    private static let foldersRange = 150.0...380.0
    private static let listRange = 280.0...720.0
    private static let clientsRange = 220.0...480.0

    var body: some View {
        VStack(spacing: 0) {
            MailModeToolbar()
            if ThemeStore.shared.look != .puls {
                Rectangle().fill(ThingsColor.separator).frame(height: 1)
            }
            HStack(spacing: 0) {
                if ThemeStore.shared.look == .tischsuper { Veneer(vertical: true).frame(width: 7) }
                if showsFolders {
                    MailModeFolders()
                        .frame(width: clamp(foldersWidth, Self.foldersRange))
                    ColumnResizer(onChanged: { foldersWidth = resized(foldersWidth, by: $0, Self.foldersRange) },
                                  onEnded: { dragStart = nil },
                                  onReset: { foldersWidth = Self.defaultFolders })
                }
                MailModeList()
                    .pulsTile()
                    .frame(width: clamp(listWidth, Self.listRange))
                ColumnResizer(onChanged: { listWidth = resized(listWidth, by: $0, Self.listRange) },
                              onEnded: { dragStart = nil },
                              onReset: { listWidth = Self.defaultList })
                MailModeReader()
                    .pulsTile()
                    .frame(minWidth: 320, maxWidth: .infinity)
                if showsClients {
                    ColumnResizer(onChanged: { clientsWidth = resized(clientsWidth, by: -$0, Self.clientsRange) },
                                  onEnded: { dragStart = nil },
                                  onReset: { clientsWidth = Self.defaultClients })
                    MailModeClients()
                        .pulsTile()
                        .frame(width: clamp(clientsWidth, Self.clientsRange))
                }
                if ThemeStore.shared.look == .tischsuper { Veneer(vertical: true).frame(width: 7) }
            }
        }
        .background(ThemeStore.shared.look == .puls ? ThingsColor.window : ThingsColor.backgroundSidebar)
        .overlay {
            if let sheet = store.sheet, !sheet.needsMail || store.selected != nil {
                MailModeSheetHost(sheet: sheet, item: store.selected)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: store.sheet)
        .background(WindowReader(window: $window))
        .onChange(of: store.selectedID) { _, _ in store.prefetchAfterSelection() }
        .onAppear(perform: installKeys)
        .onDisappear(perform: removeKeys)
    }

    private func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// De nieuwe breedte tijdens slepen: vanaf de breedte bij het begin van het slepen.
    private func resized(_ current: Double, by translation: CGFloat, _ range: ClosedRange<Double>) -> Double {
        let start = dragStart ?? current
        dragStart = start
        return clamp(start + Double(translation), range)
    }

    // MARK: Toetsen

    /// De toetsen werken overal in de mailmodus, behalve als er een paneel open staat; in een tekstveld (zoeken,
    /// antwoord) alleen combinaties met ⌘, ⌃ of ⌥.
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
              !FeedbackOverlay.shared.isShown else { return false }
        // Weggezwiept voor het slepen: de toetsen zijn van de werkbank; Esc haalt de mail terug (MailModeStore).
        if store.isReceded { return false }
        guard !PanelStore.shared.hasFocusPanels else { return false }
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
        let typing = window.firstResponder is NSText
        if !typing, event.keyCode == 53 {
            // Eerst de selectie van meer mails opheffen, daarna pas de mailmodus dicht.
            if store.isMarking { store.clearMarks() } else { store.close() }
            return true
        }
        guard let action = MailModeKeys.action(for: event) else { return false }
        // In een tekstveld is een losse toets gewoon tekst; een combinatie met ⌘, ⌃ of ⌥ werkt ook daar.
        if typing, !MailModeKeys.hasModifiers(MailModeKeys.key(for: action)) { return false }
        return perform(action)
    }

    private func perform(_ action: MailModeAction) -> Bool {
        switch action {
        case .archive: store.archiveSelected(appState: appState)
        case .reply:
            guard store.selected != nil, !store.isMarking else { return false }
            store.replyTrigger.reply()
        case .scope: store.cycleScope()
        case .search: store.requestSearchFocus()
        case .next: store.selectNext()
        case .previous: store.selectPrevious()
        case .task, .time, .plan, .follow, .claude:
            guard store.selected != nil, !store.isMarking else { return false }
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
    @Environment(AppState.self) private var appState
    private let store = MailModeStore.shared
    private let gmail = GmailSession.shared
    @AppStorage(MailModeFolders.visibleKey) private var showsFolders = true
    @AppStorage(MailModeClients.visibleKey) private var showsClients = true

    var body: some View {
        HStack(spacing: 12) {
            // Terug naar de werkbank staat in de werkbalk van het venster, naast de vensterknopjes (MainView).
            Button { showsFolders.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(MailModeButtonStyle(prominent: false))
            .accessibilityLabel("Mappen")

            MailHeaderTitle(title: "Mail", unread: store.items.filter(\.isUnread).count, total: store.items.count,
                            mailbox: store.title(of: store.scope))
                .lineLimit(1)
                // Zo breed als de titel: de mailboxen staan er direct naast, links.
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { store.close() }

            if store.scopes.count > 1 {
                HStack(spacing: 6) {
                    // Puls: de mailboxen als gesegmenteerde keuze op een grijs spoor.
                    HStack(spacing: ThemeStore.shared.look == .puls ? 0 : 6) {
                        ForEach(store.scopes, id: \.self) { scope in
                            // De eigen combinatie staat al als aangevinkte mailboxen; geen aparte knop.
                            if case .combination = scope, scope == store.scope {
                                EmptyView()
                            } else {
                                MailboxTab(title: store.title(of: scope), isOn: store.client == nil && isOn(scope),
                                           fitsContent: true) {
                                    tap(scope)
                                }
                                .fixedSize()
                                .help(scopeHelp(scope))
                                // Een mail erop loslaten: naar de inbox van die mailbox.
                                .modifier(MailModeDropTarget(isEnabled: mailbox(of: scope) != nil) { payload in
                                    if let account = mailbox(of: scope) { store.drop(payload, onMailbox: account, appState: appState) }
                                })
                            }
                        }
                    }
                    .padding(ThemeStore.shared.look == .puls ? 2 : 0)
                    .background {
                        if ThemeStore.shared.look == .puls {
                            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Puls.track)
                        }
                    }
                }
                .padding(.leading, 8)
            }
            Spacer(minLength: 8)
            // Verversen; tijdens het laden draait het wiel in de knop (blijft klikbaar als het laden blijft hangen).
            Button { store.refreshNow() } label: {
                Group {
                    if store.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.werk(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThingsColor.textSecondary)
            .help("Verversen")
            .accessibilityLabel("Verversen")
            if !showsClients {
                // De klantenkolom is weggeklikt: een blauw rondje haalt hem terug.
                Button { showsClients = true } label: {
                    Image(systemName: "person.2.fill")
                        .font(.werk(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(ThemeStore.shared.look == .puls ? Puls.blauw.solid : ThingsColor.accent))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Klanten tonen")
                .accessibilityLabel("Klanten tonen")
            }
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
        .background {
            // Tischsuper: de kop is notenhoutfineer, zoals de kast van de RT 20.
            if ThemeStore.shared.look == .tischsuper {
                Veneer()
            } else {
                ThemeStore.shared.look == .puls ? ThingsColor.window : ThingsColor.mailHeaderBackground
            }
        }
        // Lichte tekst op een donkere kop (ook als alleen de mail donker is, zoals bij Tischsuper).
        .darkScheme(ThemeStore.shared.theme.darkMailHeader || ThemeStore.shared.theme.darkMail
                    || ThemeStore.shared.look == .tischsuper)
    }

    /// Een mailbox staat aan als hij gekozen is of in de combinatie zit; Alle mail en de combinatie van het
    /// Mail-paneel alleen als die zelf gekozen zijn.
    private func isOn(_ scope: MailModeStore.Scope) -> Bool {
        if case .account(let email) = scope { return store.includes(email) }
        return scope == store.scope
    }

    /// Klik: alleen deze mailbox (of Alle mail). ⌘-klik op een mailbox: erbij zetten of eruit halen.
    private func tap(_ scope: MailModeStore.Scope) {
        if case .account(let email) = scope, NSEvent.modifierFlags.contains(.command) {
            store.toggleInScope(email)
        } else {
            store.select(scope: scope)
        }
    }

    /// De mailbox van een tab (niet de combinatie of Alle mail).
    private func mailbox(of scope: MailModeStore.Scope) -> String? {
        if case .account(let email) = scope { return email }
        return nil
    }

    private func scopeHelp(_ scope: MailModeStore.Scope) -> String {
        if case .account(let email) = scope { return "\(email) · ⌘-klik om te combineren" }
        return store.title(of: scope)
    }
}

// MARK: - Lijst

private struct MailModeList: View {
    @Environment(AppState.self) private var appState
    private let store = MailModeStore.shared
    private let gmail = GmailSession.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        // Eén keer per weergave uitrekenen: de kop, de lijst en de bundel vragen er allemaal om.
        let listed = store.listed
        let bundle = store.bundle
        return VStack(alignment: .leading, spacing: 0) {
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
                .mailSearchField()

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

            if store.isMarking {
                markedBar(listed.filter { store.markedIDs.contains($0.id) })
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            } else {
                ThemedHeading(title: store.listTitle, count: listed.count,
                              unit: listed.count == 1 ? "MAIL" : "MAILS")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            }

            content(listed: listed, bundle: bundle)
        }
        .background(ThingsColor.mailBackground)
        .darkScheme(ThemeStore.shared.theme.darkMail)
        .onChange(of: store.searchFocusRequest) { _, _ in searchFocused = true }
    }

    @ViewBuilder private func content(listed: [GmailMailItem], bundle: [GmailMailItem]) -> some View {
        if let error = store.loadError {
            Text(error)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.deadline)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if listed.isEmpty && bundle.isEmpty {
            Text(store.isLoading ? "Mail ophalen…" : "Geen mail")
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: MailLook.cardRows ? 2 : 0) {
                        if !bundle.isEmpty { bundleRow(bundle) }
                        let following = Set(FollowUpStore.shared.items.map(\.threadID))
                        ForEach(store.sections(of: listed)) { section in
                            Text(section.id)
                                .font(.werk(size: 11, weight: .semibold))
                                .foregroundStyle(ThingsColor.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                            ForEach(section.items) { item in
                                row(item, following: following).id(item.id)
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

    /// Meer mails gekozen (⌘- of ⇧-klik): wat ermee moet, boven de lijst.
    private func markedBar(_ marked: [GmailMailItem]) -> some View {
        let labels = store.labelNames(for: marked)
        let mailboxes = store.targetMailboxes(for: marked)
        return VStack(alignment: .leading, spacing: 8) {
            ThemedHeading(title: "\(marked.count) geselecteerd")
            WrapStack(spacing: 6) {
                if store.folder != .trash {
                    Button { store.trashMarked(appState: appState) } label: {
                        Label("Verwijderen", systemImage: "trash")
                    }
                    .buttonStyle(MailModeButtonStyle())
                    .help("Naar de prullenbak (⌘Z zet ze terug)")
                }
                Button { store.archiveMarked(appState: appState) } label: {
                    Label("Archiveren", systemImage: "archivebox")
                }
                .buttonStyle(MailModeButtonStyle(prominent: true))
                if !labels.isEmpty {
                    Menu {
                        ForEach(labels, id: \.self) { name in
                            Button(name.replacingOccurrences(of: "/", with: " › ")) {
                                store.moveMarked(toLabel: name, appState: appState)
                            }
                        }
                    } label: {
                        menuLabel("Naar map", systemImage: "folder")
                    }
                    .menuStyle(.button)
                    .buttonStyle(MailModeButtonStyle())
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                if !mailboxes.isEmpty {
                    Menu {
                        ForEach(mailboxes, id: \.self) { account in
                            Button(gmail.displayName(account)) {
                                store.moveMarked(toMailbox: account, appState: appState)
                            }
                        }
                    } label: {
                        menuLabel("Naar postvak", systemImage: "tray.and.arrow.up")
                    }
                    .menuStyle(.button)
                    .buttonStyle(MailModeButtonStyle())
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                Button { store.clearMarks() } label: { Image(systemName: "xmark") }
                    .buttonStyle(MailModeButtonStyle())
                    .help("Selectie opheffen (Esc)")
                    .accessibilityLabel("Selectie opheffen")
            }
        }
    }

    private func menuLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Label(title, systemImage: systemImage)
            Image(systemName: "chevron.down").font(.werk(size: 8, weight: .semibold))
        }
    }

    private func row(_ item: GmailMailItem, following: Set<String>) -> some View {
        GmailRow(message: store.rowSummary(item),
                 isBusy: gmail.busyMessageIDs.contains(item.id),
                 isSelected: store.isChosen(item),
                 accountLabel: store.showsAccounts ? gmail.account(for: item.id).map(gmail.displayName) : nil,
                 tags: tags(for: item, following: following),
                 onOpen: { store.select(item) },
                 showsActionsWhenSelected: !store.isMarking,
                 // ⌘-klik: erbij of eraf; ⇧-klik: een reeks.
                 onSelect: { store.click(item) },
                 onArchive: {
                     // Alleen deze mail, ook als er meer gekozen zijn (daarvoor is de balk boven de lijst).
                     if store.isMarking { store.unmark(item) } else { store.select(item) }
                     store.archive(item, announcing: nil, appState: appState)
                 },
                 // Laat de mailmodus ook wegzwiepen.
                 onDragStarted: { MailDragState.shared.begin(account: gmail.account(for: item.id)) })
    }

    private func tags(for item: GmailMailItem, following: Set<String>) -> [MailRowTag] {
        var tags: [MailRowTag] = []
        if let returned = FollowUpStore.shared.returned[item.threadID] {
            tags.append(MailRowTag(text: "Terug · \(returned)", systemImage: "arrow.uturn.backward", highlighted: true))
        }
        if following.contains(item.threadID) {
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
    private func bundleRow(_ bundle: [GmailMailItem]) -> some View {
        HStack(spacing: 6) {
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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
    @Environment(AppState.self) private var appState
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
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            // Een mail erop loslaten: naar de inbox van deze mailbox.
                            .modifier(MailModeDropTarget(isEnabled: true) { payload in
                                store.drop(payload, onMailbox: account, appState: appState)
                            })
                            .padding(.top, 12)
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
        .background(ThemeStore.shared.look == .puls ? ThingsColor.window : ThingsColor.backgroundSidebar)
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
            .background(RoundedRectangle(cornerRadius: ThemeStore.shared.look == .puls ? 12 : MailModeMetrics.radius,
                                         style: .continuous)
                // Puls: de gekozen map als tegel op het zwart, met een groen icoon.
                .fill(isOn ? (ThemeStore.shared.look == .puls ? ThingsColor.backgroundContent : ThingsColor.selection) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Een mail erop loslaten: naar die map (Alle mail: archiveren; Prullenbak: weggooien).
        .modifier(MailModeDropTarget(isEnabled: MailModeStore.acceptsDrop(folder)) { payload in
            store.drop(payload, on: folder, appState: appState)
        })
    }

    private static func icon(_ folder: MailFolder) -> String {
        switch folder {
        case .inbox: "tray"
        case .starred: "star"
        case .sent: "paperplane"
        case .drafts: "doc.text"
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
    @AppStorage(MailModeKeys.hiddenButtonsKey) private var hiddenButtons = ""
    private let store = MailModeStore.shared

    private func shows(_ action: MailModeAction) -> Bool { MailModeKeys.showsButton(action, hidden: hiddenButtons) }

    var body: some View {
        if store.isMarking {
            VStack(spacing: 8) {
                Image(systemName: "tray.full")
                    .font(.werk(size: 34, weight: .light))
                    .foregroundStyle(ThingsColor.textTertiary)
                Text("\(store.markedIDs.count) mails geselecteerd")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let item = store.selected {
            VStack(alignment: .leading, spacing: 0) {
                header(item)
                if let proposal = store.proposalsByID[item.id]?.first {
                    proposalBanner(proposal)
                }
                Rectangle().fill(ThingsColor.separator).frame(height: 1)
                // Een concept (Concepten, of als nieuwste in Alle mail) komt in het antwoordblok om verder te schrijven.
                MailWindowView(ref: MailRef(message: item.summary), embedded: true, trigger: store.replyTrigger,
                               opensDraft: item.labels.contains("DRAFT"),
                               onReplySent: { store.archiveAfterSending(threadID: item.threadID, appState: appState) },
                               onDraftDiscarded: { store.draftDiscarded(threadID: item.threadID) })
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
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(MailModeButtonStyle())
                    .help("Vorige mail (\(MailModeKeys.key(for: .previous)))")
                    .accessibilityLabel("Vorige mail")
                    Button { store.selectNext() } label: {
                        Image(systemName: "chevron.down")
                    }
                    .help("Volgende mail (\(MailModeKeys.key(for: .next)))")
                    .buttonStyle(MailModeButtonStyle())
                    .accessibilityLabel("Volgende mail")
                }
            }
            // Welke knoppen er staan, kies je in Voorkeuren › Mail; de sneltoetsen werken altijd.
            WrapStack(spacing: 6) {
                if shows(.archive) {
                    MailActionButton(title: "Archiveren", systemImage: "archivebox", action: .archive, prominent: true) {
                        store.archiveSelected(appState: appState)
                    }
                }
                if shows(.reply) {
                    MailActionButton(title: "Beantwoorden", systemImage: "arrowshape.turn.up.left", action: .reply) {
                        store.replyTrigger.reply()
                    }
                }
                if shows(.task) {
                    MailActionButton(title: "Taak", systemImage: "checkmark.circle", action: .task) { store.openSheet(.task) }
                }
                if shows(.time) {
                    MailActionButton(title: "Tijd schrijven", systemImage: "clock", action: .time) { store.openSheet(.time) }
                }
                if shows(.plan) {
                    MailActionButton(title: "Inplannen", systemImage: "calendar", action: .plan) { store.openSheet(.plan) }
                }
                if shows(.follow) {
                    MailActionButton(title: "Opvolgen", systemImage: "arrow.uturn.backward.circle", action: .follow) {
                        store.openSheet(.follow)
                    }
                }
                if shows(.claude) {
                    MailActionButton(title: "Concept", systemImage: "sparkles", action: .claude) { store.openSheet(.concept) }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(ThemeStore.shared.look == .puls ? ThingsColor.mailPaper : ThingsColor.backgroundSidebar)
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
    /// De kolom met klanten staat aan (wegklikken met het kruisje, terughalen met het blauwe rondje in de werkbalk).
    static let visibleKey = "mailMode.showsClients"

    private let store = MailModeStore.shared
    private let directory = ClientDirectory.shared
    @AppStorage(Self.visibleKey) private var showsClients = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 6) {
                    ThemedHeading(title: "Klanten", detail: updatedDetail)
                    if MailActivityStore.shared.isSyncing {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer(minLength: 4)
                    Button { showsClients = false } label: {
                        Image(systemName: "xmark")
                            .font(.werk(size: 10, weight: .bold))
                            .foregroundStyle(ThingsColor.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(ThemeStore.shared.look == .puls ? Puls.glass : ThingsColor.backgroundSidebar))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Klanten verbergen")
                    .accessibilityLabel("Klanten verbergen")
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
                .mailSearchField()
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
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.name) { index, rank in
                            ClientActivityRow(rank: rank, position: index + 1, isOn: store.client == rank.name) {
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

/// Een klant met hoeveel mail er de laatste drie maanden was, en de afgelopen maand als balkje: gevuld op dagen met
/// mail, leeg bij stilte.
private struct ClientActivityRow: View {
    let rank: ClientActivity.Rank
    let position: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        let puls = ThemeStore.shared.look == .puls
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(position)")
                    .font(.werk(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(ThingsColor.textTertiary)
                    .frame(width: 18, alignment: .trailing)
                ClientLogo(name: rank.name, size: 24)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(rank.name)
                            .font(.werk(size: 12.5, weight: .semibold))
                            .foregroundStyle(ThingsColor.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if puls {
                            PulsValue(value: "\(rank.count)", unit: rank.count == 1 ? "MAIL" : "MAILS", size: 15,
                                      color: Puls.rood.big)
                        } else {
                            Text(rank.count == 1 ? "1 mail" : "\(rank.count) mails")
                                .font(.werk(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(ThingsColor.textSecondary)
                                .fixedSize()
                        }
                    }
                    PulsMonthStrip(days: rank.recentDays.isEmpty ? Array(repeating: false, count: 30) : rank.recentDays,
                                   filled: puls ? Puls.rood.solid : ThingsColor.accent,
                                   empty: puls ? Puls.emptyDay : ThingsColor.separator,
                                   height: 6)
                }
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

/// De lijn tussen twee kolommen van de mailmodus: slepen maakt de kolom breder of smaller, dubbelklik zet terug. Een
/// greepje in het midden laat zien dat hij schuift.
private struct ColumnResizer: View {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
    let onReset: () -> Void
    @State private var hovering = false

    var body: some View {
        let puls = ThemeStore.shared.look == .puls
        Rectangle()
            .fill(puls ? Color.clear : ThingsColor.separator)
            .frame(width: puls ? 10 : 1)
            .overlay {
                ZStack {
                    if hovering && !puls {
                        Rectangle().fill(ThingsColor.accent).frame(width: 2)
                    }
                    Capsule()
                        .fill(hovering ? ThingsColor.accent : ThingsColor.textTertiary.opacity(0.45))
                        .frame(width: 3, height: 32)
                    // Een breder klikvlak dan de lijn zelf.
                    Color.clear
                        .frame(width: 9)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            hovering = inside
                            (inside ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
                        }
                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { onChanged($0.translation.width) }
                            .onEnded { _ in onEnded() })
                        .simultaneousGesture(TapGesture(count: 2).onEnded { onReset() })
                }
            }
            .zIndex(1)
            .accessibilityLabel("Schuif de breedte van de kolom")
    }
}

enum MailModeMetrics {
    /// Afronding van velden, knoppen en rijen: volgt het thema (Karmijn recht), hooguit 8.
    static var radius: CGFloat { min(8, max(2, ThingsMetrics.cardRadius)) }
}

/// Een handeling op de gekozen mail: icoon en naam (de toets staat alleen in de tooltip). Archiveren is de volle knop.
struct MailActionButton: View {
    let title: String
    let systemImage: String
    let action: MailModeAction
    var prominent = false
    let perform: () -> Void

    var body: some View {
        let puls = ThemeStore.shared.look == .puls
        Button(action: perform) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.werk(size: 12, weight: .medium))
                Text(title).font(.werk(size: 12.5, weight: prominent ? .semibold : .medium))
            }
            .foregroundStyle(prominent ? (puls ? Color.black : ThingsColor.backgroundContent) : ThingsColor.textPrimary)
            .padding(.horizontal, puls ? 13 : 11)
            .frame(height: 30)
            // Puls: glazen capsules; Archiveren felgroen met zwarte letters.
            .background(RoundedRectangle(cornerRadius: puls ? 15 : MailModeMetrics.radius, style: .continuous)
                .fill(prominent ? (puls ? Puls.groen.solid : ThingsColor.textPrimary) : (puls ? Puls.glass : ThingsColor.cardBackground)))
            .overlay(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous)
                .strokeBorder(prominent || puls ? Color.clear : ThingsColor.separator))
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
        // Puls: glazen capsules van 32 hoog; de hoofdknop felgroen met zwarte letters.
        let puls = ThemeStore.shared.look == .puls
        return configuration.label
            .font(.werk(size: puls ? 13 : 12.5, weight: prominent || puls ? .semibold : .medium))
            .foregroundStyle(prominent ? ThingsColor.onAccent : ThingsColor.textPrimary)
            .padding(.horizontal, puls ? 13 : 10)
            .frame(height: puls ? 32 : 28)
            .background(RoundedRectangle(cornerRadius: puls ? 16 : MailModeMetrics.radius, style: .continuous)
                .fill(prominent ? (puls ? Puls.groen.solid : ThingsColor.accent) : (puls ? Puls.glass : ThingsColor.cardBackground)))
            .overlay(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous)
                .strokeBorder(prominent || puls ? Color.clear : ThingsColor.separator))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// Een filter onder het zoekveld: aan is vol in de accentkleur.
struct MailFilterChipStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        let puls = ThemeStore.shared.look == .puls
        return configuration.label
            .font(.werk(size: 11.5, weight: puls ? .semibold : .medium))
            .foregroundStyle(isOn ? ThingsColor.onAccent : ThingsColor.textPrimary)
            .padding(.horizontal, puls ? 11 : 9)
            .frame(height: puls ? 26 : 24)
            .background(RoundedRectangle(cornerRadius: puls ? 13 : min(6, MailModeMetrics.radius), style: .continuous)
                .fill(isOn ? (puls ? Puls.groen.solid : ThingsColor.accent) : (puls ? Puls.track : ThingsColor.cardBackground)))
            .overlay(RoundedRectangle(cornerRadius: min(6, MailModeMetrics.radius), style: .continuous)
                .strokeBorder(isOn || puls ? Color.clear : ThingsColor.separator))
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
/// Het venster waarin een weergave staat (voor toetsen die alleen daar moeten werken).
struct WindowReader: NSViewRepresentable {
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

private extension View {
    /// Achter een zoekveld: in Puls een grijze capsule zonder rand, elders een kaartje met een haarlijn.
    @ViewBuilder func mailSearchField() -> some View {
        if ThemeStore.shared.look == .puls {
            background(Capsule().fill(Puls.track))
        } else {
            background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).fill(ThingsColor.cardBackground))
                .overlay(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).strokeBorder(ThingsColor.separator))
        }
    }

    /// Puls: een kolom van de mailmodus als losse tegel met ronde hoeken op het zwart; in andere thema's niets.
    @ViewBuilder func pulsTile() -> some View {
        if ThemeStore.shared.look == .puls {
            clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            self
        }
    }
}

// MARK: - Een mail loslaten op een map of mailbox

/// Een plek in de mailmodus waar je een gesleepte mail loslaat (een map, een mailbox); licht op zolang hij erboven hangt.
private struct MailModeDropTarget: ViewModifier {
    let isEnabled: Bool
    let perform: @MainActor (GmailDragPayload) -> Void
    @State private var isTargeted = false

    @ViewBuilder func body(content: Content) -> some View {
        if isEnabled {
            content
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ThingsColor.accent.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(ThingsColor.accent, lineWidth: 2))
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [.gmailMessage], isTargeted: $isTargeted) { providers in
                    guard let provider = providers.first(where: {
                        $0.hasItemConformingToTypeIdentifier(UTType.gmailMessage.identifier)
                    }) else { return false }
                    MailDragState.shared.noteDropped()
                    let perform = perform
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.gmailMessage.identifier) { data, _ in
                        guard let data, let payload = try? JSONDecoder().decode(GmailDragPayload.self, from: data) else { return }
                        Task { @MainActor in perform(payload) }
                    }
                    return true
                }
        } else {
            content
        }
    }
}
