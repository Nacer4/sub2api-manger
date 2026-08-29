import Foundation

/// 分组（账号管理 / 模型路由）
/// 注意：不命名为 Group，避免与 SwiftUI.Group 冲突
struct AccountGroup: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let platform: String?             // OpenAI / Claude / ...
    let billingType: String?          // 标准（余额）/ 标准（订阅）/ 按量计费
    let rateMultiplier: Double?       // 费率倍数 0.1x
    let groupType: String?            // 公开 / 私有
    let availableAccounts: Int?       // 可用账号数
    let totalAccounts: Int?           // 总账号数
    let capacityUsed: Int?
    let capacityLimit: Int?
    let todayCost: Double?
    let yesterdayCost: Double?
    let totalCost: Double?
    let status: String?               // 正常 / 容量低 / ...

    enum CodingKeys: String, CodingKey {
        case id, name, platform, status
        case billingType = "billing_type"
        case rateMultiplier = "rate_multiplier"
        case groupType = "group_type"
        case availableAccounts = "available_accounts"
        case totalAccounts = "total_accounts"
        case capacityUsed = "capacity_used"
        case capacityLimit = "capacity_limit"
        case todayCost = "today_cost"
        case yesterdayCost = "yesterday_cost"
        case totalCost = "total_cost"
    }
}
