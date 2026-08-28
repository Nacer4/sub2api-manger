import SwiftUI

// MARK: - 统计卡片

struct StatCard: View {
    let title: String
    let value: String
    var symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 状态徽标

struct StatusPill: View {
    let text: String
    var color: Color

    init(_ text: String?) {
        self.text = text ?? "-"
        switch self.text.lowercased() {
        case "active", "ok", "success", "normal": color = .green
        case "error", "failed", "expired", "banned", "disabled": color = .red
        case "rate_limited", "ratelimited", "cooldown", "pending", "paused": color = .orange
        default: color = .secondary
        }
    }

    var body: some View {
        Text(text.replacingOccurrences(of: "_", with: " "))
            .font(.caption2.weight(.medium))
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - 加载 / 错误 / 空态

struct LoadingView: View {
    var text: String = "加载中…"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let error: Error
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct EmptyStateView: View {
    var text: String = "暂无数据"
    var body: some View {
        ContentUnavailableView(text, systemImage: "tray")
    }
}

// MARK: - 列表加载更多

struct LoadMoreFooter: View {
    let isLoading: Bool
    var action: () -> Void

    var body: some View {
        HStack {
            if isLoading {
                ProgressView().controlSize(.small)
                Text("加载中…").font(.footnote)
            } else {
                Button("加载更多", action: action)
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - 操作确认弹窗

struct ConfirmDialog: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let action: () async -> Void
}
