import Foundation

/// 服务器连接配置（多实例管理）
struct ServerConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var baseURL: String        // 如 https://api.example.com
    /// 认证模式：jwt = 面板账号登录；adminKey = Admin API Key（服务间调用）
    var authMode: AuthMode
    var adminKey: String       // 仅 adminKey 模式使用（存 UserDefaults，敏感操作时后端仍要求 TOTP）

    enum AuthMode: String, Codable {
        case jwt
        case adminKey
    }

    /// JWT 模式下是否已有有效凭证
    var isAuthenticated: Bool {
        if authMode == .adminKey { return !adminKey.isEmpty }
        return TokenStore.shared.get(serverId: id.uuidString, field: "jwt") != nil
    }

    static func newPlaceholder() -> ServerConfig {
        ServerConfig(
            id: UUID(),
            name: "",
            baseURL: "",
            authMode: .jwt,
            adminKey: ""
        )
    }
}

/// 服务器列表持久化（UserDefaults + Keychain）
@Observable
final class ServerStore {
    static let shared = ServerStore()

    private let key = "sub2admin.servers"
    private let activeKey = "sub2admin.activeServer"

    private(set) var servers: [ServerConfig] = []
    private(set) var activeServerId: UUID?

    init() {
        load()
    }

    var activeServer: ServerConfig? {
        servers.first { $0.id == activeServerId }
    }

    func server(id: UUID?) -> ServerConfig? {
        servers.first { $0.id == id }
    }

    // MARK: - CRUD

    func upsert(_ server: ServerConfig) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
        } else {
            servers.append(server)
        }
        save()
    }

    func delete(_ server: ServerConfig) {
        servers.removeAll { $0.id == server.id }
        TokenStore.shared.clear(serverId: server.id.uuidString)
        if activeServerId == server.id {
            activeServerId = servers.first?.id
        }
        save()
    }

    func setActive(_ server: ServerConfig) {
        activeServerId = server.id
        save()
    }

    // MARK: - Persistence

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let list = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            servers = list
        }
        activeServerId = defaults.string(forKey: activeKey).flatMap(UUID.init(uuidString:))
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: key)
        }
        defaults.set(activeServerId?.uuidString, forKey: activeKey)
    }
}
