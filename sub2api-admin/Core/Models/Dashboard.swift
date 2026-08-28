import Foundation

/// 仪表盘快照（/admin/dashboard/snapshot-v2 的常用聚合字段）
struct DashboardSnapshot: Decodable {
    let totalUsers: Int?
    let activeUsers: Int?
    let totalAccounts: Int?
    let activeAccounts: Int?
    let totalApiKeys: Int?
    let totalGroups: Int?
    let todayRequests: Int?
    let todayInputTokens: Int?
    let todayOutputTokens: Int?
    let todayCost: Double?
    let totalRequests: Int?
    let totalTokens: Int?
    let totalCost: Double?
    let errorRate: Double?
    let concurrency: Int?

    enum CodingKeys: String, CodingKey {
        case totalUsers = "total_users"
        case activeUsers = "active_users"
        case totalAccounts = "total_accounts"
        case activeAccounts = "active_accounts"
        case totalApiKeys = "total_api_keys"
        case totalGroups = "total_groups"
        case todayRequests = "today_requests"
        case todayInputTokens = "today_input_tokens"
        case todayOutputTokens = "today_output_tokens"
        case todayCost = "today_cost"
        case totalRequests = "total_requests"
        case totalTokens = "total_tokens"
        case totalCost = "total_cost"
        case errorRate = "error_rate"
        case concurrency
    }
}

/// 趋势数据点
struct TrendPoint: Decodable, Identifiable, Hashable {
    let date: String
    let requests: Int?
    let tokens: Int?
    let cost: Double?

    var id: String { date }
}

/// 用户消费排行条目
struct UserRankingEntry: Decodable, Identifiable, Hashable {
    let userId: Int?
    let email: String?
    let username: String?
    let requests: Int?
    let tokens: Int?
    let cost: Double?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email, username, requests, tokens, cost
    }

    var id: Int { userId ?? 0 }
    var displayName: String { username ?? email ?? "-" }
}

/// 模型维度统计条目
struct ModelStatsEntry: Decodable, Identifiable, Hashable {
    let model: String?
    let requests: Int?
    let tokens: Int?
    let cost: Double?

    var id: String { model ?? "-" }
}
