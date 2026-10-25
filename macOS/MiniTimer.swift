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
        DuoWindowFold.shared.prepareReopen()
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
    private var dictation: Dictation { Dictation.shared }

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

    private var isShown: Bool {
        !shown.isEmpty || appState.hudMessage != nil || appState.idlePrompt != nil || dictation.isActive
    }

    /// Een melding of vraag staat als één pil; anders één pil per timer.
    private var rows: Int {
        appState.idlePrompt != nil || appState.hudMessage != nil || dictation.isActive ? 1 : max(1, shown.count)
    }

    var body: some View {
        Group {
            if let prompt = appState.idlePrompt {
                // Blijft staan tot er gekozen is.
                idleContent(prompt)
                    .padding(12)
                    .transition(.opacity)
            } else if dictation.isActive {
                // Inspreken gaat voor meldingen en de timer.
                dictationContent(listening: dictation.phase == .listening)
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
        .animation(.easeOut(duration: 0.2), value: dictation.isActive)
        .onChange(of: isShown, initial: true) { _, shown in onVisibilityChange(shown) }
        .onChange(of: sizeRaw) { _, _ in onResize(rows) }
        .onChange(of: rows, initial: true) { _, count in onResize(count) }
    }

    private func content(_ entry: TimeEntry) -> some View {
        let isRunning = entry.status == .running
        let pill = PillTheme.current
        let look = ThemeStore.shared.look
        let stop = {
            // De stopsheet staat in het hoofdvenster.
            appState.requestStop(entry, in: context)
            WindowRouter.showMain()
        }
        return HStack(spacing: size.gap) {
            // Een stilstaande stip: een knipperende liet de pil de hele dag tientallen keren per seconde hertekenen.
            if look == .sneeuwwitje {
                GrilleMark()
            } else if look == .wandklok {
                // Een kleine wijzerplaat; de wijzers tonen de verstreken tijd.
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    ClockFace(elapsed: entry.elapsed(at: timeline.date), size: size.buttonSize)
                }
            } else if look == .tischsuper {
                SpeakerGrille(color: Color(hex: 0x5A5856))
            } else if look == .principes {
                // De schuifknop links stopt de timer, zoals op de affiche.
                Button(action: stop) { ToggleKnob(height: size.buttonSize) }
                    .buttonStyle(.plain)
                    .help("Stop")
                    .accessibilityLabel("Stop")
            } else if pill.showsDot {
                Circle()
                    .fill(isRunning ? pill.dot : Color.orange)
                    .frame(width: size.dot, height: size.dot)
            }

            VStack(alignment: .leading, spacing: 1) {
                if look == .wandklok, size != .small {
                    Text(entry.client.uppercased())
                        .font(.werk(size: size.titleFont - 3.5))
                        .tracking(0.6)
                        .foregroundStyle(pill.text2)
                        .lineLimit(1)
                } else if look == .tischsuper, size != .small {
                    ThemeParts.labelValue("Klant", entry.client, size: size.titleFont - 2)
                        .lineLimit(1)
                } else if look == .karmijn, size != .small {
                    KarmijnLabel(text: entry.client, color: pill.text2, size: size.titleFont - 3.5)
                } else if look == .drukproef || look == .rekenmachine, size != .small {
                    Text(entry.client.uppercased())
                        .font(.werk(size: size.titleFont - 3, weight: .medium))
                        .tracking(look == .rekenmachine ? 0.8 : 0.2)
                        .foregroundStyle(pill.text2)
                        .lineLimit(1)
                }
                Text(entry.title)
                    .font(.werk(size: size.titleFont, weight: .medium))
                    .foregroundStyle(pill.text)
                    .lineLimit(1)
                if size != .small, ![.drukproef, .rekenmachine, .karmijn, .wandklok, .tischsuper].contains(look) {
                    Text(entry.client)
                        .font(.werk(size: size.titleFont - 2))
                        .foregroundStyle(pill.text2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let elapsed = entry.elapsed(at: timeline.date)
                let time = Billing.formatHMS(elapsed)
                if look == .rekenmachine {
                    LCDPanel(radius: 8) {
                        LCDDigits(text: time, size: size.timeFont * 0.62)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .fixedSize()
                } else if look == .wandklok {
                    // De seconden in goud, zoals de gele secondewijzer.
                    ThemeParts.secondsTinted(time)
                        .font(.werk(size: size.timeFont, weight: .bold))
                        .kerning(-0.5)
                        .monospacedDigit()
                        .foregroundStyle(pill.text)
                        .fixedSize()
                } else if look == .drukproef {
                    HStack(spacing: size.gap) {
                        if size != .small {
                            Waveform(count: 12, height: size.timeFont * 0.75, phase: Int(elapsed) % 24)
                        }
                        Text(time)
                            .font(Self.timeFont(look, size: size.timeFont))
                            .tracking(-1)
                            .foregroundStyle(ThingsColor.today)
                            .fixedSize()
                    }
                } else {
                    Text(time)
                        .font(Self.timeFont(look, size: size.timeFont))
                        .monospacedDigit()
                        .tracking(look == .drukproef ? -1 : 0)
                        .foregroundStyle(look == .drukproef || look == .karmijn ? ThingsColor.today : pill.text)
                        .fixedSize()
                }
            }

            circleButton(isRunning ? "pause.fill" : "play.fill", label: isRunning ? "Pauze" : "Hervat") {
                if isRunning { TimerService.pause(entry, in: context) } else { TimerService.start(entry, in: context) }
            }
            if look == .principes {
                // Rechts het luidsprekerrooster van de affiche (stoppen zit links).
                if size != .small {
                    PosterGrille(rows: size == .large ? 10 : 7, color: Color(hex: 0x2A2200), columnWidth: size == .large ? 30 : 22)
                }
            } else {
                stopButton(action: stop)
            }
        }
        .padding(.horizontal, size.gap + 6)
        // Sneeuwwitje: lichthouten kopse kanten zoals de SK 4.
        .padding(.horizontal, look == .sneeuwwitje ? 10 : 0)
        .frame(width: size.width, height: size.height)
        .background(pillShape(pill).fill(pill.background).shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3))
        .overlay {
            if look == .sneeuwwitje {
                HStack(spacing: 0) {
                    ThemeParts.elmGrain.frame(width: 12)
                    Spacer(minLength: 0)
                    ThemeParts.elmGrain.frame(width: 12)
                }
                .clipShape(pillShape(pill))
                .allowsHitTesting(false)
            }
        }
        .overlay(pillShape(pill).strokeBorder(pill.border, lineWidth: 1))
    }

    /// Een capsule, of een rechthoek met kleine hoeken als het thema dat wil (Karmijn).
    private func pillShape(_ pill: PillTheme) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: pill.radius ?? size.height / 2, style: .continuous)
    }

    private static func timeFont(_ look: ThemeLook, size: CGFloat) -> Font {
        switch look {
        case .standaard: .werk(size: size, weight: .semibold, design: .rounded)
        case .drukproef: .werkNumbers(size: size * 0.85)
        case .karmijn: .werkNumbers(size: size)
        case .sneeuwwitje: .werk(size: size, weight: .light)
        case .tischsuper: .werk(size: size, weight: .ultraLight)
        default: .werk(size: size, weight: .medium)
        }
    }

    /// Stopknop van de timerpil in de vorm van het thema.
    private func stopButton(action: @escaping () -> Void) -> some View {
        let pill = PillTheme.current
        let look = ThemeStore.shared.look
        return Button(action: action) {
            if look == .rekenmachine {
                // De gele =-toets: de tijd wordt uitgerekend en gaat naar Tijd schrijven.
                CalcKey(label: "=", yellow: true, size: size.buttonSize)
            } else if look == .sneeuwwitje {
                DialKnob(angle: 0, size: size.buttonSize)
            } else {
                RoundedRectangle(cornerRadius: look == .drukproef ? 0 : 2, style: .continuous)
                    .fill(pill.stopIcon)
                    .frame(width: size.buttonSize * 0.3, height: size.buttonSize * 0.3)
                    .frame(width: size.buttonSize, height: size.buttonSize)
                    .background {
                        if look == .karmijn {
                            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(pill.stopFill)
                        } else {
                            Circle().fill(pill.stopFill)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .help("Stop")
        .accessibilityLabel("Stop")
    }

    private func idleContent(_ prompt: IdlePrompt) -> some View {
        HStack(spacing: size.gap) {
            Image(systemName: "moon.zzz.fill")
                .font(.werk(size: size.titleFont + 2, weight: .semibold))
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(prompt.minutes) min weg")
                    .font(.werk(size: size.titleFont + 1, weight: .semibold))
                    .foregroundStyle(.white)
                if size != .small {
                    Text("\(prompt.start.formatted(date: .omitted, time: .shortened))–\(prompt.end.formatted(date: .omitted, time: .shortened))")
                        .font(.werk(size: size.titleFont - 2))
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
                .font(.werk(size: size.titleFont, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .padding(.horizontal, size.gap + 2)
                .frame(height: size.buttonSize)
                .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.18)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func dictationContent(listening: Bool) -> some View {
        HStack(spacing: size.gap) {
            Image(systemName: listening ? "mic.fill" : "waveform")
                .font(.werk(size: size.titleFont + 3, weight: .semibold))
                .foregroundStyle(listening ? Color(hex: 0xFF453A) : Color.white)
            if listening {
                DictationLevel(level: dictation.level, size: size)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, size.gap + 6)
        .frame(width: size.width, height: size.height)
        .background(Capsule().fill(Color.black.opacity(0.82)).shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func messageContent(_ message: String) -> some View {
        HStack(spacing: size.gap) {
            Image(systemName: "checkmark.circle.fill")
                .font(.werk(size: size.titleFont + 2, weight: .semibold))
                .foregroundStyle(Color(hex: 0x3CCB5F))
            Text(message)
                .font(.werk(size: size.titleFont, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let countdown = appState.hudCountdown {
                SendFuse(countdown: countdown, size: size)
                    .frame(width: size.width * 0.3)
            }
        }
        .padding(.horizontal, size.gap + 6)
        .frame(width: size.width, height: size.height)
        .background(Capsule().fill(Color.black.opacity(0.82)).shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        let pill = PillTheme.current
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.werk(size: size.buttonSize * 0.4, weight: .bold))
                .foregroundStyle(pill.buttonIcon)
                .frame(width: size.buttonSize, height: size.buttonSize)
                .background {
                    if ThemeStore.shared.look == .rekenmachine {
                        RoundKey()
                    } else if ThemeStore.shared.look == .drukproef {
                        Circle().strokeBorder(ThingsColor.checkboxStroke, lineWidth: 1)
                    } else if ThemeStore.shared.look == .karmijn {
                        Circle().strokeBorder(ThingsColor.separator, lineWidth: 1)
                    } else {
                        Circle().fill(pill.buttonFill)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Kleuren van de timerpil per thema (de pil van Standaard is donker doorschijnend).
private struct PillTheme {
    var background: Color
    var border: Color
    var text: Color
    var text2: Color
    var dot: Color
    var showsDot = true
    var buttonFill: Color
    var buttonIcon: Color
    var stopFill: Color
    var stopIcon: Color
    /// Hoekafronding; nil is een capsule.
    var radius: CGFloat? = nil

    static var current: PillTheme {
        switch ThemeStore.shared.look {
        case .standaard:
            PillTheme(background: .black.opacity(0.82), border: .white.opacity(0.14), text: .white, text2: .white.opacity(0.6),
                      dot: Color(hex: 0x3CCB5F), buttonFill: .white.opacity(0.18), buttonIcon: .white,
                      stopFill: .white.opacity(0.18), stopIcon: .white)
        case .wandklok:
            PillTheme(background: ThingsColor.cardBackground, border: ThingsColor.separator, text: ThingsColor.textPrimary,
                      text2: ThingsColor.textSecondary, dot: ThingsColor.running, showsDot: false, buttonFill: ThingsColor.tagBackground,
                      buttonIcon: ThingsColor.textPrimary, stopFill: ThemeParts.graphite, stopIcon: ThingsColor.cardBackground)
        case .tischsuper:
            PillTheme(background: Color(hex: 0x161616), border: .white.opacity(0.08), text: Color(hex: 0xEEEEED),
                      text2: Color(hex: 0xA8A6A2), dot: ThemeParts.orange, showsDot: false, buttonFill: Color(hex: 0xEEEEED),
                      buttonIcon: Color(hex: 0x111111), stopFill: ThemeParts.orange, stopIcon: Color(hex: 0x1C1C1C))
        case .principes:
            PillTheme(background: Color(hex: 0xF7C001), border: .clear, text: .black, text2: .black.opacity(0.7),
                      dot: .black, showsDot: false, buttonFill: .black.opacity(0.14), buttonIcon: .black,
                      stopFill: .black, stopIcon: .white)
        case .sneeuwwitje:
            PillTheme(background: ThingsColor.cardBackground, border: ThingsColor.separator, text: ThingsColor.textPrimary,
                      text2: ThingsColor.textSecondary, dot: ThingsColor.running, buttonFill: ThingsColor.tagBackground,
                      buttonIcon: ThingsColor.textPrimary, stopFill: ThingsColor.accent, stopIcon: .white)
        case .rekenmachine:
            PillTheme(background: Color(hex: 0x1F1D1B), border: .white.opacity(0.06), text: Color(hex: 0xECE8E2),
                      text2: Color(hex: 0xA39C93), dot: ThingsColor.today, showsDot: false, buttonFill: .clear,
                      buttonIcon: Color(hex: 0xD9D4CC), stopFill: ThingsColor.today, stopIcon: Color(hex: 0x1F1D1B))
        case .drukproef:
            PillTheme(background: ThingsColor.backgroundContent, border: .clear, text: ThingsColor.textPrimary,
                      text2: ThingsColor.textSecondary, dot: ThingsColor.today, showsDot: false, buttonFill: .clear,
                      buttonIcon: ThingsColor.today, stopFill: ThingsColor.textPrimary, stopIcon: ThingsColor.backgroundContent)
        case .spark:
            PillTheme(background: ThingsColor.cardBackground, border: ThingsColor.separator, text: ThingsColor.textPrimary,
                      text2: ThingsColor.textSecondary, dot: ThingsColor.running, buttonFill: ThingsColor.tagBackground,
                      buttonIcon: ThingsColor.accent, stopFill: ThingsColor.today, stopIcon: .white)
        case .karmijn:
            PillTheme(background: ThingsColor.backgroundContent, border: ThemeParts.karmijn, text: ThingsColor.textPrimary,
                      text2: ThingsColor.textSecondary, dot: ThingsColor.running, showsDot: false, buttonFill: .clear,
                      buttonIcon: ThingsColor.running, stopFill: ThemeParts.karmijn, stopIcon: ThemeParts.creme, radius: 4)
        }
    }
}
