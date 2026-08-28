import Foundation
import Observation

/// 全局应用状态：多服务器配置 + 登录态
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
        client = APIClient(server: server)
    }

    /// JWT 登录成功
    func sessionStarted() {
        isSessionValid = true
        rebuildClient()
    }

    /// 登出 / Token 失效
    func sessionEnded() {
        isSessionValid = false
        if let id = activeServer?.id {
            try? TokenStore.shared.clear(serverId: id)
        }
        rebuildClient()
    }

    /// 切换服务器
    func switchServer(_ server: ServerConfig) {
        serverStore.setActive(server)
        activeServer = server
        isSessionValid = server.isAuthenticated
        rebuildClient()
    }

    /// 服务器配置更新后刷新
    func refreshServer() {
        if let server = serverStore.server(id: activeServer?.id) {
            activeServer = server
        }
    }
}
