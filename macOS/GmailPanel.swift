import SwiftData
import SwiftUI
import WerkbankCore

/// Uitklapvenster links: je Gmail-inbox. Sleep een mail naar een kolom van het board; daarna wordt hij in Gmail gearchiveerd.
struct GmailPanel: View {
    private let gmail = GmailSession.shared
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    /// De mail die openstaat in de lijst (één tegelijk).
    @State private var expandedID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            content
        }
        .frame(maxHeight: .infinity)
        .background(ThingsColor.backgroundSidebar)
        // Een Gmail-mail loslaten op het paneel zelf doet niets (zo kun je een sleepactie afbreken).
        .onDrop(of: [.gmailMessage], isTargeted: nil) { _ in true }
        .task {
            if gmail.state == .signedIn {
                if gmail.emailAddress == nil { await gmail.loadProfile() }
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
        if expandedID == message.id { expandedID = nil }
        Task { await gmail.archiveMessage(message, appState: appState) }
    }

    /// Veeg naar rechts: een taak met het onderwerp als titel in de Inbox, zonder de mail te openen.
    /// Daarna wordt de mail gearchiveerd, net als bij slepen en bij "Maak taak".
    private func quickTask(_ message: GmailMessageSummary) {
        if expandedID == message.id { expandedID = nil }
        Task {
            await gmail.createTask(from: message, title: message.subject, minutes: 0, column: .inbox,
                                   context: context, appState: appState)
        }
    }

    // MARK: Kop

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.fill")
                .foregroundStyle(ThingsColor.accent)
            Text("Gmail")
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.textPrimary)
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
                Menu {
                    if let email = gmail.emailAddress { Text(email) }
                    Button("Uitloggen", role: .destructive) { gmail.signOut() }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(gmail.emailAddress ?? "Account")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
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
                // Een List (geen ScrollView) voor de veegacties: met twee vingers op het trackpad naar links
                // archiveert, naar rechts maakt direct een taak. Met een muis kan dat niet; gebruik dan de knoppen.
                List {
                    ForEach(gmail.messages) { message in
                        GmailRow(message: message,
                                 isBusy: gmail.busyMessageIDs.contains(message.id),
                                 isExpanded: expandedID == message.id,
                                 onToggle: {
                                     withAnimation(.easeOut(duration: 0.15)) {
                                         expandedID = expandedID == message.id ? nil : message.id
                                     }
                                 },
                                 onArchive: { archive(message) },
                                 onCreateTask: { title, minutes, column in
                                     if expandedID == message.id { expandedID = nil }
                                     Task {
                                         await gmail.createTask(from: message, title: title, minutes: minutes,
                                                                column: column, context: context, appState: appState)
                                     }
                                 })
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button { archive(message) } label: {
                                    Label("Archiveren", systemImage: "archivebox")
                                }
                                .tint(ThingsColor.textSecondary)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button { quickTask(message) } label: {
                                    Label("Taak maken", systemImage: "checkmark.circle")
                                }
                                .tint(ThingsColor.accent)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            Text("Klik een mail om hem te lezen. Veeg naar links om te archiveren, naar rechts voor een taak (twee vingers op het trackpad). Of sleep hem naar een kolom: hij wordt dan ook gearchiveerd.")
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textTertiary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GmailRow: View {
    let message: GmailMessageSummary
    let isBusy: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onArchive: () -> Void
    let onCreateTask: (String, Int, BoardColumn) -> Void

    private enum BodyState {
        case loading
        case loaded(String)
        case failed(String)
    }

    @Query(sort: \ColumnRecord.sortOrder) private var columnRecords: [ColumnRecord]
    @State private var isHovering = false
    @State private var bodyState: BodyState = .loading
    // Taak maken: titel (standaard het onderwerp), al bestede minuten en de kolom.
    @State private var taskTitle = ""
    @State private var minutesText = ""
    @State private var targetColumnID = BoardColumn.inboxID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded { expandedContent }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering || isExpanded ? ThingsColor.selection.opacity(0.5) : Color.clear)
        .opacity(isBusy ? 0.5 : 1)
        .onHover { isHovering = $0 }
    }

    // MARK: Kop (klikken klapt open, slepen naar een kolom)

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
                    .lineLimit(isExpanded ? nil : 1)
                    .padding(.leading, 13)
                if !isExpanded, !message.snippet.isEmpty {
                    Text(message.snippet)
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textSecondary)
                        .lineLimit(2)
                        .padding(.leading, 13)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onDrag { GmailSession.shared.dragProvider(for: message) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Klik om de mail te lezen, of sleep hem naar een kolom")

            Button(action: onArchive) {
                Image(systemName: "archivebox")
                    .font(.system(size: 12))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isHovering || isExpanded ? 1 : 0)
            .help("Archiveren in Gmail")
            .accessibilityLabel("Archiveer mail van \(message.senderDisplay)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
    }

    // MARK: Opengeklapt

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let address = message.fromAddress {
                Text(message.fromName.map { "\($0) <\(address)>" } ?? address)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .textSelection(.enabled)
            }
            switch bodyState {
            case .loading:
                ProgressView().controlSize(.small)
            case .loaded(let text):
                ScrollView {
                    Text(text.isEmpty ? "(Geen tekst in deze mail)" : text)
                        .thingsFont(.notes)
                        .foregroundStyle(ThingsColor.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
            case .failed(let reason):
                Text(reason)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.deadline)
            }
            taskSection
        }
        .padding(.leading, 25)
        .padding(.trailing, 12)
        .padding(.bottom, 10)
        .task(id: message.id) {
            if taskTitle.isEmpty { taskTitle = message.subject }
            await loadBody()
        }
    }

    // MARK: Taak maken

    private var minutes: Int { Int(minutesText.trimmingCharacters(in: .whitespaces)) ?? 0 }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            Text("Taak maken")
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.textPrimary)
            TextField("Titel van de taak", text: $taskTitle)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                Text("Al besteed")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                TextField("0", text: $minutesText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                Text("min")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text("In kolom")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                Picker("In kolom", selection: $targetColumnID) {
                    ForEach(columnRecords) { record in
                        Text(record.title).tag(record.key)
                    }
                }
                .labelsHidden()
            }
            HStack(spacing: 8) {
                Button {
                    let column = columnRecords.first { $0.key == targetColumnID }?.column ?? .inbox
                    onCreateTask(taskTitle, minutes, column)
                } label: {
                    Text("Maak taak")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: onArchive) {
                    Label("Alleen archiveren", systemImage: "archivebox")
                }
                .disabled(isBusy)
            }
            Text("Beide archiveren de mail in Gmail.")
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textTertiary)
        }
    }

    private func loadBody() async {
        bodyState = .loading
        do {
            bodyState = .loaded(try await GmailSession.shared.body(forMessageID: message.id))
        } catch {
            bodyState = .failed("Mail ophalen mislukt: \(error.localizedDescription)")
        }
    }

    private static func dateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
