import AppKit
import CoreGraphics
import SwiftData

/// Inactiviteit tijdens een lopende timer. Is de Mac 10 minuten of langer niet gebruikt (of slaapt hij), dan vraagt de
/// timer-pil bij terugkomst of die tijd eraf moet.
@MainActor
final class IdleWatcher {
    static let shared = IdleWatcher()
    static let threshold: TimeInterval = 600

    /// Begin van de inactiviteit en de timers die toen liepen.
    private var idleStart: Date?
    private var entryIDs: [UUID] = []
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
        let running = TimerService.runningEntries(in: context)
        guard idleStart == nil, !running.isEmpty else { return }
        idleStart = start
        entryIDs = running.map(\.id)
    }

    private func returned(at end: Date) {
        guard let start = idleStart else { return }
        let ids = entryIDs.filter { TimerService.entry(withID: $0, in: context)?.status == .running }
        idleStart = nil
        entryIDs = []
        guard end.timeIntervalSince(start) >= Self.threshold, !ids.isEmpty else { return }
        AppState.shared.idlePrompt = IdlePrompt(entryIDs: ids, start: start, end: end)
    }

    /// "Eraf": de tijd telt niet mee, alsof de timers al die tijd op pauze stonden. ⌘Z zet het terug.
    func subtract(_ prompt: IdlePrompt) {
        AppState.shared.idlePrompt = nil
        var amounts: [(id: UUID, seconds: TimeInterval)] = []
        for id in prompt.entryIDs {
            guard let entry = TimerService.entry(withID: id, in: context) else { continue }
            let seconds = min(prompt.duration, max(0, entry.elapsed()))
            if seconds > 0 { amounts.append((id, seconds)) }
        }
        guard let longest = amounts.map(\.seconds).max() else { return }
        for item in amounts { apply(-item.seconds, to: item.id) }
        UndoCenter.shared.record("Inactieve tijd aftrekken",
                                 undo: { for item in amounts { IdleWatcher.shared.apply(item.seconds, to: item.id) } },
                                 redo: { for item in amounts { IdleWatcher.shared.apply(-item.seconds, to: item.id) } })
        AppState.shared.announce("\(Int((longest / 60).rounded())) min afgetrokken")
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
