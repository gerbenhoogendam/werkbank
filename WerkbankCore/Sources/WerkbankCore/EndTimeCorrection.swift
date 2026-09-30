import Foundation

public struct EndTimeEvaluation: Equatable {
    /// Eindtijd, begrensd tot [laatste start, standaard-eindtijd].
    public var end: Date
    /// De ingevoerde tijd lag buiten het toegestane bereik (veld rood).
    public var isOutOfRange: Bool
    /// Af te trekken van de gemeten tijd. Verschillen onder 1 minuut tellen niet.
    public var subtractedSeconds: TimeInterval
    /// Tijd tussen laatste start en standaard-eindtijd ("daarna 1:07 onafgebroken").
    public var continuousSeconds: TimeInterval
    /// Timer liep te lang zonder pauze en de eindtijd is niet aangepast.
    public var showsLongRunWarning: Bool
}

public enum EndTimeCorrection {
    /// - Parameters:
    ///   - lastStart: laatste (her)start van de timer.
    ///   - defaultEnd: "nu", of het pauzemoment als de timer al gepauzeerd was.
    ///   - requestedEnd: door de gebruiker gekozen eindtijd.
    ///   - warningThresholdMinutes: drempel voor de "timer liep lang"-waarschuwing.
    public static func evaluate(lastStart: Date,
                                defaultEnd: Date,
                                requestedEnd: Date,
                                warningThresholdMinutes: Int = 60) -> EndTimeEvaluation {
        let upper = max(defaultEnd, lastStart)
        // Het invoerveld heeft minuutprecisie; de laatste start telt vanaf het begin van die minuut.
        let lowerMinute = floorToMinute(lastStart)

        let isOut = requestedEnd < lowerMinute || requestedEnd > upper
        let end = min(max(requestedEnd, lastStart), upper)

        var subtracted = upper.timeIntervalSince(end)
        if subtracted < 60 { subtracted = 0 }

        let continuous = max(0, upper.timeIntervalSince(lastStart))
        let warning = continuous > Double(warningThresholdMinutes) * 60 && subtracted == 0

        return EndTimeEvaluation(end: subtracted == 0 ? upper : end,
                                 isOutOfRange: isOut,
                                 subtractedSeconds: subtracted,
                                 continuousSeconds: continuous,
                                 showsLongRunWarning: warning)
    }

    /// Zet een uu:mm-invoer om naar een datum op de dag van `reference`.
    /// Ligt het resultaat na `reference` (bijv. timer over middernacht), dan wordt de dag ervoor
    /// gebruikt als die niet vóór `notBefore` valt.
    public static func date(hour: Int, minute: Int, near reference: Date, notBefore: Date,
                            calendar: Calendar = .current) -> Date {
        guard let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: reference) else {
            return reference
        }
        if candidate > reference,
           let previous = calendar.date(byAdding: .day, value: -1, to: candidate),
           previous >= floorToMinute(notBefore, calendar: calendar) {
            return previous
        }
        return candidate
    }

    static func floorToMinute(_ date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: parts) ?? date
    }
}
