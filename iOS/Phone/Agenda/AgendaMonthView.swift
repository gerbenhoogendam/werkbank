import SwiftUI

/// De maand: een raster dat op maandag begint, met kleine blokjes per afspraak; daaronder de afspraken van de gekozen dag.
struct AgendaMonthView: View {
    @Binding var selected: Date
    /// De dagen van het raster (hele weken, maandag eerst).
    let gridDays: [Date]
    /// Afspraken van het raster (zonder GH).
    let events: [AgendaEvent]
    let onOpen: (AgendaEvent) -> Void

    private let weekdayNames = ["MA", "DI", "WO", "DO", "VR", "ZA", "ZO"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                monthGrid
                dayList
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    // MARK: Raster

    private var monthGrid: some View {
        let month = AgendaDates.calendar.component(.month, from: selected)
        let weeks = stride(from: 0, to: gridDays.count, by: 7).map { Array(gridDays[$0..<min($0 + 7, gridDays.count)]) }
        return VStack(spacing: 3) {
            HStack(spacing: 3) {
                ForEach(weekdayNames, id: \.self) { name in
                    Text(name)
                        .font(Ph.text(9, .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Ph.ink2)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 3) {
                    ForEach(week, id: \.self) { day in
                        cell(day, inMonth: AgendaDates.calendar.component(.month, from: day) == month)
                    }
                }
            }
        }
        .padding(3)
        .phWell()
    }

    private func cell(_ day: Date, inMonth: Bool) -> some View {
        let on = AgendaDates.sameDay(day, selected)
        let today = AgendaDates.isToday(day)
        let marks = events.filter { $0.overlaps(day: day) }.prefix(4)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selected = day }
        } label: {
            VStack(spacing: 3) {
                Text("\(AgendaDates.dayNumber(day))")
                    .font(Ph.poster(19))
                    .foregroundStyle(inMonth ? Ph.ink : Ph.ink3.opacity(0.6))
                HStack(spacing: 2) {
                    ForEach(Array(marks), id: \.id) { event in
                        Rectangle()
                            .fill(on ? Ph.ink : (inMonth ? event.color : Ph.line))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if on {
                    Rectangle().fill(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                        .shadow(color: Ph.ink.opacity(0.18), radius: 0, y: 1)
                        .shadow(color: Ph.ink.opacity(0.12), radius: 2, y: 2)
                } else if inMonth {
                    Rectangle().fill(Ph.card)
                }
            }
            .overlay {
                if today && !on { Rectangle().strokeBorder(Ph.ink, lineWidth: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AgendaDates.dayAndMonth(day))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Afspraken van de dag

    private var dayList: some View {
        let dayEvents = events.filter { $0.overlaps(day: selected) }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.start < b.start
            }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("\(AgendaDates.weekdayShort(selected)) \(AgendaDates.dayNumber(selected)) \(AgendaDates.monthName(selected))")
                    .font(Ph.poster(26))
                    .foregroundStyle(Ph.ink)
                PhCaps(text: dayEvents.count == 1 ? "1 afspraak" : "\(dayEvents.count) afspraken", size: 10.5)
            }
            VStack(spacing: 0) {
                if dayEvents.isEmpty {
                    PhCaps(text: "Geen afspraken", size: 11, color: Ph.ink3)
                        .frame(maxWidth: .infinity, minHeight: 46)
                } else {
                    ForEach(dayEvents) { event in
                        row(event, isLast: event.id == dayEvents.last?.id)
                    }
                }
            }
            .phCard()
        }
    }

    private func row(_ event: AgendaEvent, isLast: Bool) -> some View {
        Button {
            onOpen(event)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    if event.isAllDay {
                        Text("DAG").font(Ph.text(11, .semibold)).tracking(1)
                    } else {
                        Text(DutchDate.time(event.start)).font(Ph.text(11, .semibold))
                        Text(DutchDate.time(event.end)).font(Ph.text(11)).foregroundStyle(Ph.ink2)
                    }
                }
                .monospacedDigit()
                .foregroundStyle(Ph.ink)
                .frame(width: 40, alignment: .leading)
                Rectangle().fill(event.color).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(Ph.text(14, .semibold))
                        .foregroundStyle(Ph.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let location = event.location {
                        Text(location)
                            .font(Ph.text(12))
                            .foregroundStyle(Ph.ink2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .opacity(event.end <= .now ? 0.55 : 1)
            .overlay(alignment: .bottom) {
                if !isLast { Rectangle().fill(Ph.hair).frame(height: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
