import Foundation
import SwiftData
import WerkbankCore

/// Een verbetering voor een volgende build (Voorkeuren › Verbeteringen): ingesproken met de sneltoets op de Mac of de
/// knop op de iPhone, of getypt. Gaat via iCloud mee naar je andere apparaten.
@Model
final class FeatureRequest {
    // Alle velden hebben een standaardwaarde en niets is `unique`: vereist voor CloudKit.
    var id: UUID = UUID()
    var text: String = ""
    var platformRaw: String = FeaturePlatform.desktop.rawValue
    var createdAt: Date = Date()
    /// Waar hij is vastgelegd: "mac" of "iphone".
    var source: String = ""
    /// Wanneer hij in een prompt aan Claude is meegegeven; nil = nog verzameld.
    var sentAt: Date?

    init(text: String, platform: FeaturePlatform, source: String) {
        self.text = text
        self.platformRaw = platform.rawValue
        self.source = source
        self.createdAt = .now
    }

    var platform: FeaturePlatform {
        get { FeaturePlatform(rawValue: platformRaw) ?? .desktop }
        set { platformRaw = newValue.rawValue }
    }
}

@MainActor
enum FeatureRequests {
    #if os(macOS)
    static let source = "mac"
    static let defaultPlatform = FeaturePlatform.desktop
    #else
    static let source = "iphone"
    static let defaultPlatform = FeaturePlatform.mobile
    #endif

    static func all(in context: ModelContext) -> [FeatureRequest] {
        (try? context.fetch(FetchDescriptor<FeatureRequest>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    /// Bewaart de verbeteringen; zonder hint in de tekst gelden ze voor dit apparaat. ⌘Z haalt ze weer weg.
    @discardableResult
    static func add(_ texts: [String], in context: ModelContext) -> [FeatureRequest] {
        add(texts.map { FeaturePrompt.Item(text: $0, platform: FeatureRequestSplitter.platform(of: $0) ?? defaultPlatform) },
            in: context)
    }

    @discardableResult
    static func add(_ items: [FeaturePrompt.Item], in context: ModelContext) -> [FeatureRequest] {
        let added = items.compactMap { item -> FeatureRequest? in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : FeatureRequest(text: text, platform: item.platform, source: source)
        }
        guard !added.isEmpty else { return [] }
        for request in added { context.insert(request) }
        try? context.save()
        let ids = Set(added.map(\.id))
        UndoCenter.shared.record(added.count == 1 ? "Verbetering bewaren" : "\(added.count) verbeteringen bewaren", undo: {
            for request in all(in: context) where ids.contains(request.id) { context.delete(request) }
            try? context.save()
        })
        return added
    }

    static func delete(_ request: FeatureRequest, in context: ModelContext) {
        context.delete(request)
        try? context.save()
    }

    /// De prompt met wat nog verzameld is.
    static func prompt(_ requests: [FeatureRequest]) -> String {
        FeaturePrompt.build(requests.map { FeaturePrompt.Item(text: $0.text, platform: $0.platform) })
    }

    /// Na het kopiëren van de prompt: doorgegeven (blijft zichtbaar onder Doorgegeven, terug te zetten).
    static func markSent(_ requests: [FeatureRequest], in context: ModelContext) {
        let now = Date()
        for request in requests { request.sentAt = now }
        try? context.save()
        let ids = Set(requests.map(\.id))
        UndoCenter.shared.record("Verbeteringen doorgeven", undo: {
            for request in all(in: context) where ids.contains(request.id) { request.sentAt = nil }
            try? context.save()
        })
    }
}
