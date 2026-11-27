import SwiftUI

/// De vijf werkdagen van de week als knoppen: weekdag, dagnummer en een blokje per afspraak.
struct AgendaDayStrip: View {
    let days: [Date]
    @Binding var selected: Date
    /// Afspraken van de week (zonder GH).
    let events: [AgendaEvent]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(days, id: \.self) { day in
                chip(day)
            }
        }
        .padding(3)
        .phWell()
        .padding(.horizontal, 16)
    }

    private func chip(_ day: Date) -> some View {
        let on = AgendaDates.sameDay(day, selected)
        let today = AgendaDates.isToday(day)
        let past = day < AgendaDates.startOfDay(.now)
        let marks = events.filter { !$0.isAllDay && $0.overlaps(day: day) }.prefix(5)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selected = day }
        } label: {
            VStack(spacing: 2) {
                Text(AgendaDates.weekdayShort(day))
                    .font(Ph.text(9.5, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(on ? Ph.ink : Ph.ink2)
                Text("\(AgendaDates.dayNumber(day))")
                    .font(Ph.poster(21))
                    .foregroundStyle(past && !on ? Ph.ink3 : Ph.ink)
                HStack(spacing: 2) {
                    ForEach(Array(marks), id: \.id) { event in
                        Rectangle()
                            .fill(on ? Ph.ink : event.color)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if on {
                    Rectangle().fill(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                        .shadow(color: Ph.ink.opacity(0.18), radius: 0, y: 1)
                        .shadow(color: Ph.ink.opacity(0.12), radius: 2, y: 2)
                }
            }
            .overlay(alignment: .bottom) {
                if today && !on {
                    Rectangle().fill(Ph.ink).frame(width: 16, height: 2).padding(.bottom, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AgendaDates.dayAndMonth(day))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Het uurgrid van één dag (07:00–19:00, 52 pt per uur) met de afspraken en de lijn van nu.
struct AgendaDayGrid: View {
    let day: Date
    /// Afspraken met een tijd (zonder GH en zonder hele dagen).
    let events: [AgendaEvent]
    let onOpen: (AgendaEvent) -> Void

    private let labelWidth: CGFloat = 44
    private let gap: CGFloat = 8

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                grid
                    .padding(.top, 10)
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
            }
            .onAppear {
                let hour = Calendar.current.component(.hour, from: .now)
                let target = min(max(hour - 1, AgendaDates.startHour), AgendaDates.endHour - 1)
                Task { @MainActor in proxy.scrollTo(target, anchor: .top) }
            }
        }
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
                let width = max(0, geo.size.width - labelWidth - gap)
                ZStack(alignment: .topLeading) {
                    ForEach(AgendaPlacedEvent.place(events)) { placed in
                        block(placed, width: width)
                    }
                    nowLine
                }
            }
        }
    }

    private func hourRow(_ hour: Int) -> some View {
        HStack(alignment: .top, spacing: gap) {
            Text(String(format: "%02d:00", hour))
                .font(Ph.text(10.5))
                .monospacedDigit()
                .foregroundStyle(Ph.ink2)
                .frame(width: labelWidth, alignment: .trailing)
                .offset(y: -7)
            Rectangle().fill(Ph.line).frame(height: 1)
        }
    }

    private func block(_ placed: AgendaPlacedEvent, width: CGFloat) -> some View {
        let event = placed.event
        let top = AgendaDates.offset(of: event.start, on: day)
        let bottom = AgendaDates.offset(of: event.end, on: day)
        let height = max(20, bottom - top - 2)
        let laneWidth = width / CGFloat(placed.lanes)
        return Button {
            onOpen(event)
        } label: {
            AgendaBlock(event: event, height: height)
        }
        .buttonStyle(.plain)
        .frame(width: max(0, laneWidth - 2), height: height)
        .offset(x: labelWidth + gap + laneWidth * CGFloat(placed.lane), y: top + 1)
    }

    @ViewBuilder private var nowLine: some View {
        if AgendaDates.isToday(day) {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let now = timeline.date
                let hours = now.timeIntervalSince(AgendaDates.startOfDay(now)) / 3600
                if hours >= Double(AgendaDates.startHour) && hours <= Double(AgendaDates.endHour) {
                    HStack(spacing: 0) {
                        Text(DutchDate.time(now))
                            .font(Ph.text(10.5, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Ph.paper)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Ph.ink)
                            .frame(width: labelWidth, alignment: .trailing)
                        Rectangle().fill(Ph.ink).frame(width: 8, height: 8)
                        Rectangle().fill(Ph.ink).frame(height: 2)
                    }
                    .frame(height: 16)
                    .offset(y: AgendaDates.offset(of: now, on: now) - 8)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}
