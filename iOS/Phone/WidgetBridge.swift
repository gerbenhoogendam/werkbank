import SwiftData
import WidgetKit

/// Zet na elke verandering die telt (naar de achtergrond, terug, timer aan of uit) een samenvatting klaar voor de
/// widgets en laat ze opnieuw tekenen.
@MainActor
enum WidgetBridge {
    static func update(in context: ModelContext) {
        let calendar = TijdDates.calendar
        let now = Date()
        let day = calendar.startOfDay(for: now)
        let entries = (try? context.fetch(FetchDescriptor<TimeEntry>())) ?? []
        let today = entries.filter { calendar.isDate(TijdDates.date(of: $0), inSameDayAs: now) }
        let finished = today.filter { $0.status == .finished }.reduce(0.0) { $0 + $1.accumulated }
        let running = today.filter { $0.status == .running || $0.status == .paused }.map { entry in
            WidgetSnapshot.Running(client: entry.client, accumulated: entry.accumulated,
                                   runningSince: entry.status == .running ? entry.runningSince : nil)
        }
        let hidden = AppSettings.hiddenCalendarIDs
        let end = calendar.date(byAdding: .day, value: 2, to: day) ?? now
        let events = CalendarService.shared.events(from: day, to: end, hiddenCalendarIDs: hidden).map { event in
            WidgetSnapshot.Event(title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay,
                                 location: event.location ?? "")
        }
        WidgetShare.write(WidgetSnapshot(writtenAt: now, day: day, finishedSeconds: finished, running: running,
                                         hiddenCalendarIDs: Array(hidden), events: events))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
