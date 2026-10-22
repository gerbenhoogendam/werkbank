import Foundation
import Observation
import WerkbankCore

/// Eén mail in een gesprek. De koppen en de snippet zijn er meteen; de inhoud (`content`) pas als de mail
/// open wordt geklapt.
struct ThreadMail: Identifiable {
    let id: String
    let date: Date
    let isSent: Bool
    let isUnread: Bool
    let from: String
    let to: String
    let cc: String
    let subject: String
    let snippet: String
    var content: MailContent?
    var mainHTML = ""
    var historyHTML: String?
    var loadError: String?

    init(_ message: GmailThreadMessage) {
        id = message.id
        date = message.date
        isSent = message.isSent
        isUnread = message.isUnread
        from = message.from
        to = message.to
        cc = message.cc
        subject = message.subject
        snippet = message.snippet
    }
}

/// Uitgelezen mails, zodat een gesprek opnieuw openen niets opnieuw hoeft te verwerken.
/// Een uitgelezen mail: inhoud plus het nieuwe deel en de geschiedenis los.
struct ParsedThreadMail {
    let content: MailContent
    let main: String
    let history: String?
}

@MainActor
private enum ParsedMailCache {
    typealias Entry = ParsedThreadMail

    private static var entries: [String: Entry] = [:]
    private static var order: [String] = []
    private static let limit = 40

    static func get(_ id: String) -> Entry? { entries[id] }

    static func put(_ id: String, _ entry: Entry) {
        entries[id] = entry
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > limit { entries[order.removeFirst()] = nil }
    }
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

    /// Eén of twee regels: de samenvatting uit de analyse zelf.
    var summary: String? {
        turns.first.flatMap { ClaudeSummary.extract(from: $0.answer) }
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
    /// De mails worden nog opgehaald voordat de aanvraag weg kan.
    func markPreparing(question: String? = nil) {
        liveQuestion = question
        phase = .preparing
    }

    func run(mails: [MailContent], focus: Int, followUp: String? = nil) {
        guard phase != .waiting, phase != .answering else { return }
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

/// Laadt een Gmail-gesprek met de bijbehorende analyses. Eerst de lijst (één lichte aanvraag), daarna alleen de
/// inhoud van de mails die open staan: de nieuwste, de aangeklikte en de ongelezen.
@MainActor
@Observable
final class MailThreadModel {
    let ref: MailRef
    private(set) var mails: [ThreadMail] = []
    private(set) var expanded: Set<String> = []
    private(set) var analyses: [ThreadAnalysisBlock] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    @ObservationIgnored private var loadingIDs: Set<String> = []
    private let gmail = GmailSession.shared

    init(ref: MailRef) {
        self.ref = ref
        analyses = ThreadAnalysisStore.load(account: ref.account, threadID: ref.threadID).map(ThreadAnalysisBlock.init(stored:))
        analyses.forEach { $0.onChange = { [weak self] in self?.persist() } }
    }

    func load() async {
        isLoading = true
        gmail.note(account: ref.account, forMessageID: ref.messageID)
        gmail.note(account: ref.account, forMessageID: ref.threadID)
        do {
            let items = try await gmail.threadMessages(threadID: ref.threadID, account: ref.account)
            mails = items.map { item in
                var mail = ThreadMail(item)
                if let cached = ParsedMailCache.get(item.id) { Self.fill(&mail, with: cached) }
                return mail
            }
            loadError = nil
            var open = Set(items.filter(\.isUnread).map(\.id))
            if let newest = items.last { open.insert(newest.id) }
            if items.contains(where: { $0.id == ref.messageID }) { open.insert(ref.messageID) }
            expanded.formUnion(open)
            isLoading = false
            await withTaskGroup(of: Void.self) { group in
                for id in open { group.addTask { await self.loadContent(id) } }
            }
        } catch {
            isLoading = false
            loadError = "Gesprek ophalen uit Gmail mislukt: \(error.localizedDescription)"
        }
    }

    func isExpanded(_ id: String) -> Bool { expanded.contains(id) }

    /// Klik op een mail: open- of dichtklappen (de inhoud wordt bij openen opgehaald).
    func toggle(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
            Task { await loadContent(id) }
        }
    }

    func loadContent(_ id: String) async {
        guard let index = mails.firstIndex(where: { $0.id == id }), mails[index].content == nil,
              !loadingIDs.contains(id) else { return }
        loadingIDs.insert(id)
        defer { loadingIDs.remove(id) }
        if let cached = ParsedMailCache.get(id) {
            Self.fill(&mails[index], with: cached)
            return
        }
        do {
            let raw = try await gmail.rawMessageData(id: id)
            let entry = await Task.detached(priority: .userInitiated) { () -> ParsedThreadMail in
                let content = MailContentParser.parse(raw)
                let split = QuoteSplitter.split(html: content.displayHTML, subject: content.subject)
                return ParsedThreadMail(content: content, main: split.main, history: split.history)
            }.value
            ParsedMailCache.put(id, entry)
            if let current = mails.firstIndex(where: { $0.id == id }) { Self.fill(&mails[current], with: entry) }
        } catch {
            if let current = mails.firstIndex(where: { $0.id == id }) {
                mails[current].loadError = "Mail ophalen mislukt: \(error.localizedDescription)"
            }
        }
    }

    private static func fill(_ mail: inout ThreadMail, with entry: ParsedThreadMail) {
        mail.content = entry.content
        mail.mainHTML = entry.main
        mail.historyHTML = entry.history
        mail.loadError = nil
    }

    /// Alle mails met inhoud (voor Claude): haalt wat nog ontbreekt eerst op.
    private func loadAll() async -> (contents: [MailContent], ids: [String]) {
        await withTaskGroup(of: Void.self) { group in
            for mail in mails where mail.content == nil { group.addTask { await self.loadContent(mail.id) } }
        }
        let loaded = mails.filter { $0.content != nil }
        return (loaded.compactMap(\.content), loaded.map(\.id))
    }

    /// Start een analyse van één mail in de context van het hele gesprek; het blok komt direct na die mail.
    @discardableResult
    func analyze(messageID: String) -> ThreadAnalysisBlock? {
        guard mails.contains(where: { $0.id == messageID }) else { return nil }
        let block = ThreadAnalysisBlock(anchorMessageID: messageID)
        block.onChange = { [weak self] in self?.persist() }
        analyses.append(block)
        block.markPreparing()
        Task {
            let all = await loadAll()
            let focus = all.ids.firstIndex(of: messageID) ?? max(0, all.ids.count - 1)
            guard !all.contents.isEmpty else { return }
            block.run(mails: all.contents, focus: focus)
        }
        return block
    }

    func ask(_ question: String, in block: ThreadAnalysisBlock) {
        block.markPreparing(question: question)
        Task {
            let all = await loadAll()
            let focus = all.ids.firstIndex(of: block.anchorMessageID) ?? max(0, all.ids.count - 1)
            block.run(mails: all.contents, focus: focus, followUp: question)
        }
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
