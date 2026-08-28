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
            if viewModel.filter.isActive {
                activeFilterBar
            }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showFilterSheet = true
                } label: {
                    Label("筛选", systemImage: viewModel.filter.isActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "按模型筛选（如 claude）")
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.debouncedFilter()
        }
        .sheet(isPresented: $viewModel.showFilterSheet) {
            UsageFilterSheet(filter: viewModel.filter) { newFilter in
                viewModel.applyFilter(newFilter)
            }
        }
        .refreshable { await viewModel.reload() }
        .task { await viewModel.reloadIfNeeded() }
        .overlay {
            if viewModel.isLoading, viewModel.logs.isEmpty { LoadingView() }
        }
    }

    /// 已激活的筛选条件条（点 × 清除）
    private var activeFilterBar: some View {
        Section {
            HStack {
                Label(
                    viewModel.filter.summary,
                    systemImage: "line.3.horizontal.decrease"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.applyFilter(UsageFilter())
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.accentColor.opacity(0.08))
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
                if let stream = log.stream {
                    if stream {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
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

// MARK: - 使用记录筛选 Sheet

/// 多条件筛选：日期范围 / 用户 ID / 账号 ID / 请求 ID / 流式
/// （参数对照源码 usage_handler.go：user_id/account_id/request_id/stream/start_date/end_date）
struct UsageFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var filter: UsageFilter

    let onApply: (UsageFilter) -> Void

    init(filter: UsageFilter, onApply: @escaping (UsageFilter) -> Void) {
        _filter = State(initialValue: filter)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("按 ID 筛选") {
                    TextField("用户 ID", text: $filter.userId)
                        .keyboardType(.numberPad)
                    TextField("账号 ID", text: $filter.accountId)
                        .keyboardType(.numberPad)
                    TextField("请求 ID", text: $filter.requestId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("流式") {
                    Picker("请求类型", selection: $filter.stream) {
                        ForEach(UsageFilter.StreamFilter.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section {
                    DatePicker("开始日期", selection: Binding(
                        get: { filter.startDate ?? Date.now.addingTimeInterval(-86400 * 7) },
                        set: { filter.startDate = $0 }
                    ), displayedComponents: .date)
                    DatePicker("结束日期", selection: Binding(
                        get: { filter.endDate ?? Date.now },
                        set: { filter.endDate = $0 }
                    ), displayedComponents: .date)
                } header: {
                    Text("日期范围")
                } footer: {
                    Text("按服务器本地时区的自然日过滤。")
                }
            }
            .navigationTitle("筛选条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") {
                        filter = UsageFilter()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        onApply(filter)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension UsageFilter {
    /// 筛选摘要（用于激活筛选条展示）
    var summary: String {
        var parts: [String] = []
        if !userId.isEmpty { parts.append("用户 \(userId)") }
        if !accountId.isEmpty { parts.append("账号 \(accountId)") }
        if !requestId.isEmpty { parts.append("请求 \(requestId.prefix(8))…") }
        if stream != .all { parts.append(stream.title) }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        if let startDate { parts.append("从 \(formatter.string(from: startDate))") }
        if let endDate { parts.append("至 \(formatter.string(from: endDate))") }
        return parts.joined(separator: " · ")
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
                    NavigationLink(value: log) {
                        RequestErrorRow(log: log)
                    }
                }
                LoadMoreFooter(
                    isLoading: viewModel.isLoading,
                    action: { Task { await viewModel.loadMore() } }
                )
                .listRowSeparator(.hidden)
            }
        }
        .navigationDestination(for: RequestErrorLog.self) { log in
            RequestErrorDetailView(errorLog: log) {
                Task { await viewModel.reload() }
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
                if let platform = log.platform {
                    Text(platform.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Text(log.model ?? "-")
                    .font(.subheadline.monospaced().weight(.medium))
                    .lineLimit(1)
                Spacer()
                if let statusCode = log.statusCode {
                    Text("HTTP \(statusCode)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusCode >= 500 ? .red : .orange)
                }
                if log.resolved == true {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            if let message = log.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                if let accountName = log.accountName {
                    Text(accountName)
                } else if let accountId = log.accountId {
                    Text("账号 \(accountId)")
                }
                if let severity = log.severity {
                    Text("· \(severity)")
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

// MARK: - 错误请求详情

/// 错误请求详情：完整字段 + 上游错误关联钻取
/// GET /admin/ops/request-errors/:id + /admin/ops/request-errors/:id/upstream-errors
struct RequestErrorDetailView: View {
    @State private var viewModel = RequestErrorDetailViewModel()
    let errorLog: RequestErrorLog
    var onResolved: (() -> Void)?

    var body: some View {
        List {
            infoSection
            contextSection
            resolveSection
            if !viewModel.upstreamErrors.isEmpty {
                upstreamSection
            }
        }
        .navigationTitle("错误详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(errorLog: errorLog) }
        .alert("操作失败", isPresented: $viewModel.showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var infoSection: some View {
        Section("错误信息") {
            if let type = errorLog.type {
                LabeledRow("类型", type)
            }
            if let phase = errorLog.phase {
                LabeledRow("阶段", phase)
            }
            if let statusCode = errorLog.statusCode {
                LabeledRow("HTTP 状态", "\(statusCode)")
            }
            if let severity = errorLog.severity {
                LabeledRow("严重程度", severity)
            }
            if let errorOwner = errorLog.errorOwner {
                LabeledRow("错误归属", errorOwner)
            }
            if let errorSource = errorLog.errorSource {
                LabeledRow("错误来源", errorSource)
            }
            if let message = errorLog.message {
                VStack(alignment: .leading, spacing: 4) {
                    Text("错误消息").font(.caption).foregroundStyle(.secondary)
                    Text(message)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var contextSection: some View {
        Section("请求上下文") {
            if let requestId = errorLog.requestId {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Request ID").font(.caption).foregroundStyle(.secondary)
                    Text(requestId)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
            if let model = errorLog.model {
                LabeledRow("模型", model)
            }
            if let platform = errorLog.platform {
                LabeledRow("平台", platform)
            }
            if let userEmail = errorLog.userEmail {
                LabeledRow("用户", userEmail)
            } else if let userId = errorLog.userId {
                LabeledRow("用户 ID", "\(userId)")
            }
            if let accountName = errorLog.accountName {
                LabeledRow("账号", accountName)
            } else if let accountId = errorLog.accountId {
                LabeledRow("账号 ID", "\(accountId)")
            }
            if let groupName = errorLog.groupName {
                LabeledRow("分组", groupName)
            }
            if let clientIp = errorLog.clientIp {
                LabeledRow("客户端 IP", clientIp)
            }
            LabeledRow("发生时间", Fmt.date(errorLog.createdAt))
            if let resolvedAt = errorLog.resolvedAt {
                LabeledRow("解决时间", Fmt.date(resolvedAt))
            }
            if let resolvedBy = errorLog.resolvedByUserName {
                LabeledRow("处理人", resolvedBy)
            }
        }
    }

    private var resolveSection: some View {
        Section {
            if viewModel.resolved {
                Label("已解决", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task {
                        await viewModel.resolve(errorLog: errorLog)
                        if viewModel.resolved { onResolved?() }
                    }
                } label: {
                    if viewModel.isResolving {
                        HStack {
                            ProgressView()
                            Text("标记中…")
                        }
                    } else {
                        Label("标记为已解决", systemImage: "checkmark.seal")
                    }
                }
                .disabled(viewModel.isResolving)
            }
        } header: {
            Text("处理状态")
        }
    }

    private var upstreamSection: some View {
        Section("关联上游错误") {
            ForEach(viewModel.upstreamErrors) { upstream in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let accountName = upstream.accountName {
                            Text(accountName)
                                .font(.subheadline.weight(.medium))
                        } else if let accountId = upstream.accountId {
                            Text("账号 \(accountId)")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        if let statusCode = upstream.statusCode {
                            Text("HTTP \(statusCode)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.red)
                        }
                    }
                    if let message = upstream.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    HStack {
                        if let errorCode = upstream.errorCode {
                            Text(errorCode)
                        }
                        if let latency = upstream.latencyMs {
                            Spacer()
                            Text(String(format: "%.0f ms", latency))
                        }
                        Spacer()
                        Text(Fmt.date(upstream.createdAt))
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

@Observable
final class RequestErrorDetailViewModel {
    var upstreamErrors: [UpstreamErrorLog] = []
    var resolved = false
    var isResolving = false
    var showError = false
    var errorMessage = ""

    private var client: APIClient? { AppStateHolder.shared.client }

    func load(errorLog: RequestErrorLog) async {
        resolved = (errorLog.resolved == true)
        guard let client, let id = errorLog.id else { return }
        // 上游错误为可选增强：失败时静默隐藏
        let page: Page<UpstreamErrorLog>? = try? await client.page(
            "/admin/ops/request-errors/\(id)/upstream-errors", query: PageQuery(pageSize: 20)
        )
        upstreamErrors = page?.items ?? []
    }

    /// 标记解决：PUT /admin/ops/request-errors/:id/resolve {resolved: true}
    func resolve(errorLog: RequestErrorLog) async {
        guard let client, let id = errorLog.id, !resolved else { return }
        isResolving = true
        defer { isResolving = false }
        do {
            struct Body: Encodable { let resolved: Bool }
            let _: EmptyData = try await client.request(
                "PUT", "/admin/ops/request-errors/\(id)/resolve", body: Body(resolved: true)
            )
            resolved = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - ViewModels

@Observable
final class UsageLogsViewModel {
    var logs: [UsageLog] = []
    var isLoading = false
    var error: Error?
    var searchText = ""

    var filter = UsageFilter()
    var showFilterSheet = false

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

    func applyFilter(_ newFilter: UsageFilter) {
        filter = newFilter
        Task { await reload() }
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

        // 搜索框 → model；筛选 Sheet → 多条件
        var extra: [String: String] = [:]
        if !searchText.isEmpty { extra["model"] = searchText }
        if !filter.userId.isEmpty { extra["user_id"] = filter.userId }
        if !filter.accountId.isEmpty { extra["account_id"] = filter.accountId }
        if !filter.requestId.isEmpty { extra["request_id"] = filter.requestId }
        if filter.stream != .all { extra["stream"] = filter.stream.rawValue }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let start = filter.startDate { extra["start_date"] = formatter.string(from: start) }
        if let end = filter.endDate { extra["end_date"] = formatter.string(from: end) }
        query.extra = extra

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
