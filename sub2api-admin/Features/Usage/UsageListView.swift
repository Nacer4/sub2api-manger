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
            .navigationDestination(for: UsageLog.self) { log in
                UsageLogDetailView(log: log)
            }
            .navigationTitle("日志")
        }
    }
}

// MARK: - 使用记录

struct UsageLogsView: View {
    @State private var viewModel = UsageLogsViewModel()

    /// 从错误详情跳转时注入的初始筛选（按 request_id 关联）
    var initialFilter: UsageFilter? = nil

    var body: some View {
        List {
            timeWindowSection
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
                    NavigationLink(value: log) {
                        UsageLogRow(log: log)
                    }
                }
                LoadMoreFooter(
                    isLoading: viewModel.isLoading,
                    action: { Task { await viewModel.loadMore() } }
                )
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("使用记录")
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
        .onChange(of: viewModel.filter.timeWindow) { _, _ in
            Task { await viewModel.reload() }
        }
        .sheet(isPresented: $viewModel.showFilterSheet) {
            UsageFilterSheet(filter: viewModel.filter) { newFilter in
                viewModel.applyFilter(newFilter)
            }
        }
        .refreshable { await viewModel.reload() }
        .task {
            await viewModel.reloadIfNeeded(initialFilter: initialFilter)
        }
        .overlay {
            if viewModel.isLoading, viewModel.logs.isEmpty { LoadingView() }
        }
    }

    /// 快捷时间范围（与设计稿一致：全部 / 今天 / 近 7 天 / 近 30 天）
    private var timeWindowSection: some View {
        Section {
            Picker("时间范围", selection: $viewModel.filter.timeWindow) {
                ForEach(UsageFilter.TimeWindow.allCases) { window in
                    Text(window.title).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
                        .foregroundStyle(Fmt.latencyColor(log.latencyMs))
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

// MARK: - 使用记录详情

/// 使用记录详情：Token 明细 + 费用 + 关联 ID 钻取（列表数据即完整字段，无需额外请求）
struct UsageLogDetailView: View {
    let log: UsageLog

    var body: some View {
        List {
            summarySection
            tokenSection
            costSection
            contextSection
        }
        .navigationTitle("使用记录详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summarySection: some View {
        Section {
            HStack {
                Text(log.model ?? "-")
                    .font(.headline.monospaced())
                Spacer()
                if let stream = log.stream, stream {
                    Label("流式", systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            if let status = log.status {
                LabeledRow("状态", status)
            }
        } header: {
            Text("请求")
        } footer: {
            if let requestId = log.requestId {
                Text("Request ID：\(requestId)")
                    .textSelection(.enabled)
            }
        }
    }

    private var tokenSection: some View {
        Section("Token 明细") {
            LabeledRow("输入", Fmt.number(log.inputTokens))
            LabeledRow("输出", Fmt.number(log.outputTokens))
            if let cacheCreation = log.cacheCreationTokens, cacheCreation > 0 {
                LabeledRow("缓存写入", Fmt.number(cacheCreation))
            }
            if let cacheRead = log.cacheReadTokens, cacheRead > 0 {
                LabeledRow("缓存读取", Fmt.number(cacheRead))
            }
            LabeledRow("合计", Fmt.number(log.totalTokens))
                .font(.body.weight(.semibold))
        }
    }

    private var costSection: some View {
        Section("计费") {
            LabeledRow("费用", Fmt.usd(log.cost))
                .foregroundStyle(.orange)
            if let latency = log.latencyMs {
                LabeledRow("总延迟", String(format: "%.0f ms", latency))
            }
        }
    }

    private var contextSection: some View {
        Section("关联") {
            if let userId = log.userId {
                LabeledRow("用户 ID", "\(userId)")
            }
            if let accountId = log.accountId {
                LabeledRow("账号 ID", "\(accountId)")
            }
            if let apiKeyId = log.apiKeyId {
                LabeledRow("API Key ID", "\(apiKeyId)")
            }
            LabeledRow("发生时间", Fmt.date(log.createdAt))
        }
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
                    Text("设置自定义日期后将覆盖顶部快捷时间范围；按服务器本地时区的自然日过滤。")
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
                        // 自定义日期与快捷时间范围互斥：设置了日期则清除快捷范围
                        if filter.startDate != nil || filter.endDate != nil {
                            filter.timeWindow = .all
                        }
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
        if timeWindow != .all { parts.append(timeWindow.title) }
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
            if viewModel.filter.isActive {
                activeErrorFilterBar
            }
            if let error = viewModel.error, viewModel.logs.isEmpty {
                ErrorStateView(error: error) {
                    Task { await viewModel.reload() }
                }
                .listRowSeparator(.hidden)
            } else if viewModel.logs.isEmpty, !viewModel.isLoading {
                EmptyStateView(text: viewModel.filter.isActive ? "当前条件下无错误请求" : "暂无错误请求")
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
        .navigationTitle("错误请求")
        .navigationDestination(for: RequestErrorLog.self) { log in
            RequestErrorDetailView(errorLog: log) {
                Task { await viewModel.reload() }
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
        .searchable(text: $viewModel.filter.searchText, prompt: "搜索消息 / 请求 ID")
        .onChange(of: viewModel.filter.searchText) { _, _ in
            viewModel.debouncedFilter()
        }
        .sheet(isPresented: $viewModel.showFilterSheet) {
            RequestErrorFilterSheet(filter: viewModel.filter) { newFilter in
                // Sheet 不管理搜索框，保留当前 searchText（→ q 参数）
                var applied = newFilter
                applied.searchText = viewModel.filter.searchText
                viewModel.applyFilter(applied)
            }
        }
        .refreshable { await viewModel.reload() }
        .task { await viewModel.reloadIfNeeded() }
        .overlay {
            if viewModel.isLoading, viewModel.logs.isEmpty { LoadingView() }
        }
    }

    /// 已激活的筛选条件条（点 × 清除）
    private var activeErrorFilterBar: some View {
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
                    viewModel.applyFilter(RequestErrorFilter())
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.accentColor.opacity(0.08))
        }
    }
}

// MARK: - 错误请求筛选 Sheet

/// 错误请求多条件筛选（对照源码 ops_handler.go ListRequestErrors）
struct RequestErrorFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var filter: RequestErrorFilter

    let onApply: (RequestErrorFilter) -> Void

    init(filter: RequestErrorFilter, onApply: @escaping (RequestErrorFilter) -> Void) {
        _filter = State(initialValue: filter)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("时间范围", selection: $filter.timeWindow) {
                        ForEach(RequestErrorFilter.TimeWindow.allCases) { w in
                            Text(w.title).tag(w)
                        }
                    }
                } header: {
                    Text("时间窗口")
                } footer: {
                    Text("服务端单次查询窗口上限 30 天。")
                }

                Section("解决状态") {
                    Picker("状态", selection: $filter.resolved) {
                        ForEach(RequestErrorFilter.ResolvedFilter.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section("条件") {
                    TextField("平台（如 claude）", text: $filter.platform)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("模型（精确匹配）", text: $filter.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("账号 ID", text: $filter.accountId)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("筛选条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") {
                        filter = RequestErrorFilter()
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

/// 错误请求详情：完整字段 + 上游错误关联钻取 + 关联使用记录
/// GET /admin/ops/request-errors/:id + /admin/ops/request-errors/:id/upstream-errors
struct RequestErrorDetailView: View {
    @State private var viewModel = RequestErrorDetailViewModel()
    let errorLog: RequestErrorLog
    var onResolved: (() -> Void)?

    var body: some View {
        List {
            infoSection
            contextSection
            timingSection
            upstreamContextSection
            resolveSection
            relatedUsageSection
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
            if let detail = viewModel.detail, detail.isBusinessLimited == true {
                Label("业务限流（不计入可操作错误）", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            if let errorBody = viewModel.detail?.errorBody, !errorBody.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("错误响应体").font(.caption).foregroundStyle(.secondary)
                    Text(errorBody)
                        .font(.caption.monospaced())
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
            if let requestedModel = errorLog.requestedModel, !requestedModel.isEmpty {
                LabeledRow("请求模型", requestedModel)
            }
            if let model = errorLog.model {
                LabeledRow("计费模型", model)
            }
            if let upstreamModel = errorLog.upstreamModel, !upstreamModel.isEmpty {
                LabeledRow("上游模型", upstreamModel)
            }
            if let platform = errorLog.platform {
                LabeledRow("平台", platform)
            }
            if let requestPath = errorLog.requestPath, !requestPath.isEmpty {
                LabeledRow("请求路径", requestPath)
            }
            if let stream = errorLog.stream {
                LabeledRow("请求方式", stream ? "流式" : "非流式")
            }
            if let userEmail = errorLog.userEmail, !userEmail.isEmpty {
                LabeledRow("用户", userEmail)
            } else if let userId = errorLog.userId {
                LabeledRow("用户 ID", "\(userId)")
            }
            if let apiKeyName = errorLog.apiKeyName, !apiKeyName.isEmpty {
                LabeledRow("API Key", apiKeyName)
            } else if let apiKeyId = errorLog.apiKeyId {
                LabeledRow("API Key ID", "\(apiKeyId)")
            }
            if let apiKeyPrefix = viewModel.detail?.apiKeyPrefix, !apiKeyPrefix.isEmpty {
                LabeledRow("Key 前缀", apiKeyPrefix)
            }
            if let accountName = errorLog.accountName, !accountName.isEmpty {
                LabeledRow("账号", accountName)
            } else if let accountId = errorLog.accountId {
                LabeledRow("账号 ID", "\(accountId)")
            }
            if let groupName = errorLog.groupName, !groupName.isEmpty {
                LabeledRow("分组", groupName)
            }
            if let clientIp = errorLog.clientIp {
                LabeledRow("客户端 IP", clientIp)
            }
            if let userAgent = errorLog.userAgent, !userAgent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("User-Agent").font(.caption).foregroundStyle(.secondary)
                    Text(userAgent)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
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

    /// 延迟分解（认证 → 路由 → 上游 → 首字）
    private var timingSection: some View {
        Section("延迟分解") {
            if let detail = viewModel.detail {
                if let v = detail.authLatencyMs {
                    LabeledRow("认证", String(format: "%.0f ms", v))
                }
                if let v = detail.routingLatencyMs {
                    LabeledRow("路由", String(format: "%.0f ms", v))
                }
                if let v = detail.upstreamLatencyMs {
                    LabeledRow("上游", String(format: "%.0f ms", v))
                }
                if let v = detail.responseLatencyMs {
                    LabeledRow("响应", String(format: "%.0f ms", v))
                }
                if let v = detail.timeToFirstTokenMs {
                    LabeledRow("首字（TTFT）", String(format: "%.0f ms", v))
                }
            }
            if timingUnavailable {
                Text("无延迟数据")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var timingUnavailable: Bool {
        guard let d = viewModel.detail else { return false }
        return d.authLatencyMs == nil && d.routingLatencyMs == nil
            && d.upstreamLatencyMs == nil && d.responseLatencyMs == nil
            && d.timeToFirstTokenMs == nil
    }

    /// 上游上下文（详情接口返回）
    @ViewBuilder
    private var upstreamContextSection: some View {
        if let d = viewModel.detail,
           d.upstreamStatusCode != nil || !(d.upstreamErrorMessage ?? "").isEmpty {
            Section("上游上下文") {
                if let statusCode = d.upstreamStatusCode {
                    LabeledRow("上游 HTTP", "\(statusCode)")
                        .foregroundStyle(.red)
                }
                if let message = d.upstreamErrorMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if let upstreamDetail = d.upstreamErrorDetail, !upstreamDetail.isEmpty {
                    Text(upstreamDetail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
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

    /// 关联使用记录钻取：按 request_id 检索 /admin/usage
    @ViewBuilder
    private var relatedUsageSection: some View {
        if let requestId = errorLog.requestId, !requestId.isEmpty {
            Section {
                NavigationLink {
                    UsageLogsView(initialFilter: {
                        var f = UsageFilter()
                        f.requestId = requestId
                        return f
                    }())
                } label: {
                    Label("查看关联使用记录", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("钻取")
            } footer: {
                Text("按 Request ID 检索使用记录。")
            }
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

@MainActor
@Observable
final class RequestErrorDetailViewModel {
    var detail: RequestErrorDetail?
    var upstreamErrors: [UpstreamErrorLog] = []
    var resolved = false
    var isResolving = false
    var showError = false
    var errorMessage = ""

    private var client: APIClient? { AppStateHolder.shared.client }

    func load(errorLog: RequestErrorLog) async {
        resolved = (errorLog.resolved == true)
        guard let client, let id = errorLog.id else { return }
        // 详情（error_body / 上游上下文 / 延迟分解）失败不阻塞页面
        detail = try? await client.request("GET", "/admin/ops/request-errors/\(id)")
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

@MainActor
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

    func reloadIfNeeded(initialFilter: UsageFilter? = nil) async {
        guard !loadedOnce else { return }
        if let initialFilter { filter = initialFilter }
        loadedOnce = true
        await reload()
    }

    func applyFilter(_ newFilter: UsageFilter) {
        // onChange(of: filter.timeWindow) 已负责时间窗变化时的 reload；
        // 此处仅在时间窗未变时自行触发，避免一次「应用」产生两个并发 reload 竞态
        let timeWindowChanged = filter.timeWindow != newFilter.timeWindow
        filter = newFilter
        if !timeWindowChanged {
            Task { await reload() }
        }
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
        // 失败回退页码，避免下次加载跳过整页数据
        let ok = await loadPage()
        if !ok { query.page -= 1 }
    }

    @discardableResult
    private func loadPage() async -> Bool {
        guard let client else { return false }
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
        // 快捷时间窗口优先；未选择时沿用自定义日期范围
        if let quickStart = filter.timeWindow.rangeStart() {
            extra["start_date"] = formatter.string(from: quickStart)
            extra["end_date"] = formatter.string(from: .now)
        } else {
            if let start = filter.startDate { extra["start_date"] = formatter.string(from: start) }
            if let end = filter.endDate { extra["end_date"] = formatter.string(from: end) }
        }
        query.extra = extra

        do {
            let page: Page<UsageLog> = try await client.page("/admin/usage", query: query)
            if query.page == 1 { logs = page.items } else { logs += page.items }
            reachedEnd = logs.count >= page.total
            error = nil
            return true
        } catch {
            self.error = error
            return false
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

@MainActor
@Observable
final class RequestErrorsViewModel {
    var logs: [RequestErrorLog] = []
    var isLoading = false
    var error: Error?

    var filter = RequestErrorFilter()
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

    func applyFilter(_ newFilter: RequestErrorFilter) {
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
        // 失败回退页码，避免下次加载跳过整页数据
        let ok = await loadPage()
        if !ok { query.page -= 1 }
    }

    @discardableResult
    private func loadPage() async -> Bool {
        guard let client else { return false }
        isLoading = true
        defer { isLoading = false }

        // 后端默认窗口仅 1h，必须显式传 start_time（RFC3339）
        query.extra = filter.queryItems()

        do {
            let page: Page<RequestErrorLog> = try await client.page(
                "/admin/ops/request-errors", query: query
            )
            if query.page == 1 { logs = page.items } else { logs += page.items }
            reachedEnd = logs.count >= page.total
            error = nil
            return true
        } catch {
            self.error = error
            return false
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
