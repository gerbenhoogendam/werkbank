import AppKit
import CoreImage
import SwiftUI

/// De Duo-vouw op een afbeelding, in Core Animation, in een doorzichtig venster boven de plek waar het om gaat. Core
/// Animation draait in de render-server, dus de vouw blijft vloeiend als de app het druk heeft (opstarten, mail laden).
/// - Hoofdvenster en losse opstelvensters bij openen en sluiten. Titelbalk en knoppenbalk zijn AppKit, vandaar de
///   afbeelding. Bij openen staat het echte venster zolang achter de bureaubladachtergrond: daar wordt het opgebouwd
///   zonder dat je het ziet.
/// - Mail- en opstelpanelen bij sluiten en versturen (zie `PanelStore`): het paneel verdwijnt, de afbeelding vouwt weg.
/// Lukt de afbeelding niet, dan gaat het zonder vouw (vensters) of met de vouw op het paneel zelf (`DuoFoldEffect`).
@MainActor
final class DuoWindowFold {
    static let shared = DuoWindowFold()

    /// Gekoppelde vensters; `true` voor het hoofdvenster (dat vouwt ook bij stoppen met ⌘Q).
    private var windows: [ObjectIdentifier: Bool] = [:]
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var overlays: [NSWindow] = []
    /// Gesloten vensters die macOS bij opnieuw openen hergebruikt (Dock, menubalk): dan weer openvouwen.
    private var closed: [ObjectIdentifier: ClosedWindow] = [:]
    /// Waar de mail- en opstelpanelen staan (`PanelProbe`).
    private var probes: [String: WeakView] = [:]
    private var isQuitting = false
    /// Het volgende venster dat sluit, sluit na versturen (los opstelvenster).
    private var nextCloseIsSend = false

    /// Onder de bureaubladachtergrond.
    private static let hiddenLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)

    /// `reused`: een eerder gesloten venster dat weer getoond wordt (de inhoud staat er al).
    func attach(_ window: NSWindow, isMain: Bool, reused: Bool = false) {
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
        unfold(window, settle: reused ? .milliseconds(60) : .milliseconds(300))
    }

    /// Vlak voordat macOS een gesloten venster weer toont (Dock, menubalk): alvast achter de bureaubladachtergrond,
    /// zodat het niet eerst even plat in beeld staat. Komt het binnen 1,5 s niet tevoorschijn, dan terug zoals het was.
    func prepareReopen() {
        let waiting = closed.values.compactMap(\.window).filter { !$0.isVisible }
        for window in waiting { window.level = Self.hiddenLevel }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            for window in waiting where window.level == Self.hiddenLevel && windows[ObjectIdentifier(window)] == nil {
                window.level = .normal
            }
        }
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
        play(image, frame: window.frame, cornerRadius: nil, shadow: .window, opening: false, part: .windowClose,
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
        play(piece, frame: window.convertToScreen(rect), cornerRadius: 12, shadow: .panel, opening: false,
             part: part) {}
        return true
    }

    // MARK: Vensters

    private func canFold(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && !window.styleMask.contains(.fullScreen)
            && window.level != Self.hiddenLevel
    }

    private func unfold(_ window: NSWindow, settle: Duration) {
        let level = window.level == Self.hiddenLevel ? .normal : window.level
        guard !window.styleMask.contains(.fullScreen) else {
            window.level = level
            return
        }
        window.level = Self.hiddenLevel
        Task { @MainActor in
            // Eerst laten opbouwen (board, agenda), dan vastleggen.
            try? await Task.sleep(for: settle)
            var image = window.isVisible ? Self.windowImage(window) : nil
            for _ in 0..<5 where image == nil && window.isVisible {
                try? await Task.sleep(for: .milliseconds(100))
                image = Self.windowImage(window)
            }
            guard let image else {
                window.level = level
                return
            }
            play(image, frame: window.frame, cornerRadius: nil, shadow: .window, opening: true, part: .windowOpen) {
                window.level = level
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func windowWillClose(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        let isMain = windows.removeValue(forKey: key) ?? false
        if let observer = observers.removeValue(forKey: key) { NotificationCenter.default.removeObserver(observer) }
        // Pas als het venster echt weg is; anders telt de vouw erboven als "weer in beeld".
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            watchForReappearance(window, isMain: isMain)
        }
        let part: FoldSpeed = nextCloseIsSend ? .send : .windowClose
        nextCloseIsSend = false
        guard !isQuitting, canFold(window), let image = Self.windowImage(window) else { return }
        play(image, frame: window.frame, cornerRadius: nil, shadow: .window, opening: false, part: part) {}
    }

    /// Een gesloten venster dat later weer getoond wordt (macOS maakt dan geen nieuw venster): opnieuw koppelen.
    private func watchForReappearance(_ window: NSWindow, isMain: Bool) {
        let entry = ClosedWindow(window: window, isMain: isMain)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
            entry.observers.append(NotificationCenter.default.addObserver(forName: name, object: window,
                                                                          queue: .main) { note in
                MainActor.assumeIsolated {
                    guard let window = note.object as? NSWindow else { return }
                    DuoWindowFold.shared.windowReappeared(window)
                }
            })
        }
        closed = closed.filter { $0.value.window != nil }
        closed[ObjectIdentifier(window)] = entry
    }

    private func windowReappeared(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard window.isVisible, window.occlusionState.contains(.visible) || window.isKeyWindow,
              let entry = closed.removeValue(forKey: key) else { return }
        for observer in entry.observers { NotificationCenter.default.removeObserver(observer) }
        attach(window, isMain: entry.isMain, reused: true)
    }

    /// Speelt de vouw af boven `frame` (schermcoördinaten); `completion` als hij klaar is. `cornerRadius` nil: de vorm
    /// komt uit de afbeelding zelf (venster met eigen ronde hoeken).
    private func play(_ image: CGImage, frame: CGRect, cornerRadius: CGFloat?, shadow: DuoShadow, opening: Bool,
                      part: FoldSpeed, completion: @escaping () -> Void) {
        let margin: CGFloat = 80   // ruimte voor de schaduw
        let overlayFrame = frame.insetBy(dx: -margin, dy: -margin)
        let overlay = NSWindow(contentRect: overlayFrame, styleMask: .borderless, backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.isReleasedWhenClosed = false
        overlay.animationBehavior = .none
        overlay.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        let host = NSView(frame: CGRect(origin: .zero, size: overlayFrame.size))
        let root = CALayer()
        root.frame = host.bounds
        host.layer = root
        host.wantsLayer = true
        overlay.contentView = host

        let fold = DuoFoldLayers(in: root, rect: CGRect(x: margin, y: margin, width: frame.width, height: frame.height),
                                 image: image, cornerRadius: cornerRadius, shadow: shadow)
        fold.show(progress: opening ? 1 : 0)
        overlay.orderFrontRegardless()
        overlay.displayIfNeeded()
        CATransaction.flush()
        overlays.append(overlay)

        let finish = { [weak self] in
            guard !fold.isFinished else { return }
            fold.isFinished = true
            completion()
            // Pas weghalen als het echte venster weer getekend is.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                overlay.orderOut(nil)
                self?.overlays.removeAll { $0 === overlay }
            }
        }
        let scale = CGFloat(image.width) / max(frame.width, 1)
        Task { @MainActor in
            // Waas één keer vooraf (± 10–30 ms); daarna verschuift per beeld alleen nog het verloop.
            let levels = await Task.detached(priority: .userInitiated) {
                DuoFrost.levels(of: image, scale: scale)
            }.value
            fold.setFrost(levels)
            fold.run(from: opening ? 1 : 0, to: opening ? 0 : 1, duration: part.duration,
                     timing: DuoFold.timing(opening: opening), completion: finish)
            // Voor als de afronding uitblijft: het echte venster mag nooit verborgen blijven.
            try? await Task.sleep(for: .seconds(part.duration + 1.5))
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

private final class ClosedWindow {
    weak var window: NSWindow?
    let isMain: Bool
    var observers: [NSObjectProtocol] = []

    init(window: NSWindow, isMain: Bool) {
        self.window = window
        self.isMain = isMain
    }
}

private final class WeakView {
    weak var view: NSView?

    init(_ view: NSView) {
        self.view = view
    }
}

/// Schaduw onder de vouw: een vaste vorm (`shadowPath`), dus niet elk beeld opnieuw uitgerekend.
private struct DuoShadow {
    let color: CGColor
    let opacity: Float
    let radius: CGFloat
    let offset: CGFloat
    let cornerRadius: CGFloat

    static let window = DuoShadow(color: CGColor(gray: 0, alpha: 1), opacity: 0.35, radius: 30, offset: 14,
                                  cornerRadius: 16)

    /// Zoals `ThingsColor.cardShadow`.
    @MainActor static var panel: DuoShadow {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return DuoShadow(color: CGColor(gray: 0, alpha: 1), opacity: dark ? 0.45 : 0.10, radius: 18, offset: 6,
                         cornerRadius: 12)
    }
}

/// Vooraf berekende waas: twee lagen op lage resolutie (meer is niet nodig voor iets wat wazig is).
private enum DuoFrost {
    /// Onveranderlijke afbeeldingen: veilig tussen threads.
    struct Levels: @unchecked Sendable {
        let medium: CGImage?
        let heavy: CGImage?
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// `scale`: pixels per punt van `image`.
    static func levels(of image: CGImage, scale: CGFloat) -> Levels {
        Levels(medium: blurred(image, radius: DuoFold.mediumFrost, scale: scale, downscale: 0.5),
               heavy: blurred(image, radius: DuoFold.heavyFrost, scale: scale, downscale: 0.25))
    }

    private static func blurred(_ image: CGImage, radius: Double, scale: CGFloat, downscale: CGFloat) -> CGImage? {
        let small = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: downscale, y: downscale))
        let extent = small.extent.integral
        let sigma = radius / 2.5 * Double(scale * downscale)   // waasstraal ≈ 2,5 sigma
        let output = small.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        return context.createCGImage(output, from: extent)
    }
}

/// De afbeelding als lagen: kantelen om de onderrand, de twee waaslagen met elk een verloop als masker (scherp onder,
/// wazig boven), en de schaduw. De lagen staan niet gespiegeld: y loopt omhoog, de onderrand is y = 0.
@MainActor
private final class DuoFoldLayers {
    var isFinished = false

    private let container = CALayer()
    private let shadowCaster = CALayer()
    private let plate = CALayer()
    private let medium = CALayer()
    private let heavy = CALayer()
    private let mediumMask = CAGradientLayer()
    private let heavyMask = CAGradientLayer()
    private let height: Double
    private let shadowOpacity: Float

    /// Punten van het verloop, van de onderrand (0) naar de bovenrand (1).
    private static let fractions = (0...8).map { Double($0) / 8 }

    init(in root: CALayer, rect: CGRect, image: CGImage, cornerRadius: CGFloat?, shadow: DuoShadow) {
        height = rect.height
        shadowOpacity = shadow.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        container.frame = rect
        var perspective = CATransform3DIdentity
        perspective.m34 = -DuoFold.perspective / max(rect.width, rect.height)
        container.sublayerTransform = perspective
        root.addSublayer(container)

        let bounds = CGRect(origin: .zero, size: rect.size)
        for layer in [shadowCaster, plate] {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0)   // kantelen om de onderrand
            layer.bounds = bounds
            layer.position = CGPoint(x: bounds.midX, y: 0)
            container.addSublayer(layer)
        }
        shadowCaster.shadowPath = CGPath(roundedRect: bounds, cornerWidth: shadow.cornerRadius,
                                         cornerHeight: shadow.cornerRadius, transform: nil)
        shadowCaster.shadowColor = shadow.color
        shadowCaster.shadowRadius = shadow.radius
        shadowCaster.shadowOffset = CGSize(width: 0, height: -shadow.offset)

        plate.contents = image
        plate.contentsGravity = .resize
        if let cornerRadius {
            plate.cornerRadius = cornerRadius
            plate.cornerCurve = .continuous
            plate.masksToBounds = true
        } else {
            let mask = CALayer()
            mask.frame = bounds
            mask.contents = image
            mask.contentsGravity = .resize
            plate.mask = mask
        }
        for (layer, mask) in [(medium, mediumMask), (heavy, heavyMask)] {
            layer.frame = bounds
            layer.contentsGravity = .resize
            Self.setUp(mask, bounds: bounds)
            layer.mask = mask
            plate.addSublayer(layer)
        }
        CATransaction.commit()
    }

    private static func setUp(_ gradient: CAGradientLayer, bounds: CGRect) {
        gradient.frame = bounds
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.locations = fractions.map { NSNumber(value: $0) }
    }

    func setFrost(_ levels: DuoFrost.Levels) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        medium.contents = levels.medium
        heavy.contents = levels.heavy
        CATransaction.commit()
    }

    /// Zet de stand vast, zonder animatie.
    func show(progress: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, keyPath, value) in values(at: progress) { layer.setValue(value, forKeyPath: keyPath) }
        CATransaction.commit()
    }

    /// Van `from` naar `to`, als keyframes langs de tijdcurve: de render-server speelt het af.
    func run(from: Double, to: Double, duration: Double, timing: CAMediaTimingFunction,
             completion: @escaping () -> Void) {
        let steps = 24
        let samples = (0...steps).map { values(at: from + (to - from) * Double($0) / Double(steps)) }
        let keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        for (index, (layer, keyPath, _)) in samples[0].enumerated() {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = samples.map { $0[index].value }
            animation.keyTimes = keyTimes
            animation.duration = duration
            animation.timingFunction = timing
            animation.calculationMode = .linear
            layer.setValue(samples[steps][index].value, forKeyPath: keyPath)   // eindstand
            layer.add(animation, forKey: keyPath)
        }
        CATransaction.commit()
    }

    private func values(at progress: Double) -> [(layer: CALayer, keyPath: String, value: Any)] {
        let frost = Self.fractions.map { DuoFold.frost(at: $0, height: height, progress: progress) }
        let rotation = NSValue(caTransform3D: CATransform3DMakeRotation(-DuoFold.tilt(progress), 1, 0, 0))
        return [
            (plate, "transform", rotation),
            (shadowCaster, "transform", rotation),
            (shadowCaster, "shadowOpacity", NSNumber(value: shadowOpacity * Float(1 - min(progress * 2.5, 1)))),
            (container, "opacity", NSNumber(value: Float(DuoFold.opacity(progress)))),
            (mediumMask, "colors", frost.map { CGColor(gray: 1, alpha: DuoFold.mediumWeight($0)) }),
            (heavyMask, "colors", frost.map { CGColor(gray: 1, alpha: DuoFold.heavyWeight($0)) }),
        ]
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
