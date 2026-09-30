import AppKit
import KeyboardShortcuts
import SwiftData
import SwiftUI

extension KeyboardShortcuts.Name {
    /// Globale sneltoets voor snelle invoer (standaard ⌥⌘T, aanpasbaar in Instellingen).
    static let quickEntry = Self("quickEntry", default: .init(.t, modifiers: [.option, .command]))
}

/// Zwevend invoerpaneel in Spotlight-stijl, boven alle apps.
private final class QuickEntryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    /// Klikken buiten het paneel sluit het.
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}

@MainActor
final class QuickEntryController {
    static let shared = QuickEntryController()

    private var panel: QuickEntryPanel?

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func hide() { panel?.orderOut(nil) }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Verse weergave bij elke keer, zodat het veld leeg is en direct focus krijgt.
        let root = QuickEntryView(onClose: { [weak self] in self?.hide() })
            .environment(AppState.shared)
            .modelContainer(Persistence.container)
        let host = NSHostingView(rootView: root)
        panel.contentView = host
        panel.setContentSize(NSSize(width: 580, height: 64))

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                         y: visible.maxY - visible.height * 0.28 - size.height))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> QuickEntryPanel {
        let panel = QuickEntryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 64),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        return panel
    }
}

struct QuickEntryView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: BoardColumn.inbox.symbol)
                .font(.system(size: 20))
                .foregroundStyle(BoardColumn.inbox.color)
            TextField("Nieuwe kaart in Inbox — #klant voor een label", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .foregroundStyle(ThingsColor.textPrimary)
                .focused($focused)
                .onSubmit(submit)
        }
        .padding(.horizontal, 18)
        .frame(width: 580, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ThingsColor.backgroundContent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ThingsColor.separator, lineWidth: 1)
        )
        .task {
            // Het paneel wordt net key; geef het venster even de tijd voordat het veld focus vraagt.
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
        .onExitCommand(perform: onClose)
    }

    /// Enter: nieuwe kaart bovenaan de Inbox. `#woord` wordt het klantlabel.
    private func submit() {
        guard BoardService.addQuickEntry(text, in: context) != nil else { return }
        appState.showToast("Toegevoegd aan Inbox")
        text = ""
        onClose()
    }
}
