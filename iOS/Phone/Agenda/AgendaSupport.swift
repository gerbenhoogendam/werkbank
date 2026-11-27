import SwiftUI
import WerkbankCore

/// De weergaven van de agenda: dag, werkweek, maand en de lijst met wat er de komende twee weken staat.
enum AgendaMode: String, Hashable {
    case dag, week, maand, lijst
}

/// Datums voor de agenda: weken beginnen op maandag (ISO), Nederlandse namen.
enum AgendaDates {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "nl_NL")
        cal.timeZone = .current
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }()

    /// Het grid van de dag- en weekweergave: 07:00 tot 19:00.
    static let startHour = 7
    static let endHour = 19
    static let hourHeight: CGFloat = 52

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.dateFormat = pattern
        return f
    }

    private static let weekdayLong = formatter("EEEE")
    private static let monthLong = formatter("LLLL")
    private static let dayMonth = formatter("d MMMM")

    static func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func monday(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(date)
    }

    /// Maandag tot en met vrijdag van de week van `date`.
    static func workdays(of date: Date) -> [Date] {
        let first = Self.monday(of: date)
        return (0..<5).map { adding(days: $0, to: first) }
    }

    static func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }

    static func isWeekend(_ date: Date) -> Bool { calendar.isDateInWeekend(date) }

    static func sameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }

    /// Volgende of vorige werkdag (weekend overgeslagen).
    static func workday(after date: Date, by step: Int) -> Date {
        var day = adding(days: step, to: startOfDay(date))
        while isWeekend(day) { day = adding(days: step, to: day) }
        return day
    }

    static func firstOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? startOfDay(date)
    }

    static func addingMonths(_ months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    static func week(_ date: Date) -> Int { DutchDate.isoWeek(date) }

    /// "DO"
    static func weekdayShort(_ date: Date) -> String { DutchDate.weekdayShort(date).uppercased() }

    /// "DONDERDAG 26"
    static func dayTitle(_ date: Date) -> String {
        "\(weekdayLong.string(from: date)) \(calendar.component(.day, from: date))".uppercased()
    }

    /// "NOVEMBER"
    static func monthName(_ date: Date) -> String { monthLong.string(from: date).uppercased() }

    /// "DONDERDAG 26 NOVEMBER"
    static func dayAndMonth(_ date: Date) -> String {
        "\(weekdayLong.string(from: date)) \(dayMonth.string(from: date))".uppercased()
    }

    /// "23 – 27 NOVEMBER", of "30 NOVEMBER – 4 DECEMBER".
    static func workweekRange(_ date: Date) -> String {
        let days = workdays(of: date)
        guard let first = days.first, let last = days.last else { return "" }
        let firstDay = calendar.component(.day, from: first)
        if calendar.component(.month, from: first) == calendar.component(.month, from: last) {
            return "\(firstDay) – \(dayMonth.string(from: last))".uppercased()
        }
        return "\(dayMonth.string(from: first)) – \(dayMonth.string(from: last))".uppercased()
    }

    static func dayNumber(_ date: Date) -> Int { calendar.component(.day, from: date) }

    /// "07:15 – 07:45", of "HELE DAG".
    static func timeRange(_ event: AgendaEvent) -> String {
        event.isAllDay ? "HELE DAG" : "\(DutchDate.time(event.start)) – \(DutchDate.time(event.end))"
    }

    /// Positie in het grid (07:00 = 0), begrensd op het grid.
    static func offset(of date: Date, on day: Date) -> CGFloat {
        let hours = date.timeIntervalSince(startOfDay(day)) / 3600
        let clamped = min(max(hours, Double(startHour)), Double(endHour))
        return CGFloat(clamped - Double(startHour)) * hourHeight
    }

    static var gridHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }
}

extension AgendaEvent {
    /// Afspraken die met "GH" beginnen zijn persoonlijk: niet in het grid, maar in de lijst erboven.
    var isPersonal: Bool { title.hasPrefix("GH") }

    func overlaps(day: Date) -> Bool {
        let start = AgendaDates.startOfDay(day)
        let end = AgendaDates.adding(days: 1, to: start)
        return self.start < end && self.end > start
    }
}

/// Een afspraak met zijn plek naast overlappende afspraken.
struct AgendaPlacedEvent: Identifiable {
    let event: AgendaEvent
    let lane: Int
    let lanes: Int

    var id: String { event.id }

    static func place(_ events: [AgendaEvent]) -> [AgendaPlacedEvent] {
        let slots = EventLayout.assign(events.map { (start: $0.start, end: $0.end) })
        return zip(events, slots).map { AgendaPlacedEvent(event: $0, lane: $1.lane, lanes: max(1, $1.laneCount)) }
    }
}

// MARK: - Persoonlijke afspraken (GH)

/// Compacte lijst bovenaan: één regel van 22 pt per afspraak, in een putje met een inktlijn eronder.
struct AgendaPersonalBand: View {
    let events: [AgendaEvent]
    let onOpen: (AgendaEvent) -> Void

    var body: some View {
        if !events.isEmpty {
            VStack(spacing: 0) {
                ForEach(events) { event in
                    Button {
                        onOpen(event)
                    } label: {
                        HStack(spacing: 8) {
                            Text(AgendaDates.weekdayShort(event.start))
                                .font(Ph.text(9.5, .semibold))
                                .tracking(0.8)
                                .foregroundStyle(Ph.ink2)
                                .frame(width: 20, alignment: .leading)
                            Text(AgendaDates.timeRange(event))
                                .font(Ph.text(11))
                                .monospacedDigit()
                                .foregroundStyle(Ph.ink2)
                                .frame(width: 80, alignment: .leading)
                            Text(event.title)
                                .font(Ph.text(11, .medium))
                                .foregroundStyle(event.end < .now ? Ph.ink3 : Ph.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .overlay(alignment: .bottom) { Rectangle().fill(Ph.line).frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .phWell(Ph.band)
            .overlay(alignment: .bottom) { Rectangle().fill(Ph.ink).frame(height: 2) }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Blok in het grid

/// Een afspraak als wit blok met inktrand en een gekleurde rand (links in de dag, boven in de week).
struct AgendaBlock: View {
    let event: AgendaEvent
    let height: CGFloat
    /// Weekweergave: heel kleine tekst, gekleurde rand boven.
    var small = false

    private var isPast: Bool { event.end <= .now }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Rectangle().fill(Ph.card).shadow(color: Ph.ink.opacity(0.12), radius: 1, y: 1))
            .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 1))
            .overlay(alignment: small ? .top : .leading) {
                if small {
                    Rectangle().fill(event.color).frame(height: 3)
                } else {
                    Rectangle().fill(event.color).frame(width: 4)
                }
            }
            .clipped()
            .opacity(isPast ? 0.55 : 1)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        if small {
            VStack(alignment: .leading, spacing: 0) {
                Text(DutchDate.time(event.start))
                    .font(Ph.text(8.5))
                    .monospacedDigit()
                    .foregroundStyle(Ph.ink2)
                    .lineLimit(1)
                Text(event.title)
                    .font(Ph.text(9.5, .semibold))
                    .foregroundStyle(Ph.ink)
                    .lineLimit(max(1, Int((height - 14) / 11)))
            }
            .padding(.horizontal, 3)
            .padding(.top, 4)
            .padding(.bottom, 1)
        } else if height < 30 {
            HStack(spacing: 8) {
                Text(event.title)
                    .font(Ph.text(13, .semibold))
                    .foregroundStyle(Ph.ink)
                    .lineLimit(1)
                Text(meta)
                    .font(Ph.text(11.5))
                    .monospacedDigit()
                    .foregroundStyle(Ph.ink2)
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(Ph.text(13, .semibold))
                    .foregroundStyle(Ph.ink)
                    .lineLimit(height > 60 ? 2 : 1)
                Text(meta)
                    .font(Ph.text(11.5))
                    .monospacedDigit()
                    .foregroundStyle(Ph.ink2)
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
        }
    }

    private var meta: String {
        let time = "\(DutchDate.time(event.start)) – \(DutchDate.time(event.end))"
        if let location = event.location { return "\(time) · \(location)" }
        return time
    }
}

// MARK: - Geen toegang

/// Agenda zonder toegang: knop om toegang te vragen, of naar Instellingen als die geweigerd is.
struct AgendaAccessCard: View {
    let service: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "calendar")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Ph.ink)
            Text("GEEN TOEGANG TOT AGENDA'S")
                .font(Ph.poster(28))
                .foregroundStyle(Ph.ink)
            if service.isDenied || service.status == .writeOnly {
                Button("INSTELLINGEN") { SystemSettings.openCalendarPrivacy() }
                    .buttonStyle(PhPrimaryStyle())
            } else {
                Button("TOEGANG GEVEN") { Task { await service.requestAccess() } }
                    .buttonStyle(PhPrimaryStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .phCard()
        .padding(.horizontal, 16)
    }
}
