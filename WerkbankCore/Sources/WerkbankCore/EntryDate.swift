import Foundation

/// De datum en tijd van een tijdregel als tekst om aan te passen: "di 3-11-2026 16:27". Inlezen is ruim: een weekdag
/// mag erbij staan (die telt niet mee), alleen een tijd ("9:30") houdt de dag, alleen een dag ("4-11", "4 nov") houdt
/// de tijd, en "vandaag", "gisteren" en "eergisteren" kunnen ook.
public enum EntryDateText {
    private static let weekdays = ["zo", "ma", "di", "wo", "do", "vr", "za"]
    private static let weekdayNames: Set<String> = [
        "zo", "ma", "di", "wo", "do", "vr", "za",
        "zondag", "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag",
    ]
    private static let monthNames = ["januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus",
                                     "september", "oktober", "november", "december"]

    /// "di 3-11-2026 16:27"
    public static func text(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        let weekday = weekdays[max(0, min(6, (c.weekday ?? 1) - 1))]
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        return "\(weekday) \(c.day ?? 1)-\(c.month ?? 1)-\(c.year ?? 2000) \(time)"
    }

    /// Leest een datum en/of tijd; wat er niet staat komt uit `base`. `now`: waar "vandaag" en "gisteren" van uitgaan.
    /// `nil` als er niets bruikbaars staat, iets onbekends bij staat, of de datum niet bestaat (31-2).
    public static func parse(_ text: String, base: Date, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let tokens = text.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }

        var hour: Int?
        var minute: Int?
        var day: Int?
        var month: Int?
        var year: Int?
        var offset: Int?

        var index = 0
        while index < tokens.count {
            let token = tokens[index].trimmingCharacters(in: CharacterSet(charactersIn: "."))
            defer { index += 1 }
            if token.isEmpty || weekdayNames.contains(token) || token == "u" || token == "uur" { continue }
            if let time = Self.time(token) {
                guard hour == nil else { return nil }
                hour = time.hour
                minute = time.minute
                continue
            }
            switch token {
            case "vandaag": offset = 0; continue
            case "gisteren": offset = -1; continue
            case "eergisteren": offset = -2; continue
            default: break
            }
            if let numeric = Self.numericDate(token) {
                guard day == nil else { return nil }
                day = numeric.day
                month = numeric.month
                year = numeric.year
                continue
            }
            // "4 nov" of "4 november 2026"
            if let number = Int(token), (1...31).contains(number), index + 1 < tokens.count,
               let named = Self.month(tokens[index + 1].trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
                guard day == nil else { return nil }
                day = number
                month = named
                index += 1
                if index + 1 < tokens.count, let full = Int(tokens[index + 1]), (1000...9999).contains(full) {
                    year = full
                    index += 1
                }
                continue
            }
            return nil
        }

        guard hour != nil || day != nil || offset != nil else { return nil }
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: base)
        if let offset {
            guard day == nil, let target = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            let shifted = calendar.dateComponents([.year, .month, .day], from: target)
            components.year = shifted.year
            components.month = shifted.month
            components.day = shifted.day
        }
        if let day, let month {
            components.day = day
            components.month = month
            if let year { components.year = year < 100 ? 2000 + year : year }
        }
        if let hour, let minute {
            components.hour = hour
            components.minute = minute
        }
        components.second = 0
        guard let wanted = components.year, (2000...2100).contains(wanted),
              let date = calendar.date(from: components) else { return nil }
        // Een dag die niet bestaat (31-2) schuift Calendar door naar de volgende maand: dat is geen geldige invoer.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == components.year, check.month == components.month, check.day == components.day else { return nil }
        return date
    }

    /// "16:27" of "9:05"
    private static func time(_ token: String) -> (hour: Int, minute: Int)? {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// "3-11", "3-11-2026", "3/11/26", "3.11.2026"
    private static func numericDate(_ token: String) -> (day: Int, month: Int, year: Int?)? {
        let parts = token.split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." }).map(String.init)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts[0].count <= 2, parts[1].count <= 2,
              let day = Int(parts[0]), let month = Int(parts[1]),
              (1...31).contains(day), (1...12).contains(month) else { return nil }
        guard parts.count == 3 else { return (day, month, nil) }
        guard parts[2].count == 2 || parts[2].count == 4, let year = Int(parts[2]) else { return nil }
        return (day, month, year)
    }

    /// "nov", "november", "mrt", "maart": het begin van de naam (minstens drie letters).
    private static func month(_ token: String) -> Int? {
        if token == "mrt" { return 3 }
        guard token.count >= 3 else { return nil }
        return monthNames.firstIndex { $0.hasPrefix(token) }.map { $0 + 1 }
    }
}
