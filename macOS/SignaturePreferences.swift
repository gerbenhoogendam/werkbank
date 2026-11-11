import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Voorkeuren › Mail: gekoppelde mailboxen met per mailbox de naam op de tab en de naam die de ontvanger als afzender
/// ziet, en de handtekening: HTML en logo (voor `cid:`-afbeeldingen), per mailbox of voor alle.
struct SignaturePreferences: View {
    private let gmail = GmailSession.shared

    @State private var key = MailSignatures.defaultKey
    @State private var html = ""
    /// Afzendernamen per mailbox ("" is die voor alle mailboxen); meteen bewaard bij het typen.
    @State private var senderNames: [String: String] = [:]
    @State private var logo: Data?
    @State private var logoImage: NSImage?
    @State private var preview = ""
    @State private var importing = false
    @State private var importError: String?
    @State private var disconnecting: String?
    @AppStorage(MailSettings.newestAtBottomKey) private var newestAtBottom = true

    var body: some View {
        Form {
            Section {
                ForEach(gmail.accounts, id: \.self) { email in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(email)
                            Spacer()
                            Button("Loskoppelen", role: .destructive) { disconnecting = email }
                        }
                        // Naam op de tab boven de maillijst (leeg = het deel vóór de @).
                        LabeledContent("Naam op de tab") {
                            TextField("", text: Binding(get: { gmail.displayNames[email] ?? "" },
                                                        set: { gmail.rename(email, to: $0) }),
                                      prompt: Text(GmailSession.shortName(email)))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                        }
                        // De naam die de ontvanger in zijn inbox ziet ("Gerben | ITG Solutions"). Leeg: die voor alle
                        // mailboxen (staat er dan grijs), en is die er ook niet, dan alleen het adres.
                        LabeledContent("Naam afzender") {
                            TextField("", text: senderBinding(email), prompt: sharedSenderName.map { Text($0) })
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                        }
                    }
                }
                HStack {
                    Button("Mailbox toevoegen…") { Task { await gmail.signIn() } }
                        .disabled(gmail.isAddingAccount || !gmail.isConfigured)
                    if gmail.isAddingAccount { ProgressView().controlSize(.small) }
                }
                if let error = gmail.lastError, gmail.isAddingAccount == false, gmail.accounts.isEmpty {
                    Text(error).foregroundStyle(.red)
                }
            } header: {
                Text("Mailboxen")
            }

            Section("Gesprekken") {
                Picker("Volgorde", selection: $newestAtBottom) {
                    Text("Nieuwste mail onderaan").tag(true)
                    Text("Nieuwste mail bovenaan").tag(false)
                }
                QuoteColorsSection()
            }

            DefaultMailAppSection()

            MailClientsSection()

            MailModeKeysSection()

            if !MailModeStore.shared.bulkRules.isEmpty {
                Section("Nooit in één keer archiveren") {
                    ForEach(MailModeStore.shared.bulkRules) { rule in
                        LabeledContent(rule.title) {
                            Button("Weer meenemen") { MailModeStore.shared.removeBulkRule(rule) }
                        }
                    }
                }
            }

            Section {
                Picker("Handtekening voor", selection: $key) {
                    Text("Alle mailboxen (standaard)").tag(MailSignatures.defaultKey)
                    ForEach(gmail.accounts, id: \.self) { Text($0).tag($0) }
                }
                if key == MailSignatures.defaultKey {
                    // Voor mailboxen zonder eigen afzendernaam (die staan hierboven bij Mailboxen).
                    TextField("Naam afzender", text: senderBinding(MailSignatures.defaultKey))
                }
            }

            Section("HTML van de handtekening") {
                TextEditor(text: $html)
                    .font(.werk(size: 11, design: .monospaced))
                    .frame(minHeight: 110)
            }

            Section {
                HStack(spacing: 10) {
                    if logo != nil, let image = logoImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 120, maxHeight: 40)
                    } else {
                        Text("Geen logo").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Kies logo…") { importing = true }
                    if logo != nil {
                        Button("Verwijder", role: .destructive) { logo = nil }
                    }
                }
                if let importError { Text(importError).foregroundStyle(.red) }
            } header: {
                Text("Logo")
            }

            Section("Voorbeeld") {
                MailWebView(html: preview, allowRemote: true)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Mailbox loskoppelen?",
                            isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }),
                            titleVisibility: .visible, presenting: disconnecting) { email in
            Button("\(email) loskoppelen", role: .destructive) {
                gmail.removeAccount(email)
                if key == email { key = MailSignatures.defaultKey }
            }
            Button("Annuleer", role: .cancel) {}
        } message: { _ in
            Text("Werkbank verliest de toegang tot deze mailbox. Opnieuw toevoegen kan altijd.")
        }
        .onAppear(perform: load)
        .onChange(of: key) { _, _ in load() }
        .onChange(of: html) { _, new in MailSignatures.setHTML(new, for: key) }
        .onChange(of: logo) { _, new in MailSignatures.setLogo(new, for: key) }
        // Het logo één keer ontleden, niet bij elke toetsaanslag in de velden.
        .onChange(of: logo, initial: true) { _, new in logoImage = new.flatMap(NSImage.init(data:)) }
        // Het voorbeeld (een webvlak dat helemaal opnieuw laadt) pas als het typen even stilstaat.
        .task(id: PreviewInput(html: html, logo: logo)) {
            if !preview.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            preview = MailSignatures.previewHTML(html, logo: logo)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .gif]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), NSImage(data: data) != nil {
                    logo = data
                    importError = nil
                } else {
                    importError = "Dat bestand kon niet als afbeelding worden gelezen."
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }

    private func load() {
        html = MailSignatures.ownHTML(key)
        senderNames = MailSignatures.senderNames()
        logo = MailSignatures.ownLogo(key)
    }

    private func senderBinding(_ key: String) -> Binding<String> {
        Binding(get: { senderNames[key] ?? "" },
                set: { name in
                    senderNames[key] = name.isEmpty ? nil : name
                    MailSignatures.setSenderName(name, for: key)
                })
    }

    /// De afzendernaam voor alle mailboxen, als die is ingevuld.
    private var sharedSenderName: String? {
        let name = senderNames[MailSignatures.defaultKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private struct PreviewInput: Equatable {
        let html: String
        let logo: Data?
    }
}

/// Voorkeuren › Mail: de toetsen van de mailmodus. Klik op een toets en druk de nieuwe in; Esc laat hem staan.
private struct MailModeKeysSection: View {
    @State private var recording: MailModeAction?
    @State private var monitor: Any?
    @State private var error: String?
    @State private var revision = 0
    @AppStorage(MailModeKeys.hiddenButtonsKey) private var hiddenButtons = ""

    var body: some View {
        Section("Knoppen en sneltoetsen in de mailmodus") {
            ForEach(MailModeAction.allCases) { action in
                LabeledContent {
                    keyButton(action)
                } label: {
                    if MailModeKeys.buttons.contains(action) {
                        // Aangevinkt: de knop staat in de mail. De sneltoets werkt hoe dan ook.
                        Toggle(action.title, isOn: Binding(
                            get: { MailModeKeys.showsButton(action, hidden: hiddenButtons) },
                            set: { hiddenButtons = MailModeKeys.hidden(hiddenButtons, showing: $0, action) }))
                            .toggleStyle(.checkbox)
                    } else {
                        Text(action.title)
                    }
                }
            }
            .id(revision)
            if let error {
                Text(error).foregroundStyle(.red)
            }
            Button("Standaard herstellen") {
                stop()
                MailModeKeys.resetAll()
                error = nil
                revision += 1
            }
        }
        .onDisappear(perform: stop)
    }

    @ViewBuilder private func keyButton(_ action: MailModeAction) -> some View {
        if recording == action {
            Button("…") { stop() }
                .buttonStyle(.borderedProminent)
                .frame(minWidth: 54)
        } else {
            Button(MailModeKeys.key(for: action)) { record(action) }
                .frame(minWidth: 54)
        }
    }

    private func record(_ action: MailModeAction) {
        stop()
        recording = action
        error = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { capture(event, for: action) }
            return nil
        }
    }

    private func capture(_ event: NSEvent, for action: MailModeAction) {
        defer { stop() }
        if event.keyCode == 53 { return }
        guard let key = MailModeKeys.key(from: event) else {
            error = "Kies een letter, cijfer, leesteken of Tab, eventueel met ⌘, ⌃, ⌥ of ⇧."
            return
        }
        if MailModeKeys.reserved.contains(key) {
            error = "\(key) is al van macOS of Werkbank."
            return
        }
        if let other = MailModeKeys.conflict(key, excluding: action) {
            error = "\(key) staat al op \(other.title)."
            return
        }
        MailModeKeys.set(key, for: action)
        revision += 1
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}

/// Voorkeuren › Mail: uit welke mailboxen de klanten rechts in de mailmodus komen, en wie geen klant is.
private struct MailClientsSection: View {
    private let gmail = GmailSession.shared
    @State private var counted: Set<String> = []
    @State private var excluded: [String] = []

    var body: some View {
        Section("Klanten in de mailmodus") {
            ForEach(gmail.accounts, id: \.self) { account in
                Toggle(isOn: Binding(get: { counted.contains(account) }, set: { set(account, $0) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(gmail.displayName(account))
                        Text(account).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            ForEach(excluded, id: \.self) { name in
                LabeledContent(name) {
                    Button("Weer als klant") {
                        MailClientSettings.setExcluded(name, false)
                        refresh()
                    }
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private func set(_ account: String, _ on: Bool) {
        MailClientSettings.setCounts(account, on)
        refresh()
    }

    private func refresh() {
        counted = Set(MailClientSettings.accounts)
        excluded = MailClientSettings.excluded
        MailModeStore.shared.refreshRanking()
    }
}
