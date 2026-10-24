import AppKit
import SwiftUI

/// Na het versturen van een antwoord of doorgestuurde mail: 2 seconden lang archiveert Enter het gesprek. De timer-pil
/// telt af (`HudCountdown`, getekend door `SendFuse`).
@MainActor
enum SendFollowUp {
    static let duration: TimeInterval = 2

    private static var monitor: Any?
    private static var timeout: Task<Void, Never>?

    /// Meldt het versturen en biedt archiveren aan voor het gesprek van `source`.
    static func offerArchive(_ source: MailRef, message: String, appState: AppState) {
        stop()
        appState.hudCountdown = HudCountdown(start: .now, duration: duration)
        appState.announce(message, seconds: duration)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Return of Enter (numeriek), zonder toetsen erbij.
            guard event.keyCode == 36 || event.keyCode == 76, modifiers.isEmpty, !event.isARepeat else { return event }
            MainActor.assumeIsolated { archive(source, appState: appState) }
            return nil
        }
        timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            stop()
            appState.hudCountdown = nil
        }
    }

    private static func archive(_ source: MailRef, appState: AppState) {
        stop()
        appState.hudCountdown?.isDone = true
        appState.announce("Gearchiveerd", seconds: 1.2)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if appState.hudCountdown?.isDone == true { appState.hudCountdown = nil }
        }
        let gmail = GmailSession.shared
        gmail.note(account: source.account, forMessageID: source.messageID)
        gmail.note(account: source.account, forMessageID: source.threadID)
        PanelStore.shared.closeThread(source.threadID)
        Task { await gmail.archiveMessage(source.summary, appState: appState) }
    }

    private static func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        timeout?.cancel()
        timeout = nil
    }
}

/// Het aftellen na versturen: een gloeiende balk die opbrandt naar het archiefdoosje, dat langzaam dooft. Enter op
/// tijd: de balk schiet groen vol en het doosje springt op.
struct SendFuse: View {
    let countdown: HudCountdown
    let size: MiniTimerSize

    private static let blue = Color(hex: 0x1A8CFF)
    private static let cyan = Color(hex: 0x6FE3FF)
    private static let green = Color(hex: 0x3CCB5F)

    var body: some View {
        let thickness = max(3, size.dot * 0.5)
        TimelineView(.animation(paused: countdown.isDone)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(countdown.start)
            let left = countdown.isDone ? 1 : max(0, 1 - elapsed / countdown.duration)
            HStack(spacing: size.gap * 0.6) {
                GeometryReader { geo in
                    let width = geo.size.width * left
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(countdown.isDone
                                  ? AnyShapeStyle(Self.green)
                                  : AnyShapeStyle(LinearGradient(colors: [Self.blue, Self.cyan],
                                                                 startPoint: .leading, endPoint: .trailing)))
                            .frame(width: width)
                        if !countdown.isDone && left > 0 {
                            // Het vonkje aan de kop van de balk.
                            Circle()
                                .fill(Color.white)
                                .frame(width: thickness * 1.8, height: thickness * 1.8)
                                .scaleEffect(1 + 0.25 * sin(elapsed * 14))
                                .shadow(color: Self.cyan, radius: thickness * 1.5)
                                .offset(x: width - thickness * 0.9)
                        }
                    }
                    .frame(height: thickness)
                    .frame(maxHeight: .infinity)
                }
                Image(systemName: countdown.isDone ? "archivebox.fill" : "archivebox")
                    .font(.system(size: size.titleFont + 3, weight: .semibold))
                    .foregroundStyle(countdown.isDone ? Self.green : Color.white.opacity(0.35 + 0.6 * left))
                    .scaleEffect(countdown.isDone ? 1.25 : 1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.45), value: countdown.isDone)
            }
        }
    }
}
