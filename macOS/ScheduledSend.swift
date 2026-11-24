import AppKit
import Observation
import SwiftUI
import WerkbankCore

/// Een mail die later weg moet. De mail zelf staat er helemaal in (zoals hij verstuurd wordt); de Date-kop wordt bij
/// versturen op het echte moment gezet.
struct ScheduledMail: Codable, Identifiable, Equatable {
    var id = UUID()
    var raw: Data
    var threadID: String?
    var account: String
    var sendAt: Date
    var subject: String
    var recipients: String
    /// Na versturen: opvolgen als er na zoveel dagen geen antwoord is.
    var followUpDays: Int?
    /// Antwoord in het gesprek van een kaart: die gaat bij versturen naar "wacht op klant".
    var replyThreadID: String?
    var lastError: String?
}

/// Later versturen gebeurt op deze Mac: Werkbank verstuurt de mail zelf op het gekozen tijdstip (de Gmail-API kent geen
/// ingeplande verzending). Zolang er iets gepland staat, valt de Mac niet vanzelf in slaap (het scherm wel); een
/// dichtgeklapte laptop slaapt toch, en draait Werkbank niet, dan gaat de mail zodra dat weer zo is. Bewaard in
/// Application Support (niet gesynchroniseerd: een andere Mac zou hem anders ook versturen).
@MainActor
@Observable
final class ScheduledSend {
    static let shared = ScheduledSend()

    private(set) var items: [ScheduledMail] = []
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var sending = false
    @ObservationIgnored private var started = false
    /// Houdt de Mac wakker (niet het scherm) zolang er iets gepland staat.
    @ObservationIgnored private var keepAwake: NSObjectProtocol?

    private static let file: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("Werkbank", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Gepland.json")
    }()

    func start() {
        guard !started else { return }
        started = true
        if let file = Self.file, let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode([ScheduledMail].self, from: data) {
            items = stored.sorted { $0.sendAt < $1.sendAt }
        }
        updateKeepAwake()
        // Wakker geworden: wat intussen had moeten gaan meteen versturen.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated { ScheduledSend.shared.check() }
        }
        restartLoop()
    }

    func add(_ mail: ScheduledMail) {
        items.append(mail)
        items.sort { $0.sendAt < $1.sendAt }
        save()
        restartLoop()
    }

    func sendNow(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].sendAt = Date()
        save()
        check()
    }

    /// Niet versturen: de mail gaat terug naar de concepten in Gmail (om verder te bewerken). `false`: dat lukte niet,
    /// en dan blijft hij gepland staan.
    func cancel(_ id: UUID) async -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return true }
        do {
            _ = try await GmailSession.shared.saveDraft(raw: item.raw, draftID: nil, threadID: item.threadID,
                                                        account: item.account)
        } catch {
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].lastError = "Terugzetten naar concepten mislukt: \(error.localizedDescription)"
            }
            return false
        }
        items.removeAll { $0.id == id }
        save()
        AppState.shared.announce("Geplande mail staat weer bij de concepten")
        return true
    }

    // MARK: Versturen

    /// Elke halve minuut kijken (de klok van de Mac, dus ook na slapen of een andere tijdzone); alleen zolang er iets
    /// gepland staat.
    private func restartLoop() {
        loop?.cancel()
        guard !items.isEmpty else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.check()
                guard let next = self?.items.first?.sendAt else { return }
                let wait = min(max(next.timeIntervalSinceNow, 1), 30)
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func check() {
        guard !sending, items.contains(where: { $0.sendAt <= Date() }) else { return }
        sending = true
        Task {
            await sendDue()
            sending = false
            restartLoop()
        }
    }

    private func sendDue() async {
        let gmail = GmailSession.shared
        for item in items where item.sendAt <= Date() {
            do {
                let raw = MailComposer.replacingDate(in: item.raw, with: Date())
                let sentThread = try await gmail.send(raw: raw, threadID: item.threadID, account: item.account)
                items.removeAll { $0.id == item.id }
                save()
                var message = "Geplande mail verzonden: \(item.subject.isEmpty ? item.recipients : item.subject)"
                if let replyThread = item.replyThreadID, let column = WaitingWatcher.shared.didReply(threadID: replyThread) {
                    message += " · kaart naar \(column)"
                }
                if let days = item.followUpDays, let sentThread {
                    let due = Date().addingTimeInterval(Double(days) * 86_400)
                    FollowUpStore.shared.add(threadID: sentThread, account: item.account, subject: item.subject,
                                             kind: .noReply, due: due)
                }
                AppState.shared.announce(message)
            } catch {
                // Geen internet of nog niet ingelogd: over een halve minuut opnieuw.
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].lastError = error.localizedDescription
                }
            }
        }
    }

    private func updateKeepAwake() {
        if items.isEmpty {
            if let keepAwake { ProcessInfo.processInfo.endActivity(keepAwake) }
            keepAwake = nil
        } else if keepAwake == nil {
            keepAwake = ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled,
                                                              reason: "Geplande mail versturen")
        }
    }

    private func save() {
        updateKeepAwake()
        guard let file = Self.file else { return }
        if items.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

// MARK: - Weergave

/// Werkbalk: de geplande mails, met nu versturen of terug naar de concepten.
struct ScheduledSendButton: View {
    private let store = ScheduledSend.shared
    @State private var showList = false

    var body: some View {
        Button {
            showList.toggle()
        } label: {
            Label("Gepland (\(store.items.count))", systemImage: "clock.arrow.circlepath")
        }
        .help("Geplande mails (\(store.items.count))")
        .popover(isPresented: $showList, arrowEdge: .bottom) {
            ScheduledSendList()
        }
    }
}

private struct ScheduledSendList: View {
    private let store = ScheduledSend.shared
    @State private var busy: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Gepland")
                .font(.werk(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            if store.items.isEmpty {
                Text("Niets gepland")
                    .font(.werk(size: 12))
                    .foregroundStyle(Color.fieldLabel)
                    .padding(14)
            }
            ForEach(store.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(SendLater.label(item.sendAt, now: Date()))
                            .font(.werk(size: 12, weight: .semibold))
                            .foregroundStyle(ThingsColor.accent)
                        Spacer()
                        Text(item.account)
                            .font(.werk(size: 10.5))
                            .foregroundStyle(Color.fieldLabel)
                            .lineLimit(1)
                    }
                    Text(item.subject.isEmpty ? "(geen onderwerp)" : item.subject)
                        .font(.werk(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(item.recipients)
                        .font(.werk(size: 11.5))
                        .foregroundStyle(ThingsColor.textSecondary)
                        .lineLimit(1)
                    if let error = item.lastError {
                        Text(error)
                            .font(.werk(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    HStack {
                        Button("Nu versturen") { store.sendNow(item.id) }
                        Button("Terug naar concepten") {
                            busy = item.id
                            Task {
                                _ = await store.cancel(item.id)
                                busy = nil
                            }
                        }
                        if busy == item.id { ProgressView().controlSize(.small) }
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider()
            }
        }
        .frame(width: 340)
    }
}
