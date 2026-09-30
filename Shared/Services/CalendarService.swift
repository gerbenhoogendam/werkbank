import EventKit
import Foundation
import SwiftUI

struct AgendaCalendar: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
    let allowsModifications: Bool
}

struct AgendaEvent: Identifiable, Equatable {
    /// Stabiel per afspraak-voorkomen (herhalende afspraken delen een eventIdentifier).
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let color: Color
}

/// EventKit-laag. `revision` verhoogt bij elke `EKEventStoreChanged`, zodat views live meebewegen.
@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    private(set) var status: EKAuthorizationStatus
    private(set) var calendars: [AgendaCalendar] = []
    private(set) var revision = 0

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?

    var hasAccess: Bool { status == .fullAccess }
    var isDenied: Bool { status == .denied || status == .restricted }

    private init() {
        status = EKEventStore.authorizationStatus(for: .event)
        reloadCalendars()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.storeChanged() }
        }
    }

    // MARK: Toegang

    func requestAccess() async {
        do { _ = try await store.requestFullAccessToEvents() } catch { /* status hieronder bepaalt de UI */ }
        status = EKEventStore.authorizationStatus(for: .event)
        reloadCalendars()
        revision += 1
    }

    func refreshStatus() {
        let new = EKEventStore.authorizationStatus(for: .event)
        guard new != status else { return }
        status = new
        reloadCalendars()
        revision += 1
    }

    private func storeChanged() {
        store.refreshSourcesIfNecessary()
        reloadCalendars()
        revision += 1
    }

    private func reloadCalendars() {
        guard hasAccess else { calendars = []; return }
        calendars = store.calendars(for: .event)
            .map { AgendaCalendar(id: $0.calendarIdentifier, title: $0.title,
                                  color: Color(cgColor: $0.cgColor), allowsModifications: $0.allowsContentModifications) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: Lezen

    func events(from start: Date, to end: Date, hiddenCalendarIDs: Set<String>) -> [AgendaEvent] {
        guard hasAccess else { return [] }
        let visible = store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
        return store.events(matching: predicate)
            .map { event in
                AgendaEvent(
                    id: "\(event.eventIdentifier ?? UUID().uuidString)|\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "(zonder titel)",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarID: event.calendar.calendarIdentifier,
                    calendarTitle: event.calendar.title,
                    color: Color(cgColor: event.calendar.cgColor)
                )
            }
            .sorted { $0.start < $1.start }
    }

    // MARK: Schrijven

    var writableCalendars: [AgendaCalendar] { calendars.filter(\.allowsModifications) }

    /// Standaard doelagenda: de ingestelde, anders "Werk", anders de eerste zichtbare schrijfbare.
    func defaultTargetCalendarID(hiddenCalendarIDs: Set<String>) -> String? {
        let writable = writableCalendars
        if let id = AppSettings.defaultCalendarID, writable.contains(where: { $0.id == id }) { return id }
        if let work = writable.first(where: { $0.title.lowercased() == "werk" }) { return work.id }
        if let visible = writable.first(where: { !hiddenCalendarIDs.contains($0.id) }) { return visible.id }
        return writable.first?.id
    }

    func createEvent(title: String, start: Date, end: Date, calendarID: String) throws {
        guard let calendar = store.calendar(withIdentifier: calendarID) else {
            throw CalendarError.calendarNotFound
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        revision += 1
    }

    enum CalendarError: LocalizedError {
        case calendarNotFound
        var errorDescription: String? { "De gekozen agenda bestaat niet meer." }
    }
}
