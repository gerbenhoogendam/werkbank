import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

/// Waar een opstelvenster mee begint: een nieuwe mail, of een antwoord op / doorsturen van een bestaande.
struct ComposeRef: Codable, Hashable {
    enum Mode: String, Codable, Hashable { case new, reply, replyAll, forward }

    var id = UUID()
    var mode: Mode
    var source: MailRef?
}

/// Mail opstellen als paneel boven het hoofdvenster. Verstuurt via de Gmail API, met de handtekening uit Voorkeuren.
struct ComposeView: View {
    let ref: ComposeRef
    /// In een gesprek: geen eigen titel en geen citaatvoorbeeld (het gesprek staat erboven).
    var embedded = false
    /// De mail waarop wordt geantwoord, als die al is opgehaald.
    var preloaded: MailContent?
    /// De tekst van de mail buiten dit venster bewaren (blijft staan als je een andere mail kiest om op te antwoorden).
    var externalBody: Binding<String>?
    /// Conceptantwoord van Claude, lichtgrijs; Tab neemt het over, zelf typen laat het vallen.
    var suggestion: String?
    var onSuggestionDone: (() -> Void)?
    var onSent: (() -> Void)?
    /// In een gesprek: het concept weggooien (prullenbak onderaan).
    var onDiscard: (() -> Void)?
    /// In een eigen venster (losgehaald): `restored` is wat er al ingevuld was.
    var detached = false
    var restored: ComposeDraft?

    init(ref: ComposeRef, embedded: Bool = false, preloaded: MailContent? = nil, externalBody: Binding<String>? = nil,
         suggestion: String? = nil, onSuggestionDone: (() -> Void)? = nil, onSent: (() -> Void)? = nil,
         onDiscard: (() -> Void)? = nil, detached: Bool = false, restored: ComposeDraft? = nil) {
        self.ref = ref
        self.embedded = embedded
        self.detached = detached
        self.restored = restored
        self.preloaded = preloaded
        self.externalBody = externalBody
        self.suggestion = suggestion
        self.onSuggestionDone = onSuggestionDone
        self.onSent = onSent
        self.onDiscard = onDiscard
    }

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    private let gmail = GmailSession.shared

    private enum Field { case to, body }
    @FocusState private var focus: Field?

    @State private var fromAccount = ""
    @State private var toText = ""
    @State private var ccText = ""
    @State private var bccText = ""
    @State private var subject = ""
    @State private var localBody = ""
    @State private var attachments: [MailAttachment] = []
    @State private var useSignature = true
    @State private var original: MailContent?
    @State private var isLoading = false
    @State private var isSending = false
    @State private var importing = false
    @State private var errorText: String?
    @State private var suggestionDismissed = false
    @State private var signatureHeight: CGFloat = 60
    /// De handtekening van de gekozen mailbox, één keer opgebouwd (niet bij elke toetsaanslag).
    @State private var signaturePreview: String?
    @State private var showCc = false
    @State private var reviewer = MailReviewer()
    @State private var showBcc = false
    /// Opmaak van de tekst (werkbalk, HTML bij versturen).
    @State private var rich = RichTextController()

    private static let maxAttachmentBytes = 18_000_000

    private var bodyBinding: Binding<String> { externalBody ?? $localBody }
    private var bodyText: String { bodyBinding.wrappedValue }

    private var totalAttachmentBytes: Int { attachments.reduce(0) { $0 + $1.data.count } }
    private var isReply: Bool { ref.mode == .reply || ref.mode == .replyAll }

    var body: some View {
        VStack(spacing: 0) {
            fields
            if !isLoading {
                RichTextToolbar(controller: rich)
                Rectangle().fill(ThingsColor.separator).frame(height: 1)
            }
            if isLoading {
                ProgressView("Mail ophalen…")
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: embedded ? 120 : .infinity)
            } else if embedded {
                // In een gesprek groeit het opstelblok mee; het gesprek eromheen scrolt.
                editorContent
            } else {
                ScrollView { editorContent }
                    .scrollIndicators(.never)
                quotePreview
            }
            reviewSection
            footer
        }
        .background(ThingsColor.backgroundContent)
        .task { await prepare() }
        .onChange(of: suggestion) { _, _ in suggestionDismissed = false }
        .onChange(of: bodyText) { _, _ in markEngaged() }
        .onChange(of: toText) { _, _ in markEngaged() }
        .onChange(of: subject) { _, _ in markEngaged() }
        .onChange(of: attachments.count) { _, _ in markEngaged() }
        .onChange(of: fromAccount, initial: true) { _, account in signaturePreview = MailSignatures.preview(for: account) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in addFile(url) }
                }
            }
            return true
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach { addFile($0, scoped: true) } }
        }
    }

    // MARK: Velden

    private var fields: some View {
        VStack(spacing: 0) {
            if embedded {
                Text(titleText)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            } else {
                Text(titleText)
                    .thingsFont(.heading)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
                    .padding(.trailing, 36)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            row("Aan") {
                TextField("", text: $toText).focused($focus, equals: .to)
            } trailing: {
                if !showCc && ccText.isEmpty { fieldToggle("Cc") { showCc = true } }
                if !showBcc && bccText.isEmpty { fieldToggle("Bcc") { showBcc = true } }
            }
            if showCc || !ccText.isEmpty { row("Cc") { TextField("", text: $ccText) } }
            if showBcc || !bccText.isEmpty { row("Bcc") { TextField("", text: $bccText) } }
            row("Van") { fromField }
            row("Onderwerp") { TextField("", text: $subject) }
        }
    }

    /// Eén regel zoals in een mailprogramma: label en veld, met een dunne lijn die niet tot de randen loopt.
    private func row<Content: View, Trailing: View>(_ label: String, @ViewBuilder content: () -> Content,
                                                    @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .foregroundStyle(ThingsColor.textTertiary)
            content()
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .font(.system(size: 13))
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(ThingsColor.separator.opacity(0.5)).frame(height: 0.5) }
        .padding(.horizontal, 20)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        row(label, content: content, trailing: { EmptyView() })
    }

    private func fieldToggle(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .foregroundStyle(ThingsColor.accent)
    }

    @ViewBuilder private var fromField: some View {
        if gmail.accounts.count > 1 {
            Menu {
                ForEach(gmail.accounts, id: \.self) { email in
                    Button(fromLabel(email)) { fromAccount = email }
                }
            } label: {
                Text(fromLabel(fromAccount))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(ThingsColor.accent)
        } else {
            Text(fromLabel(fromAccount)).foregroundStyle(ThingsColor.accent)
        }
    }

    private func fromLabel(_ email: String) -> String {
        guard !email.isEmpty else { return "—" }
        let name = MailSignatures.senderName(for: email).flatMap { $0.isEmpty ? nil : $0 } ?? gmail.displayName(email)
        return "\(name) (\(email))"
    }

    private var titleText: String {
        switch ref.mode {
        case .new: "Nieuwe mail"
        case .reply: "Beantwoorden"
        case .replyAll: "Allen beantwoorden"
        case .forward: "Doorsturen"
        }
    }

    // MARK: Tekst

    /// Staat de suggestie van Claude nog open (tot je Tab drukt of zelf begint te typen)?
    private var activeSuggestion: String? {
        guard let suggestion, !suggestion.isEmpty, !suggestionDismissed else { return nil }
        return suggestion
    }

    /// Tekst, eventuele suggestie en de handtekening direct eronder, zoals in een mailprogramma.
    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReplyTextView(text: bodyBinding,
                          controller: rich,
                          suggestion: bodyText.isEmpty ? activeSuggestion : nil,
                          focusOnAppear: isReply,
                          minHeight: ReplyTextView.twoLines,
                          onTab: acceptSuggestion,
                          onTyped: { if activeSuggestion != nil { dismissSuggestion() } })
                .padding(.horizontal, 15)
                .padding(.top, 10)
            if !bodyText.isEmpty, let activeSuggestion {
                // Er staat al tekst: de suggestie eronder, Tab voegt hem toe.
                VStack(alignment: .leading, spacing: 4) {
                    Text(activeSuggestion)
                        .font(.system(size: 13))
                        .foregroundStyle(ThingsColor.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            if useSignature, let signature = signaturePreview {
                // De handtekening zoals hij onder de mail komt (bewerken doe je in Voorkeuren › Mail).
                AutoHeightMailWebView(html: signature, height: $signatureHeight)
                    .frame(height: signatureHeight)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // Klik naast of onder de tekst: cursor achteraan in het tekstvak.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { rich.focusEnd() })
    }

    @ViewBuilder private var quotePreview: some View {
        if let original, !original.quotableText.isEmpty {
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            ScrollView {
                Text(original.quotableText)
                    .font(.system(size: 12))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 130)
            .background(ThingsColor.backgroundSidebar)
        }
    }

    /// Een los opstelpaneel waarin je iets hebt ingevuld, sluit niet meer bij een klik ernaast.
    private func markEngaged() {
        guard !embedded, !detached, !isLoading else { return }
        PanelStore.shared.markEngaged(PanelKind.compose(ref).id)
    }

    // MARK: Controle door Claude

    @ViewBuilder private var reviewSection: some View {
        switch reviewer.phase {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Claude controleert…").thingsFont(.metadata).foregroundStyle(ThingsColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        case .failed(let message):
            Text(message)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.deadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        case .done:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ClaudeSpark().frame(width: 13, height: 13)
                    Text(reviewer.issues.isEmpty ? "Geen opmerkingen" : "\(reviewer.issues.count) opmerking\(reviewer.issues.count == 1 ? "" : "en")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ThingsColor.textPrimary)
                    Spacer()
                    if reviewer.issues.contains(where: { canApply($0) }) {
                        Button("Alles toepassen") {
                            for issue in reviewer.issues where canApply(issue) { apply(issue) }
                        }
                        .buttonStyle(.borderless)
                    }
                    Button { reviewer.reset() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }
                ForEach(reviewer.issues) { issue in reviewRow(issue) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThingsColor.backgroundSidebar))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func reviewRow(_ issue: ReviewIssue) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(issue.isLanguage ? "Taal" : "Inhoud")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(issue.isLanguage ? Color.fieldLabel : Color.orange))
                Text(issue.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if canApply(issue) {
                    Button("Toepassen") { apply(issue) }
                        .buttonStyle(.borderless)
                }
                Button("Negeer") { reviewer.dismiss(issue) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(ThingsColor.textSecondary)
            }
            if !issue.quote.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(issue.quote)
                        .strikethrough(!issue.replacement.isEmpty)
                        .foregroundStyle(ThingsColor.textSecondary)
                    if !issue.replacement.isEmpty {
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(ThingsColor.textTertiary)
                        Text(issue.replacement).foregroundStyle(Color.green)
                    }
                }
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 2)
            }
        }
    }

    private func canApply(_ issue: ReviewIssue) -> Bool {
        !issue.replacement.isEmpty && !issue.quote.isEmpty && bodyText.contains(issue.quote)
    }

    /// Vervangt het aangewezen stuk (de eerste keer dat het voorkomt) en haalt de opmerking weg.
    private func apply(_ issue: ReviewIssue) {
        if !rich.replaceFirst(issue.quote, with: issue.replacement) {
            guard let range = bodyText.range(of: issue.quote) else { return }
            bodyBinding.wrappedValue = bodyText.replacingCharacters(in: range, with: issue.replacement)
        }
        reviewer.dismiss(issue)
    }

    private func acceptSuggestion() -> Bool {
        guard let activeSuggestion else { return false }
        let current = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            bodyBinding.wrappedValue = activeSuggestion
        } else if !rich.append("\n\n" + activeSuggestion) {
            bodyBinding.wrappedValue = bodyText + "\n\n" + activeSuggestion
        }
        suggestionDismissed = true
        onSuggestionDone?()
        return true
    }

    private func dismissSuggestion() {
        suggestionDismissed = true
        onSuggestionDone?()
    }

    // MARK: Onderkant

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(attachments.enumerated()), id: \.offset) { index, file in
                            HStack(spacing: 4) {
                                Image(systemName: "paperclip")
                                Text(file.name).lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                                    .foregroundStyle(ThingsColor.textTertiary)
                                Button { attachments.remove(at: index) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain)
                            }
                            .thingsFont(.metadata)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(ThingsColor.backgroundSidebar))
                        }
                    }
                }
            }
            if let errorText {
                Text(errorText).thingsFont(.metadata).foregroundStyle(ThingsColor.deadline)
            }
            HStack(spacing: 12) {
                Button { importing = true } label: { Label("Bijlage", systemImage: "paperclip") }
                Toggle("Handtekening", isOn: $useSignature)
                    .toggleStyle(.checkbox)
                    .disabled(signaturePreview == nil)
                Button {
                    reviewer.run(draft: bodyText, subject: subject, original: original)
                } label: {
                    HStack(spacing: 5) {
                        ClaudeSpark().frame(width: 13, height: 13)
                        Text("Controleer")
                    }
                }
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reviewer.phase == .running)
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .help("Taal en inhoud laten controleren (⇧⌘K)")
                if let source = ref.source, ref.mode != .forward {
                    MailTimerButton(threadID: source.threadID, subject: source.subject, senders: senders(of: source))
                }
                if !detached {
                    Button { detach() } label: { Image(systemName: "macwindow.badge.plus") }
                        .help("Loshalen in een eigen venster")
                }
                if let onDiscard {
                    Button {
                        bodyBinding.wrappedValue = ""
                        attachments = []
                        onDiscard()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Concept verwijderen")
                }
                Spacer()
                if isSending { ProgressView().controlSize(.small) }
                Button("Verstuur") { sendDirectly() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isSending || isLoading)
                    .help("Versturen (⌘↩ of ⇧⌘D)")
                // ⇧⌘D: hetzelfde, zoals in Mail.
                Button("") { sendDirectly() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(isSending || isLoading)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(ThingsColor.separator.opacity(0.5)).frame(height: 0.5).padding(.horizontal, 20) }
    }

    // MARK: Voorbereiden

    private func prepare() async {
        if let restored {
            restore(restored)
            return
        }
        fromAccount = ref.source?.account ?? gmail.activeAccount ?? gmail.accounts.first ?? ""
        guard let source = ref.source else {
            focus = .to
            return
        }
        isLoading = preloaded == nil
        defer { isLoading = false }
        gmail.note(account: source.account, forMessageID: source.messageID)
        gmail.note(account: source.account, forMessageID: source.threadID)
        do {
            let mail: MailContent
            if let preloaded {
                mail = preloaded
            } else {
                let raw = try await gmail.rawMessageData(id: source.messageID)
                mail = await Task.detached(priority: .userInitiated) { MailContentParser.parse(raw) }.value
            }
            original = mail
            subject = ReplyBuilder.subject(mail.subject.isEmpty ? source.subject : mail.subject, forward: ref.mode == .forward)
            if ref.mode == .forward, attachments.isEmpty {
                // Doorsturen: de bijlagen van de oorspronkelijke mail gaan mee (zolang ze samen binnen de grens passen).
                var total = 0
                for file in mail.files where total + file.data.count <= Self.maxAttachmentBytes {
                    attachments.append(file)
                    total += file.data.count
                }
                if attachments.count < mail.files.count {
                    errorText = "Niet alle bijlagen passen in één mail (maximaal \(Self.maxAttachmentBytes / 1_000_000) MB); de grootste zijn weggelaten."
                }
            }
            if isReply {
                let recipients = ReplyBuilder.recipients(from: mail.from, replyTo: mail.replyTo, to: mail.to, cc: mail.cc,
                                                         replyingAs: source.account, myAddresses: gmail.accounts,
                                                         replyAll: ref.mode == .replyAll)
                toText = recipients.to.map(\.displayString).joined(separator: ", ")
                ccText = recipients.cc.map(\.displayString).joined(separator: ", ")
            }
            focus = isReply ? .body : .to
        } catch {
            errorText = "Oorspronkelijke mail ophalen mislukt: \(error.localizedDescription)"
            subject = ReplyBuilder.subject(source.subject, forward: ref.mode == .forward)
        }
    }

    // MARK: Bijlagen

    private func addFile(_ url: URL, scoped: Bool = false) {
        let access = scoped ? url.startAccessingSecurityScopedResource() : false
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorText = "\(url.lastPathComponent) kon niet worden gelezen."
            return
        }
        guard totalAttachmentBytes + data.count <= Self.maxAttachmentBytes else {
            errorText = "Bijlagen mogen samen niet groter zijn dan \(Self.maxAttachmentBytes / 1_000_000) MB."
            return
        }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        attachments.append(MailAttachment(name: url.lastPathComponent, mediaType: type, data: data))
        errorText = nil
    }

    // MARK: Loshalen

    /// Zet wat er staat over naar een eigen venster (bijvoorbeeld op een ander scherm) en sluit dit opstelblok.
    private func detach() {
        let draft = ComposeDraft(fromAccount: fromAccount, to: toText, cc: ccText, bcc: bccText, subject: subject,
                                 body: bodyText, attachments: attachments, useSignature: useSignature,
                                 showCc: showCc, showBcc: showBcc, original: original, bodyRich: rich.rtf())
        openWindow(value: DetachedCompose(ref: ref, draftID: ComposeDrafts.store(draft)))
        if embedded {
            bodyBinding.wrappedValue = ""
            attachments = []
            onDiscard?()
        } else {
            PanelStore.shared.close(.compose(ref))
        }
    }

    private func restore(_ draft: ComposeDraft) {
        fromAccount = draft.fromAccount
        toText = draft.to
        ccText = draft.cc
        bccText = draft.bcc
        subject = draft.subject
        bodyBinding.wrappedValue = draft.body
        if let rtf = draft.bodyRich { rich.load(rtf: rtf, text: draft.body) }
        attachments = draft.attachments
        useSignature = draft.useSignature
        showCc = draft.showCc
        showBcc = draft.showBcc
        original = draft.original
        focus = draft.to.isEmpty ? .to : .body
    }

    /// Afzenders van het gesprek, om bij de timer de klant te bepalen.
    private func senders(of source: MailRef) -> [String] {
        var list: [String] = []
        if let original { list.append(original.from) }
        if let address = source.fromAddress {
            list.append(MailAddress(name: source.fromName, address: address).displayString)
        }
        return list
    }

    // MARK: Versturen

    private func sendDirectly() {
        guard !isSending, !isLoading, validate() else { return }
        Task { await send() }
    }

    private func validate() -> Bool {
        errorText = nil
        let to = MailAddress.parse(toText), cc = MailAddress.parse(ccText), bcc = MailAddress.parse(bccText)
        let invalid = to.invalid + cc.invalid + bcc.invalid
        if let first = invalid.first {
            errorText = "Dit is geen geldig e-mailadres: \(first)"
        } else if to.valid.isEmpty && cc.valid.isEmpty && bcc.valid.isEmpty {
            errorText = "Vul minstens één ontvanger in."
        } else if fromAccount.isEmpty {
            errorText = "Er is geen mailbox om vanaf te versturen."
        } else {
            return true
        }
        return false
    }

    private func send() async {
        let to = MailAddress.parse(toText).valid, cc = MailAddress.parse(ccText).valid, bcc = MailAddress.parse(bccText).valid
        let name = MailSignatures.senderName(for: fromAccount).flatMap { $0.isEmpty ? nil : $0 }
        var mail = ComposedMail(from: MailAddress(name: name, address: fromAccount), subject: subject, bodyText: bodyText)
        mail.bodyHTML = rich.html()
        mail.to = to
        mail.cc = cc
        mail.bcc = bcc
        mail.attachments = attachments
        if useSignature, let signature = MailSignatures.html(for: fromAccount) {
            mail.signatureHTML = signature
            mail.signatureImage = MailSignatures.logo(for: fromAccount)
        }
        if let original, !original.quotableText.isEmpty {
            mail.quote = original.quotableText
            mail.quoteIntro = ReplyBuilder.quoteIntro(date: original.date, from: original.from, forward: ref.mode == .forward,
                                                      subject: original.subject)
        }
        if isReply, let original {
            mail.inReplyTo = original.messageID
            mail.references = ReplyBuilder.references(old: original.references, messageID: original.messageID)
        }
        // Een gesprek bestaat alleen in de mailbox waar het in staat.
        let threadID = isReply && ref.source?.account == fromAccount ? ref.source?.threadID : nil

        isSending = true
        defer { isSending = false }
        do {
            try await gmail.send(raw: MailComposer.build(mail), threadID: threadID, account: fromAccount)
            SendSound.play()
            // Een antwoord in het gesprek van een kaart: die wacht nu op de klant.
            let waiting = isReply ? ref.source.flatMap { WaitingWatcher.shared.didReply(threadID: $0.threadID) } : nil
            let message = waiting.map { "Mail verzonden · kaart naar \($0)" } ?? "Mail verzonden"
            // Antwoord of doorgestuurd: 2 seconden lang archiveert Enter het gesprek.
            if let source = ref.source {
                SendFollowUp.offerArchive(source, message: message, appState: appState)
            } else {
                appState.announce(message)
            }
            if embedded {
                bodyBinding.wrappedValue = ""
                attachments = []
                onSent?()
            } else if detached {
                onSent?()
            } else {
                PanelStore.shared.closeAfterSending(id: PanelKind.compose(ref).id)
            }
        } catch {
            errorText = "Versturen mislukt: \(error.localizedDescription)"
        }
    }
}

/// Het verzendgeluid van Mail; is dat niet te vinden, dan een systeemgeluid.
enum SendSound {
    private static var current: NSSound?   // vasthouden zolang hij speelt

    static func play() {
        let candidates = ["/System/Applications/Mail.app/Contents/Resources/Mail Sent.aiff",
                          "/Applications/Mail.app/Contents/Resources/Mail Sent.aiff"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if let sound = NSSound(contentsOfFile: path, byReference: true) {
                current = sound
                sound.play()
                return
            }
        }
        current = NSSound(named: "Pop")
        current?.play()
    }
}

// MARK: - Los venster

/// Wat er in een opstelblok stond op het moment van loshalen.
struct ComposeDraft {
    var fromAccount: String
    var to: String
    var cc: String
    var bcc: String
    var subject: String
    var body: String
    var attachments: [MailAttachment]
    var useSignature: Bool
    var showCc: Bool
    var showBcc: Bool
    var original: MailContent?
    /// De tekst met opmaak (RTF), zodat die meegaat naar het eigen venster.
    var bodyRich: Data? = nil
}

/// Concepten die naar een eigen venster gaan (een venster krijgt alleen een id mee).
@MainActor
enum ComposeDrafts {
    private static var drafts: [UUID: ComposeDraft] = [:]

    static func store(_ draft: ComposeDraft) -> UUID {
        let id = UUID()
        drafts[id] = draft
        return id
    }

    static func draft(_ id: UUID) -> ComposeDraft? { drafts[id] }
    static func remove(_ id: UUID) { drafts[id] = nil }
}

struct DetachedCompose: Codable, Hashable {
    var ref: ComposeRef
    var draftID: UUID
}

/// Een losgehaald opstelvenster; sluit na versturen of weggooien.
struct DetachedComposeWindow: View {
    let value: DetachedCompose
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ComposeView(ref: value.ref,
                    onSent: {
                        DuoWindowFold.shared.markSending()
                        dismiss()
                    },
                    onDiscard: { dismiss() },
                    detached: true, restored: ComposeDrafts.draft(value.draftID))
            .frame(minWidth: 520, minHeight: 420)
            .background(DuoWindowHook().frame(width: 0, height: 0))
            .onDisappear { ComposeDrafts.remove(value.draftID) }
    }
}
