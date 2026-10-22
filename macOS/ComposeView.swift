import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

/// Waar een opstelvenster mee begint: een nieuwe mail, of een antwoord op / doorsturen van een bestaande.
struct ComposeRef: Hashable {
    enum Mode: String, Hashable { case new, reply, replyAll, forward }

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

    init(ref: ComposeRef, embedded: Bool = false, preloaded: MailContent? = nil, externalBody: Binding<String>? = nil,
         suggestion: String? = nil, onSuggestionDone: (() -> Void)? = nil, onSent: (() -> Void)? = nil) {
        self.ref = ref
        self.embedded = embedded
        self.preloaded = preloaded
        self.externalBody = externalBody
        self.suggestion = suggestion
        self.onSuggestionDone = onSuggestionDone
        self.onSent = onSent
    }

    @Environment(AppState.self) private var appState
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
    @State private var confirmSend = false
    @State private var importing = false
    @State private var errorText: String?
    @State private var suggestionDismissed = false
    @State private var signatureHeight: CGFloat = 60

    private static let maxAttachmentBytes = 18_000_000

    private var bodyBinding: Binding<String> { externalBody ?? $localBody }
    private var bodyText: String { bodyBinding.wrappedValue }

    private var totalAttachmentBytes: Int { attachments.reduce(0) { $0 + $1.data.count } }
    private var isReply: Bool { ref.mode == .reply || ref.mode == .replyAll }

    var body: some View {
        VStack(spacing: 0) {
            fields
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            if isLoading {
                ProgressView("Mail ophalen…").frame(maxWidth: .infinity, maxHeight: embedded ? 160 : .infinity)
            } else {
                editor
            }
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            footer
        }
        .background(ThingsColor.backgroundContent)
        .task { await prepare() }
        .onChange(of: suggestion) { _, _ in suggestionDismissed = false }
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
        .confirmationDialog("Mail versturen?", isPresented: $confirmSend, titleVisibility: .visible) {
            Button("Verstuur") { Task { await send() } }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Aan: \(toText.isEmpty ? "—" : toText)")
        }
    }

    // MARK: Velden

    private var fields: some View {
        VStack(spacing: 0) {
            Text(titleText)
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .padding(.trailing, 36)
                .padding(.vertical, embedded ? 8 : 10)
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            row("Van") {
                if gmail.accounts.count > 1 {
                    Picker("Van", selection: $fromAccount) {
                        ForEach(gmail.accounts, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                } else {
                    Text(fromAccount).foregroundStyle(ThingsColor.textSecondary)
                }
            }
            row("Aan") { TextField("", text: $toText).focused($focus, equals: .to) }
            row("Cc") { TextField("", text: $ccText) }
            row("Bcc") { TextField("", text: $bccText) }
            row("Onderwerp") { TextField("", text: $subject) }
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textTertiary)
                .frame(width: 68, alignment: .trailing)
            content()
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .overlay(alignment: .bottom) { Rectangle().fill(ThingsColor.separator.opacity(0.6)).frame(height: 1) }
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

    private var editor: some View {
        VStack(spacing: 0) {
            ReplyTextView(text: bodyBinding,
                          suggestion: bodyText.isEmpty ? activeSuggestion : nil,
                          focusOnAppear: isReply,
                          onTab: acceptSuggestion,
                          onTyped: { if activeSuggestion != nil { dismissSuggestion() } })
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: embedded ? 180 : nil)
            if !bodyText.isEmpty, let activeSuggestion {
                // Er staat al tekst: de suggestie eronder, Tab voegt hem toe.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggestie van Claude · Tab voegt toe")
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textTertiary)
                    Text(activeSuggestion)
                        .font(.system(size: 13))
                        .foregroundStyle(ThingsColor.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 17)
                .padding(.bottom, 8)
            }
            if useSignature, let signature = MailSignatures.preview(for: fromAccount) {
                // De handtekening zoals hij onder de mail komt (niet te bewerken; dat doe je in Voorkeuren › Mail).
                AutoHeightMailWebView(html: signature, height: $signatureHeight)
                    .frame(height: min(signatureHeight, 180))
                    .padding(.horizontal, 17)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
                    .opacity(0.85)
            }
            if !embedded, let original, !original.quotableText.isEmpty {
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
    }

    private func acceptSuggestion() -> Bool {
        guard let activeSuggestion else { return false }
        let current = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        bodyBinding.wrappedValue = current.isEmpty ? activeSuggestion : bodyText + "\n\n" + activeSuggestion
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
                    .disabled(MailSignatures.html(for: fromAccount) == nil)
                Spacer()
                if isSending { ProgressView().controlSize(.small) }
                Button("Verstuur") { validateThenConfirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isSending || isLoading)
                    .help("Versturen (⌘↩ of ⇧⌘D)")
                // ⇧⌘D: direct versturen, net als in Mail.
                Button("") { sendDirectly() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(isSending || isLoading)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
    }

    // MARK: Voorbereiden

    private func prepare() async {
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
            if isReply {
                let recipients = ReplyBuilder.recipients(from: mail.from, replyTo: mail.replyTo, to: mail.to, cc: mail.cc,
                                                         myAddresses: gmail.accounts, replyAll: ref.mode == .replyAll)
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

    // MARK: Versturen

    private func validateThenConfirm() {
        if validate() { confirmSend = true }
    }

    /// ⇧⌘D: meteen versturen, zonder bevestiging.
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
            appState.showToast("Mail verzonden")
            if embedded {
                bodyBinding.wrappedValue = ""
                attachments = []
                onSent?()
            } else {
                PanelStore.shared.close(.compose(ref))
            }
        } catch {
            errorText = "Versturen mislukt: \(error.localizedDescription)"
        }
    }
}
