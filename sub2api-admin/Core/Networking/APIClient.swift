import Foundation

/// sub2api 管理 API 客户端
/// - 双通道认证：JWT（Bearer）或 Admin API Key（x-api-key）
/// - 401 时自动尝试 refresh，失败后抛 unauthorized
final class APIClient {
    let server: ServerConfig
    private let session: URLSession
    private let decoder = JSONDecoder()

    /// 服务器 API 前缀
    static let apiPrefix = "/api/v1"

    init(server: ServerConfig) {
        self.server = server
        self.session = URLSession(configuration: .ephemeral)
    }

    // MARK: - 认证

    private var jwt: String? {
        get { TokenStore.shared.get(serverId: server.id.uuidString, field: "jwt") }
        set {
            if let newValue {
                TokenStore.shared.set(newValue, serverId: server.id.uuidString, field: "jwt")
            } else {
                TokenStore.shared.clear(serverId: server.id.uuidString)
            }
        }
    }

    private var refreshToken: String? {
        get { TokenStore.shared.get(serverId: server.id.uuidString, field: "refresh") }
        set {
            if let newValue {
                TokenStore.shared.set(newValue, serverId: server.id.uuidString, field: "refresh")
            }
        }
    }

    private func authHeader() -> [String: String] {
        switch server.authMode {
        case .adminKey:
            return ["x-api-key": server.adminKey]
        case .jwt:
            if let jwt { return ["Authorization": "Bearer \(jwt)"] }
            return [:]
        }
    }

    // MARK: - 公开请求方法

    /// 解析 data 字段的请求
    func request<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Encodable? = nil
    ) async throws -> T {
        let data = try await raw(method, path, query: query, body: body)
        let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        guard envelope.code == 0 else {
            throw APIError.http(status: envelope.code, message: envelope.message, reason: nil)
        }
        guard let payload = envelope.data else {
            // code == 0 但无 data：尝试按空对象解析
            if let empty = EmptyData() as? T { return empty }
            throw APIError.invalidResponse
        }
        return payload
    }

    /// 无返回体的请求（宽松解析：只校验信封 code，不解析 data）
    func requestEmpty(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Encodable? = nil
    ) async throws {
        let data = try await raw(method, path, query: query, body: body)
        if let envelope = try? decoder.decode(APIErrorResponse.self, from: data),
           let code = envelope.code, code != 0 {
            throw APIError.http(status: code, message: envelope.message ?? "请求失败", reason: envelope.reason)
        }
    }

    /// 分页列表请求：GET + PageQuery → Page<T>
    func page<T: Decodable>(_ path: String, query: PageQuery) async throws -> Page<T> {
        try await request("GET", path, query: query.queryItems)
    }

    // MARK: - 原始请求（含 401 → refresh → 重试一次）

    private func raw(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Encodable? = nil,
        isRetry: Bool = false
    ) async throws -> Data {
        guard var components = URLComponents(string: server.baseURL + Self.apiPrefix + path) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query.filter { $0.value != nil && !$0.value!.isEmpty }
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        for (k, v) in authHeader() { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        // 401：JWT 模式尝试刷新一次
        if http.statusCode == 401, server.authMode == .jwt, !isRetry {
            if try await refreshTokens() {
                return try await raw(method, path, query: query, body: body, isRetry: true)
            }
            throw APIError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode(APIErrorResponse.self, from: data))?.message
                ?? "请求失败"
            let reason = (try? decoder.decode(APIErrorResponse.self, from: data))?.reason
            throw APIError.http(status: http.statusCode, message: message, reason: reason)
        }
        return data
    }

    private func refreshTokens() async throws -> Bool {
        guard let refresh = refreshToken else { return false }
        guard let url = URL(string: server.baseURL + Self.apiPrefix + "/auth/refresh") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refresh])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return false
        }
        guard let envelope = try? decoder.decode(APIEnvelope<TokenPair>.self, from: data),
              let pair = envelope.data else { return false }
        jwt = pair.token
        if let rt = pair.refreshToken { refreshToken = rt }
        return true
    }

    // MARK: - 登录（静态：登录时还没有 client 绑定凭证）

    struct LoginPayload: Encodable {
        let email: String
        let password: String
        let totp_code: String?
    }

    struct TokenPair: Decodable {
        let token: String?
        let refresh_token: String?

        var refreshToken: String? { refresh_token }
    }

    @discardableResult
    static func login(server: ServerConfig, email: String, password: String, totp: String?) async throws -> ServerConfig {
        guard let url = URL(string: server.baseURL + apiPrefix + "/auth/login") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = LoginPayload(email: email, password: password, totp_code: totp?.isEmpty == true ? nil : totp)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw APIError.http(status: http.statusCode, message: body?.message ?? "登录失败", reason: body?.reason)
        }
        let envelope = try JSONDecoder().decode(APIEnvelope<TokenPair>.self, from: data)
        guard let pair = envelope.data, let token = pair.token else {
            throw APIError.invalidResponse
        }
        TokenStore.shared.set(token, serverId: server.id.uuidString, field: "jwt")
        if let rt = pair.refreshToken {
            TokenStore.shared.set(rt, serverId: server.id.uuidString, field: "refresh")
        }
        return server
    }
}

// MARK: - 辅助类型

/// 空数据占位（部分接口 code=0 且 data 为空/缺省）
struct EmptyData: Decodable {}

struct APIErrorResponse: Decodable {
    let code: Int?
    let message: String?
    let reason: String?
}

/// type-erasing 编码器
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encodeFunc = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
