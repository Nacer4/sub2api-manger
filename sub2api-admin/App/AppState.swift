import Foundation
import Observation

/// 全局应用状态：多服务器配置 + 登录态
@MainActor
@Observable
final class AppState {
    let serverStore = ServerStore.shared

    /// 当前激活的 API 客户端（切换服务器 / 登录后重建）
    private(set) var client: APIClient?

    /// 登录态（仅 JWT 模式使用；AdminKey 模式视为免登录）
    private(set) var isSessionValid = false

    var activeServer: ServerConfig? {
        didSet { rebuildClient() }
    }

    init() {
        activeServer = serverStore.activeServer
        isSessionValid = activeServer?.isAuthenticated ?? false
        rebuildClient()
    }

    private func rebuildClient() {
        guard let server = activeServer else {
            client = nil
            return
        }
        let newClient = APIClient(server: server)
        // 401 确认失效（refresh 失败 / AdminKey 无效）→ 全局登出回登录页
        newClient.onSessionInvalid = { [weak self] in
            Task { @MainActor in
                self?.sessionEnded()
            }
        }
        client = newClient
    }

    /// 登出 / Token 失效
    func sessionEnded() {
        isSessionValid = false
        if let id = activeServer?.id {
            TokenStore.shared.clear(serverId: id.uuidString)
        }
        rebuildClient()
    }

    /// 切换服务器（activeServer 的 didSet 已重建 client，无需再显式调用）
    func switchServer(_ server: ServerConfig) {
        serverStore.setActive(server)
        activeServer = server
        isSessionValid = server.isAuthenticated
    }

    /// 服务器配置更新后刷新；被删除的活跃服务器置空（触发登出态）
    func refreshServer() {
        activeServer = serverStore.server(id: activeServer?.id)
        isSessionValid = activeServer?.isAuthenticated ?? false
    }
}
