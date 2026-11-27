import Foundation
import Observation
import SwiftUI
import UIKit
import WerkbankCore

/// De uitbak: een verstuurde mail wacht zes seconden voordat hij echt weggaat. Tot dan staat boven de tabbalk de balk
/// Verstuurd met Ongedaan maken; ongedaan maken opent het opstelscherm weer met dezelfde inhoud.
@MainActor
@Observable
final class PhoneOutbox {
    static let shared = PhoneOutbox()
    static let delay: TimeInterval = 6

    struct Pending: Identifiable {
        let id = UUID()
        let raw: Data
        let threadID: String?
        let account: String
        /// Wat er in het opstelscherm stond, om terug te zetten.
        let request: PhoneComposeRequest
        /// Naam of adres van de eerste ontvanger.
        let label: String
        let deadline: Date
    }

    private(set) var pending: Pending?
    /// Na ongedaan maken of een mislukte verzending: het opstelscherm weer open.
    var reopen: PhoneComposeRequest?
    /// Telt op na elke verstuurde mail (de lijst met concepten laadt dan opnieuw).
    private(set) var sentCount = 0

    @ObservationIgnored private var timer: Task<Void, Never>?

    func enqueue(raw: Data, threadID: String?, account: String, request: PhoneComposeRequest, label: String) {
        if pending != nil { flush() }
        let item = Pending(raw: raw, threadID: threadID, account: account, request: request, label: label,
                           deadline: Date().addingTimeInterval(Self.delay))
        withAnimation(.easeOut(duration: 0.2)) { pending = item }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.delay))
            guard !Task.isCancelled else { return }
            await self?.deliver(item)
        }
    }

    func undo() {
        guard let item = pending else { return }
        timer?.cancel()
        timer = nil
        withAnimation(.easeOut(duration: 0.2)) { pending = nil }
        reopen = item.request
    }

    /// Meteen versturen (een nieuwe mail in de uitbak, of de app gaat naar de achtergrond).
    func flush() {
        guard let item = pending else { return }
        timer?.cancel()
        timer = nil
        pending = nil
        // Ook als de app intussen naar de achtergrond gaat: even doorwerken tot de mail weg is.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Versturen", expirationHandler: nil)
        Task {
            await deliver(item)
            UIApplication.shared.endBackgroundTask(background)
        }
    }

    private func deliver(_ item: Pending) async {
        if pending?.id == item.id {
            withAnimation(.easeOut(duration: 0.2)) { pending = nil }
        }
        let raw = MailComposer.replacingDate(in: item.raw, with: Date())
        do {
            try await PhoneGmail.shared.send(raw, threadID: item.threadID, account: item.account)
            if let draftID = item.request.draftID {
                await PhoneGmail.shared.deleteDraft(messageID: draftID, account: item.request.draftAccount ?? item.account)
            }
            sentCount += 1
        } catch {
            AppState.shared.showToast("Versturen mislukt")
            reopen = item.request
        }
    }
}

/// De balk boven de tabbalk: Verstuurd, de ontvanger, Ongedaan maken met de seconden en een lijn die krimpt.
struct PhoneOutboxBar: View {
    let pending: PhoneOutbox.Pending

    var body: some View {
        TimelineView(.animation) { timeline in
            let left = max(0, pending.deadline.timeIntervalSince(timeline.date))
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Ph.ink)
                        .frame(width: 30, height: 30)
                        .background(Ph.lime)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Verstuurd").font(Ph.text(14, .semibold)).foregroundStyle(Ph.paper)
                        if !pending.label.isEmpty {
                            Text(pending.label).font(Ph.text(12)).foregroundStyle(Color(hex: 0xB5B5AC)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Button {
                        PhoneOutbox.shared.undo()
                    } label: {
                        HStack(spacing: 8) {
                            Text("ONGEDAAN MAKEN").tracking(1.4)
                            Text("\(Int(left.rounded(.up)))").monospacedDigit()
                        }
                        .font(Ph.text(11, .semibold))
                        .foregroundStyle(Ph.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                        .shadow(color: .black.opacity(0.6), radius: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color(hex: 0x3A3A36))
                        Rectangle().fill(Ph.lime)
                            .frame(width: geometry.size.width * CGFloat(left / PhoneOutbox.delay))
                    }
                }
                .frame(height: 3)
                .accessibilityHidden(true)
            }
            .background(Ph.ink)
            .shadow(color: .black.opacity(0.5), radius: 0, y: 2)
            .shadow(color: Ph.ink.opacity(0.32), radius: 12, y: 10)
        }
    }
}
