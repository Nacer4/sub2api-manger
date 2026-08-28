import Foundation

/// 全局 AppState 引用（供 ViewModel 获取当前 APIClient）
/// App 启动时由 Sub2AdminApp 注入
@Observable
final class AppStateHolder {
    static let shared = AppStateHolder()
    private init() {}

    var appState: AppState?
    var client: APIClient? { appState?.client }
}
