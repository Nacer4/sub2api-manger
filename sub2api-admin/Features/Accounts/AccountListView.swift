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

    /// 筛选：分组（group=分组名，契约同 BulkUpdateAccountFilters）+ 认证方式（type）
    private var filterSection: some View {
        Section {
            Picker("分组", selection: $viewModel.groupFilter) {
                Text("全部分组").tag("")
                ForEach(viewModel.groups) { group in
                    Text(group.name ?? "#\(group.id)")
                        .tag(group.name ?? "#\(group.id)")
                }
            }
            .onChange(of: viewModel.groupFilter) { _, _ in
                Task { await viewModel.reload() }
            }

            Picker("认证方式", selection: $viewModel.typeFilter) {
                Text("全部认证").tag("")
                ForEach(viewModel.typeOptions, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .onChange(of: viewModel.typeFilter) { _, _ in
                Task { await viewModel.reload() }
            }
        }
    }
}

// MARK: - 账号信息卡

struct AccountRow: View {
    let account: Account
    let onToggleSchedulable: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let notes = account.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                LabeledRow("容量", capacityText)
                LabeledRow("状态", pill: account.status)
                schedRow
                LabeledRow("分组", groupText)
                LabeledRow("用量窗口", windowText)
                LabeledRow("上游声明倍率", rateText)
                LabeledRow("最近使用", Fmt.date(account.lastUsedAt))
                LabeledRow("创建时间", Fmt.date(account.createdAt))
                LabeledRow("过期时间", expiresText)
            }

            actionsRow
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(account.name ?? "账号 #\(account.id)")
                .font(.subheadline.weight(.semibold))
            Text("#\(account.id) · \(account.platform ?? "-") \(typeLabel)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    /// oauth → OAuth，apikey → Key，其余原样展示
    private var typeLabel: String {
        switch account.type {
        case "oauth": return "OAuth"
        case "apikey": return "Key"
        default: return account.type ?? "-"
        }
    }

    private var capacityText: String? {
        if let current = account.currentConcurrency, let max = account.concurrency {
            return "\(current) / \(max)"
        }
        return account.concurrency.map { "- / \($0)" }
    }

    private var groupText: String? {
        guard let names = account.groups?.compactMap(\.name), !names.isEmpty else { return nil }
        return names.joined(separator: " · ")
    }

    /// 当前 5h 窗口费用 + 配额（A 账号侧 / U 配额）
    private var windowText: String? {
        var parts: [String] = []
        if let cost = account.currentWindowCost {
            parts.append("A \(Fmt.usd(cost))")
        }
        if let used = account.quotaUsed {
            let limit = account.quotaLimit.map { "/\(Fmt.usd($0))" } ?? ""
            parts.append("U \(Fmt.usd(used))\(limit)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var rateText: String? {
        account.rateMultiplier.map { "\($0)x" }
    }

    private var expiresText: String? {
        guard let ts = account.expiresAt, ts > 0 else { return "-" }
        return Date(timeIntervalSince1970: TimeInterval(ts))
            .formatted(.verbatim(year: .defaultDigits, month: .twoDigits, day: .twoDigits,
                                 hour: .twoDigits, minute: .twoDigits, second: .twoDigits,
                                 timeZoneName: .localizedGMT))
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
    var groupFilter = ""
    var typeFilter = ""

    /// 分组选项（GET /admin/groups，取名称用于筛选）
    var groups: [AccountGroup] = []

    var showNotice = false
    var noticeMessage = ""

    var pendingDelete: Account?
    var showDeleteConfirm = false

    /// 认证方式（契约值：type，oauth / apikey）
    let typeOptions = ["oauth", "apikey"]

    private var query = PageQuery()
    private var reachedEnd = false
    private var searchTask: Task<Void, Never>?
    private var loadedOnce = false

    private var client: APIClient? { AppStateHolder.shared.client }

    // MARK: - 提示

    func notice(_ message: String) {
        noticeMessage = message
        showNotice = true
    }

    // MARK: - 调度开关

    /// 乐观更新：先切 UI，失败再回滚并提示
    /// 契约：PUT /admin/accounts/:id，body {schedulable}（UpdateAccountRequest.Schedulable *bool）
    func setSchedulable(_ account: Account, value: Bool) async {
        guard let client else { return }
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let original = accounts[index].schedulable
        accounts[index].schedulable = value
        do {
            struct Body: Encodable { let schedulable: Bool }
            let _: EmptyData = try await client.request(
                "PUT", "/admin/accounts/\(account.id)", body: Body(schedulable: value)
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

    /// 筛选参数对照账号列表过滤契约：search / type / status / group / platform
    @discardableResult
    private func loadPage() async -> Bool {
        guard let client else { return false }
        isLoading = true
        defer { isLoading = false }

        var extra: [String: String] = [:]
        if !groupFilter.isEmpty { extra["group"] = groupFilter }
        if !typeFilter.isEmpty { extra["type"] = typeFilter }
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
            // 分组加载失败不阻塞账号列表，仅筛选器少选项
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
