import SwiftUI

/// 上游账号列表：分页 + 平台/状态筛选
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
                        NavigationLink(value: account) {
                            AccountRow(account: account)
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
            .overlay {
                if viewModel.isLoading, viewModel.accounts.isEmpty {
                    LoadingView()
                }
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

@Observable
final class AccountListViewModel {
    var accounts: [Account] = []
    var isLoading = false
    var error: Error?

    var searchText = ""
    var platformFilter = ""
    var statusFilter = ""

    /// 常见上游平台（作为筛选项）
    let platforms = ["claude", "openai", "gemini", "antigravity", "grok", "kimi", "zhipu", "deepseek"]

    private var query = PageQuery()
    private var reachedEnd = false
    private var searchTask: Task<Void, Never>?
    private var loadedOnce = false

    private var client: APIClient? { AppStateHolder.shared.client }

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
