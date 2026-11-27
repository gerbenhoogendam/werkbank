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

    /// De gekozen mailboxen, met komma's; leeg is Alle. Tikken kiest er één, lang drukken voegt er een toe.
    @AppStorage("phone.mail.box") private var box = ""
    @AppStorage(PhoneMailSettings.starRowsKey) private var starRows = 3
    @AppStorage(PhoneMailSettings.lateDaysKey) private var lateDays = 4
    @AppStorage(PhoneMailSettings.urgentDaysKey) private var urgentDays = 6
    @AppStorage(PhoneMailSettings.densityKey) private var density = "ruim"
    @AppStorage(PhoneMailSettings.swipeLeftKey) private var swipeLeft = "archief"
    @AppStorage(PhoneMailSettings.swipeRightKey) private var swipeRight = "gelezen"
    @AppStorage(PhoneMailSettings.hiddenInAllKey) private var hiddenRaw = ""

    @State private var filterUnread = false
    @State private var filterAttachment = false
    @State private var filterToday = false
    /// Het welkomstscherm blijft staan tot Verder, ook als er intussen een account bij is gekomen.
    @State private var welcomeActive = false
    @State private var path: [PhoneMailRoute] = []
    @State private var selecting = false
    @State private var chosen: Set<String> = []
    @State private var compose: PhoneComposeRequest?
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var starsOpen = false
    @State private var action: PhoneMailAction?

    private var hiddenBoxes: Set<String> { PhoneMailSettings.hiddenInAll(hiddenRaw) }

    /// Eén mailbox, of bij Alle de mailboxen die in Alle getoond worden.
    private var shownAccounts: [String] {
        let picked = gmail.accounts.filter(chosenBoxes.contains)
        if !picked.isEmpty { return picked }
        let visible = gmail.accounts.filter { !hiddenBoxes.contains($0) }
        return visible.isEmpty ? gmail.accounts : visible
    }

    private var chosenBoxes: Set<String> {
        Set(box.split(separator: ",").map(String.init))
    }

    /// Lang drukken: de mailbox erbij of eraf. Vanuit Alle begint de combinatie met alleen die mailbox.
    private func toggleBox(_ account: String) {
        guard !account.isEmpty else { box = ""; return }
        var set = chosenBoxes.intersection(gmail.accounts)
        if set.contains(account) { set.remove(account) } else { set.insert(account) }
        box = gmail.accounts.filter(set.contains).joined(separator: ",")
    }

    private var filtersOn: Bool { filterUnread || filterAttachment || filterToday }

    /// De mails in de lijst: zonder filter alles zonder ster (die staan in de band), met filter alles wat past.
    private var visible: [PhoneMail] {
        guard filtersOn else { return others }
        return all.filter { mail in
            if filterUnread && !mail.item.isUnread { return false }
            if filterAttachment && !mail.item.mayHaveAttachment { return false }
            if filterToday && !(mail.item.date.map { Calendar.current.isDateInToday($0) } ?? false) { return false }
            return true
        }
    }

    private var listIsEmpty: Bool { filtersOn ? visible.isEmpty : (others.isEmpty && starred.isEmpty) }

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
                if gmail.accounts.isEmpty || welcomeActive {
                    PhoneWelcomeView { welcomeActive = false }
                } else {
                    header
                    if !filtersOn && !starred.isEmpty { starBand }
                    list
                }
            }
            .phScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PhoneMailRoute.self) { route in
                switch route {
                case .thread(let mail): PhoneThreadView(mail: mail, onArchived: { openNext(after: $0) })
                case .folders(let account): PhoneFoldersView(account: account)
                case .folder(let ref): PhoneFolderView(ref: ref)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !selecting && !gmail.accounts.isEmpty && !welcomeActive {
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
            if gmail.accounts.isEmpty { welcomeActive = true }
            if gmail.inbox.isEmpty { await gmail.reloadAll() }
        }
        .onChange(of: PhoneNavigation.shared.inboxRequest) { _, _ in
            path = []
            selecting = false
            chosen = []
        }
        .onChange(of: gmail.accounts.isEmpty) { _, empty in
            if empty { welcomeActive = true }
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
            PhHeader(eyebrow: selecting ? "\(chosen.count) gekozen" : eyebrow,
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
                        Button { path.append(.folders(folderAccount)) } label: { Image(systemName: "folder") }
                            .buttonStyle(PhIconButtonStyle())
                            .accessibilityLabel("Mappen")
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
                PhSegmented(items: boxItems, selection: $box,
                            isOn: { value in
                                let set = chosenBoxes.intersection(gmail.accounts)
                                return value.isEmpty ? set.isEmpty : set.contains(value)
                            },
                            onLongPress: toggleBox)
                    .padding(.horizontal, 16)
            }
            HStack(spacing: 5) {
                PhChip(title: "Ongelezen", isOn: filterUnread) { filterUnread.toggle() }
                PhChip(title: "Bijlage", isOn: filterAttachment) { filterAttachment.toggle() }
                PhChip(title: "Vandaag", isOn: filterToday) { filterToday.toggle() }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var eyebrow: String {
        var parts = ["\(unreadCount) ongelezen"]
        if shownAccounts.count > 1 && (filterUnread || !chosenBoxes.isEmpty) { parts.append("\(shownAccounts.count) mailboxen") }
        if density == "compact" { parts.append("compact") }
        return parts.joined(separator: " · ")
    }

    /// De mailbox voor Mappen: de gekozen, bij Alle de eerste.
    private var folderAccount: String {
        if let first = gmail.accounts.first(where: chosenBoxes.contains) { return first }
        return gmail.accounts.first ?? ""
    }

    private var boxItems: [PhSegmented<String>.Item] {
        let inAll = gmail.accounts.filter { !hiddenBoxes.contains($0) }
        let alle = PhSegmented<String>.Item(value: "", title: "Alle",
                                            count: (inAll.isEmpty ? gmail.accounts : inAll)
                                                .reduce(0) { $0 + (gmail.inbox[$1]?.filter(\.isUnread).count ?? 0) })
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
            if filterUnread && shownAccounts.count > 1 {
                ForEach(shownAccounts, id: \.self) { account in
                    let mails = visible.filter { $0.account == account }
                    if !mails.isEmpty {
                        Section {
                            rows(mails)
                        } header: {
                            groupHeader(account, count: mails.count)
                        }
                    }
                }
            } else {
                rows(visible)
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
            } else if listIsEmpty {
                emptyState
            }
        }
    }

    private func rows(_ mails: [PhoneMail]) -> some View {
        let left = PhoneMailSettings.order(swipeLeft, in: PhoneMailSettings.swipeLeftOptions)
        let right = PhoneMailSettings.order(swipeRight, in: PhoneMailSettings.swipeRightOptions)
        return ForEach(mails) { mail in
            row(mail)
                .contentShape(Rectangle())
                .onTapGesture { open(mail) }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(chosen.contains(mail.id) ? Ph.chosen : Ph.card)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    swipeButton(left[0], mail)
                    swipeButton(left[1], mail)
                    swipeButton(left[2], mail)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    swipeButton(right[0], mail)
                    swipeButton(right[1], mail)
                    swipeButton(right[2], mail)
                }
        }
    }

    @ViewBuilder
    private func row(_ mail: PhoneMail) -> some View {
        if density == "compact" {
            PhoneMailCompactRow(mail: mail, showsBox: shownAccounts.count > 1, selecting: selecting,
                                isChosen: chosen.contains(mail.id))
        } else {
            PhoneMailRow(mail: mail, showsBox: shownAccounts.count > 1, selecting: selecting,
                         isChosen: chosen.contains(mail.id))
        }
    }

    /// Een handeling onder het vegen (Voorkeuren: vegen naar links en naar rechts; de gekozen staat vooraan en
    /// gebeurt bij helemaal doorvegen).
    @ViewBuilder
    private func swipeButton(_ kind: String, _ mail: PhoneMail) -> some View {
        switch kind {
        case "archief":
            Button { archive([mail]) } label: { Label("Archiveer", systemImage: "archivebox") }
                .tint(Ph.olive)
        case "taak":
            Button { action = PhoneMailAction(kind: .task, mail: mail) } label: {
                Label("Taak", systemImage: "checkmark.square")
            }
            .tint(Ph.ink)
        case "ster":
            Button { stars.toggle([mail.item.threadID]) } label: {
                Label(stars.contains(mail.item.threadID) ? "Ster eraf" : "Ster", systemImage: "star")
            }
            .tint(Ph.ink3)
        case "tijd":
            Button { action = PhoneMailAction(kind: .time, mail: mail) } label: {
                Label("Tijd", systemImage: "clock")
            }
            .tint(Ph.ink)
        default:
            Button {
                Task { await gmail.setUnread(!mail.item.isUnread, [(threadID: mail.item.threadID, account: mail.account)]) }
            } label: {
                Label(mail.item.isUnread ? "Gelezen" : "Ongelezen", systemImage: "envelope")
            }
            .tint(Ph.ink2)
        }
    }

    /// De kop van een mailbox in de lijst met ongelezen (Alle): blijft staan tijdens het scrollen.
    private func groupHeader(_ account: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Ph.ink).frame(width: 6, height: 16)
            Text(gmail.displayName(account)).font(Ph.text(11.5, .semibold)).tracking(1.6).foregroundStyle(Ph.ink)
            Text(account).font(Ph.text(11.5)).foregroundStyle(Ph.ink3).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(Ph.text(11, .semibold))
                .foregroundStyle(Ph.olive)
                .padding(.horizontal, 6)
                .frame(minWidth: 22, minHeight: 20)
                .background(Ph.card)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(Ph.band)
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.line).frame(height: 1) }
        .listRowInsets(EdgeInsets())
    }

    /// Inbox leeg: een grote 0, de mailbox en wanneer er voor het laatst is opgehaald.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("0")
                .font(Ph.poster(200))
                .foregroundStyle(Ph.ink)
                .shadow(color: .white.opacity(0.9), radius: 0, y: 1)
                .shadow(color: Ph.ink.opacity(0.10), radius: 4, y: 4)
            HStack(spacing: 10) {
                Rectangle().fill(Ph.olive).frame(width: 24, height: 1)
                Text(filtersOn ? "GEEN MAILS" : "INBOX LEEG")
                Rectangle().fill(Ph.olive).frame(width: 24, height: 1)
            }
            .font(Ph.text(12, .semibold))
            .tracking(2.4)
            .foregroundStyle(Ph.olive)
            if shownAccounts.count == 1, let account = shownAccounts.first {
                Text(account).font(Ph.text(12)).foregroundStyle(Ph.ink2)
            }
            if let date = gmail.lastRefresh {
                Button {
                    Task { await gmail.reloadAll() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                        Text("BIJGEWERKT " + date.formatted(date: .omitted, time: .shortened))
                    }
                    .font(Ph.text(10.5, .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Ph.ink2)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .phCard()
                }
                .buttonStyle(.plain)
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

    /// Na archiveren in een mail: de volgende in de lijst openen (of de vorige als het de laatste was); is die er niet,
    /// terug naar de lijst.
    private func openNext(after mail: PhoneMail) {
        guard !path.isEmpty else { return }
        let list = visible
        guard let index = list.firstIndex(of: mail) else {
            path.removeLast()
            return
        }
        let next = index + 1 < list.count ? list[index + 1] : (index > 0 ? list[index - 1] : nil)
        if let next {
            path[path.count - 1] = .thread(next)
        } else {
            path.removeLast()
        }
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
    /// Mappen van een mailbox.
    case folders(String)
    case folder(PhoneFolderRef)
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
                PhAvatar(name: mail.item.senderDisplay, address: mail.item.fromAddress ?? "")
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

/// Eén mail op één regel (weergave compact): stip, afzender, onderwerp, mailbox, tijd.
struct PhoneMailCompactRow: View {
    let mail: PhoneMail
    var showsBox = true
    var selecting = false
    var isChosen = false

    var body: some View {
        let unread = mail.item.isUnread
        HStack(spacing: 8) {
            if selecting {
                PhCheck(isOn: isChosen, size: 18)
            } else {
                Circle().fill(unread ? Ph.olive : .clear).frame(width: 6, height: 6)
            }
            Text(mail.item.senderDisplay)
                .font(Ph.text(13.5, unread ? .semibold : .regular))
                .lineLimit(1)
                .frame(width: 98, alignment: .leading)
            Text(mail.item.subject.isEmpty ? "(geen onderwerp)" : mail.item.subject)
                .font(Ph.text(13.5))
                .foregroundStyle(unread ? Ph.ink : Ph.ink2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsBox { PhBoxTag(text: PhoneGmail.shared.displayName(mail.account)) }
            Text(PhoneMailSettings.timeText(mail.item.date))
                .font(Ph.text(12))
                .monospacedDigit()
                .foregroundStyle(Ph.ink2)
                .frame(minWidth: 38, alignment: .trailing)
        }
        .foregroundStyle(Ph.ink)
        .padding(.leading, 9)
        .padding(.trailing, 10)
        .frame(height: 36)
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
    }
}

/// Instellingen van de mail op de iPhone.
enum PhoneMailSettings {
    static let starRowsKey = "phone.stars.rows"
    static let lateDaysKey = "phone.stars.lateDays"
    static let urgentDaysKey = "phone.stars.urgentDays"
    /// Weergave van de inbox: "ruim" of "compact".
    static let densityKey = "phone.mail.density"
    /// Vegen naar links: "archief", "taak" of "ster"; naar rechts: "gelezen", "tijd" of "ster".
    static let swipeLeftKey = "phone.mail.swipeLeft"
    static let swipeRightKey = "phone.mail.swipeRight"
    static let swipeLeftOptions = ["archief", "taak", "ster"]
    static let swipeRightOptions = ["gelezen", "tijd", "ster"]
    /// Na archiveren in een mail: "volgende" of "lijst".
    static let afterArchiveKey = "phone.mail.afterArchive"
    /// Afbeeldingen laden: "altijd", "bekend" (klanten en eigen mailboxen) of "nooit".
    static let imagesKey = "phone.mail.images"
    /// Mailboxen die niet in Alle staan, één adres per regel.
    static let hiddenInAllKey = "phone.mail.hiddenInAll"
    /// Een timer starten bij het openen van mail van een bekende klant.
    static let clientTimerKey = "phone.mail.clientTimer"

    static func hiddenInAll(_ raw: String) -> Set<String> {
        Set(raw.split(separator: "\n").map(String.init))
    }

    /// De gekozen handeling vooraan, de rest erachter.
    static func order(_ first: String, in options: [String]) -> [String] {
        let chosen = options.contains(first) ? first : options[0]
        return [chosen] + options.filter { $0 != chosen }
    }

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
