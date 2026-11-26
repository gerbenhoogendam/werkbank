import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

/// Mail in kolommen: het hele venster toont de inboxen van een paar mailboxen naast elkaar. Klik op een mailbox bovenin
/// toont alleen die, ⌘-klik zet er een bij of haalt hem weg (wordt onthouden). Een klik kiest een mail, dubbelklik
/// opent hem als paneel; een mail naar een andere kolom slepen verhuist het gesprek naar die mailbox.
@MainActor
@Observable
final class MailColumnsStore {
    static let shared = MailColumnsStore()
    static let accountsKey = "mailColumns.accounts"

    private(set) var isActive = false
    /// De gekozen mailboxen (leeg: de eerste drie).
    private(set) var chosen: [String] = UserDefaults.standard.stringArray(forKey: MailColumnsStore.accountsKey) ?? []
    private(set) var lists: [String: [GmailMailItem]] = [:]
    private(set) var loading: Set<String> = []
    private(set) var errors: [String: String] = [:]
    var selectedID: String?
    /// De kolom waar een mail boven hangt tijdens het slepen.
    var dropTarget: String?

    private let gmail = GmailSession.shared

    /// De kolommen, in de volgorde van de mailboxen.
    var shown: [String] {
        let all = gmail.accounts
        let picked = all.filter { chosen.contains($0) }
        return picked.isEmpty ? Array(all.prefix(3)) : picked
    }

    var unreadCount: Int { shown.reduce(0) { $0 + (lists[$1]?.filter(\.isUnread).count ?? 0) } }

    func toggle() { isActive ? close() : open() }

    func open() {
        if MailModeStore.shared.isActive { MailModeStore.shared.close() }
        withAnimation(.easeOut(duration: 0.2)) { isActive = true }
        Task { await reloadAll() }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.2)) { isActive = false }
        selectedID = nil
    }

    /// Klik op een mailbox: alleen die. ⌘-klik: erbij of eraf (de laatste blijft staan).
    func tap(_ account: String) {
        var current = shown
        if NSEvent.modifierFlags.contains(.command) {
            if let index = current.firstIndex(of: account) {
                guard current.count > 1 else { return }
                current.remove(at: index)
            } else {
                current.append(account)
            }
        } else {
            current = [account]
        }
        chosen = gmail.accounts.filter { current.contains($0) }
        UserDefaults.standard.set(chosen, forKey: Self.accountsKey)
        if lists[account] == nil, shown.contains(account) { Task { await reload(account) } }
    }

    // MARK: Lijsten

    func reloadAll() async {
        await withTaskGroup(of: Void.self) { group in
            for account in shown { group.addTask { await self.reload(account) } }
        }
    }

    func reload(_ account: String) async {
        loading.insert(account)
        defer { loading.remove(account) }
        do {
            let items = try await gmail.mailItems(MailSearch.request(text: "", folder: .inbox), account: account,
                                                  maxResults: 50)
            for item in items {
                gmail.note(account: account, forMessageID: item.id)
                gmail.note(account: account, forMessageID: item.threadID)
            }
            lists[account] = items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            errors[account] = nil
        } catch {
            errors[account] = error.localizedDescription
        }
    }

    /// Gearchiveerd of verplaatst (waar dan ook in de app): uit de kolommen.
    func removeThread(_ threadID: String) {
        for key in Array(lists.keys) { lists[key]?.removeAll { $0.threadID == threadID } }
    }

    /// Gelezen of ongelezen gezet (waar dan ook in de app).
    func noteUnread(_ unread: Bool, threadID: String) {
        for key in Array(lists.keys) {
            guard let index = lists[key]?.firstIndex(where: { $0.threadID == threadID }) else { continue }
            var labels = lists[key]?[index].labels.filter { $0 != "UNREAD" } ?? []
            if unread { labels.append("UNREAD") }
            lists[key]?[index].labels = labels
        }
    }

    func account(of threadID: String) -> String? {
        lists.first { $0.value.contains { $0.threadID == threadID } }?.key
    }

    // MARK: Handelingen

    func archive(_ item: GmailMailItem) {
        if selectedID == item.id { selectedID = nil }
        Task { await gmail.archiveMessage(item.summary, appState: AppState.shared) }
    }

    /// Een mail op een andere kolom laten vallen: het gesprek verhuist naar die mailbox.
    func move(threadID: String, messageID: String, to target: String) {
        guard let source = account(of: threadID), source != target else { return }
        PanelStore.shared.closeMail(messageID: messageID, snapshot: false)
        lists[source]?.removeAll { $0.threadID == threadID }
        Task {
            await gmail.moveThread(threadID: threadID, messageID: messageID, from: source, to: target,
                                   appState: AppState.shared)
            await reload(target)
            await reload(source)
        }
    }
}

// MARK: - Weergave

struct MailColumnsView: View {
    private let store = MailColumnsStore.shared
    private let gmail = GmailSession.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HStack(alignment: .top, spacing: 10) {
                ForEach(store.shown, id: \.self) { account in
                    MailColumn(account: account)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(ThingsColor.mailBackground)
        .task { await store.reloadAll() }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            // Terug naar de werkbank (ook met Esc of ⌘1).
            Button {
                store.close()
            } label: {
                Image(systemName: "rectangle.split.3x1.fill")
                    .font(.werk(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(ThingsColor.onAccent)
                    .background(RoundedRectangle(cornerRadius: min(6, ThingsMetrics.cardRadius), style: .continuous)
                        .fill(ThemeStore.shared.look == .etiket ? Etiket.lime : ThingsColor.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Kolommen sluiten (Esc)")
            MailHeaderTitle(title: "Mail", unread: store.unreadCount, total: 0, mailbox: "")
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: 4) {
                ForEach(gmail.accounts, id: \.self) { account in
                    MailboxTab(title: gmail.displayName(account), isOn: store.shown.contains(account), fitsContent: true) {
                        store.tap(account)
                    }
                    .help("\(account) · ⌘-klik om erbij te zetten of weg te halen")
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await store.reloadAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Verversen")
            Button {
                DefaultMailApp.composeNew()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("Nieuwe mail (⌘N)")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

/// Eén mailbox: de naam, het aantal ongelezen en de inbox.
private struct MailColumn: View {
    let account: String
    private let store = MailColumnsStore.shared
    private let gmail = GmailSession.shared

    private var items: [GmailMailItem] { store.lists[account] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                ThemedHeading(title: gmail.displayName(account))
                Spacer(minLength: 6)
                let unread = items.filter(\.isUnread).count
                if unread > 0 {
                    Text(unread == 1 ? "1 ongelezen" : "\(unread) ongelezen")
                        .font(.werk(size: 11, weight: .semibold))
                        .foregroundStyle(Color.fieldLabel)
                }
                if store.loading.contains(account) { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            if let error = store.errors[account], items.isEmpty {
                Text(error)
                    .font(.werk(size: 11.5))
                    .foregroundStyle(ThingsColor.deadline)
                    .padding(12)
            }
            ScrollView {
                LazyVStack(spacing: MailLook.cardRows ? 2 : 0) {
                    ForEach(items) { item in
                        GmailRow(message: item.summary,
                                 isBusy: gmail.busyMessageIDs.contains(item.id),
                                 isSelected: store.selectedID == item.id,
                                 onSelect: { store.selectedID = item.id },
                                 onArchive: { store.archive(item) },
                                 onDragStarted: {})
                        if !MailLook.cardRows {
                            Rectangle().fill(ThingsColor.separator).frame(height: 1).padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.horizontal, MailLook.cardRows ? 6 : 0)
                .padding(.vertical, MailLook.cardRows ? 4 : 0)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ThingsColor.mailHeaderBackground)
        .overlay {
            if store.dropTarget == account {
                RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                    .fill(ThingsColor.accent.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous))
        .onDrop(of: [.gmailMessage], isTargeted: Binding(
            get: { store.dropTarget == account },
            set: { targeted in
                if targeted { store.dropTarget = account } else if store.dropTarget == account { store.dropTarget = nil }
            })) { providers in
            guard let provider = providers.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.gmailMessage.identifier)
            }) else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.gmailMessage.identifier) { data, _ in
                guard let data, let payload = try? JSONDecoder().decode(GmailDragPayload.self, from: data) else { return }
                Task { @MainActor in
                    MailColumnsStore.shared.move(threadID: payload.threadID, messageID: payload.messageID, to: account)
                }
            }
            return true
        }
    }
}
