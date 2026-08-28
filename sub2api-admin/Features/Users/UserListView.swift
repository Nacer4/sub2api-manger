import SwiftUI

/// 用户列表：分页 + 搜索 + 状态/角色筛选
struct UserListView: View {
    @State private var viewModel = UserListViewModel()

    var body: some View {
        NavigationStack {
            List {
                filterSection
                if let error = viewModel.error, viewModel.users.isEmpty {
                    ErrorStateView(error: error) {
                        Task { await viewModel.reload() }
                    }
                    .listRowSeparator(.hidden)
                } else if viewModel.users.isEmpty, !viewModel.isLoading {
                    EmptyStateView(text: "暂无用户")
                } else {
                    ForEach(viewModel.users) { user in
                        NavigationLink(value: user) {
                            UserRow(user: user)
                        }
                    }
                    LoadMoreFooter(
                        isLoading: viewModel.isLoading,
                        action: { Task { await viewModel.loadMore() } }
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("用户")
            .searchable(text: $viewModel.searchText, prompt: "搜索邮箱 / 用户名")
            .onChange(of: viewModel.searchText) { _, newValue in
                viewModel.debouncedSearch()
            }
            .navigationDestination(for: User.self) { user in
                UserDetailView(userId: user.id)
            }
            .refreshable { await viewModel.reload() }
            .task { await viewModel.reloadIfNeeded() }
            .overlay {
                if viewModel.isLoading, viewModel.users.isEmpty {
                    LoadingView()
                }
            }
        }
    }

    private var filterSection: some View {
        Section {
            Picker("状态", selection: $viewModel.statusFilter) {
                Text("全部").tag("")
                Text("active").tag("active")
                Text("disabled").tag("disabled")
                Text("banned").tag("banned")
            }
            .onChange(of: viewModel.statusFilter) { _, _ in
                Task { await viewModel.reload() }
            }

            Picker("角色", selection: $viewModel.roleFilter) {
                Text("全部").tag("")
                Text("user").tag("user")
                Text("admin").tag("admin")
            }
            .onChange(of: viewModel.roleFilter) { _, _ in
                Task { await viewModel.reload() }
            }
        }
    }
}

struct UserRow: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(user.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                StatusPill(user.status)
                if user.role == "admin" {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            HStack {
                if let email = user.email, email != user.displayName {
                    Text(email)
                }
                Spacer()
                Text(Fmt.usd(user.balance))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

@Observable
final class UserListViewModel {
    var users: [User] = []
    var isLoading = false
    var error: Error?

    var searchText = ""
    var statusFilter = ""
    var roleFilter = ""

    private var query = PageQuery()
    private var reachedEnd = false
    private var searchTask: Task<Void, Never>?
    private var loadedOnce = false

    private var client: APIClient? { AppStateHolder.shared.client }

    var canLoadMore: Bool { !reachedEnd && !isLoading }

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
        users = []
        await loadPage()
    }

    func loadMore() async {
        guard canLoadMore else { return }
        query.page += 1
        await loadPage()
    }

    private func loadPage() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }

        var extra: [String: String] = [:]
        if !statusFilter.isEmpty { extra["status"] = statusFilter }
        if !roleFilter.isEmpty { extra["role"] = roleFilter }
        if !searchText.isEmpty { extra["search"] = searchText }
        query.extra = extra

        do {
            let page: Page<User> = try await client.page("/admin/users", query: query)
            if query.page == 1 { users = page.items } else { users += page.items }
            reachedEnd = users.count >= page.total
            error = nil
        } catch {
            // 加载更多失败不清空已有数据
            if users.isEmpty { self.error = error }
            else { self.error = error }
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
