import SwiftData
import SwiftUI

/// Voorkeuren op de iPhone. Wat ook op de Mac geldt (namen van mailboxen, handtekening, sterren, model van Claude)
/// komt via iCloud; wat alleen voor de iPhone is (vegen, aantal sterregels) staat hier ook en gaat mee via iCloud.
struct PhonePreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    private let gmail = PhoneGmail.shared
    private let sync = PhonePreferencesSync.shared

    @AppStorage(PhoneMailSettings.starRowsKey) private var starRows = 3
    @AppStorage(PhoneMailSettings.lateDaysKey) private var lateDays = 4
    @AppStorage(PhoneMailSettings.urgentDaysKey) private var urgentDays = 6
    @AppStorage("phone.mail.newFrom") private var newFrom = ""
    @AppStorage(PhoneClaude.modelKey) private var model = "claude-sonnet-5-5"
    @AppStorage(PhoneMailSettings.densityKey) private var density = "ruim"
    @AppStorage(SettingsKey.mailLogos) private var mailLogos = true
    @AppStorage(PhoneMailSettings.swipeLeftKey) private var swipeLeft = "archief"
    @AppStorage(PhoneMailSettings.swipeRightKey) private var swipeRight = "gelezen"
    @AppStorage(PhoneMailSettings.afterArchiveKey) private var afterArchive = "lijst"
    @AppStorage(PhoneMailSettings.imagesKey) private var images = "altijd"
    @AppStorage(PhoneMailSettings.clientTimerKey) private var clientTimer = false
    @AppStorage(PhoneMailSettings.hiddenInAllKey) private var hiddenRaw = ""
    @AppStorage(PhoneLock.enabledKey) private var faceID = false
    @AppStorage(PhoneTimeReminder.enabledKey) private var reminder = false
    @AppStorage(PhoneTimeReminder.hoursKey) private var reminderHours = 6
    @AppStorage(PhoneNavigationApp.key) private var navigationApp = PhoneNavigationApp.waze.rawValue

    @State private var claudeKey = ""
    @State private var icon = UIApplication.shared.alternateIconName ?? ""
    @State private var iconError: String?
    @State private var hasKey = PhoneClaude.apiKey != nil

    var body: some View {
        NavigationStack {
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
                        mailboxes
                        inbox
                        privacy
                        agenda
                        time
                        claude
                        appIcon
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .phScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { account in
                PhoneMailboxPreferences(account: account)
            }
        }
        .onChange(of: starRows) { _, value in sync.set(value, forKey: PhoneMailSettings.starRowsKey) }
        .onChange(of: lateDays) { _, value in sync.set(value, forKey: PhoneMailSettings.lateDaysKey) }
        .onChange(of: urgentDays) { _, value in sync.set(value, forKey: PhoneMailSettings.urgentDaysKey) }
        .onChange(of: density) { _, value in sync.set(value, forKey: PhoneMailSettings.densityKey) }
        .onChange(of: swipeLeft) { _, value in sync.set(value, forKey: PhoneMailSettings.swipeLeftKey) }
        .onChange(of: swipeRight) { _, value in sync.set(value, forKey: PhoneMailSettings.swipeRightKey) }
        .onChange(of: afterArchive) { _, value in sync.set(value, forKey: PhoneMailSettings.afterArchiveKey) }
        .onChange(of: images) { _, value in sync.set(value, forKey: PhoneMailSettings.imagesKey) }
        .onChange(of: clientTimer) { _, value in sync.set(value, forKey: PhoneMailSettings.clientTimerKey) }
        .onChange(of: faceID) { _, value in sync.set(value, forKey: PhoneLock.enabledKey) }
        .onChange(of: reminder) { _, value in
            sync.set(value, forKey: PhoneTimeReminder.enabledKey)
            if value { Task { await PhoneTimeReminder.requestPermission() } }
            PhoneTimeReminder.update(in: context)
        }
        .onChange(of: reminderHours) { _, value in
            sync.set(value, forKey: PhoneTimeReminder.hoursKey)
            PhoneTimeReminder.update(in: context)
        }
    }

    // MARK: Onderdelen

    private var mailboxes: some View {
        let hidden = PhoneMailSettings.hiddenInAll(hiddenRaw)
        return VStack(alignment: .leading, spacing: 8) {
            section("Mailboxen")
            VStack(spacing: 0) {
                ForEach(gmail.accounts, id: \.self) { account in
                    NavigationLink(value: account) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                PhCaps(text: gmail.displayName(account), size: 13, color: Ph.ink)
                                Text(account).font(Ph.text(12.5)).foregroundStyle(Ph.ink2)
                            }
                            Spacer()
                            if hidden.contains(account) {
                                PhCaps(text: "Niet in Alle", size: 10, color: Ph.ink3)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Ph.ink3)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .phCard()
            if let error = gmail.lastError {
                Text(error).font(Ph.text(13)).foregroundStyle(Ph.danger)
            }
        }
    }

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Inbox")
            VStack(spacing: 0) {
                choice("Weergave", selection: $density, options: [("ruim", "Ruim"), ("compact", "Compact")])
                toggle("Logo's bij afzenders", isOn: Binding(get: { mailLogos }, set: { value in
                    mailLogos = value
                    sync.set(value, forKey: SettingsKey.mailLogos)
                }))
                choice("Vegen naar links", selection: $swipeLeft,
                       options: [("archief", "Archief"), ("taak", "Taak"), ("ster", "Ster")])
                choice("Vegen naar rechts", selection: $swipeRight,
                       options: [("gelezen", "Gelezen"), ("tijd", "Tijd"), ("ster", "Ster")])
                choice("Na archiveren", selection: $afterArchive, options: [("volgende", "Volgende"), ("lijst", "Lijst")])
                stepper("Regels met ster zichtbaar", value: $starRows, range: 1...8)
                stepper("Oranje na dagen", value: $lateDays, range: 1...30)
                stepper("Rood na dagen", value: $urgentDays, range: 2...60)
            }
            .phCard()
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Mail en privacy")
            VStack(spacing: 0) {
                row("Nieuwe mail vanuit") {
                    Menu {
                        ForEach(gmail.accounts, id: \.self) { account in
                            Button(gmail.displayName(account)) {
                                newFrom = account
                                sync.set(account, forKey: "phone.mail.newFrom")
                            }
                        }
                    } label: {
                        menuLabel(newFrom.isEmpty ? "Eerste" : gmail.displayName(newFrom))
                    }
                }
                row("Afbeeldingen laden") {
                    Menu {
                        Button("Altijd") { images = "altijd" }
                        Button("Bekende afzenders") { images = "bekend" }
                        Button("Nooit") { images = "nooit" }
                    } label: {
                        menuLabel(imagesTitle)
                    }
                }
                toggle("Ontgrendelen met Face ID", isOn: $faceID)
            }
            .phCard()
        }
    }

    private var time: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Tijd")
            VStack(spacing: 0) {
                toggle("Herinnering om 17:00", isOn: $reminder)
                if reminder {
                    stepper("Onder uren", value: $reminderHours, range: 1...12, suffix: ":00")
                }
                toggle("Timer bij openen klantmail", isOn: $clientTimer)
            }
            .phCard()
        }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Agenda")
            VStack(spacing: 0) {
                choice("Navigeren met", selection: Binding(get: { navigationApp }, set: { value in
                    navigationApp = value
                    sync.set(value, forKey: PhoneNavigationApp.key)
                }), options: PhoneNavigationApp.allCases.map { ($0.rawValue, $0.title) })
            }
            .phCard()
        }
    }

    private var claude: some View {
        VStack(alignment: .leading, spacing: 8) {
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
    }

    private var imagesTitle: String {
        switch images {
        case "bekend": return "Bekende afzenders"
        case "nooit": return "Nooit"
        default: return "Altijd"
        }
    }

    private var syncLine: String {
        guard sync.isAvailable else { return "Geen iCloud" }
        guard let date = sync.lastSync else { return "iCloud" }
        let source = sync.lastSource.map { " · \($0)" } ?? ""
        return "iCloud · " + date.formatted(date: .omitted, time: .shortened) + source
    }

    // MARK: Bouwstenen

    private func section(_ title: String) -> some View {
        PhCaps(text: title).padding(.top, 10).padding(.horizontal, 2)
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            PhCaps(text: title, size: 12, color: Ph.ink)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Ph.ink)
        }
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

    /// Kleur (via iCloud) en het app-icoon (alleen deze telefoon: iOS meldt de wissel zelf).
    private var appIcon: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Weergave")
            VStack(alignment: .leading, spacing: 0) {
                choice("Kleur", selection: Binding(get: { PhThemeStore.shared.accent.rawValue }, set: { value in
                    PhThemeStore.shared.set(PhAccent(rawValue: value) ?? .limoen)
                    sync.set(value, forKey: PhThemeStore.key)
                }), options: PhAccent.allCases.map { ($0.rawValue, $0.title) })
                choice("App-icoon", selection: Binding(get: { icon }, set: setIcon),
                       options: [("", "Papier"), ("AppIconLimoen", "Limoen"), ("AppIconOranje", "Oranje")])
                if let iconError {
                    Text(iconError)
                        .font(Ph.text(13))
                        .foregroundStyle(Ph.urgent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
            .phCard()
        }
    }

    private func setIcon(_ name: String) {
        guard UIApplication.shared.supportsAlternateIcons, name != icon else { return }
        let previous = icon
        icon = name
        iconError = nil
        UIApplication.shared.setAlternateIconName(name.isEmpty ? nil : name) { error in
            guard let error else { return }
            Task { @MainActor in
                icon = previous
                iconError = error.localizedDescription
            }
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).font(Ph.text(15)).foregroundStyle(Ph.ink) }
            .toggleStyle(PhToggleStyle())
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
    }

    /// Een keuze uit een paar waarden: de naam erboven, het spoor eronder.
    private func choice(_ title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Ph.text(15)).foregroundStyle(Ph.ink)
            PhSegmented(items: options.map { PhSegmented<String>.Item(value: $0.0, title: $0.1) }, selection: selection,
                        height: 32)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String = "") -> some View {
        row(title) {
            HStack(spacing: 0) {
                Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) } label: {
                    Image(systemName: "minus").frame(width: 36, height: 34)
                }
                Text("\(value.wrappedValue)\(suffix)")
                    .font(Ph.poster(22))
                    .padding(.horizontal, suffix.isEmpty ? 0 : 4)
                    .frame(minWidth: 32, minHeight: 34)
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

/// Eén mailbox: de korte naam, de afzendernaam (dezelfde als op de Mac), of hij in Alle staat, en verwijderen.
struct PhoneMailboxPreferences: View {
    let account: String
    @Environment(\.dismiss) private var dismiss
    private let gmail = PhoneGmail.shared
    private let sync = PhonePreferencesSync.shared
    private static let senderNamesKey = "mail.senderName"

    @AppStorage(PhoneMailSettings.hiddenInAllKey) private var hiddenRaw = ""
    @State private var shortName = ""
    @State private var senderName = ""
    @State private var confirmRemove = false

    private var inAll: Binding<Bool> {
        Binding(get: { !PhoneMailSettings.hiddenInAll(hiddenRaw).contains(account) }, set: { show in
            var hidden = PhoneMailSettings.hiddenInAll(hiddenRaw)
            if show { hidden.remove(account) } else { hidden.insert(account) }
            hiddenRaw = hidden.sorted().joined(separator: "\n")
            sync.set(hiddenRaw, forKey: PhoneMailSettings.hiddenInAllKey)
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            PhBackBar(title: "Voorkeuren", action: { dismiss() })
            PhHeader(eyebrow: "Mailbox", title: gmail.displayName(account), size: 46)
                .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        PhFieldRow(label: "Kort") {
                            TextField("", text: $shortName)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .onSubmit(saveShortName)
                        }
                        PhFieldRow(label: "Afzender") {
                            TextField("", text: $senderName)
                                .autocorrectionDisabled()
                                .onSubmit(saveSenderName)
                        }
                        PhFieldRow(label: "Adres") {
                            Text(account).foregroundStyle(Ph.ink2).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .font(Ph.text(15))
                    .foregroundStyle(Ph.ink)
                    .phCard()

                    PhEyebrow(text: "Gedrag").padding(.top, 6)
                    Toggle(isOn: inAll) { Text("Tonen in Alle").font(Ph.text(15)).foregroundStyle(Ph.ink) }
                        .toggleStyle(PhToggleStyle())
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .phCard()

                    Button {
                        confirmRemove = true
                    } label: {
                        Label("MAILBOX VERWIJDEREN", systemImage: "trash")
                    }
                    .buttonStyle(PhSecondaryStyle(height: 48, tint: Ph.danger))
                    .padding(.top, 10)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .phScreen()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            let names = UserDefaults.standard.dictionary(forKey: PhoneGmail.displayNamesKey) as? [String: String] ?? [:]
            shortName = names[account] ?? ""
            let senders = UserDefaults.standard.dictionary(forKey: Self.senderNamesKey) as? [String: String] ?? [:]
            senderName = senders[account] ?? ""
        }
        .onDisappear {
            saveShortName()
            saveSenderName()
        }
        .confirmationDialog("Mailbox verwijderen", isPresented: $confirmRemove) {
            Button("Verwijderen", role: .destructive) {
                gmail.remove(account)
                dismiss()
            }
        }
    }

    private func saveShortName() {
        guard gmail.accounts.contains(account) else { return }
        let names = UserDefaults.standard.dictionary(forKey: PhoneGmail.displayNamesKey) as? [String: String] ?? [:]
        let trimmed = shortName.trimmingCharacters(in: .whitespaces)
        guard (names[account] ?? "") != trimmed else { return }
        gmail.setDisplayName(trimmed, for: account)
    }

    private func saveSenderName() {
        guard gmail.accounts.contains(account) else { return }
        var names = UserDefaults.standard.dictionary(forKey: Self.senderNamesKey) as? [String: String] ?? [:]
        let trimmed = senderName.trimmingCharacters(in: .whitespaces)
        guard (names[account] ?? "") != trimmed else { return }
        if trimmed.isEmpty { names[account] = nil } else { names[account] = trimmed }
        sync.set(names, forKey: Self.senderNamesKey)
    }
}
