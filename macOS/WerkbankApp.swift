import AppKit
import KeyboardShortcuts
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Volledig scherm staat als eigen item in het menu Venster (⌃⌘F); niet nog eens automatisch van macOS.
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceSetting.applyStored()
        ScrollBarHider.start()
        BoardService.ensureColumns(in: Persistence.container.mainContext)
        MiniTimerController.shared.start()
        WaitingWatcher.shared.start()
        IdleWatcher.shared.start()
        WerkbankSync.start()
        Dictation.shared.start()

        // Globale sneltoets: werkt ook als Werkbank niet op de voorgrond staat.
        KeyboardShortcuts.onKeyUp(for: .quickEntry) {
            Task { @MainActor in QuickEntryController.shared.toggle() }
        }
        KeyboardShortcuts.onKeyUp(for: .quickEntryAlt) {
            Task { @MainActor in QuickEntryController.shared.toggle() }
        }
    }

    /// De app draait door als het hoofdvenster gesloten is (de menubalkknop blijft actief).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Klik op het Dock-icoon zonder open venster: macOS toont het gesloten hoofdvenster weer; dat vouwt dan open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { DuoWindowFold.shared.prepareReopen() }
        return true
    }

    /// Stoppen: eerst vouwt het hoofdvenster dicht.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let folding = DuoWindowFold.shared.foldForQuit {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return folding ? .terminateLater : .terminateNow
    }
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
        .commands {
            CommandGroup(after: .windowSize) {
                Button("Volledig scherm") { FullScreenSupport.shared.toggle() }
                    .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .scrollIndicators(.never)
                .environment(appState)
                .modelContainer(Persistence.container)
        } label: {
            MenuBarLabel()
                .modelContainer(Persistence.container)
        }
        .menuBarExtraStyle(.window)

        // Losgehaalde opstelvensters (bijvoorbeeld op een ander scherm).
        WindowGroup("Mail", id: "compose", for: DetachedCompose.self) { $value in
            if let value {
                DetachedComposeWindow(value: value)
                    .environment(appState)
                    .modelContainer(Persistence.container)
            }
        }
        .defaultSize(width: 760, height: 680)
        .commands { CommandGroup(replacing: .newItem) {} }

        Settings {
            PreferencesView()
                .scrollIndicators(.never)
                .environment(appState)
                .modelContainer(Persistence.container)
        }
    }
}
