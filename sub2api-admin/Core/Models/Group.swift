import Foundation

/// 分组（账号管理 / 模型路由）
/// 注意：不命名为 Group，避免与 SwiftUI.Group 冲突
struct AccountGroup: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let description: String?
    let models: [String]?
    let priority: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, models, priority
        case createdAt = "created_at"
    }
}
