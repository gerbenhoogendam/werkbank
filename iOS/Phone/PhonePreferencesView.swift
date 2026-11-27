import SwiftUI

/// Voorkeuren op de iPhone. Wat ook op de Mac geldt (namen van mailboxen, handtekening, sterren, model van Claude)
/// komt via iCloud; wat alleen voor de iPhone is (vegen, aantal sterregels) staat hier ook en gaat mee via iCloud.
struct PhonePreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    private let gmail = PhoneGmail.shared
    private let sync = PhonePreferencesSync.shared

    @AppStorage(PhoneMailSettings.starRowsKey) private var starRows = 3
    @AppStorage(PhoneMailSettings.lateDaysKey) private var lateDays = 4
    @AppStorage(PhoneMailSettings.urgentDaysKey) private var urgentDays = 6
    @AppStorage("phone.mail.newFrom") private var newFrom = ""
    @AppStorage(PhoneClaude.modelKey) private var model = "claude-sonnet-5-5"

    @State private var claudeKey = ""
    @State private var hasKey = PhoneClaude.apiKey != nil
    @State private var renaming: String?
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            PhHeader(eyebrow: syncLine, title: "Voorkeuren", size: 46) {
                Button("KLAAR") { dismiss() }
                    .font(Ph.text(12, .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Ph.ink)
                    .frame(height: 44)
            }
            .padding(.top, 18)
            .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    section("Mailboxen")
                    VStack(spacing: 0) {
                        ForEach(gmail.accounts, id: \.self) { account in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    PhCaps(text: gmail.displayName(account), size: 13, color: Ph.ink)
                                    Text(account).font(Ph.text(12.5)).foregroundStyle(Ph.ink2)
                                }
                                Spacer()
                                Menu {
                                    Button("Naam wijzigen") {
                                        newName = gmail.displayName(account)
                                        renaming = account
                                    }
                                    Button("Verwijderen", role: .destructive) { gmail.remove(account) }
                                } label: {
                                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                                }
                                .foregroundStyle(Ph.ink)
                            }
                            .padding(.leading, 14)
                            .frame(minHeight: 56)
                            .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
                        }
                        Button {
                            Task { await gmail.signIn() }
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("MAILBOX TOEVOEGEN").font(Ph.text(12, .semibold)).tracking(1.4)
                                Spacer()
                                if gmail.isSigningIn { ProgressView().tint(Ph.ink) }
                            }
                            .foregroundStyle(Ph.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 50)
                        }
                        .buttonStyle(.plain)
                    }
                    .phCard()
                    if let error = gmail.lastError {
                        Text(error).font(Ph.text(13)).foregroundStyle(Ph.danger)
                    }

                    section("Inbox")
                    VStack(spacing: 0) {
                        stepper("Regels met ster zichtbaar", value: $starRows, range: 1...8)
                        stepper("Oranje na dagen", value: $lateDays, range: 1...30)
                        stepper("Rood na dagen", value: $urgentDays, range: 2...60)
                        row("Nieuwe mail vanuit") {
                            Menu {
                                ForEach(gmail.accounts, id: \.self) { account in
                                    Button(gmail.displayName(account)) { newFrom = account }
                                }
                            } label: {
                                PhCaps(text: newFrom.isEmpty ? "Eerste" : gmail.displayName(newFrom), size: 12, color: Ph.ink)
                            }
                        }
                    }
                    .phCard()

                    section("Claude")
                    VStack(alignment: .leading, spacing: 10) {
                        PhSegmented(items: [.init(value: "claude-opus-5-5", title: "Opus"),
                                            .init(value: "claude-sonnet-5-5", title: "Sonnet"),
                                            .init(value: "claude-haiku-5-5", title: "Haiku")],
                                    selection: Binding(get: { model }, set: { value in
                                        model = value
                                        sync.set(value, forKey: PhoneClaude.modelKey)
                                    }), height: 36)
                        HStack(spacing: 8) {
                            SecureField(hasKey ? "Opgeslagen" : "Sleutel", text: $claudeKey)
                                .font(Ph.text(15))
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .phWell(Ph.card)
                                .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 1))
                            Button("BEWAAR") {
                                PhoneClaude.setAPIKey(claudeKey)
                                claudeKey = ""
                                hasKey = PhoneClaude.apiKey != nil
                            }
                            .buttonStyle(PhSecondaryStyle(height: 44))
                            .frame(width: 90)
                        }
                        PhCaps(text: hasKey ? "In de sleutelhanger" : "Geen sleutel", size: 10,
                               color: hasKey ? Ph.olive : Ph.danger)
                    }
                    .padding(14)
                    .phCard()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .phScreen()
        .alert("Naam van de mailbox", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Naam", text: $newName)
            Button("Bewaar") {
                if let account = renaming { gmail.setDisplayName(newName, for: account) }
                renaming = nil
            }
            Button("Annuleer", role: .cancel) { renaming = nil }
        }
        .onChange(of: starRows) { _, value in sync.set(value, forKey: PhoneMailSettings.starRowsKey) }
        .onChange(of: lateDays) { _, value in sync.set(value, forKey: PhoneMailSettings.lateDaysKey) }
        .onChange(of: urgentDays) { _, value in sync.set(value, forKey: PhoneMailSettings.urgentDaysKey) }
    }

    private var syncLine: String {
        guard sync.isAvailable else { return "Geen iCloud" }
        guard let date = sync.lastSync else { return "iCloud" }
        let source = sync.lastSource.map { " · \($0)" } ?? ""
        return "iCloud · " + date.formatted(date: .omitted, time: .shortened) + source
    }

    private func section(_ title: String) -> some View {
        PhCaps(text: title).padding(.top, 10).padding(.horizontal, 2)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(Ph.text(15)).foregroundStyle(Ph.ink)
            Spacer()
            content()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        row(title) {
            HStack(spacing: 0) {
                Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) } label: {
                    Image(systemName: "minus").frame(width: 36, height: 34)
                }
                Text("\(value.wrappedValue)")
                    .font(Ph.poster(22))
                    .frame(width: 32, height: 34)
                    .background(Ph.card)
                Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) } label: {
                    Image(systemName: "plus").frame(width: 36, height: 34)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ph.ink)
            .phWell()
        }
    }
}
