import SwiftUI

/// 日志中心：使用记录 + 错误请求 两个分段
struct UsageListView: View {
    @State private var segment = Segment.usage

    enum Segment: String, CaseIterable, Identifiable {
        case usage, errors
        var id: String { rawValue }
        var title: String { self == .usage ? "使用记录" : "错误请求" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("日志类型", selection: $segment) {
                    ForEach(Segment.allCases) { seg in
                        Text(seg.title).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch segment {
                case .usage: UsageLogsView()
                case .errors: RequestErrorsView()
                }
            }
            .navigationTitle("日志")
        }
    }
}

// MARK: - 使用记录

struct UsageLogsView: View {
    @State private var viewModel = UsageLogsViewModel()

    var body: some View {
        List {
            if let error = viewModel.error, viewModel.logs.isEmpty {
                ErrorStateView(error: error) {
                    Task { await viewModel.reload() }
                }
                .listRowSeparator(.hidden)
            } else if viewModel.logs.isEmpty, !viewModel.isLoading {
                EmptyStateView(text: "暂无使用记录")
            } else {
                ForEach(viewModel.logs) { log in
                    UsageLogRow(log: log)
                }
                LoadMoreFooter(
                    isLoading: viewModel.isLoading,
                    action: { Task { await viewModel.loadMore() } }
                )
                .listRowSeparator(.hidden)
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "按模型筛选（如 claude）")
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.debouncedFilter()
        }
        .refreshable { await viewModel.reload() }
        .task { await viewModel.reloadIfNeeded() }
        .overlay {
            if viewModel.isLoading, viewModel.logs.isEmpty { LoadingView() }
        }
    }
}

struct UsageLogRow: View {
    let log: UsageLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.model ?? "-")
                    .font(.subheadline.monospaced().weight(.medium))
                    .lineLimit(1)
                Spacer()
                if let status = log.status {
                    StatusPill(status)
                }
            }
            HStack {
                if let userId = log.userId {
                    Text("用户 \(userId)")
                }
                if let accountId = log.accountId {
                    Text("· 账号 \(accountId)")
                }
                Spacer()
                Text(Fmt.number(log.totalTokens) + " tok")
                Text(Fmt.usd(log.cost))
                    .foregroundStyle(.orange)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                if let latency = log.latencyMs {
                    Text(String(format: "%.0f ms", latency))
                }
                Spacer()
                Text(Fmt.date(log.createdAt))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 错误请求

struct RequestErrorsView: View {
    @State private var viewModel = RequestErrorsViewModel()

    var body: some View {
        List {
            if let error = viewModel.error, viewModel.logs.isEmpty {
                ErrorStateView(error: error) {
                    Task { await viewModel.reload() }
                }
                .listRowSeparator(.hidden)
            } else if viewModel.logs.isEmpty, !viewModel.isLoading {
                EmptyStateView(text: "暂无错误请求")
            } else {
                ForEach(viewModel.logs) { log in
                    RequestErrorRow(log: log)
                }
                LoadMoreFooter(
                    isLoading: viewModel.isLoading,
                    action: { Task { await viewModel.loadMore() } }
                )
                .listRowSeparator(.hidden)
            }
        }
        .refreshable { await viewModel.reload() }
        .task { await viewModel.reloadIfNeeded() }
        .overlay {
            if viewModel.isLoading, viewModel.logs.isEmpty { LoadingView() }
        }
    }
}

struct RequestErrorRow: View {
    let log: RequestErrorLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.model ?? "-")
                    .font(.subheadline.monospaced().weight(.medium))
                Spacer()
                if log.resolved == true {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            if let code = log.errorCode {
                Text(code)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
            if let message = log.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack {
                if let userId = log.userId { Text("用户 \(userId)") }
                if let accountId = log.accountId { Text("· 账号 \(accountId)") }
                Spacer()
                Text(Fmt.date(log.createdAt))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ViewModels

@Observable
final class UsageLogsViewModel {
    var logs: [UsageLog] = []
    var isLoading = false
    var error: Error?
    var searchText = ""

    private var query = PageQuery()
    private var reachedEnd = false
    private var filterTask: Task<Void, Never>?
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
        logs = []
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

        if !searchText.isEmpty { query.extra["model"] = searchText } else { query.extra.removeValue(forKey: "model") }

        do {
            let page: Page<UsageLog> = try await client.page("/admin/usage", query: query)
            if query.page == 1 { logs = page.items } else { logs += page.items }
            reachedEnd = logs.count >= page.total
            error = nil
        } catch {
            self.error = error
        }
    }

    func debouncedFilter() {
        filterTask?.cancel()
        filterTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }
}

@Observable
final class RequestErrorsViewModel {
    var logs: [RequestErrorLog] = []
    var isLoading = false
    var error: Error?

    private var query = PageQuery()
    private var reachedEnd = false
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
        logs = []
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
        do {
            let page: Page<RequestErrorLog> = try await client.page(
                "/admin/ops/request-errors", query: query
            )
            if query.page == 1 { logs = page.items } else { logs += page.items }
            reachedEnd = logs.count >= page.total
            error = nil
        } catch {
            self.error = error
        }
    }
}
