import AppKit
import ScreenCaptureKit

/// De screenshot bij een verbetering op de Mac: het hoofdvenster van Werkbank (ook als er iets voor ligt); staat dat
/// niet in beeld, het scherm met de muis. Daarvoor is toestemming voor schermopname nodig (Systeeminstellingen ›
/// Privacy en beveiliging). Zonder toestemming: wat het hoofdvenster zelf kan tekenen (mails en sommige effecten
/// blijven dan leeg).
@MainActor
enum FeedbackScreenshot {
    private static let askedKey = "feedback.askedScreenCapture"

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// De eerste keer vraagt macOS het zelf; daarna opent Systeeminstellingen op de juiste plek.
    static func requestPermission() {
        if UserDefaults.standard.bool(forKey: askedKey),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        } else {
            UserDefaults.standard.set(true, forKey: askedKey)
            _ = CGRequestScreenCaptureAccess()
        }
    }

    static func capture() async -> CapturedScreen {
        let date = Date()
        let window = mainWindow
        if hasPermission, let image = await screenCapture(window: window) {
            return CapturedScreen(data: ScreenshotEncoding.jpeg(image), date: date)
        }
        if !hasPermission, !UserDefaults.standard.bool(forKey: askedKey) {
            UserDefaults.standard.set(true, forKey: askedKey)
            _ = CGRequestScreenCaptureAccess()
        }
        return CapturedScreen(data: window.flatMap(drawn).flatMap { ScreenshotEncoding.jpeg($0) }, date: date)
    }

    /// Het hoofdvenster (niet Voorkeuren of een los paneel).
    static var mainWindow: NSWindow? {
        let candidates = NSApp.windows.filter {
            $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain && !($0 is NSPanel)
                && !($0.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false)
        }
        return candidates.first { $0.identifier?.rawValue.hasPrefix("main") == true }
            ?? candidates.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private static func screenCapture(window: NSWindow?) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let filter: SCContentFilter
            let size: CGSize
            if let window, let match = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
                filter = SCContentFilter(desktopIndependentWindow: match)
                size = match.frame.size
            } else {
                let mouse = NSEvent.mouseLocation
                let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
                let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                guard let display = content.displays.first(where: { $0.displayID == number?.uint32Value })
                    ?? content.displays.first else { return nil }
                filter = SCContentFilter(display: display, excludingWindows: [])
                size = CGSize(width: display.width, height: display.height)
            }
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = max(1, Int(size.width * scale))
            configuration.height = max(1, Int(size.height * scale))
            configuration.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            return nil
        }
    }

    private static func drawn(_ window: NSWindow) -> CGImage? {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }
}
