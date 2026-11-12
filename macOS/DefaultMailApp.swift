import AppKit
import SwiftUI
import WerkbankCore

/// Werkbank als standaard mailprogramma: een mailto-link opent een nieuwe mail, al ingevuld.
@MainActor
enum DefaultMailApp {
    /// Het programma dat nu mailto-links opent.
    static var current: URL? {
        URL(string: "mailto:").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }

    static var isWerkbank: Bool {
        guard let current, let identifier = Bundle(url: current)?.bundleIdentifier else { return false }
        return identifier == Bundle.main.bundleIdentifier
    }

    static var currentName: String? {
        current.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }

    static func makeWerkbank() async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "mailto")
    }

    /// Een mailto-link: het hoofdvenster naar voren en een nieuwe mail.
    static func compose(_ prefill: MailPrefill) {
        if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            WindowRouter.showMain()
        }
        PanelStore.shared.open(.compose(ComposeRef(mode: .new, source: nil, prefill: prefill)))
    }
}

extension DefaultMailApp {
    /// ⌘N, waar je ook bent in de app: het hoofdvenster naar voren en een lege nieuwe mail.
    static func composeNew() {
        if DuoWindowFold.shared.mainWindow?.isKeyWindow != true { WindowRouter.focusMain() }
        PanelStore.shared.open(.compose(ComposeRef(mode: .new, source: nil)))
    }
}

/// Voorkeuren › Mail: welk programma mailto-links opent.
struct DefaultMailAppSection: View {
    @State private var isWerkbank = DefaultMailApp.isWerkbank
    @State private var currentName = DefaultMailApp.currentName
    @State private var error: String?

    var body: some View {
        Section("Standaard mailprogramma") {
            LabeledContent("Nu", value: isWerkbank ? "Werkbank" : (currentName ?? "Geen"))
            if !isWerkbank {
                Button("Werkbank als standaard instellen") {
                    Task {
                        do {
                            try await DefaultMailApp.makeWerkbank()
                            error = nil
                        } catch {
                            self.error = "Instellen lukte niet: \(error.localizedDescription). Kies Werkbank in Mail › Instellingen › Algemeen › Standaard e-mailprogramma."
                        }
                        refresh()
                    }
                }
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        isWerkbank = DefaultMailApp.isWerkbank
        currentName = DefaultMailApp.currentName
    }
}
