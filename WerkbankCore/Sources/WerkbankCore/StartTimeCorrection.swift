import Foundation

public struct StartTimeEvaluation: Equatable {
    /// Begintijd na controle (de oude begintijd als de invoer niet klopt of niet wijzigt).
    public var start: Date
    /// De ingevoerde begintijd ligt niet vóór de eindtijd.
    public var isOutOfRange: Bool
    /// Bij te tellen bij de gemeten tijd: positief bij eerder beginnen, negatief bij later beginnen.
    /// Verschillen onder 1 minuut tellen niet.
    public var adjustmentSeconds: TimeInterval
}

public enum StartTimeCorrection {
    /// - Parameters:
    ///   - firstStart: huidige begintijd van de tijdregel.
    ///   - requestedStart: door de gebruiker gekozen begintijd.
    ///   - end: eindtijd (de begintijd moet daarvoor liggen).
    ///   - measuredSeconds: gemeten tijd die er nu is; later beginnen kan er niet meer van afhalen dan dit.
    public static func evaluate(firstStart: Date, requestedStart: Date, end: Date,
                                measuredSeconds: TimeInterval) -> StartTimeEvaluation {
        guard requestedStart < end else {
            return StartTimeEvaluation(start: firstStart, isOutOfRange: true, adjustmentSeconds: 0)
        }
        let difference = firstStart.timeIntervalSince(requestedStart)   // > 0: eerder beginnen
        guard abs(difference) >= 60 else {
            return StartTimeEvaluation(start: firstStart, isOutOfRange: false, adjustmentSeconds: 0)
        }
        let adjustment = max(difference, -max(0, measuredSeconds))
        return StartTimeEvaluation(start: firstStart.addingTimeInterval(-adjustment),
                                   isOutOfRange: false, adjustmentSeconds: adjustment)
    }
}
