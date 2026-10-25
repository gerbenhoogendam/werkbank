import AppKit
import AVFoundation
import KeyboardShortcuts
import Observation
import SwiftData
import SwiftUI
import WerkbankCore
import WhisperKit

/// Inspreken (F17 ingedrukt houden): opnemen, op de Mac zelf omzetten naar tekst met WhisperKit (Whisper large-v3
/// turbo, Nederlands), verdelen over klant, case, uitgevoerd en duur, en de snelle invoer ingevuld openen. Verdelen
/// gaat op trefwoorden (`DictationParser`); zonder trefwoorden doet Claude het (`DictationSplitter`).
@MainActor
@Observable
final class Dictation {
    static let shared = Dictation()
    static let enabledKey = "dictation.enabled"
    static let model = WhisperModel.large

    enum Phase: Equatable {
        case off
        /// Eerste keer: het model downloaden (0…1).
        case downloading(Double)
        /// Model laden; de eerste keer (en na een macOS-update) stelt Core ML het af op deze Mac, dat duurt even.
        case loading
        case ready
        case listening
        case transcribing
        case failed(String)
    }

    private(set) var phase: Phase = .off
    /// Geluidsniveau tijdens opnemen (0…1), voor de pil.
    private(set) var level: Double = 0

    var isActive: Bool { phase == .listening || phase == .transcribing }

    @ObservationIgnored private var whisper: WhisperKit?
    @ObservationIgnored private let recorder = SpeechRecorder()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// De toets is (nog) ingedrukt; laat je los voordat de opname loopt (toestemmingsvraag), dan geen opname.
    @ObservationIgnored private var holding = false

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Bij het starten van de app.
    func start() {
        KeyboardShortcuts.onKeyDown(for: .dictate) { Task { @MainActor in Dictation.shared.keyDown() } }
        KeyboardShortcuts.onKeyUp(for: .dictate) { Task { @MainActor in Dictation.shared.keyUp() } }
        // Het model pas laden als de app er staat.
        apply(enabled: Self.isEnabled, delay: .seconds(3))
    }

    /// Aan of uit (Voorkeuren › Overig). Uit: het model gaat uit het geheugen. De toets blijft gevangen, zodat hij
    /// niet als onbekende toets bij een ander venster terechtkomt (foutgeluid); de pil meldt dan dat het uit staat.
    func apply(enabled: Bool, delay: Duration = .zero) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            load(after: delay)
        } else {
            if phase == .listening { _ = recorder.stop() }
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
        load()
    }

    private func load(after delay: Duration = .zero) {
        guard whisper == nil, loadTask == nil else { return }
        loadTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.prepareModel()
            self?.loadTask = nil
        }
    }

    private func prepareModel() async {
        do {
            // De bewaarde map (werkt offline); de eerste keer downloaden.
            let folder: URL
            if let saved = WhisperModel.savedFolder() {
                folder = saved
            } else {
                folder = try await WhisperModel.download(variant: Self.model) { fraction in
                    // Niet meer als inspreken intussen is uitgezet.
                    if Dictation.shared.loadTask != nil { Dictation.shared.phase = .downloading(fraction) }
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

    // MARK: Opnemen

    private func keyDown() {
        holding = true
        switch phase {
        case .ready:
            break
        case .downloading(let fraction):
            let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
            AppState.shared.announce("Spraakmodel downloaden: \(percent)")
            return
        case .loading:
            AppState.shared.announce("Spraakmodel wordt geladen")
            return
        case .off:
            AppState.shared.announce("Inspreken staat uit (Voorkeuren › Overig)", seconds: 4)
            return
        case .failed(let message):
            AppState.shared.announce(message, seconds: 4)
            return
        case .listening, .transcribing:
            return
        }
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                AppState.shared.announce("Geen toegang tot de microfoon (Systeeminstellingen › Privacy)", seconds: 4)
                return
            }
            guard holding, phase == .ready else { return }
            do {
                try recorder.start { value in
                    Task { @MainActor in Dictation.shared.level = value }
                }
                phase = .listening
            } catch {
                AppState.shared.announce("Opnemen mislukt: \(error.localizedDescription)", seconds: 4)
            }
        }
    }

    private func keyUp() {
        holding = false
        guard phase == .listening else { return }
        let samples = recorder.stop()
        level = 0
        // Korter dan een halve seconde: per ongeluk aangetikt.
        guard samples.count > WhisperKit.sampleRate / 2 else {
            phase = .ready
            return
        }
        phase = .transcribing
        Task { await finish(samples) }
    }

    private func finish(_ samples: [Float]) async {
        defer { if phase == .transcribing { phase = .ready } }
        guard let whisper else { return }
        let names = WhisperModel.knownClients()
        // Klantnamen en de trefwoorden als hint, de trefwoorden achteraan.
        let hint = names.isEmpty ? nil : names.prefix(25).joined(separator: ", ") + ". Klant, case, uitgevoerd."
        do {
            var text = try await WhisperModel.transcribe(samples, with: whisper, hint: hint)
            // Een hint die misgaat geeft soms niets terug; dan zonder.
            if text.isEmpty { text = try await WhisperModel.transcribe(samples, with: whisper, hint: nil) }
            guard !text.isEmpty else {
                AppState.shared.announce("Niets verstaan")
                return
            }
            var entry = DictationParser.parse(text)
            if entry == nil { entry = await DictationSplitter.split(text, clients: names) }
            var result = entry ?? DictatedTimeEntry(performed: text)
            result.client = WhisperModel.matchClient(result.client, known: names)
            phase = .ready
            QuickEntryController.shared.show(dictation: result)
        } catch {
            AppState.shared.announce("Omzetten mislukt: \(error.localizedDescription)", seconds: 4)
        }
    }
}

// MARK: - Verdelen door Claude

/// Zonder trefwoorden: Claude verdeelt de tekst (het model uit Voorkeuren, lage inspanning, vast antwoordformaat).
enum DictationSplitter {
    private struct Answer: Decodable {
        let client: String
        let caseTitle: String
        let performed: String
        let minutes: Int

        enum CodingKeys: String, CodingKey {
            case client, caseTitle = "case", performed, minutes
        }
    }

    @MainActor
    static func split(_ text: String, clients: [String]) async -> DictatedTimeEntry? {
        guard let key = ClaudeKeychain.read() else { return nil }
        let model = ClaudeSettings.model
        let context = ClaudeSettings.context
        let names = Array(clients.prefix(200))
        do {
            let result = try await ClaudeStreamer.run(
                key: key,
                makeBody: { useFallbacks in
                    body(text: text, clients: names, context: context, model: model, useFallbacks: useFallbacks)
                },
                onText: { _ in })
            guard result.stopReason != "refusal", let data = result.text.data(using: .utf8),
                  let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
            return DictatedTimeEntry(client: answer.client, caseTitle: answer.caseTitle, performed: answer.performed,
                                     minutes: answer.minutes > 0 ? answer.minutes : nil)
        } catch {
            return nil
        }
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "client": ["type": "string"],
            "case": ["type": "string"],
            "performed": ["type": "string"],
            "minutes": ["type": "integer"],
        ],
        "required": ["client", "case", "performed", "minutes"],
        "additionalProperties": false,
    ]

    nonisolated static func body(text: String, clients: [String], context: String, model: ClaudeModel,
                                 useFallbacks: Bool) -> Data {
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 8_000,
            "stream": true,
            "system": systemPrompt(clients: clients, context: context),
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema],
            ],
            "messages": [["role": "user", "content": [["type": "text", "text": text]]]],
        ]
        if useFallbacks { body["fallbacks"] = "default" }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    nonisolated static func systemPrompt(clients: [String], context: String) -> String {
        """
        Je krijgt een ingesproken tijdregel van een IT-specialist, zoals de spraakherkenning hem verstond. Verdeel hem \
        over de velden van zijn urenregistratie.

        Over de organisatie:
        \(context)

        Bekende klantnamen: \(clients.joined(separator: "; "))

        - client: de klant, bij voorkeur precies zoals in de bekende klantnamen; leeg als er geen klant genoemd is.
        - case: het onderwerp, kort zoals een ticket, hooguit zes woorden.
        - performed: wat er gedaan is, in de verleden tijd. Verzin niets en laat niets weg.
        - minutes: de genoemde duur in minuten; 0 als er geen duur genoemd is.
        Verbeter alleen duidelijke fouten van de spraakherkenning (vaktermen, productnamen). Schrijf in het Nederlands.
        """
    }
}

// MARK: - Pil

/// Tijdens het inspreken in de timer-pil: het niveau als balkjes, daarna een draaiend wieltje.
struct DictationLevel: View {
    let level: Double
    let size: MiniTimerSize

    var body: some View {
        HStack(alignment: .center, spacing: max(2, size.dot * 0.3)) {
            ForEach(0..<9, id: \.self) { index in
                // Midden hoger dan de randen, zodat het als een golf leest.
                let shape = 1 - abs(Double(index) - 4) / 5
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: max(2, size.dot * 0.35),
                           height: max(3, size.buttonSize * 0.7 * (0.15 + 0.85 * level * shape)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}

// MARK: - Voorkeuren

/// Voorkeuren › Overig › Inspreken.
struct DictationPreferences: View {
    @AppStorage(Dictation.enabledKey) private var enabled = false
    private var dictation: Dictation { Dictation.shared }

    var body: some View {
        Toggle("Inspreken", isOn: $enabled)
            .onChange(of: enabled) { _, on in dictation.apply(enabled: on) }
        if enabled {
            KeyboardShortcuts.Recorder("Sneltoets", name: .dictate)
            LabeledContent("Spraakmodel") { status }
        }
    }

    @ViewBuilder private var status: some View {
        switch dictation.phase {
        case .off:
            Text("—").foregroundStyle(.secondary)
        case .downloading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(width: 140)
                Text("Downloaden \(fraction.formatted(.percent.precision(.fractionLength(0))))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Laden").foregroundStyle(.secondary)
            }
        case .ready, .listening, .transcribing:
            Text("Klaar").foregroundStyle(.secondary)
        case .failed(let message):
            HStack(spacing: 8) {
                Text(message)
                    .foregroundStyle(ThingsColor.error)
                    .lineLimit(3)
                Button("Opnieuw") { dictation.retry() }
            }
        }
    }
}
