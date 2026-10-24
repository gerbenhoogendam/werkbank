import AppKit
import Observation
import SwiftUI

/// Hoofdvenster en losse opstelvensters openen en sluiten met de Duo-vouw in plaats van de animatie van macOS.
/// Titelbalk en knoppenbalk zijn AppKit, dus de vouw draait op een afbeelding van het venster, in een doorzichtig
/// venster op dezelfde plek. Bij openen staat het echte venster zolang achter de bureaubladachtergrond: daar wordt het
/// opgebouwd zonder dat je het ziet. Lukt de afbeelding niet, dan opent of sluit het venster gewoon, zonder vouw.
@MainActor
final class DuoWindowFold {
    static let shared = DuoWindowFold()

    /// Gekoppelde vensters; `true` voor het hoofdvenster (dat vouwt ook bij stoppen met ⌘Q).
    private var windows: [ObjectIdentifier: Bool] = [:]
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var overlays: [NSWindow] = []
    private var isQuitting = false

    /// Onder de bureaubladachtergrond.
    private static let hiddenLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)

    func attach(_ window: NSWindow, isMain: Bool) {
        let key = ObjectIdentifier(window)
        guard windows[key] == nil else { return }
        windows[key] = isMain
        window.animationBehavior = .none
        observers[key] = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                                queue: .main) { note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow else { return }
                DuoWindowFold.shared.windowWillClose(window)
            }
        }
        unfold(window)
    }

    /// ⌘Q: eerst het hoofdvenster dichtvouwen, dan `reply`. `false`: niets te vouwen, meteen stoppen.
    func foldForQuit(then reply: @escaping () -> Void) -> Bool {
        guard !isQuitting,
              let window = NSApp.windows.first(where: { windows[ObjectIdentifier($0)] == true && canFold($0) }),
              let image = Self.snapshot(of: window) else { return false }
        isQuitting = true
        play(image, frame: window.frame, opening: false, completion: reply)
        window.orderOut(nil)
        return true
    }

    private func canFold(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && !window.styleMask.contains(.fullScreen)
            && window.level != Self.hiddenLevel
    }

    private func unfold(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        let level = window.level
        window.level = Self.hiddenLevel
        Task { @MainActor in
            // Eerst laten opbouwen (board, agenda), dan vastleggen.
            try? await Task.sleep(for: .milliseconds(300))
            var image = window.isVisible ? Self.snapshot(of: window) : nil
            for _ in 0..<5 where image == nil && window.isVisible {
                try? await Task.sleep(for: .milliseconds(100))
                image = Self.snapshot(of: window)
            }
            guard let image else {
                window.level = level
                return
            }
            play(image, frame: window.frame, opening: true) {
                window.level = level
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func windowWillClose(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        windows[key] = nil
        if let observer = observers.removeValue(forKey: key) { NotificationCenter.default.removeObserver(observer) }
        guard !isQuitting, canFold(window), let image = Self.snapshot(of: window) else { return }
        play(image, frame: window.frame, opening: false) {}
    }

    /// Speelt de vouw af in een doorzichtig venster boven `frame`; `completion` als hij klaar is.
    private func play(_ image: NSImage, frame: CGRect, opening: Bool, completion: @escaping () -> Void) {
        let margin: CGFloat = 80   // ruimte voor de schaduw
        let overlay = NSWindow(contentRect: frame.insetBy(dx: -margin, dy: -margin), styleMask: .borderless,
                               backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.isReleasedWhenClosed = false
        overlay.animationBehavior = .none
        overlay.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        let model = DuoWindowFoldModel(progress: opening ? 1 : 0)
        overlay.contentView = NSHostingView(rootView: DuoWindowFoldView(image: image, size: frame.size, model: model))
        overlay.contentView?.layoutSubtreeIfNeeded()
        overlay.orderFrontRegardless()
        overlay.displayIfNeeded()
        CATransaction.flush()
        overlays.append(overlay)

        let finish = { [weak self] in
            guard !model.isFinished else { return }
            model.isFinished = true
            completion()
            // Pas weghalen als het echte venster weer getekend is.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                overlay.orderOut(nil)
                self?.overlays.removeAll { $0 === overlay }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))   // eerst de beginstand in beeld
            withAnimation(opening ? DuoFold.windowOpening : DuoFold.windowClosing) {
                model.progress = opening ? 0 : 1
            } completion: {
                finish()
            }
            // Voor als de afronding uitblijft: het echte venster mag nooit verborgen blijven.
            try? await Task.sleep(for: .seconds(1.5))
            finish()
        }
    }

    // MARK: Afbeelding van een venster

    /// `CGWindowListCreateImage` is verouderd, maar de enige manier om het eigen venster inclusief titelbalk en
    /// mailtekst vast te leggen zonder toestemming voor schermopname. Via `dlsym`, zodat het ook bouwt met een SDK
    /// waarin de declaratie is weggehaald; ontbreekt de functie, dan geen vouw.
    private typealias CreateWindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> UnsafeMutableRawPointer?

    private static let createWindowImage: CreateWindowImage? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: CreateWindowImage.self)
    }()

    private static func snapshot(of window: NSWindow) -> NSImage? {
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let createWindowImage, window.windowNumber > 0,
              let raw = createWindowImage(.null, CGWindowListOption.optionIncludingWindow.rawValue,
                                          CGWindowID(window.windowNumber), options.rawValue) else { return nil }
        let image = Unmanaged<CGImage>.fromOpaque(raw).takeRetainedValue()
        guard image.width > 1, image.height > 1, hasContent(image) else { return nil }
        return NSImage(cgImage: image, size: window.frame.size)
    }

    /// Niet helemaal doorzichtig (dan was het venster nog niet getekend).
    private static func hasContent(_ image: CGImage) -> Bool {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn && stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
    }
}

@MainActor
@Observable
private final class DuoWindowFoldModel {
    var progress: Double
    @ObservationIgnored var isFinished = false

    init(progress: Double) {
        self.progress = progress
    }
}

private struct DuoWindowFoldView: View {
    let image: NSImage
    let size: CGSize
    let model: DuoWindowFoldModel

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .modifier(DuoFoldEffect(progress: model.progress, width: size.width, cornerRadius: 0,
                                    shadow: .black.opacity(0.4), shadowRadius: 30, keepsTransparency: true))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Koppelt het venster waarin deze view staat aan de Duo-vouw.
struct DuoWindowHook: NSViewRepresentable {
    var isMain = false

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.isMain = isMain
        return view
    }

    func updateNSView(_ view: HookView, context: Context) {}

    final class HookView: NSView {
        var isMain = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DuoWindowFold.shared.attach(window, isMain: isMain) }
        }
    }
}
