import SwiftUI
import WerkbankCore

/// Een map van een mailbox (of van alle mailboxen, bij de vaste mappen).
struct PhoneFolderRef: Hashable {
    let folder: MailFolder
    let account: String
}

/// Terug-knop bovenaan een scherm in de mail.
struct PhBackBar: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                    PhCaps(text: title, size: 12, color: Ph.ink)
                }
                .frame(height: 44)
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            Spacer()
        }
        .foregroundStyle(Ph.ink)
        .padding(.trailing, 16)
        .padding(.top, 8)
    }
}

/// Mappen van een mailbox: de vaste mappen en de eigen labels uit Gmail.
struct PhoneFoldersView: View {
    @Environment(\.dismiss) private var dismiss
    private let gmail = PhoneGmail.shared
    private let stars = PhoneStars.shared

    @State private var account: String
    @State private var labels: [PhoneLabel] = []
    @State private var draftCount: Int?
    @State private var error: String?

    static var system: [MailFolder] { [.inbox, .starred, .sent, .drafts, .all, .trash] }

    init(account: String) {
        _account = State(initialValue: account)
    }

    var body: some View {
        VStack(spacing: 0) {
            PhBackBar(title: "Inbox", action: { dismiss() })
            PhHeader(eyebrow: account, title: "Mappen")
                .padding(.bottom, 12)
            if gmail.accounts.count > 1 {
                PhSegmented(items: gmail.accounts.map { .init(value: $0, title: gmail.displayName($0)) }, selection: $account)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        ForEach(Self.system, id: \.self) { folder in
                            NavigationLink(value: PhoneMailRoute.folder(PhoneFolderRef(folder: folder, account: account))) {
                                folderRow(mark: Self.mark(folder), title: folder == .inbox ? "Inbox" : folder.title,
                                          count: count(folder), strong: folder == .inbox, depth: 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .phCard()
                    if !labels.isEmpty {
                        PhCaps(text: "Labels").padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(labels) { label in
                                let folder = MailFolder.label(account: account, id: label.label.id, name: label.label.name)
                                NavigationLink(value: PhoneMailRoute.folder(PhoneFolderRef(folder: folder, account: account))) {
                                    folderRow(mark: nil, title: label.label.leaf, count: label.total.map { "\($0)" } ?? "",
                                              strong: (label.unread ?? 0) > 0, depth: label.label.depth)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .phCard()
                    }
                    if let error {
                        Text(error).font(Ph.text(13)).foregroundStyle(Ph.danger)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .phScreen()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: account) { await load() }
    }

    private func folderRow(mark: String?, title: String, count: String, strong: Bool, depth: Int) -> some View {
        HStack(spacing: 14) {
            if let mark {
                Text(mark)
                    .font(Ph.poster(16))
                    .foregroundStyle(Ph.ink)
                    .frame(width: 30, height: 30)
                    .phWell(Ph.band)
            } else {
                Image(systemName: "tag")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ph.ink2)
                    .frame(width: 30, height: 30)
                    .padding(.leading, CGFloat(depth) * 16)
            }
            Text(title).font(Ph.text(15)).foregroundStyle(Ph.ink).lineLimit(1)
            Spacer(minLength: 4)
            Text(count).font(Ph.text(12.5, .semibold)).foregroundStyle(strong ? Ph.olive : Ph.ink2)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ph.ink3)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
    }

    private func count(_ folder: MailFolder) -> String {
        switch folder {
        case .inbox:
            let unread = gmail.inbox[account]?.filter(\.isUnread).count ?? 0
            return unread > 0 ? "\(unread)" : ""
        case .starred:
            let starred = gmail.inbox[account]?.filter { stars.contains($0.threadID) }.count ?? 0
            return starred > 0 ? "\(starred)" : ""
        case .drafts:
            return (draftCount ?? 0) > 0 ? "\(draftCount ?? 0)" : ""
        default:
            return ""
        }
    }

    static func mark(_ folder: MailFolder) -> String {
        switch folder {
        case .inbox: "IN"
        case .starred: "ST"
        case .sent: "VS"
        case .drafts: "CO"
        case .all: "AL"
        case .spam: "SP"
        case .trash: "PB"
        case .label: ""
        }
    }

    private func load() async {
        guard !account.isEmpty else { return }
        error = nil
        draftCount = await gmail.labelCounts("DRAFT", account: account)?.total
        do {
            labels = try await gmail.userLabels(account: account)
        } catch {
            labels = []
            self.error = "Labels ophalen mislukt"
        }
    }
}

/// De mails in één map. Bij de vaste mappen kies je Alle of één mailbox; Concepten opent een concept in het
/// opstelscherm.
struct PhoneFolderView: View {
    let ref: PhoneFolderRef
    @Environment(\.dismiss) private var dismiss
    private let gmail = PhoneGmail.shared
    private let outbox = PhoneOutbox.shared

    @State private var box: String
    @State private var mails: [PhoneMail] = []
    @State private var loading = false
    @State private var error: String?
    @State private var compose: PhoneComposeRequest?
    @State private var openingDraft: String?

    init(ref: PhoneFolderRef) {
        self.ref = ref
        _box = State(initialValue: ref.account)
    }

    private var isDrafts: Bool { ref.folder == .drafts }
    /// Een eigen label hoort bij één mailbox; de vaste mappen kunnen ook over alle mailboxen.
    private var allowsAll: Bool { ref.folder.account == nil && gmail.accounts.count > 1 }
    private var chosenAccounts: [String] {
        if box.isEmpty { return gmail.accounts }
        return gmail.accounts.contains(box) ? [box] : []
    }

    private var title: String { ref.folder == .inbox ? "Inbox" : ref.folder.title }

    private var eyebrow: String {
        if isDrafts { return mails.count == 1 ? "1 concept" : "\(mails.count) concepten" }
        return mails.count == 1 ? "1 mail" : "\(mails.count) mails"
    }

    var body: some View {
        VStack(spacing: 0) {
            PhBackBar(title: "Mappen", action: { dismiss() })
            PhHeader(eyebrow: eyebrow, title: title, size: 48) {
                if isDrafts {
                    Button { compose = PhoneComposeRequest(mode: .new, account: box.isEmpty ? nil : box) } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(PhIconButtonStyle())
                    .accessibilityLabel("Nieuwe mail")
                }
            }
            .padding(.bottom, 12)
            if allowsAll {
                PhSegmented(items: boxItems, selection: $box)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(mails) { mail in
                        if isDrafts {
                            Button { openDraft(mail) } label: { draftRow(mail) }
                                .buttonStyle(.plain)
                                .disabled(openingDraft != nil)
                        } else {
                            NavigationLink(value: PhoneMailRoute.thread(mail)) {
                                PhoneMailRow(mail: mail, showsBox: box.isEmpty)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(mails.isEmpty ? Color.clear : Ph.card)
                .overlay(Rectangle().strokeBorder(mails.isEmpty ? Color.clear : Ph.line, lineWidth: 1))
                if mails.isEmpty {
                    Group {
                        if loading {
                            ProgressView().tint(Ph.ink)
                        } else {
                            Text("0").font(Ph.poster(96)).foregroundStyle(Ph.ink)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
                if let error {
                    Text(error).font(Ph.text(13)).foregroundStyle(Ph.danger).padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .refreshable { await load() }
        }
        .phScreen()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: box) { await load() }
        .onChange(of: outbox.sentCount) { _, _ in
            if isDrafts { Task { await load() } }
        }
        .sheet(item: $compose) { request in
            PhoneComposeView(request: request).presentationBackground(Ph.paper)
        }
    }

    private var boxItems: [PhSegmented<String>.Item] {
        [PhSegmented<String>.Item(value: "", title: "Alle")]
            + gmail.accounts.map { PhSegmented<String>.Item(value: $0, title: gmail.displayName($0)) }
    }

    private func draftRow(_ mail: PhoneMail) -> some View {
        let to = mail.item.recipients.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                PhCaps(text: "Aan", size: 10, color: Ph.ink3)
                Text(to.isEmpty ? "Geen ontvanger" : to)
                    .font(Ph.text(14, .semibold))
                    .foregroundStyle(to.isEmpty ? Ph.ink3 : Ph.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if openingDraft == mail.id { ProgressView().tint(Ph.ink) }
                if box.isEmpty { PhBoxTag(text: gmail.displayName(mail.account)) }
                Text(PhoneMailSettings.timeText(mail.item.date)).font(Ph.text(12)).foregroundStyle(Ph.ink2)
            }
            Text(mail.item.subject.isEmpty ? "(geen onderwerp)" : mail.item.subject)
                .font(Ph.text(14.5))
                .foregroundStyle(Ph.ink)
                .lineLimit(1)
            Text(mail.item.snippet)
                .font(Ph.text(13))
                .foregroundStyle(Ph.ink2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
    }

    private func load() async {
        let accounts = chosenAccounts
        guard !accounts.isEmpty else { return }
        loading = true
        defer { loading = false }
        error = nil
        let isStarred = ref.folder == .starred
        let labels = [ref.folder.labelID].compactMap { $0 }
        let includeTrash = ref.folder.includesSpamTrash
        let gmail = self.gmail
        var found: [PhoneMail] = []
        var failed = false
        await withTaskGroup(of: (String, [GmailMailItem]?).self) { group in
            for account in accounts {
                group.addTask {
                    let items: [GmailMailItem]?
                    if isStarred {
                        items = await gmail.starredItems(account: account)
                    } else {
                        items = try? await gmail.list(query: "", labels: labels, account: account, max: 50,
                                                      includeSpamTrash: includeTrash)
                    }
                    return (account, items)
                }
            }
            for await (account, items) in group {
                if let items {
                    found += items.map { PhoneMail(item: $0, account: account) }
                } else {
                    failed = true
                }
            }
        }
        mails = found.sorted { ($0.item.date ?? .distantPast) > ($1.item.date ?? .distantPast) }
        if failed { error = "Ophalen mislukt" }
    }

    private func openDraft(_ mail: PhoneMail) {
        openingDraft = mail.id
        Task {
            defer { openingDraft = nil }
            guard let content = try? await gmail.content(mail.item.id, account: mail.account) else {
                error = "Concept ophalen mislukt"
                return
            }
            var request = PhoneComposeRequest(mode: .new, account: mail.account, threadID: mail.item.threadID,
                                              to: content.to, subject: content.subject, body: content.quotableText)
            request.cc = content.cc
            request.draftID = mail.item.id
            request.draftAccount = mail.account
            request.draftReferences = content.references
            compose = request
        }
    }
}
