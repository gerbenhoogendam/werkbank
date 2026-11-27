import EventKit
import WidgetKit

/// Eén moment voor de widgets: de afspraken van vandaag en morgen, de uren van vandaag en wat er loopt.
struct DayEntry: TimelineEntry {
    let date: Date
    let events: [WidgetSnapshot.Event]
    let seconds: TimeInterval
    let running: WidgetSnapshot.Running?

    var calendar: Calendar { .current }

    /// De afspraken van vandaag, hele dagen eerst.
    var today: [WidgetSnapshot.Event] {
        events.filter { calendar.isDate($0.start, inSameDayAs: date) || ($0.isAllDay && $0.start <= date && $0.end > date) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// De afspraak die nu loopt of als eerste komt (geen hele dagen).
    var next: WidgetSnapshot.Event? {
        events.filter { !$0.isAllDay && $0.end > date }.min { $0.start < $1.start }
    }

    /// De twee afspraken na `next`.
    var afterNext: [WidgetSnapshot.Event] {
        guard let next else { return [] }
        return Array(events.filter { !$0.isAllDay && $0.start > next.start }.sorted { $0.start < $1.start }.prefix(2))
    }

    static let sample: DayEntry = {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let events = [
            WidgetSnapshot.Event(title: "GH Stand-up", start: at(9), end: at(9, 15), isAllDay: false, location: ""),
            WidgetSnapshot.Event(title: "GH Belronde", start: at(11), end: at(12), isAllDay: false, location: ""),
            WidgetSnapshot.Event(title: "GH Overleg Hoveniers", start: at(14), end: at(15), isAllDay: false,
                                 location: "Kamer 2"),
            WidgetSnapshot.Event(title: "DH GH Plaatsing", start: at(15, 30), end: at(16, 30), isAllDay: false,
                                 location: ""),
        ]
        return DayEntry(date: at(13, 12), events: events, seconds: 5.75 * 3600, running: nil)
    }()
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(context.isPreview ? .sample : Self.entries(from: .now).first ?? .sample)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: Self.entries(from: now), policy: .after(now.addingTimeInterval(2 * 3600))))
    }

    /// Een moment nu, elk kwartier de komende twee uur en bij elk begin en einde van een afspraak tot middernacht.
    static func entries(from now: Date) -> [DayEntry] {
        let snapshot = WidgetShare.read()
        // Alleen eigen afspraken (GH in de eerste vijf tekens); de rest is van collega's.
        let events = loadEvents(now: now, snapshot: snapshot).filter(\.isMine)
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        var moments: Set<Date> = [now]
        for step in 1...8 { moments.insert(now.addingTimeInterval(Double(step) * 900)) }
        for event in events where !event.isAllDay {
            for moment in [event.start, event.end] where moment > now && moment <= midnight { moments.insert(moment) }
        }
        moments.insert(midnight)
        return moments.sorted().prefix(60).map { moment in
            let sameDay = snapshot.map { calendar.isDate($0.day, inSameDayAs: moment) } ?? false
            let running = sameDay ? snapshot?.running.first : nil
            return DayEntry(date: moment, events: events, seconds: snapshot?.secondsToday(at: moment) ?? 0,
                            running: running)
        }
    }

    /// Zelf uit de agenda als dat mag (dan is het altijd actueel), anders wat de app het laatst klaarzette.
    static func loadEvents(now: Date, snapshot: WidgetSnapshot?) -> [WidgetSnapshot.Event] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return snapshot?.events ?? [] }
        let store = EKEventStore()
        let hidden = Set(snapshot?.hiddenCalendarIDs ?? [])
        let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        // Twee weken vooruit: de volgende eigen afspraak kan ook morgen of na het weekend zijn.
        let end = calendar.date(byAdding: .day, value: 14, to: start) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map { event in
            WidgetSnapshot.Event(title: event.title ?? "", start: event.startDate, end: event.endDate,
                                 isAllDay: event.isAllDay, location: event.location ?? "")
        }
    }
}
