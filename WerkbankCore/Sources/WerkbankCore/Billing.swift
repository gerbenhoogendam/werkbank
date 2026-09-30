import Foundation

public enum Billing {
    /// Te factureren minuten: gemeten tijd, naar boven afgerond op `unitMinutes` (1, 6 of 15).
    /// De gemeten tijd wordt eerst op hele seconden afgerond, zodat ruis in de klok niet
    /// een extra eenheid kost.
    public static func billedMinutes(seconds: TimeInterval, unitMinutes: Int) -> Int {
        let unit = max(1, unitMinutes)
        let whole = Int(max(0, seconds).rounded())
        let unitSeconds = unit * 60
        let units = (whole + unitSeconds - 1) / unitSeconds
        return units * unit
    }

    public static func billedHours(seconds: TimeInterval, unitMinutes: Int) -> Double {
        Double(billedMinutes(seconds: seconds, unitMinutes: unitMinutes)) / 60
    }

    /// 0.25 → "0,25"
    public static func formatHours(_ hours: Double) -> String {
        String(format: "%.2f", hours).replacingOccurrences(of: ".", with: ",")
    }

    /// 4027 s → "1:07:07"
    public static func formatHMS(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// 4027 s → "1:07"
    public static func formatHM(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds)) / 60
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
