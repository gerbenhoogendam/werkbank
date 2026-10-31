import Foundation

/// Een moment dat in een mail wordt voorgesteld ("dinsdag 3 november om 14:00").
public struct DateProposal: Equatable {
    public var start: Date
    public var end: Date
    /// Er stond een tijd bij; zonder tijd is het een dag (start om 10:00, een uur).
    public var hasTime: Bool
    /// De tekst uit de mail.
    public var text: String
}

/// Herkent voorgestelde momenten in Nederlandse mailtekst: een datum ("3 november", "3-11", "dinsdag", "morgen",
/// "volgende week donderdag") met een tijd erbij ("om 14:00", "14.30 uur", "15u", "tussen 9.30 en 11 uur").
/// Data in het verleden vallen weg (een factuur "van 3 oktober" is geen voorstel).
public enum DateProposals {
    private static let months: [(String, Int)] = [
        ("januari", 1), ("jan", 1), ("februari", 2), ("feb", 2), ("maart", 3), ("mrt", 3), ("maa", 3), ("april", 4),
        ("apr", 4), ("mei", 5), ("juni", 6), ("jun", 6), ("juli", 7), ("jul", 7), ("augustus", 8), ("aug", 8),
        ("september", 9), ("sept", 9), ("sep", 9), ("oktober", 10), ("okt", 10), ("november", 11), ("nov", 11),
        ("december", 12), ("dec", 12),
    ]
    private static let weekdays = ["zondag", "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag"]

    private static let dayMonth = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})\s+(januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|november|december|jan|feb|mrt|maa|apr|jun|jul|aug|sept|sep|okt|nov|dec)\b\.?(?:\s+(\d{4}))?"#,
        options: [.caseInsensitive])
    private static let numeric = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})[-/](\d{1,2})(?:[-/](\d{4}|\d{2}))?\b(?!\s*uur)"#, options: [.caseInsensitive])
    private static let weekday = try! NSRegularExpression(
        pattern: #"\b(?:(volgende week|aanstaande|komende)\s+)?(maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag|zondag)\b"#,
        options: [.caseInsensitive])
    private static let relative = try! NSRegularExpression(pattern: #"\b(vandaag|overmorgen|morgen)\b"#, options: [.caseInsensitive])
    /// "14:00", "14.30", met eventueel "uur"; of "14 uur", "14u". Een bereik: "14:00-15:00", "tussen 9.30 en 11 uur".
    private static let time = try! NSRegularExpression(
        pattern: #"(?:\b([01]?\d|2[0-3])[:.]([0-5]\d)\b|\b([01]?\d|2[0-3])\s*(?:uur|u)\b)(?:\s*(?:-|–|tot|en)\s*(?:\b([01]?\d|2[0-3])[:.]([0-5]\d)\b|\b([01]?\d|2[0-3])(?:\s*(?:uur|u))?\b))?"#,
        options: [.caseInsensitive])

    public static func find(in text: String, reference: Date, calendar: Calendar = .current) -> [DateProposal] {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        var anchors: [(range: NSRange, day: Date)] = []
        var taken: [NSRange] = []

        func overlapsTaken(_ range: NSRange, slack: Int = 0) -> Bool {
            let widened = NSRange(location: range.location, length: range.length + slack)
            return taken.contains { NSIntersectionRange($0, widened).length > 0 }
        }

        let today = calendar.startOfDay(for: reference)
        let year = calendar.component(.year, from: reference)

        /// Een dag zonder jaar: dit jaar; ligt hij meer dan een dag terug, dan alleen het volgende jaar als dat
        /// binnen een half jaar valt (in december over "5 januari"), anders geen voorstel.
        func resolve(day: Int, month: Int, explicitYear: Int?) -> Date? {
            if let explicitYear {
                return calendar.date(from: DateComponents(year: explicitYear, month: month, day: day))
            }
            guard let thisYear = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            if thisYear >= today.addingTimeInterval(-86_400) { return thisYear }
            guard let next = calendar.date(from: DateComponents(year: year + 1, month: month, day: day)),
                  next.timeIntervalSince(today) < 183 * 86_400 else { return nil }
            return next
        }

        for match in dayMonth.matches(in: text, range: all) {
            let day = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let name = ns.substring(with: match.range(at: 2)).lowercased()
            let month = months.first { $0.0 == name }?.1 ?? 0
            let explicit = match.range(at: 3).location != NSNotFound ? Int(ns.substring(with: match.range(at: 3))) : nil
            guard (1...31).contains(day), month > 0, let date = resolve(day: day, month: month, explicitYear: explicit) else { continue }
            anchors.append((match.range, date))
            taken.append(match.range)
        }
        for match in numeric.matches(in: text, range: all) where !overlapsTaken(match.range) {
            let day = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let month = Int(ns.substring(with: match.range(at: 2))) ?? 0
            var explicit: Int?
            if match.range(at: 3).location != NSNotFound, let value = Int(ns.substring(with: match.range(at: 3))) {
                explicit = value < 100 ? 2000 + value : value
            }
            guard (1...31).contains(day), (1...12).contains(month),
                  let date = resolve(day: day, month: month, explicitYear: explicit) else { continue }
            anchors.append((match.range, date))
            taken.append(match.range)
        }
        for match in weekday.matches(in: text, range: all) {
            // "dinsdag 3 november": de datum erachter telt.
            let name = match.range(at: 2)
            if overlapsTaken(name, slack: 3) { continue }
            let target = (weekdays.firstIndex(of: ns.substring(with: name).lowercased()) ?? 0) + 1
            let current = calendar.component(.weekday, from: today)
            var ahead = (target - current + 7) % 7
            if ahead == 0 { ahead = 7 }
            var date = calendar.date(byAdding: .day, value: ahead, to: today) ?? today
            if match.range(at: 1).location != NSNotFound,
               ns.substring(with: match.range(at: 1)).lowercased() == "volgende week" {
                // Volgende week: de dag in de week na deze week (weken beginnen op maandag).
                var mondayCalendar = calendar
                mondayCalendar.firstWeekday = 2
                if let thisWeek = mondayCalendar.dateInterval(of: .weekOfYear, for: today),
                   let nextWeekStart = mondayCalendar.date(byAdding: .day, value: 7, to: thisWeek.start) {
                    let offset = (target + 5) % 7   // maandag 0 … zondag 6
                    date = mondayCalendar.date(byAdding: .day, value: offset, to: nextWeekStart) ?? date
                }
            }
            anchors.append((match.range, date))
            taken.append(match.range)
        }
        for match in relative.matches(in: text, range: all) where !overlapsTaken(match.range) {
            let word = ns.substring(with: match.range).lowercased()
            let offset = word == "vandaag" ? 0 : (word == "morgen" ? 1 : 2)
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            anchors.append((match.range, date))
            taken.append(match.range)
        }

        var proposals: [(location: Int, proposal: DateProposal)] = []
        for anchor in anchors.sorted(by: { $0.range.location < $1.range.location }) {
            let after = NSRange(location: anchor.range.location + anchor.range.length,
                                length: min(45, ns.length - anchor.range.location - anchor.range.length))
            let beforeStart = max(0, anchor.range.location - 25)
            let before = NSRange(location: beforeStart, length: anchor.range.location - beforeStart)
            let found = time.matches(in: text, range: after).first { !overlapsTaken($0.range) }
                ?? time.matches(in: text, range: before).last { !overlapsTaken($0.range) }
            var start = calendar.date(byAdding: .hour, value: 10, to: anchor.day) ?? anchor.day
            var end = start.addingTimeInterval(3600)
            var hasTime = false
            var textRange = anchor.range
            if let found {
                func value(_ index: Int) -> Int? {
                    let range = found.range(at: index)
                    return range.location == NSNotFound ? nil : Int(ns.substring(with: range))
                }
                let hour = value(1) ?? value(3) ?? 0
                let minute = value(2) ?? 0
                start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: anchor.day) ?? start
                if let endHour = value(4) ?? value(6) {
                    let candidate = calendar.date(bySettingHour: endHour, minute: value(5) ?? 0, second: 0, of: anchor.day)
                    end = candidate.flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(3600)
                } else {
                    end = start.addingTimeInterval(3600)
                }
                hasTime = true
                textRange = NSUnionRange(anchor.range, found.range)
            }
            guard end > reference else { continue }
            if proposals.contains(where: { $0.proposal.start == start }) { continue }
            proposals.append((textRange.location, DateProposal(start: start, end: end, hasTime: hasTime,
                                                               text: ns.substring(with: textRange))))
        }
        return proposals.sorted { $0.location < $1.location }.map(\.proposal)
    }
}

// MARK: - Vrije momenten

public enum FreeSlots {
    /// De eerste vrije momenten van `duration` op werkdagen tussen `startHour` en `endHour`, op een raster van een
    /// half uur, vanaf `from` (afgerond naar het volgende halve uur). Hooguit één moment per dag, zodat je keuze hebt.
    public static func find(busy: [DateInterval], from: Date, days: Int = 10, startHour: Int = 9, endHour: Int = 17,
                            duration: TimeInterval = 3600, workDays: Set<Int> = [2, 3, 4, 5, 6], limit: Int = 3,
                            calendar: Calendar = .current) -> [DateInterval] {
        var result: [DateInterval] = []
        let step: TimeInterval = 1800
        let earliest = Date(timeIntervalSinceReferenceDate: (from.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
        var day = calendar.startOfDay(for: from)
        for _ in 0..<days {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400) }
            guard workDays.contains(calendar.component(.weekday, from: day)),
                  let open = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
                  let close = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day) else { continue }
            var start = max(open, earliest)
            while start.addingTimeInterval(duration) <= close {
                let slot = DateInterval(start: start, duration: duration)
                if !busy.contains(where: { $0.start < slot.end && $0.end > slot.start }) {
                    result.append(slot)
                    break
                }
                start = start.addingTimeInterval(step)
            }
            if result.count >= limit { break }
        }
        return result
    }
}

// MARK: - Uitnodiging

/// Een uitnodiging als iCalendar-bestand (METHOD:REQUEST), om bij een mail te voegen: de ontvanger kan hem in zijn
/// eigen agenda accepteren.
public enum CalendarInvite {
    public static func ics(uid: String, start: Date, end: Date, title: String, organizer: MailAddress,
                           attendees: [MailAddress], description: String? = nil, now: Date = Date()) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "PRODID:-//Werkbank//NL",
            "VERSION:2.0",
            "CALSCALE:GREGORIAN",
            "METHOD:REQUEST",
            "BEGIN:VEVENT",
            "UID:\(uid)",
            "DTSTAMP:\(stamp(now))",
            "DTSTART:\(stamp(start))",
            "DTEND:\(stamp(end))",
            "SUMMARY:\(escape(title))",
            "ORGANIZER\(commonName(organizer)):mailto:\(organizer.address)",
        ]
        for attendee in attendees {
            lines.append("ATTENDEE\(commonName(attendee));ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:\(attendee.address)")
        }
        if let description, !description.isEmpty { lines.append("DESCRIPTION:\(escape(description))") }
        lines += ["SEQUENCE:0", "STATUS:CONFIRMED", "END:VEVENT", "END:VCALENDAR"]
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    private static func commonName(_ address: MailAddress) -> String {
        guard let name = address.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "" }
        return ";CN=\"\(name.replacingOccurrences(of: "\"", with: ""))\""
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Regels langer dan 75 bytes gaan verder op een nieuwe regel die met een spatie begint (RFC 5545).
    static func fold(_ line: String) -> String {
        var result = ""
        var count = 0
        for character in line {
            let size = String(character).utf8.count
            if count + size > 75 {
                result += "\r\n "
                count = 1
            }
            result.append(character)
            count += size
        }
        return result
    }
}
