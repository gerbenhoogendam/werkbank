import Foundation
import Observation

/// De aangeklikte mail in het Gmail-paneel (gedeeld, zodat ⇧⌘A ook werkt als het paneel niet de focus heeft).
@MainActor
@Observable
final class MailSelection {
    static let shared = MailSelection()
    var selectedID: String?
}

enum MailSettings {
    /// `true`: in een gesprek staat de nieuwste mail onderaan (met het antwoord eronder).
    static let newestAtBottomKey = "mail.newestAtBottom"
}

/// Sneltoetsen voor mail die overal in het hoofdvenster werken.
@MainActor
enum MailCommands {
    /// ⇧⌘A: archiveert het open gesprek (het laatst geopende mailpaneel), anders de geselecteerde mail in de zijbalk.
    static func archiveFocused(appState: AppState) {
        let gmail = GmailSession.shared
        let openMail = PanelStore.shared.panels.reversed().lazy.compactMap { panel -> MailRef? in
            if case .mail(let ref) = panel { return ref }
            return nil
        }.first
        if let ref = openMail {
            gmail.note(account: ref.account, forMessageID: ref.messageID)
            gmail.note(account: ref.account, forMessageID: ref.threadID)
            PanelStore.shared.closeMail(messageID: ref.messageID)
            Task { await gmail.archiveMessage(ref.summary, appState: appState) }
            return
        }
        guard let id = MailSelection.shared.selectedID,
              let index = gmail.messages.firstIndex(where: { $0.id == id }) else {
            appState.showToast("Geen mail geselecteerd")
            return
        }
        let message = gmail.messages[index]
        // De volgende mail wordt geselecteerd, zodat je door kunt.
        let next = gmail.messages.indices.contains(index + 1) ? gmail.messages[index + 1].id
            : (index > 0 ? gmail.messages[index - 1].id : nil)
        MailSelection.shared.selectedID = next
        Task { await gmail.archiveMessage(message, appState: appState) }
    }
}
