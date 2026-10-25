import AVFoundation
import Observation
import SwiftUI
import WhisperKit

/// Inspreken op de iPhone (Tijd schrijven): klant, case en uitgevoerd elk apart opnemen en op het toestel zelf omzetten
/// met WhisperKit. Het model laadt bij gebruik en gaat uit het geheugen als de app naar de achtergrond gaat.
@MainActor
@Observable
final class PhoneDictation {
    static let shared = PhoneDictation()
    static let enabledKey = "dictation.enabled"

    enum Phase: Equatable {
        case off
        /// Eerste keer: het model downloaden (0…1).
        case downloading(Double)
        /// Gedownload, nog niet in het geheugen; laadt bij de volgende opname.
        case standby
        /// Model laden; de eerste keer (en na een iOS-update) stelt Core ML het af op dit toestel, dat duurt even.
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .off
    /// Geluidsniveau tijdens opnemen (0…1).
    private(set) var level: Double = 0
    private(set) var isRecording = false

    @ObservationIgnored private var whisper: WhisperKit?
    @ObservationIgnored private let recorder = SpeechRecorder()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Welke laadpoging de laatste is (een afgebroken poging ruimt de volgende niet op).
    @ObservationIgnored private var loadID = 0
    /// Omzetten gaat één stuk tegelijk, in volgorde.
    @ObservationIgnored private var queue: Task<Void, Never>?

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Aan en gedownload: de tijdinvoer begint met inspreken. Anders met typen.
    var canDictate: Bool {
        guard Self.isEnabled, WhisperModel.savedFolder() != nil else { return false }
        if case .failed = phase { return false }
        return true
    }

    /// Bij het starten en elke keer dat de app weer in beeld komt: een onderbroken download gaat verder.
    func refresh() {
        guard Self.isEnabled else {
            phase = .off
            return
        }
        if WhisperModel.savedFolder() == nil {
            prepare()
        } else if whisper == nil, loadTask == nil, phase == .off {
            phase = .standby
        }
    }

    /// Aan of uit (Voorkeuren › Overig). Aan: meteen downloaden en laden.
    func apply(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            prepare()
        } else {
            _ = stopRecording()
            loadTask?.cancel()
            loadTask = nil
            whisper = nil
            phase = .off
        }
    }

    /// Opnieuw proberen na een fout (Voorkeuren); bij een kapot model eerst opnieuw downloaden.
    func retry() {
        WhisperModel.forget()
        whisper = nil
        phase = .off
        prepare()
    }

    /// Downloaden (eerste keer) en laden; niets als het model er al staat of al geladen wordt.
    func prepare() {
        guard Self.isEnabled, whisper == nil, loadTask == nil else { return }
        loadID += 1
        let id = loadID
        loadTask = Task { [weak self] in
            await self?.loadModel()
            if self?.loadID == id { self?.loadTask = nil }
        }
    }

    /// De app gaat naar de achtergrond: het model uit het geheugen (anders sluit iOS de app eerder). Een download
    /// loopt door zolang iOS dat toestaat.
    func unload() {
        if case .downloading = phase { return }
        _ = stopRecording()
        loadTask?.cancel()
        loadTask = nil
        whisper = nil
        if Self.isEnabled, WhisperModel.savedFolder() != nil { phase = .standby }
    }

    private func loadModel() async {
        do {
            let folder: URL
            if let saved = WhisperModel.savedFolder() {
                folder = saved
            } else {
                let variant = await Self.variant()
                folder = try await WhisperModel.download(variant: variant) { fraction in
                    // Niet meer als inspreken intussen is uitgezet.
                    if PhoneDictation.shared.loadTask != nil { PhoneDictation.shared.phase = .downloading(fraction) }
                }
            }
            guard !Task.isCancelled else { return }
            phase = .loading
            let loaded = try await WhisperModel.load(folder: folder)
            guard !Task.isCancelled else { return }
            whisper = loaded
            phase = .ready
        } catch {
            guard !Task.isCancelled else { return }
            WhisperModel.forget()
            phase = .failed("Spraakmodel laden mislukt: \(error.localizedDescription)")
        }
    }

    /// Hetzelfde model als op de Mac als dit toestel het aankan (A16 en nieuwer), anders het grootste kleinere.
    private static func variant() async -> String {
        let support = await WhisperKit.recommendedRemoteModels()
        let names = support.supported
        if let large = names.first(where: { $0.hasSuffix(WhisperModel.large) }) { return large }
        for smaller in ["openai_whisper-small", "openai_whisper-base"] where names.contains(smaller) { return smaller }
        return support.default
    }

    // MARK: Opnemen

    /// Begint met opnemen (de eerste keer vraagt iOS om de microfoon). Geeft de foutmelding als het niet lukt.
    func startRecording() async -> String? {
        guard !isRecording else { return nil }
        guard await AVAudioApplication.requestRecordPermission() else {
            return "Geen toegang tot de microfoon (Instellingen › Werkbank)"
        }
        do {
            try recorder.start { value in
                Task { @MainActor in PhoneDictation.shared.level = value }
            }
            isRecording = true
            return nil
        } catch {
            return "Opnemen mislukt: \(error.localizedDescription)"
        }
    }

    /// Wat er voor dit veld is ingesproken; de opname loopt door voor het volgende.
    func nextSegment() -> [Float] {
        recorder.takeSegment()
    }

    func stopRecording() -> [Float] {
        guard isRecording else { return [] }
        isRecording = false
        level = 0
        return recorder.stop()
    }

    /// Zet een stuk opname om naar tekst; wacht zo nodig tot het model geladen is. Nil: niets verstaan of mislukt.
    func transcribe(_ samples: [Float], hint: String?) async -> String? {
        guard samples.count > WhisperKit.sampleRate / 3, SpeechRecorder.hasSpeech(samples) else { return nil }
        prepare()
        let previous = queue
        let task = Task { @MainActor [weak self] () -> String? in
            await previous?.value
            return await self?.run(samples, hint: hint)
        }
        queue = Task { _ = await task.value }
        return await task.value
    }

    private func run(_ samples: [Float], hint: String?) async -> String? {
        await loadTask?.value
        guard let whisper else { return nil }
        do {
            var text = try await WhisperModel.transcribe(samples, with: whisper, hint: hint)
            // Een hint die misgaat geeft soms niets terug; dan zonder.
            if text.isEmpty, hint != nil { text = try await WhisperModel.transcribe(samples, with: whisper, hint: nil) }
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}

// MARK: - Voorkeuren

/// Voorkeuren › Overig › Inspreken (iPhone en iPad).
struct PhoneDictationPreferences: View {
    @AppStorage(PhoneDictation.enabledKey) private var enabled = false
    private var dictation: PhoneDictation { PhoneDictation.shared }

    var body: some View {
        Toggle("Inspreken", isOn: $enabled)
            .onChange(of: enabled) { _, on in dictation.apply(enabled: on) }
        if enabled {
            LabeledContent("Spraakmodel") { status }
        }
    }

    @ViewBuilder private var status: some View {
        switch dictation.phase {
        case .off:
            Text("—").foregroundStyle(.secondary)
        case .downloading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(width: 90)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Laden").foregroundStyle(.secondary)
            }
        case .standby, .ready:
            Text("Klaar").foregroundStyle(.secondary)
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 4) {
                Text(message)
                    .foregroundStyle(ThingsColor.error)
                    .lineLimit(3)
                    .multilineTextAlignment(.trailing)
                Button("Opnieuw") { dictation.retry() }
            }
        }
    }
}
