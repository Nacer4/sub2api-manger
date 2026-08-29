import SwiftUI

@main
struct Sub2AdminApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                // 首次渲染时注入全局引用（避免在 App.init 中读取未安装的 @State）
                .onAppear {
                    AppStateHolder.shared.appState = appState
                }
        }
    }
}
