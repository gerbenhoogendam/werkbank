import SwiftData
import SwiftUI
import WerkbankCore
#if os(macOS)
import AppKit
import KeyboardShortcuts
#else
import UIKit
#endif

/// Voorkeuren › Verbeteringen: wat je voor een volgende build hebt ingesproken of getypt (Mac en iPhone samen, via
/// iCloud), en de prompt voor Claude met desktop en mobiel apart.
struct FeatureRequestsPreferences: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \FeatureRequest.createdAt) private var all: [FeatureRequest]
    @State private var newText = ""
    @State private var newPlatform = FeatureRequests.defaultPlatform
    @State private var showsPrompt = false
    #if os(macOS)
    @AppStorage(Dictation.enabledKey) private var dictationEnabled = false
    #else
    @State private var dictating = false
    #endif

    private var collected: [FeatureRequest] { all.filter { $0.sentAt == nil } }
    private var sent: [FeatureRequest] {
        all.filter { $0.sentAt != nil }.sorted { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }
    }

    var body: some View {
        Form {
            Section {
                ForEach(collected) { request in
                    FeatureRequestRow(request: request) { FeatureRequests.delete(request, in: context) }
                }
                HStack(spacing: 8) {
                    TextField("Nieuwe verbetering", text: $newText)
                        .onSubmit(add)
                    PlatformPicker(selection: $newPlatform)
                    Button("Toevoegen", action: add)
                        .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                #if os(iOS)
                Button { dictating = true } label: { Label("Inspreken", systemImage: "mic") }
                #endif
            } header: {
                Text("Verzameld · \(collected.count)")
            }

            Section("Prompt voor Claude") {
                LabeledContent("Desktop", value: "\(collected.filter { $0.platform == .desktop }.count)")
                LabeledContent("Mobiel", value: "\(collected.filter { $0.platform == .mobile }.count)")
                DisclosureGroup("Prompt", isExpanded: $showsPrompt) {
                    Text(FeatureRequests.prompt(collected))
                        .font(.werk(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Kopieer prompt", action: copy)
                    Button("Markeer als doorgegeven") {
                        let count = collected.count
                        FeatureRequests.markSent(collected, in: context)
                        appState.announce(count == 1 ? "1 verbetering doorgegeven" : "\(count) verbeteringen doorgegeven")
                    }
                }
                .disabled(collected.isEmpty)
            }

            #if os(macOS)
            Section("Inspreken") {
                if dictationEnabled {
                    KeyboardShortcuts.Recorder("Sneltoets", name: .dictateFeedback)
                } else {
                    LabeledContent("Inspreken", value: "Uit")
                    Button("Aanzetten") { Dictation.shared.apply(enabled: true) }
                }
            }
            #endif

            if !sent.isEmpty {
                Section("Doorgegeven") {
                    ForEach(sent.prefix(40)) { request in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.text)
                                Text("\(request.platform.title) · \(DutchDate.short(request.sentAt ?? request.createdAt))")
                                    .font(.werk(size: 11))
                                    .foregroundStyle(ThingsColor.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Button("Terugzetten") {
                                request.sentAt = nil
                                try? context.save()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .sheet(isPresented: $dictating) { FeedbackDictationSheet() }
        #endif
    }

    private func add() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        FeatureRequests.add([FeaturePrompt.Item(text: text, platform: newPlatform)], in: context)
        newText = ""
    }

    private func copy() {
        let prompt = FeatureRequests.prompt(collected)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #else
        UIPasteboard.general.string = prompt
        #endif
        appState.announce("Prompt gekopieerd")
    }
}

/// Desktop of mobiel.
struct PlatformPicker: View {
    @Binding var selection: FeaturePlatform

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(FeaturePlatform.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

/// Eén verzamelde verbetering: de tekst is aan te passen, desktop of mobiel te wisselen.
private struct FeatureRequestRow: View {
    @Bindable var request: FeatureRequest
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("", text: $request.text, axis: .vertical)
                .labelsHidden()
            PlatformPicker(selection: $request.platform)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Verwijderen")
        }
    }
}
