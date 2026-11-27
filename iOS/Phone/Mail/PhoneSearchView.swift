import SwiftUI
import WerkbankCore

/// Zoeken op criteria in één of meer mailboxen tegelijk. Een resultaat klapt open als voorbeeld; Openen schuift de mail
/// als kaart omhoog (omlaag vegen brengt je terug bij de resultaten).
struct PhoneSearchView: View {
    @Environment(\.dismiss) private var dismiss
    private let gmail = PhoneGmail.shared
    private let stars = PhoneStars.shared

    enum Period: String, CaseIterable { case week, month, year, all }

    @State private var words = ""
    @State private var boxes: Set<String> = []
    @State private var fromText = ""
    @State private var toText = ""
    @State private var subjectText = ""
    @State private var notText = ""
    @State private var period: Period = .month
    @State private var unread = false
    @State private var attachment = false
    @State private var starred = false

    @State private var results: [PhoneMail]?
    @State private var searching = false
    @State private var previewID: String?
    @State private var opened: PhoneMail?
    @AppStorage("phone.search.recent") private var recentRaw = ""

    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }

    var body: some View {
        VStack(spacing: 0) {
            PhHeader(eyebrow: results == nil ? "In \(boxes.count) \(boxes.count == 1 ? "mailbox" : "mailboxen")"
                                              : "\(results?.count ?? 0) resultaten",
                     title: "Zoeken", size: 48) {
                Button("KLAAR") { dismiss() }
                    .font(Ph.text(12, .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Ph.ink)
                    .frame(height: 44)
            }
            .padding(.top, 18)
            .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    searchField
                    if let results {
                        resultsList(results)
                    } else {
                        criteria
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            if results == nil {
                HStack(spacing: 8) {
                    Button("WIS") { reset() }
                        .buttonStyle(PhSecondaryStyle(height: 52))
                        .frame(width: 80)
                    Button {
                        Task { await search() }
                    } label: {
                        if searching { ProgressView().tint(Ph.ink) } else { Text("ZOEK") }
                    }
                    .buttonStyle(PhPrimaryStyle())
                    .disabled(boxes.isEmpty || searching)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
            }
        }
        .phScreen()
        .onAppear { if boxes.isEmpty { boxes = Set(gmail.accounts) } }
        .sheet(item: $opened) { mail in
            PhoneThreadView(mail: mail)
                .presentationBackground(Ph.paper)
                .presentationDragIndicator(.visible)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold))
            TextField("Met de woorden", text: $words)
                .font(Ph.text(17))
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
            if results != nil {
                Button("CRITERIA") { results = nil }
                    .font(Ph.text(11, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Ph.ink2)
            }
        }
        .foregroundStyle(Ph.ink)
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Rectangle().fill(Ph.card.shadow(.inner(color: Ph.ink.opacity(0.08), radius: 1.5, y: 2))))
        .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 2))
    }

    // MARK: Criteria

    private var criteria: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhCaps(text: "Mailboxen")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
                ForEach(gmail.accounts, id: \.self) { account in
                    PhChip(title: gmail.displayName(account), isOn: boxes.contains(account)) {
                        if boxes.contains(account) { boxes.remove(account) } else { boxes.insert(account) }
                    }
                }
            }
            VStack(spacing: 0) {
                PhFieldRow(label: "Van") { TextField("", text: $fromText).textInputAutocapitalization(.never) }
                PhFieldRow(label: "Aan") { TextField("", text: $toText).textInputAutocapitalization(.never) }
                PhFieldRow(label: "Onderwerp") { TextField("", text: $subjectText) }
                PhFieldRow(label: "Niet") { TextField("", text: $notText) }
                VStack(alignment: .leading, spacing: 8) {
                    PhCaps(text: "Periode")
                    PhSegmented(items: [.init(value: Period.week, title: "7 dgn"), .init(value: .month, title: "30 dgn"),
                                        .init(value: .year, title: "Jaar"), .init(value: .all, title: "Alles")],
                                selection: $period, height: 34)
                }
                .padding(14)
            }
            .font(Ph.text(15))
            .foregroundStyle(Ph.ink)
            .phCard()
            HStack(spacing: 6) {
                PhChip(title: "Ongelezen", isOn: unread) { unread.toggle() }
                PhChip(title: "Bijlage", isOn: attachment) { attachment.toggle() }
                PhChip(title: "Met ster", isOn: starred) { starred.toggle() }
            }
            if !recent.isEmpty {
                PhCaps(text: "Recent").padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(recent, id: \.self) { query in
                        Button {
                            words = query
                            Task { await search() }
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Ph.ink2)
                                Text(query).foregroundStyle(Ph.ink)
                                Spacer()
                            }
                            .font(Ph.text(14))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .phCard()
            }
        }
    }

    // MARK: Resultaten

    private func resultsList(_ list: [PhoneMail]) -> some View {
        VStack(spacing: 8) {
            if list.isEmpty {
                Text("0").font(Ph.poster(80)).foregroundStyle(Ph.ink).frame(maxWidth: .infinity)
            }
            ForEach(list) { mail in
                let isOpen = previewID == mail.id
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { previewID = isOpen ? nil : mail.id }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(mail.item.senderDisplay).font(Ph.text(14.5, .semibold)).lineLimit(1)
                                PhBoxTag(text: gmail.displayName(mail.account))
                                Spacer()
                                Text(PhoneMailSettings.timeText(mail.item.date)).font(Ph.text(12.5)).foregroundStyle(Ph.ink2)
                            }
                            highlighted(mail.item.subject).font(Ph.text(14)).lineLimit(1)
                        }
                        .foregroundStyle(Ph.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    if isOpen {
                        VStack(alignment: .leading, spacing: 10) {
                            highlighted(mail.item.snippet).font(Ph.mail(14)).foregroundStyle(Ph.ink)
                            Button("OPENEN") { opened = mail }
                                .buttonStyle(PhInkStyle(height: 38))
                                .frame(width: 120)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .phWell(Color(hex: 0xFBFBF8))
                    }
                }
                .modifier(PhResultCard(isOpen: isOpen))
            }
        }
    }

    /// De zoekwoorden gemarkeerd (limoen achter inkt).
    private func highlighted(_ text: String) -> Text {
        let terms = words.split(separator: " ").map { $0.lowercased() }.filter { $0.count > 1 }
        guard !terms.isEmpty else { return Text(text) }
        var attributed = AttributedString(text)
        let lower = text.lowercased()
        for term in terms {
            var searchStart = lower.startIndex
            while let range = lower.range(of: term, range: searchStart..<lower.endIndex) {
                if let low = AttributedString.Index(range.lowerBound, within: attributed),
                   let high = AttributedString.Index(range.upperBound, within: attributed) {
                    attributed[low..<high].backgroundColor = Ph.lime
                }
                searchStart = range.upperBound
            }
        }
        return Text(attributed)
    }

    // MARK: Zoeken

    private var query: String {
        var parts: [String] = []
        let trimmed = words.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { parts.append(trimmed) }
        if !fromText.isEmpty { parts.append("from:(\(fromText))") }
        if !toText.isEmpty { parts.append("to:(\(toText))") }
        if !subjectText.isEmpty { parts.append("subject:(\(subjectText))") }
        for word in notText.split(separator: " ") { parts.append("-\(word)") }
        switch period {
        case .week: parts.append("newer_than:7d")
        case .month: parts.append("newer_than:30d")
        case .year: parts.append("newer_than:1y")
        case .all: break
        }
        if unread { parts.append("is:unread") }
        if attachment { parts.append("has:attachment") }
        return parts.joined(separator: " ")
    }

    private func search() async {
        guard !boxes.isEmpty else { return }
        searching = true
        defer { searching = false }
        let chosen = gmail.accounts.filter { boxes.contains($0) }
        var found = await gmail.search(query, accounts: chosen).map { PhoneMail(item: $0.item, account: $0.account) }
        if starred { found = found.filter { stars.contains($0.item.threadID) } }
        results = found
        previewID = found.first?.id
        let trimmed = words.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            recentRaw = ([trimmed] + recent.filter { $0 != trimmed }).prefix(8).joined(separator: "\n")
        }
    }

    private func reset() {
        words = ""; fromText = ""; toText = ""; subjectText = ""; notText = ""
        period = .month; unread = false; attachment = false; starred = false
        boxes = Set(gmail.accounts)
        results = nil
    }
}

private struct PhResultCard: ViewModifier {
    let isOpen: Bool

    func body(content: Content) -> some View {
        if isOpen { content.phRaisedCard() } else { content.phCard() }
    }
}
