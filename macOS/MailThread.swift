import Foundation
import Observation
import WerkbankCore

/// Eén mail in een gesprek, met het nieuwe deel en de ingeklapte geschiedenis los.
struct ThreadMail: Identifiable {
    let id: String
    let date: Date
    let content: MailContent
    let mainHTML: String
    let historyHTML: String?
    let isSent: Bool
}

// MARK: - Bewaarde analyses

/// Een analyse zoals hij op schijf staat (per gesprek, alleen op deze Mac).
struct StoredAnalysis: Codable, Identifiable {
    var id = UUID()
    var anchorMessageID: String
    var createdAt: Date
    var model: String
    var turns: [ClaudeTurn]
    var usage: String?
}

enum ThreadAnalysisStore {
    private static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent("Werkbank/Analyses", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func file(account: String?, threadID: String) -> URL? {
        let safe = "\(account ?? "standaard")-\(threadID)".map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return folder?.appendingPathComponent(String(safe) + ".json")
    }

    static func load(account: String?, threadID: String) -> [StoredAnalysis] {
        guard let url = file(account: account, threadID: threadID), let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([StoredAnalysis].self, from: data)) ?? []
    }

    static func save(_ analyses: [StoredAnalysis], account: String?, threadID: String) {
        guard let url = file(account: account, threadID: threadID) else { return }
        if analyses.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(analyses) { try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Analyseblok

/// Een analyse door Claude binnen een gesprek: hoort bij één mail, kan vervolgvragen krijgen en levert een conceptantwoord.
@MainActor
@Observable
final class ThreadAnalysisBlock: Identifiable {
    let id: UUID
    let anchorMessageID: String
    let createdAt: Date
    private(set) var modelName: String
    private(set) var turns: [ClaudeTurn]
    private(set) var usage: String?
    private(set) var phase: ClaudePhase = .idle
    private(set) var liveAnswer = ""
    private(set) var liveQuestion: String?

    /// Wordt aangeroepen als er iets te bewaren is.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(anchorMessageID: String) {
        id = UUID()
        self.anchorMessageID = anchorMessageID
        createdAt = Date()
        modelName = ClaudeSettings.model.rawValue
        turns = []
    }

    init(stored: StoredAnalysis) {
        id = stored.id
        anchorMessageID = stored.anchorMessageID
        createdAt = stored.createdAt
        modelName = stored.model
        turns = stored.turns
        usage = stored.usage
        phase = stored.turns.isEmpty ? .idle : .done
    }

    var stored: StoredAnalysis {
        StoredAnalysis(id: id, anchorMessageID: anchorMessageID, createdAt: createdAt, model: modelName, turns: turns, usage: usage)
    }

    /// Het nieuwste conceptantwoord uit de antwoorden.
    var draft: String? {
        for turn in turns.reversed() {
            if let draft = ClaudeDraft.extract(from: turn.answer) { return draft }
        }
        return nil
    }

    var modelTitle: String {
        (ClaudeModel(rawValue: modelName)?.title ?? modelName).replacingOccurrences(of: " (aanbevolen)", with: "")
    }

    /// Eerste analyse of een vervolgvraag. `mails` oudste eerst; `focus` is de mail waar het om gaat.
    func run(mails: [MailContent], focus: Int, followUp: String? = nil) {
        guard !phase.isBusy else { return }
        guard let key = ClaudeKeychain.read() else {
            phase = .failed("Er is nog geen API-sleutel ingesteld (Voorkeuren › Claude).")
            return
        }
        let model = ClaudeSettings.model
        let context = ClaudeSettings.context
        let history = turns
        if followUp == nil, !turns.isEmpty { return }
        modelName = model.rawValue
        liveQuestion = followUp
        liveAnswer = ""
        phase = .waiting
        task = Task { [weak self] in
            do {
                let result = try await ClaudeStreamer.run(
                    key: key,
                    makeBody: { useFallbacks in
                        ClaudeRequest.body(mails: mails, focus: focus, history: history, followUp: followUp, model: model,
                                           context: context, useFallbacks: useFallbacks)
                    },
                    onFirstText: { [weak self] in self?.phase = .answering },
                    onText: { [weak self] text in self?.liveAnswer = text })
                guard let self else { return }
                self.turns.append(ClaudeTurn(question: followUp, answer: result.finalText))
                self.liveAnswer = ""
                self.liveQuestion = nil
                self.usage = result.usageLine(model: model)
                self.phase = .done
                self.onChange?()
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        if phase.isBusy { phase = turns.isEmpty ? .idle : .done }
        liveQuestion = nil
        liveAnswer = ""
    }
}

// MARK: - Gesprek

/// Laadt een Gmail-gesprek met de bijbehorende analyses.
@MainActor
@Observable
final class MailThreadModel {
    let ref: MailRef
    private(set) var mails: [ThreadMail] = []
    private(set) var analyses: [ThreadAnalysisBlock] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    private let gmail = GmailSession.shared

    init(ref: MailRef) {
        self.ref = ref
        analyses = ThreadAnalysisStore.load(account: ref.account, threadID: ref.threadID).map(ThreadAnalysisBlock.init(stored:))
        analyses.forEach { $0.onChange = { [weak self] in self?.persist() } }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        gmail.note(account: ref.account, forMessageID: ref.messageID)
        gmail.note(account: ref.account, forMessageID: ref.threadID)
        do {
            let items = try await gmail.threadMessages(threadID: ref.threadID, account: ref.account)
            let loaded = try await withThrowingTaskGroup(of: (Int, ThreadMail).self) { group -> [ThreadMail] in
                for (index, item) in items.enumerated() {
                    group.addTask {
                        let raw = try await self.gmail.rawMessageData(id: item.id)
                        let mail = await Task.detached(priority: .userInitiated) { () -> ThreadMail in
                            let content = MailContentParser.parse(raw)
                            let split = QuoteSplitter.split(html: content.displayHTML)
                            return ThreadMail(id: item.id, date: item.date, content: content, mainHTML: split.main,
                                              historyHTML: split.history, isSent: item.labels.contains("SENT"))
                        }.value
                        return (index, mail)
                    }
                }
                var result: [(Int, ThreadMail)] = []
                for try await pair in group { result.append(pair) }
                return result.sorted { $0.0 < $1.0 }.map(\.1)
            }
            mails = loaded
            loadError = nil
        } catch {
            loadError = "Gesprek ophalen uit Gmail mislukt: \(error.localizedDescription)"
        }
    }

    /// Start een analyse van één mail in de context van het hele gesprek; het blok komt direct na die mail.
    @discardableResult
    func analyze(messageID: String) -> ThreadAnalysisBlock? {
        guard let focus = mails.firstIndex(where: { $0.id == messageID }) else { return nil }
        let block = ThreadAnalysisBlock(anchorMessageID: messageID)
        block.onChange = { [weak self] in self?.persist() }
        analyses.append(block)
        block.run(mails: mails.map(\.content), focus: focus)
        return block
    }

    func ask(_ question: String, in block: ThreadAnalysisBlock) {
        let focus = mails.firstIndex { $0.id == block.anchorMessageID } ?? max(0, mails.count - 1)
        block.run(mails: mails.map(\.content), focus: focus, followUp: question)
    }

    func remove(_ block: ThreadAnalysisBlock) {
        block.cancel()
        analyses.removeAll { $0.id == block.id }
        persist()
    }

    /// Het conceptantwoord van de nieuwste afgeronde analyse.
    var latestDraft: (id: UUID, text: String)? {
        for block in analyses.sorted(by: { $0.createdAt > $1.createdAt }) {
            if let draft = block.draft { return (block.id, draft) }
        }
        return nil
    }

    private func persist() {
        ThreadAnalysisStore.save(analyses.filter { !$0.turns.isEmpty }.map(\.stored), account: ref.account, threadID: ref.threadID)
    }
}
