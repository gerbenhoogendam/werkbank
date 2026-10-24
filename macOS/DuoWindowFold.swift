import AppKit
import Observation
import SwiftUI

/// De Duo-vouw met het echte matglas (shader), op een afbeelding in een doorzichtig venster boven de plek waar het om
/// gaat:
/// - Hoofdvenster en losse opstelvensters bij openen en sluiten. Titelbalk en knoppenbalk zijn AppKit, vandaar de
///   afbeelding. Bij openen staat het echte venster zolang achter de bureaubladachtergrond: daar wordt het opgebouwd
///   zonder dat je het ziet.
/// - Mail- en opstelpanelen bij sluiten en versturen (zie `PanelStore`): het paneel verdwijnt, de afbeelding vouwt weg.
/// Lukt de afbeelding niet, dan gaat het zonder vouw (vensters) of met de benaderde vouw (panelen).
@MainActor
final class DuoWindowFold {
    static let shared = DuoWindowFold()

    /// Gekoppelde vensters; `true` voor het hoofdvenster (dat vouwt ook bij stoppen met ⌘Q).
    private var windows: [ObjectIdentifier: Bool] = [:]
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var overlays: [NSWindow] = []
    /// Waar de mail- en opstelpanelen staan (`PanelProbe`).
    private var probes: [String: WeakView] = [:]
    private var isQuitting = false
    /// Het volgende venster dat sluit, sluit na versturen (los opstelvenster).
    private var nextCloseIsSend = false

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

    /// Vlak voor het sluiten van een los opstelvenster na versturen: dan geldt de duur van Versturen.
    func markSending() {
        nextCloseIsSend = true
    }

    /// ⌘Q: eerst het hoofdvenster dichtvouwen, dan `reply`. `false`: niets te vouwen, meteen stoppen.
    func foldForQuit(then reply: @escaping () -> Void) -> Bool {
        guard !isQuitting,
              let window = NSApp.windows.first(where: { windows[ObjectIdentifier($0)] == true && canFold($0) }),
              let image = Self.windowImage(window) else { return false }
        isQuitting = true
        play(NSImage(cgImage: image, size: window.frame.size), frame: window.frame, opening: false, part: .windowClose,
             completion: reply)
        window.orderOut(nil)
        return true
    }

    // MARK: Panelen

    func register(_ view: NSView, panelID: String) {
        probes = probes.filter { $0.value.view != nil }
        probes[panelID] = WeakView(view)
    }

    /// Laat een afbeelding van het paneel boven het venster wegvouwen. `false`: geen afbeelding (paneel niet in beeld).
    func foldAway(panelID: String, part: FoldSpeed) -> Bool {
        guard let view = probes[panelID]?.view, let window = view.window, canFold(window),
              let image = Self.windowImage(window) else { return false }
        let rect = view.convert(view.bounds, to: nil)   // in het venster, oorsprong linksonder
        let scale = CGFloat(image.width) / window.frame.width
        let crop = CGRect(x: rect.minX * scale, y: (window.frame.height - rect.maxY) * scale,
                          width: rect.width * scale, height: rect.height * scale).integral
        guard rect.width > 1, rect.height > 1, let piece = image.cropping(to: crop) else { return false }
        play(NSImage(cgImage: piece, size: rect.size), frame: window.convertToScreen(rect), cornerRadius: 12,
             shadow: ThingsColor.cardShadow, shadowRadius: 18, opening: false, part: part) {}
        return true
    }

    // MARK: Vensters

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
            var image = window.isVisible ? Self.windowImage(window) : nil
            for _ in 0..<5 where image == nil && window.isVisible {
                try? await Task.sleep(for: .milliseconds(100))
                image = Self.windowImage(window)
            }
            guard let image else {
                window.level = level
                return
            }
            play(NSImage(cgImage: image, size: window.frame.size), frame: window.frame, opening: true,
                 part: .windowOpen) {
                window.level = level
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func windowWillClose(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        windows[key] = nil
        if let observer = observers.removeValue(forKey: key) { NotificationCenter.default.removeObserver(observer) }
        let part: FoldSpeed = nextCloseIsSend ? .send : .windowClose
        nextCloseIsSend = false
        guard !isQuitting, canFold(window), let image = Self.windowImage(window) else { return }
        play(NSImage(cgImage: image, size: window.frame.size), frame: window.frame, opening: false, part: part) {}
    }

    /// Speelt de vouw af in een doorzichtig venster boven `frame` (schermcoördinaten); `completion` als hij klaar is.
    private func play(_ image: NSImage, frame: CGRect, cornerRadius: CGFloat = 0, shadow: Color = .black.opacity(0.4),
                      shadowRadius: CGFloat = 30, opening: Bool, part: FoldSpeed,
                      completion: @escaping () -> Void) {
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
        overlay.contentView = NSHostingView(rootView: DuoWindowFoldView(
            image: image, size: frame.size, cornerRadius: cornerRadius, shadow: shadow, shadowRadius: shadowRadius,
            model: model))
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
            withAnimation(opening ? DuoFold.opening(part) : DuoFold.closing(part)) {
                model.progress = opening ? 0 : 1
            } completion: {
                finish()
            }
            // Voor als de afronding uitblijft: het echte venster mag nooit verborgen blijven.
            try? await Task.sleep(for: .seconds(part.duration + 1))
            finish()
        }
    }

    // MARK: Afbeelding van een venster

    /// `CGWindowListCreateImage` is verouderd, maar de enige manier om het eigen venster inclusief titelbalk en
    /// mailtekst vast te leggen zonder toestemming voor schermopname. Via `dlsym`, zodat het ook bouwt met een SDK
    /// waarin de declaratie is weggehaald; ontbreekt de functie, dan geen afbeelding.
    private typealias CreateWindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> UnsafeMutableRawPointer?

    private static let createWindowImage: CreateWindowImage? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: CreateWindowImage.self)
    }()

    /// Het venster zoals het nu getekend is, zonder schaduw, op schermresolutie.
    private static func windowImage(_ window: NSWindow) -> CGImage? {
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let createWindowImage, window.windowNumber > 0,
              let raw = createWindowImage(.null, CGWindowListOption.optionIncludingWindow.rawValue,
                                          CGWindowID(window.windowNumber), options.rawValue) else { return nil }
        let image = Unmanaged<CGImage>.fromOpaque(raw).takeRetainedValue()
        guard image.width > 1, image.height > 1, hasContent(image) else { return nil }
        return image
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

private final class WeakView {
    weak var view: NSView?

    init(_ view: NSView) {
        self.view = view
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
    let cornerRadius: CGFloat
    let shadow: Color
    let shadowRadius: CGFloat
    let model: DuoWindowFoldModel

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .modifier(DuoFoldEffect(progress: model.progress, height: size.height, cornerRadius: cornerRadius,
                                    shadow: shadow, shadowRadius: shadowRadius, usesShader: true))
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

/// Meldt waar een mail- of opstelpaneel staat, zodat er bij sluiten een afbeelding van gemaakt kan worden.
struct PanelProbe: NSViewRepresentable {
    let panelID: String

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.panelID = panelID
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.panelID = panelID
    }

    final class ProbeView: NSView {
        var panelID = "" {
            didSet { if panelID != oldValue { DuoWindowFold.shared.register(self, panelID: panelID) } }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
