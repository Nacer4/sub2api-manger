import Foundation
import Security

/// Keychain 封装：按服务器 ID 存储 JWT / Refresh Token
struct TokenStore {
    static let shared = TokenStore()
    private let service = "com.nacer4.sub2admin.tokens"

    private func key(_ serverId: String, field: String) -> String {
        "\(serverId).\(field)"
    }

    func set(_ value: String, serverId: String, field: String) {
        let account = key(serverId, field: field)
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    func get(serverId: String, field: String) -> String? {
        let account = key(serverId, field: field)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clear(serverId: String) {
        for field in ["jwt", "refresh"] {
            let account = key(serverId, field: field)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
