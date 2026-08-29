import Foundation

/// 上游账号（账号管理）模型
struct Account: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let platform: String?      // claude / openai / gemini / antigravity / grok / ...
    let authType: String?      // oauth / api_key / ...
    let tier: String?          // free / pro / max5 / max20 ...
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

    // 信息卡展示字段（服务端聚合）
    let capacityUsed: Int?            // 容量已用
    let capacityLimit: Int?           // 容量上限
    let tags: [String]?               // 标签（Compact / Auto ...）
    let groupNote: String?            // 分组备注（如 对接plus）
    let rateMultiplier: Double?       // 上游声明倍率
    let windowRequests: String?       // 用量窗口请求数（如 26.5K）
    let windowTokens: String?         // 用量窗口 Token（如 3.0B）
    let windowAmount: Double?         // A：账号侧费用
    let windowUserAmount: Double?     // U：用户侧费用
    let expiredAt: String?            // 过期时间（- 表示未设置）

    enum CodingKeys: String, CodingKey {
        case id, name, platform, status, priority, weight, email, tier, tags
        case authType = "auth_type"
        case schedulable
        case proxyId = "proxy_id"
        case groupId = "group_id"
        case clientId = "client_id"
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case errorMessage = "error_message"
        case capacityUsed = "capacity_used"
        case capacityLimit = "capacity_limit"
        case groupNote = "group_note"
        case rateMultiplier = "rate_multiplier"
        case windowRequests = "window_requests"
        case windowTokens = "window_tokens"
        case windowAmount = "window_amount"
        case windowUserAmount = "window_user_amount"
        case expiredAt = "expired_at"
    }
}
