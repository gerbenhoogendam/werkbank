import SwiftUI

/// Voorkeuren › Claude: API-sleutel, model en de vaste context die bij elke analyse meegaat.
struct ClaudePreferences: View {
    @AppStorage(ClaudeSettings.modelKey) private var modelRaw = ClaudeModel.opus.rawValue
    @AppStorage(ClaudeSettings.contextKey) private var context = ClaudeSettings.defaultContext
    @State private var keyText = ""
    @State private var hasKey = ClaudeKeychain.read() != nil

    var body: some View {
        Form {
            Section {
                if hasKey {
                    LabeledContent("API-sleutel") {
                        HStack {
                            Text("Bewaard in de sleutelhanger").foregroundStyle(.secondary)
                            Button("Verwijderen", role: .destructive) {
                                ClaudeKeychain.delete()
                                hasKey = false
                            }
                        }
                    }
                } else {
                    HStack {
                        SecureField("API-sleutel", text: $keyText, prompt: Text("sk-ant-…"))
                        Button("Bewaar") {
                            ClaudeKeychain.write(keyText)
                            keyText = ""
                            hasKey = ClaudeKeychain.read() != nil
                        }
                        .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("Toegang")
            } footer: {
                Text("Maak een sleutel op platform.claude.com (Settings › API keys) en zet er tegoed bij. Betaald wordt per analyse; onder het antwoord staat een schatting.")
            }

            Section {
                Picker("Model", selection: $modelRaw) {
                    ForEach(ClaudeModel.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Alleen mails die je zelf naar Claude stuurt (slepen op het Claude-icoon of via de knop in de mail) worden verstuurd, met hun bijlagen.")
            }

            Section {
                TextEditor(text: $context)
                    .font(.system(size: 12))
                    .frame(minHeight: 90)
                Button("Standaardtekst terugzetten") { context = ClaudeSettings.defaultContext }
                    .disabled(context == ClaudeSettings.defaultContext)
            } header: {
                Text("Over jullie werk")
            } footer: {
                Text("Gaat bij elke analyse mee. Hoe meer Claude weet over jullie omgevingen, hoe bruikbaarder de suggesties.")
            }
        }
        .formStyle(.grouped)
    }
}
