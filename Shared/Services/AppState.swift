import Foundation
import SwiftData
import SwiftUI

struct StopContext: Identifiable, Equatable {
    let id = UUID()
    let entryID: UUID
    /// "Nu", of het pauzemoment als de timer al gepauzeerd was.
    let defaultEnd: Date
}

/// Globale UI-status die door hoofdvenster, menubalk en snelle invoer gedeeld wordt.
@MainActor
@Observable
final class AppState {
    /// Eén gedeelde instantie: hoofdvenster, menubalk en snelle invoer tonen dezelfde meldingen.
    static let shared = AppState()

    var toast: String?
    var stopContext: StopContext?
    var isDropTargeted = false

    @ObservationIgnored private var toastTask: Task<Void, Never>?

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
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
