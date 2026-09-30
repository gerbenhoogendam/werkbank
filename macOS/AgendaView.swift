import AppKit
import SwiftData
import SwiftUI
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
    @AppStorage(SettingsKey.hiddenCalendars) private var hiddenRaw = ""

    private let service = CalendarService.shared
    private let calendar = Calendar(identifier: .iso8601)

    @State private var offset = 0
    @State private var scrollHour = 8
    @State private var draftFrame: CGRect = .zero
    @State private var agendaSize: CGSize = .zero

    private var startHour: Int { min(max(startHourSetting, 0), 23) }
    private var endHour: Int { min(max(endHourSetting, startHour + 1), 24) }
    private var hours: Int { endHour - startHour }
    private var hiddenIDs: Set<String> { AppSettings.parseHidden(hiddenRaw) }
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
                                    onTapEvent: addToTimeList
                                )
                            }
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 4)
                        .padding(.bottom, 48)
                    }
                    .scrollIndicators(.automatic)
                    .onAppear {
                        scrollHour = min(max(calendar.component(.hour, from: .now) - 1, startHour), max(startHour, endHour - 1))
                        proxy.scrollTo("hour-\(scrollHour)", anchor: .top)
                    }
                    .task(id: drag.isDragging && drag.region == .agenda) {
                        await autoScroll(proxy)
                    }
                }
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
        .overlay(alignment: .topLeading) { confirmPopover }
        .animation(.easeOut(duration: 0.18), value: drag.draft?.step)
        .onAppear {
            drag.onAgendaDrop = { card, slot in
                let end = Scheduling.defaultEnd(start: slot.start, dayEnd: dayEnd(slot.day))
                drag.draft = ScheduleDraft(cardID: card.id, todoTitle: card.title, day: slot.day,
                                           start: slot.start, end: end, step: .end)
            }
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(service.calendars) { calendar in
                        calendarChip(calendar)
                    }
                }
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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

    private func calendarChip(_ cal: AgendaCalendar) -> some View {
        let hidden = hiddenIDs.contains(cal.id)
        return Button {
            var ids = hiddenIDs
            if hidden { ids.remove(cal.id) } else { ids.insert(cal.id) }
            hiddenRaw = ids.sorted().joined(separator: ",")
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
                        Text(event.title)
                            .thingsFont(.tag)
                            .foregroundStyle(ThingsColor.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(event.color.opacity(0.25)))
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

    private func addToTimeList(_ event: AgendaEvent) {
        if TimerService.addCalendarEvent(event, in: context) != nil {
            appState.showToast("Afspraak toegevoegd aan Tijd schrijven")
        } else {
            appState.showToast("Deze afspraak staat al in Tijd schrijven")
        }
    }

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

    // MARK: Stap 3: popover

    @ViewBuilder private var confirmPopover: some View {
        if let draft = drag.draft, draft.step == .confirm, draftFrame != .zero {
            ScheduleConfirmView(todoTitle: draft.todoTitle, start: draft.start, end: draft.end,
                                onCancel: { drag.draft = nil },
                                onSchedule: { title, calendarID in schedule(draft, title: title, calendarID: calendarID) })
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

private struct DayColumn: View {
    let day: Date
    let events: [AgendaEvent]
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat
    let dayEnd: Date
    let onTapEvent: (AgendaEvent) -> Void

    @Environment(DragCoordinator.self) private var drag
    private let calendar = Calendar.current

    private var totalHeight: CGFloat { hourHeight * CGFloat(endHour - startHour) }

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

                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    let slot = layout[index]
                    let top = max(0, y(event.start))
                    let bottom = min(totalHeight, y(event.end))
                    let laneWidth = width / CGFloat(slot.laneCount)
                    if bottom > top {
                        EventBlock(event: event)
                            .frame(width: max(0, laneWidth - 3), height: max(18, bottom - top - 1))
                            .offset(x: laneWidth * CGFloat(slot.lane) + 1.5, y: top)
                            .onTapGesture { onTapEvent(event) }
                    }
                }

                if let slot = drag.agendaSlot, slot.day == day {
                    slotPreview(slot, width: width)
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
            .background(
                Color.clear.preference(key: DayFrameKey.self, value: [day: geo.frame(in: .main)])
            )
        }
        .frame(height: totalHeight)
        .overlay(alignment: .leading) {
            Rectangle().fill(ThingsColor.separator).frame(width: 1)
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

    var body: some View {
        // Korter dan 1 uur: alleen titel. Langer: titel + tijd.
        let isShort = event.end.timeIntervalSince(event.start) < 3600
        HStack(spacing: 0) {
            Rectangle().fill(event.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .thingsFont(.tag)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(isShort ? 1 : 2)
                if !isShort {
                    Text(DutchDate.range(event.start, event.end))
                        .font(.system(size: 10))
                        .foregroundStyle(ThingsColor.textSecondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(event.color.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .help("\(event.title)\n\(DutchDate.range(event.start, event.end))\nKlik om toe te voegen aan Tijd schrijven")
        .accessibilityLabel("\(event.title), \(DutchDate.range(event.start, event.end))")
        .accessibilityHint("Voegt de afspraak toe aan Tijd schrijven")
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
