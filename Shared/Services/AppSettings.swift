import Foundation

/// Sleutels voor @AppStorage en leestoegang voor services.
enum SettingsKey {
    static let roundingMinutes  = "roundingMinutes"
    static let agendaMode       = "agendaMode"          // "week" | "day"
    static let workDays         = "workDays"            // "1,2,3,4,5" (ISO: 1 = maandag)
    static let startHour        = "agendaStartHour"
    static let endHour          = "agendaEndHour"
    static let defaultCalendar  = "defaultCalendarID"
    static let hiddenCalendars  = "hiddenCalendarIDs"   // komma-gescheiden
    static let googleAPIKey     = "googleAPIKey"
    static let googleCX         = "googleSearchEngineID"
    static let longRunMinutes   = "longRunWarningMinutes"
    static let appearance       = "appearance"         // "system" | "light" | "dark"
}

enum AppSettings {
    private static let d = UserDefaults.standard

    static var roundingMinutes: Int {
        let v = d.integer(forKey: SettingsKey.roundingMinutes)
        return [1, 6, 15].contains(v) ? v : 15
    }

    static var startHour: Int {
        d.object(forKey: SettingsKey.startHour) as? Int ?? 8
    }

    static var endHour: Int {
        let v = d.object(forKey: SettingsKey.endHour) as? Int ?? 18
        return max(v, startHour + 1)
    }

    static var longRunMinutes: Int {
        let v = d.integer(forKey: SettingsKey.longRunMinutes)
        return v > 0 ? v : 60
    }

    static var isDayMode: Bool {
        d.string(forKey: SettingsKey.agendaMode) == "day"
    }

    /// ISO-weekdagen (1 = maandag … 7 = zondag).
    static var workDays: [Int] {
        parseWorkDays(d.string(forKey: SettingsKey.workDays))
    }

    static func parseWorkDays(_ raw: String?) -> [Int] {
        let days = (raw ?? "1,2,3,4,5").split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) }
        return days.isEmpty ? [1, 2, 3, 4, 5] : Array(Set(days)).sorted()
    }

    static var hiddenCalendarIDs: Set<String> {
        parseHidden(d.string(forKey: SettingsKey.hiddenCalendars))
    }

    static func parseHidden(_ raw: String?) -> Set<String> {
        Set((raw ?? "").split(separator: ",").map(String.init))
    }

    static var defaultCalendarID: String? {
        let v = d.string(forKey: SettingsKey.defaultCalendar)
        return (v?.isEmpty ?? true) ? nil : v
    }

    static var googleAPIKey: String { d.string(forKey: SettingsKey.googleAPIKey) ?? "" }
    static var googleCX: String { d.string(forKey: SettingsKey.googleCX) ?? "" }
}
