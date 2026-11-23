import Foundation

/// Later versturen: de vaste keuzes (op een natuurlijk ogende minuut, niet precies op het hele uur) en hoe een tijdstip
/// heet ("morgen 07:56").
public enum SendLater {
    public struct Choice: Equatable, Sendable {
        public let title: String
        public let date: Date
    }

    public static let morning = (hour: 7, minute: 56)
    public static let afternoon = (hour: 13, minute: 7)

    /// Ochtend en middag (vandaag als dat nog komt, anders morgen), en maandagochtend als die er niet al bij staat.
    public static func choices(now: Date, calendar: Calendar = .current) -> [Choice] {
        var result: [Choice] = []
        let morning = next(hour: Self.morning.hour, minute: Self.morning.minute, after: now, calendar: calendar)
        result.append(Choice(title: dayPart(morning, part: "ochtend", now: now, calendar: calendar), date: morning))
        let afternoon = next(hour: Self.afternoon.hour, minute: Self.afternoon.minute, after: now, calendar: calendar)
        result.append(Choice(title: dayPart(afternoon, part: "middag", now: now, calendar: calendar), date: afternoon))
        var monday = morning
        while calendar.component(.weekday, from: monday) != 2 {
            monday = calendar.date(byAdding: .day, value: 1, to: monday) ?? monday
        }
        if !result.contains(where: { $0.date == monday }) {
            result.append(Choice(title: "Maandagochtend \(time(monday, calendar: calendar))", date: monday))
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Het eerstvolgende moment met dit uur en deze minuut na `now`.
    static func next(hour: Int, minute: Int, after now: Date, calendar: Calendar) -> Date {
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private static func dayPart(_ date: Date, part: String, now: Date, calendar: Calendar) -> String {
        let prefix: String
        if calendar.isDate(date, inSameDayAs: now) {
            prefix = part == "ochtend" ? "Vanochtend" : "Vanmiddag"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            prefix = "Morgen" + part
        } else {
            prefix = weekday(date, calendar: calendar).capitalized + part
        }
        return "\(prefix) \(time(date, calendar: calendar))"
    }

    /// "vandaag 07:56", "morgen 07:56", "maandag 07:56" (binnen een week), anders "ma 7 dec 07:56".
    public static func label(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let clock = time(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) { return "vandaag \(clock)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "morgen \(clock)"
        }
        let start = calendar.startOfDay(for: now)
        if let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day, days > 0, days < 7 {
            return "\(weekday(date, calendar: calendar)) \(clock)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "") + " \(clock)"
    }

    private static func weekday(_ date: Date, calendar: Calendar) -> String {
        let names = ["zondag", "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag"]
        return names[(calendar.component(.weekday, from: date) - 1) % 7]
    }

    private static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
