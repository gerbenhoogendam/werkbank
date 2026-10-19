import AppKit
import SwiftData
import SwiftUI
import WerkbankCore

/// Maandagenda: vier volledige werkweken over het hele venster (huidige week linksboven, daarna rechtsboven,
/// linksonder, rechtsonder). Opent als een vouwblad: de pagina's klappen een voor een open.
struct MonthAgendaView: View {
    @Binding var isOpen: Bool
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @AppStorage(SettingsKey.workDays) private var workDaysRaw = "1,2,3,4,5"
    @AppStorage(SettingsKey.startHour) private var startHourSetting = 8
    @AppStorage(SettingsKey.endHour) private var endHourSetting = 18
    @AppStorage(SettingsKey.hiddenCalendars) private var disabledRaw = ""
    @AppStorage(SettingsKey.agendaHidden) private var headerHiddenRaw = ""

    private let service = CalendarService.shared
    private let calendar = Calendar(identifier: .iso8601)

    @State private var weekOffset = 0

    private var startHour: Int { min(max(startHourSetting, 0), 23) }
    private var endHour: Int { min(max(endHourSetting, startHour + 1), 24) }
    private var hiddenIDs: Set<String> { AppSettings.parseHidden(disabledRaw).union(AppSettings.parseHidden(headerHiddenRaw)) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ThingsColor.backgroundSidebar)
                .opacity(isOpen ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: isOpen)

            VStack(spacing: 0) {
                topBar
                    .opacity(isOpen ? 1 : 0)
                    .animation(.easeOut(duration: 0.12).delay(isOpen ? 0.15 : 0), value: isOpen)
                if service.hasAccess {
                    pages
                } else {
                    CalendarAccessView(service: service)
                }
            }
        }
        .onAppear {
            // Eerst dichtgevouwen tonen, dan in de volgende ronde openklappen, zodat de animatie echt loopt.
            DispatchQueue.main.async { isOpen = true }
        }
    }

    // MARK: Weken

    private func monday(forWeek offset: Int) -> Date {
        let today = calendar.startOfDay(for: .now)
        let anchor = calendar.date(byAdding: .weekOfYear, value: offset, to: today) ?? today
        return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)) ?? anchor
    }

    private func workDays(of monday: Date) -> [Date] {
        AppSettings.parseWorkDays(workDaysRaw).compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monday) }
    }

    private var rangeTitle: String {
        let first = monday(forWeek: weekOffset)
        let last = monday(forWeek: weekOffset + 3)
        return "Week \(DutchDate.isoWeek(first)) – \(DutchDate.isoWeek(last))"
    }

    // MARK: Kop

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(ThingsColor.accent)
            Text("Maandagenda")
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.textPrimary)
            Text(rangeTitle)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
                .monospacedDigit()

            HStack(spacing: 2) {
                navButton("chevron.left", label: "Vorige week") { weekOffset -= 1 }
                Button("Vandaag") { weekOffset = 0 }
                    .buttonStyle(.plain)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.accent)
                    .padding(.horizontal, 4)
                navButton("chevron.right", label: "Volgende week") { weekOffset += 1 }
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(ThingsColor.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Maandagenda sluiten")
            .accessibilityLabel("Maandagenda sluiten")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    // MARK: Pagina's

    private var pages: some View {
        let mondays = (0..<4).map { monday(forWeek: weekOffset + $0) }
        let rangeStart = mondays[0]
        let rangeEnd = calendar.date(byAdding: .day, value: 28, to: rangeStart) ?? rangeStart
        _ = service.revision   // live meebewegen met EKEventStoreChanged
        let fetched = service.events(from: rangeStart, to: rangeEnd, hiddenCalendarIDs: hiddenIDs)

        return GeometryReader { geo in
            let gap: CGFloat = 12
            let width = max(0, (geo.size.width - gap * 3) / 2)
            let height = max(0, (geo.size.height - gap * 3) / 2)

            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    page(mondays[0], fetched, width, height)
                        .opacity(isOpen ? 1 : 0)
                        .scaleEffect(isOpen ? 1 : 0.92, anchor: .topLeading)
                        .animation(.easeOut(duration: 0.2).delay(isOpen ? 0.025 : 0.25), value: isOpen)
                    // Rechtsboven klapt open om de linkerrand (de rug), onderaan om de bovenrand.
                    page(mondays[1], fetched, width, height)
                        .modifier(FoldEffect(angle: isOpen ? 0 : -90, axis: (0, 1, 0), anchor: .leading))
                        .animation(.easeInOut(duration: 0.275).delay(isOpen ? 0.1 : 0.15), value: isOpen)
                }
                HStack(spacing: gap) {
                    page(mondays[2], fetched, width, height)
                        .modifier(FoldEffect(angle: isOpen ? 0 : 90, axis: (1, 0, 0), anchor: .top))
                        .animation(.easeInOut(duration: 0.275).delay(isOpen ? 0.275 : 0.05), value: isOpen)
                    page(mondays[3], fetched, width, height)
                        .modifier(FoldEffect(angle: isOpen ? 0 : 90, axis: (1, 0, 0), anchor: .top))
                        .animation(.easeInOut(duration: 0.275).delay(isOpen ? 0.35 : 0), value: isOpen)
                }
            }
            .padding(.horizontal, gap)
            .padding(.bottom, gap)
        }
    }

    private func page(_ monday: Date, _ all: [AgendaEvent], _ width: CGFloat, _ height: CGFloat) -> some View {
        let days = workDays(of: monday)
        let start = calendar.startOfDay(for: monday)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let events = all.filter { $0.start < end && $0.end > start }
        return WeekPage(days: days, events: events, startHour: startHour, endHour: endHour, onTapEvent: addToTimeList)
            .frame(width: width, height: height)
    }

    private func addToTimeList(_ event: AgendaEvent) {
        if TimerService.addCalendarEvent(event, in: context) != nil {
            appState.showToast("Afspraak toegevoegd aan Tijd schrijven")
        } else {
            appState.showToast("Deze afspraak staat al in Tijd schrijven")
        }
    }
}

// MARK: - Vouweffect

/// Klapt een pagina om een rand open: 0° is open, ±90° staat zij-aan (onzichtbaar). Tijdens het openen
/// wordt de pagina donkerder, alsof er schaduw op valt.
private struct FoldEffect: ViewModifier, Animatable {
    var angle: Double
    let axis: (x: CGFloat, y: CGFloat, z: CGFloat)
    let anchor: UnitPoint

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .overlay(Color.black.opacity(0.28 * min(abs(angle) / 90, 1)).allowsHitTesting(false))
            .opacity(abs(angle) >= 90 ? 0 : 1)
            .rotation3DEffect(.degrees(angle), axis: axis, anchor: anchor, anchorZ: 0, perspective: 0.35)
    }
}

// MARK: - Weekpagina

/// Eén werkweek op een pagina: kop, dagkoppen en de uren zonder scrollen (de uren passen in de hoogte).
private struct WeekPage: View {
    let days: [Date]
    let events: [AgendaEvent]
    let startHour: Int
    let endHour: Int
    let onTapEvent: (AgendaEvent) -> Void

    private let calendar = Calendar(identifier: .iso8601)
    private let gutter: CGFloat = 34
    private let corner: CGFloat = 12

    private var hasToday: Bool { days.contains { calendar.isDateInToday($0) } }

    private var title: String {
        guard let first = days.first, let last = days.last else { return "" }
        return "Week \(DutchDate.isoWeek(first)) · \(DutchDate.short(first)) – \(DutchDate.short(last))"
    }

    var body: some View {
        let allDay = events.filter(\.isAllDay)
        VStack(spacing: 0) {
            Text(title)
                .thingsFont(.heading)
                .foregroundStyle(hasToday ? ThingsColor.accent : ThingsColor.textPrimary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            dayHeaders
            if !allDay.isEmpty { allDayRow(allDay) }
            Rectangle().fill(ThingsColor.separator).frame(height: 1)

            GeometryReader { geo in
                let hours = max(1, endHour - startHour)
                let hourHeight = max(12, geo.size.height / CGFloat(hours))
                HStack(alignment: .top, spacing: 0) {
                    hourGutter(hourHeight)
                    ForEach(days, id: \.self) { day in
                        DayColumn(day: day,
                                  events: timed(on: day),
                                  startHour: startHour,
                                  endHour: endHour,
                                  hourHeight: hourHeight,
                                  dayEnd: dayEnd(day),
                                  onTapEvent: onTapEvent)
                    }
                }
                .padding(.trailing, 2)
            }
        }
        .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(ThingsColor.backgroundContent))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(ThingsColor.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: ThingsColor.cardShadow, radius: 8, x: 0, y: 2)
    }

    private func dayEnd(_ day: Date) -> Date {
        calendar.date(byAdding: .hour, value: endHour, to: calendar.startOfDay(for: day)) ?? day
    }

    private func timed(on day: Date) -> [AgendaEvent] {
        let startOfDay = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return events.filter { !$0.isAllDay && $0.start < nextDay && $0.end > startOfDay }
    }

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDateInToday(day)
                HStack(spacing: 5) {
                    Text(DutchDate.weekdayShort(day))
                        .thingsFont(.upcomingWeekday)
                        .foregroundStyle(isToday ? ThingsColor.accent : ThingsColor.textSecondary)
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isToday ? Color.white : ThingsColor.textPrimary)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Circle().fill(isToday ? ThingsColor.accent : .clear))
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            }
            Color.clear.frame(width: 2, height: 1)
        }
    }

    private func allDayRow(_ allDay: [AgendaEvent]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    ForEach(allDay.filter { $0.start < dayEnd(day) && $0.end > calendar.startOfDay(for: day) }) { event in
                        Text(event.title)
                            .thingsFont(.tag)
                            .foregroundStyle(ThingsColor.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(event.color.opacity(0.25)))
                    }
                }
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity)
            }
            Color.clear.frame(width: 2, height: 1)
        }
        .padding(.bottom, 3)
    }

    /// Uurlabels; bij weinig hoogte om het andere uur, zodat ze elkaar niet raken.
    private func hourGutter(_ hourHeight: CGFloat) -> some View {
        let step = hourHeight < 22 ? 2 : 1
        return VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                Text((hour - startHour) % step == 0 ? String(format: "%02d", hour) : "")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textTertiary)
                    .monospacedDigit()
                    .frame(width: gutter - 6, height: hourHeight, alignment: .topTrailing)
                    .offset(y: -6)
            }
        }
        .frame(width: gutter)
    }
}
