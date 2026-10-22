import AppKit
import SwiftData
import SwiftUI
import WebKit
import WerkbankCore

/// Wat een mailpaneel nodig heeft om zijn gesprek op te halen.
struct MailRef: Codable, Hashable {
    var messageID: String
    var threadID: String
    var subject: String
    var fromName: String?
    var fromAddress: String?
    /// De mailbox waaruit de mail komt; het paneel kan intussen naar een andere zijn geschakeld.
    var account: String?
    /// Meteen een analyse door Claude starten van deze mail (slepen naar het Claude-icoon, knop in de lijst).
    var analyze = false

    @MainActor
    init(message: GmailMessageSummary) {
        messageID = message.id
        threadID = message.threadID
        subject = message.subject
        fromName = message.fromName
        fromAddress = message.fromAddress
        account = GmailSession.shared.account(for: message.id)
    }

    init(messageID: String, threadID: String, subject: String, fromName: String? = nil, fromAddress: String? = nil,
         account: String?, analyze: Bool = false) {
        self.messageID = messageID
        self.threadID = threadID
        self.subject = subject
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.account = account
        self.analyze = analyze
    }

    var summary: GmailMessageSummary {
        GmailMessageSummary(id: messageID, threadID: threadID, fromName: fromName, fromAddress: fromAddress, subject: subject)
    }
}

private let claudeTint = Color(red: 0.85, green: 0.47, blue: 0.34)

/// Een heel mailgesprek: alle mails als blokken, analyses van Claude ertussen en onderaan (of bovenaan) het antwoord.
/// Aan de drie streepjes bovenaan pak je het gesprek vast en sleep je het naar een kolom, de agenda of het Claude-icoon.
struct MailWindowView: View {
    let ref: MailRef

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \ColumnRecord.sortOrder) private var columnRecords: [ColumnRecord]
    @AppStorage(MailSettings.newestAtBottomKey) private var newestAtBottom = true

    private let gmail = GmailSession.shared

    @State private var model: MailThreadModel
    @State private var wasInList = false
    @State private var showTaskRow = false
    @State private var taskTitle = ""
    @State private var minutesText = ""
    @State private var targetColumnID = BoardColumn.inboxID
    /// Op welke mail het antwoordblok antwoordt (en hoe).
    @State private var replyRef: ComposeRef?
    @State private var replyBody = ""
    /// Het conceptantwoord dat al is overgenomen of overgeslagen.
    @State private var usedDraftID: UUID?
    /// Een blok waar het gesprek naartoe moet scrollen (bijv. een net gestarte analyse).
    @State private var scrollTarget: String?

    init(ref: MailRef) {
        self.ref = ref
        _model = State(initialValue: MailThreadModel(ref: ref))
    }

    private var isBusy: Bool { gmail.busyMessageIDs.contains(ref.messageID) }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            header
            if showTaskRow { taskRow }
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            conversation
        }
        .background(ThingsColor.backgroundContent)
        .task(id: ref.messageID) { await start() }
        // Begonnen aan een antwoord, analyse of taak: niet meer sluiten bij een klik ernaast.
        .onChange(of: replyRef) { _, new in if new != nil { markEngaged() } }
        .onChange(of: model.analyses.count) { _, _ in markEngaged() }
        .onChange(of: showTaskRow) { _, shown in if shown { markEngaged() } }
        // Is het gesprek gearchiveerd (of via slepen een kaart geworden en gearchiveerd), dan is dit paneel klaar.
        .onChange(of: gmail.messages) { _, new in
            if wasInList, !new.contains(where: { $0.threadID == ref.threadID }) { dismiss() }
        }
    }

    private func dismiss() { PanelStore.shared.closeMail(messageID: ref.messageID) }

    private func markEngaged() { PanelStore.shared.markEngaged(PanelKind.mail(ref).id) }

    private func start() async {
        taskTitle = ref.subject
        wasInList = gmail.messages.contains { $0.threadID == ref.threadID }
        await model.load()
        // Geen antwoordblok vooraf: dat komt pas bij ⌘R, Beantwoorden, Allen of Doorsturen.
        if ref.analyze, ClaudeKeychain.read() != nil {
            let target = model.mails.contains { $0.id == ref.messageID } ? ref.messageID : (model.mails.last?.id ?? ref.messageID)
            if let block = model.analyze(messageID: target) { scrollTarget = "analyse-\(block.id)" }
        }
    }

    private func composeRef(_ mode: ComposeRef.Mode, for mail: ThreadMail) -> ComposeRef {
        let sender = MailAddress.parse(mail.from).valid.first
        let source = MailRef(messageID: mail.id, threadID: ref.threadID,
                             subject: mail.subject.isEmpty ? ref.subject : mail.subject,
                             fromName: sender?.name, fromAddress: sender?.address, account: ref.account)
        return ComposeRef(mode: mode, source: source)
    }

    // MARK: Greep

    private var grabber: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ThingsColor.textTertiary)
            .frame(width: 96, height: 24)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThingsColor.backgroundSidebar))
            .contentShape(Rectangle())
            .padding(.top, 8)
            .padding(.bottom, 6)
            .onDrag({
                MailDragState.shared.begin()
                return gmail.dragProvider(for: ref.summary)
            }, preview: { dragChip })
            .onHover { inside in
                if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
            }
            .help("Pak vast en sleep naar een kolom, de agenda of het Claude-icoon")
            .accessibilityLabel("Sleep deze mail")
    }

    private var dragChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "envelope.fill").foregroundStyle(ThingsColor.accent)
            Text(ref.subject)
                .thingsFont(.todoTitle)
                .foregroundStyle(ThingsColor.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 260)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThingsColor.backgroundContent))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ThingsColor.separator))
    }

    // MARK: Kop

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ref.subject.isEmpty ? "(geen onderwerp)" : ref.subject)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ThingsColor.textPrimary)
                .textSelection(.enabled)
                .padding(.trailing, 28)
            HStack(spacing: 10) {
                Button {
                    Task {
                        gmail.note(account: ref.account, forMessageID: ref.threadID)
                        await gmail.archiveMessage(ref.summary, appState: appState)
                        dismiss()
                    }
                } label: {
                    Label("Archiveren", systemImage: "archivebox")
                }
                .disabled(isBusy)
                .help("Gesprek archiveren (⇧⌘A)")

                Button {
                    if let newest = model.mails.last, let block = model.analyze(messageID: newest.id) {
                        scrollTarget = "analyse-\(block.id)"
                    }
                } label: {
                    HStack(spacing: 5) {
                        ClaudeSpark().frame(width: 13, height: 13)
                        Text("Analyseer gesprek")
                    }
                }
                .disabled(model.mails.isEmpty)

                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showTaskRow.toggle() }
                } label: {
                    Label("Taak maken", systemImage: "checkmark.circle")
                }

                let source = ref.account ?? gmail.account(for: ref.messageID)
                let targets = gmail.accounts.filter { $0 != source }
                if !targets.isEmpty {
                    Menu {
                        ForEach(targets, id: \.self) { email in
                            Button(gmail.displayName(email)) {
                                Task {
                                    dismiss()
                                    await gmail.moveThread(threadID: ref.threadID, messageID: ref.messageID, from: source,
                                                           to: email, appState: appState)
                                }
                            }
                        }
                    } label: {
                        Label("Verplaats naar", systemImage: "tray.and.arrow.up")
                    }
                    .fixedSize()
                }
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var taskRow: some View {
        HStack(spacing: 8) {
            TextField("Titel van de taak", text: $taskTitle)
                .textFieldStyle(.roundedBorder)
            TextField("0", text: $minutesText)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
            Text("min")
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
            Picker("In kolom", selection: $targetColumnID) {
                ForEach(columnRecords) { Text($0.title).tag($0.key) }
            }
            .labelsHidden()
            .frame(maxWidth: 150)
            Button("Maak taak") {
                let column = columnRecords.first { $0.key == targetColumnID }?.column ?? .inbox
                let minutes = Int(minutesText.trimmingCharacters(in: .whitespaces)) ?? 0
                Task {
                    await gmail.createTask(from: ref.summary, title: taskTitle, minutes: minutes,
                                           column: column, context: context, appState: appState)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: Gesprek

    private enum Entry: Identifiable {
        case mail(ThreadMail)
        case analysis(ThreadAnalysisBlock)

        var id: String {
            switch self {
            case .mail(let mail): "mail-\(mail.id)"
            case .analysis(let block): "analyse-\(block.id)"
            }
        }
    }

    /// Mails op volgorde, met elke analyse direct na de mail waar hij over gaat.
    private var entries: [Entry] {
        var result: [Entry] = []
        let known = Set(model.mails.map(\.id))
        for mail in model.mails {
            result.append(.mail(mail))
            for block in model.analyses.filter({ $0.anchorMessageID == mail.id }).sorted(by: { $0.createdAt < $1.createdAt }) {
                result.append(.analysis(block))
            }
        }
        for block in model.analyses where !known.contains(block.anchorMessageID) && !model.mails.isEmpty {
            result.append(.analysis(block))
        }
        return newestAtBottom ? result : result.reversed()
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if let error = model.loadError {
                        Text(error)
                            .thingsFont(.notes)
                            .foregroundStyle(ThingsColor.deadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !newestAtBottom { replyBlock.id("reply") }
                    ForEach(entries) { entry in
                        switch entry {
                        case .mail(let mail):
                            ThreadMailCard(mail: mail,
                                           showsHistoryByDefault: model.mails.first?.id == mail.id,
                                           isExpanded: model.isExpanded(mail.id),
                                           onToggle: { model.toggle(mail.id) },
                                           onReply: { mode in
                                               replyRef = composeRef(mode, for: mail)
                                               withAnimation { proxy.scrollTo("reply", anchor: .center) }
                                           },
                                           onAnalyze: {
                                               if let block = model.analyze(messageID: mail.id) {
                                                   withAnimation { proxy.scrollTo("analyse-\(block.id)", anchor: .top) }
                                               }
                                           })
                                .id(entry.id)
                        case .analysis(let block):
                            ThreadAnalysisView(block: block,
                                               onAsk: { question in
                                                   markEngaged()
                                                   model.ask(question, in: block)
                                               },
                                               onInsert: insertIntoReply,
                                               onRemove: { model.remove(block) })
                                .id(entry.id)
                        }
                    }
                    if newestAtBottom { replyBlock.id("reply") }
                }
                .padding(14)
            }
            .scrollIndicators(.never)
            .background(ThingsColor.backgroundSidebar)
            .background {
                // ⌘R: allen beantwoorden op de nieuwste mail.
                Button("") {
                    guard let newest = model.mails.last else { return }
                    replyRef = composeRef(.replyAll, for: newest)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation { proxy.scrollTo("reply", anchor: .center) }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                // Even wachten tot het nieuwe blok in de lijst staat.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                    scrollTarget = nil
                }
            }
            .onChange(of: model.mails.count) { _, count in
                guard count > 0 else { return }
                // Naar de nieuwste mail.
                let newest = model.mails.last.map { "mail-\($0.id)" } ?? "reply"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    proxy.scrollTo(newest, anchor: newestAtBottom ? .top : .bottom)
                }
            }
        }
    }

    @ViewBuilder private var replyBlock: some View {
        if let replyRef, let mail = model.mails.first(where: { $0.id == replyRef.source?.messageID }) {
            let draft = model.latestDraft
            ComposeView(ref: replyRef, embedded: true, preloaded: mail.content, externalBody: $replyBody,
                        suggestion: draft.flatMap { $0.id == usedDraftID ? nil : $0.text },
                        onSuggestionDone: { usedDraftID = model.latestDraft?.id },
                        onSent: {
                            // Verstuurd: het gesprek klapt weg.
                            PanelStore.shared.foldAway(id: PanelKind.mail(ref).id)
                        },
                        onDiscard: {
                            usedDraftID = model.latestDraft?.id
                            self.replyRef = nil
                        })
                .id(replyRef.id)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ThingsColor.separator))
        }
    }

    /// "Concept in antwoord": voegt de tekst toe onder wat er al staat.
    private func insertIntoReply(_ text: String) {
        if replyRef == nil, let newest = model.mails.last { replyRef = composeRef(.replyAll, for: newest) }
        let current = replyBody.trimmingCharacters(in: .whitespacesAndNewlines)
        replyBody = current.isEmpty ? text : replyBody + "\n\n" + text
        usedDraftID = model.latestDraft?.id
    }
}

// MARK: - Eén mail in het gesprek

private struct ThreadMailCard: View {
    let mail: ThreadMail
    /// Er staan geen eerdere mails als blok in het gesprek: dan is de geciteerde geschiedenis de enige plek waar
    /// die te lezen is, en staat ze meteen open.
    var showsHistoryByDefault = false
    let isExpanded: Bool
    let onToggle: () -> Void
    let onReply: (ComposeRef.Mode) -> Void
    let onAnalyze: () -> Void

    @State private var showHistory = false
    @State private var bodyHeight: CGFloat = 40
    @State private var historyHeight: CGFloat = 40

    private var sender: (name: String, address: String) {
        if let first = MailAddress.parse(mail.from).valid.first {
            return (first.name ?? first.address, first.address)
        }
        return (mail.from, "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                SenderAvatar(name: sender.name, address: sender.address, isSent: mail.isSent)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(sender.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ThingsColor.textPrimary)
                        Spacer()
                        Text(Self.dateText(mail.date))
                            .thingsFont(.metadata)
                            .foregroundStyle(ThingsColor.textTertiary)
                    }
                    if isExpanded {
                        recipients
                    } else {
                        Text(mail.snippet)
                            .thingsFont(.metadata)
                            .foregroundStyle(ThingsColor.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            // Klik op de kop klapt de mail open of dicht.
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if isExpanded { expandedBody }
        }
        .task(id: mail.id) { if showsHistoryByDefault { showHistory = true } }
        .padding(isExpanded ? 14 : 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ThingsColor.backgroundContent))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ThingsColor.separator))
    }

    @ViewBuilder private var expandedBody: some View {
        if let error = mail.loadError {
            Text(error)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.deadline)
        } else if mail.content == nil {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            AutoHeightMailWebView(html: mail.mainHTML, height: $bodyHeight, margin: "12px 14px")
                .frame(height: bodyHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            if let history = mail.historyHTML {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showHistory.toggle() }
                } label: {
                    Label(showHistory ? "Verberg geschiedenis" : "Toon geschiedenis", systemImage: "clock.arrow.circlepath")
                        .thingsFont(.metadata)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThingsColor.accent)
                if showHistory {
                    AutoHeightMailWebView(html: history, height: $historyHeight, margin: "12px 14px")
                        .frame(height: historyHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            if let files = mail.content?.files, !files.isEmpty {
                MailAttachmentsView(files: files, folderName: mail.id)
            }

            HStack(spacing: 14) {
                Spacer()
                action("Beantwoorden", "arrowshape.turn.up.left") { onReply(.reply) }
                action("Allen", "arrowshape.turn.up.left.2") { onReply(.replyAll) }
                action("Doorsturen", "arrowshape.turn.up.right") { onReply(.forward) }
                Button(action: onAnalyze) {
                    HStack(spacing: 4) {
                        ClaudeSpark().frame(width: 12, height: 12)
                        Text("Analyse").thingsFont(.metadata)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThingsColor.textSecondary)
                .help("Laat Claude deze mail analyseren, met het hele gesprek als context")
                Spacer()
            }
        }
    }

    @ViewBuilder private var recipients: some View {
        let to = mail.to
        let cc = mail.cc
        if !to.isEmpty || !cc.isEmpty {
            Text([to.isEmpty ? nil : "Aan: \(Self.names(to))", cc.isEmpty ? nil : "Cc: \(Self.names(cc))"]
                .compactMap { $0 }.joined(separator: "   "))
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.accent)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private func action(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol).thingsFont(.metadata)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ThingsColor.textSecondary)
    }

    private static func names(_ list: String) -> String {
        let parsed = MailAddress.parse(list).valid
        guard !parsed.isEmpty else { return list }
        return parsed.map { $0.name ?? $0.address }.joined(separator: ", ")
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).hour().minute().locale(Locale(identifier: "nl_NL")))
    }
}

// MARK: - Analyse door Claude in het gesprek

private struct ThreadAnalysisView: View {
    let block: ThreadAnalysisBlock
    let onAsk: (String) -> Void
    let onInsert: (String) -> Void
    let onRemove: () -> Void

    @State private var question = ""
    @State private var isExpanded: Bool

    init(block: ThreadAnalysisBlock, onAsk: @escaping (String) -> Void, onInsert: @escaping (String) -> Void,
         onRemove: @escaping () -> Void) {
        self.block = block
        self.onAsk = onAsk
        self.onInsert = onInsert
        self.onRemove = onRemove
        // Een nieuwe analyse staat open; een eerdere (bewaarde) staat dicht met alleen de samenvatting.
        _isExpanded = State(initialValue: block.turns.isEmpty || block.phase.isBusy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ClaudeSpark().frame(width: 18, height: 18)
                Text("Analyse door Claude")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ThingsColor.textPrimary)
                Text("\(block.modelTitle) · \(block.createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "nl_NL"))))")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textTertiary)
                Spacer()
                if block.phase.isBusy { ProgressView().controlSize(.small) }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThingsColor.textSecondary)
                Menu {
                    if block.phase.isBusy { Button("Stoppen") { block.cancel() } }
                    Button("Verwijder analyse", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } }

            if !isExpanded, let summary = block.summary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .lineLimit(2)
                    .padding(.leading, 26)
            }

            if isExpanded {
                ForEach(block.turns) { turn in
                    if let q = turn.question { bubble(q) }
                    MarkdownLite(text: turn.answer)
                }
                if let q = block.liveQuestion { bubble(q) }
                status
                if !block.liveAnswer.isEmpty { MarkdownLite(text: block.liveAnswer) }

                if let usage = block.usage {
                    Text(usage).thingsFont(.metadata).foregroundStyle(ThingsColor.textTertiary)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Vervolgvraag…", text: $question, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .onSubmit(send)
                    Button("Stuur", action: send)
                        .disabled(block.phase.isBusy || block.turns.isEmpty
                                  || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let draft = block.draft {
                        Button {
                            onInsert(draft)
                        } label: {
                            Label("Concept in antwoord", systemImage: "text.append")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(claudeTint)
                        .help("Voegt het conceptantwoord toe aan je antwoord onderaan")
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(claudeTint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(claudeTint.opacity(0.45)))
    }

    private func send() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !block.phase.isBusy, !block.turns.isEmpty else { return }
        question = ""
        onAsk(text)
    }

    private func bubble(_ text: String) -> some View {
        Text(text)
            .thingsFont(.notes)
            .foregroundStyle(ThingsColor.textPrimary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThingsColor.backgroundContent))
    }

    @ViewBuilder private var status: some View {
        switch block.phase {
        case .preparing, .waiting:
            Label("Claude leest het gesprek en de bijlagen…", systemImage: "ellipsis.circle")
                .thingsFont(.metadata).foregroundStyle(ThingsColor.textSecondary)
        case .failed(let message):
            Text(message)
                .thingsFont(.notes)
                .foregroundStyle(ThingsColor.deadline)
                .textSelection(.enabled)
        default:
            EmptyView()
        }
    }
}

// MARK: - HTML met meegroeiende hoogte

/// Mail-HTML in een gesprek: zo hoog als de inhoud (gemeten na het laden), scrollen gaat naar het gesprek eromheen.
struct AutoHeightMailWebView: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    /// Ruimte rond de inhoud (CSS-marge van de body).
    var margin = "0"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PassthroughWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = PassthroughWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.postsFrameChangedNotifications = true
        context.coordinator.observe(view)
        return view
    }

    func updateNSView(_ view: PassthroughWebView, context: Context) {
        context.coordinator.parent = self
        // Vergelijk de HTML zelf; het document eromheen pas bouwen als er echt iets anders te tonen is.
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        view.loadHTMLString(MailWebView.document(html, allowRemote: true, margin: margin, fitsContent: true), baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AutoHeightMailWebView
        var lastHTML: String?
        private weak var webView: WKWebView?
        private var lastWidth: CGFloat = 0
        private var observer: NSObjectProtocol?

        init(_ parent: AutoHeightMailWebView) { self.parent = parent }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        func observe(_ view: WKWebView) {
            webView = view
            observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view,
                                                              queue: .main) { [weak self] _ in
                guard let self, let view = self.webView, abs(view.frame.width - self.lastWidth) > 1 else { return }
                self.lastWidth = view.frame.width
                self.measure()
            }
        }

        func measure() {
            // Script van de app zelf (niet van de mail): mag ook als JavaScript voor de inhoud uit staat.
            // Inclusief de marges (body.scrollHeight telt die niet mee): anders blijft er een scrollbalk over.
            let script = "Math.ceil(Math.max(document.body.scrollHeight, document.documentElement.scrollHeight))"
            webView?.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
                guard let self, case .success(let value) = result else { return }
                let height = (value as? NSNumber).map { CGFloat(truncating: $0) } ?? 0
                if height > 0, abs(height - self.parent.height) > 1 {
                    DispatchQueue.main.async { self.parent.height = height + 4 }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measure()
            // Afbeeldingen en lettertypen kunnen de hoogte nog veranderen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.measure() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.measure() }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                if let url = action.request.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

/// WKWebView die scrollen doorgeeft aan het gesprek eromheen.
final class PassthroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

// MARK: - Weergave van de HTML

/// WKWebView zonder JavaScript en met een beveiligingsregel die alles van het internet blokkeert (tot je "Laden" kiest):
/// geen tracking-pixels, geen scripts. Links openen in de browser.
struct MailWebView: NSViewRepresentable {
    let html: String
    let allowRemote: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let document = Self.document(html, allowRemote: allowRemote)
        guard context.coordinator.lastDocument != document else { return }
        context.coordinator.lastDocument = document
        view.loadHTMLString(document, baseURL: nil)
    }

    static func document(_ inner: String, allowRemote: Bool, margin: String = "18px 22px", fitsContent: Bool = false) -> String {
        let images = allowRemote ? "img-src data: https: http:" : "img-src data:"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; \(images); style-src 'unsafe-inline'; font-src data:">
        <meta name="color-scheme" content="light">
        <style>
        html { color-scheme: light; }
        body { margin: \(margin); background: #fff; color: #1d1d1f;
               font: 14px -apple-system, "Helvetica Neue", sans-serif; line-height: 1.45; word-wrap: break-word; }
        img { max-width: 100%; height: auto; }
        pre.plain { white-space: pre-wrap; font: 13px ui-monospace, Menlo, monospace; margin: 0; }
        blockquote { margin: 8px 0 8px 4px; padding-left: 12px; border-left: 3px solid #d0d0d5; color: #55555a; }
        table { max-width: 100%; }
        \(fitsContent ? "html, body { overflow: hidden; }" : "")
        </style></head><body>\(inner)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastDocument = ""

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                if let url = action.request.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)   // alleen het laden van onze eigen HTML
            }
        }
    }
}
