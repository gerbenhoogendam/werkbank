import AppKit

/// Zet de scrollbalken uit van alle scrollvensters in de vensters van Werkbank.
/// `.scrollIndicators(.hidden)` in SwiftUI is niet altijd genoeg: met een muis of de systeeminstelling
/// "Scrollbalken tonen: altijd" tekent macOS ze toch en ze nemen dan ruimte in. Scrollen met trackpad,
/// muiswiel of toetsen blijft gewoon werken; alleen de balk zelf verdwijnt.
@MainActor
enum ScrollBarHider {
    private static var started = false
    private static var lastScan = Date.distantPast

    static func start() {
        guard !started else { return }
        started = true
        // SwiftUI bouwt weergaven vaak opnieuw op (en zet dan balken terug), dus op elke venster-update
        // opnieuw, maximaal een paar keer per seconde.
        NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { scan(force: false) }
        }
        scan(force: true)
    }

    private static func scan(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastScan) > 0.2 else { return }
        lastScan = now
        for window in NSApp.windows where !(window is NSSavePanel) {
            if let root = window.contentView { hide(in: root) }
        }
    }

    private static func hide(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
        }
        for subview in view.subviews { hide(in: subview) }
    }
}
