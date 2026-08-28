import Foundation

/// 上游账号（账号池）模型
struct Account: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let platform: String?      // claude / openai / gemini / antigravity / grok / ...
    let authType: String?      // oauth / api_key / ...
    let status: String?        // active / error / rate_limited / expired ...
    var schedulable: Bool?
    let priority: Int?
    let weight: Int?
    let proxyId: Int?
    let groupId: Int?
    let clientId: String?
    let email: String?
    let lastUsedAt: String?
    let createdAt: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id, name, platform, status, priority, weight, email
        case authType = "auth_type"
        case schedulable
        case proxyId = "proxy_id"
        case groupId = "group_id"
        case clientId = "client_id"
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case errorMessage = "error_message"
    }
}

/// 账号运维操作（对应 POST /admin/accounts/:id/<action>）
enum AccountAction: String, CaseIterable, Identifiable {
    case test = "test"
    case refresh = "refresh"
    case clearError = "clear-error"
    case clearRateLimit = "clear-rate-limit"
    case resetQuota = "reset-quota"
    case recoverState = "recover-state"
    case refreshTier = "refresh-tier"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .test: return "测试可用性"
        case .refresh: return "刷新凭证"
        case .clearError: return "清除错误状态"
        case .clearRateLimit: return "清除限流状态"
        case .resetQuota: return "重置配额"
        case .recoverState: return "恢复状态"
        case .refreshTier: return "刷新账号等级"
        }
    }

    var symbol: String {
        switch self {
        case .test: return "checkmark.seal"
        case .refresh: return "arrow.clockwise"
        case .clearError: return "xmark.bubble"
        case .clearRateLimit: return "gauge.with.needle"
        case .resetQuota: return "arrow.counterclockwise.circle"
        case .recoverState: return "wand.and.stars"
        case .refreshTier: return "sparkles"
        }
    }
}

/// 账号当日统计
struct AccountTodayStats: Decodable, Hashable {
    let requests: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let cost: Double?

    enum CodingKeys: String, CodingKey {
        case requests, cost
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}
