import Foundation
import SwiftUI

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

    /// 延迟分级颜色（与设计稿 latCls 一致）：<1s 绿 / 1-3s 黄 / 3-10s 橙 / >10s 红
    static func latencyColor(_ ms: Double?) -> Color {
        guard let ms else { return .secondary }
        switch ms {
        case ..<1000: return .green
        case ..<3000: return .yellow
        case ..<10000: return .orange
        default: return .red
        }
    }
}
