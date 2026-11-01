import AppKit
import Observation

/// Houdt bij of er een mail wordt gesleept (uit de lijst of uit een mailvenster), zodat het Claude-doel verschijnt en de
/// mailmodus wegzwiept. AppKit meldt niet wanneer een sleepactie eindigt; daarom worden de muisknop en Esc in de gaten
/// gehouden.
///
/// Afgebroken (Esc, of losgelaten zonder dat iets de mail aannam): de mailmodus komt meteen terug, alsof er niets is
/// gebeurd. Neergezet: de werkbank blijft staan tot Esc.
@MainActor
@Observable
final class MailDragState {
    static let shared = MailDragState()

    private(set) var isDragging = false
    /// Mailbox van de mail die gesleept wordt (die staat niet tussen de mailboxen om naartoe te verplaatsen).
    private(set) var sourceAccount: String?
    /// Een doel heeft de mail aangenomen (kolom, agenda, Claude, andere mailbox).
    @ObservationIgnored private var dropped = false
    /// Telt op per sleepactie, zodat de afloop van een vorige een nieuwe niet beëindigt.
    @ObservationIgnored private var session = 0

    func begin(account: String? = nil) {
        guard !isDragging else { return }
        isDragging = true
        sourceAccount = account
        dropped = false
        session += 1
        let current = session
        // Pas na het begin van het slepen (niet midden in de opbouw ervan), zodat de animatie gewoon loopt.
        Task { @MainActor in
            guard current == session else { return }
            MailModeStore.shared.recede()
        }
        Task { @MainActor in
            while NSEvent.pressedMouseButtons & 1 != 0 {
                guard current == session else { return }
                // Esc breekt het slepen af; die toets komt dan niet bij de app aan, dus kijken we zelf.
                if Self.escapeIsDown {
                    cancel()
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
            try? await Task.sleep(for: .milliseconds(450))   // de afhandeling van de drop gaat voor
            guard current == session else { return }
            end(cancelled: !dropped)
        }
    }

    /// Een doel neemt de mail aan; aanroepen vanuit de afhandeling van de drop.
    func noteDropped() {
        guard isDragging else { return }
        dropped = true
    }

    /// Bedacht: het slepen stopt en de mailmodus komt terug.
    func cancel() {
        guard isDragging else { return }
        end(cancelled: true)
    }

    private func end(cancelled: Bool) {
        session += 1
        isDragging = false
        sourceAccount = nil
        guard cancelled else { return }
        AppState.shared.isDropTargeted = false
        MailModeStore.shared.restore()
    }

    private static var escapeIsDown: Bool { CGEventSource.keyState(.combinedSessionState, key: 0x35) }
}
