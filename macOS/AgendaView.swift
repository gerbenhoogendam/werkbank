import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

// MARK: - Voorkeuren

private struct DayFrameKey: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct AgendaFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct AgendaSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct DraftFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct AgendaConfig: Equatable {
    var hourHeight: CGFloat
    var startHour: Int
    var endHour: Int
}

private let gutterWidth: CGFloat = 46
private let popoverWidth: CGFloat = 272
private let popoverHeightEstimate: CGFloat = 300

// MARK: - Agenda

/// Werkweek- of dagagenda met EventKit, klikbare afspraken en inplannen door een kaart te slepen.
struct AgendaView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(DragCoordinator.self) private var drag

    @AppStorage(SettingsKey.agendaMode) private var agendaMode = "week"
    @AppStorage(SettingsKey.workDays) private var workDaysRaw = "1,2,3,4,5"
    @AppStorage(SettingsKey.startHour) private var startHourSetting = 8
    @AppStorage(SettingsKey.endHour) private var endHourSetting = 18
    @AppStorage(SettingsKey.hiddenCalendars) private var disabledRaw = ""   // uitgezet in Voorkeuren
    @AppStorage(SettingsKey.agendaHidden) private var headerHiddenRaw = ""  // uitgevinkt boven de agenda

    private let service = CalendarService.shared
    private let calendar = Calendar(identifier: .iso8601)

    @State private var offset = 0
    @State private var scrollHour = 8
    @State private var draftFrame: CGRect = .zero
    @State private var agendaSize: CGSize = .zero

    private var startHour: Int { min(max(startHourSetting, 0), 23) }
    private var endHour: Int { min(max(endHourSetting, startHour + 1), 24) }
    private var hours: Int { endHour - startHour }
    private var disabledIDs: Set<String> { AppSettings.parseHidden(disabledRaw) }
    private var headerHiddenIDs: Set<String> { AppSettings.parseHidden(headerHiddenRaw) }
    /// Wat niet getoond wordt: uitgezet in Voorkeuren of uitgevinkt boven de agenda.
    private var hiddenIDs: Set<String> { disabledIDs.union(headerHiddenIDs) }
    private var isDayMode: Bool { agendaMode == "day" }

    var body: some View {
        Group {
            if service.hasAccess {
                agendaBody
            } else {
                CalendarAccessView(service: service)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThingsColor.backgroundContent)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: AgendaFrameKey.self, value: geo.frame(in: .main))
            }
        )
        .onPreferenceChange(AgendaFrameKey.self) { drag.agenda.frame = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            service.refreshStatus()
        }
    }

    // MARK: Dagen

    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        if isDayMode {
            return [calendar.date(byAdding: .day, value: offset, to: today) ?? today]
        }
        let anchor = calendar.date(byAdding: .weekOfYear, value: offset, to: today) ?? today
        let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)) ?? anchor
        return AppSettings.parseWorkDays(workDaysRaw).compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monday) }
    }

    private func dayEnd(_ day: Date) -> Date {
        calendar.date(byAdding: .hour, value: endHour, to: calendar.startOfDay(for: day)) ?? day
    }

    private var title: String {
        let days = days
        guard let first = days.first, let last = days.last else { return "" }
        if isDayMode { return DutchDate.weekdayAndDay(first) }
        return "Week \(DutchDate.isoWeek(first)) · \(DutchDate.short(first)) – \(DutchDate.short(last))"
    }

    // MARK: Inhoud

    private var agendaBody: some View {
        let days = days
        _ = service.revision   // live meebewegen met EKEventStoreChanged
        let rangeStart = days.first ?? .now
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: days.last ?? .now) ?? .now
        let fetched = service.events(from: rangeStart, to: rangeEnd, hiddenCalendarIDs: hiddenIDs)
        let allDay = fetched.filter(\.isAllDay)

        return VStack(spacing: 0) {
            header
            dayHeaderRow(days)
            if !allDay.isEmpty { allDayRow(days, allDay) }
            Rectangle().fill(ThingsColor.separator).frame(height: 1)

            GeometryReader { geo in
                // 8 pt boven, 48 pt onder (ruimte voor het "Eind … Volgende"-label bij een afspraak tot einde dag).
                let hourHeight = max(46, (geo.size.height - 56) / CGFloat(hours))
                let config = AgendaConfig(hourHeight: hourHeight, startHour: startHour, endHour: endHour)

                ScrollViewReader { proxy in
                    ScrollView {
                        HStack(alignment: .top, spacing: 0) {
                            hourGutter(hourHeight)
                            ForEach(days, id: \.self) { day in
                                DayColumn(
                                    day: day,
                                    events: events(on: day, in: fetched),
                                    startHour: startHour,
                                    endHour: endHour,
                                    hourHeight: hourHeight,
                                    dayEnd: dayEnd(day),
                                    onTapEvent: { EventDetailStore.shared.present(.existing($0), day: day) },
                                    onCreate: { start, end in EventDetailStore.shared.present(.new(start: start, end: end), day: day) }
                                )
                            }
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 4)
                        .padding(.bottom, 48)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        scrollHour = min(max(calendar.component(.hour, from: .now) - 1, startHour), max(startHour, endHour - 1))
                        proxy.scrollTo("hour-\(scrollHour)", anchor: .top)
                    }
                    .task(id: drag.isDragging && drag.region == .agenda) {
                        await autoScroll(proxy)
                    }
                }
                .overlay(alignment: .topLeading) { eventDetail(in: geo.size, days: days) }
                .onChange(of: config, initial: true) { _, new in
                    drag.agenda.hourHeight = new.hourHeight
                    drag.agenda.startHour = new.startHour
                    drag.agenda.endHour = new.endHour
                }
                .onChange(of: geo.size, initial: true) { _, _ in
                    drag.agenda.scrollViewport = geo.frame(in: .main)
                }
            }
        }
        .coordinateSpace(.named("agenda"))
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: AgendaSizeKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(AgendaSizeKey.self) { agendaSize = $0 }
        .onPreferenceChange(DayFrameKey.self) { drag.agenda.dayFrames = $0 }
        .onPreferenceChange(DraftFrameKey.self) { draftFrame = $0 }
        // In een eigen view: zo rekent alleen de popover mee bij elke muisbeweging van het concept, niet de hele agenda.
        .overlay(alignment: .topLeading) {
            ScheduleConfirmLayer(draftFrame: draftFrame, agendaSize: agendaSize, onSchedule: schedule)
        }
        .onAppear {
            drag.onAgendaDrop = { card, slot in
                let end = Scheduling.defaultEnd(start: slot.start, dayEnd: dayEnd(slot.day))
                drag.draft = ScheduleDraft(cardID: card.id, todoTitle: card.title, day: slot.day,
                                           start: slot.start, end: end, step: .end)
            }
        }
    }

    /// Detailvenster van een afspraak, over de kolom van die dag (minstens 360 pt breed, binnen de agenda).
    /// De positie volgt uit de indeling zelf (uren-kolom plus even brede dagkolommen), niet uit gemeten frames.
    @ViewBuilder private func eventDetail(in size: CGSize, days: [Date]) -> some View {
        let store = EventDetailStore.shared
        if let presented = store.presented, !days.isEmpty {
            let index = days.firstIndex { calendar.isDate($0, inSameDayAs: presented.day) } ?? 0
            let columnWidth = max(1, (size.width - gutterWidth - 4) / CGFloat(days.count))
            let width = min(max(columnWidth, 360), max(200, size.width - 8))
            let x = max(4, min(gutterWidth + columnWidth * CGFloat(index), size.width - width - 4))
            EventDetailView(target: presented.target) { store.close() }
                .id(presented.id)
                .frame(width: width, height: max(200, size.height - 8))
                .background(ThingsColor.backgroundContent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ThingsColor.separator))
                .shadow(color: ThingsColor.cardShadow, radius: 14, x: 0, y: 5)
                .offset(x: x, y: 4)
        }
    }

    /// Afspraken met tijd die deze kalenderdag raken (ook als ze over middernacht lopen).
    private func events(on day: Date, in all: [AgendaEvent]) -> [AgendaEvent] {
        let startOfDay = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return all.filter { !$0.isAllDay && $0.start < nextDay && $0.end > startOfDay }
    }

    // MARK: Kop

    private var header: some View {
        HStack(spacing: 10) {
            Text(title)
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.textPrimary)
                .monospacedDigit()

            HStack(spacing: 2) {
                navButton("chevron.left", label: "Vorige") { offset -= 1 }
                Button("Vandaag") { offset = 0 }
                    .buttonStyle(.plain)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.accent)
                    .padding(.horizontal, 4)
                navButton("chevron.right", label: "Volgende") { offset += 1 }
            }

            Spacer(minLength: 8)

            // Zichtbare agenda's aan/uit; dezelfde keuze staat in Voorkeuren › Agenda's.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Alleen agenda's die in Voorkeuren aan staan zijn hier te kiezen.
                    ForEach(service.calendars.filter { !disabledIDs.contains($0.id) }) { calendar in
                        calendarChip(calendar)
                    }
                }
            }
            .frame(maxWidth: 460)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func calendarChip(_ cal: AgendaCalendar) -> some View {
        let hidden = headerHiddenIDs.contains(cal.id)
        return Button {
            var ids = headerHiddenIDs
            if hidden { ids.remove(cal.id) } else { ids.insert(cal.id) }
            headerHiddenRaw = ids.sorted().joined(separator: ",")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hidden ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(cal.color)
                Text(cal.title)
                    .thingsFont(.metadata)
                    .foregroundStyle(hidden ? ThingsColor.textTertiary : ThingsColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Agenda \(cal.title)")
        .accessibilityValue(hidden ? "verborgen" : "zichtbaar")
    }

    private func navButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ThingsColor.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dayHeaderRow(_ days: [Date]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth, height: 1)
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDateInToday(day)
                HStack(spacing: 6) {
                    Text(DutchDate.weekdayShort(day))
                        .thingsFont(.upcomingWeekday)
                        .foregroundStyle(isToday ? ThingsColor.accent : ThingsColor.textSecondary)
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isToday ? Color.white : ThingsColor.textPrimary)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Circle().fill(isToday ? ThingsColor.accent : .clear))
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
            }
            Color.clear.frame(width: 4, height: 1)
        }
    }

    private func allDayRow(_ days: [Date], _ allDay: [AgendaEvent]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: gutterWidth, height: 1)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    ForEach(allDay.filter { $0.start < dayEnd(day) && $0.end > calendar.startOfDay(for: day) }) { event in
                        AllDayChip(title: event.title, color: event.color)
                            .contentShape(Rectangle())
                            .onTapGesture { PanelStore.shared.open(.event(event)) }
                    }
                }
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity)
            }
            Color.clear.frame(width: 4, height: 1)
        }
        .padding(.bottom, 4)
    }

    private func hourGutter(_ hourHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textTertiary)
                    .monospacedDigit()
                    .frame(width: gutterWidth - 6, height: hourHeight, alignment: .topTrailing)
                    .offset(y: -6)
                    .id("hour-\(hour)")
            }
        }
        .frame(width: gutterWidth)
    }

    // MARK: Acties

    private func autoScroll(_ proxy: ScrollViewProxy) async {
        guard drag.isDragging, drag.region == .agenda else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(160))
            guard drag.isDragging else { return }
            let y = drag.pointer.y
            let viewport = drag.agenda.scrollViewport
            var hour = scrollHour
            if y < viewport.minY + 36 {
                hour = max(startHour, scrollHour - 1)
            } else if y > viewport.maxY - 36 {
                hour = min(endHour - 1, scrollHour + 1)
            }
            if hour != scrollHour {
                scrollHour = hour
                withAnimation(.linear(duration: 0.16)) { proxy.scrollTo("hour-\(hour)", anchor: .top) }
            }
        }
    }

    private func schedule(_ draft: ScheduleDraft, title: String, calendarID: String) {
        do {
            try service.createEvent(title: title, start: draft.start, end: draft.end, calendarID: calendarID)
            appState.showToast("Ingepland: \(title)")
            drag.draft = nil
        } catch {
            appState.showToast("Inplannen mislukt: \(error.localizedDescription)")
        }
    }
}

// MARK: - Stap 3: popover

/// Bevestigingspopover van een concept-afspraak. Leest zelf `drag.draft`, zodat de agenda eromheen niet bij elke
/// muisbeweging opnieuw wordt opgebouwd.
private struct ScheduleConfirmLayer: View {
    let draftFrame: CGRect
    let agendaSize: CGSize
    let onSchedule: (ScheduleDraft, String, String) -> Void

    @Environment(DragCoordinator.self) private var drag

    var body: some View {
        confirmPopover
            .animation(.easeOut(duration: 0.18), value: drag.draft?.step)
    }

    @ViewBuilder private var confirmPopover: some View {
        if let draft = drag.draft, draft.step == .confirm, draftFrame != .zero {
            ScheduleConfirmView(todoTitle: draft.todoTitle, start: draft.start, end: draft.end,
                                onCancel: { drag.draft = nil },
                                onSchedule: { title, calendarID in onSchedule(draft, title, calendarID) })
                .padding(14)
                .frame(width: popoverWidth)
                .background(
                    RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                        .fill(ThingsColor.backgroundContent)
                        .shadow(color: ThingsColor.cardShadow, radius: 12, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                        .strokeBorder(ThingsColor.separator, lineWidth: 1)
                )
                .offset(popoverOffset)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    /// Rechts van de kolom; links als er rechts geen ruimte is (do/vr). Boven- of onderaan verankerd,
    /// zodat de popover binnen beeld blijft.
    private var popoverOffset: CGSize {
        let fitsRight = draftFrame.maxX + 8 + popoverWidth + 8 <= agendaSize.width
        var x = fitsRight ? draftFrame.maxX + 8 : draftFrame.minX - 8 - popoverWidth
        x = max(8, min(x, agendaSize.width - popoverWidth - 8))

        var y = draftFrame.minY
        if y + popoverHeightEstimate > agendaSize.height - 8 {
            y = draftFrame.maxY - popoverHeightEstimate
        }
        y = max(8, min(y, max(8, agendaSize.height - popoverHeightEstimate - 8)))
        return CGSize(width: x, height: y)
    }
}

// MARK: - Dagkolom

struct DayColumn: View {
    let day: Date
    let events: [AgendaEvent]
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat
    let dayEnd: Date
    let onTapEvent: (AgendaEvent) -> Void
    /// Vasthouden en slepen over een leeg stuk van de kolom: begin- en eindtijd van een nieuwe afspraak.
    var onCreate: ((Date, Date) -> Void)?

    @Environment(DragCoordinator.self) private var drag
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    private let calendar = Calendar.current
    /// Waar een gesleepte mail boven de kolom hangt (voor het stippelblok).
    @State private var mailHoverY: CGFloat?
    /// Het tijdvak dat je nu met de muis opspant.
    @State private var createRange: (start: Date, end: Date)?

    /// Verplaatsing van een herhalende afspraak die nog op de keuze "alleen deze / ook volgende" wacht.
    private struct PendingMove: Identifiable {
        let event: AgendaEvent
        let calendar: AgendaCalendar
        var id: String { event.id }
    }
    @State private var pendingMove: PendingMove?

    // Expliciet, omdat de privé-eigenschappen de automatische init buiten dit bestand verbergen
    // (ook de Maandagenda gebruikt deze kolom).
    init(day: Date, events: [AgendaEvent], startHour: Int, endHour: Int, hourHeight: CGFloat,
         dayEnd: Date, onTapEvent: @escaping (AgendaEvent) -> Void, onCreate: ((Date, Date) -> Void)? = nil) {
        self.day = day
        self.events = events
        self.startHour = startHour
        self.endHour = endHour
        self.hourHeight = hourHeight
        self.dayEnd = dayEnd
        self.onTapEvent = onTapEvent
        self.onCreate = onCreate
    }

    private var totalHeight: CGFloat { hourHeight * CGFloat(endHour - startHour) }

    private func addToTimeList(_ event: AgendaEvent) {
        if TimerService.addCalendarEvent(event, in: modelContext) != nil {
            appState.showToast("Afspraak toegevoegd aan Tijd schrijven")
        } else {
            appState.showToast("Deze afspraak staat al in Tijd schrijven")
        }
    }

    private func minutes(_ date: Date) -> Int {
        // Afspraken van eerdere/latere dagen worden tot deze dag begrensd.
        let startOfDay = calendar.startOfDay(for: day)
        let clamped = min(max(date, startOfDay), calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date)
        return Int(clamped.timeIntervalSince(startOfDay) / 60)
    }

    private func y(_ date: Date) -> CGFloat {
        CGFloat(minutes(date) - startHour * 60) / 60 * hourHeight
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let layout = EventLayout.assign(events.map { ($0.start, $0.end) })

            ZStack(alignment: .topLeading) {
                hourLines
                    .contentShape(Rectangle())
                    .gesture(createGesture)

                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    let slot = layout[index]
                    let top = max(0, y(event.start))
                    let bottom = min(totalHeight, y(event.end))
                    let laneWidth = width / CGFloat(slot.laneCount)
                    if bottom > top {
                        EventBlock(event: event)
                            .frame(width: max(0, laneWidth - 3), height: max(18, bottom - top - 1))
                            .offset(x: laneWidth * CGFloat(slot.lane) + 1.5, y: top)
                            // Klikken opent de details; "Tijd schrijven" zit in het contextmenu en in het detailpaneel.
                            .onTapGesture { onTapEvent(event) }
                            .contextMenu {
                                Button("Toevoegen aan Tijd schrijven") { addToTimeList(event) }
                                moveMenu(for: event)
                            }
                    }
                }

                if let slot = drag.agendaSlot, slot.day == day {
                    slotPreview(slot, width: width)
                }

                if let range = pendingRange {
                    let top = y(range.start)
                    let bottom = y(range.end)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(ThingsColor.accent.opacity(0.22))
                        .overlay(alignment: .topLeading) {
                            Text("\(DutchDate.time(range.start))–\(DutchDate.time(range.end))")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(ThingsColor.accent)
                                .padding(4)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(ThingsColor.accent.opacity(0.6)))
                        .frame(width: max(0, width - 4), height: max(8, bottom - top))
                        .offset(x: 2, y: top)
                        .allowsHitTesting(false)
                }

                if let y = mailHoverY {
                    slotPreview(AgendaSlot(day: day, start: slotStart(forY: y)), width: width)
                }

                if let draft = drag.draft, draft.day == day {
                    DraftBlock(draft: draft, hourHeight: hourHeight, dayEnd: dayEnd)
                        .frame(width: max(0, width - 4), height: draftHeight(draft))
                        .offset(x: 2, y: y(draft.start))
                }

                if calendar.isDateInToday(day) {
                    nowLine(width: width)
                }
            }
            .frame(width: width, height: totalHeight, alignment: .topLeading)
            .animation(.easeOut(duration: 0.18), value: drag.draft?.step)
            .onDrop(of: [.gmailMessage], delegate: MailDropDelegate(hoverY: $mailHoverY, perform: handleMailDrop))
            .background(
                Color.clear.preference(key: DayFrameKey.self, value: [day: geo.frame(in: .main)])
            )
        }
        .frame(height: totalHeight)
        .overlay(alignment: .leading) {
            Rectangle().fill(ThingsColor.separator).frame(width: 1)
        }
        .confirmationDialog(
            "Herhalende afspraak",
            isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }),
            titleVisibility: .visible,
            presenting: pendingMove
        ) { move in
            Button("Alleen deze afspraak") { perform(move, thisAndFuture: false) }
            Button("Deze en alle volgende") { perform(move, thisAndFuture: true) }
            Button("Annuleer", role: .cancel) {}
        } message: { move in
            Text("\"\(move.event.title)\" verplaatsen naar \(move.calendar.title).")
        }
    }

    // MARK: Een afspraak opspannen

    /// Het tijdvak dat nu getoond wordt: wat je opspant, of de nieuwe afspraak waarvan het formulier openstaat.
    private var pendingRange: (start: Date, end: Date)? {
        if let createRange { return createRange }
        if onCreate != nil, let presented = EventDetailStore.shared.presented,
           calendar.isDate(presented.day, inSameDayAs: day), case .new(let start, let end) = presented.target {
            return (start, end)
        }
        return nil
    }

    private func time(forY y: CGFloat, roundUp: Bool) -> Date {
        let raw = Double(startHour * 60) + Double(y / hourHeight) * 60
        let snapped = roundUp ? (raw / 15).rounded(.up) * 15 : (raw / 15).rounded(.down) * 15
        let clamped = min(max(snapped, Double(startHour * 60)), Double(endHour * 60))
        return calendar.startOfDay(for: day).addingTimeInterval(clamped * 60)
    }

    private func range(from a: CGFloat, to b: CGFloat) -> (start: Date, end: Date) {
        let start = time(forY: min(a, b), roundUp: false)
        var end = time(forY: max(a, b), roundUp: true)
        if end <= start { end = min(start.addingTimeInterval(15 * 60), dayEndLimit) }
        return (start, end)
    }

    private var dayEndLimit: Date {
        calendar.startOfDay(for: day).addingTimeInterval(Double(endHour * 60) * 60)
    }

    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard onCreate != nil else { return }
                createRange = range(from: value.startLocation.y, to: value.location.y)
            }
            .onEnded { value in
                defer { createRange = nil }
                guard let onCreate else { return }
                let result = range(from: value.startLocation.y, to: value.location.y)
                guard result.end > result.start else { return }
                onCreate(result.start, result.end)
            }
    }

    // MARK: Een mail op de agenda laten vallen

    /// Begin van het kwartier onder de muis, binnen de zichtbare uren.
    private func slotStart(forY y: CGFloat) -> Date {
        let raw = Double(startHour * 60) + Double(y / hourHeight) * 60
        let snapped = (raw / 15).rounded(.down) * 15
        let clamped = min(max(snapped, Double(startHour * 60)), Double(endHour * 60 - 15))
        return calendar.startOfDay(for: day).addingTimeInterval(clamped * 60)
    }

    /// De mail wordt een kaart in de Inbox (de mail blijft in Gmail staan) en loopt dan door dezelfde stappen als een
    /// kaart die je op de agenda sleept: eindtijd kiezen en bevestigen.
    private func handleMailDrop(y: CGFloat, providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.gmailMessage.identifier) }) else {
            return false
        }
        let start = slotStart(forY: y)
        let end = Scheduling.defaultEnd(start: start, dayEnd: dayEnd)
        let day = day
        provider.loadDataRepresentation(forTypeIdentifier: UTType.gmailMessage.identifier) { data, _ in
            guard let data, let payload = try? JSONDecoder().decode(GmailDragPayload.self, from: data) else { return }
            Task { @MainActor in
                guard let card = await GmailSession.shared.importDropped(payload, column: .inbox, archive: false,
                                                                         context: modelContext, appState: appState) else { return }
                drag.draft = ScheduleDraft(cardID: card.id, todoTitle: card.title, day: day,
                                           start: start, end: end, step: .end)
            }
        }
        return true
    }

    // MARK: Verplaatsen naar een andere agenda

    /// Alleen agenda's waarin je mag schrijven, behalve de agenda waar de afspraak al in staat.
    @ViewBuilder private func moveMenu(for event: AgendaEvent) -> some View {
        let targets = CalendarService.shared.writableCalendars.filter { $0.id != event.calendarID }
        if !targets.isEmpty {
            Menu("Verplaats naar agenda") {
                ForEach(targets) { target in
                    Button(target.title) {
                        if event.isRecurring {
                            pendingMove = PendingMove(event: event, calendar: target)
                        } else {
                            perform(PendingMove(event: event, calendar: target), thisAndFuture: false)
                        }
                    }
                }
            }
        }
    }

    private func perform(_ move: PendingMove, thisAndFuture: Bool) {
        do {
            try CalendarService.shared.moveEvent(move.event, toCalendarID: move.calendar.id, thisAndFuture: thisAndFuture)
            appState.showToast("\"\(move.event.title)\" staat nu in \(move.calendar.title)")
        } catch {
            appState.showToast("Verplaatsen mislukt: \(error.localizedDescription)", seconds: 6)
        }
    }

    private func draftHeight(_ draft: ScheduleDraft) -> CGFloat {
        max(CGFloat(draft.end.timeIntervalSince(draft.start) / 3600) * hourHeight, 12)
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { _ in
                VStack(spacing: 0) {
                    Rectangle().fill(ThingsColor.separator).frame(height: 1)
                    Spacer(minLength: 0)
                }
                .frame(height: hourHeight)
            }
        }
        .allowsHitTesting(false)
    }

    /// Gestippeld voorbeeldblok van 1 uur terwijl je een kaart boven de dagkolom houdt.
    private func slotPreview(_ slot: AgendaSlot, width: CGFloat) -> some View {
        let end = slot.start.addingTimeInterval(3600)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(ThingsColor.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ThingsColor.accent.opacity(0.08)))
            .overlay(alignment: .topLeading) {
                Text(DutchDate.range(slot.start, end))
                    .thingsFont(.tag)
                    .foregroundStyle(ThingsColor.accent)
                    .monospacedDigit()
                    .padding(5)
            }
            .frame(width: max(0, width - 4), height: hourHeight)
            .offset(x: 2, y: y(slot.start))
            .allowsHitTesting(false)
    }

    private func nowLine(width: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let position = y(timeline.date)
            if position >= 0 && position <= totalHeight {
                ZStack(alignment: .leading) {
                    Rectangle().fill(ThingsColor.deadline).frame(height: 1.5)
                    Circle().fill(ThingsColor.deadline).frame(width: 7, height: 7).offset(x: -3.5)
                }
                .frame(width: width)
                .offset(y: position - 3.5)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Afspraak

private struct EventBlock: View {
    let event: AgendaEvent

    @AppStorage(SettingsKey.eventOpacity) private var opacity = EventStyle.defaultOpacity
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Korter dan 1 uur: alleen titel. Langer: titel + tijd.
        let isShort = event.end.timeIntervalSince(event.start) < 3600
        let text = EventStyle.textColors(on: event.color, opacity: opacity, dark: colorScheme == .dark)
        HStack(spacing: 0) {
            Rectangle().fill(event.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .thingsFont(.tag)
                    .foregroundStyle(text.primary)
                    .lineLimit(isShort ? 1 : 2)
                if !isShort {
                    Text(DutchDate.range(event.start, event.end))
                        .font(.system(size: 10))
                        .foregroundStyle(text.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(event.color.opacity(opacity))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .help("\(event.title)\n\(DutchDate.range(event.start, event.end))")
        .accessibilityLabel("\(event.title), \(DutchDate.range(event.start, event.end))")
        .accessibilityHint("Opent de details van de afspraak")
    }
}

// MARK: - Concept-afspraak (stap 2)

private struct DraftBlock: View {
    let draft: ScheduleDraft
    let hourHeight: CGFloat
    let dayEnd: Date

    @Environment(DragCoordinator.self) private var drag
    @State private var gripBase: Date?

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(ThingsColor.accent.opacity(0.14))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(ThingsColor.accent, lineWidth: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("GH: \(draft.todoTitle)")
                    .thingsFont(.tag)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(2)
                Text(DutchDate.range(draft.start, draft.end))
                    .font(.system(size: 10))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .monospacedDigit()
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Sleepgreep voor de eindtijd (stappen van 15 minuten).
            Capsule()
                .fill(ThingsColor.accent)
                .frame(width: 30, height: 5)
                .padding(.bottom, 3)
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(gripGesture)
                .onHover { inside in
                    if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
                }
                .accessibilityLabel("Eindtijd aanpassen")
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: DraftFrameKey.self, value: geo.frame(in: .named("agenda")))
            }
        )
        .overlay(alignment: .bottomLeading) {
            if draft.step == .end {
                HStack(spacing: 6) {
                    Text("Eind \(DutchDate.time(draft.end))")
                        .thingsFont(.tag)
                        .foregroundStyle(ThingsColor.textPrimary)
                        .monospacedDigit()
                    Button("Volgende") { drag.draft?.step = .confirm }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(ThingsColor.backgroundContent)
                        .shadow(color: ThingsColor.cardShadow, radius: 4, y: 1)
                )
                .fixedSize()
                .offset(y: 34)
            }
        }
        .zIndex(2)
    }

    private var gripGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .main)
            .onChanged { value in
                if gripBase == nil {
                    gripBase = draft.end
                    drag.draft?.step = .end
                }
                guard let base = gripBase else { return }
                let baseMinutes = Int(base.timeIntervalSince(draft.start) / 60)
                let deltaMinutes = Int((value.translation.height / hourHeight * 60).rounded())
                drag.draft?.end = Scheduling.clampEnd(start: draft.start,
                                                      proposedMinutesAfterStart: baseMinutes + deltaMinutes,
                                                      dayEnd: dayEnd)
            }
            .onEnded { _ in
                gripBase = nil
                drag.draft?.step = .confirm
            }
    }
}

/// Opvangen van een mail boven een dagkolom, met de hoogte van de muis voor het stippelblok.
private struct MailDropDelegate: DropDelegate {
    @Binding var hoverY: CGFloat?
    let perform: (CGFloat, [NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.gmailMessage]) }
    func dropEntered(info: DropInfo) { hoverY = info.location.y }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        hoverY = info.location.y
        return DropProposal(operation: .copy)
    }
    func dropExited(info: DropInfo) { hoverY = nil }
    func performDrop(info: DropInfo) -> Bool {
        hoverY = nil
        return perform(info.location.y, info.itemProviders(for: [.gmailMessage]))
    }
}
