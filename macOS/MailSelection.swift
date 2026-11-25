import AppKit
import Foundation
import Observation
import WerkbankCore

/// De gekozen mails in het Gmail-paneel (gedeeld, zodat ⇧⌘A ook werkt als het paneel niet de focus heeft).
/// Klik kiest één mail, ⌘-klik zet er een bij of haalt hem eruit, ⇧-klik kiest alles tussen de vorige klik en deze.
@MainActor
@Observable
final class MailSelection {
    static let shared = MailSelection()
    /// De laatst aangeklikte mail. Op nil of een andere mail zetten (van buiten) maakt de keuze weer één mail.
    var selectedID: String? {
        didSet {
            guard let selectedID else {
                selectedIDs = []
                return
            }
            if !selectedIDs.contains(selectedID) { selectedIDs = [selectedID] }
        }
    }
    private(set) var selectedIDs: Set<String> = []
    @ObservationIgnored private var anchorID: String?

    /// Een klik op een mail in de lijst (`order`: de mails zoals ze onder elkaar staan).
    func click(_ id: String, in order: [String]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
                selectedID = selectedIDs.isEmpty ? nil : order.last { selectedIDs.contains($0) }
            } else {
                selectedIDs.insert(id)
                selectedID = id
            }
            anchorID = id
        } else if flags.contains(.shift), let anchorID, let from = order.firstIndex(of: anchorID),
                  let to = order.firstIndex(of: id) {
            selectedIDs = Set(order[min(from, to)...max(from, to)])
            selectedID = id
        } else {
            selectedIDs = [id]
            selectedID = id
            anchorID = id
        }
    }

    /// De gekozen mails die nog in de lijst staan, in de volgorde van de lijst.
    func selected(in messages: [GmailMessageSummary]) -> [GmailMessageSummary] {
        messages.filter { selectedIDs.contains($0.id) }
    }
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
        IdleSearchReset.start()
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
        let chosen = MailSelection.shared.selected(in: gmail.messages)
        if chosen.count > 1 {
            // Meer mails: staat er één ongelezen tussen, dan alles gelezen; anders alles ongelezen.
            setUnread(!chosen.contains(where: \.isUnread), chosen, appState: appState)
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
        let chosen = MailSelection.shared.selected(in: gmail.messages)
        if chosen.count > 1 {
            archive(chosen, appState: appState)
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

    /// Meer gekozen mails archiveren; daarna is de mail onder de laatste gekozen.
    static func archive(_ messages: [GmailMessageSummary], appState: AppState) {
        let gmail = GmailSession.shared
        let ids = Set(messages.map(\.id))
        let lastIndex = gmail.messages.lastIndex { ids.contains($0.id) }
        let next = lastIndex.flatMap { index in gmail.messages[(index + 1)...].first { !ids.contains($0.id) }?.id }
        MailSelection.shared.selectedID = next
        Task {
            for message in messages { await gmail.archiveMessage(message, appState: appState, announce: false) }
            appState.showToast(messages.count == 1 ? "Mail gearchiveerd in Gmail" : "\(messages.count) mails gearchiveerd in Gmail")
        }
    }

    /// Meer gekozen mails op gelezen of ongelezen.
    static func setUnread(_ unread: Bool, _ messages: [GmailMessageSummary], appState: AppState) {
        let gmail = GmailSession.shared
        Task {
            let threads = messages.map { (threadID: $0.threadID, account: gmail.account(for: $0.id)) }
            let done = await gmail.setUnread(unread, threads: threads)
            appState.showToast("\(done) \(done == 1 ? "mail" : "mails") \(unread ? "ongelezen" : "gelezen")")
        }
    }
}

/// Een minuut niets gedaan in Werkbank (geen toets, klik of scroll in een van zijn vensters, of een andere app voor):
/// een zoekopdracht in de mailmodus gaat weg, zodat de mail bij terugkomst niet half gefilterd staat. Filters (zoals
/// Ongelezen) en een gekozen klant blijven.
@MainActor
enum IdleSearchReset {
    static let interval: TimeInterval = 60
    private static var lastInput = Date()
    private static var monitor: Any?
    private static var loop: Task<Void, Never>?

    static func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { event in
            MainActor.assumeIsolated { lastInput = Date() }
            return event
        }
        loop = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                check()
            }
        }
    }

    private static func check() {
        guard Date().timeIntervalSince(lastInput) >= interval else { return }
        let store = MailModeStore.shared
        if store.hasSearch { store.clearSearch() }
        if !store.clientQuery.isEmpty { store.clientQuery = "" }
    }
}
