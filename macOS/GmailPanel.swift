import AppKit
import SwiftData
import SwiftUI
import WerkbankCore

/// Uitklapvenster links: je Gmail-inbox. Sleep een mail naar een kolom van het board; daarna wordt hij in Gmail gearchiveerd.
struct GmailPanel: View {
    private let gmail = GmailSession.shared
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    /// De mail die is aangeklikt (alleen markering; lezen doe je met dubbelklikken).
    @State private var selectedID: String?
    private let dragState = MailDragState.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            if gmail.accounts.count > 1 { tabs }
            content
        }
        .frame(maxHeight: .infinity)
        .background(ThingsColor.backgroundSidebar)
        .background { mailboxShortcuts }
        // Een Gmail-mail loslaten op het paneel zelf doet niets (zo kun je een sleepactie afbreken).
        .onDrop(of: [.gmailMessage], isTargeted: nil) { _ in true }
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
        if selectedID == message.id { selectedID = nil }
        Task { await gmail.archiveMessage(message, appState: appState) }
    }

    /// Veeg naar rechts: een taak met het onderwerp als titel in de Inbox, zonder de mail te openen.
    /// Daarna wordt de mail gearchiveerd, net als bij slepen en bij "Maak taak".
    private func quickTask(_ message: GmailMessageSummary) {
        if selectedID == message.id { selectedID = nil }
        Task {
            await gmail.createTask(from: message, title: message.subject, minutes: 0, column: .inbox,
                                   context: context, appState: appState)
        }
    }

    // MARK: Kop

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.fill")
                .foregroundStyle(gmail.isCombined ? Color.white : ThingsColor.accent)
            Text(gmail.isCombined ? "Alle mailboxen" : (gmail.accounts.count > 1 ? "Mail" : "Gmail"))
                .thingsFont(.heading)
                .foregroundStyle(gmail.isCombined ? Color.white : ThingsColor.textPrimary)
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
                    .foregroundStyle(gmail.isCombined ? Color.white.opacity(0.75) : ThingsColor.textSecondary)
                    .help("Inbox verversen")
                }
                accountMenu
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        // Gecombineerde weergave (⌘0): de balk is donker, zodat je ziet dat het niet één mailbox is.
        .background(gmail.isCombined ? Color(white: 0.17) : Color.clear)
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Array(gmail.accounts.enumerated()), id: \.element) { index, email in
                tab(title: GmailSession.shortName(email), hint: index < 9 ? "⌘\(index + 1)" : nil,
                    isOn: !gmail.isCombined && gmail.activeAccount == email) {
                    selectedID = nil
                    Task { await gmail.switchAccount(to: email) }
                }
                .help(email)
            }
            tab(title: "Alles", hint: "⌘0", isOn: gmail.isCombined) {
                selectedID = nil
                Task { await gmail.showCombined() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(ThingsColor.separator).frame(height: 1) }
    }

    private func tab(title: String, hint: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                if let hint {
                    Text(hint).foregroundStyle(isOn ? Color.white.opacity(0.7) : ThingsColor.textTertiary)
                }
            }
            .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
            .foregroundStyle(isOn ? Color.white : ThingsColor.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(isOn ? ThingsColor.accent : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// ⌘1…⌘9 schakelt tussen de mailboxen, ⌘0 toont ze samen (alleen als het Gmail-paneel open staat).
    @ViewBuilder private var mailboxShortcuts: some View {
        if gmail.accounts.count > 1 {
            ZStack {
                ForEach(Array(gmail.accounts.prefix(9).enumerated()), id: \.element) { index, email in
                    Button("") {
                        selectedID = nil
                        Task { await gmail.switchAccount(to: email) }
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Button("") {
                    selectedID = nil
                    Task { await gmail.showCombined() }
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    /// Schakelen tussen gekoppelde mailboxen, een mailbox toevoegen of loskoppelen.
    private var accountMenu: some View {
        Menu {
            ForEach(gmail.accounts, id: \.self) { email in
                Button {
                    selectedID = nil
                    Task { await gmail.switchAccount(to: email) }
                } label: {
                    if email == gmail.activeAccount, !gmail.isCombined {
                        Label(email, systemImage: "checkmark")
                    } else {
                        Text(email)
                    }
                }
            }
            Divider()
            Button("Mailbox toevoegen…") { Task { await gmail.signIn() } }
                .disabled(gmail.isAddingAccount)
            if let email = gmail.activeAccount {
                Button("\(email) loskoppelen", role: .destructive) { gmail.removeAccount(email) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                if gmail.accounts.count > 1, let email = gmail.activeAccount {
                    Text(gmail.isCombined ? "Alles" : GmailSession.shortName(email))
                        .thingsFont(.metadata)
                        .lineLimit(1)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(gmail.isCombined ? Color.white : ThingsColor.textPrimary)
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
                .font(.system(size: 30))
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
                .font(.system(size: 28))
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
                    LazyVStack(spacing: 0) {
                        ForEach(gmail.messages) { message in
                            GmailRow(message: message,
                                     isBusy: gmail.busyMessageIDs.contains(message.id),
                                     isSelected: selectedID == message.id,
                                     accountLabel: gmail.isCombined ? gmail.account(for: message.id).map(GmailSession.shortName) : nil,
                                     onSelect: { selectedID = message.id },
                                     onArchive: { archive(message) },
                                     onDragStarted: { dragState.begin() })
                                .trackpadSwipe(
                                    leading: SwipeAction(systemImage: "checkmark.circle", title: "Taak maken",
                                                         color: ThingsColor.accent) { quickTask(message) },
                                    trailing: SwipeAction(systemImage: "archivebox", title: "Archiveren",
                                                          color: ThingsColor.textSecondary) { archive(message) }
                                )
                            Rectangle().fill(ThingsColor.separator).frame(height: 1)
                        }
                    }
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
    let onSelect: () -> Void
    let onArchive: () -> Void
    let onDragStarted: () -> Void

    @State private var isHovering = false

    var body: some View {
        header
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ThingsColor.selection : (isHovering ? ThingsColor.selection.opacity(0.5) : Color.clear))
            .opacity(isBusy ? 0.5 : 1)
            .onHover { isHovering = $0 }
    }

    private func open() {
        PanelStore.shared.open(.mail(MailRef(message: message)))
    }

    // MARK: Rij (één klik markeert, dubbelklik opent de mail, slepen naar een kolom)

    private var header: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(message.isUnread ? ThingsColor.accent : Color.clear)
                        .frame(width: 7, height: 7)
                    Text(message.senderDisplay)
                        .font(.system(size: 13, weight: message.isUnread ? .semibold : .regular))
                        .foregroundStyle(ThingsColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let accountLabel {
                        Text(accountLabel)
                            .font(.system(size: 10, weight: .medium))
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
                Divider()
                Button("Archiveren", action: onArchive)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Dubbelklik om de mail te openen, of sleep hem naar een kolom")

            Button(action: analyze) {
                ClaudeSpark()
                    .frame(width: 14, height: 14)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isHovering || isSelected ? 1 : 0)
            .help("Laat Claude deze mail analyseren")
            .accessibilityLabel("Analyseer mail van \(message.senderDisplay) met Claude")

            Button(action: onArchive) {
                Image(systemName: "archivebox")
                    .font(.system(size: 12))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isHovering || isSelected ? 1 : 0)
            .help("Archiveren in Gmail")
            .accessibilityLabel("Archiveer mail van \(message.senderDisplay)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
    }

    private func analyze() {
        ClaudeAnalyzer.shared.analyze(messageID: message.id, subject: message.subject)
        PanelStore.shared.open(.claude)
    }

    private static func dateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
