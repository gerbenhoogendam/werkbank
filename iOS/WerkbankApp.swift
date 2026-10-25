import SwiftUI
import UIKit

@main
struct WerkbankApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .modelContainer(Persistence.container)
        }
    }
}

/// Snelle acties op het beginscherm (het icoon lang indrukken): "Tijd inspreken" en "Tijd typen" openen de
/// tijdinvoer, meteen in die vorm. Staan in `UIApplicationShortcutItems` (project.yml).
enum QuickAction {
    static let voice = "tijd-inspreken"
    static let keyboard = "tijd-typen"

    @MainActor
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        switch item.type {
        case voice:    AppState.shared.timeEntry = .voice
        case keyboard: AppState.shared.timeEntry = .keyboard
        default:       return false
        }
        return true
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // De app start via de snelle actie.
        if let item = options.shortcutItem { _ = QuickAction.handle(item) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem { _ = QuickAction.handle(item) }
    }

    /// De app draaide al.
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        QuickAction.handle(shortcutItem)
    }
}
