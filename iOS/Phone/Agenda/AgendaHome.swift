import SwiftUI

/// De agenda op de iPhone: dag (werkweekstrook en uurgrid), drie werkdagen, werkweek in vijf kolommen of de lijst van
/// de komende twee weken.
/// Afspraken die met "GH" beginnen staan gewoon in het grid, net als de rest; bovenaan alleen afspraken van een hele dag.
struct AgendaHome: View {
    private let service = CalendarService.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: AgendaMode = .dag
    @State private var selected = AgendaDates.startOfDay(.now)
    @State private var openEvent: AgendaEvent?
    @State private var creating = false
    /// "Tijd schrijven" gekozen: na het sluiten van het blad de tijdinvoer openen (twee bladen tegelijk kan niet).
    @State private var writeTimeAfterClose = false
    /// Waar de nieuwe dag of week vandaan schuift: rechts bij vooruit, links bij terug.
    @State private var slideEdge: Edge = .trailing

    private var modeItems: [PhSegmented<AgendaMode>.Item] {
        [PhSegmented<AgendaMode>.Item(value: .dag, title: "Dag"),
         PhSegmented<AgendaMode>.Item(value: .drie, title: "3 dagen"),
         PhSegmented<AgendaMode>.Item(value: .week, title: "Week")]
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
        case .drie:
            return AgendaDates.range(threeDays)
        case .week:
            return AgendaDates.workweekRange(selected)
        case .lijst:
            return "KOMEND · \(upcoming.count) AFSPRAKEN"
        }
    }

    private var title: String {
        switch mode {
        case .dag: return AgendaDates.dayTitle(selected)
        case .drie: return AgendaDates.dayTitle(threeDays.first ?? selected)
        case .week: return "WEEK \(AgendaDates.week(selected))"
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

    /// De drie werkdagen vanaf de gekozen dag.
    private var threeDays: [Date] { AgendaDates.workdays(from: selected, count: 3) }

    /// Dag: vorige of volgende werkdag; 3 dagen: drie werkdagen; week: een week.
    private func shift(_ step: Int) {
        slideEdge = step > 0 ? .trailing : .leading
        withAnimation(.easeOut(duration: 0.22)) {
            switch mode {
            case .dag: selected = AgendaDates.workday(after: selected, by: step)
            case .drie:
                var day = threeDays.first ?? selected
                for _ in 0..<3 { day = AgendaDates.workday(after: day, by: step) }
                selected = day
            case .week: selected = AgendaDates.adding(days: 7 * step, to: selected)
            case .lijst: break
            }
        }
    }

    /// Vegen over de dag, de band of het grid: naar links vooruit, naar rechts terug (zoals de pijltjes).
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard let step = Self.swipeStep(value) else { return }
                shift(step)
            }
    }

    /// Vegen over de strook met dagen: een hele week verder of terug, dezelfde dag van de week.
    private var weekSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard let step = Self.swipeStep(value) else { return }
                slideEdge = step > 0 ? .trailing : .leading
                withAnimation(.easeOut(duration: 0.22)) {
                    selected = AgendaDates.adding(days: 7 * step, to: selected)
                }
            }
    }

    /// Een veeg telt als hij vooral horizontaal is en ver genoeg gaat (of snel genoeg).
    private static func swipeStep(_ value: DragGesture.Value) -> Int? {
        let dx = value.translation.width
        let dy = value.translation.height
        let flick = value.predictedEndTranslation.width
        guard abs(dx) > abs(dy) * 1.4, abs(dx) > 50 || abs(flick) > 140 else { return nil }
        return dx < 0 ? 1 : -1
    }

    /// Een dag kiezen in de strook schuift ook van de goede kant.
    private var stripSelection: Binding<Date> {
        Binding(get: { selected }, set: { day in
            slideEdge = day > selected ? .trailing : .leading
            withAnimation(.easeOut(duration: 0.22)) { selected = day }
        })
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
            AgendaDayStrip(days: AgendaDates.workdays(of: selected), selected: stripSelection,
                           events: weekEvents)
                .contentShape(Rectangle())
                .simultaneousGesture(weekSwipe)
            VStack(alignment: .leading, spacing: 10) {
                AgendaPersonalBand(events: dayEvents.filter(\.isAllDay), onOpen: open)
                AgendaDayGrid(day: selected, events: dayEvents.filter { !$0.isAllDay }, onOpen: open)
            }
            .id(selected)
            .transition(.push(from: slideEdge))
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
        case .drie:
            columns(threeDays)
        case .week:
            columns(AgendaDates.workdays(of: selected))
        case .lijst:
            AgendaListView(events: upcoming, onOpen: open)
        }
    }

    /// 3 dagen en Week: dagen als kolommen; GH-afspraken gewoon in het grid, alleen hele dagen bovenaan.
    @ViewBuilder private func columns(_ days: [Date]) -> some View {
        let first = days.first ?? selected
        let end = AgendaDates.adding(days: 1, to: days.last ?? selected)
        let events = fetch(from: first, to: end).filter { event in days.contains { event.overlaps(day: $0) } }
        AgendaPersonalBand(events: events.filter(\.isAllDay), onOpen: open)
        AgendaWeekGrid(days: days, events: events.filter { !$0.isAllDay }, onOpen: open) { day in
            withAnimation(.easeOut(duration: 0.15)) {
                selected = day
                mode = .dag
            }
        }
        .id(first)
        .transition(.push(from: slideEdge))
        .simultaneousGesture(swipe)
    }
}
