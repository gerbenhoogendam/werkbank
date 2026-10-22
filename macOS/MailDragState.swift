import AppKit
import Observation

/// Houdt bij of er een mail wordt gesleept (uit de lijst of uit een mailvenster), zodat het Claude-doel verschijnt.
/// AppKit meldt niet wanneer een sleepactie eindigt; daarom wordt de muisknop in de gaten gehouden.
@MainActor
@Observable
final class MailDragState {
    static let shared = MailDragState()

    private(set) var isDragging = false
    /// Mailbox van de mail die gesleept wordt (die staat niet tussen de mailboxen om naartoe te verplaatsen).
    private(set) var sourceAccount: String?

    func begin(account: String? = nil) {
        guard !isDragging else { return }
        isDragging = true
        sourceAccount = account
        Task { @MainActor in
            while NSEvent.pressedMouseButtons & 1 != 0 { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(450))   // de afhandeling van de drop gaat voor
            isDragging = false
            sourceAccount = nil
        }
    }
}
