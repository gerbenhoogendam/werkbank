import Foundation

/// Wat er na "GH:" in de afspraaktitel komt.
public enum PrefixChoice: String, CaseIterable, Identifiable {
    case time, vdm, ndm
    public var id: String { rawValue }
}

public enum Scheduling {
    public static let step = 15   // minuten

    // MARK: Afronden

    /// Naar beneden afronden op 15 minuten.
    public static func snapDown(minutes: Int) -> Int {
        (minutes / step) * step
    }

    /// Naar het dichtstbijzijnde kwartier.
    public static func snapNearest(minutes: Int) -> Int {
        Int((Double(minutes) / Double(step)).rounded()) * step
    }

    /// Start op basis van minuten sinds middernacht (bijv. vanuit de cursorpositie), naar beneden op 15 min.
    public static func start(onDayOf day: Date, minutesFromMidnight: Int, calendar: Calendar = .current) -> Date {
        let snapped = max(0, snapDown(minutes: minutesFromMidnight))
        let startOfDay = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: snapped, to: startOfDay) ?? startOfDay
    }

    public static func snapDown(_ date: Date, calendar: Calendar = .current) -> Date {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return start(onDayOf: date, minutesFromMidnight: minutes, calendar: calendar)
    }

    // MARK: Eindtijd

    /// Standaard 1 uur, maximaal tot het einde van de dag.
    public static func defaultEnd(start: Date, dayEnd: Date) -> Date {
        min(start.addingTimeInterval(3600), dayEnd)
    }

    /// Eindtijd in stappen van 15 minuten, minimaal 15 minuten na de start, maximaal `dayEnd`.
    public static func clampEnd(start: Date, proposedMinutesAfterStart: Int, dayEnd: Date) -> Date {
        let minutes = max(step, snapNearest(minutes: proposedMinutesAfterStart))
        let proposed = start.addingTimeInterval(Double(minutes) * 60)
        return min(proposed, max(dayEnd, start.addingTimeInterval(Double(step) * 60)))
    }

    // MARK: Prefix en titel

    /// vdm tot 13:00, ndm vanaf 13:00. (Vóór 08:00 is niet gespecificeerd; dat valt onder vdm.)
    public static func defaultPrefix(forStart start: Date, calendar: Calendar = .current) -> PrefixChoice {
        let hour = calendar.component(.hour, from: start)
        return hour >= 13 ? .ndm : .vdm
    }

    /// "8:30" — zonder voorloopnul.
    public static func timeLabel(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    public static func prefixText(_ choice: PrefixChoice, start: Date, calendar: Calendar = .current) -> String {
        switch choice {
        case .vdm:  return "vdm"
        case .ndm:  return "ndm"
        case .time: return timeLabel(start, calendar: calendar)
        }
    }

    /// "GH: vdm Offerte nieuwe website De Vries" / "GH: 8:30 Offerte …"
    public static func eventTitle(choice: PrefixChoice, start: Date, todoTitle: String,
                                  calendar: Calendar = .current) -> String {
        "GH: \(prefixText(choice, start: start, calendar: calendar)) \(todoTitle)"
    }
}
