import SwiftUI

/// 账号管理：分组/认证筛选 + 信息卡展示 + 调度开关 + 编辑/删除/更多
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
                        groupName: viewModel.groupName(for: account),
                        onToggleSchedulable: { newValue in
                            Task { await viewModel.setSchedulable(account, value: newValue) }
                        },
                        onEdit: {
                            viewModel.notice("编辑账号「\(account.name ?? "#\(account.id)")」")
                        },
                        onDelete: {
                            viewModel.requestDelete(account)
                        },
                        onMore: {
                            viewModel.notice("账号「\(account.name ?? "#\(account.id)")」更多操作")
                        }
                    )
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
        .alert("提示", isPresented: $viewModel.showNotice) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.noticeMessage)
        }
        .alert("删除账号", isPresented: $viewModel.showDeleteConfirm) {
            Button("取消", role: .cancel) {
                viewModel.pendingDelete = nil
            }
            Button("删除", role: .destructive) {
                Task { await viewModel.deletePending() }
            }
        } message: {
            if let account = viewModel.pendingDelete {
                Text("将删除账号「\(account.name ?? "#\(account.id)")」，该操作不可恢复。")
            }
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

// MARK: - 账号信息卡

struct AccountRow: View {
    let account: Account
    let groupName: String?
    let onToggleSchedulable: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let tags = account.tags, !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.fill.tertiary, in: Capsule())
                    }
                }
            }

            VStack(spacing: 0) {
                LabeledRow("容量", capacityText)
                LabeledRow("状态", pill: account.status)
                schedRow
                LabeledRow("分组", groupText)
                LabeledRow("用量窗口", windowText)
                LabeledRow("", amountText)
                LabeledRow("上游声明倍率", rateText)
                LabeledRow("最近使用", Fmt.date(account.lastUsedAt))
                LabeledRow("创建时间", Fmt.date(account.createdAt))
                LabeledRow("过期时间", Fmt.date(account.expiredAt))
            }

            actionsRow
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(account.name ?? "账号 #\(account.id)")
                .font(.subheadline.weight(.semibold))
            Text("#\(account.id) · \(account.platform ?? "-") \(authLabel)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    private var authLabel: String {
        account.authType == "api_key" ? "Key" : (account.authType ?? "-")
    }

    private var capacityText: String? {
        if let used = account.capacityUsed, let limit = account.capacityLimit {
            return "\(used) / \(limit)"
        }
        return account.capacityLimit.map { "- / \($0)" }
    }

    private var groupText: String? {
        switch (groupName, account.groupNote) {
        case let (name?, note?): return "\(name) · \(note)"
        case let (name?, nil): return name
        case let (nil, note?): return note
        default: return nil
        }
    }

    private var windowText: String? {
        switch (account.windowRequests, account.windowTokens) {
        case let (req?, tok?): return "\(req) req · \(tok)"
        case let (req?, nil): return "\(req) req"
        case let (nil, tok?): return tok
        default: return nil
        }
    }

    private var amountText: String? {
        switch (account.windowAmount, account.windowUserAmount) {
        case let (a?, u?): return "A \(Fmt.usd(a)) · U \(Fmt.usd(u))"
        case let (a?, nil): return "A \(Fmt.usd(a))"
        case let (nil, u?): return "U \(Fmt.usd(u))"
        default: return nil
        }
    }

    private var rateText: String? {
        account.rateMultiplier.map { "\($0)x" }
    }

    private var schedRow: some View {
        HStack {
            Text("调度")
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { account.schedulable ?? true },
                set: onToggleSchedulable
            ))
            .labelsHidden()
        }
        .font(.subheadline)
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button {
                onEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Menu {
                Button("测试可用性", systemImage: "checkmark.seal") { onMore() }
                Button("刷新凭证", systemImage: "arrow.clockwise") { onMore() }
                Button("刷新账号等级", systemImage: "sparkles") { onMore() }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - ViewModel

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

    var showNotice = false
    var noticeMessage = ""

    var pendingDelete: Account?
    var showDeleteConfirm = false

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

    // MARK: - 提示

    func notice(_ message: String) {
        noticeMessage = message
        showNotice = true
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
            noticeMessage = "设置失败：\(error.localizedDescription)"
            showNotice = true
        }
    }

    // MARK: - 删除

    /// 发起删除确认
    func requestDelete(_ account: Account) {
        pendingDelete = account
        showDeleteConfirm = true
    }

    /// 删除待确认账号（DELETE /admin/accounts/:id）
    func deletePending() async {
        guard let client, let account = pendingDelete else { return }
        defer { pendingDelete = nil }
        do {
            let _: EmptyData = try await client.request(
                "DELETE", "/admin/accounts/\(account.id)"
            )
            accounts.removeAll { $0.id == account.id }
            noticeMessage = "账号「\(account.name ?? "#\(account.id)")」已删除。"
        } catch {
            noticeMessage = "删除失败：\(error.localizedDescription)"
        }
        showNotice = true
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
