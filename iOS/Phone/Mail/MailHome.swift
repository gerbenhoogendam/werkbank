import SwiftData
import SwiftUI
import WerkbankCore

/// Mail: bovenaan de mailboxen (Alle of één), daaronder de mails met een ster in een compacte band (hooguit een paar
/// regels; meer scrollt en de donkere balk telt wat er nog is), dan de inbox. Vegen voor de vaste handelingen, kiezen
/// voor meer mails tegelijk over mailboxen heen.
struct MailHome: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    private let gmail = PhoneGmail.shared
    private let stars = PhoneStars.shared

    @AppStorage("phone.mail.box") private var box = ""
    @AppStorage(PhoneMailSettings.starRowsKey) private var starRows = 3
    @AppStorage(PhoneMailSettings.lateDaysKey) private var lateDays = 4
    @AppStorage(PhoneMailSettings.urgentDaysKey) private var urgentDays = 6

    @State private var path: [PhoneMailRoute] = []
    @State private var selecting = false
    @State private var chosen: Set<String> = []
    @State private var compose: PhoneComposeRequest?
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var starsOpen = false
    @State private var action: PhoneMailAction?

    private var shownAccounts: [String] { box.isEmpty || !gmail.accounts.contains(box) ? gmail.accounts : [box] }

    /// Alle mails van de getoonde mailboxen, nieuwste eerst.
    private var all: [PhoneMail] {
        shownAccounts.flatMap { account in (gmail.inbox[account] ?? []).map { PhoneMail(item: $0, account: account) } }
            .sorted { ($0.item.date ?? .distantPast) > ($1.item.date ?? .distantPast) }
    }

    private var starred: [PhoneMail] {
        all.filter { stars.contains($0.item.threadID) }.sorted { ($0.item.date ?? .distantPast) < ($1.item.date ?? .distantPast) }
    }
    private var others: [PhoneMail] { all.filter { !stars.contains($0.item.threadID) } }
    private var unreadCount: Int { all.filter(\.item.isUnread).count }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                if gmail.accounts.isEmpty {
                    PhoneMailWelcome()
                } else {
                    if !starred.isEmpty { starBand }
                    list
                }
            }
            .phScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PhoneMailRoute.self) { route in
                switch route {
                case .thread(let mail): PhoneThreadView(mail: mail)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !selecting && !gmail.accounts.isEmpty {
                    Button { compose = PhoneComposeRequest(mode: .new) } label: {
                        Image(systemName: "square.and.pencil").font(.system(size: 21, weight: .medium))
                    }
                    .buttonStyle(PhFabStyle())
                    .accessibilityLabel("Nieuwe mail")
                    .padding(.trailing, 22)
                    .padding(.bottom, 18)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selecting { selectionBar }
            }
        }
        .task {
            if gmail.inbox.isEmpty { await gmail.reloadAll() }
        }
        .sheet(item: $compose) { request in
            PhoneComposeView(request: request)
                .presentationBackground(Ph.paper)
        }
        .sheet(isPresented: $showSearch) {
            PhoneSearchView()
                .presentationBackground(Ph.paper)
        }
        .sheet(isPresented: $showSettings) {
            PhonePreferencesView()
                .presentationBackground(Ph.paper)
        }
        .sheet(item: $action) { action in
            PhoneMailActionSheet(action: action)
                .presentationBackground(Ph.paper)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Kop

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhHeader(eyebrow: selecting ? "\(chosen.count) gekozen" : "\(unreadCount) ongelezen",
                     title: selecting ? "Kiezen" : "Mail") {
                HStack(spacing: 6) {
                    if selecting {
                        Button("KLAAR") {
                            selecting = false
                            chosen = []
                        }
                        .buttonStyle(PhSecondaryStyle(height: 44))
                        .frame(width: 84)
                    } else {
                        Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(PhIconButtonStyle())
                            .accessibilityLabel("Zoeken")
                        Button { selecting = true } label: { Image(systemName: "checkmark.square") }
                            .buttonStyle(PhIconButtonStyle())
                            .accessibilityLabel("Kiezen")
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .buttonStyle(PhIconButtonStyle())
                            .accessibilityLabel("Voorkeuren")
                    }
                }
            }
            if gmail.accounts.count > 1 {
                PhSegmented(items: boxItems, selection: $box)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var boxItems: [PhSegmented<String>.Item] {
        let alle = PhSegmented<String>.Item(value: "", title: "Alle",
                                            count: gmail.accounts.reduce(0) { $0 + (gmail.inbox[$1]?.filter(\.isUnread).count ?? 0) })
        return [alle] + gmail.accounts.map { account in
            PhSegmented<String>.Item(value: account, title: gmail.displayName(account),
                                     count: gmail.inbox[account]?.filter(\.isUnread).count ?? 0)
        }
    }

    // MARK: Ster

    private var starBand: some View {
        let rowHeight: CGFloat = 46
        let visible = max(1, starRows)
        let hidden = max(0, starred.count - visible)
        let urgent = starred.filter { mail in
            guard let date = mail.item.date else { return false }
            return PhoneMailSettings.days(since: date) > urgentDays
        }.count
        let shownRows = starsOpen ? min(starred.count, visible * 2) : min(starred.count, visible)
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(starred) { mail in
                        starRow(mail)
                            .frame(minHeight: rowHeight)
                        Rectangle().fill(Ph.line.opacity(0.6)).frame(height: 1)
                    }
                }
            }
            .frame(height: rowHeight * CGFloat(shownRows) + 2)
            if hidden > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { starsOpen.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: starsOpen ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                        Text("+\(hidden)")
                        if urgent > 0 { Text("\(urgent) URGENT").foregroundStyle(Ph.urgent) }
                        Spacer()
                    }
                    .font(Ph.text(10.5, .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Ph.paper)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Ph.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nog \(hidden) met ster, waarvan \(urgent) urgent")
            } else {
                Rectangle().fill(Ph.ink).frame(height: 2)
            }
        }
        .phWell(Ph.band)
        .padding(.horizontal, 16)
    }

    private func starRow(_ mail: PhoneMail) -> some View {
        let date = mail.item.date ?? Date()
        let days = PhoneMailSettings.days(since: date)
        let color = days > urgentDays ? Ph.urgent : (days > lateDays ? Ph.late : Ph.ink2)
        return HStack(alignment: .top, spacing: 9) {
            Button { stars.toggle([mail.item.threadID]) } label: { PhStar(size: 15) }
                .buttonStyle(.plain)
                .accessibilityLabel("Ster eraf")
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(StarredMail.dayMonth(date))
                        .font(Ph.text(12.5, days > lateDays ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(color)
                    Text(StarredMail.firstName(mail.item.fromName, address: mail.item.fromAddress))
                        .font(Ph.text(14, mail.item.isUnread ? .semibold : .medium))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(mail.item.subject).font(Ph.text(14)).lineLimit(1)
                }
                Text(StarredMail.oneLine(mail.item.snippet))
                    .font(Ph.text(12))
                    .foregroundStyle(Ph.ink3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Ph.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { open(mail) }
    }

    // MARK: Lijst

    private var list: some View {
        List {
            ForEach(others) { mail in
                PhoneMailRow(mail: mail, showsBox: shownAccounts.count > 1, selecting: selecting,
                             isChosen: chosen.contains(mail.id))
                    .contentShape(Rectangle())
                    .onTapGesture { open(mail) }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(chosen.contains(mail.id) ? Ph.chosen : Ph.card)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { archive([mail]) } label: { Label("Archiveer", systemImage: "archivebox") }
                            .tint(Ph.olive)
                        Button { action = PhoneMailAction(kind: .task, mail: mail) } label: {
                            Label("Taak", systemImage: "checkmark.square")
                        }
                        .tint(Ph.ink)
                        Button { stars.toggle([mail.item.threadID]) } label: { Label("Ster", systemImage: "star") }
                            .tint(Ph.ink2)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task { await gmail.setUnread(!mail.item.isUnread, [(threadID: mail.item.threadID, account: mail.account)]) }
                        } label: {
                            Label(mail.item.isUnread ? "Gelezen" : "Ongelezen", systemImage: "envelope")
                        }
                        .tint(Ph.ink2)
                        Button { action = PhoneMailAction(kind: .time, mail: mail) } label: {
                            Label("Tijd", systemImage: "clock")
                        }
                        .tint(Ph.ink)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Ph.card)
        .overlay(Rectangle().strokeBorder(Ph.line, lineWidth: 1).allowsHitTesting(false))
        .shadow(color: Ph.ink.opacity(0.06), radius: 6, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .refreshable { await gmail.reloadAll() }
        .overlay {
            if all.isEmpty && !gmail.loading.isEmpty {
                ProgressView().tint(Ph.ink)
            } else if others.isEmpty && starred.isEmpty {
                VStack(spacing: 4) {
                    Text("0").font(Ph.poster(96)).foregroundStyle(Ph.ink)
                    PhCaps(text: "Inbox leeg", size: 12)
                }
            }
        }
    }

    private var selectionBar: some View {
        let picked = all.filter { chosen.contains($0.id) }
        let anyUnread = picked.contains(where: \.item.isUnread)
        return HStack(spacing: 6) {
            Button("ARCHIVEER") { archive(picked) }
                .buttonStyle(PhPrimaryStyle(height: 50))
            Button(anyUnread ? "GELEZEN" : "ONGELEZEN") {
                let threads = picked.map { (threadID: $0.item.threadID, account: $0.account) }
                Task { await gmail.setUnread(!anyUnread, threads) }
                endSelection()
            }
            .buttonStyle(PhSecondaryStyle(height: 50))
            Button("STER") {
                stars.toggle(picked.map(\.item.threadID))
                endSelection()
            }
            .buttonStyle(PhSecondaryStyle(height: 50))
            Button("WEG") {
                let threads = picked.map { (threadID: $0.item.threadID, account: $0.account) }
                endSelection()
                Task {
                    let done = await gmail.trash(threads)
                    appState.showToast(done == 1 ? "Mail in de prullenbak" : "\(done) mails in de prullenbak")
                }
            }
            .buttonStyle(PhSecondaryStyle(height: 50, tint: Ph.danger))
        }
        .disabled(picked.isEmpty)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Ph.paper)
        .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
    }

    // MARK: Handelingen

    private func open(_ mail: PhoneMail) {
        if selecting {
            if chosen.contains(mail.id) { chosen.remove(mail.id) } else { chosen.insert(mail.id) }
            return
        }
        path.append(.thread(mail))
    }

    private func archive(_ mails: [PhoneMail]) {
        let threads = mails.map { (threadID: $0.item.threadID, account: $0.account) }
        endSelection()
        Task {
            let done = await gmail.archive(threads)
            appState.showToast(done == 1 ? "Mail gearchiveerd" : "\(done) mails gearchiveerd")
        }
    }

    private func endSelection() {
        chosen = []
        selecting = false
    }
}

// MARK: - Onderdelen

/// Een mail met de mailbox erbij (de lijst toont meer mailboxen tegelijk).
struct PhoneMail: Identifiable, Hashable {
    let item: GmailMailItem
    let account: String
    var id: String { item.id }

    static func == (a: PhoneMail, b: PhoneMail) -> Bool { a.item.id == b.item.id && a.account == b.account }
    func hash(into hasher: inout Hasher) { hasher.combine(item.id) }
}

enum PhoneMailRoute: Hashable {
    case thread(PhoneMail)
}

/// Eén mail in de lijst: afzender, mailbox, tijd, onderwerp en twee regels tekst.
struct PhoneMailRow: View {
    let mail: PhoneMail
    var showsBox = true
    var selecting = false
    var isChosen = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if selecting {
                PhCheck(isOn: isChosen, size: 22).padding(.top, 6)
            } else {
                PhAvatar(name: mail.item.senderDisplay)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(mail.item.isUnread ? Ph.olive : .clear).frame(width: 7, height: 7)
                    Text(mail.item.senderDisplay)
                        .font(Ph.text(15, mail.item.isUnread ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if showsBox { PhBoxTag(text: PhoneGmail.shared.displayName(mail.account)) }
                    Text(PhoneMailSettings.timeText(mail.item.date))
                        .font(Ph.text(12.5))
                        .foregroundStyle(Ph.ink2)
                }
                Text(mail.item.subject.isEmpty ? "(geen onderwerp)" : mail.item.subject)
                    .font(Ph.text(14.5))
                    .lineLimit(1)
                Text(mail.item.snippet)
                    .font(Ph.text(13))
                    .foregroundStyle(Ph.ink2)
                    .lineLimit(2)
            }
            .foregroundStyle(Ph.ink)
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1).padding(.leading, 56) }
    }
}

/// De knop rechtsonder: limoen met inktrand en een harde schaduw.
struct PhFabStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(Ph.ink)
            .frame(width: 58, height: 58)
            .background(
                Rectangle().fill(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                    .background(Rectangle().fill(Ph.ink).offset(y: pressed ? 0 : 3))
                    .shadow(color: Ph.ink.opacity(0.18), radius: 8, y: 6)
            )
            .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 2))
            .offset(y: pressed ? 2 : 0)
    }
}

/// Nog geen mailbox: er een toevoegen.
struct PhoneMailWelcome: View {
    private let gmail = PhoneGmail.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhCaps(text: "Mailboxen", size: 11)
            Button {
                Task { await gmail.signIn() }
            } label: {
                HStack(spacing: 10) {
                    if gmail.isSigningIn { ProgressView().tint(Ph.ink) }
                    Text("GMAIL TOEVOEGEN")
                }
            }
            .buttonStyle(PhPrimaryStyle())
            if let error = gmail.lastError {
                Text(error).font(Ph.text(13)).foregroundStyle(Ph.danger)
            }
            Spacer()
        }
        .padding(20)
    }
}

/// Instellingen van de mail op de iPhone.
enum PhoneMailSettings {
    static let starRowsKey = "phone.stars.rows"
    static let lateDaysKey = "phone.stars.lateDays"
    static let urgentDaysKey = "phone.stars.urgentDays"

    static func days(since date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
    }

    /// Vandaag de tijd, anders dag/maand.
    static func timeText(_ date: Date?) -> String {
        guard let date else { return "" }
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        return StarredMail.dayMonth(date)
    }
}
