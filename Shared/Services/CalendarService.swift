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
    /// Nodig om dezelfde afspraak later in EventKit terug te vinden (verplaatsen naar een andere agenda).
    let eventIdentifier: String
    let isRecurring: Bool
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
                    color: Color(cgColor: event.calendar.cgColor),
                    eventIdentifier: event.eventIdentifier ?? "",
                    isRecurring: event.hasRecurrenceRules
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

    /// Zet een afspraak in een andere agenda. Bij een herhalende afspraak kiest `thisAndFuture` of alleen
    /// dit voorkomen verhuist of ook alle volgende. EventKit weigert dit soms (andere account, uitnodiging van
    /// iemand anders); die fout komt ongewijzigd terug, en niet-opgeslagen wijzigingen worden weggegooid.
    func moveEvent(_ event: AgendaEvent, toCalendarID: String, thisAndFuture: Bool) throws {
        guard let target = store.calendar(withIdentifier: toCalendarID) else { throw CalendarError.calendarNotFound }
        guard target.allowsContentModifications else { throw CalendarError.targetReadOnly }
        guard let ek = ekEvent(for: event) else { throw CalendarError.eventNotFound }
        guard ek.calendar.allowsContentModifications else { throw CalendarError.eventReadOnly }
        ek.calendar = target
        do {
            try store.save(ek, span: thisAndFuture ? .futureEvents : .thisEvent)
        } catch {
            store.reset()
            throw error
        }
        revision += 1
    }

    private func ekEvent(for event: AgendaEvent) -> EKEvent? {
        guard !event.eventIdentifier.isEmpty else { return nil }
        let predicate = store.predicateForEvents(withStart: event.start.addingTimeInterval(-1),
                                                 end: event.end.addingTimeInterval(1), calendars: nil)
        return store.events(matching: predicate).first {
            $0.eventIdentifier == event.eventIdentifier && $0.startDate == event.start
        }
    }

    enum CalendarError: LocalizedError {
        case calendarNotFound, targetReadOnly, eventNotFound, eventReadOnly
        var errorDescription: String? {
            switch self {
            case .calendarNotFound: "De gekozen agenda bestaat niet meer."
            case .targetReadOnly: "In die agenda kun je niets toevoegen (alleen lezen)."
            case .eventNotFound: "De afspraak is niet meer gevonden; hij is waarschijnlijk gewijzigd."
            case .eventReadOnly: "Deze afspraak staat in een agenda die je niet kunt wijzigen."
            }
        }
    }
}
