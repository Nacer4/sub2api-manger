import Foundation

/// 使用记录（/admin/usage）
struct UsageLog: Decodable, Identifiable, Hashable {
    let id: Int?
    let userId: Int?
    let apiKeyId: Int?
    let accountId: Int?
    let model: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationTokens: Int?
    let cacheReadTokens: Int?
    let totalTokens: Int?
    let cost: Double?
    let status: String?
    let latencyMs: Double?
    let stream: Bool?
    let createdAt: String?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case id, model, cost, status, stream
        case userId = "user_id"
        case apiKeyId = "api_key_id"
        case accountId = "account_id"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationTokens = "cache_creation_input_tokens"
        case cacheReadTokens = "cache_read_input_tokens"
        case totalTokens = "total_tokens"
        case latencyMs = "latency_ms"
        case createdAt = "created_at"
        case requestId = "request_id"
    }
}

/// 错误请求（/admin/ops/request-errors）
struct RequestErrorLog: Decodable, Identifiable, Hashable {
    let id: Int?
    let userId: Int?
    let model: String?
    let errorCode: String?
    let errorMessage: String?
    let upstream: String?
    let accountId: Int?
    let createdAt: String?
    let resolved: Bool?

    enum CodingKeys: String, CodingKey {
        case id, model, upstream, resolved
        case userId = "user_id"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case accountId = "account_id"
        case createdAt = "created_at"
    }
}
