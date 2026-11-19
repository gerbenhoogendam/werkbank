import AppKit
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
    private static var keyMonitor: Any?

    /// De toets voor gelezen of ongelezen (Voorkeuren › Mail, standaard ⇧⌘U) werkt ook op de werkbank. In de
    /// mailmodus regelt de mailmodus hem zelf (`MailModeView.handle`); een toets zonder ⌘, ⌃ of ⌥ geldt alleen daar,
    /// want op de werkbank is een losse letter gewoon een letter.
    static func start() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handleUnreadKey(event) } ? nil : event
        }
    }

    private static func handleUnreadKey(_ event: NSEvent) -> Bool {
        let key = MailModeKeys.key(for: .unread)
        guard MailModeKeys.hasModifiers(key), MailModeKeys.key(from: event) == key else { return false }
        let mailMode = MailModeStore.shared
        guard !mailMode.isActive || mailMode.isReceded else { return false }
        guard let window = DuoWindowFold.shared.mainWindow, event.window === window, window.attachedSheet == nil
        else { return false }
        return toggleUnreadFocused(appState: AppState.shared)
    }

    /// Gelezen wordt ongelezen en andersom: het open gesprek (het laatst geopende mailpaneel), anders de gekozen
    /// mail in het Mail-paneel. `false`: er is geen mail om te markeren.
    @discardableResult
    static func toggleUnreadFocused(appState: AppState) -> Bool {
        let gmail = GmailSession.shared
        let openMail = PanelStore.shared.panels.reversed().lazy.compactMap { panel -> MailRef? in
            if case .mail(let ref) = panel { return ref }
            return nil
        }.first
        if let ref = openMail {
            gmail.note(account: ref.account, forMessageID: ref.messageID)
            gmail.note(account: ref.account, forMessageID: ref.threadID)
            // Staat het gesprek in de lijst, dan telt wat daar staat; een open gesprek is anders gelezen.
            let message = gmail.messages.first { $0.threadID == ref.threadID } ?? ref.summary
            Task { await gmail.toggleUnread(message, appState: appState) }
            return true
        }
        guard let id = MailSelection.shared.selectedID,
              let message = gmail.messages.first(where: { $0.id == id }) else { return false }
        Task { await gmail.toggleUnread(message, appState: appState) }
        return true
    }

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
