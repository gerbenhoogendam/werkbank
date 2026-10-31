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
    @State private var exportURL: URL?
    @State private var exportError: String?
    #if os(macOS)
    @AppStorage(Dictation.enabledKey) private var dictationEnabled = false
    @State private var screenPermission = FeedbackScreenshot.hasPermission
    #else
    @State private var dictating: FeedbackStart?
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
                Button {
                    Task { dictating = FeedbackStart(screenshot: await FeedbackScreenshot.capture()) }
                } label: {
                    Label("Inspreken", systemImage: "mic")
                }
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
                    Button("PDF voor Claude", action: export)
                    Button("Kopieer prompt", action: copy)
                    Button("Markeer als doorgegeven") {
                        let count = collected.count
                        FeatureRequests.markSent(collected, in: context)
                        appState.announce(count == 1 ? "1 verbetering doorgegeven" : "\(count) verbeteringen doorgegeven")
                    }
                }
                .disabled(collected.isEmpty)
                if let exportURL {
                    HStack {
                        Text(exportURL.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        ShareLink(item: exportURL) { Label("Delen", systemImage: "square.and.arrow.up") }
                        #if os(macOS)
                        Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([exportURL]) }
                        #endif
                    }
                }
                if let exportError {
                    Text(exportError).foregroundStyle(ThingsColor.error)
                }
            }

            #if os(macOS)
            Section("Inspreken") {
                if dictationEnabled {
                    KeyboardShortcuts.Recorder("Sneltoets", name: .dictateFeedback)
                } else {
                    LabeledContent("Inspreken", value: "Uit")
                    Button("Aanzetten") { Dictation.shared.apply(enabled: true) }
                }
                LabeledContent("Schermopname") {
                    if screenPermission {
                        Text("Toegestaan").foregroundStyle(ThingsColor.textSecondary)
                    } else {
                        Button("Toestaan") { FeedbackScreenshot.requestPermission() }
                    }
                }
            }
            .onAppear { screenPermission = FeedbackScreenshot.hasPermission }
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
        .sheet(item: $dictating) { start in FeedbackDictationSheet(screenshot: start.screenshot) }
        #endif
    }

    /// Getypt: met een screenshot van het hoofdvenster (Mac) of het scherm (iPhone) van dit moment.
    private func add() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        newText = ""
        let platform = newPlatform
        Task {
            let screenshot = await FeedbackScreenshot.capture()
            FeatureRequests.add([FeaturePrompt.Item(text: text, platform: platform)], screenshot: screenshot, in: context)
        }
    }

    private func export() {
        do {
            exportURL = try FeatureExport.pdf(collected)
            exportError = nil
        } catch {
            exportURL = nil
            exportError = error.localizedDescription
        }
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

    @State private var thumbnail: CGImage?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(ThingsColor.separator))
                    .accessibilityLabel("Screenshot")
            }
            VStack(alignment: .leading, spacing: 2) {
                TextField("", text: $request.text, axis: .vertical)
                    .labelsHidden()
                Text("\(FeaturePrompt.stamp(request.moment)) · \(request.device)")
                    .font(.werk(size: 11))
                    .foregroundStyle(ThingsColor.textSecondary)
            }
            PlatformPicker(selection: $request.platform)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Verwijderen")
        }
        .task(id: request.screenshot?.count) {
            thumbnail = request.screenshot.flatMap { ScreenshotEncoding.thumbnail($0, maxPixels: 160) }
        }
    }
}
