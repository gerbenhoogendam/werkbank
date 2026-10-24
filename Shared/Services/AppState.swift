import Foundation
import SwiftData
import SwiftUI

struct StopContext: Identifiable, Equatable {
    let id = UUID()
    let entryID: UUID
    /// "Nu", of het pauzemoment als de timer al gepauzeerd was.
    let defaultEnd: Date
}

/// Was de Mac een tijd niet in gebruik terwijl de timer liep: die tijd aftrekken of laten staan.
struct IdlePrompt: Equatable {
    /// De timers die liepen toen de Mac niet gebruikt werd.
    let entryIDs: [UUID]
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var minutes: Int { Int((duration / 60).rounded()) }
}

/// Na versturen (macOS): even de kans om het gesprek met Enter te archiveren; de timer-pil telt af.
struct HudCountdown: Equatable {
    let id = UUID()
    let start: Date
    let duration: TimeInterval
    /// Enter op tijd: gearchiveerd.
    var isDone = false
}

/// Globale UI-status die door hoofdvenster, menubalk en snelle invoer gedeeld wordt.
@MainActor
@Observable
final class AppState {
    /// Eén gedeelde instantie: hoofdvenster, menubalk en snelle invoer tonen dezelfde meldingen.
    static let shared = AppState()

    var toast: String?
    /// Korte melding in de zwevende timer-pil (bijvoorbeeld "Taak afronden ongedaan", "Mail verzonden").
    var hudMessage: String?
    /// Aftellen onder de melding in de timer-pil (`SendFollowUp`).
    var hudCountdown: HudCountdown?
    /// Vraag in de timer-pil na inactiviteit (macOS); blijft staan tot er gekozen is.
    var idlePrompt: IdlePrompt?
    var stopContext: StopContext?
    var isDropTargeted = false

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var hudTask: Task<Void, Never>?

    func announce(_ message: String, seconds: Double = 2.5) {
        hudMessage = message
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hudMessage = nil
        }
    }

    func showToast(_ message: String, seconds: Double = 2) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// Bevriest de timer en opent de stopsheet ("Werkzaamheden omschrijven").
    func requestStop(_ entry: TimeEntry, in context: ModelContext) {
        let end = TimerService.freezeForStop(entry, in: context)
        stopContext = StopContext(entryID: entry.id, defaultEnd: end)
    }
}

struct ToastOverlay: View {
    let message: String?

    var body: some View {
        VStack {
            Spacer()
            if let message {
                Text(message)
                    .thingsFont(.todoTitleOpen)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: message)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
