import Foundation

/// De tellers boven de maandagenda: hoeveel afspraken, hoeveel uur er gepland staat en hoeveel werkdagen helemaal vrij
/// zijn. Alleen werkdagen en alleen binnen de werkuren (Voorkeuren › Agenda): een afspraak 's avonds telt niet.
public enum MonthAgendaStats {
    public struct Slot: Equatable {
        public var start: Date
        public var end: Date
        public var isAllDay: Bool

        public init(start: Date, end: Date, isAllDay: Bool) {
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
        }
    }

    public struct Result: Equatable {
        /// Afspraken met een tijd die (deels) binnen de werkuren van een werkdag vallen; elke afspraak één keer.
        public var appointments: Int
        /// Uren waarin iets gepland staat; afspraken die elkaar overlappen tellen één keer.
        public var plannedHours: Double
        /// Werkdagen zonder één afspraak met een tijd binnen de werkuren. Een afspraak voor de hele dag (vakantie,
        /// vrij) maakt een dag niet bezet.
        public var freeDays: Int
    }

    public static func compute(_ slots: [Slot], days: [Date], startHour: Int, endHour: Int,
                               calendar: Calendar) -> Result {
        let timed = slots.filter { !$0.isAllDay && $0.end > $0.start }
        var counted = Set<Int>()
        var seconds: TimeInterval = 0
        var free = 0
        for day in days {
            let midnight = calendar.startOfDay(for: day)
            guard let open = calendar.date(byAdding: .hour, value: startHour, to: midnight),
                  let close = calendar.date(byAdding: .hour, value: endHour, to: midnight), close > open else { continue }
            var pieces: [(Date, Date)] = []
            for (index, slot) in timed.enumerated() {
                let from = max(slot.start, open)
                let to = min(slot.end, close)
                guard to > from else { continue }
                pieces.append((from, to))
                counted.insert(index)
            }
            if pieces.isEmpty { free += 1 }
            seconds += covered(pieces)
        }
        return Result(appointments: counted.count, plannedHours: seconds / 3600, freeDays: free)
    }

    /// De tijd die de stukken samen beslaan, waarbij overlap één keer telt.
    private static func covered(_ pieces: [(Date, Date)]) -> TimeInterval {
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for piece in pieces.sorted(by: { $0.0 < $1.0 }) {
            if let open = current, piece.0 <= open.1 {
                current = (open.0, max(open.1, piece.1))
            } else {
                if let open = current { total += open.1.timeIntervalSince(open.0) }
                current = piece
            }
        }
        if let open = current { total += open.1.timeIntervalSince(open.0) }
        return total
    }

    /// Uren zoals ze in de kop staan: hele uren vanaf tien, daaronder met een halve ("7,5").
    public static func hoursText(_ hours: Double) -> String {
        if hours >= 10 { return String(Int(hours.rounded())) }
        let halves = (hours * 2).rounded() / 2
        if halves == halves.rounded() { return String(Int(halves)) }
        return String(format: "%.1f", halves).replacingOccurrences(of: ".", with: ",")
    }
}
