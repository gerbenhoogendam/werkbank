import SwiftUI

/// De werkweek: maandag tot en met vrijdag in vijf even brede kolommen naast elkaar, heel kleine tekst.
struct AgendaWeekGrid: View {
    let days: [Date]
    /// Afspraken van de week met een tijd (zonder GH en zonder hele dagen).
    let events: [AgendaEvent]
    let onOpen: (AgendaEvent) -> Void
    /// Tik op een dag: die dag openen in de dagweergave.
    let onSelectDay: (Date) -> Void

    private let labelWidth: CGFloat = 34
    private let gap: CGFloat = 4
    private let columnGap: CGFloat = 3

    var body: some View {
        VStack(spacing: 4) {
            dayHeaders
            ScrollViewReader { proxy in
                ScrollView {
                    grid
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .onAppear {
                    let hour = Calendar.current.component(.hour, from: .now)
                    let target = min(max(hour - 1, AgendaDates.startHour), AgendaDates.endHour - 1)
                    Task { @MainActor in proxy.scrollTo(target, anchor: .top) }
                }
            }
        }
        .padding(.trailing, 12)
    }

    private var dayHeaders: some View {
        HStack(spacing: columnGap) {
            ForEach(days, id: \.self) { day in
                let today = AgendaDates.isToday(day)
                Button {
                    onSelectDay(day)
                } label: {
                    VStack(spacing: 0) {
                        Text(AgendaDates.weekdayShort(day))
                            .font(Ph.text(9, .semibold))
                            .tracking(1.2)
                            .foregroundStyle(today ? Ph.ink : Ph.ink2)
                        Text("\(AgendaDates.dayNumber(day))")
                            .font(Ph.poster(18))
                            .foregroundStyle(Ph.ink)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background {
                        if today {
                            Rectangle().fill(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                                .shadow(color: Ph.ink.opacity(0.18), radius: 0, y: 1)
                        } else {
                            Rectangle().fill(Ph.card).shadow(color: Ph.ink.opacity(0.06), radius: 0, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AgendaDates.dayAndMonth(day))
            }
        }
        .padding(.leading, labelWidth + gap)
        .padding(.top, 4)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(AgendaDates.startHour..<AgendaDates.endHour, id: \.self) { hour in
                hourRow(hour)
                    .frame(height: AgendaDates.hourHeight, alignment: .top)
                    .id(hour)
            }
            hourRow(AgendaDates.endHour)
                .frame(height: 1, alignment: .top)
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                let available = max(0, geo.size.width - labelWidth - gap)
                let columnWidth = max(0, (available - columnGap * CGFloat(max(0, days.count - 1))) / CGFloat(max(1, days.count)))
                ZStack(alignment: .topLeading) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        column(day, width: columnWidth)
                            .offset(x: labelWidth + gap + CGFloat(index) * (columnWidth + columnGap))
                    }
                    nowLine
                }
            }
        }
    }

    private func hourRow(_ hour: Int) -> some View {
        HStack(alignment: .top, spacing: gap) {
            Text(String(format: "%02d:00", hour))
                .font(Ph.text(9))
                .monospacedDigit()
                .foregroundStyle(Ph.ink2)
                .frame(width: labelWidth, alignment: .trailing)
                .offset(y: -5)
            Rectangle().fill(Ph.hair).frame(height: 1)
        }
    }

    private func column(_ day: Date, width: CGFloat) -> some View {
        let dayEvents = events.filter { $0.overlaps(day: day) }
        let today = AgendaDates.isToday(day)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill((today ? Color.white.opacity(0.55) : Color.clear)
                    .shadow(.inner(color: Ph.ink.opacity(0.05), radius: 1, y: 1)))
                .frame(width: width, height: AgendaDates.gridHeight)
            ForEach(AgendaPlacedEvent.place(dayEvents)) { placed in
                let event = placed.event
                let top = AgendaDates.offset(of: event.start, on: day)
                let bottom = AgendaDates.offset(of: event.end, on: day)
                let height = max(16, bottom - top - 2)
                let laneWidth = width / CGFloat(placed.lanes)
                Button {
                    onOpen(event)
                } label: {
                    AgendaBlock(event: event, height: height, small: true)
                }
                .buttonStyle(.plain)
                .frame(width: max(0, laneWidth - 2), height: height)
                .offset(x: 1 + laneWidth * CGFloat(placed.lane), y: top + 1)
            }
        }
        .frame(width: width, height: AgendaDates.gridHeight, alignment: .topLeading)
    }

    @ViewBuilder private var nowLine: some View {
        if days.contains(where: { AgendaDates.isToday($0) }) {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let now = timeline.date
                let hours = now.timeIntervalSince(AgendaDates.startOfDay(now)) / 3600
                if hours >= Double(AgendaDates.startHour) && hours <= Double(AgendaDates.endHour) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Ph.ink).frame(width: 6, height: 6)
                        Rectangle().fill(Ph.ink).frame(height: 2)
                    }
                    .frame(height: 6)
                    .padding(.leading, labelWidth - 2)
                    .offset(y: AgendaDates.offset(of: now, on: now) - 3)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}
