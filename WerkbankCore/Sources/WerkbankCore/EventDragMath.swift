import Foundation

/// Nieuwe tijden van een afspraak die je in de agenda versleept. Alles in minuten sinds middernacht van de dag waarop
/// je hem pakte (een afspraak die de dag ervoor begon heeft een negatief begin); `visible` zijn de zichtbare uren.
public enum EventDragMath {
    public enum Edge: Sendable { case start, end }

    /// Het hele blok `delta` minuten verschoven, met het begin op een kwartier. Het begin blijft binnen de zichtbare
    /// uren (minstens een kwartier zichtbaar), tenzij het daar al buiten lag. Een afspraak over meerdere dagen schuift
    /// vrij.
    public static func moved(start: Int, end: Int, delta: Int, visible: ClosedRange<Int>) -> (start: Int, end: Int) {
        let duration = end - start
        var newStart = Scheduling.snapNearest(minutes: start + delta)
        if start >= 0, end <= 24 * 60 {
            let lower = min(visible.lowerBound, start)
            let upper = max(visible.upperBound - Scheduling.step, start)
            newStart = min(max(newStart, lower), upper)
        }
        return (newStart, newStart + duration)
    }

    /// De boven- of onderrand naar `pointer`, op een kwartier, minstens een kwartier lang en binnen de zichtbare uren
    /// (of de oorspronkelijke tijd, als die daarbuiten lag).
    public static func resized(start: Int, end: Int, edge: Edge, pointer: Int,
                               visible: ClosedRange<Int>) -> (start: Int, end: Int) {
        let snapped = Scheduling.snapNearest(minutes: pointer)
        switch edge {
        case .start:
            let lower = min(visible.lowerBound, start)
            return (min(max(snapped, lower), end - Scheduling.step), end)
        case .end:
            let upper = max(visible.upperBound, end)
            return (start, max(min(snapped, upper), start + Scheduling.step))
        }
    }
}
