import SwiftUI

/// 账号详情：信息 → 当日统计 → 运维操作（测试/刷新/清错/清限流/重置配额/调度开关）
struct AccountDetailView: View {
    @State private var viewModel = AccountDetailViewModel()

    let accountId: Int

    var body: some View {
        Group {
            if let account = viewModel.account {
                content(account: account)
            } else if let error = viewModel.error {
                ErrorStateView(error: error) {
                    Task { await viewModel.load(accountId: accountId) }
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle(viewModel.account?.name ?? "账号")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(accountId: accountId) }
        .refreshable { await viewModel.load(accountId: accountId) }
        .alert("提示", isPresented: $viewModel.showResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.resultMessage)
        }
        .alert("确认操作", isPresented: $viewModel.showConfirm) {
            Button("取消", role: .cancel) {}
            Button("执行", role: .destructive) {
                Task { await viewModel.runPendingAction() }
            }
        } message: {
            if let action = viewModel.pendingAction {
                Text("将在服务器上执行「\(action.title)」。")
            }
        }
    }

    @ViewBuilder
    private func content(account: Account) -> some View {
        List {
            infoSection(account: account)
            statsSection
            if let message = account.errorMessage, !message.isEmpty {
                errorSection(message: message)
            }
            actionsSection(account: account)
        }
    }

    private func infoSection(account: Account) -> some View {
        Section("账号信息") {
            LabeledRow("ID", "\(account.id)")
            LabeledRow("名称", account.name)
            LabeledRow("平台", account.platform)
            LabeledRow("认证类型", account.authType)
            if let tier = account.tier, !tier.isEmpty {
                LabeledRow("等级", tier)
            }
            LabeledRow("状态", pill: account.status)
            LabeledRow("可调度", account.schedulable == nil ? "-" : (account.schedulable! ? "是" : "否"))
            LabeledRow("优先级", account.priority.map(String.init))
            LabeledRow("权重", account.weight.map(String.init))
            LabeledRow("分组 ID", account.groupId.map(String.init))
            LabeledRow("最近使用", Fmt.date(account.lastUsedAt))
            LabeledRow("创建时间", Fmt.date(account.createdAt))
        }
    }

    private var statsSection: some View {
        Section("当日用量") {
            if viewModel.isLoadingStats {
                HStack { ProgressView().controlSize(.small) }
            } else if let stats = viewModel.todayStats {
                LabeledRow("请求数", Fmt.number(stats.requests))
                LabeledRow("输入 Token", Fmt.number(stats.inputTokens))
                LabeledRow("输出 Token", Fmt.number(stats.outputTokens))
                LabeledRow("费用", Fmt.usd(stats.cost))
            } else {
                Text("暂无统计").foregroundStyle(.secondary)
            }
        }
    }

    private func errorSection(message: String) -> some View {
        Section {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        } header: {
            Text("错误信息")
        }
    }

    private func actionsSection(account: Account) -> some View {
        Section("运维操作") {
            ForEach(AccountAction.allCases) { action in
                Button {
                    viewModel.confirm(action: action, accountId: account.id)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                }
            }

            Toggle("允许调度", isOn: Binding(
                get: { viewModel.account?.schedulable ?? true },
                set: { newValue in
                    Task { await viewModel.setSchedulable(newValue) }
                }
            ))
        }
    }
}

@MainActor
@Observable
final class AccountDetailViewModel {
    var account: Account?
    var todayStats: AccountTodayStats?
    var isLoadingStats = false
    var error: Error?

    var pendingAction: AccountAction?
    var showConfirm = false
    var showResult = false
    var resultMessage = ""

    private var pendingAccountId: Int = 0
    private var client: APIClient? { AppStateHolder.shared.client }

    func load(accountId: Int) async {
        guard let client else { return }
        error = nil
        do {
            account = try await client.request("GET", "/admin/accounts/\(accountId)")
            await loadStats(accountId: accountId)
        } catch {
            self.error = error
        }
    }

    private func loadStats(accountId: Int) async {
        guard let client else { return }
        isLoadingStats = true
        defer { isLoadingStats = false }
        todayStats = try? await client.request("GET", "/admin/accounts/\(accountId)/today-stats")
    }

    func confirm(action: AccountAction, accountId: Int) {
        pendingAction = action
        pendingAccountId = accountId
        showConfirm = true
    }

    func runPendingAction() async {
        guard let client, let action = pendingAction else { return }
        do {
            let _: EmptyData = try await client.request(
                "POST", "/admin/accounts/\(pendingAccountId)/\(action.rawValue)"
            )
            resultMessage = "「\(action.title)」已执行。"
            showResult = true
            // 重新拉取详情反映状态变化
            await load(accountId: pendingAccountId)
        } catch {
            resultMessage = "执行失败：\(error.localizedDescription)"
            showResult = true
        }
        pendingAction = nil
    }

    func setSchedulable(_ value: Bool) async {
        guard let client, let account else { return }
        // 乐观更新：先切 UI，失败再回滚（避免 Toggle 回弹闪烁）
        let original = account.schedulable
        account?.schedulable = value
        do {
            struct Body: Encodable { let schedulable: Bool }
            let _: EmptyData = try await client.request(
                "POST", "/admin/accounts/\(account.id)/schedulable", body: Body(schedulable: value)
            )
        } catch {
            self.account?.schedulable = original
            resultMessage = "设置失败：\(error.localizedDescription)"
            showResult = true
        }
    }
}
