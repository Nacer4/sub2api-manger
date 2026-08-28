import Foundation

enum Fmt {
    /// 大数字紧凑显示（1.2万 / 3.4M）
    static func number(_ value: Int?) -> String {
        guard let value else { return "-" }
        return value.formatted(.number.notation(.compactName))
    }

    /// 金额（USD）
    static func usd(_ value: Double?) -> String {
        guard let value else { return "-" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(0...4)))
    }

    /// ISO 字符串 → 本地化时间（解析失败原样返回）
    static func date(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "-" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            return date.formatted(.dateTime.month().day().hour().minute())
        }
        return iso
    }
}
