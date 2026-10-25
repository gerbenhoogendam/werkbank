import EventKit
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AgendaCalendar: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
    let allowsModifications: Bool
}

struct AgendaEvent: Identifiable, Hashable {
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
    let location: String?
    let notes: String?
    let url: URL?
    let organizer: String?
    let attendees: [String]
}

/// EventKit-laag. `revision` verhoogt bij elke `EKEventStoreChanged`, zodat views live meebewegen.
@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    private(set) var status: EKAuthorizationStatus
    private(set) var calendars: [AgendaCalendar] = []
    private(set) var revision = 0 {
        didSet { eventCache.removeAll() }
    }

    @ObservationIgnored private let store = EKEventStore()
    /// Opgehaalde afspraken per periode, tot er iets verandert (`revision`). De agenda vraagt ze bij elke
    /// herberekening van de weergave op; zo gaat dat niet telkens naar EventKit.
    @ObservationIgnored private var eventCache: [EventQuery: [AgendaEvent]] = [:]
    @ObservationIgnored private var changeTask: Task<Void, Never>?

    private struct EventQuery: Hashable {
        let start: Date
        let end: Date
        let hidden: Set<String>
    }
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
        store.refreshSourcesIfNecessary()
        let new = EKEventStore.authorizationStatus(for: .event)
        guard new != status else { return }
        status = new
        reloadCalendars()
        revision += 1
    }

    /// Tijdens synchroniseren komen wijzigingen vaak in een reeks: één keer verversen, 250 ms na de laatste.
    private func storeChanged() {
        changeTask?.cancel()
        changeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            self.reloadCalendars()
            self.revision += 1
        }
    }

    /// Per agenda een naam die op elke Mac gelijk is ("account|agenda"); de id's verschillen per Mac.
    func calendarKeys() -> [String: String] {
        guard hasAccess else { return [:] }
        var keys: [String: String] = [:]
        for calendar in store.calendars(for: .event) {
            keys[calendar.calendarIdentifier] = "\(calendar.source?.title ?? "")|\(calendar.title)"
        }
        return keys
    }

    /// Na het overnemen van voorkeuren van een andere Mac (kleuren, verborgen agenda's).
    func settingsChanged() {
        CalendarColors.reload()
        reloadCalendars()
        revision += 1
    }

    private func reloadCalendars() {
        guard hasAccess else { calendars = []; return }
        calendars = store.calendars(for: .event)
            .map { AgendaCalendar(id: $0.calendarIdentifier, title: $0.title,
                                  color: CalendarColors.color(for: $0.calendarIdentifier) ?? Color(cgColor: $0.cgColor), allowsModifications: $0.allowsContentModifications) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: Lezen

    func events(from start: Date, to end: Date, hiddenCalendarIDs: Set<String>) -> [AgendaEvent] {
        guard hasAccess else { return [] }
        let key = EventQuery(start: start, end: end, hidden: hiddenCalendarIDs)
        if let cached = eventCache[key] { return cached }
        if eventCache.count > 12 { eventCache.removeAll() }
        let result = fetchEvents(from: start, to: end, hiddenCalendarIDs: hiddenCalendarIDs)
        eventCache[key] = result
        return result
    }

    private func fetchEvents(from start: Date, to end: Date, hiddenCalendarIDs: Set<String>) -> [AgendaEvent] {
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
                    color: CalendarColors.color(for: event.calendar.calendarIdentifier) ?? Color(cgColor: event.calendar.cgColor),
                    eventIdentifier: event.eventIdentifier ?? "",
                    isRecurring: event.hasRecurrenceRules,
                    location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
                    notes: event.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
                    url: event.url,
                    organizer: event.organizer?.name,
                    attendees: (event.attendees ?? []).compactMap { $0.name }
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
        recordCreated("Inplannen", identifier: event.eventIdentifier)
    }

    /// Zet een afspraak in een andere agenda. Bij een herhalende afspraak kiest `thisAndFuture` of alleen
    /// dit voorkomen verhuist of ook alle volgende. EventKit weigert dit soms (andere account, uitnodiging van
    /// iemand anders); die fout komt ongewijzigd terug, en niet-opgeslagen wijzigingen worden weggegooid.
    func moveEvent(_ event: AgendaEvent, toCalendarID: String, thisAndFuture: Bool) throws {
        guard let target = store.calendar(withIdentifier: toCalendarID) else { throw CalendarError.calendarNotFound }
        guard target.allowsContentModifications else { throw CalendarError.targetReadOnly }
        guard let ek = ekEvent(for: event) else { throw CalendarError.eventNotFound }
        guard ek.calendar.allowsContentModifications else { throw CalendarError.eventReadOnly }
        let oldCalendarID = ek.calendar.calendarIdentifier
        let undoable = !thisAndFuture && !ek.hasRecurrenceRules
        ek.calendar = target
        do {
            try store.save(ek, span: thisAndFuture ? .futureEvents : .thisEvent)
        } catch {
            store.reset()
            throw error
        }
        revision += 1
        if undoable, let identifier = ek.eventIdentifier {
            UndoCenter.shared.record("Andere agenda kiezen", undo: { [weak self] in
                self?.moveBack(identifier: identifier, toCalendarID: oldCalendarID)
            })
        }
    }

    /// Andere begin- en eindtijd (een afspraak verslepen in de agenda). Bij een herhalende afspraak kiest
    /// `thisAndFuture` of alleen dit voorkomen verschuift of ook alle volgende.
    func reschedule(_ event: AgendaEvent, start: Date, end: Date, thisAndFuture: Bool) throws {
        guard end > start else { throw CalendarError.invalidRange }
        guard let ek = ekEvent(for: event) else { throw CalendarError.eventNotFound }
        guard ek.calendar.allowsContentModifications else { throw CalendarError.eventReadOnly }
        let oldStart: Date = ek.startDate
        let oldEnd: Date = ek.endDate
        let undoable = !thisAndFuture && !ek.hasRecurrenceRules
        ek.startDate = start
        ek.endDate = end
        do {
            try store.save(ek, span: thisAndFuture ? .futureEvents : .thisEvent)
        } catch {
            store.reset()
            throw error
        }
        revision += 1
        if undoable, let identifier = ek.eventIdentifier {
            UndoCenter.shared.record("Afspraak verschuiven", undo: { [weak self] in
                self?.setTimes(identifier: identifier, start: oldStart, end: oldEnd)
            }, redo: { [weak self] in
                self?.setTimes(identifier: identifier, start: start, end: end)
            })
        }
    }

    // MARK: Ongedaan maken (alleen afspraken die niet herhalen)

    private func setTimes(identifier: String, start: Date, end: Date) {
        guard let ek = store.event(withIdentifier: identifier), ek.calendar.allowsContentModifications else { return }
        ek.startDate = start
        ek.endDate = end
        do {
            try store.save(ek, span: .thisEvent)
            revision += 1
        } catch {
            store.reset()
        }
    }

    private func removeEvent(identifier: String) {
        guard let ek = store.event(withIdentifier: identifier), ek.calendar.allowsContentModifications else { return }
        do {
            try store.remove(ek, span: .thisEvent)
            revision += 1
        } catch {
            store.reset()
        }
    }

    private func moveBack(identifier: String, toCalendarID calendarID: String) {
        guard let ek = store.event(withIdentifier: identifier), let target = store.calendar(withIdentifier: calendarID),
              target.allowsContentModifications else { return }
        ek.calendar = target
        do {
            try store.save(ek, span: .thisEvent)
            revision += 1
        } catch {
            store.reset()
        }
    }

    private func recordCreated(_ name: String, identifier: String?) {
        guard let identifier else { return }
        UndoCenter.shared.record(name, undo: { [weak self] in self?.removeEvent(identifier: identifier) })
    }

    // MARK: Kleuren

    /// Stelt een eigen kleur in voor een agenda (alleen in Werkbank; de Agenda-app en de agenda zelf blijven ongemoeid).
    /// `nil` zet de oorspronkelijke kleur terug.
    func setColor(_ color: Color?, forCalendar id: String) {
        CalendarColors.set(color, for: id)
        reloadCalendars()
        revision += 1
    }

    var hasCustomColors: Bool { CalendarColors.hasAny }
    func hasCustomColor(_ id: String) -> Bool { CalendarColors.color(for: id) != nil }

    // MARK: Bewerken

    /// De bewerkbare velden van een afspraak, zoals ze nu in EventKit staan.
    func editableEvent(for event: AgendaEvent) -> EventEdit? {
        guard let ek = ekEvent(for: event) else { return nil }
        let rules = ek.recurrenceRules ?? []
        let repeatOption: EventRepeat
        if rules.isEmpty {
            repeatOption = .none
        } else if rules.count == 1, let rule = rules.first, rule.recurrenceEnd == nil,
                  rule.daysOfTheWeek == nil, rule.daysOfTheMonth == nil, rule.monthsOfTheYear == nil,
                  rule.weeksOfTheYear == nil, rule.daysOfTheYear == nil, rule.setPositions == nil {
            switch (rule.frequency, rule.interval) {
            case (.daily, 1): repeatOption = .daily
            case (.weekly, 1): repeatOption = .weekly
            case (.weekly, 2): repeatOption = .biweekly
            case (.monthly, 1): repeatOption = .monthly
            case (.yearly, 1): repeatOption = .yearly
            default: repeatOption = .custom
            }
        } else {
            repeatOption = .custom
        }
        let alarms = ek.alarms ?? []
        let alert: EventAlert
        if alarms.isEmpty {
            alert = .none
        } else if alarms.count == 1, alarms[0].absoluteDate == nil, alarms[0].proximity == .none,
                  let match = EventAlert(rawValue: Int((-alarms[0].relativeOffset / 60).rounded())), match.rawValue >= 0 {
            alert = match
        } else {
            alert = .custom
        }
        let availability: EventAvailability = switch ek.availability {
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .unavailable
        default: .busy
        }
        return EventEdit(title: ek.title ?? "", location: ek.location ?? "", urlText: ek.url?.absoluteString ?? "",
                         isAllDay: ek.isAllDay, start: ek.startDate, end: ek.endDate,
                         calendarID: ek.calendar.calendarIdentifier, repeatOption: repeatOption, alert: alert,
                         availability: availability, notes: ek.notes ?? "",
                         canModify: ek.calendar.allowsContentModifications)
    }

    func saveEvent(_ event: AgendaEvent, edit: EventEdit, original: EventEdit, thisAndFuture: Bool) throws {
        guard let ek = ekEvent(for: event) else { throw CalendarError.eventNotFound }
        guard ek.calendar.allowsContentModifications else { throw CalendarError.eventReadOnly }
        let undoable = !thisAndFuture && original.repeatOption == .none && edit.repeatOption == .none
        if edit.calendarID != ek.calendar.calendarIdentifier {
            guard let target = store.calendar(withIdentifier: edit.calendarID) else { throw CalendarError.calendarNotFound }
            guard target.allowsContentModifications else { throw CalendarError.targetReadOnly }
            ek.calendar = target
        }
        try apply(edit, to: ek, originalRepeat: original.repeatOption, originalAlert: original.alert)
        do {
            try store.save(ek, span: thisAndFuture ? .futureEvents : .thisEvent)
        } catch {
            store.reset()
            throw error
        }
        revision += 1
        if undoable, let identifier = ek.eventIdentifier {
            UndoCenter.shared.record("Afspraak wijzigen", undo: { [weak self] in
                self?.restore(identifier: identifier, to: original, from: edit)
            })
        }
    }

    private func restore(identifier: String, to original: EventEdit, from current: EventEdit) {
        guard let ek = store.event(withIdentifier: identifier), ek.calendar.allowsContentModifications else { return }
        if original.calendarID != ek.calendar.calendarIdentifier,
           let calendar = store.calendar(withIdentifier: original.calendarID), calendar.allowsContentModifications {
            ek.calendar = calendar
        }
        do {
            try apply(original, to: ek, originalRepeat: current.repeatOption, originalAlert: current.alert)
            try store.save(ek, span: .thisEvent)
            revision += 1
        } catch {
            store.reset()
        }
    }

    /// Maakt een nieuwe afspraak met alle velden van het bewerkformulier.
    func createEvent(edit: EventEdit) throws {
        let identifier = try insert(edit: edit)
        recordCreated("Afspraak maken", identifier: identifier)
    }

    @discardableResult
    private func insert(edit: EventEdit) throws -> String? {
        guard let calendar = store.calendar(withIdentifier: edit.calendarID) else { throw CalendarError.calendarNotFound }
        guard calendar.allowsContentModifications else { throw CalendarError.targetReadOnly }
        let ek = EKEvent(eventStore: store)
        ek.calendar = calendar
        try apply(edit, to: ek, originalRepeat: nil, originalAlert: nil)
        do {
            try store.save(ek, span: .thisEvent)
        } catch {
            store.reset()
            throw error
        }
        revision += 1
        return ek.eventIdentifier
    }

    /// Zet de velden van het formulier op een EKEvent. Herhaling en herinnering worden alleen aangeraakt als ze
    /// anders zijn dan voor het bewerken (zo blijft een aangepaste regel staan).
    private func apply(_ edit: EventEdit, to ek: EKEvent, originalRepeat: EventRepeat?, originalAlert: EventAlert?) throws {
        let cal = Calendar.current
        var start = edit.start
        var end = edit.end
        if edit.isAllDay {
            start = cal.startOfDay(for: edit.start)
            end = cal.date(byAdding: DateComponents(day: 1, second: -1), to: cal.startOfDay(for: edit.end)) ?? edit.end
            guard end >= start else { throw CalendarError.invalidRange }
        } else {
            guard end > start else { throw CalendarError.invalidRange }
        }

        let urlText = edit.urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        var url: URL?
        if !urlText.isEmpty {
            guard let parsed = URL(string: urlText), parsed.scheme != nil else { throw CalendarError.invalidURL }
            url = parsed
        }

        let title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        ek.title = title.isEmpty ? "(zonder titel)" : title
        ek.location = edit.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : edit.location
        ek.url = url
        ek.isAllDay = edit.isAllDay
        ek.startDate = start
        ek.endDate = end
        ek.notes = edit.notes.isEmpty ? nil : edit.notes
        ek.availability = switch edit.availability {
        case .busy: .busy
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .unavailable
        }

        if edit.repeatOption != .custom, edit.repeatOption != (originalRepeat ?? .none) {
            for rule in ek.recurrenceRules ?? [] { ek.removeRecurrenceRule(rule) }
            if let rule = edit.repeatOption.rule { ek.addRecurrenceRule(rule) }
        }
        if edit.alert != .custom, edit.alert != (originalAlert ?? .none) {
            for alarm in ek.alarms ?? [] { ek.removeAlarm(alarm) }
            if edit.alert != .none { ek.addAlarm(EKAlarm(relativeOffset: -Double(edit.alert.rawValue) * 60)) }
        }
    }

    /// Lege afspraak voor het formulier "nieuwe afspraak" (standaardagenda, bezet, geen herhaling).
    func blankEdit(start: Date, end: Date, hiddenCalendarIDs: Set<String>) -> EventEdit {
        EventEdit(title: "", location: "", urlText: "", isAllDay: false, start: start, end: end,
                  calendarID: defaultTargetCalendarID(hiddenCalendarIDs: hiddenCalendarIDs) ?? "",
                  repeatOption: .none, alert: .none, availability: .busy, notes: "", canModify: true)
    }

    func deleteEvent(_ event: AgendaEvent, thisAndFuture: Bool) throws {
        guard let ek = ekEvent(for: event) else { throw CalendarError.eventNotFound }
        guard ek.calendar.allowsContentModifications else { throw CalendarError.eventReadOnly }
        // Voor ⌘Z: de velden van een losse afspraak (deelnemers kunnen niet terug).
        let snapshot = ek.hasRecurrenceRules ? nil : editableEvent(for: event)
        do {
            try store.remove(ek, span: thisAndFuture ? .futureEvents : .thisEvent)
        } catch {
            store.reset()
            throw error
        }
        revision += 1
        if let snapshot {
            UndoCenter.shared.record("Afspraak verwijderen", undo: { [weak self] in _ = try? self?.insert(edit: snapshot) })
        }
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
        case calendarNotFound, targetReadOnly, eventNotFound, eventReadOnly, invalidRange, invalidURL
        var errorDescription: String? {
            switch self {
            case .calendarNotFound: "De gekozen agenda bestaat niet meer."
            case .targetReadOnly: "In die agenda kun je niets toevoegen (alleen lezen)."
            case .eventNotFound: "De afspraak is niet meer gevonden; hij is waarschijnlijk gewijzigd."
            case .eventReadOnly: "Deze afspraak staat in een agenda die je niet kunt wijzigen."
            case .invalidRange: "Het einde moet na het begin liggen."
            case .invalidURL: "Die link is geen geldige URL (bijvoorbeeld https://…)."
            }
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Bewerken: waarden

enum EventRepeat: String, CaseIterable, Identifiable {
    case none, daily, weekly, biweekly, monthly, yearly, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Nooit"
        case .daily: "Elke dag"
        case .weekly: "Elke week"
        case .biweekly: "Elke 2 weken"
        case .monthly: "Elke maand"
        case .yearly: "Elk jaar"
        case .custom: "Aangepast (ongewijzigd)"
        }
    }
    var rule: EKRecurrenceRule? {
        switch self {
        case .none, .custom: nil
        case .daily: EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly: EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .biweekly: EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
        case .monthly: EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly: EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        }
    }
}

/// Herinnering: het aantal minuten vóór de afspraak (-1 = geen, -2 = een aangepaste die ongewijzigd blijft).
enum EventAlert: Int, CaseIterable, Identifiable {
    case none = -1, custom = -2
    case atTime = 0, min5 = 5, min10 = 10, min15 = 15, min30 = 30, hour1 = 60, hour2 = 120, day1 = 1440, day2 = 2880
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .none: "Geen"
        case .custom: "Aangepast (ongewijzigd)"
        case .atTime: "Op het moment zelf"
        case .min5: "5 minuten ervoor"
        case .min10: "10 minuten ervoor"
        case .min15: "15 minuten ervoor"
        case .min30: "30 minuten ervoor"
        case .hour1: "1 uur ervoor"
        case .hour2: "2 uur ervoor"
        case .day1: "1 dag ervoor"
        case .day2: "2 dagen ervoor"
        }
    }
}

enum EventAvailability: CaseIterable, Identifiable {
    case busy, free, tentative, unavailable
    var id: Self { self }
    var title: String {
        switch self {
        case .busy: "Bezet"
        case .free: "Beschikbaar"
        case .tentative: "Voorlopig"
        case .unavailable: "Niet aanwezig"
        }
    }
}

struct EventEdit: Equatable {
    var title: String
    var location: String
    var urlText: String
    var isAllDay: Bool
    var start: Date
    var end: Date
    var calendarID: String
    var repeatOption: EventRepeat
    var alert: EventAlert
    var availability: EventAvailability
    var notes: String
    var canModify: Bool
}

// MARK: - Eigen agendakleuren

/// Eigen kleur per agenda, alleen binnen Werkbank (UserDefaults). EventKit kent geen kleur per afspraak.
@MainActor
enum CalendarColors {
    private static let key = "calendar.colors"

    /// Eén keer uit UserDefaults gelezen, daarna uit het geheugen (wordt per afspraak opgevraagd).
    private static var cache: [String: [Double]]?

    private static var stored: [String: [Double]] {
        if let cache { return cache }
        let loaded = UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] ?? [:]
        cache = loaded
        return loaded
    }

    static var hasAny: Bool { !stored.isEmpty }

    /// Opnieuw uit UserDefaults lezen (na het overnemen van voorkeuren van een andere Mac).
    static func reload() { cache = nil }

    static func color(for id: String) -> Color? {
        guard let c = stored[id], c.count == 3 else { return nil }
        return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: 1)
    }

    static func set(_ color: Color?, for id: String) {
        var all = stored
        if let color, let components = rgb(color) { all[id] = components } else { all[id] = nil }
        UserDefaults.standard.set(all, forKey: key)
        cache = all
    }

    private static func rgb(_ color: Color) -> [Double]? {
        #if os(macOS)
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return [Double(r), Double(g), Double(b)]
        #endif
    }
}
