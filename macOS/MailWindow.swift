import AppKit
import SwiftData
import SwiftUI
import WebKit
import WerkbankCore

/// Wat een mailvenster nodig heeft om zijn mail op te halen (waardeert als venster-id, dus één venster per mail).
struct MailRef: Codable, Hashable {
    var messageID: String
    var threadID: String
    var subject: String
    var fromName: String?
    var fromAddress: String?
    /// De mailbox waaruit de mail komt; het paneel kan intussen naar een andere zijn geschakeld.
    var account: String?

    @MainActor
    init(message: GmailMessageSummary) {
        messageID = message.id
        threadID = message.threadID
        subject = message.subject
        fromName = message.fromName
        fromAddress = message.fromAddress
        account = GmailSession.shared.account(for: message.id)
    }

    var summary: GmailMessageSummary {
        GmailMessageSummary(id: messageID, threadID: threadID, fromName: fromName, fromAddress: fromAddress, subject: subject)
    }
}

/// De mail als echte mailweergave in een paneel boven het hoofdvenster. Aan de drie streepjes bovenaan pak je hem vast en sleep je hem
/// naar een kolom van het board, naar de agenda (taak plus inplannen) of naar het Claude-icoon in het Gmail-paneel.
struct MailWindowView: View {
    let ref: MailRef

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \ColumnRecord.sortOrder) private var columnRecords: [ColumnRecord]

    private let gmail = GmailSession.shared

    @State private var mail: MailContent?
    @State private var loadError: String?
    @State private var wasInList = false
    @State private var taskTitle = ""
    @State private var minutesText = ""
    @State private var targetColumnID = BoardColumn.inboxID

    private var isBusy: Bool { gmail.busyMessageIDs.contains(ref.messageID) }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            header
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            content
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            actions
        }
        .background(ThingsColor.backgroundContent)
        .task(id: ref) { await load() }
        // Is de mail via slepen een kaart geworden (en dus gearchiveerd), dan is dit venster klaar.
        .onChange(of: gmail.messages) { _, new in
            if wasInList, !new.contains(where: { $0.id == ref.messageID }) { dismiss() }
        }
    }

    private func dismiss() { PanelStore.shared.closeMail(messageID: ref.messageID) }

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
        VStack(alignment: .leading, spacing: 4) {
            Text(ref.subject.isEmpty ? "(geen onderwerp)" : ref.subject)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ThingsColor.textPrimary)
                .textSelection(.enabled)
            if let mail {
                headerRow("Van", mail.from)
                headerRow("Aan", mail.to)
                headerRow("Cc", mail.cc)
                headerRow("Datum", mail.date)
            } else {
                headerRow("Van", [ref.fromName, ref.fromAddress.map { "<\($0)>" }].compactMap { $0 }.joined(separator: " "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    @ViewBuilder private func headerRow(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textTertiary)
                    .frame(width: 44, alignment: .trailing)
                Text(value)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
    }

    // MARK: Inhoud

    @ViewBuilder private var content: some View {
        if let loadError {
            Text(loadError)
                .thingsFont(.notes)
                .foregroundStyle(ThingsColor.deadline)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let mail {
            VStack(spacing: 0) {
                MailWebView(html: mail.displayHTML, allowRemote: true)
            }
        } else {
            ProgressView("Mail ophalen…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        taskTitle = ref.subject
        wasInList = gmail.messages.contains { $0.id == ref.messageID }
        gmail.note(account: ref.account, forMessageID: ref.messageID)
        gmail.note(account: ref.account, forMessageID: ref.threadID)
        do {
            let raw = try await gmail.rawMessageData(id: ref.messageID)
            mail = await Task.detached(priority: .userInitiated) { MailContentParser.parse(raw) }.value
        } catch {
            loadError = "Mail ophalen uit Gmail mislukt: \(error.localizedDescription)"
        }
    }

    // MARK: Acties

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    Task {
                        await gmail.archiveMessage(ref.summary, appState: appState)
                        dismiss()
                    }
                } label: {
                    Label("Archiveren", systemImage: "archivebox")
                }
                .disabled(isBusy)

                Button {
                    ClaudeAnalyzer.shared.analyze(messageID: ref.messageID, subject: ref.subject)
                    PanelStore.shared.open(.claude)
                } label: {
                    HStack(spacing: 5) {
                        ClaudeSpark().frame(width: 13, height: 13)
                        Text("Analyseer met Claude")
                    }
                }
                .disabled(isBusy)
                Spacer()
            }

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
        }
        .padding(12)
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

    static func document(_ inner: String, allowRemote: Bool) -> String {
        let images = allowRemote ? "img-src data: https: http:" : "img-src data:"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; \(images); style-src 'unsafe-inline'; font-src data:">
        <meta name="color-scheme" content="light">
        <style>
        html { color-scheme: light; }
        body { margin: 18px 22px; background: #fff; color: #1d1d1f;
               font: 14px -apple-system, "Helvetica Neue", sans-serif; line-height: 1.45; word-wrap: break-word; }
        img { max-width: 100%; height: auto; }
        pre.plain { white-space: pre-wrap; font: 13px ui-monospace, Menlo, monospace; margin: 0; }
        blockquote { margin: 8px 0 8px 4px; padding-left: 12px; border-left: 3px solid #d0d0d5; color: #55555a; }
        table { max-width: 100%; }
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
