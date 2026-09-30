import SwiftUI

@main
struct WerkbankApp: App {
    @State private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .modelContainer(Persistence.container)
        }
    }
}
