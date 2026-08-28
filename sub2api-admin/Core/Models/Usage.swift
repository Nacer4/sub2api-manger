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

/// 使用记录筛选条件（对应 GET /admin/usage 的查询参数，源码 usage_handler.go 验证）
struct UsageFilter: Equatable {
    var userId: String = ""
    var accountId: String = ""
    var model: String = ""
    var requestId: String = ""
    var stream: StreamFilter = .all
    var startDate: Date?
    var endDate: Date?

    enum StreamFilter: String, CaseIterable, Identifiable {
        case all = "", yes = "true", no = "false"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .yes: return "流式"
            case .no: return "非流式"
            }
        }
    }

    var isActive: Bool {
        !userId.isEmpty || !accountId.isEmpty || !model.isEmpty || !requestId.isEmpty
            || stream != .all || startDate != nil || endDate != nil
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if !userId.isEmpty { items.append(.init(name: "user_id", value: userId)) }
        if !accountId.isEmpty { items.append(.init(name: "account_id", value: accountId)) }
        if !model.isEmpty { items.append(.init(name: "model", value: model)) }
        if !requestId.isEmpty { items.append(.init(name: "request_id", value: requestId)) }
        if stream != .all { items.append(.init(name: "stream", value: stream.rawValue)) }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let startDate { items.append(.init(name: "start_date", value: formatter.string(from: startDate))) }
        if let endDate { items.append(.init(name: "end_date", value: formatter.string(from: endDate))) }
        return items
    }
}

/// 错误请求（/admin/ops/request-errors；字段对照源码 ops_models.go）
struct RequestErrorLog: Decodable, Identifiable, Hashable {
    let id: Int?
    let createdAt: String?
    let phase: String?
    let type: String?
    let errorOwner: String?
    let errorSource: String?
    let severity: String?
    let statusCode: Int?
    let platform: String?
    let model: String?
    let resolved: Bool?
    let resolvedAt: String?
    let resolvedByUserName: String?
    let clientRequestId: String?
    let requestId: String?
    let message: String?
    let userId: Int?
    let userEmail: String?
    let apiKeyId: Int?
    let accountId: Int?
    let accountName: String?
    let groupId: Int?
    let groupName: String?
    let clientIp: String?

    enum CodingKeys: String, CodingKey {
        case id, phase, type, platform, model, resolved, message
        case createdAt = "created_at"
        case errorOwner = "error_owner"
        case errorSource = "error_source"
        case statusCode = "status_code"
        case resolvedAt = "resolved_at"
        case resolvedByUserName = "resolved_by_user_name"
        case clientRequestId = "client_request_id"
        case requestId = "request_id"
        case userId = "user_id"
        case userEmail = "user_email"
        case apiKeyId = "api_key_id"
        case accountId = "account_id"
        case accountName = "account_name"
        case groupId = "group_id"
        case groupName = "group_name"
        case clientIp = "client_ip"
    }
}

/// 上游错误（/admin/ops/request-errors/:id/upstream-errors）
struct UpstreamErrorLog: Decodable, Identifiable, Hashable {
    let id: Int?
    let createdAt: String?
    let accountId: Int?
    let accountName: String?
    let platform: String?
    let statusCode: Int?
    let errorCode: String?
    let errorMessage: String?
    let latencyMs: Double?

    enum CodingKeys: String, CodingKey {
        case id, platform
        case createdAt = "created_at"
        case accountId = "account_id"
        case accountName = "account_name"
        case statusCode = "status_code"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case latencyMs = "latency_ms"
    }
}
