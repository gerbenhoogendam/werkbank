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
                        VStack(alignment: .leading, spacing: 1) {
                            Text(gmail.displayName(email))
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
            } footer: {
                Text("De naam op de tab wijzig je via het persoonsicoon in de Mail-balk.")
            }

            Section("Gesprekken") {
                Picker("Volgorde", selection: $newestAtBottom) {
                    Text("Nieuwste mail onderaan").tag(true)
                    Text("Nieuwste mail bovenaan").tag(false)
                }
            }

            Section {
                Picker("Handtekening voor", selection: $key) {
                    Text("Alle mailboxen (standaard)").tag(MailSignatures.defaultKey)
                    ForEach(gmail.accounts, id: \.self) { Text($0).tag($0) }
                }
                TextField("Naam afzender", text: $senderName, prompt: Text("Gerben Hoogendam"))
            } footer: {
                Text("Een mailbox zonder eigen handtekening gebruikt de standaard.")
            }

            Section("HTML van de handtekening") {
                TextEditor(text: $html)
                    .font(.system(size: 11, design: .monospaced))
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
            } footer: {
                Text("Verwijst de HTML naar een ingesloten afbeelding (src=\"cid:…\", zoals Apple Mail die maakt), dan wordt dit bestand daarvoor ingesloten.")
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
