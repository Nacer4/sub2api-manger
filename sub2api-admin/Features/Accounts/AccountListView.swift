import SwiftUI

/// 账号管理：分页 + 平台/状态/等级/认证筛选 + 多选批量操作 + 新增账号 + 分组管理
struct AccountListView: View {
    @State private var viewModel = AccountListViewModel()

    var body: some View {
        NavigationStack {
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
        .navigationTitle("账号管理")
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
                        viewModel.showAddSheet = true
                    } label: {
                        Label("新增", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        GroupListView()
                    } label: {
                        Label("分组", systemImage: "square.stack.3d.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.enterSelection()
                    } label: {
                        Label("选择", systemImage: "checkmark.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
            AccountAddSheet { name, platform, authType, credential in
                Task {
                    await viewModel.createAccount(
                        name: name, platform: platform, authType: authType, credential: credential
                    )
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

            Picker("等级", selection: $viewModel.tierFilter) {
                Text("全部").tag("")
                ForEach(viewModel.tiers, id: \.self) { tier in
                    Text(tier).tag(tier)
                }
            }
            .onChange(of: viewModel.tierFilter) { _, _ in
                Task { await viewModel.reload() }
            }

            Picker("认证方式", selection: $viewModel.authFilter) {
                Text("全部").tag("")
                ForEach(viewModel.authTypes, id: \.self) { auth in
                    Text(auth).tag(auth)
                }
            }
            .onChange(of: viewModel.authFilter) { _, _ in
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
                if let tier = account.tier, !tier.isEmpty {
                    Text("· \(tier)")
                        .foregroundStyle(.tint)
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

/// 新增账号 Sheet（对标 sub2api 官方 dashboard：OAuth 授权流 / API Key 两种方式）
/// OAuth：生成授权链接（POST /admin/{platform}/oauth/auth-url）→ 浏览器完成授权 → 粘贴回跳码交换
/// API Key：直填 key 创建（POST /admin/accounts）
struct AccountAddSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var platform = "claude"
    @State private var authType = "api_key"
    @State private var apiKey = ""
    @State private var proxy = ""
    @State private var oauthURL = ""
    @State private var oauthCode = ""
    @State private var isGeneratingURL = false
    @State private var isSaving = false

    let onCreate: (_ name: String, _ platform: String, _ authType: String, _ credential: String) -> Void

    private let platforms = ["claude", "openai", "gemini", "antigravity", "grok"]
    private var isOAuth: Bool { authType == "oauth" }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称（必填）", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("平台", selection: $platform) {
                        ForEach(platforms, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section {
                    Picker("认证方式", selection: $authType) {
                        Text("API Key").tag("api_key")
                        Text("OAuth").tag("oauth")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)

                    if isOAuth {
                        // OAuth 两步：生成授权链接 → 粘贴回跳码
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                generateAuthURL()
                            } label: {
                                if isGeneratingURL {
                                    HStack { ProgressView(); Text("生成中…") }
                                } else {
                                    Label("生成 OAuth 授权链接", systemImage: "link")
                                }
                            }
                            .disabled(isGeneratingURL || isSaving)

                            if !oauthURL.isEmpty {
                                Text(oauthURL)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }

                            TextField("粘贴回跳链接或授权码", text: $oauthCode)
                                .font(.caption.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } else {
                        TextField("API Key（sk-…）", text: $apiKey)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("代理（可选）", text: $proxy)
                            .font(.caption.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("认证")
                } footer: {
                    Text(isOAuth
                         ? "先生成授权链接并在浏览器完成授权，再粘贴回跳链接或授权码。"
                         : "API Key 将以密文存储，保存后不可查看。")
                }
            }
            .navigationTitle("新增账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        isSaving = true
                        let credential = isOAuth
                            ? oauthCode.trimmingCharacters(in: .whitespaces)
                            : apiKey.trimmingCharacters(in: .whitespaces)
                        onCreate(name.trimmingCharacters(in: .whitespaces), platform, authType, credential)
                        isSaving = false
                        dismiss()
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return isOAuth ? !oauthCode.trimmingCharacters(in: .whitespaces).isEmpty
                       : !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 生成 OAuth 授权链接（POST /admin/{platform}/oauth/auth-url）
    private func generateAuthURL() {
        guard let client = AppStateHolder.shared.client else { return }
        isGeneratingURL = true
        Task {
            defer { isGeneratingURL = false }
            struct Body: Encodable { let platform: String }
            struct Resp: Decodable { let authUrl: String?; let url: String?
                enum CodingKeys: String, CodingKey {
                    case authUrl = "auth_url", url
                }
            }
            if let resp: Resp = try? await client.request(
                "POST", "/admin/\(platform)/oauth/auth-url", body: Body(platform: platform)
            ) {
                oauthURL = resp.authUrl ?? resp.url ?? ""
                if oauthURL.isEmpty { oauthURL = "授权链接为空，请检查服务端配置。" }
            } else {
                oauthURL = "生成失败：无法连接服务器。"
            }
        }
    }
}

/// 批量操作确认弹窗（删除类操作红色确认 + 选中账号预览）
struct BatchConfirmSheet: View {    @Environment(\.dismiss) private var dismiss
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
    var tierFilter = ""
    var authFilter = ""

    // 多选批量操作状态
    var isSelecting = false
    var selectedIds: Set<Int> = []
    var showBatchSheet = false
    var pendingBatchAction: AccountBatchAction?
    var showBatchResult = false
    var batchResultMessage = ""

    // 新增账号
    var showAddSheet = false

    /// 常见上游平台（作为筛选项）
    let platforms = ["claude", "openai", "gemini", "antigravity", "grok", "kimi", "zhipu", "deepseek"]

    /// 账号等级（与设计稿一致）
    let tiers = ["free", "pro", "max5", "max20"]

    /// 认证方式
    let authTypes = ["oauth", "api_key"]

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

    // MARK: - 新增账号

    /// 创建账号（POST /admin/accounts）
    /// - API Key：credential 为 key 明文
    /// - OAuth：credential 为回跳链接或授权码，先经 exchange-code 交换再创建
    func createAccount(name: String, platform: String, authType: String, credential: String) async {
        guard let client, !name.isEmpty, !credential.isEmpty else { return }
        do {
            var finalCredential = credential
            if authType == "oauth" {
                // OAuth：先交换授权码（POST /admin/{platform}/oauth/exchange-code）
                struct ExchangeBody: Encodable { let code: String }
                struct ExchangeResp: Decodable {
                    let apiKey: String?; let api_key: String?
                    let accessToken: String?
                }
                if let resp: ExchangeResp = try? await client.request(
                    "POST", "/admin/\(platform)/oauth/exchange-code",
                    body: ExchangeBody(code: credential)
                ) {
                    finalCredential = resp.apiKey ?? resp.api_key ?? resp.accessToken ?? credential
                }
            }
            struct Body: Encodable {
                let name: String
                let platform: String
                let authType: String
                let apiKey: String
                enum CodingKeys: String, CodingKey {
                    case name, platform, apiKey
                    case authType = "auth_type"
                }
            }
            let _: EmptyData = try await client.request(
                "POST", "/admin/accounts",
                body: Body(name: name, platform: platform, authType: authType, apiKey: finalCredential)
            )
            batchResultMessage = "账号「\(name)」已创建。"
            showBatchResult = true
            await reload()
        } catch {
            batchResultMessage = "创建失败：\(error.localizedDescription)"
            showBatchResult = true
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
        if !tierFilter.isEmpty { extra["tier"] = tierFilter }
        if !authFilter.isEmpty { extra["auth_type"] = authFilter }
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
