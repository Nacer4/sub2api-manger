import SwiftUI

/// 上游账号列表：分页 + 平台/状态筛选 + 多选批量操作
struct AccountListView: View {
    @State private var viewModel = AccountListViewModel()

    var body: some View {
        List {
            if viewModel.isSelecting {
                selectionSection
            }
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
                    if viewModel.isSelecting {
                        Button {
                            viewModel.toggleSelection(account)
                        } label: {
                            HStack {
                                Image(systemName: viewModel.isSelected(account)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(viewModel.isSelected(account) ? .tint : .secondary)
                                AccountRow(account: account)
                            }
                        }
                        .tint(.primary)
                    } else {
                        NavigationLink(value: account) {
                            AccountRow(account: account)
                        }
                    }
                }
                LoadMoreFooter(
                    isLoading: viewModel.isLoading,
                    action: { Task { await viewModel.loadMore() } }
                )
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("账号池")
        .searchable(text: $viewModel.searchText, prompt: "搜索账号名称")
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.debouncedSearch()
        }
        .navigationDestination(for: Account.self) { account in
            AccountDetailView(accountId: account.id)
        }
        .refreshable { await viewModel.reload() }
        .task { await viewModel.reloadIfNeeded() }
        .toolbar {
            if viewModel.isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { viewModel.exitSelection() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("已选 \(viewModel.selectedIds.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.enterSelection()
                    } label: {
                        Label("选择", systemImage: "checkmark.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showBatchSheet) {
            if let action = viewModel.pendingBatchAction {
                BatchConfirmSheet(
                    action: action,
                    count: viewModel.selectedIds.count,
                    previewNames: viewModel.selectedPreviewNames,
                    onConfirm: {
                        Task { await viewModel.runBatch(action) }
                    }
                )
            }
        }
        .alert("批量操作", isPresented: $viewModel.showBatchResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.batchResultMessage)
        }
        .overlay {
            if viewModel.isLoading, viewModel.accounts.isEmpty {
                LoadingView()
            }
        }
    }

    private var filterSection: some View {
        Section {
            Picker("平台", selection: $viewModel.platformFilter) {
                Text("全部").tag("")
                ForEach(viewModel.platforms, id: \.self) { platform in
                    Text(platform.capitalized).tag(platform)
                }
            }
            .onChange(of: viewModel.platformFilter) { _, _ in
                Task { await viewModel.reload() }
            }

            Picker("状态", selection: $viewModel.statusFilter) {
                Text("全部").tag("")
                Text("active").tag("active")
                Text("error").tag("error")
                Text("rate_limited").tag("rate_limited")
                Text("expired").tag("expired")
            }
            .onChange(of: viewModel.statusFilter) { _, _ in
                Task { await viewModel.reload() }
            }
        }
    }

    private var selectionSection: some View {
        Section {
            ForEach(AccountBatchAction.allCases) { action in
                Button {
                    viewModel.pendingBatchAction = action
                    viewModel.showBatchSheet = true
                } label: {
                    Label(action.title, systemImage: action.symbol)
                        .foregroundStyle(action.isDestructive ? .red : .primary)
                }
                .disabled(viewModel.selectedIds.isEmpty)
            }

            Button {
                viewModel.selectAll()
            } label: {
                Label("全选当前页", systemImage: "checkmark.circle.2")
            }
            .disabled(viewModel.accounts.isEmpty)

            Button(role: .destructive) {
                viewModel.selectedIds.removeAll()
            } label: {
                Label("清空选择", systemImage: "eraser")
            }
            .disabled(viewModel.selectedIds.isEmpty)
        } header: {
            Text("批量操作")
        } footer: {
            Text("勾选账号后执行。批量删除不可恢复。")
        }
    }
}

struct AccountRow: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: platformSymbol)
                    .foregroundStyle(.tint)
                Text(account.name ?? "账号 #\(account.id)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                StatusPill(account.status)
            }
            HStack {
                Text(account.platform ?? "-")
                    .textCase(.uppercase)
                if let authType = account.authType {
                    Text("· \(authType)")
                }
                if account.schedulable == false {
                    Text("· 不可调度")
                }
                Spacer()
                Text(Fmt.date(account.lastUsedAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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

/// 批量操作确认弹窗（删除类操作红色确认 + 选中账号预览）
struct BatchConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isRunning = false

    let action: AccountBatchAction
    let count: Int
    let previewNames: [String]
    let onConfirm: () async -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: action.symbol)
                            .font(.title2)
                            .foregroundStyle(action.isDestructive ? .red : .tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.headline)
                            Text("将对 \(count) 个账号执行该操作。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if action.isDestructive {
                        Label("该操作不可恢复。", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if !previewNames.isEmpty {
                    Section("选中账号（前 \(previewNames.count) 项）") {
                        ForEach(previewNames, id: \.self) { name in
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        if count > previewNames.count {
                            Text("…及其他 \(count - previewNames.count) 个")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        Task {
                            isRunning = true
                            await onConfirm()
                            isRunning = false
                            dismiss()
                        }
                    } label: {
                        if isRunning {
                            HStack {
                                ProgressView()
                                Text("执行中…")
                            }
                        } else {
                            Text("确认执行")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(action.isDestructive ? .red : .accentColor)
                    .listRowBackground(Color.clear)
                    .disabled(isRunning)
                }
            }
            .navigationTitle("确认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

@Observable
final class AccountListViewModel {
    var accounts: [Account] = []
    var isLoading = false
    var error: Error?

    var searchText = ""
    var platformFilter = ""
    var statusFilter = ""

    // 多选批量操作状态
    var isSelecting = false
    var selectedIds: Set<Int> = []
    var showBatchSheet = false
    var pendingBatchAction: AccountBatchAction?
    var showBatchResult = false
    var batchResultMessage = ""

    /// 常见上游平台（作为筛选项）
    let platforms = ["claude", "openai", "gemini", "antigravity", "grok", "kimi", "zhipu", "deepseek"]

    private var query = PageQuery()
    private var reachedEnd = false
    private var searchTask: Task<Void, Never>?
    private var loadedOnce = false

    private var client: APIClient? { AppStateHolder.shared.client }

    // MARK: - 选择

    func enterSelection() {
        isSelecting = true
        selectedIds.removeAll()
    }

    func exitSelection() {
        isSelecting = false
        selectedIds.removeAll()
        pendingBatchAction = nil
    }

    func isSelected(_ account: Account) -> Bool {
        selectedIds.contains(account.id)
    }

    func toggleSelection(_ account: Account) {
        if selectedIds.contains(account.id) {
            selectedIds.remove(account.id)
        } else {
            selectedIds.insert(account.id)
        }
    }

    func selectAll() {
        for account in accounts where !selectedIds.contains(account.id) {
            selectedIds.insert(account.id)
        }
    }

    /// 确认弹窗中的选中账号预览（当前页已加载的前 5 个名称）
    var selectedPreviewNames: [String] {
        accounts
            .filter { selectedIds.contains($0.id) }
            .prefix(5)
            .map { $0.name ?? "账号 #\($0.id)" }
    }

    // MARK: - 批量操作

    func runBatch(_ action: AccountBatchAction) async {
        guard let client, !selectedIds.isEmpty else { return }
        do {
            struct BatchBody: Encodable { let account_ids: [Int] }
            let _: EmptyData = try await client.request(
                "POST", "/admin/accounts/\(action.rawValue)",
                body: BatchBody(account_ids: Array(selectedIds))
            )
            batchResultMessage = "「\(action.title)」已提交（\(selectedIds.count) 个账号）。"
            showBatchResult = true
            if action.isDestructive {
                selectedIds.removeAll()
            }
            await reload()
        } catch {
            batchResultMessage = "执行失败：\(error.localizedDescription)"
            showBatchResult = true
        }
        pendingBatchAction = nil
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
        await loadPage()
    }

    func loadMore() async {
        guard !reachedEnd, !isLoading else { return }
        query.page += 1
        await loadPage()
    }

    private func loadPage() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }

        var extra: [String: String] = [:]
        if !platformFilter.isEmpty { extra["platform"] = platformFilter }
        if !statusFilter.isEmpty { extra["status"] = statusFilter }
        if !searchText.isEmpty { extra["search"] = searchText }
        query.extra = extra

        do {
            let page: Page<Account> = try await client.page("/admin/accounts", query: query)
            if query.page == 1 { accounts = page.items } else { accounts += page.items }
            reachedEnd = accounts.count >= page.total
            error = nil
        } catch {
            self.error = error
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
