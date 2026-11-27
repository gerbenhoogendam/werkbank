import Foundation

/// Eén afspraak uit een `.ics`-bestand (een uitnodiging uit een mail of een los bestand).
public struct ICSEvent: Equatable {
    public var uid: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String
    public var notes: String
    public var organizerName: String
    public var organizerEmail: String
    public var url: String
}

/// Een `.ics`-bestand: de methode (REQUEST, CANCEL, PUBLISH) en de afspraken erin.
public struct ICSDocument: Equatable {
    public var method: String?
    public var events: [ICSEvent]
}

/// Leest de VEVENT's uit een iCalendar-bestand (RFC 5545): gevouwen regels, tijdzones (ook de Windows-namen van
/// Outlook), hele dagen en DURATION. Herhaling en uitzonderingen worden niet uitgewerkt: alleen het eerste voorkomen.
public enum ICSParser {
    public static func parse(_ text: String, timeZone: TimeZone = .current) -> ICSDocument {
        var method: String?
        var events: [ICSEvent] = []
        var fields: [(name: String, params: [String: String], value: String)]?
        for line in unfold(text) {
            let (name, params, value) = splitLine(line)
            switch name {
            case "BEGIN" where value.uppercased() == "VEVENT":
                fields = []
            case "END" where value.uppercased() == "VEVENT":
                if let collected = fields, let event = event(from: collected, timeZone: timeZone) {
                    events.append(event)
                }
                fields = nil
            case "METHOD" where fields == nil:
                method = value.uppercased()
            default:
                fields?.append((name, params, value))
            }
        }
        return ICSDocument(method: method, events: events)
    }

    // MARK: Regels

    /// Een regel die met een spatie of tab begint hoort bij de vorige.
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(String(raw))
            }
        }
        return lines
    }

    /// `NAAM;PARAM=x;PARAM="y:z":waarde` in naam, parameters en waarde. Een dubbele punt tussen aanhalingstekens
    /// telt niet.
    static func splitLine(_ line: String) -> (String, [String: String], String) {
        var inQuotes = false
        var colon: String.Index?
        for index in line.indices {
            let char = line[index]
            if char == "\"" { inQuotes.toggle() }
            if char == ":" && !inQuotes { colon = index; break }
        }
        guard let colon else { return (line.uppercased(), [:], "") }
        let head = line[..<colon]
        let value = String(line[line.index(after: colon)...])
        var parts: [Substring] = []
        var current = ""
        inQuotes = false
        for char in head {
            if char == "\"" { inQuotes.toggle() }
            if char == ";" && !inQuotes {
                parts.append(Substring(current))
                current = ""
            } else {
                current.append(char)
            }
        }
        parts.append(Substring(current))
        let name = parts.first.map { String($0).uppercased() } ?? ""
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            params[String(pair[0]).uppercased()] = String(pair[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return (name, params, value)
    }

    static func unescape(_ text: String) -> String {
        var result = ""
        var escaping = false
        for char in text {
            if escaping {
                switch char {
                case "n", "N": result.append("\n")
                default: result.append(char)
                }
                escaping = false
            } else if char == "\\" {
                escaping = true
            } else {
                result.append(char)
            }
        }
        return result
    }

    // MARK: Afspraak

    private static func event(from fields: [(name: String, params: [String: String], value: String)],
                              timeZone: TimeZone) -> ICSEvent? {
        func field(_ name: String) -> (params: [String: String], value: String)? {
            fields.first { $0.name == name }.map { ($0.params, $0.value) }
        }
        guard let startField = field("DTSTART"),
              let parsedStart = date(startField.value, params: startField.params, timeZone: timeZone)
        else { return nil }
        let start = parsedStart.0
        let allDay = parsedStart.1
        var end: Date
        if let endField = field("DTEND"),
           let parsedEnd = date(endField.value, params: endField.params, timeZone: timeZone) {
            end = parsedEnd.0
        } else if let duration = field("DURATION").flatMap({ Self.duration($0.value) }) {
            end = start.addingTimeInterval(duration)
        } else {
            end = allDay ? start.addingTimeInterval(86_400) : start
        }
        if end < start { end = start }
        var organizerName = ""
        var organizerEmail = ""
        if let organizer = field("ORGANIZER") {
            organizerName = organizer.params["CN"] ?? ""
            let value = organizer.value
            organizerEmail = value.lowercased().hasPrefix("mailto:") ? String(value.dropFirst(7)) : value
        }
        return ICSEvent(uid: field("UID")?.value ?? "",
                        title: unescape(field("SUMMARY")?.value ?? ""),
                        start: start, end: end, isAllDay: allDay,
                        location: unescape(field("LOCATION")?.value ?? ""),
                        notes: unescape(field("DESCRIPTION")?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        organizerName: organizerName, organizerEmail: organizerEmail,
                        url: field("URL")?.value ?? "")
    }

    /// `20261127` (hele dag), `20261127T090000Z` (UTC), `20261127T090000` met of zonder TZID.
    static func date(_ value: String, params: [String: String], timeZone: TimeZone) -> (Date, Bool)? {
        let digits = value.trimmingCharacters(in: .whitespaces)
        let isDate = params["VALUE"]?.uppercased() == "DATE" || (digits.count == 8 && !digits.contains("T"))
        var zone = timeZone
        if digits.hasSuffix("Z") {
            zone = TimeZone(identifier: "UTC")!
        } else if !isDate, let id = params["TZID"], let named = zoneNamed(id) {
            zone = named
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let plain = digits.replacingOccurrences(of: "Z", with: "")
        func number(_ from: Int, _ length: Int) -> Int? {
            let chars = Array(plain)
            guard chars.count >= from + length else { return nil }
            return Int(String(chars[from..<from + length]))
        }
        guard let year = number(0, 4), let month = number(4, 2), let day = number(6, 2) else { return nil }
        var parts = DateComponents(year: year, month: month, day: day)
        if !isDate {
            guard plain.count >= 15, let hour = number(9, 2), let minute = number(11, 2) else { return nil }
            parts.hour = hour
            parts.minute = minute
            parts.second = number(13, 2) ?? 0
        }
        guard let date = calendar.date(from: parts) else { return nil }
        return (date, isDate)
    }

    /// Een IANA-naam, of een Windows-naam zoals Outlook die meestuurt.
    static func zoneNamed(_ id: String) -> TimeZone? {
        if let zone = TimeZone(identifier: id) { return zone }
        let windows: [String: String] = [
            "W. Europe Standard Time": "Europe/Amsterdam",
            "Romance Standard Time": "Europe/Paris",
            "Central Europe Standard Time": "Europe/Budapest",
            "Central European Standard Time": "Europe/Warsaw",
            "GMT Standard Time": "Europe/London",
            "Greenwich Standard Time": "Atlantic/Reykjavik",
            "E. Europe Standard Time": "Europe/Chisinau",
            "FLE Standard Time": "Europe/Kiev",
            "Eastern Standard Time": "America/New_York",
            "Central Standard Time": "America/Chicago",
            "Pacific Standard Time": "America/Los_Angeles",
            "UTC": "UTC",
        ]
        return windows[id].flatMap(TimeZone.init(identifier:))
    }

    /// `PT1H30M`, `P1D`, `P1W`, `-PT15M` in seconden.
    static func duration(_ value: String) -> TimeInterval? {
        var text = value.uppercased()
        var sign: Double = 1
        if text.hasPrefix("-") { sign = -1; text.removeFirst() } else if text.hasPrefix("+") { text.removeFirst() }
        guard text.hasPrefix("P") else { return nil }
        text.removeFirst()
        var total: Double = 0
        var number = ""
        for char in text {
            if char.isNumber { number.append(char); continue }
            let amount = Double(number) ?? 0
            number = ""
            switch char {
            case "W": total += amount * 604_800
            case "D": total += amount * 86_400
            case "H": total += amount * 3_600
            case "M": total += amount * 60
            case "S": total += amount
            case "T": break
            default: return nil
            }
        }
        return sign * total
    }
}
