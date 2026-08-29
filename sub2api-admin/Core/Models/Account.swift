import Foundation

/// 上游账号（账号管理）模型
/// 契约对照 sub2api `backend/internal/handler/dto/types.go` 的 dto.Account，
/// 列表响应为 AccountWithConcurrency（在 dto.Account 基础上附加实时并发/窗口字段），
/// 全字段宽松 Optional 解码。
struct Account: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let notes: String?                  // 备注（如「对接plus」）
    let platform: String?               // anthropic / openai / gemini / antigravity / grok / ...
    let type: String?                   // oauth / apikey / setup-token / upstream / bedrock / service_account
    let status: String?                 // active / inactive / error / rate_limited / ...
    var schedulable: Bool?
    let priority: Int?
    let rateMultiplier: Double?         // 上游声明倍率
    let concurrency: Int?               // 并发容量上限
    let currentConcurrency: Int?        // 实时并发（列表附加字段 current_concurrency）
    let currentWindowCost: Double?      // 当前 5h 窗口费用（列表附加字段）
    let quotaLimit: Double?             // API Key 账号配额上限（USD）
    let quotaUsed: Double?              // API Key 账号配额已用（USD）
    let proxyId: Int?
    let groupIds: [Int]?
    let groups: [AccountGroupRef]?      // 嵌套分组（含 name）
    let lastUsedAt: String?
    let createdAt: String?
    let expiresAt: Int?                 // Unix 秒；nil = 永不过期
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id, name, notes, platform, type, status, schedulable, priority, groups
        case rateMultiplier = "rate_multiplier"
        case concurrency, groupIds = "group_ids"
        case currentConcurrency = "current_concurrency"
        case currentWindowCost = "current_window_cost"
        case quotaLimit = "quota_limit"
        case quotaUsed = "quota_used"
        case proxyId = "proxy_id"
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case errorMessage = "error_message"
    }
}

/// 账号响应内嵌的分组对象（dto.Group 的宽松子集，仅取展示所需字段）
struct AccountGroupRef: Decodable, Hashable {
    let id: Int
    let name: String?
}
