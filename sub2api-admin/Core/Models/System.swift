import Foundation

/// 系统版本信息（/admin/system/version）
struct SystemVersion: Decodable {
    let version: String?
    let commit: String?
    let buildDate: String?

    enum CodingKeys: String, CodingKey {
        case version, commit
        case buildDate = "build_date"
    }
}
