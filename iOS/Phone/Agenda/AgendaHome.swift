import SwiftUI

/// De agenda op de iPhone: dag (werkweekstrook en uurgrid), werkweek in vijf kolommen, maand of de lijst van de
/// komende twee weken.
/// Afspraken die met "GH" beginnen staan niet in het grid maar compact bovenaan.
struct AgendaHome: View {
    private let service = CalendarService.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: AgendaMode = .dag
    @State private var selected = AgendaDates.startOfDay(.now)
    @State private var openEvent: AgendaEvent?
    @State private var creating = false
    /// "Tijd schrijven" gekozen: na het sluiten van het blad de tijdinvoer openen (twee bladen tegelijk kan niet).
    @State private var writeTimeAfterClose = false

    private var modeItems: [PhSegmented<AgendaMode>.Item] {
        [PhSegmented<AgendaMode>.Item(value: .dag, title: "Dag"),
         PhSegmented<AgendaMode>.Item(value: .week, title: "Week"),
         PhSegmented<AgendaMode>.Item(value: .maand, title: "Maand")]
    }

    var body: some View {
        let _ = service.revision   // live meebewegen met EKEventStoreChanged
        VStack(alignment: .leading, spacing: 10) {
            header
            controls
            if service.hasAccess {
                content
            } else {
                AgendaAccessCard(service: service)
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .phScreen()
        .onAppear { service.refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { service.refreshStatus() }
        }
        .sheet(item: $openEvent, onDismiss: {
            guard writeTimeAfterClose else { return }
            writeTimeAfterClose = false
            AppState.shared.timeEntry = .choose
        }) { event in
            AgendaEventSheet(event: event) {
                writeTimeAfterClose = true
                openEvent = nil
            }
        }
        .sheet(isPresented: $creating) {
            AgendaEventEditor(day: selected)
        }
    }

    // MARK: Kop

    private var eyebrow: String {
        switch mode {
        case .dag:
            return "WEEK \(AgendaDates.week(selected)) · \(AgendaDates.monthName(selected))"
        case .week:
            return AgendaDates.workweekRange(selected)
        case .maand:
            return "WEEK \(AgendaDates.week(selected)) · \(AgendaDates.calendar.component(.year, from: selected))"
        case .lijst:
            return "KOMEND · \(upcoming.filter { !$0.isPersonal }.count) AFSPRAKEN"
        }
    }

    private var title: String {
        switch mode {
        case .dag: return AgendaDates.dayTitle(selected)
        case .week: return "WEEK \(AgendaDates.week(selected))"
        case .maand: return AgendaDates.monthName(selected)
        case .lijst: return "Agenda"
        }
    }

    private var header: some View {
        PhHeader(eyebrow: eyebrow, title: title, size: 46) {
            Button {
                creating = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(PhIconButtonStyle())
            .disabled(!service.hasAccess)
            .accessibilityLabel("Nieuwe afspraak")
        }
        .contentShape(Rectangle())
        // Op de titel tikken: terug naar vandaag.
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { selected = AgendaDates.startOfDay(.now) }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            PhSegmented(items: modeItems, selection: $mode)
            if mode != .lijst {
                Button {
                    shift(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(PhIconButtonStyle())
                .accessibilityLabel("Vorige")
                Button {
                    shift(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(PhIconButtonStyle())
                .accessibilityLabel("Volgende")
            }
            listButton
        }
        .padding(.horizontal, 16)
    }

    /// De lijst: inkt met een limoen icoon als hij gekozen is (ingedrukt), anders wit.
    private var listButton: some View {
        let on = mode == .lijst
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { mode = on ? .dag : .lijst }
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on ? Ph.lime : Ph.ink)
                .frame(width: 44, height: 44)
                .background {
                    if on {
                        Rectangle().fill(Ph.ink.shadow(.inner(color: .black.opacity(0.4), radius: 1.5, y: 2)))
                    } else {
                        Rectangle().fill(Ph.card)
                            .shadow(color: Ph.ink.opacity(0.08), radius: 0, y: 1)
                            .shadow(color: Ph.ink.opacity(0.06), radius: 3, y: 2)
                    }
                }
                .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lijst")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Dag: vorige of volgende werkdag; week: een week; maand: een maand.
    private func shift(_ step: Int) {
        withAnimation(.easeOut(duration: 0.15)) {
            switch mode {
            case .dag: selected = AgendaDates.workday(after: selected, by: step)
            case .week: selected = AgendaDates.adding(days: 7 * step, to: selected)
            case .maand: selected = AgendaDates.firstOfMonth(AgendaDates.addingMonths(step, to: selected))
            case .lijst: break
            }
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.5 else { return }
                shift(dx < 0 ? 1 : -1)
            }
    }

    // MARK: Inhoud

    private func open(_ event: AgendaEvent) { openEvent = event }

    private func fetch(from start: Date, to end: Date) -> [AgendaEvent] {
        service.events(from: start, to: end, hiddenCalendarIDs: AppSettings.hiddenCalendarIDs, prefetchNeighbors: true)
    }

    /// Vandaag tot en met de komende veertien dagen (de lijst).
    private var upcoming: [AgendaEvent] {
        let today = AgendaDates.startOfDay(.now)
        return service.events(from: today, to: AgendaDates.adding(days: AgendaListView.dayCount, to: today),
                              hiddenCalendarIDs: AppSettings.hiddenCalendarIDs)
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .dag:
            let monday = AgendaDates.monday(of: selected)
            let weekEvents = fetch(from: monday, to: AgendaDates.adding(days: 7, to: monday))
            let dayEvents = weekEvents.filter { $0.overlaps(day: selected) }
            AgendaDayStrip(days: AgendaDates.workdays(of: selected), selected: $selected,
                           events: weekEvents.filter { !$0.isPersonal })
            AgendaPersonalBand(events: dayEvents.filter { $0.isPersonal || $0.isAllDay }, onOpen: open)
            AgendaDayGrid(day: selected, events: dayEvents.filter { !$0.isPersonal && !$0.isAllDay }, onOpen: open)
                .id(selected)
                .simultaneousGesture(swipe)
        case .week:
            let days = AgendaDates.workdays(of: selected)
            let monday = AgendaDates.monday(of: selected)
            let weekEvents = fetch(from: monday, to: AgendaDates.adding(days: 7, to: monday))
                .filter { event in days.contains { event.overlaps(day: $0) } }
            AgendaPersonalBand(events: weekEvents.filter { $0.isPersonal || $0.isAllDay }, onOpen: open)
            AgendaWeekGrid(days: days, events: weekEvents.filter { !$0.isPersonal && !$0.isAllDay },
                           onOpen: open) { day in
                withAnimation(.easeOut(duration: 0.15)) {
                    selected = day
                    mode = .dag
                }
            }
            .id(monday)
            .simultaneousGesture(swipe)
        case .maand:
            let first = AgendaDates.firstOfMonth(selected)
            let gridDays = monthGrid(first)
            let start = gridDays.first ?? first
            let end = AgendaDates.adding(days: 1, to: gridDays.last ?? first)
            let monthEvents = fetch(from: start, to: end)
            AgendaPersonalBand(events: monthEvents.filter { $0.isPersonal && $0.overlaps(day: selected) },
                               onOpen: open)
            AgendaMonthView(selected: $selected, gridDays: gridDays,
                            events: monthEvents.filter { !$0.isPersonal }, onOpen: open)
                .simultaneousGesture(swipe)
        case .lijst:
            AgendaListView(events: upcoming, onOpen: open)
        }
    }

    /// Hele weken van maandag tot en met zondag rond de maand.
    private func monthGrid(_ first: Date) -> [Date] {
        let calendar = AgendaDates.calendar
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let last = AgendaDates.adding(days: count - 1, to: first)
        let gridStart = AgendaDates.monday(of: first)
        let gridEnd = AgendaDates.adding(days: 7, to: AgendaDates.monday(of: last))
        let days = calendar.dateComponents([.day], from: gridStart, to: gridEnd).day ?? 35
        return (0..<max(7, days)).map { AgendaDates.adding(days: $0, to: gridStart) }
    }
}
