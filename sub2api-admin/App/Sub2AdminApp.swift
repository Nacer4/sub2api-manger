import SwiftUI

@main
struct Sub2AdminApp: App {
    @State private var appState = AppState()

    init() {
        AppStateHolder.shared.appState = appState
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}
