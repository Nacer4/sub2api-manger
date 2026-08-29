import SwiftUI

/// 账号管理（简化）：分组/认证筛选 + 简单信息展示 + 调度开关
struct AccountListView: View {
    @State private var viewModel = AccountListViewModel()

    var body: some View {
        NavigationStack {
            List {
            filterSection
            if let error = viewModel.error, viewModel.accounts.isEmpty {
                ErrorStateView(error: error) {
                    Task { await viewModel.reload() }
                }
                .listRowSeparator(.hidden)
            } else if viewModel.accounts.isEmpty, !viewModel.isLoading {
                EmptyStateView(text: "暂无账号")
            } else {
                ForEach(viewModel.accounts) { account in
                    AccountRow(
                        account: account,
                        groupName: viewModel.groupName(for: account)
                    ) { newValue in
                        Task { await viewModel.setSchedulable(account, value: newValue) }
                    }
                    .listRowSeparator(.hidden)
                }
                LoadMoreFooter(
                    isLoading: viewModel.isLoading,
                    action: { Task { await viewModel.loadMore() } }
                )
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("账号管理")
        .searchable(text: $viewModel.searchText, prompt: "搜索账号名称")
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.debouncedSearch()
        }
        .refreshable { await viewModel.reload() }
        .task { await viewModel.reloadIfNeeded() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    GroupListView()
                } label: {
                    Label("分组", systemImage: "square.stack.3d.up")
                }
            }
        }
        .alert("提示", isPresented: $viewModel.showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .overlay {
            if viewModel.isLoading, viewModel.accounts.isEmpty {
                LoadingView()
            }
        }
        }
    }

    private var filterSection: some View {
        Section {
            Picker("分组", selection: $viewModel.groupFilter) {
                Text("全部分组").tag(Int?.none)
                ForEach(viewModel.groups) { group in
                    Text(group.name ?? "#\(group.id)").tag(Int?.some(group.id))
                }
            }
            .onChange(of: viewModel.groupFilter) { _, _ in
                Task { await viewModel.reload() }
            }

            Picker("认证方式", selection: $viewModel.authFilter) {
                Text("全部认证").tag("")
                ForEach(viewModel.authTypes, id: \.self) { auth in
                    Text(auth).tag(auth)
                }
            }
            .onChange(of: viewModel.authFilter) { _, _ in
                Task { await viewModel.reload() }
            }
        }
    }
}

struct AccountRow: View {
    let account: Account
    let groupName: String?
    let onToggleSchedulable: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: platformSymbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(account.name ?? "账号 #\(account.id)")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    StatusPill(account.status)
                }
                HStack(spacing: 4) {
                    Text(account.platform?.uppercased() ?? "-")
                    if let authType = account.authType {
                        Text("· \(authType)")
                    }
                    if let tier = account.tier, !tier.isEmpty {
                        Text("· \(tier)")
                            .foregroundStyle(.tint)
                    }
                    if let groupName {
                        Text("· \(groupName)")
                            .foregroundStyle(.tint)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { account.schedulable ?? true },
                set: onToggleSchedulable
            ))
            .labelsHidden()
            .tint(.accentColor)
        }
        .padding(.vertical, 2)
    }

    private var platformSymbol: String {
        switch account.platform?.lowercased() {
        case "claude", "anthropic": return "bubble.left.and.text.bubble.right"
        case "openai", "codex": return "circle.hexagongrid"
        case "gemini": return "sparkles"
        case "grok": return "bolt"
        case "antigravity": return "arrow.up.circle"
        default: return "externaldrive.connected.to.line.below"
        }
    }
}

@MainActor
@Observable
final class AccountListViewModel {
    var accounts: [Account] = []
    var isLoading = false
    var error: Error?

    var searchText = ""
    var groupFilter: Int?
    var authFilter = ""

    var groups: [AccountGroup] = []

    var showError = false
    var errorMessage = ""

    /// 认证方式
    let authTypes = ["oauth", "api_key"]

    private var query = PageQuery()
    private var reachedEnd = false
    private var searchTask: Task<Void, Never>?
    private var loadedOnce = false

    private var client: APIClient? { AppStateHolder.shared.client }

    // MARK: - 分组名称

    func groupName(for account: Account) -> String? {
        guard let groupId = account.groupId else { return nil }
        return groups.first { $0.id == groupId }?.name
    }

    // MARK: - 调度开关

    /// 乐观更新：先切 UI，失败再回滚并提示（POST /admin/accounts/:id/schedulable）
    func setSchedulable(_ account: Account, value: Bool) async {
        guard let client else { return }
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let original = accounts[index].schedulable
        accounts[index].schedulable = value
        do {
            struct Body: Encodable { let schedulable: Bool }
            let _: EmptyData = try await client.request(
                "POST", "/admin/accounts/\(account.id)/schedulable", body: Body(schedulable: value)
            )
        } catch {
            accounts[index].schedulable = original
            errorMessage = "设置失败：\(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - 列表加载

    func reloadIfNeeded() async {
        guard !loadedOnce else { return }
        loadedOnce = true
        await reload()
    }

    func reload() async {
        query = PageQuery()
        query.sortBy = "created_at"
        query.sortOrder = "desc"
        reachedEnd = false
        accounts = []
        await loadGroups()
        await loadPage()
    }

    func loadMore() async {
        guard !reachedEnd, !isLoading else { return }
        query.page += 1
        // 失败回退页码，避免下次加载跳过整页数据
        let ok = await loadPage()
        if !ok { query.page -= 1 }
    }

    @discardableResult
    private func loadPage() async -> Bool {
        guard let client else { return false }
        isLoading = true
        defer { isLoading = false }

        var extra: [String: String] = [:]
        if let groupFilter { extra["group_id"] = String(groupFilter) }
        if !authFilter.isEmpty { extra["auth_type"] = authFilter }
        if !searchText.isEmpty { extra["search"] = searchText }
        query.extra = extra

        do {
            let page: Page<Account> = try await client.page("/admin/accounts", query: query)
            if query.page == 1 { accounts = page.items } else { accounts += page.items }
            reachedEnd = accounts.count >= page.total
            error = nil
            return true
        } catch {
            self.error = error
            return false
        }
    }

    private func loadGroups() async {
        guard let client else { return }
        do {
            let page: Page<AccountGroup> = try await client.page(
                "/admin/groups", query: PageQuery(pageSize: 200)
            )
            groups = page.items
        } catch {
            // 分组加载失败不阻塞账号列表，仅无法显示分组名
        }
    }

    func debouncedSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }
}
