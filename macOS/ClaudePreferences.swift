import SwiftUI

/// Voorkeuren › Claude: API-sleutel, model en de vaste context die bij elke analyse meegaat.
struct ClaudePreferences: View {
    @AppStorage(ClaudeSettings.modelKey) private var modelRaw = ClaudeModel.opus.rawValue
    @AppStorage(ClaudeSettings.contextKey) private var context = ClaudeSettings.defaultContext
    @State private var keyText = ""
    @State private var hasKey = ClaudeKeychain.read() != nil
    @State private var newMemory = ""
    private let memory = ClaudeMemory.shared

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
            }

            Section {
                Picker("Model", selection: $modelRaw) {
                    ForEach(ClaudeModel.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("Model")
            }

            Section {
                TextEditor(text: $context)
                    .font(.werk(size: 12))
                    .frame(minHeight: 90)
                Button("Standaardtekst terugzetten") { context = ClaudeSettings.defaultContext }
                    .disabled(context == ClaudeSettings.defaultContext)
            } header: {
                Text("Over jullie werk")
            }

            Section {
                ForEach(memory.items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Button { memory.remove(item) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    TextField("", text: $newMemory, axis: .vertical)
                        .lineLimit(1...3)
                        .labelsHidden()
                    Button("Toevoegen") {
                        memory.add(newMemory)
                        newMemory = ""
                    }
                    .disabled(newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Geheugen")
            }
        }
        .formStyle(.grouped)
        .task { await memory.reload() }
    }
}
