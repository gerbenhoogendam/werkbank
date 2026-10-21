import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Voorkeuren › Handtekening: HTML, logo (voor `cid:`-afbeeldingen) en afzendernaam, per mailbox of voor alle.
struct SignaturePreferences: View {
    private let gmail = GmailSession.shared

    @State private var key = MailSignatures.defaultKey
    @State private var html = ""
    @State private var senderName = ""
    @State private var logo: Data?
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        Form {
            Section {
                Picker("Voor", selection: $key) {
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

    /// De HTML zoals de ontvanger hem ziet; `cid:` wijst hier naar het gekozen logo.
    private var previewHTML: String {
        guard let logo else { return html }
        let type = MailSignatures.imageType(of: logo).mediaType
        return html.replacingOccurrences(of: #"cid:[^"'\s>)]+"#,
                                         with: "data:\(type);base64,\(logo.base64EncodedString())",
                                         options: .regularExpression)
    }
}
