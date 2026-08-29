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

    enum CodingKeys: String, CodingKey {
        case id, name, platform, status, priority, weight, email, tier
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
