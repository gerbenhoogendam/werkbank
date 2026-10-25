import AppKit

/// Volledig scherm voor het hoofdvenster. De groene knop en Venster › Volledig scherm (⌃⌘F) roepen hier zelf
/// `toggleFullScreen` aan. Weigert macOS het toch, dan staan de gegevens van het venster (niveau, gedrag, maten) op
/// het klembord en meldt de pil dat, zodat de oorzaak te vinden is.
@MainActor
final class FullScreenSupport: NSObject {
    static let shared = FullScreenSupport()

    private weak var window: NSWindow?

    /// Bij het koppelen van het hoofdvenster (`DuoWindowFold.attach`).
    func adopt(_ window: NSWindow) {
        self.window = window
        prepare(window)
        if let button = window.standardWindowButton(.zoomButton) {
            button.isEnabled = true
            button.target = self
            button.action = #selector(zoomPressed(_:))
        }
    }

    func toggle() {
        guard let window = window ?? NSApp.mainWindow else { return }
        let wasFullScreen = window.styleMask.contains(.fullScreen)
        prepare(window)
        if window.level != .normal { window.level = .normal }
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if window.styleMask.contains(.fullScreen) == wasFullScreen { report(window) }
        }
    }

    @objc private func zoomPressed(_ sender: Any?) {
        toggle()
    }

    /// Wat macOS nodig heeft om een venster op volledig scherm te zetten.
    private func prepare(_ window: NSWindow) {
        window.styleMask.insert(.resizable)
        window.collectionBehavior.remove([.fullScreenNone, .fullScreenAuxiliary])
        window.collectionBehavior.insert(.fullScreenPrimary)
        let unlimited = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.maxSize = unlimited
        window.contentMaxSize = unlimited
    }

    private func report(_ window: NSWindow) {
        func size(_ s: NSSize) -> String {
            s.width > 100_000 ? "∞" : "\(Int(s.width))×\(Int(s.height))"
        }
        let screen = window.screen?.frame.size ?? .zero
        let lines = [
            "Volledig scherm lukte niet",
            "niveau: \(window.level.rawValue)",
            "gedrag: \(window.collectionBehavior.rawValue)",
            "stijl: \(window.styleMask.rawValue)",
            "min: \(size(window.minSize)), inhoud min: \(size(window.contentMinSize))",
            "max: \(size(window.maxSize)), inhoud max: \(size(window.contentMaxSize))",
            "venster: \(size(window.frame.size)), scherm: \(size(screen))",
            "zichtbaar: \(window.isVisible), key: \(window.isKeyWindow), klasse: \(type(of: window))",
            "ruimtes apart per scherm: \(NSScreen.screensHaveSeparateSpaces)",
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        AppState.shared.announce("Volledig scherm lukte niet; details op het klembord", seconds: 6)
    }
}
