import QuickLook
import SwiftUI
import WebKit
import WerkbankCore

/// Een gesprek: de oudere mails ingeklapt, de nieuwste open als kaart die naar voren komt. In de kaart de knoppen
/// voor wat je met de mail doet (Claude, taak, inplannen, tijd, contact); onderaan beantwoorden en archiveren.
struct PhoneThreadView: View {
    let mail: PhoneMail
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    private let gmail = PhoneGmail.shared
    private let stars = PhoneStars.shared

    @State private var messages: [GmailThreadMessage] = []
    @State private var contents: [String: MailContent] = [:]
    @State private var open: Set<String> = []
    @State private var loadError: String?
    @State private var compose: PhoneComposeRequest?
    @State private var action: PhoneMailAction?
    @State private var preview: URL?
    @State private var showActions = false

    private var newest: GmailThreadMessage? { messages.last }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        PhEyebrow(text: messages.count == 1 ? "1 bericht" : "\(messages.count) berichten")
                        Text((mail.item.subject.isEmpty ? "(geen onderwerp)" : mail.item.subject).uppercased())
                            .font(Ph.poster(38))
                            .foregroundStyle(Ph.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                    if let loadError {
                        Text(loadError).font(Ph.text(13)).foregroundStyle(Ph.danger)
                    }
                    ForEach(messages, id: \.id) { message in
                        if open.contains(message.id) {
                            expanded(message)
                        } else {
                            collapsed(message)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
            bottomBar
        }
        .phScreen()
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sheet(item: $compose) { request in
            PhoneComposeView(request: request).presentationBackground(Ph.paper)
        }
        .sheet(item: $action) { action in
            PhoneMailActionSheet(action: action)
                .presentationBackground(Ph.paper)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Meer", isPresented: $showActions) {
            Button(stars.contains(mail.item.threadID) ? "Ster eraf" : "Ster") { stars.toggle([mail.item.threadID]) }
            Button("Markeer als ongelezen") { markUnread() }
            Button("Verplaats naar mailbox") { action = PhoneMailAction(kind: .move, mail: mail) }
            Button("Naar de prullenbak", role: .destructive) { trash() }
        }
        .quickLookPreview($preview)
    }

    // MARK: Kop en voet

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                    PhCaps(text: gmail.displayName(mail.account), size: 12, color: Ph.ink)
                }
                .frame(height: 44)
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            Spacer()
            Button { stars.toggle([mail.item.threadID]) } label: {
                if stars.contains(mail.item.threadID) {
                    PhStar(size: 19)
                } else {
                    Image(systemName: "star").font(.system(size: 18))
                }
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Ster")
            Button { markUnread() } label: { Image(systemName: "envelope.badge").font(.system(size: 17)) }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Markeer als ongelezen")
            Button { showActions = true } label: { Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)) }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Meer")
        }
        .foregroundStyle(Ph.ink)
        .padding(.trailing, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Button { reply(.reply) } label: { Label("ANTWOORD", systemImage: "arrowshape.turn.up.left") }
                .buttonStyle(PhPrimaryStyle(height: 50))
                .layoutPriority(1)
            Button("ALLEN") { reply(.replyAll) }.buttonStyle(PhSecondaryStyle(height: 50))
            Button("DOOR") { reply(.forward) }.buttonStyle(PhSecondaryStyle(height: 50))
            Button("ARCHIEF") { archive() }.buttonStyle(PhInkStyle(height: 50))
        }
        .labelStyle(.titleOnly)
        .disabled(newest == nil)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Ph.paper)
        .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
    }

    // MARK: Mails

    private func collapsed(_ message: GmailThreadMessage) -> some View {
        Button {
            open.insert(message.id)
            Task { await loadContent(message.id) }
        } label: {
            HStack(spacing: 10) {
                PhAvatar(name: senderName(message.from), size: 28, isMe: message.labels.contains("SENT"))
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(senderName(message.from)).font(Ph.text(13.5, .semibold))
                        Spacer()
                        Text(PhoneMailSettings.timeText(message.date)).font(Ph.text(12)).foregroundStyle(Ph.ink2)
                    }
                    Text(message.snippet).font(Ph.text(12.5)).foregroundStyle(Ph.ink2).lineLimit(1)
                }
            }
            .foregroundStyle(Ph.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .phCard()
        }
        .buttonStyle(.plain)
    }

    private func expanded(_ message: GmailThreadMessage) -> some View {
        let content = contents[message.id]
        let isNewest = message.id == newest?.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                action = PhoneMailAction(kind: .sender(message.from), mail: mail)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    PhAvatar(name: senderName(message.from), size: 36, isMe: message.labels.contains("SENT"))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(senderName(message.from)).font(Ph.text(15, .semibold))
                            Spacer()
                            Text(message.date.formatted(date: .abbreviated, time: .shortened))
                                .font(Ph.text(12.5)).foregroundStyle(Ph.ink2)
                        }
                        Text(recipientsLine(message)).font(Ph.text(12.5)).foregroundStyle(Ph.ink2).lineLimit(1)
                    }
                }
                .foregroundStyle(Ph.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            Rectangle().fill(Ph.hair).frame(height: 1)
            if let content {
                PhoneMailWebView(html: content.displayHTML)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                if !content.files.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(content.files.enumerated()), id: \.offset) { _, file in
                            Button { preview = PhoneFiles.temporaryURL(for: file) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc").font(.system(size: 14))
                                    Text(file.name).font(Ph.text(13)).lineLimit(1)
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                                        .font(Ph.text(12)).foregroundStyle(Ph.ink2)
                                }
                                .foregroundStyle(Ph.ink)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 40)
                                .phWell(Ph.paper)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            } else {
                ProgressView().tint(Ph.ink).frame(maxWidth: .infinity, minHeight: 80)
            }
            if isNewest { tools }
        }
        .modifier(PhExpandedCard(isNewest: isNewest))
        .padding(.bottom, isNewest ? 4 : 0)
    }

    private var tools: some View {
        HStack(spacing: 5) {
            tool("Claude", symbol: "sparkle", tint: Ph.claude) { action = PhoneMailAction(kind: .claude, mail: mail) }
            tool("Taak", symbol: "checkmark.square") { action = PhoneMailAction(kind: .task, mail: mail) }
            tool("Plan", symbol: "calendar") { action = PhoneMailAction(kind: .plan, mail: mail) }
            tool("Tijd", symbol: "clock") { action = PhoneMailAction(kind: .time, mail: mail) }
            tool("Contact", symbol: "person.crop.circle.badge.plus") {
                action = PhoneMailAction(kind: .contact(newest?.from ?? ""), mail: mail)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func tool(_ title: String, symbol: String, tint: Color = Ph.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(tint)
                Text(title.uppercased()).font(Ph.text(9.5, .semibold)).tracking(1.2)
            }
            .foregroundStyle(Ph.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .phCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: Laden en handelingen

    private func load() async {
        do {
            let list = try await gmail.thread(mail.item.threadID, account: mail.account)
            messages = list
            var toOpen = Set(list.filter { $0.labels.contains("UNREAD") }.map(\.id))
            if let last = list.last { toOpen.insert(last.id) }
            open = toOpen
            for id in toOpen { await loadContent(id) }
            if list.contains(where: { $0.labels.contains("UNREAD") }) {
                await gmail.setUnread(false, [(threadID: mail.item.threadID, account: mail.account)])
            }
        } catch {
            loadError = "Gesprek ophalen mislukt"
        }
    }

    private func loadContent(_ id: String) async {
        guard contents[id] == nil else { return }
        if let content = try? await gmail.content(id, account: mail.account) { contents[id] = content }
    }

    private func reply(_ mode: PhoneComposeRequest.Mode) {
        guard let newest else { return }
        compose = PhoneComposeRequest(mode: mode, account: mail.account, threadID: mail.item.threadID,
                                      source: newest, content: contents[newest.id])
    }

    private func archive() {
        let thread = (threadID: mail.item.threadID, account: mail.account)
        dismiss()
        Task {
            _ = await gmail.archive([thread])
            appState.showToast("Mail gearchiveerd")
        }
    }

    private func trash() {
        let thread = (threadID: mail.item.threadID, account: mail.account)
        dismiss()
        Task {
            _ = await gmail.trash([thread])
            appState.showToast("Mail in de prullenbak")
        }
    }

    private func markUnread() {
        let thread = (threadID: mail.item.threadID, account: mail.account)
        dismiss()
        Task { await gmail.setUnread(true, [thread]) }
    }

    private func senderName(_ from: String) -> String {
        let address = MailAddress.parse(from).valid.first
        if let name = address?.name, !name.isEmpty { return name }
        return address?.address ?? from
    }

    private func recipientsLine(_ message: GmailThreadMessage) -> String {
        let to = MailAddress.parse(message.to).valid.map { $0.name ?? $0.address }
        let cc = MailAddress.parse(message.cc).valid.map { $0.name ?? $0.address }
        var line = "aan " + to.joined(separator: ", ")
        if !cc.isEmpty { line += " · cc " + cc.joined(separator: ", ") }
        return line
    }
}

/// De nieuwste mail komt naar voren (inktrand, harde schaduw); oudere geopende mails zijn gewone kaarten.
private struct PhExpandedCard: ViewModifier {
    let isNewest: Bool

    func body(content: Content) -> some View {
        if isNewest { content.phRaisedCard() } else { content.phCard() }
    }
}

/// De mail zelf in een webweergave die zo hoog wordt als de inhoud (de pagina scrollt, niet de mail).
struct PhoneMailWebView: View {
    let html: String
    @State private var height: CGFloat = 120

    var body: some View {
        PhoneMailWebRepresentable(html: html, height: $height)
            .frame(height: height)
    }
}

private struct PhoneMailWebRepresentable: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        let page = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: https: cid:; style-src 'unsafe-inline'; font-src data: https:">
        <style>body{margin:6px;font:15px/1.5 Helvetica,Arial,sans-serif;color:#0B0B0B;word-wrap:break-word}
        img{max-width:100%;height:auto}table{max-width:100%}pre{white-space:pre-wrap;font:inherit}
        blockquote{margin:0 0 0 8px;padding-left:8px;border-left:2px solid #DADAD2;color:#55554F}</style></head>
        <body>\(html)</body></html>
        """
        view.loadHTMLString(page, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var loaded: String?

        init(height: Binding<CGFloat>) { self.height = height }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { value, _ in
                if let number = value as? CGFloat {
                    DispatchQueue.main.async { self.height.wrappedValue = number + 16 }
                } else if let number = value as? Double {
                    DispatchQueue.main.async { self.height.wrappedValue = CGFloat(number) + 16 }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// Bijlagen als tijdelijk bestand, om te bekijken of te delen.
enum PhoneFiles {
    static func temporaryURL(for file: MailAttachment) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Bijlagen", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = file.name.isEmpty ? "bijlage" : file.name.replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent(name)
        do {
            try file.data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
