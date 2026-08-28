import Foundation

/// 管理端用户模型（字段均为宽松解码，与部署版本差异时不会崩）
struct User: Decodable, Identifiable, Hashable {
    let id: Int
    let email: String?
    let username: String?
    let role: String?          // admin / user
    var status: String?        // active / disabled / banned
    let balance: Double?       // USD
    let groupName: String?
    let concurrencyLimit: Int?
    let rpmLimit: Int?
    let isGroupUnlimited: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, username, role, status, balance
        case groupName = "group_name"
        case concurrencyLimit = "concurrency_limit"
        case rpmLimit = "rpm_limit"
        case isGroupUnlimited = "is_group_unlimited"
        case createdAt = "created_at"
    }

    var displayName: String { username ?? email ?? "用户 #\(id)" }
}

/// 余额调整入参
struct BalanceOperation: Encodable {
    let operation: String      // set / add / subtract
    let amount: Double
    let note: String?
    let idempotencyKey: String?

    enum CodingKeys: String, CodingKey {
        case operation, amount, note
        case idempotencyKey = "idempotency_key"
    }
}

/// 余额变动记录
struct BalanceHistoryEntry: Decodable, Identifiable, Hashable {
    let id: Int?
    let amount: Double?
    let balanceAfter: Double?
    let reason: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, reason
        case balanceAfter = "balance_after"
        case createdAt = "created_at"
    }
}
