import AppKit
import SwiftData
import SwiftUI
import WerkbankCore

/// Opent en toont vensters van buiten SwiftUI (vanuit het zwevende timerpaneel).
@MainActor
enum WindowRouter {
    /// Wordt gezet door een view die `openWindow` kent (menubalklabel, hoofdvenster).
    static var openMain: (() -> Void)?

    static func showMain() {
        if let openMain {
            openMain()
        } else if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Paneel

private final class MiniTimerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Zwevend minipaneel met de lopende timer, boven alle apps (zoals een HUD).
@MainActor
final class MiniTimerController {
    static let shared = MiniTimerController()

    private var panel: MiniTimerPanel?
    /// Aantal pillen onder elkaar (één per lopende timer).
    private var rows = 1
    private static let positionKey = "miniTimerPosition"   // "midX,maxY"
    private static let margin: CGFloat = 12               // ruimte voor de schaduw
    static let rowSpacing: CGFloat = 6

    func start() {
        guard panel == nil else { return }
        let panel = MiniTimerPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 70),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = MiniTimerView(
            onVisibilityChange: { [weak self] visible in self?.setVisible(visible) },
            onResize: { [weak self] rows in
                self?.rows = max(1, rows)
                self?.resize()
            }
        )
        .environment(AppState.shared)
        .modelContainer(Persistence.container)
        panel.contentView = NSHostingView(rootView: view)
        self.panel = panel

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePosition() }
        }
        resize()
    }

    private var contentSize: NSSize {
        let size = MiniTimerSize(stored: UserDefaults.standard.string(forKey: SettingsKey.miniTimerSize))
        let height = size.height * CGFloat(rows) + Self.rowSpacing * CGFloat(rows - 1)
        return NSSize(width: size.width + Self.margin * 2, height: height + Self.margin * 2)
    }

    private func setVisible(_ visible: Bool) {
        guard let panel else { return }
        if visible {
            guard !panel.isVisible else { return }
            resize(placing: true)
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func resize(placing: Bool = false) {
        guard let panel else { return }
        let size = contentSize
        var origin: NSPoint
        if placing || !panel.isVisible {
            origin = savedOrigin(for: size) ?? defaultOrigin(for: size)
        } else {
            // Behoud het midden bovenin bij een andere grootte.
            let old = panel.frame
            origin = NSPoint(x: old.midX - size.width / 2, y: old.maxY - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Bovenaan het scherm, in het midden.
    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height + Self.margin - 8)
    }

    private func savedOrigin(for size: NSSize) -> NSPoint? {
        guard let raw = UserDefaults.standard.string(forKey: Self.positionKey) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        let origin = NSPoint(x: parts[0] - size.width / 2, y: parts[1] - size.height)
        // Alleen gebruiken als het nog op een scherm valt.
        let rect = NSRect(origin: origin, size: size)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(rect) } ? origin : nil
    }

    private func savePosition() {
        guard let panel, panel.isVisible else { return }
        let f = panel.frame
        UserDefaults.standard.set("\(f.midX),\(f.maxY)", forKey: Self.positionKey)
    }
}

// MARK: - Weergave

struct MiniTimerView: View {
    var onVisibilityChange: (Bool) -> Void
    /// Aantal pillen onder elkaar, zodat het paneel mee groeit.
    var onResize: (Int) -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @AppStorage(SettingsKey.miniTimerSize) private var sizeRaw = MiniTimerSize.small.rawValue
    @Query(filter: #Predicate<TimeEntry> { $0.statusRaw == "running" || $0.statusRaw == "paused" })
    private var active: [TimeEntry]

    private var size: MiniTimerSize { MiniTimerSize(stored: sizeRaw) }

    /// De lopende timers (tot drie, oudste boven); loopt er geen, dan de laatst gepauzeerde van de afgelopen twee uur,
    /// zodat je hem kunt hervatten.
    private var shown: [TimeEntry] {
        let running = active
            .filter { $0.status == .running }
            .sorted { ($0.firstStart ?? $0.createdAt) < ($1.firstStart ?? $1.createdAt) }
        if !running.isEmpty { return Array(running.prefix(TimerService.maxRunning)) }
        let cutoff = Date().addingTimeInterval(-7200)
        return active
            .filter { $0.status == .paused && ($0.pausedAt ?? .distantPast) > cutoff }
            .max { ($0.pausedAt ?? .distantPast) < ($1.pausedAt ?? .distantPast) }
            .map { [$0] } ?? []
    }

    private var isShown: Bool { !shown.isEmpty || appState.hudMessage != nil || appState.idlePrompt != nil }

    /// Een melding of vraag staat als één pil; anders één pil per timer.
    private var rows: Int {
        appState.idlePrompt != nil || appState.hudMessage != nil ? 1 : max(1, shown.count)
    }

    var body: some View {
        Group {
            if let prompt = appState.idlePrompt {
                // Blijft staan tot er gekozen is.
                idleContent(prompt)
                    .padding(12)
                    .transition(.opacity)
            } else if let message = appState.hudMessage {
                // Een melding gaat even voor de timer.
                messageContent(message)
                    .padding(12)
                    .transition(.opacity)
            } else if !shown.isEmpty {
                VStack(spacing: MiniTimerController.rowSpacing) {
                    ForEach(shown) { entry in content(entry) }
                }
                .padding(12)   // ruimte voor de schaduw; moet gelijk zijn aan MiniTimerController.margin
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.hudMessage)
        .animation(.easeOut(duration: 0.2), value: appState.idlePrompt)
        .onChange(of: isShown, initial: true) { _, shown in onVisibilityChange(shown) }
        .onChange(of: sizeRaw) { _, _ in onResize(rows) }
        .onChange(of: rows, initial: true) { _, count in onResize(count) }
    }

    private func content(_ entry: TimeEntry) -> some View {
        let isRunning = entry.status == .running
        return HStack(spacing: size.gap) {
            // Een stilstaande stip: een knipperende liet de pil de hele dag tientallen keren per seconde hertekenen.
            Circle()
                .fill(isRunning ? Color(hex: 0x3CCB5F) : Color.orange)
                .frame(width: size.dot, height: size.dot)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: size.titleFont, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if size != .small {
                    Text(entry.client)
                        .font(.system(size: size.titleFont - 2))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(Billing.formatHMS(entry.elapsed(at: timeline.date)))
                    .font(.system(size: size.timeFont, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .fixedSize()
            }

            circleButton(isRunning ? "pause.fill" : "play.fill", label: isRunning ? "Pauze" : "Hervat") {
                if isRunning { TimerService.pause(entry, in: context) } else { TimerService.start(entry, in: context) }
            }
            circleButton("stop.fill", label: "Stop") {
                // De stopsheet staat in het hoofdvenster.
                appState.requestStop(entry, in: context)
                WindowRouter.showMain()
            }
        }
        .padding(.horizontal, size.gap + 6)
        .frame(width: size.width, height: size.height)
        .background(Capsule().fill(Color.black.opacity(0.82)).shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func idleContent(_ prompt: IdlePrompt) -> some View {
        HStack(spacing: size.gap) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: size.titleFont + 2, weight: .semibold))
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(prompt.minutes) min weg")
                    .font(.system(size: size.titleFont + 1, weight: .semibold))
                    .foregroundStyle(.white)
                if size != .small {
                    Text("\(prompt.start.formatted(date: .omitted, time: .shortened))–\(prompt.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: size.titleFont - 2))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            textButton("Eraf", prominent: true) { IdleWatcher.shared.subtract(prompt) }
            textButton("Laten", prominent: false) { IdleWatcher.shared.keep() }
        }
        .padding(.horizontal, size.gap + 6)
        .frame(width: size.width, height: size.height)
        .background(Capsule().fill(Color.black.opacity(0.82)).shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func textButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size.titleFont, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .padding(.horizontal, size.gap + 2)
                .frame(height: size.buttonSize)
                .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.18)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func messageContent(_ message: String) -> some View {
        HStack(spacing: size.gap) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size.titleFont + 2, weight: .semibold))
                .foregroundStyle(Color(hex: 0x3CCB5F))
            Text(message)
                .font(.system(size: size.titleFont, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, size.gap + 6)
        .frame(width: size.width, height: size.height)
        .background(Capsule().fill(Color.black.opacity(0.82)).shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size.buttonSize * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size.buttonSize, height: size.buttonSize)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
