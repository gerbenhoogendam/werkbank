import SwiftUI
import WerkbankCore

/// De lijst: wat er de komende veertien dagen staat, per dag met een kop die blijft staan (vandaag limoen).
/// GH-afspraken staan ertussen als kleine regel.
struct AgendaListView: View {
    static let dayCount = 14

    /// Alle afspraken van vandaag tot en met dag 14 (met GH).
    let events: [AgendaEvent]
    let onOpen: (AgendaEvent) -> Void

    private struct DayGroup: Identifiable {
        let day: Date
        let events: [AgendaEvent]
        var id: Date { day }
    }

    private var groups: [DayGroup] {
        let today = AgendaDates.startOfDay(.now)
        return (0..<Self.dayCount).compactMap { offset in
            let day = AgendaDates.adding(days: offset, to: today)
            let dayEvents = events.filter { $0.overlaps(day: day) }
                .sorted { a, b in
                    if a.isAllDay != b.isAllDay { return a.isAllDay }
                    return a.start < b.start
                }
            return dayEvents.isEmpty ? nil : DayGroup(day: day, events: dayEvents)
        }
    }

    var body: some View {
        let groups = self.groups
        ScrollView {
            if groups.isEmpty {
                PhCaps(text: "Geen afspraken", size: 11, color: Ph.ink3)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .phCard()
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            rows(group)
                                .padding(.bottom, 10)
                        } header: {
                            header(group)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: Kop per dag

    private func label(_ day: Date) -> String {
        let calendar = AgendaDates.calendar
        if calendar.isDateInToday(day) { return "VANDAAG" }
        if calendar.isDateInTomorrow(day) { return "MORGEN" }
        return AgendaDates.dayTitle(day).split(separator: " ").first.map(String.init) ?? ""
    }

    private func sub(_ day: Date) -> String {
        let calendar = AgendaDates.calendar
        if calendar.isDateInToday(day) || calendar.isDateInTomorrow(day) {
            return DutchDate.weekdayAndDay(day).uppercased()
        }
        return DutchDate.short(day).uppercased()
    }

    private func header(_ group: DayGroup) -> some View {
        let today = AgendaDates.isToday(group.day)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label(group.day))
                .font(Ph.poster(20))
                .foregroundStyle(Ph.ink)
            PhCaps(text: sub(group.day), size: 10.5, color: today ? Ph.ink : Ph.ink2)
            Spacer(minLength: 8)
            PhCaps(text: "\(group.events.count)", size: 10.5, color: today ? Ph.ink : Ph.ink2)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background {
            if today {
                Rectangle().fill(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                    .shadow(color: Ph.ink.opacity(0.14), radius: 3, y: 2)
            } else {
                Rectangle().fill(Ph.paper)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.ink).frame(height: 1) }
    }

    // MARK: Regels

    /// Afspraken van de dag; vandaag met een lijn "nu" voor de eerste afspraak die nog moet beginnen.
    private func rows(_ group: DayGroup) -> some View {
        let today = AgendaDates.isToday(group.day)
        let now = Date()
        let nowIndex: Int? = today
            ? (group.events.firstIndex { !$0.isAllDay && $0.start >= now } ?? group.events.count)
            : nil
        return VStack(spacing: 0) {
            ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                if index == nowIndex { nowLine(now) }
                Button {
                    onOpen(event)
                } label: {
                    eventRow(event, on: group.day)
                }
                .buttonStyle(.plain)
            }
            if nowIndex == group.events.count { nowLine(now) }
        }
        .phCard()
    }

    private func nowLine(_ now: Date) -> some View {
        HStack(spacing: 0) {
            Text(DutchDate.time(now))
                .font(Ph.text(10, .semibold))
                .monospacedDigit()
                .foregroundStyle(Ph.ink)
                .padding(.leading, 10)
                .frame(width: 54, alignment: .leading)
            Rectangle().fill(Ph.ink).frame(width: 7, height: 7)
            Rectangle().fill(Ph.ink).frame(height: 2)
        }
        .frame(height: 14)
        .accessibilityLabel("Nu \(DutchDate.time(now))")
    }

    /// Begin en einde voor deze dag: een afspraak die op een andere dag begint of eindigt krijgt een streepje.
    private func times(_ event: AgendaEvent, on day: Date) -> (start: String, end: String) {
        if event.isAllDay { return ("HELE", "DAG") }
        let start = AgendaDates.sameDay(event.start, day) ? DutchDate.time(event.start) : "–"
        let end = AgendaDates.sameDay(event.end, day) ? DutchDate.time(event.end) : "–"
        return (start, end)
    }

    private func eventRow(_ event: AgendaEvent, on day: Date) -> some View {
        let time = times(event, on: day)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(time.start)
                    .font(Ph.text(13, .semibold))
                    .foregroundStyle(Ph.ink)
                Text(time.end)
                    .font(Ph.text(11))
                    .foregroundStyle(Ph.ink3)
            }
            .monospacedDigit()
            .lineLimit(1)
            .padding(.leading, 10)
            .frame(width: 54, alignment: .leading)
            Rectangle()
                .fill(event.color)
                .frame(width: 4, height: 30)
                .overlay(Rectangle().strokeBorder(Ph.ink.opacity(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(Ph.text(13.5, .semibold))
                    .foregroundStyle(Ph.ink)
                    .lineLimit(1)
                Text(event.location ?? event.calendarTitle)
                    .font(Ph.text(11.5))
                    .foregroundStyle(Ph.ink2)
                    .lineLimit(1)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            Spacer(minLength: 0)
        }
        .frame(height: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
        .opacity(event.end <= .now ? 0.5 : 1)
        .contentShape(Rectangle())
    }
}
