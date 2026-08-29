import SwiftUI

/// 用户详情：基本信息 → 余额操作 → API Key → 余额变动
struct UserDetailView: View {
    @State private var viewModel = UserDetailViewModel()

    let userId: Int

    var body: some View {
        Group {
            if let user = viewModel.user {
                content(user: user)
            } else if let error = viewModel.error {
                ErrorStateView(error: error) {
                    Task { await viewModel.load(userId: userId) }
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle(viewModel.user?.displayName ?? "用户")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(userId: userId) }
        .refreshable { await viewModel.load(userId: userId) }
        .sheet(isPresented: $viewModel.showBalanceSheet) {
            if let user = viewModel.user {
                BalanceAdjustSheet(user: user) { _ in
                    Task { await viewModel.load(userId: userId) }
                }
            }
        }
        .alert("操作失败", isPresented: $viewModel.showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("确认禁用 / 启用", isPresented: $viewModel.showToggleConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认", role: .destructive) {
                Task { await viewModel.toggleStatus() }
            }
        } message: {
            Text("将把该用户状态改为 \(viewModel.user?.status == "active" ? "disabled" : "active")。")
        }
    }

    @ViewBuilder
    private func content(user: User) -> some View {
        List {
            infoSection(user: user)
            balanceSection(user: user)
            actionsSection(user: user)
            if !viewModel.apiKeys.isEmpty {
                apiKeysSection
            }
            if !viewModel.balanceHistory.isEmpty {
                historySection
            }
        }
    }

    private func infoSection(user: User) -> some View {
        Section("基本信息") {
            LabeledRow("ID", "\(user.id)")
            LabeledRow("邮箱", user.email)
            LabeledRow("用户名", user.username)
            LabeledRow("角色", user.role)
            LabeledRow("状态", pill: user.status)
            LabeledRow("分组", user.groupName)
            LabeledRow("并发上限", user.concurrencyLimit.map(String.init))
            LabeledRow("RPM 上限", user.rpmLimit.map(String.init))
            LabeledRow("注册时间", Fmt.date(user.createdAt))
        }
    }

    private func balanceSection(user: User) -> some View {
        Section("余额") {
            HStack {
                Text(Fmt.usd(user.balance))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.orange)
                Spacer()
                Button("调整余额") {
                    viewModel.showBalanceSheet = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func actionsSection(user: User) -> some View {
        Section("操作") {
            Button(role: .destructive) {
                viewModel.showToggleConfirm = true
            } label: {
                Label(
                    user.status == "active" ? "禁用账号" : "启用账号",
                    systemImage: user.status == "active" ? "person.crop.circle.badge.xmark" : "person.crop.circle.badge.checkmark"
                )
            }
        }
    }

    private var apiKeysSection: some View {
        Section("API Keys") {
            ForEach(viewModel.apiKeySummaries, id: \.self) { key in
                VStack(alignment: .leading, spacing: 2) {
                    Text(key)
                        .font(.subheadline.monospaced())
                        .lineLimit(1)
                }
            }
        }
    }

    private var historySection: some View {
        Section("余额变动") {
            ForEach(viewModel.balanceHistory) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.reason ?? "-")
                            .font(.subheadline)
                        Text(Fmt.date(entry.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let amount = entry.amount {
                        Text((amount >= 0 ? "+" : "") + Fmt.usd(amount))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(amount >= 0 ? .green : .red)
                    }
                }
            }
        }
    }
}

/// Form 行：label + value（可选状态徽标）
struct LabeledRow: View {
    let label: String
    let value: String?
    var pill: String?

    init(_ label: String, _ value: String?) {
        self.label = label
        self.value = value
    }

    init(_ label: String, pill value: String?) {
        self.label = label
        self.value = nil
        self.pill = value
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            if let pill {
                StatusPill(pill)
            } else {
                Text(value ?? "-")
                    .foregroundStyle(pill == nil ? .primary : .secondary)
            }
        }
        .font(.subheadline)
    }
}

@MainActor
@Observable
final class UserDetailViewModel {
    var user: User?
    var apiKeys: [APIKeySummary] = []
    var balanceHistory: [BalanceHistoryEntry] = []
    var error: Error?
    var isLoading = false

    var showBalanceSheet = false
    var showToggleConfirm = false
    var showError = false
    var errorMessage = ""

    var apiKeySummaries: [String] {
        apiKeys.map(\.displayName)
    }

    private var client: APIClient? { AppStateHolder.shared.client }

    func load(userId: Int) async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil

        do {
            user = try await client.request("GET", "/admin/users/\(userId)")
            // 子资源失败不影响主详情
            let keys: Page<APIKeySummary>? = try? await client.page(
                "/admin/users/\(userId)/api-keys", query: PageQuery(pageSize: 50)
            )
            apiKeys = keys?.items ?? []
            let history: Page<BalanceHistoryEntry>? = try? await client.page(
                "/admin/users/\(userId)/balance-history", query: PageQuery(pageSize: 20)
            )
            balanceHistory = history?.items ?? []
        } catch {
            self.error = error
        }
    }

    func toggleStatus() async {
        guard let client, let current = user else { return }
        let newStatus = current.status == "active" ? "disabled" : "active"
        do {
            struct UpdateBody: Encodable { let status: String }
            let _: EmptyData = try await client.request(
                "PUT", "/admin/users/\(current.id)", body: UpdateBody(status: newStatus)
            )
            current.status = newStatus
            user = current
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

/// 用户 API Key（宽松字段）
struct APIKeySummary: Decodable, Hashable {
    let id: Int?
    let name: String?
    let keyPrefix: String?
    let status: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status
        case keyPrefix = "key_prefix"
        case createdAt = "created_at"
    }

    var displayName: String {
        (name ?? "Key") + (keyPrefix.map { "（\($0)…）" } ?? "")
    }
}
