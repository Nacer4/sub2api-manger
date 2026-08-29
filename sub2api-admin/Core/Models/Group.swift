import Foundation

/// 分组（账号管理 / 模型路由）
/// 契约对照 sub2api `backend/internal/handler/dto/types.go` 的 dto.AdminGroup。
/// 注意：不命名为 Group，避免与 SwiftUI.Group 冲突。
struct AccountGroup: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let description: String?
    let platform: String?                 // anthropic / openai / gemini / antigravity / grok / kimi / zhipu / deepseek / composite
    let rateMultiplier: Double?           // 费率倍数 0.1x
    let isExclusive: Bool?                // true = 私有/专属，false = 公开
    let status: String?
    let subscriptionType: String?         // standard / subscription
    let accountCount: Int?                // 总账号数
    let activeAccountCount: Int?          // 可用账号数
    let rateLimitedAccountCount: Int?     // 限流账号数
    let dailyLimitUsd: Double?
    let createdAt: String?
    let updatedAt: String?

    /// 计费类型展示值：standard → 标准（余额），subscription → 标准（订阅）
    var billingDisplay: String? {
        switch subscriptionType {
        case "standard": return "标准（余额）"
        case "subscription": return "标准（订阅）"
        default: return subscriptionType
        }
    }

    /// 类型展示值：公开 / 私有
    var typeDisplay: String? {
        (isExclusive ?? false) ? "私有" : "公开"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, platform, status
        case rateMultiplier = "rate_multiplier"
        case isExclusive = "is_exclusive"
        case subscriptionType = "subscription_type"
        case accountCount = "account_count"
        case activeAccountCount = "active_account_count"
        case rateLimitedAccountCount = "rate_limited_account_count"
        case dailyLimitUsd = "daily_limit_usd"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// 分组容量汇总（GET /admin/groups/capacity-summary）
/// 契约对照 sub2api `service.GroupCapacitySummary`
struct GroupCapacitySummary: Decodable, Hashable {
    let groupId: Int
    let concurrencyUsed: Int
    let concurrencyMax: Int
    let sessionsUsed: Int?
    let sessionsMax: Int?
    let rpmUsed: Int?
    let rpmMax: Int?

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case concurrencyUsed = "concurrency_used"
        case concurrencyMax = "concurrency_max"
        case sessionsUsed = "sessions_used"
        case sessionsMax = "sessions_max"
        case rpmUsed = "rpm_used"
        case rpmMax = "rpm_max"
    }
}

/// 分组用量汇总（GET /admin/groups/usage-summary）
/// 契约对照 sub2api `usagestats.GroupUsageSummary`
struct GroupUsageSummary: Decodable, Hashable {
    let groupId: Int
    let todayCost: Double
    let yesterdayCost: Double
    let totalCost: Double

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case todayCost = "today_cost"
        case yesterdayCost = "yesterday_cost"
        case totalCost = "total_cost"
    }
}
