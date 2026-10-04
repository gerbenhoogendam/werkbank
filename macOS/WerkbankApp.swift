import AppKit
import KeyboardShortcuts
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceSetting.applyStored()
        ScrollBarHider.start()
        BoardService.ensureColumns(in: Persistence.container.mainContext)
        MiniTimerController.shared.start()

        // Globale sneltoets: werkt ook als Werkbank niet op de voorgrond staat.
        KeyboardShortcuts.onKeyUp(for: .quickEntry) {
            Task { @MainActor in QuickEntryController.shared.toggle() }
        }
    }

    /// De app draait door als het hoofdvenster gesloten is (de menubalkknop blijft actief).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct WerkbankApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared
    @State private var drag = DragCoordinator()

    var body: some Scene {
        Window("Werkbank", id: "main") {
            MainView()
                .environment(appState)
                .environment(drag)
                .modelContainer(Persistence.container)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .defaultSize(width: 1440, height: 900)

        MenuBarExtra {
            MenuBarPanel()
                .scrollIndicators(.hidden)
                .environment(appState)
                .modelContainer(Persistence.container)
        } label: {
            MenuBarLabel()
                .modelContainer(Persistence.container)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .scrollIndicators(.hidden)
                .environment(appState)
                .modelContainer(Persistence.container)
        }
    }
}
