import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Voorkeuren › Mail: gekoppelde mailboxen, en per mailbox de handtekening: HTML, logo (voor `cid:`-afbeeldingen) en afzendernaam, per mailbox of voor alle.
struct SignaturePreferences: View {
    private let gmail = GmailSession.shared

    @State private var key = MailSignatures.defaultKey
    @State private var html = ""
    @State private var senderName = ""
    @State private var logo: Data?
    @State private var importing = false
    @State private var importError: String?
    @State private var disconnecting: String?
    @AppStorage(MailSettings.newestAtBottomKey) private var newestAtBottom = true

    var body: some View {
        Form {
            Section {
                ForEach(gmail.accounts, id: \.self) { email in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            // Naam op de tab boven de maillijst (leeg = het deel vóór de @).
                            TextField("", text: Binding(get: { gmail.displayNames[email] ?? "" },
                                                        set: { gmail.rename(email, to: $0) }),
                                      prompt: Text(GmailSession.shortName(email)))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 220)
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Loskoppelen", role: .destructive) { disconnecting = email }
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
            }

            MailModeKeysSection()

            Section {
                Picker("Handtekening voor", selection: $key) {
                    Text("Alle mailboxen (standaard)").tag(MailSignatures.defaultKey)
                    ForEach(gmail.accounts, id: \.self) { Text($0).tag($0) }
                }
                TextField("Naam afzender", text: $senderName, prompt: Text("Gerben Hoogendam"))
            }

            Section("HTML van de handtekening") {
                TextEditor(text: $html)
                    .font(.werk(size: 11, design: .monospaced))
                    .frame(minHeight: 110)
            }

            Section {
                HStack(spacing: 10) {
                    if let logo, let image = NSImage(data: logo) {
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
                MailWebView(html: previewHTML, allowRemote: true)
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
        .onChange(of: senderName) { _, new in MailSignatures.setSenderName(new, for: key) }
        .onChange(of: logo) { _, new in MailSignatures.setLogo(new, for: key) }
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
        senderName = MailSignatures.ownSenderName(key)
        logo = MailSignatures.ownLogo(key)
    }

    private var previewHTML: String { MailSignatures.previewHTML(html, logo: logo) }
}

/// Voorkeuren › Mail: de toetsen van de mailmodus. Klik op een toets en druk de nieuwe in; Esc laat hem staan.
private struct MailModeKeysSection: View {
    @State private var recording: MailModeAction?
    @State private var monitor: Any?
    @State private var error: String?
    @State private var revision = 0

    var body: some View {
        Section("Sneltoetsen in de mailmodus") {
            ForEach(MailModeAction.allCases) { action in
                LabeledContent(action.title) {
                    if recording == action {
                        Button("…") { stop() }
                            .buttonStyle(.borderedProminent)
                            .frame(minWidth: 54)
                    } else {
                        Button(MailModeKeys.key(for: action)) { record(action) }
                            .frame(minWidth: 54)
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
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let key = MailModeKeys.key(from: event) else {
            error = "Kies een letter, cijfer, leesteken of Tab, zonder ⌘, ⌃ of ⌥."
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
