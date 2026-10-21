import Foundation
import Observation

/// Wat het detailvenster in de dagkolom toont.
enum EventTarget: Equatable {
    case existing(AgendaEvent)
    case new(start: Date, end: Date)
}

/// Welke afspraak (of nieuwe afspraak) er nu in welke dagkolom van de agenda is opgeklapt.
@MainActor
@Observable
final class EventDetailStore {
    static let shared = EventDetailStore()

    struct Presented: Equatable {
        var day: Date
        var target: EventTarget
        var id = UUID()
    }

    private(set) var presented: Presented?

    func present(_ target: EventTarget, day: Date) {
        presented = Presented(day: day, target: target)
    }

    func close() { presented = nil }
}
