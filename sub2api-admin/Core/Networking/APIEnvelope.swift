import Foundation

// MARK: - 统一响应信封 { code, message, data }

struct APIEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
}

// MARK: - 分页结构 { items, total, page, page_size, pages }

struct Page<T: Decodable>: Decodable {
    let items: [T]
    let total: Int
    let page: Int
    let pageSize: Int
    let pages: Int

    enum CodingKeys: String, CodingKey {
        case items, total, page, pages
        case pageSize = "page_size"
    }
}

// MARK: - 分页请求参数

struct PageQuery {
    var page: Int = 1
    var pageSize: Int = 20
    var sortBy: String?
    var sortOrder: String? // "asc" / "desc"
    var extra: [String: String] = [:]

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "page_size", value: String(pageSize)),
        ]
        if let sortBy { items.append(.init(name: "sort_by", value: sortBy)) }
        if let sortOrder { items.append(.init(name: "sort_order", value: sortOrder)) }
        items.append(contentsOf: extra.map { .init(name: $0.key, value: $0.value) })
        return items
    }
}

// MARK: - 错误

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(status: Int, message: String, reason: String?)
    case decoding(Error)
    case network(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的服务器地址"
        case .invalidResponse: return "服务器返回了无法解析的响应"
        case let .http(status, message, reason):
            return reason.map { "\(message)（\($0)）[HTTP \(status)]" } ?? "\(message) [HTTP \(status)]"
        case .decoding: return "数据解析失败（接口字段可能已变更）"
        case let .network(err): return err.localizedDescription
        case .unauthorized: return "登录已过期，请重新登录"
        }
    }
}
