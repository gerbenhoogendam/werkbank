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
    /// Het scherm op het moment van inspreken of typen (JPEG); via iCloud als los bestand.
    @Attribute(.externalStorage) var screenshot: Data?
    /// Wanneer de screenshot is gemaakt (het label in de prompt).
    var capturedAt: Date?
    /// Klikken en kaders uit de aanwijsmodus (JSON van `FeedbackMark`); [n] in de tekst verwijst ernaar.
    var marksData: Data?

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

    var device: String { source == "iphone" ? "iPhone" : "Mac" }
    var marks: [FeedbackMark] { FeedbackMark.decode(marksData) }
    var moment: Date { capturedAt ?? createdAt }

    var promptItem: FeaturePrompt.Item {
        FeaturePrompt.Item(text: text, platform: platform, date: moment, device: device, hasScreenshot: screenshot != nil,
                           marks: marks)
    }
}

/// Een screenshot met het moment waarop hij is gemaakt.
struct CapturedScreen {
    var data: Data?
    var date: Date
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
    /// `screenshot`: het scherm op het moment van vastleggen; alle verbeteringen uit één keer inspreken krijgen dezelfde.
    /// `marks`: de klikken en kaders van die opname; elke verbetering krijgt die waar haar tekst [n] naar verwijst
    /// (één verbetering: alle).
    @discardableResult
    static func add(_ texts: [String], screenshot: CapturedScreen?, marks: [FeedbackMark] = [],
                    in context: ModelContext) -> [FeatureRequest] {
        add(texts.map { text in
            FeaturePrompt.Item(text: text, platform: FeatureRequestSplitter.platform(of: text) ?? defaultPlatform,
                               marks: texts.count == 1 ? marks : marks.filter { text.contains("[\($0.number)]") })
        }, screenshot: screenshot, in: context)
    }

    @discardableResult
    static func add(_ items: [FeaturePrompt.Item], screenshot: CapturedScreen?, in context: ModelContext) -> [FeatureRequest] {
        let added = items.compactMap { item -> FeatureRequest? in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let request = FeatureRequest(text: text, platform: item.platform, source: source)
            request.screenshot = screenshot?.data
            request.capturedAt = screenshot?.date
            request.marksData = FeedbackMark.encode(item.marks)
            return request
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

    /// De prompt met wat nog verzameld is (als tekst, zonder de screenshots).
    static func prompt(_ requests: [FeatureRequest]) -> String {
        FeaturePrompt.build(requests.map(\.promptItem))
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
