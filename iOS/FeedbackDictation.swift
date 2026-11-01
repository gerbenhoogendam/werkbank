import SwiftData
import SwiftUI
import WerkbankCore

/// De knop Verbetering op de iPhone: inspreken (op het toestel omgezet met WhisperKit), losse verbeteringen herkennen,
/// nalopen en bewaren in Voorkeuren › Verbeteringen.
struct FeedbackDictationSheet: View {
    /// Het scherm op het moment dat je op Verbetering tikte.
    let screenshot: CapturedScreen?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @AppStorage(PhoneDictation.enabledKey) private var enabled = false
    @State private var drafts: [Draft] = []
    @State private var transcribing = 0
    @State private var error: String?
    @State private var voiceMotion = VoiceMotion()
    /// Eén keer verkleind (niet in `body`: die loopt tijdens het opnemen een keer of twaalf per seconde).
    @State private var thumbnail: CGImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var dictation: PhoneDictation { PhoneDictation.shared }

    private struct Draft: Identifiable {
        let id = UUID()
        var text: String
        var platform: FeaturePlatform
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let image = thumbnail {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ThingsColor.separator))
                            .accessibilityLabel("Screenshot")
                    }
                    recordButton
                    if transcribing > 0 {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if let error {
                        Text(error)
                            .font(.werk(size: 15))
                            .foregroundStyle(ThingsColor.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach($drafts) { $draft in
                        draftRow($draft)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Verbetering")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(drafts.count > 1 ? "Bewaar \(drafts.count)" : "Bewaar", action: save)
                        .disabled(drafts.isEmpty || transcribing > 0 || dictation.isRecording)
                }
            }
        }
        .task {
            // Meteen opnemen: één tik op de knop en praten. Staat inspreken uit, dan gaat het aan (de eerste keer
            // downloadt het spraakmodel; opnemen kan al, omzetten wacht erop).
            if !enabled { dictation.apply(enabled: true) }
            dictation.prepare()
            await start()
        }
        .task {
            guard let data = screenshot?.data else { return }
            thumbnail = await Task.detached(priority: .userInitiated) {
                ScreenshotEncoding.thumbnail(data, maxPixels: 600)
            }.value
        }
        .onDisappear { _ = dictation.stopRecording() }
    }

    @ViewBuilder private var recordButton: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: toggle) {
            VStack(spacing: 10) {
                if dictation.isRecording {
                    VoiceWave(level: dictation.level, motion: voiceMotion)
                        .frame(height: 56)
                    Text("Klaar")
                        .font(.werk(size: 17, weight: .semibold))
                } else {
                    Image(systemName: "mic.fill")
                        .font(.werk(size: 30, weight: .semibold))
                    Text(drafts.isEmpty ? "Inspreken" : "Nog iets inspreken")
                        .font(.werk(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(ThingsColor.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(shape.fill(ThingsColor.backgroundSidebar))
            .overlay {
                if dictation.isRecording {
                    VoiceGlow(level: dictation.level, motion: voiceMotion, shape: shape)
                } else {
                    shape.strokeBorder(ThingsColor.separator)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressScaleButtonStyle())
        modelStatus
    }

    /// Het spraakmodel als het nog niet klaar is.
    @ViewBuilder private var modelStatus: some View {
        switch dictation.phase {
        case .downloading(let fraction):
            HStack(spacing: 8) {
                Text("Spraakmodel")
                    .font(.werk(size: 13, weight: .semibold))
                    .foregroundStyle(Color.fieldLabel)
                ProgressView(value: fraction)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.werk(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(ThingsColor.textSecondary)
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Spraakmodel laden")
                    .font(.werk(size: 13))
                    .foregroundStyle(ThingsColor.textSecondary)
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Text(message)
                    .font(.werk(size: 13))
                    .foregroundStyle(ThingsColor.error)
                Button("Opnieuw") { dictation.retry() }
            }
        case .off, .standby, .ready:
            EmptyView()
        }
    }

    private func draftRow(_ draft: Binding<Draft>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: draft.text, axis: .vertical)
                .font(.werk(size: 17))
                .foregroundStyle(ThingsColor.textPrimary)
            HStack {
                PlatformPicker(selection: draft.platform)
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    let id = draft.wrappedValue.id
                    drafts.removeAll { $0.id == id }
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Verwijderen")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ThingsColor.backgroundSidebar))
        .transition(ThingsMotion.materialize(reduceMotion: reduceMotion))
    }

    private func toggle() {
        if dictation.isRecording {
            transcribe(dictation.stopRecording())
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        error = nil
        if let message = await dictation.startRecording() { error = message }
    }

    private func transcribe(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        transcribing += 1
        Task {
            let text = await dictation.transcribe(samples, hint: "Werkbank, board, agenda, Tijd schrijven, mailmodus, iPhone, Mac.")
            transcribing -= 1
            guard let text else {
                error = "Niets verstaan"
                return
            }
            withAnimation(ThingsMotion.reveal) {
                drafts += FeatureRequestSplitter.split(text).map {
                    Draft(text: $0, platform: FeatureRequestSplitter.platform(of: $0) ?? .mobile)
                }
            }
        }
    }

    private func save() {
        let added = FeatureRequests.add(drafts.map { FeaturePrompt.Item(text: $0.text, platform: $0.platform) },
                                        screenshot: screenshot, in: context)
        appState.announce(added.count == 1 ? "Verbetering bewaard" : "\(added.count) verbeteringen bewaard")
        close()
    }

    private func close() {
        _ = dictation.stopRecording()
        dismiss()
    }
}

/// De knop Verbetering, linksonder naast de Magic Plus.
struct FeedbackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Verbetering", systemImage: "lightbulb")
                .font(.werk(size: 15, weight: .semibold))
                .foregroundStyle(ThingsColor.accent)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Capsule().fill(ThingsColor.backgroundContent)
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2))
                .overlay(Capsule().strokeBorder(ThingsColor.accent.opacity(0.35)))
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}
