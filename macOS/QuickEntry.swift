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
    private static let width: CGFloat = 580

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func hide() { panel?.orderOut(nil) }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Verse weergave bij elke keer, zodat de velden leeg zijn en direct focus krijgen.
        let root = QuickEntryView(onClose: { [weak self] in self?.hide() },
                                  onResize: { [weak self] height in self?.resize(to: height) })
            .environment(AppState.shared)
            .modelContainer(Persistence.container)
        panel.contentView = NSHostingView(rootView: root)

        let height: CGFloat = 360   // eerste schatting; de weergave meldt daarna de echte hoogte
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let top = visible.maxY - visible.height * 0.22
            panel.setFrame(NSRect(x: visible.midX - Self.width / 2, y: top - height, width: Self.width, height: height),
                           display: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Nieuwe hoogte met de bovenrand op zijn plek (het paneel groeit naar beneden).
    private func resize(to height: CGFloat) {
        guard let panel, height > 0, abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        panel.setFrame(frame, display: true)
    }

    private func makePanel() -> QuickEntryPanel {
        let panel = QuickEntryPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 360),
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

private struct QuickEntryHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Snelle invoer (⌥⌘T): standaard tijd schrijven (klant, case, uitgevoerd, tijd); als tweede een nieuwe taak in de Inbox.
struct QuickEntryView: View {
    let onClose: () -> Void
    let onResize: (CGFloat) -> Void

    private enum Mode: Hashable { case time, task }

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var mode: Mode = .time
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Soort", selection: $mode) {
                    Text("Tijd schrijven").tag(Mode.time)
                    Text("Taak").tag(Mode.task)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Text("Esc sluit")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, mode == .time ? 6 : 0)

            switch mode {
            case .time:
                SupportEntryView(autofocusClient: true, onFinished: onClose)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            case .task:
                taskField
            }
        }
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ThingsColor.backgroundContent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ThingsColor.separator, lineWidth: 1)
        )
        .background(GeometryReader { geo in
            Color.clear.preference(key: QuickEntryHeightKey.self, value: geo.size.height)
        })
        .onPreferenceChange(QuickEntryHeightKey.self) { onResize($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: mode) { _, new in
            if new == .task {
                Task {
                    try? await Task.sleep(for: .milliseconds(60))
                    focused = true
                }
            }
        }
        .onExitCommand(perform: onClose)
    }

    private var taskField: some View {
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
        .frame(height: 64)
    }

    /// Enter: nieuwe kaart bovenaan de Inbox. `#woord` wordt het klantlabel.
    private func submit() {
        guard BoardService.addQuickEntry(text, in: context) != nil else { return }
        appState.announce("Toegevoegd aan Inbox")
        text = ""
        onClose()
    }
}
