import AVFoundation
import Foundation
import WhisperKit

/// WhisperKit voor inspreken op de Mac (F17, `Dictation`) en de iPhone (Tijd schrijven, `PhoneDictation`): het model
/// downloaden en laden, opnames omzetten naar tekst en klantnamen koppelen.
@MainActor
enum WhisperModel {
    /// Het aanbevolen meertalige model van Argmax (± 630 MB).
    static let large = "large-v3-v20240930_626MB"
    private static let folderKey = "dictation.modelFolder"

    /// De bewaarde map van het model (werkt offline), als die er nog is.
    static func savedFolder() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: folderKey),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Kapot of onvolledig model: de volgende poging downloadt opnieuw.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: folderKey)
    }

    /// Downloadt `variant` naar Application Support/Whisper en onthoudt de map. `onProgress` krijgt 0…1, alleen
    /// zolang het downloaden loopt.
    static func download(variant: String, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> URL {
        let finished = Flag()
        defer { finished.isSet = true }
        onProgress(0)
        let folder = try await WhisperKit.download(variant: variant, downloadBase: try storage()) { progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                if !finished.isSet { onProgress(fraction) }
            }
        }
        UserDefaults.standard.set(folder.path, forKey: folderKey)
        return folder
    }

    /// Laadt het model; de eerste keer (en na een systeemupdate) stelt Core ML het af op dit apparaat, dat duurt even.
    static func load(folder: URL) async throws -> WhisperKit {
        let config = WhisperKitConfig(modelFolder: folder.path, tokenizerFolder: try storage(), verbose: false,
                                      prewarm: true, load: true, download: false)
        return try await WhisperKit(config)
    }

    /// Application Support/Whisper (in de sandbox van de app). Op iOS niet in de iCloud-reservekopie: het model is
    /// honderden MB's en kan altijd opnieuw gedownload worden.
    private static func storage() throws -> URL {
        let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
            .appendingPathComponent("Whisper", isDirectory: true)
        #if os(iOS)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = url
        try? excluded.setResourceValues(values)
        #endif
        return url
    }

    /// Nederlands vast. `hint`: woorden die vaak voorkomen (klantnamen, trefwoorden); Whisper houdt alleen het laatste
    /// stuk, dus het belangrijkste achteraan.
    static func transcribe(_ samples: [Float], with whisper: WhisperKit, hint: String?) async throws -> String {
        var options = DecodingOptions(language: "nl", temperature: 0, usePrefillPrompt: true, skipSpecialTokens: true,
                                      withoutTimestamps: true)
        if let hint, !hint.isEmpty, let tokenizer = whisper.tokenizer {
            let tokens = tokenizer.encode(text: " " + hint).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.promptTokens = Array(tokens.suffix(100))
        }
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Klantnamen uit de laatste tijdregels (meest recent eerst), voor de hint en het koppelen.
    static func knownClients() -> [String] {
        var seen = Set<String>()
        return TimerService.allEntries(in: Persistence.container.mainContext)
            .sorted { $0.createdAt > $1.createdAt }
            .map(\.client)
            .filter { $0 != TimerService.noClient && !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Koppelt wat je zei aan de klantenlijst ("ecom" → "Schildersbedrijf Willegom"); anders zoals gezegd.
    static func matchClient(_ spoken: String, known: [String]) -> String {
        let spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return "" }
        return ClientDirectory.shared.suggestions(for: spoken, known: known, limit: 1).first?.name ?? spoken
    }

    @MainActor
    private final class Flag {
        var isSet = false
    }
}

// MARK: - Opname

/// Neemt op van de standaardmicrofoon en levert 16 kHz mono, wat Whisper verwacht. Op de iPhone kan de opname in
/// stukken (`takeSegment`): één per veld, zonder de microfoon tussendoor te stoppen.
final class SpeechRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(WhisperKit.sampleRate),
                                       channels: 1, interleaved: false)!

    enum RecorderError: LocalizedError {
        case noInput

        var errorDescription: String? { "Geen microfoon gevonden" }
    }

    func start(level: @escaping @Sendable (Double) -> Void) throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let converter = AVAudioConverter(from: format, to: target) else { throw RecorderError.noInput }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer, converter: converter, level: level)
        }
        engine.prepare()
        try engine.start()
    }

    /// Wat er sinds de start (of het vorige stuk) is opgenomen; de opname loopt door.
    func takeSegment() -> [Float] {
        lock.withLock {
            let segment = samples
            samples.removeAll(keepingCapacity: true)
            return segment
        }
    }

    /// Zat er geluid in (niet alleen stilte of geruis)? Whisper verzint bij stilte soms een zin.
    static func hasSpeech(_ samples: [Float]) -> Bool {
        let window = WhisperKit.sampleRate / 10
        var start = 0
        while start + window <= samples.count {
            let slice = samples[start..<(start + window)]
            let power = slice.reduce(Float(0)) { $0 + $1 * $1 } / Float(window)
            if sqrt(power) > 0.008 { return true }
            start += window
        }
        return false
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if os(iOS)
        // Muziek of een podcast die door de opname stilviel, speelt weer verder.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        return lock.withLock { samples }
    }

    private func append(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, level: (Double) -> Void) {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var delivered = false
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0], output.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        lock.withLock { samples.append(contentsOf: chunk) }
        let power = chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.count)
        level(Double(min(1, sqrt(power) * 8)))
    }
}
