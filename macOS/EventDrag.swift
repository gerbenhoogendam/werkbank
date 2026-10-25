import AppKit
import SwiftUI
import WerkbankCore

/// Een afspraak optillen en verslepen in de week- of dagagenda: het hele blok naar een andere tijd of dag, de boven-
/// of onderrand voor begin of eind, of naar de agendafilters bovenin. Daar klapt "Verplaatsen naar" open met de andere
/// agenda's (zoals een mail bij de mailboxen). Een herhalende afspraak vraagt eerst "alleen deze / ook volgende".
@MainActor
@Observable
final class EventDrag {
    enum Mode { case move, start, end }
    enum Phase { case idle, dragging, confirming }

    /// Een wijziging die (bij een herhalende afspraak) op de keuze wacht.
    struct Pending: Identifiable {
        enum Change {
            case times(start: Date, end: Date)
            case calendar(AgendaCalendar)
        }

        let event: AgendaEvent
        let change: Change
        var id: String { event.id }

        var question: String {
            switch change {
            case .times(let start, let end):
                "\"\(event.title)\" verschuiven naar \(DutchDate.weekdayAndDay(start)) \(DutchDate.range(start, end))."
            case .calendar(let target):
                "\"\(event.title)\" verplaatsen naar \(target.title)."
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var event: AgendaEvent?
    private(set) var mode: Mode = .move
    private(set) var start = Date.distantPast
    private(set) var end = Date.distantPast
    /// Boven de agendafilters of de kaart eronder: de afspraak gaat naar een andere agenda, op dezelfde tijd.
    private(set) var overCalendars = false
    private(set) var hoveredCalendar: String?
    /// Het hele blok hangt buiten de tijdlijn (en niet bij de agendafilters): loslaten laat alles zoals het was.
    private(set) var isOutside = false
    /// Waar de afspraak heen kan: schrijfbaar, niet uitgezet in Voorkeuren en niet de agenda waar hij al in staat.
    private(set) var targets: [AgendaCalendar] = []
    /// Muispositie in "main"-coördinaten; alleen de zwevende laag leest dit.
    private(set) var pointer: CGPoint = .zero
    private(set) var pending: Pending?

    // Geometrie in "main"-coördinaten, gevuld door de agenda.
    @ObservationIgnored var filterFrame: CGRect = .zero
    @ObservationIgnored var cardFrame: CGRect = .zero
    @ObservationIgnored var tileFrames: [String: CGRect] = [:]
    @ObservationIgnored var disabledCalendarIDs: Set<String> = []

    @ObservationIgnored private var geometry: AgendaGeometry?
    /// De dagkolom waarin je de afspraak pakte (sleutel van `AgendaGeometry.dayFrames`) en die waar hij nu hangt.
    @ObservationIgnored private var originColumn = Date()
    @ObservationIgnored private var column = Date()
    @ObservationIgnored private var originDay = Date()
    @ObservationIgnored private var grabMinutes: Double = 0
    @ObservationIgnored private let calendar = Calendar.current

    var isDragging: Bool { phase == .dragging }

    /// Het blok zoals het nu zou komen te staan. Nil boven de agendafilters en bij een verhuizing naar een andere agenda.
    var preview: AgendaEvent? {
        guard let event, phase != .idle, !overCalendars, !isOutside else { return nil }
        if case .calendar = pending?.change { return nil }
        return event.with(start: start, end: end)
    }

    /// De afspraak die nu opgetild is (het origineel wordt dan vaag getoond).
    func isLifted(_ other: AgendaEvent) -> Bool {
        event?.id == other.id && (phase == .dragging || preview != nil)
    }

    /// Alleen afspraken met een tijd, in een agenda die je mag wijzigen.
    static func canDrag(_ event: AgendaEvent) -> Bool {
        !event.isAllDay && CalendarService.shared.calendars.contains { $0.id == event.calendarID && $0.allowsModifications }
    }

    // MARK: Slepen

    func begin(_ event: AgendaEvent, mode: Mode, column key: Date, location: CGPoint, geometry: AgendaGeometry) {
        guard phase == .idle else { return }
        self.geometry = geometry
        originColumn = key
        column = key
        originDay = calendar.startOfDay(for: key)
        grabMinutes = minutes(atY: location.y, column: key) ?? 0
        targets = mode == .move
            ? CalendarService.shared.writableCalendars.filter(isTarget(for: event))
            : []
        pointer = location
        overCalendars = false
        hoveredCalendar = nil
        isOutside = false
        // Optillen: het blok komt los met een korte veer (schaduw en het vage origineel animeren mee).
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
            self.event = event
            self.mode = mode
            start = event.start
            end = event.end
            phase = .dragging
        }
    }

    func update(_ location: CGPoint) {
        guard phase == .dragging, let event, let geometry else { return }
        pointer = location
        let near = isNearCalendars(location)
        if near != overCalendars { overCalendars = near }
        let hovered = near ? tileFrames.first(where: { $0.value.contains(location) })?.key : nil
        if hovered != hoveredCalendar { hoveredCalendar = hovered }
        let outside = !near && mode == .move && !geometry.scrollViewport.contains(location)
        if outside != isOutside { isOutside = outside }
        guard !near, !outside else { return }

        let visible = geometry.startHour * 60 ... geometry.endHour * 60
        let oldStart = minutesFromOrigin(event.start)
        let oldEnd = minutesFromOrigin(event.end)
        var day = originDay
        let result: (start: Int, end: Int)
        switch mode {
        case .move:
            if let key = geometry.dayFrames.first(where: { $0.value.minX <= location.x && location.x < $0.value.maxX })?.key {
                column = key
            }
            guard let pointerMinutes = minutes(atY: location.y, column: column) else { return }
            day = calendar.startOfDay(for: column)
            result = EventDragMath.moved(start: oldStart, end: oldEnd, delta: Int((pointerMinutes - grabMinutes).rounded()),
                                         visible: visible)
        case .start, .end:
            guard let pointerMinutes = minutes(atY: location.y, column: originColumn) else { return }
            result = EventDragMath.resized(start: oldStart, end: oldEnd, edge: mode == .start ? .start : .end,
                                           pointer: Int(pointerMinutes.rounded()), visible: visible)
        }
        let newStart = date(day, result.start)
        let newEnd = date(day, result.end)
        if newStart != start { start = newStart }
        if newEnd != end { end = newEnd }
    }

    /// Opnieuw rekenen op dezelfde muispositie (na automatisch scrollen).
    func refresh() {
        update(pointer)
    }

    func end(_ location: CGPoint) {
        guard phase == .dragging, let event else { return }
        update(location)
        if isOutside {
            reset()
        } else if overCalendars {
            if let id = hoveredCalendar, let target = targets.first(where: { $0.id == id }) {
                commit(Pending(event: event, change: .calendar(target)))
            } else {
                reset()
            }
        } else if start != event.start || end != event.end {
            commit(Pending(event: event, change: .times(start: start, end: end)))
        } else {
            reset()
        }
    }

    /// Het gebaar is afgebroken zonder einde (bijvoorbeeld een app-wissel): alles blijft zoals het was.
    func cancel() {
        if phase == .dragging { reset() }
    }

    // MARK: Vastleggen

    private func commit(_ change: Pending) {
        overCalendars = false
        hoveredCalendar = nil
        if change.event.isRecurring {
            pending = change
            phase = .confirming
        } else {
            perform(change, thisAndFuture: false)
        }
    }

    func perform(_ change: Pending, thisAndFuture: Bool) {
        defer { reset() }
        do {
            switch change.change {
            case .times(let start, let end):
                try CalendarService.shared.reschedule(change.event, start: start, end: end, thisAndFuture: thisAndFuture)
            case .calendar(let target):
                try CalendarService.shared.moveEvent(change.event, toCalendarID: target.id, thisAndFuture: thisAndFuture)
                AppState.shared.announce("\"\(change.event.title)\" staat nu in \(target.title)")
            }
        } catch {
            AppState.shared.announce("Verplaatsen mislukt: \(error.localizedDescription)", seconds: 6)
        }
    }

    /// "Annuleer" bij de vraag over een herhalende afspraak.
    func dismissPending() {
        if phase == .confirming { reset() }
    }

    private func reset() {
        // `targets` blijft staan: de kaart vervaagt nog even met de agenda's erop.
        phase = .idle
        event = nil
        pending = nil
        overCalendars = false
        hoveredCalendar = nil
        isOutside = false
        geometry = nil
    }

    // MARK: Rekenen

    private func isTarget(for event: AgendaEvent) -> (AgendaCalendar) -> Bool {
        let disabled = disabledCalendarIDs
        return { $0.id != event.calendarID && !disabled.contains($0.id) }
    }

    /// De kop boven de tijdlijn (agendafilters en de rij met de dagen), en de kaart zolang die openstaat.
    private func isNearCalendars(_ point: CGPoint) -> Bool {
        guard mode == .move, !targets.isEmpty, filterFrame.width > 1, let geometry else { return false }
        let viewport = geometry.scrollViewport
        let top = filterFrame.minY - 16
        let header = CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, viewport.minY - top))
        if header.contains(point) || filterFrame.insetBy(dx: -48, dy: -22).contains(point) { return true }
        return overCalendars && cardFrame.insetBy(dx: -16, dy: -16).contains(point)
    }

    /// Minuten sinds middernacht op de hoogte `y` in een dagkolom.
    private func minutes(atY y: CGFloat, column key: Date) -> Double? {
        guard let geometry, let frame = geometry.dayFrames[key], geometry.hourHeight > 0 else { return nil }
        return Double(geometry.startHour * 60) + Double((y - frame.minY) / geometry.hourHeight) * 60
    }

    private func minutesFromOrigin(_ date: Date) -> Int {
        Int((date.timeIntervalSince(originDay) / 60).rounded())
    }

    private func date(_ day: Date, _ minutes: Int) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: day) ?? day
    }
}

extension AgendaEvent {
    /// Dezelfde afspraak op een andere tijd (het voorbeeldblok tijdens het slepen).
    func with(start: Date, end: Date) -> AgendaEvent {
        AgendaEvent(id: id, title: title, start: start, end: end, isAllDay: isAllDay, calendarID: calendarID,
                    calendarTitle: calendarTitle, color: color, eventIdentifier: eventIdentifier,
                    isRecurring: isRecurring, location: location, notes: notes, url: url, organizer: organizer,
                    attendees: attendees)
    }
}

// MARK: - Zwevende laag

extension View {
    /// Geeft het frame direct door, bij het verschijnen en bij elke verandering. Niet via een PreferenceKey met
    /// `value = nextValue()`: views zonder eigen waarde leveren daar `.zero` aan, en dat overschreef het echte frame
    /// (zo kwamen het frame van de agendafilters en dat van de concept-afspraak niet aan).
    func reportFrame(in space: CoordinateSpace = .main, _ report: @escaping (CGRect) -> Void) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { report(geo.frame(in: space)) }
                    .onChange(of: geo.frame(in: space)) { _, frame in report(frame) }
            }
        )
    }
}

private struct MoveTileFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Boven de agenda tijdens het slepen van een afspraak: de kaart "Verplaatsen naar" onder de agendafilters, en het
/// opgetilde blok dat daar de muis volgt. Vangt zelf geen muis op; welke agenda je raakt volgt uit de muispositie.
struct EventDragLayer: View {
    let drag: EventDrag

    private let cardWidthSingle: CGFloat = 250

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .main).origin
            ZStack(alignment: .topLeading) {
                if drag.overCalendars {
                    let width = cardWidth
                    card(width: width)
                        .padding(.leading, max(8, min(drag.filterFrame.maxX - origin.x - width, geo.size.width - width - 8)))
                        .padding(.top, drag.filterFrame.maxY - origin.y + 8)
                        .transition(.asymmetric(insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                                                removal: .opacity))
                }
                if drag.isDragging, drag.overCalendars || drag.isOutside, let event = drag.event {
                    LiftedChip(event: event)
                        .position(x: min(drag.pointer.x - origin.x + 104, geo.size.width - 100),
                                  y: drag.pointer.y - origin.y + 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .onPreferenceChange(MoveTileFramesKey.self) { drag.tileFrames = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: drag.overCalendars)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: drag.hoveredCalendar)
    }

    private var columns: Int { drag.targets.count > 6 ? 2 : 1 }
    private var cardWidth: CGFloat { columns == 2 ? cardWidthSingle * 1.7 : cardWidthSingle }

    private func card(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .foregroundStyle(ThingsColor.accent)
                Text("Verplaatsen naar")
                    .font(.werk(size: 14, weight: .semibold))
                    .foregroundStyle(ThingsColor.textPrimary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                ForEach(drag.targets) { tile($0) }
            }
        }
        .padding(12)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ThingsColor.backgroundContent)
                .shadow(color: ThingsColor.cardShadow, radius: 18, x: 0, y: 6)
        )
        .reportFrame { drag.cardFrame = $0 }
    }

    private func tile(_ target: AgendaCalendar) -> some View {
        let isOn = drag.hoveredCalendar == target.id
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(isOn ? Color.white.opacity(0.25) : target.color.opacity(0.16))
                Image(systemName: isOn ? "calendar.badge.checkmark" : "calendar")
                    .font(.werk(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : target.color)
            }
            .frame(width: 26, height: 26)
            Text(target.title)
                .font(.werk(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : ThingsColor.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isOn ? target.color : ThingsColor.backgroundSidebar)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isOn ? target.color : ThingsColor.separator,
                              style: StrokeStyle(lineWidth: isOn ? 2 : 1.5, dash: isOn ? [] : [5, 4]))
        )
        .background(GeometryReader { g in
            Color.clear.preference(key: MoveTileFramesKey.self, value: [target.id: g.frame(in: .main)])
        })
        .scaleEffect(isOn ? 1.04 : 1)
        .shadow(color: isOn ? target.color.opacity(0.4) : .clear, radius: 10, x: 0, y: 3)
        .opacity(drag.hoveredCalendar == nil || isOn ? 1 : 0.5)
    }
}

/// Het opgetilde blok naast de muis, boven de agendafilters of buiten de tijdlijn.
private struct LiftedChip: View {
    let event: AgendaEvent

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(event.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .thingsFont(.tag)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(1)
                Text(DutchDate.range(event.start, event.end))
                    .font(.werk(size: 10))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            Spacer(minLength: 0)
        }
        .frame(width: 180, height: 34)
        .background(event.color.opacity(0.22))
        .background(ThingsColor.backgroundContent)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
        .rotationEffect(.degrees(-2))
    }
}
