import SwiftUI

// Aanvullingen op ThingsTheme.swift die Werkbank nodig heeft en die Things zelf niet kent.

extension ThingsColor {
    /// Lopende timer (pulserende stip).
    static let running = Color.dynamic(light: 0x30B550, dark: 0x3CCB5F)
    /// Foutmarkering (verplichte omschrijving, eindtijd buiten bereik) — zelfde rood als deadline.
    static let error = ThingsColor.deadline
}

/// Nederlandse datum/tijd-weergave (vaste locale, ongeacht systeemtaal).
enum DutchDate {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.dateFormat = pattern
        return f
    }

    private static let day = formatter("d MMM")
    private static let weekday = formatter("EEE")
    private static let weekdayDay = formatter("EEE d MMM")
    private static let hourMinute = formatter("HH:mm")

    private static func clean(_ s: String) -> String { s.replacingOccurrences(of: ".", with: "") }

    /// "28 sep"
    static func short(_ d: Date) -> String { clean(day.string(from: d)) }
    /// "ma"
    static func weekdayShort(_ d: Date) -> String { clean(weekday.string(from: d)) }
    /// "di 29 sep"
    static func weekdayAndDay(_ d: Date) -> String { clean(weekdayDay.string(from: d)) }
    /// "09:15"
    static func time(_ d: Date) -> String { hourMinute.string(from: d) }
    /// "09:15–10:15"
    static func range(_ a: Date, _ b: Date) -> String { "\(time(a))–\(time(b))" }

    static func isoWeek(_ d: Date) -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: d)
    }
}

/// Korte schudanimatie bij een ongeldige invoer.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 7
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * .pi * 2), y: 0))
    }
}
