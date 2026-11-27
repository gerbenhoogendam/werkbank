import SwiftData
import SwiftUI
import WerkbankCore

/// Klanten bij mail: de klantenlijst (`ClientDirectory`, domein → klant) en anders de naam uit het domein.
@MainActor
enum PhoneClients {
    /// De klant uit de klantenlijst bij dit adres (volledig domein, dan het registreerbare domein); anders nil.
    static func knownClient(forAddress address: String) -> String? {
        guard let host = ClientNaming.domain(ofAddress: address) else { return nil }
        let map = ClientDirectory.shared.domainMap
        let registrable = ClientNaming.registrableDomain(of: host)
        guard let name = map[host] ?? map[registrable], !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return name
    }

    static func name(forAddress address: String, displayName: String?) -> String {
        ClientNaming.resolve(displayName: displayName, address: address, mapping: ClientDirectory.shared.domainMap)?.name
            ?? address
    }
}

/// Een klant: naam groot, uren deze maand, open taken op het board en alle mail van het domein in alle mailboxen,
/// per maand.
struct PhoneClientView: View {
    let address: String
    let displayName: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var cards: [TodoCard]
    @Query private var entries: [TimeEntry]
    private let gmail = PhoneGmail.shared

    @State private var mails: [PhoneMail] = []
    @State private var loading = true
    @State private var path: [PhoneMail] = []
    @State private var compose: PhoneComposeRequest?

    private var host: String { ClientNaming.domain(ofAddress: address) ?? "" }
    private var domain: String { ClientNaming.registrableDomain(of: host) }
    private var isFreemail: Bool { ClientNaming.freemailDomains.contains(domain) }
    private var name: String { PhoneClients.name(forAddress: address, displayName: displayName) }
    private var query: String {
        isFreemail ? "from:\(address) OR to:\(address)" : "from:@\(domain) OR to:@\(domain)"
    }

    private var openCards: [TodoCard] {
        let key = name.lowercased()
        let needle = (isFreemail ? address : domain).lowercased()
        return cards.filter { card in
            guard card.completedAt == nil, card.columnRaw != BoardColumn.doneID else { return false }
            if let label = card.clientLabel, label.lowercased() == key { return true }
            if !needle.isEmpty, let sender = card.senderLine, sender.lowercased().contains(needle) { return true }
            return false
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private var monthSeconds: TimeInterval {
        entries.filter { entry in
            entry.client.caseInsensitiveCompare(name) == .orderedSame
                && Calendar.current.isDate(entry.createdAt, equalTo: Date(), toGranularity: .month)
        }
        .reduce(0) { $0 + $1.elapsed() }
    }

    private var thisYear: [PhoneMail] {
        mails.filter { mail in
            guard let date = mail.item.date else { return false }
            return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        }
    }

    private var boxes: [String] {
        gmail.accounts.filter { account in mails.contains { $0.account == account } }
    }

    private struct MonthGroup: Identifiable {
        let id: Date
        let mails: [PhoneMail]
    }

    /// De mails per maand, nieuwste maand eerst.
    private var months: [MonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: mails) { mail -> Date in
            let date = mail.item.date ?? .distantPast
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        }
        return grouped.keys.sorted(by: >).map { key in
            MonthGroup(id: key, mails: (grouped[key] ?? []).sorted { ($0.item.date ?? .distantPast) > ($1.item.date ?? .distantPast) })
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                        VStack(alignment: .leading, spacing: 5) {
                            PhEyebrow(text: boxes.isEmpty ? "Klant" : "Klant · \(boxes.count) \(boxes.count == 1 ? "mailbox" : "mailboxen")")
                            Text(name.uppercased())
                                .font(Ph.poster(48))
                                .foregroundStyle(Ph.ink)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                        }
                        .padding(.horizontal, 4)
                        buttons
                        figures
                        if !openCards.isEmpty { tasks }
                        HStack {
                            PhCaps(text: "Mail")
                            Spacer()
                            PhCaps(text: boxes.map { gmail.displayName($0) }.joined(separator: " · "), size: 10.5, color: Ph.ink3)
                        }
                        .padding(.top, 4)
                        if loading && mails.isEmpty {
                            ProgressView().tint(Ph.ink).frame(maxWidth: .infinity, minHeight: 80)
                        } else if mails.isEmpty {
                            Text("0").font(Ph.poster(80)).foregroundStyle(Ph.ink).frame(maxWidth: .infinity)
                        }
                        ForEach(months) { month in
                            Section {
                                VStack(spacing: 0) {
                                    ForEach(month.mails) { mail in
                                        NavigationLink(value: mail) { mailRow(mail) }
                                            .buttonStyle(.plain)
                                    }
                                }
                                .phCard()
                            } header: {
                                monthHeader(month.id, count: month.mails.count)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .phScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PhoneMail.self) { mail in
                PhoneThreadView(mail: mail)
            }
        }
        .task { await load() }
        .sheet(item: $compose) { request in
            PhoneComposeView(request: request).presentationBackground(Ph.paper)
        }
    }

    // MARK: Onderdelen

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                    PhCaps(text: "Afzender", size: 12, color: Ph.ink)
                }
                .frame(height: 44)
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            Spacer()
        }
        .foregroundStyle(Ph.ink)
        .padding(.top, 8)
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button("NIEUWE MAIL") {
                compose = PhoneComposeRequest(mode: .new, account: mails.first?.account, to: address)
            }
            .buttonStyle(PhPrimaryStyle(height: 42))
            .layoutPriority(1)
            Button {
                TimerService.startSupport(client: name, caseTitle: mails.first?.item.subject ?? name, in: context)
                appState.showToast("Tijd loopt · \(name)")
            } label: {
                Label("TIJD", systemImage: "play.fill")
            }
            .buttonStyle(PhSecondaryStyle(height: 42))
        }
    }

    private var figures: some View {
        let monthName = Self.monthFormatter("MMM").string(from: Date()).replacingOccurrences(of: ".", with: "")
        let unread = thisYear.filter(\.item.isUnread).count
        let late = openCards.filter { card in
            guard let since = card.waitingSince else { return false }
            return PhoneMailSettings.days(since: since) > 6
        }.count
        return HStack(alignment: .top, spacing: 6) {
            figure("Uren \(monthName)", value: Self.hours(monthSeconds), note: nil, noteColor: Ph.olive)
                .layoutPriority(1)
            figure("Open taken", value: "\(openCards.count)", note: late > 0 ? "\(late) te laat" : nil, noteColor: Ph.urgent)
            figure("Mails \(Calendar.current.component(.year, from: Date()))", value: "\(thisYear.count)",
                   note: unread > 0 ? "\(unread) ongelezen" : nil, noteColor: Ph.olive)
        }
    }

    private func figure(_ title: String, value: String, note: String?, noteColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            PhCaps(text: title, size: 10)
            Text(value).font(Ph.poster(30)).foregroundStyle(Ph.ink)
            if let note { PhCaps(text: note, size: 10, color: noteColor) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .phCard()
    }

    private var tasks: some View {
        let titles = Dictionary(BoardService.columns(in: context).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 6) {
            PhCaps(text: "Open taken")
            VStack(spacing: 0) {
                ForEach(openCards) { card in
                    HStack(spacing: 10) {
                        Text((titles[card.columnRaw] ?? card.columnRaw).uppercased())
                            .font(Ph.text(9.5, .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Ph.ink2)
                            .lineLimit(1)
                            .frame(width: 56)
                            .padding(.vertical, 3)
                            .phWell(Ph.band)
                        Text(card.title).font(Ph.text(14)).foregroundStyle(Ph.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(StarredMail.dayMonth(card.createdAt)).font(Ph.text(12.5)).monospacedDigit().foregroundStyle(Ph.ink2)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)
                    .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
                }
            }
            .phCard()
        }
    }

    private func monthHeader(_ month: Date, count: Int) -> some View {
        HStack {
            Text(Self.monthFormatter("MMMM yyyy").string(from: month).uppercased())
                .font(Ph.text(10, .semibold))
                .tracking(1.6)
                .foregroundStyle(Ph.olive)
            Spacer()
            Text("\(count)").font(Ph.text(10, .semibold)).foregroundStyle(Ph.ink3)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .phWell(Ph.band)
        .background(Ph.paper)
    }

    private func mailRow(_ mail: PhoneMail) -> some View {
        HStack(spacing: 10) {
            Circle().fill(mail.item.isUnread ? Ph.olive : .clear).frame(width: 6, height: 6)
            Text(mail.item.date.map { StarredMail.dayMonth($0) } ?? "")
                .font(Ph.text(12.5))
                .monospacedDigit()
                .foregroundStyle(Ph.ink2)
                .frame(width: 40, alignment: .leading)
            Text(mail.item.subject.isEmpty ? "(geen onderwerp)" : mail.item.subject)
                .font(Ph.text(14, mail.item.isUnread ? .semibold : .regular))
                .foregroundStyle(Ph.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            PhBoxTag(text: gmail.displayName(mail.account))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
    }

    // MARK: Laden

    private func load() async {
        loading = true
        defer { loading = false }
        if ClientDirectory.shared.domainMap.isEmpty { await ClientDirectory.shared.refresh() }
        guard !host.isEmpty else { return }
        let found = await gmail.search(query, accounts: gmail.accounts, max: 100)
        mails = found.map { PhoneMail(item: $0.item, account: $0.account) }
    }

    static func hours(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    private static func monthFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = format
        return formatter
    }
}
