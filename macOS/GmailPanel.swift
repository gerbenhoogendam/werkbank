import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

/// Uitklapvenster links: je Gmail-inbox. Sleep een mail naar een kolom van het board; daarna wordt hij in Gmail gearchiveerd.
struct GmailPanel: View {
    private let gmail = GmailSession.shared
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    /// De mail die is aangeklikt (alleen markering; lezen doe je met dubbelklikken).
    private let selection = MailSelection.shared
    /// "Verplaatsen naar" bovenin staat open (tijdens het slepen van een mail).
    @State private var moveZoneOpen = false
    /// Hoogte van kop en tabs: daar klapt "Verplaatsen naar" open.
    @State private var topBarHeight: CGFloat = 74
    /// Mailbox waarvan de tabnaam wordt gewijzigd.
    @State private var renaming: String?
    @State private var renameText = ""
    private let dragState = MailDragState.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                if look == .standaard { Rectangle().fill(ThingsColor.separator).frame(height: 1) }
                if gmail.accounts.count > 1 { tabs }
            }
            .background(ThingsColor.mailHeaderBackground)
            .darkScheme(ThemeStore.shared.theme.darkMailHeader)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { topBarHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in topBarHeight = height }
            })
            content
                .blur(radius: moveZoneOpen ? 4 : 0)
                .animation(.easeOut(duration: 0.18), value: moveZoneOpen)
        }
        .frame(maxHeight: .infinity)
        .background(ThingsColor.mailBackground)
        .darkScheme(ThemeStore.shared.theme.darkMail)
        .background { mailboxShortcuts }
        .alert("Naam van de tab", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(renaming.map(GmailSession.shortName) ?? "", text: $renameText)
            Button("Bewaar") { if let renaming { gmail.rename(renaming, to: renameText) } }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text(renaming ?? "")
        }
        // Een Gmail-mail loslaten op het paneel zelf doet niets (zo kun je een sleepactie afbreken).
        .onDrop(of: [.gmailMessage], isTargeted: nil) { _ in true }
        .overlay(alignment: .top) {
            if dragState.isDragging, gmail.accounts.count > 1 {
                MailMoveZone(triggerHeight: topBarHeight, isOpen: $moveZoneOpen) { email, providers in
                    moveDrop(to: email, providers: providers)
                }
            }
        }
        .onChange(of: dragState.isDragging) { _, dragging in if !dragging { moveZoneOpen = false } }
        .overlay(alignment: .bottom) {
            if dragState.isDragging {
                ClaudeDropTarget()
                    .padding(.bottom, 64)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: dragState.isDragging)
        .task {
            if gmail.state == .signedIn {
                await gmail.migrateLegacyIfNeeded()
                await gmail.reload()
            }
            // Gmail kent geen push naar deze app: ververs af en toe zolang het paneel open staat.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                await gmail.reload()
            }
        }
    }

    // MARK: Acties

    private func archive(_ message: GmailMessageSummary) {
        if selection.selectedID == message.id { selection.selectedID = nil }
        Task { await gmail.archiveMessage(message, appState: appState) }
    }

    /// Veeg naar rechts: een taak met het onderwerp als titel in de Inbox, zonder de mail te openen.
    /// Daarna wordt de mail gearchiveerd, net als bij slepen en bij "Maak taak".
    private func quickTask(_ message: GmailMessageSummary) {
        if selection.selectedID == message.id { selection.selectedID = nil }
        Task {
            await gmail.createTask(from: message, title: message.subject, minutes: 0, column: .inbox,
                                   context: context, appState: appState)
        }
    }

    // MARK: Kop

    private var look: ThemeLook { ThemeStore.shared.look }
    private var unreadCount: Int { gmail.messages.filter(\.isUnread).count }

    private var headerHeight: CGFloat {
        switch look {
        case .standaard: 38
        case .tischsuper: 78
        case .principes, .drukproef: 54
        default: 46
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if look == .standaard {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(ThingsColor.accent)
                Text(headerTitle)
                    .lineLimit(1)
                    .thingsFont(.heading)
                    .foregroundStyle(ThingsColor.textPrimary)
            } else {
                MailHeaderTitle(title: headerTitle, unread: unreadCount)
                    .lineLimit(1)
            }
            Spacer()
            if gmail.state == .signedIn {
                if gmail.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await gmail.reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .help("Inbox verversen")
                }
                Button {
                    PanelStore.shared.open(.compose(ComposeRef(mode: .new, source: nil)))
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThingsColor.textSecondary)
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Nieuwe mail (⇧⌘N)")
                accountMenu
            }
        }
        .padding(.horizontal, look == .standaard ? 12 : 14)
        .frame(height: headerHeight)
    }

    private var headerTitle: String {
        if gmail.isAllCombined { return "Alle mailboxen" }
        if gmail.isCombined { return gmail.combinedAccounts.map(gmail.displayName).joined(separator: " + ") }
        return gmail.accounts.count > 1 ? "Mail" : "Gmail"
    }

    // MARK: Tabs

    /// Een eigen selectie (niet alles): die mailboxen staan samen in één blauwe pil vooraan.
    private var hasPartialCombination: Bool { gmail.isCombined && !gmail.isAllCombined }

    @ViewBuilder private var tabs: some View {
        let accounts = gmail.accounts.filter { !hasPartialCombination || !gmail.combinedAccounts.contains($0) }
        if look == .spark {
            // Spark: de mailboxen onder elkaar in de donkerblauwe kop, elk met een kleurstreepje.
            VStack(spacing: 2) {
                if hasPartialCombination { combinedPill.frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(accounts, id: \.self) { email in
                    let isOn = !gmail.isCombined && gmail.activeAccount == email
                    MailboxTab(title: gmail.displayName(email), isOn: isOn, color: mailboxColor(email),
                               count: isOn ? unreadCount : nil) { select(email) }
                        .help("\(email) · ⌘-klik om te combineren")
                }
                MailboxTab(title: "Alles", isOn: gmail.isAllCombined, color: ThingsColor.textSecondary,
                           count: gmail.isAllCombined ? unreadCount : nil) {
                    selection.selectedID = nil
                    Task { await gmail.showCombined() }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        } else {
            HStack(spacing: look == .drukproef ? 14 : (look == .wandklok || look == .sneeuwwitje ? 0 : (look == .standaard ? 4 : 6))) {
                if hasPartialCombination { combinedPill }
                ForEach(accounts, id: \.self) { email in
                    tab(title: gmail.displayName(email),
                        isOn: !gmail.isCombined && gmail.activeAccount == email) {
                        select(email)
                    }
                    .help("\(email) · ⌘-klik om te combineren")
                }
                tab(title: "Alles", isOn: gmail.isAllCombined) {
                    selection.selectedID = nil
                    Task { await gmail.showCombined() }
                }
                if look == .standaard || look == .principes || look == .drukproef { Spacer(minLength: 0) }
            }
            .padding(3)
            .background {
                if look == .wandklok || look == .sneeuwwitje {
                    Capsule().fill(ThingsColor.separator.opacity(0.6))
                }
            }
            .padding(.horizontal, look == .standaard ? 5 : 9)
            .padding(.vertical, look == .standaard ? 3 : 6)
            .overlay(alignment: .bottom) {
                if look == .standaard { Rectangle().fill(ThingsColor.separator).frame(height: 1) }
            }
        }
    }

    /// Kleur van een mailbox (Spark): op volgorde van de mailboxen.
    private func mailboxColor(_ email: String) -> Color {
        let index = gmail.accounts.firstIndex(of: email) ?? 0
        return ThemeParts.mailboxColors[index % ThemeParts.mailboxColors.count]
    }

    /// Klik: alleen deze mailbox. ⌘-klik: erbij zetten of eruit halen.
    private func select(_ email: String) {
        selection.selectedID = nil
        if NSEvent.modifierFlags.contains(.command) {
            Task { await gmail.toggleInCombination(email) }
        } else {
            Task { await gmail.switchAccount(to: email) }
        }
    }

    private var combinedPill: some View {
        HStack(spacing: 0) {
            ForEach(Array(gmail.combinedAccounts.enumerated()), id: \.element) { index, email in
                if index > 0 {
                    Text("+").foregroundStyle(Color.white.opacity(0.7))
                }
                Button { select(email) } label: {
                    Text(gmail.displayName(email))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(email) · ⌘-klik om uit de combinatie te halen")
            }
        }
        .font(.werk(size: 11.5, weight: .semibold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .background(Capsule().fill(ThingsColor.accent))
    }

    private func tab(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        MailboxTab(title: title, isOn: isOn, action: action)
    }

    /// Een mail op een mailbox in "Verplaatsen naar" laten vallen: het gesprek verhuist naar die mailbox.
    private func moveDrop(to email: String, providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.gmailMessage.identifier) }) else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.gmailMessage.identifier) { data, _ in
            guard let data, let payload = try? JSONDecoder().decode(GmailDragPayload.self, from: data) else { return }
            Task { @MainActor in
                let source = gmail.account(for: payload.messageID)
                guard source != email else { return }
                PanelStore.shared.closeMail(messageID: payload.messageID, snapshot: false)
                await gmail.moveThread(threadID: payload.threadID, messageID: payload.messageID, from: source, to: email,
                                       appState: appState)
            }
        }
        return true
    }

    /// ⌘1…⌘9 schakelt tussen de mailboxen, ⌘0 toont ze samen (alleen als het Gmail-paneel open staat).
    @ViewBuilder private var mailboxShortcuts: some View {
        if gmail.accounts.count > 1 {
            ZStack {
                ForEach(Array(gmail.accounts.prefix(9).enumerated()), id: \.element) { index, email in
                    Button("") {
                        selection.selectedID = nil
                        Task { await gmail.switchAccount(to: email) }
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Button("") {
                    selection.selectedID = nil
                    Task { await gmail.showCombined() }
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    /// Schakelen tussen gekoppelde mailboxen en ze een eigen naam geven. Toevoegen en loskoppelen: Voorkeuren › Mail.
    private var accountMenu: some View {
        Menu {
            ForEach(gmail.accounts, id: \.self) { email in
                Button {
                    selection.selectedID = nil
                    Task { await gmail.switchAccount(to: email) }
                } label: {
                    if email == gmail.activeAccount, !gmail.isCombined {
                        Label("\(gmail.displayName(email)) — \(email)", systemImage: "checkmark")
                    } else {
                        Text("\(gmail.displayName(email)) — \(email)")
                    }
                }
            }
            Divider()
            Menu("Naam wijzigen") {
                ForEach(gmail.accounts, id: \.self) { email in
                    Button("\(email)…") {
                        renameText = gmail.displayNames[email] ?? ""
                        renaming = email
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                if gmail.accounts.count > 1, let email = gmail.activeAccount {
                    Text(gmail.isAllCombined ? "Alles" : (gmail.isCombined ? "\(gmail.combinedAccounts.count) mailboxen" : gmail.displayName(email)))
                        .thingsFont(.metadata)
                        .lineLimit(1)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(ThingsColor.textPrimary)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(gmail.emailAddress ?? "Account")
    }

    // MARK: Inhoud

    @ViewBuilder
    private var content: some View {
        if !gmail.isConfigured {
            notice(symbol: "wrench.and.screwdriver",
                   title: "Gmail is nog niet gekoppeld",
                   text: "Zet GOOGLE_CLIENT_ID in Config/Local.xcconfig, draai xcodegen generate en bouw opnieuw. Zie de README, \"Gmail koppelen\".")
        } else if gmail.state == .signedIn {
            inbox
        } else {
            signInPrompt
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.werk(size: 30))
                .foregroundStyle(ThingsColor.textTertiary)
            Text("Log in om je inbox hier te zien")
                .thingsFont(.todoTitle)
                .foregroundStyle(ThingsColor.textPrimary)
                .multilineTextAlignment(.center)
            Button {
                Task { await gmail.signIn() }
            } label: {
                if gmail.state == .signingIn {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Inloggen met Google")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(gmail.state == .signingIn)
            if let error = gmail.lastError {
                Text(error)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.deadline)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notice(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.werk(size: 28))
                .foregroundStyle(ThingsColor.textTertiary)
            Text(title)
                .thingsFont(.todoTitle)
                .foregroundStyle(ThingsColor.textPrimary)
            Text(text)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inbox: some View {
        VStack(spacing: 0) {
            if let error = gmail.lastError {
                Text(error)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.deadline)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if gmail.messages.isEmpty {
                Text(gmail.isLoading ? "Inbox ophalen…" : "Geen mail in je Gmail-inbox.")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // ScrollView, geen List: een List nam het slepen van de rij over. De veegacties (twee vingers op het
                // trackpad: links archiveert, rechts maakt een taak) staan los in `TrackpadSwipe`.
                ScrollView {
                    LazyVStack(spacing: MailLook.cardRows ? 2 : 0) {
                        ForEach(gmail.messages) { message in
                            GmailRow(message: message,
                                     isBusy: gmail.busyMessageIDs.contains(message.id),
                                     isSelected: selection.selectedID == message.id,
                                     accountLabel: gmail.isCombined ? gmail.account(for: message.id).map(gmail.displayName) : nil,
                                accountColor: gmail.account(for: message.id).map(mailboxColor),
                                     onSelect: { selection.selectedID = message.id },
                                     onArchive: { archive(message) },
                                     onDragStarted: { dragState.begin(account: gmail.account(for: message.id)) })
                                .trackpadSwipe(
                                    leading: SwipeAction(systemImage: "checkmark.circle", title: "Taak maken",
                                                         color: ThingsColor.accent) { quickTask(message) },
                                    trailing: SwipeAction(systemImage: "archivebox", title: "Archiveren",
                                                          color: ThingsColor.textSecondary) { archive(message) }
                                )
                            if !MailLook.cardRows {
                                Rectangle().fill(ThingsColor.separator).frame(height: 1)
                                    .padding(.horizontal, look == .standaard ? 0 : 12)
                            }
                        }
                    }
                    .padding(.horizontal, MailLook.cardRows ? 8 : 0)
                    .padding(.top, MailLook.cardRows ? 4 : 0)
                }
            }
        }
    }
}

private struct GmailRow: View {
    let message: GmailMessageSummary
    let isBusy: Bool
    let isSelected: Bool
    var accountLabel: String? = nil
    /// Kleurstreepje van de mailbox voor de afzender (Spark).
    var accountColor: Color? = nil
    let onSelect: () -> Void
    let onArchive: () -> Void
    let onDragStarted: () -> Void

    @State private var isHovering = false

    var body: some View {
        header
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { rowBackground }
            .opacity(isBusy ? 0.5 : 1)
            .onHover { isHovering = $0 }
    }

    /// Gekozen of aangewezen rij, zoals het thema hem tekent.
    @ViewBuilder private var rowBackground: some View {
        let look = ThemeStore.shared.look
        let radius: CGFloat = look == .principes || look == .sneeuwwitje || look == .rekenmachine ? 14 : (look == .drukproef ? 10 : 12)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch look {
        case .standaard, .spark:
            isSelected ? ThingsColor.selection : (isHovering ? ThingsColor.selection.opacity(0.5) : Color.clear)
        case .wandklok, .sneeuwwitje, .rekenmachine:
            if isSelected {
                shape.fill(ThingsColor.cardBackground).shadow(color: ThingsColor.cardShadow, radius: 8, y: 3)
            } else if isHovering {
                shape.fill(Color.primary.opacity(0.04))
            }
        case .tischsuper, .principes, .drukproef:
            if isSelected {
                shape.fill(ThingsColor.cardBackground)
            } else if isHovering {
                shape.fill(Color.primary.opacity(0.05))
            }
        }
    }

    private func open() {
        PanelStore.shared.open(.mail(MailRef(message: message)))
    }

    // MARK: Rij (één klik markeert, dubbelklik opent de mail, slepen naar een kolom)

    private var header: some View {
        let look = ThemeStore.shared.look
        return HStack(alignment: .top, spacing: MailLook.avatars ? 10 : 4) {
            if MailLook.avatars {
                Text(MailLook.initials(message.senderDisplay))
                    .font(.werk(size: 11, weight: .semibold))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .frame(width: 30, height: 30)
                    .background {
                        if look == .rekenmachine { RoundKey() } else { Circle().fill(ThingsColor.tagBackground) }
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(message.isUnread ? MailLook.unreadDot : Color.clear)
                        .frame(width: 7, height: 7)
                    if look == .spark, let accountColor {
                        RoundedRectangle(cornerRadius: 1.5).fill(accountColor).frame(width: 3, height: 14)
                    }
                    Text(message.senderDisplay)
                        .font(.werk(size: 13, weight: look == .spark ? .bold : (message.isUnread ? .semibold : .regular)))
                        .foregroundStyle(ThingsColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let accountLabel {
                        Text(accountLabel)
                            .font(.werk(size: 10, weight: .medium))
                            .foregroundStyle(ThingsColor.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(ThingsColor.separator.opacity(0.6)))
                    }
                    if isBusy {
                        ProgressView().controlSize(.mini)
                    } else if let date = message.date {
                        Text(Self.dateText(date))
                            .thingsFont(.metadata)
                            .foregroundStyle(ThingsColor.textSecondary)
                    }
                }
                Text(message.subject)
                    .thingsFont(.todoTitle)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(1)
                    .padding(.leading, 13)
                if !message.snippet.isEmpty {
                    Text(message.snippet)
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textSecondary)
                        .lineLimit(2)
                        .padding(.leading, 13)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Eerst dubbelklik, dan enkele klik: anders wint de enkele klik altijd.
            .onTapGesture(count: 2, perform: open)
            .onTapGesture(perform: onSelect)
            .onDrag {
                onDragStarted()
                return GmailSession.shared.dragProvider(for: message)
            }
            .contextMenu {
                Button("Openen") { open() }
                Button("Analyseer met Claude") { analyze() }
                Button("Losse analyse (eigen venster)") {
                    ClaudeAnalyzer.shared.analyze(messageID: message.id, subject: message.subject)
                    PanelStore.shared.open(.claude)
                }
                let source = GmailSession.shared.account(for: message.id)
                let targets = GmailSession.shared.accounts.filter { $0 != source }
                if !targets.isEmpty {
                    Menu("Verplaats naar") {
                        ForEach(targets, id: \.self) { email in
                            Button(GmailSession.shared.displayName(email)) {
                                Task {
                                    await GmailSession.shared.moveThread(threadID: message.threadID, messageID: message.id,
                                                                         from: source, to: email, appState: AppState.shared)
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Archiveren", action: onArchive)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Dubbelklik om de mail te openen, of sleep hem naar een kolom")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // De knoppen zweven over de rij (rechtsonder) in plaats van altijd ruimte in te nemen.
        .overlay(alignment: .bottomTrailing) {
            if isHovering || isSelected { hoverActions }
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 0) {
            Button(action: analyze) {
                ClaudeSpark()
                    .frame(width: 14, height: 14)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .help("Laat Claude deze mail analyseren")
            .accessibilityLabel("Analyseer mail van \(message.senderDisplay) met Claude")

            Button(action: onArchive) {
                Image(systemName: "archivebox")
                    .font(.werk(size: 12))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .help("Archiveren in Gmail")
            .accessibilityLabel("Archiveer mail van \(message.senderDisplay)")
        }
        .padding(.horizontal, 2)
        .background(Capsule().fill(ThingsColor.backgroundContent).shadow(color: ThingsColor.cardShadow, radius: 3, y: 1))
        .padding(.trailing, 8)
        .padding(.bottom, 6)
    }

    /// Opent het gesprek en zet er een analyse van deze mail in.
    private func analyze() {
        var ref = MailRef(message: message)
        ref.analyze = true
        PanelStore.shared.open(.mail(ref))
    }

    private static func dateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
