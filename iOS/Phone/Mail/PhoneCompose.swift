import SwiftUI
import WerkbankCore

/// Wat er opgesteld wordt: een nieuwe mail, een antwoord (aan de afzender of allen) of doorsturen.
struct PhoneComposeRequest: Identifiable {
    enum Mode { case new, reply, replyAll, forward }

    let id = UUID()
    var mode: Mode
    var account: String?
    var threadID: String?
    var source: GmailThreadMessage?
    var content: MailContent?
    var to: String = ""
    var subject: String = ""
    /// Tekst om mee te beginnen (het concept van Claude).
    var body: String = ""
}

/// Opstellen: van welke mailbox, aan, cc, onderwerp (icoon), tekst; bij beantwoorden het origineel ingeklapt eronder.
/// Handtekening en afzendernaam komen uit de voorkeuren van de Mac (via iCloud).
struct PhoneComposeView: View {
    let request: PhoneComposeRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    private let gmail = PhoneGmail.shared

    @State private var from = ""
    @State private var to = ""
    @State private var cc = ""
    @State private var showCc = false
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var showQuote = false
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case to, cc, subject, body }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 10) {
                    fields
                    bodyCard
                    if let error {
                        Text(error).font(Ph.text(13)).foregroundStyle(Ph.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .phScreen()
        .onAppear(perform: prefill)
        .interactiveDismissDisabled(!bodyText.isEmpty)
    }

    // MARK: Kop

    private var title: String {
        switch request.mode {
        case .new: "Nieuwe mail"
        case .reply, .replyAll: "Antwoord"
        case .forward: "Doorsturen"
        }
    }

    private var header: some View {
        HStack {
            Button("ANNULEER") { dismiss() }
                .font(Ph.text(12, .semibold))
                .tracking(1.6)
                .foregroundStyle(Ph.ink2)
                .frame(height: 44)
            Spacer()
            Text(title.uppercased()).font(Ph.poster(28)).foregroundStyle(Ph.ink)
            Spacer()
            Button {
                Task { await send() }
            } label: {
                if sending { ProgressView().tint(Ph.ink) } else { Text("VERSTUUR") }
            }
            .buttonStyle(PhPrimaryStyle(height: 40))
            .frame(width: 110)
            .disabled(sending || MailAddress.parse(to).valid.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: Velden

    private var fields: some View {
        VStack(spacing: 0) {
            PhFieldRow(label: "Van") {
                Menu {
                    ForEach(gmail.accounts, id: \.self) { account in
                        Button(gmail.displayName(account)) { from = account }
                    }
                } label: {
                    HStack(spacing: 6) {
                        PhCaps(text: gmail.displayName(from), size: 12, color: Ph.ink)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Ph.ink)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .phWell(Ph.band)
                }
                Spacer()
            }
            PhFieldRow(label: "Aan") {
                TextField("", text: $to)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .to)
                if !showCc {
                    Button("CC") { showCc = true }
                        .font(Ph.text(11, .semibold))
                        .foregroundStyle(Ph.ink2)
                }
            }
            if showCc {
                PhFieldRow(label: "Cc") {
                    TextField("", text: $cc)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .cc)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "textformat")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ph.ink2)
                    .frame(width: 74, alignment: .leading)
                    .accessibilityLabel("Onderwerp")
                TextField("", text: $subject)
                    .font(Ph.text(15, .semibold))
                    .focused($focus, equals: .subject)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
        }
        .font(Ph.text(15))
        .foregroundStyle(Ph.ink)
        .phCard()
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $bodyText)
                .font(Ph.mail(16))
                .foregroundStyle(Ph.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 220)
                .focused($focus, equals: .body)
            if let signature = signatureText, !signature.isEmpty {
                Text(signature)
                    .font(Ph.text(13))
                    .foregroundStyle(Ph.ink2)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(Ph.hair).frame(height: 1) }
            }
            if let content = request.content, request.mode != .new {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showQuote.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showQuote ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                        PhCaps(text: "Origineel", size: 11)
                        Spacer()
                    }
                    .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
                if showQuote {
                    PhoneMailWebView(html: content.displayHTML)
                        .padding(6)
                        .phWell(Ph.paper)
                }
                if request.mode == .forward, !content.files.isEmpty {
                    ForEach(Array(content.files.enumerated()), id: \.offset) { _, file in
                        HStack(spacing: 8) {
                            Image(systemName: "paperclip")
                            Text(file.name).lineLimit(1)
                            Spacer()
                        }
                        .font(Ph.text(13))
                        .foregroundStyle(Ph.ink)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 36)
                        .phWell(Ph.paper)
                    }
                }
            }
        }
        .padding(14)
        .phCard()
    }

    // MARK: Invullen en versturen

    private var signatureHTML: String? {
        let all = UserDefaults.standard.dictionary(forKey: "mail.signatureHTML") as? [String: String] ?? [:]
        let value = all[from] ?? all[""]
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value : nil
    }

    /// De handtekening als tekst, om te zien wat er onder de mail komt.
    private var signatureText: String? {
        guard let html = signatureHTML else { return nil }
        let text = ContactCard.signatureText(html: html, subject: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var senderName: String? {
        let all = UserDefaults.standard.dictionary(forKey: "mail.senderName") as? [String: String] ?? [:]
        return [all[from], all[""]].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    private func prefill() {
        from = request.account ?? UserDefaults.standard.string(forKey: "phone.mail.newFrom") ?? gmail.accounts.first ?? ""
        if !gmail.accounts.contains(from) { from = gmail.accounts.first ?? "" }
        to = request.to
        subject = request.subject
        bodyText = request.body
        guard let content = request.content else {
            focus = .to
            return
        }
        switch request.mode {
        case .new:
            focus = .to
        case .reply, .replyAll:
            let recipients = ReplyBuilder.recipients(from: content.from, replyTo: content.replyTo, to: content.to,
                                                     cc: content.cc, replyingAs: from, myAddresses: gmail.accounts,
                                                     replyAll: request.mode == .replyAll)
            to = recipients.to.map(display).joined(separator: ", ")
            cc = recipients.cc.map(display).joined(separator: ", ")
            showCc = !cc.isEmpty
            subject = ReplyBuilder.subject(content.subject, forward: false)
            focus = .body
        case .forward:
            subject = ReplyBuilder.subject(content.subject, forward: true)
            focus = .to
        }
    }

    private func display(_ address: MailAddress) -> String {
        if let name = address.name, !name.isEmpty { return "\(name) <\(address.address)>" }
        return address.address
    }

    private func send() async {
        let recipients = MailAddress.parse(to)
        let copies = MailAddress.parse(cc)
        guard !recipients.valid.isEmpty, recipients.invalid.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }),
              copies.invalid.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            error = "Controleer de adressen"
            return
        }
        sending = true
        defer { sending = false }
        var mail = ComposedMail(from: MailAddress(name: senderName, address: from), subject: subject, bodyText: bodyText)
        mail.to = recipients.valid
        mail.cc = copies.valid
        mail.signatureHTML = signatureHTML
        if let logo = signatureLogo { mail.signatureImage = logo }
        var threadID: String?
        if let content = request.content, request.mode != .new {
            let forward = request.mode == .forward
            mail.quote = content.quotableText
            mail.quoteIntro = ReplyBuilder.quoteIntro(date: content.date, from: content.from, forward: forward,
                                                      subject: content.subject)
            mail.quoteHTML = content.forwardHTML
            mail.inlineImages = content.forwardImages
            if forward {
                mail.attachments = content.files
            } else {
                mail.inReplyTo = content.messageID.isEmpty ? nil : content.messageID
                mail.references = ReplyBuilder.references(old: content.references, messageID: content.messageID)
                threadID = request.threadID
            }
        }
        let raw = MailComposer.build(mail)
        do {
            try await gmail.send(raw, threadID: threadID, account: from)
            appState.showToast("Verstuurd")
            dismiss()
        } catch {
            self.error = "Versturen mislukt: \(error.localizedDescription)"
        }
    }

    private var signatureLogo: MailAttachment? {
        let all = UserDefaults.standard.dictionary(forKey: "mail.signatureLogo") as? [String: Data] ?? [:]
        guard let data = all[from] ?? all[""] else { return nil }
        let isJPEG = data.starts(with: [0xFF, 0xD8])
        return MailAttachment(name: isJPEG ? "logo.jpg" : "logo.png", mediaType: isJPEG ? "image/jpeg" : "image/png",
                              data: data)
    }
}
