import AppKit
import Observation

/// Houdt bij of er een mail wordt gesleept (uit de lijst of uit een mailvenster), zodat het Claude-doel verschijnt.
/// AppKit meldt niet wanneer een sleepactie eindigt; daarom wordt de muisknop in de gaten gehouden.
@MainActor
@Observable
final class MailDragState {
    static let shared = MailDragState()

    private(set) var isDragging = false

    func begin() {
        guard !isDragging else { return }
        isDragging = true
        Task { @MainActor in
            while NSEvent.pressedMouseButtons & 1 != 0 { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(450))   // de afhandeling van de drop gaat voor
            isDragging = false
        }
    }
}
