import AppKit
import KeyboardShortcuts
import SwiftUI
import WerkbankCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Volledig scherm staat als eigen item in het menu Venster (⌃⌘F); niet nog eens automatisch van macOS.
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
        // mailto-links (Werkbank als standaard mailprogramma). Vóór het opstarten, zodat ook de link die de app
        // start binnenkomt.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let link = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let prefill = MailtoLink.parse(link) else { return }
        MainActor.assumeIsolated { DefaultMailApp.compose(prefill) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceSetting.applyStored()
        ScrollBarHider.start()
        BoardService.ensureColumns(in: Persistence.container.mainContext)
        MiniTimerController.shared.start()
        WaitingWatcher.shared.start()
        FollowUpStore.shared.start()
        IdleWatcher.shared.start()
        WerkbankSync.start()
        Dictation.shared.start()
        MailNotifier.shared.start()
        // Wat de mailmodus nodig heeft alvast buiten de hoofdthread inlezen, zodat hij meteen opent.
        MailActivityStore.shared.preload()
        MailListCache.shared.preload()
        // WebKit alvast opstarten, zodat de eerste mail niet hoeft te wachten (niet tijdens het starten zelf).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            WebKitWarmup.start()
        }

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

    /// Klik op het Dock-icoon: altijd het hoofdvenster. Zonder open venster toont macOS het gesloten hoofdvenster
    /// weer (dat vouwt dan open). Staat er een los venster open (mail, opstelvenster, timer), dan doet macOS niets:
    /// dan zelf het hoofdvenster openen, uit het Dock halen of naar voren halen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard flag else {
            DuoWindowFold.shared.prepareReopen()
            return true
        }
        WindowRouter.focusMain()
        return false
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
            // Weergave: wisselen tussen de werkbank en de mailmodus.
            CommandGroup(before: .toolbar) {
                Button("Werkbank") { WindowRouter.show(mail: false) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Mail") { WindowRouter.show(mail: true) }
                    .keyboardShortcut("2", modifiers: .command)
                Divider()
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
        .commands {
            // ⌘N: overal in de app een nieuwe mail (geen nieuw venster).
            CommandGroup(replacing: .newItem) {
                Button("Nieuwe mail") { DefaultMailApp.composeNew() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            PreferencesView()
                .scrollIndicators(.never)
                .environment(appState)
                .modelContainer(Persistence.container)
        }
    }
}
