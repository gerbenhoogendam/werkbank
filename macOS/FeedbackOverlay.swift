import AppKit
import SwiftUI
import WerkbankCore

/// De aanwijsmodus bij het inspreken van een verbetering: over het hoofdvenster ligt een laag met de Siri-gloed langs
/// de rand. Klik op wat je bedoelt ("als ik hier klik …") of sleep een kader; de app eronder reageert dan niet. Elke
/// markering krijgt een nummer en het moment in de opname. F18 (of Klaar, ⏎) rondt af, Esc annuleert, ⌘Z haalt de
/// laatste markering weg.
@MainActor
@Observable
final class FeedbackSession {
    private(set) var marks: [FeedbackMark] = []
    /// Tijdens slepen: het kader in punten (linksboven 0,0).
    private(set) var dragRect: CGRect?
    /// Het begin van de opname; de tijd van een markering telt vanaf hier.
    var startedAt = Date()

    func drag(from start: CGPoint, to end: CGPoint) {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x),
                          height: abs(end.y - start.y))
        dragRect = rect.width > 4 || rect.height > 4 ? rect : nil
    }

    /// Losgelaten: een klik als er (bijna) niet gesleept is, anders een kader.
    func finishDrag(from start: CGPoint, to end: CGPoint, in size: CGSize) {
        dragRect = nil
        guard size.width > 0, size.height > 0 else { return }
        let time = Date().timeIntervalSince(startedAt)
        let number = (marks.last?.number ?? 0) + 1
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x),
                          height: abs(end.y - start.y))
        if rect.width < 6 && rect.height < 6 {
            marks.append(FeedbackMark(number: number, kind: .click, x: Double(end.x / size.width),
                                      y: Double(end.y / size.height), time: time))
        } else {
            marks.append(FeedbackMark(number: number, kind: .area, x: Double(rect.minX / size.width),
                                      y: Double(rect.minY / size.height), width: Double(rect.width / size.width),
                                      height: Double(rect.height / size.height), time: time))
        }
    }

    func removeLast() {
        if !marks.isEmpty { marks.removeLast() }
    }
}

@MainActor
final class FeedbackOverlay {
    static let shared = FeedbackOverlay()

    private var window: NSWindow?
    private var keyMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
    private(set) var session: FeedbackSession?

    var isShown: Bool { window != nil }

    func show(over parent: NSWindow, session: FeedbackSession, onFinish: @escaping () -> Void,
              onCancel: @escaping () -> Void) {
        hide()
        self.session = session
        let overlay = OverlayWindow(contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.isReleasedWhenClosed = false
        overlay.collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
        overlay.contentView = FirstMouseHostingView(rootView: FeedbackOverlayView(session: session, onFinish: onFinish,
                                                                                  onCancel: onCancel))
        parent.addChildWindow(overlay, ordered: .above)
        overlay.setFrame(parent.frame, display: true)
        window = overlay
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: parent,
                                                                queue: .main) { [weak overlay, weak parent] _ in
            MainActor.assumeIsolated {
                if let overlay, let parent { overlay.setFrame(parent.frame, display: true) }
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let undo = event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z"
            let handled = MainActor.assumeIsolated { () -> Bool in
                switch keyCode {
                case 53: onCancel()                      // Esc
                case 36, 76: onFinish()                  // ⏎
                default:
                    guard undo else { return false }
                    session.removeLast()
                }
                return true
            }
            return handled ? nil : event
        }
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        if let window {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
        window = nil
        session = nil
    }
}

/// Een randloos venster dat klikken krijgt zonder het hoofdvenster eerst te activeren.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - De laag

private struct FeedbackOverlayView: View {
    let session: FeedbackSession
    let onFinish: () -> Void
    let onCancel: () -> Void
    @State private var motion = VoiceMotion()
    private var dictation: Dictation { Dictation.shared }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // Vangt klikken en slepen (bijna doorzichtig: helemaal doorzichtig krijgt geen klikken).
                Color.black.opacity(0.03)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in session.drag(from: value.startLocation, to: value.location) }
                        .onEnded { value in
                            session.finishDrag(from: value.startLocation, to: value.location, in: proxy.size)
                        })
                ForEach(session.marks) { mark in
                    FeedbackMarkView(mark: mark, size: proxy.size, color: ThingsColor.deadline)
                }
                if let rect = session.dragRect {
                    Rectangle()
                        .fill(ThingsColor.deadline.opacity(0.08))
                        .overlay(Rectangle().strokeBorder(ThingsColor.deadline, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }
                VoiceGlow(level: dictation.level, motion: motion,
                          shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                controls
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                    .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea()
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.werk(size: 14, weight: .semibold))
                .foregroundStyle(SiriPalette.peach)
            if dictation.phase == .listening {
                HStack(spacing: 2.5) {
                    ForEach(0..<9, id: \.self) { index in
                        let shape = 1 - abs(Double(index) - 4) / 5
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 3, height: max(3, 18 * (0.15 + 0.85 * dictation.level * shape)))
                    }
                }
                .animation(.easeOut(duration: 0.12), value: dictation.level)
            }
            if !session.marks.isEmpty {
                Text("\(session.marks.count)")
                    .font(.werk(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(ThingsColor.deadline))
                Button("Laatste weg") { session.removeLast() }
                    .buttonStyle(OverlayButtonStyle())
            }
            Button("Annuleren", action: onCancel)
                .buttonStyle(OverlayButtonStyle())
            Button("Klaar", action: onFinish)
                .buttonStyle(OverlayButtonStyle(prominent: true))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Capsule().fill(Color.black.opacity(0.82)).shadow(color: .black.opacity(0.35), radius: 10, y: 3))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
    }
}

private struct OverlayButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.werk(size: 12.5, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.18)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
