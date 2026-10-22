import AppKit
import CoreGraphics
import SwiftData

/// Inactiviteit tijdens een lopende timer. Is de Mac 10 minuten of langer niet gebruikt (of slaapt hij), dan vraagt de
/// timer-pil bij terugkomst of die tijd eraf moet.
@MainActor
final class IdleWatcher {
    static let shared = IdleWatcher()
    static let threshold: TimeInterval = 600

    /// Begin van de inactiviteit en de timer die toen liep.
    private var idleStart: Date?
    private var entryID: UUID?
    private var task: Task<Void, Never>?
    private var context: ModelContext { Persistence.container.mainContext }

    func start() {
        guard task == nil else { return }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated { IdleWatcher.shared.markAway(since: .now) }
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self?.tick()
            }
        }
    }

    /// Seconden sinds de laatste muis- of toetsenbordactie.
    private static var secondsIdle: TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown, .flagsChanged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    private func tick() {
        let idle = Self.secondsIdle
        if idleStart == nil {
            if idle >= Self.threshold { markAway(since: Date().addingTimeInterval(-idle)) }
        } else if idle < 30 {
            returned(at: Date().addingTimeInterval(-idle))
        }
    }

    private func markAway(since start: Date) {
        guard idleStart == nil, let running = TimerService.runningEntry(in: context) else { return }
        idleStart = start
        entryID = running.id
    }

    private func returned(at end: Date) {
        guard let start = idleStart, let id = entryID else { return }
        idleStart = nil
        entryID = nil
        guard end.timeIntervalSince(start) >= Self.threshold,
              let entry = TimerService.entry(withID: id, in: context), entry.status == .running else { return }
        AppState.shared.idlePrompt = IdlePrompt(entryID: id, start: start, end: end)
    }

    /// "Eraf": de tijd telt niet mee, alsof de timer al die tijd op pauze stond. ⌘Z zet hem terug.
    func subtract(_ prompt: IdlePrompt) {
        AppState.shared.idlePrompt = nil
        guard let entry = TimerService.entry(withID: prompt.entryID, in: context) else { return }
        let seconds = min(prompt.duration, max(0, entry.elapsed()))
        guard seconds > 0 else { return }
        let id = prompt.entryID
        apply(-seconds, to: id)
        UndoCenter.shared.record("Inactieve tijd aftrekken",
                                 undo: { IdleWatcher.shared.apply(seconds, to: id) },
                                 redo: { IdleWatcher.shared.apply(-seconds, to: id) })
        AppState.shared.announce("\(Int((seconds / 60).rounded())) min afgetrokken")
    }

    func keep() {
        AppState.shared.idlePrompt = nil
    }

    private func apply(_ delta: TimeInterval, to id: UUID) {
        guard let entry = TimerService.entry(withID: id, in: context) else { return }
        entry.accumulated += delta
        entry.pausedTotal = max(0, entry.pausedTotal - delta)
        entry.interruptions = max(0, entry.interruptions + (delta < 0 ? 1 : -1))
        TimerService.save(context)
    }
}
