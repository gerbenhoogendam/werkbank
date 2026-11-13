import AppKit
import UserNotifications
import WerkbankCore

/// Meldingen van nieuwe mail: een melding van macOS per nieuwe mail en het aantal ongelezen mails op het Dock-icoon.
/// Alleen voor de mailboxen die in Voorkeuren › Mail zijn aangezet, en niet voor nieuwsbrieven en meldingen (wat de
/// mailmodus in de bundel zet). Kijkt elke minuut, ook als het hoofdvenster dicht is of de mailmodus niet open staat:
/// Gmail stuurt deze app zelf niets.
@MainActor
final class MailNotifier {
    static let shared = MailNotifier()

    /// De mailboxen met meldingen (Voorkeuren › Mail); gaat mee naar je andere Macs.
    static let accountsKey = "mail.notifyAccounts"
    private static let interval: Duration = .seconds(60)
    /// Komen er meer nieuwe mails tegelijk binnen dan dit (na de slaapstand), dan één melding met het aantal.
    private static let burstLimit = 4

    private let delegate = NotificationDelegate()
    private var loop: Task<Void, Never>?
    private var soon: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var isChecking = false
    private var askedPermission = false
    /// Per mailbox: ongelezen in de inbox, zonder nieuwsbrieven en meldingen. Dit telt het Dock-icoon.
    private var unread: [String: [GmailMailItem]] = [:]
    /// Per mailbox: de koppen van alle ongelezen mail van de vorige keer, zodat die niet opnieuw opgehaald worden.
    private var known: [String: [String: GmailMailItem]] = [:]
    /// Per mailbox: wanneer er voor het laatst is gekeken. Nog niet gekeken: dan is alles wat er staat de beginstand
    /// en komt er geen melding.
    private var lastCheck: [String: Date] = [:]
    private var notified: Set<String> = []
    /// Gesprekken die net in de app zijn gelezen of weggehaald: een controle die al onderweg was telt ze niet meer mee.
    private var handled: [String: Date] = [:]

    // MARK: Instelling

    /// De mailboxen waarvoor meldingen aan staan. Zolang je niets kiest: de werkmailboxen (gh@, support@ en info@,
    /// `MailClientSettings.preferred`).
    static var accounts: [String] {
        let all = GmailSession.shared.accounts
        if let stored = UserDefaults.standard.stringArray(forKey: accountsKey) { return all.filter(stored.contains) }
        return MailClientSettings.preferred
    }

    static func set(_ account: String, notifies: Bool) {
        var list = accounts.filter { $0 != account }
        if notifies { list.append(account) }
        UserDefaults.standard.set(list, forKey: accountsKey)
        shared.checkSoon()
    }

    /// Staan meldingen voor Werkbank uit in Systeeminstellingen?
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Kijken

    func start() {
        guard loop == nil else { return }
        UNUserNotificationCenter.current().delegate = delegate
        loop = Task { [weak self] in
            // Even na het starten: inloggen en de eerste lijsten gaan voor.
            try? await Task.sleep(for: .seconds(6))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.interval)
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { MailNotifier.shared.checkSoon() }
        }
    }

    /// Na een handeling in de app (weer op ongelezen gezet, een andere keuze in Voorkeuren) of na de slaapstand:
    /// binnen een paar seconden opnieuw kijken in plaats van pas bij de volgende minuut.
    func checkSoon() {
        soon?.cancel()
        soon = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.check()
        }
    }

    private func check() async {
        let gmail = GmailSession.shared
        guard gmail.state == .signedIn, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let accounts = Self.accounts
        for account in Array(unread.keys) where !accounts.contains(account) { forget(account) }
        guard !accounts.isEmpty else {
            updateBadge()
            return
        }
        await askPermission()
        let startedAt = Date()
        var arrived = false
        await withTaskGroup(of: (String, [GmailMailItem]?).self) { group in
            for account in accounts {
                let cached = known[account] ?? [:]
                group.addTask { (account, try? await gmail.unreadInbox(account: account, known: cached)) }
            }
            for await (account, items) in group {
                // Niet bereikbaar: laten staan wat er stond.
                guard let items else { continue }
                if apply(items, account: account, startedAt: startedAt, mailboxes: accounts.count) { arrived = true }
            }
        }
        updateBadge()
        if arrived {
            // De lijsten meteen bij: wie op de melding klikt, vindt de mail.
            MailModeStore.shared.refreshIfStale(after: 0)
            await gmail.reloadIfStale(after: 0)
        }
    }

    /// Verwerkt wat er nu ongelezen in de inbox van een mailbox staat. `true`: er is nieuwe mail gemeld.
    private func apply(_ items: [GmailMailItem], account: String, startedAt: Date, mailboxes: Int) -> Bool {
        known[account] = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recently = Date().addingTimeInterval(-20)
        handled = handled.filter { $0.value > recently }
        let wanted = items.filter { !MailModeStore.shared.isNewsletter($0) && handled[$0.threadID] == nil }
        // Elders gelezen of gearchiveerd (telefoon, Gmail): de melding kan uit Berichtencentrum.
        let gone = Set((unread[account] ?? []).map(\.id)).subtracting(wanted.map(\.id))
        if !gone.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: gone.map(Self.identifier))
        }
        var fresh: [GmailMailItem] = []
        if let since = lastCheck[account] {
            fresh = MailNotices.fresh(wanted, notified: notified, since: since)
            announce(fresh, account: account, mailboxes: mailboxes)
        }
        notified.formUnion(wanted.map(\.id))
        lastCheck[account] = startedAt
        unread[account] = wanted
        return !fresh.isEmpty
    }

    private func forget(_ account: String) {
        let ids = (unread[account] ?? []).map(\.id)
        if !ids.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids.map(Self.identifier))
        }
        unread[account] = nil
        known[account] = nil
        lastCheck[account] = nil
    }

    /// Een gesprek is in de app gelezen, gearchiveerd of weggehaald: meteen van het Dock-icoon af en de melding uit
    /// Berichtencentrum.
    func noteHandled(threadID: String) {
        var ids: [String] = []
        for account in Array(unread.keys) {
            ids += (unread[account] ?? []).filter { $0.threadID == threadID }.map(\.id)
            unread[account]?.removeAll { $0.threadID == threadID }
        }
        handled[threadID] = Date()
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids.map(Self.identifier))
        updateBadge()
    }

    // MARK: Melden

    private func askPermission() async {
        guard !askedPermission else { return }
        askedPermission = true
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    private static func identifier(_ messageID: String) -> String { "mail:" + messageID }

    private func announce(_ fresh: [GmailMailItem], account: String, mailboxes: Int) {
        guard !fresh.isEmpty else { return }
        let mailbox = GmailSession.shared.displayName(account)
        let center = UNUserNotificationCenter.current()
        if fresh.count > Self.burstLimit, let newest = fresh.last {
            let summary = MailNotices.summary(fresh, mailbox: mailboxes > 1 ? mailbox : "")
            let content = UNMutableNotificationContent()
            content.title = summary.title
            content.body = summary.body
            content.sound = .default
            content.threadIdentifier = account
            content.userInfo = ["account": account, "messageID": newest.id, "threadID": newest.threadID]
            center.add(UNNotificationRequest(identifier: "mail-samen:" + newest.id, content: content, trigger: nil))
            return
        }
        for item in fresh {
            let text = MailNotices.text(for: item, mailbox: mailboxes > 1 ? mailbox : nil)
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.subtitle = text.subtitle
            content.body = text.body
            content.sound = .default
            content.threadIdentifier = account
            content.userInfo = ["account": account, "messageID": item.id, "threadID": item.threadID]
            center.add(UNNotificationRequest(identifier: Self.identifier(item.id), content: content, trigger: nil))
        }
    }

    private func updateBadge() {
        let accounts = Self.accounts
        let count = accounts.reduce(0) { $0 + (unread[$1]?.count ?? 0) }
        NSApp.dockTile.badgeLabel = MailNotices.badge(count)
    }

    /// Op een melding geklikt: het hoofdvenster naar voren, de mailmodus op die mailbox en die mail gekozen.
    fileprivate func opened(messageID: String?, threadID: String?, account: String) {
        WindowRouter.focusMain()
        NSApp.activate(ignoringOtherApps: true)
        MailModeStore.shared.show(messageID: messageID, threadID: threadID, account: account)
    }
}

/// Wat macOS over de meldingen vraagt. Los van de hoofdthread: macOS roept dit op een eigen moment aan.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Ook tonen als Werkbank op de voorgrond staat (je kijkt dan lang niet altijd naar de mail).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let account = info["account"] as? String
        let messageID = info["messageID"] as? String
        let threadID = info["threadID"] as? String
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier, let account {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MailNotifier.shared.opened(messageID: messageID, threadID: threadID, account: account)
                }
            }
        }
        completionHandler()
    }
}
