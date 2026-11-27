import Foundation
import LocalAuthentication
import Observation
import SwiftData
import SwiftUI
import UserNotifications

/// Voorkeur "Ontgrendelen met Face ID": bij het starten en na meer dan een minuut op de achtergrond ligt de app achter
/// een slot tot Face ID (of de toegangscode) slaagt.
@MainActor
@Observable
final class PhoneLock {
    static let shared = PhoneLock()
    nonisolated static let enabledKey = "phone.lock.faceID"
    nonisolated static let grace: TimeInterval = 60

    private(set) var isLocked = UserDefaults.standard.bool(forKey: PhoneLock.enabledKey)
    private(set) var isEvaluating = false
    @ObservationIgnored private var backgroundSince: Date?

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func didEnterBackground() {
        backgroundSince = Date()
    }

    /// Terug van de achtergrond (niet na het venster van Face ID zelf: dan blijft de knop staan).
    func didBecomeActive() {
        guard isEnabled else {
            isLocked = false
            return
        }
        guard let since = backgroundSince else { return }
        backgroundSince = nil
        if Date().timeIntervalSince(since) > Self.grace { isLocked = true }
        if isLocked { Task { await unlock() } }
    }

    func unlock() async {
        guard isLocked, !isEvaluating else { return }
        isEvaluating = true
        defer { isEvaluating = false }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Geen Face ID en geen toegangscode op dit toestel: niets om mee te ontgrendelen.
            isLocked = false
            return
        }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Werkbank ontgrendelen")) ?? false
        if ok { isLocked = false }
    }
}

/// Het slot: Werkbank groot en een knop om te ontgrendelen.
struct PhoneLockScreen: View {
    private let lock = PhoneLock.shared

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Ph.ink)
                .frame(width: 58, height: 58)
                .background(Ph.lime)
                .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 2))
            Text("WERKBANK").font(Ph.poster(72)).foregroundStyle(Ph.ink)
            Spacer()
            Button {
                Task { await lock.unlock() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "faceid")
                    Text("ONTGRENDELEN")
                }
            }
            .buttonStyle(PhPrimaryStyle(height: 54))
            .disabled(lock.isEvaluating)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ph.paper.ignoresSafeArea())
    }
}

/// Voorkeur "Herinnering om 17:00 onder": gaat de app naar de achtergrond op een werkdag voor 17:00 en staat er
/// vandaag minder dan het ingestelde aantal uren, dan komt er om 17:00 een melding; anders gaat die weg.
enum PhoneTimeReminder {
    static let enabledKey = "phone.time.reminder"
    static let hoursKey = "phone.time.reminderHours"
    static let identifier = "werkbank.reminder.1700"

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    @MainActor
    static func update(in context: ModelContext, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let hours = UserDefaults.standard.object(forKey: hoursKey) as? Int ?? 6
        let calendar = Calendar.current
        guard !calendar.isDateInWeekend(now),
              let fire = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now), fire > now else { return }
        let start = calendar.startOfDay(for: now)
        let seconds = TimerService.allEntries(in: context)
            .filter { $0.createdAt >= start && $0.createdAt < fire }
            .reduce(0) { $0 + $1.elapsed(at: now) }
        guard seconds < Double(hours) * 3600 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tijd"
        content.body = "Vandaag \(PhoneClientView.hours(seconds)) van \(hours):00"
        content.sound = .default
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
