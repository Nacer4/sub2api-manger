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

/// 错误请求（/admin/ops/request-errors；字段对照源码 service/ops_models.go OpsErrorLog）
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
    let apiKeyName: String?
    let accountId: Int?
    let accountName: String?
    let groupId: Int?
    let groupName: String?
    let clientIp: String?
    let requestPath: String?
    let stream: Bool?
    let requestedModel: String?
    let upstreamModel: String?
    let userAgent: String?

    enum CodingKeys: String, CodingKey {
        case id, phase, type, platform, model, resolved, message, stream
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
        case apiKeyName = "api_key_name"
        case accountId = "account_id"
        case accountName = "account_name"
        case groupId = "group_id"
        case groupName = "group_name"
        case clientIp = "client_ip"
        case requestPath = "request_path"
        case requestedModel = "requested_model"
        case upstreamModel = "upstream_model"
        case userAgent = "user_agent"
    }
}

/// 错误请求详情（GET /admin/ops/request-errors/:id；OpsErrorLogDetail 额外字段）
struct RequestErrorDetail: Decodable {
    let errorBody: String?
    let upstreamStatusCode: Int?
    let upstreamErrorMessage: String?
    let upstreamErrorDetail: String?
    let authLatencyMs: Double?
    let routingLatencyMs: Double?
    let upstreamLatencyMs: Double?
    let responseLatencyMs: Double?
    let timeToFirstTokenMs: Double?
    let isBusinessLimited: Bool?
    let apiKeyPrefix: String?

    enum CodingKeys: String, CodingKey {
        case errorBody = "error_body"
        case upstreamStatusCode = "upstream_status_code"
        case upstreamErrorMessage = "upstream_error_message"
        case upstreamErrorDetail = "upstream_error_detail"
        case authLatencyMs = "auth_latency_ms"
        case routingLatencyMs = "routing_latency_ms"
        case upstreamLatencyMs = "upstream_latency_ms"
        case responseLatencyMs = "response_latency_ms"
        case timeToFirstTokenMs = "time_to_first_token_ms"
        case isBusinessLimited = "is_business_limited"
        case apiKeyPrefix = "api_key_prefix"
    }
}

/// 错误请求筛选条件（对照源码 ops_handler.go ListRequestErrors：
/// resolved/phase/platform/model/account_id/q/user_query + start_time/end_time RFC3339，窗口上限 30 天，默认 1h）
struct RequestErrorFilter: Equatable {
    enum ResolvedFilter: String, CaseIterable, Identifiable {
        case all = "", unresolved = "false", resolved = "true"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .unresolved: return "未解决"
            case .resolved: return "已解决"
            }
        }
    }

    /// 时间窗口（后端默认仅 1h，App 需显式放大）
    enum TimeWindow: String, CaseIterable, Identifiable {
        case hour = "1h", hours24 = "24h", days7 = "7d", days30 = "30d"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hour: return "1 小时"
            case .hours24: return "24 小时"
            case .days7: return "7 天"
            case .days30: return "30 天"
            }
        }
        /// 对应秒数
        var seconds: TimeInterval {
            switch self {
            case .hour: return 3600
            case .hours24: return 86400
            case .days7: return 86400 * 7
            case .days30: return 86400 * 30
            }
        }
    }

    var timeWindow: TimeWindow = .hours24
    var resolved: ResolvedFilter = .all
    var platform: String = ""
    var model: String = ""
    var accountId: String = ""
    var searchText: String = ""   // → q（消息/请求 ID 检索）

    var isActive: Bool {
        timeWindow != .hours24 || resolved != .all || !platform.isEmpty
            || !model.isEmpty || !accountId.isEmpty || !searchText.isEmpty
    }

    /// 汇总摘要（用于激活筛选条）
    var summary: String {
        var parts: [String] = ["近\(timeWindow.title)"]
        if resolved != .all { parts.append(resolved.title) }
        if !platform.isEmpty { parts.append(platform) }
        if !model.isEmpty { parts.append("模型 \(model)") }
        if !accountId.isEmpty { parts.append("账号 \(accountId)") }
        if !searchText.isEmpty { parts.append("「\(searchText.prefix(12))」") }
        return parts.joined(separator: " · ")
    }

    /// 转为查询参数（含 start_time RFC3339）
    func queryItems(now: Date = .now) -> [String: String] {
        var items: [String: String] = [:]
        let formatter = ISO8601DateFormatter()
        items["start_time"] = formatter.string(from: now.addingTimeInterval(-timeWindow.seconds))
        if resolved != .all { items["resolved"] = resolved.rawValue }
        if !platform.isEmpty { items["platform"] = platform }
        if !model.isEmpty { items["model"] = model }
        if !accountId.isEmpty { items["account_id"] = accountId }
        if !searchText.isEmpty { items["q"] = searchText }
        return items
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
