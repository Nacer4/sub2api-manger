import SwiftUI

/// 分组管理：信息卡（平台/计费/倍率/类型/账号数/容量/用量）+ 新建/编辑/复制/删除
/// 契约（routes/admin.go registerGroupRoutes）：
/// GET /admin/groups（AdminGroup 分页）
/// GET /admin/groups/usage-summary（今日/昨日/累计费用）
/// GET /admin/groups/capacity-summary（并发/会话/RPM 容量）
/// POST /admin/groups、PUT /admin/groups/:id、DELETE /admin/groups/:id、POST /admin/groups/:id/duplicate
struct GroupListView: View {
    @State private var viewModel = GroupListViewModel()

    var body: some View {
        List {
            if let error = viewModel.error, viewModel.groups.isEmpty {
                ErrorStateView(error: error) {
                    Task { await viewModel.reload() }
                }
                .listRowSeparator(.hidden)
            } else if viewModel.groups.isEmpty, !viewModel.isLoading {
                EmptyStateView(text: "暂无分组")
            } else {
                ForEach(viewModel.groups) { group in
                    Button {
                        viewModel.openEdit(group)
                    } label: {
                        GroupRow(
                            group: group,
                            usage: viewModel.usage(for: group),
                            capacity: viewModel.capacity(for: group)
                        )
                    }
                    .tint(.primary)
                    .contextMenu {
                        Button {
                            Task { await viewModel.duplicate(group) }
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        Button {
                            viewModel.notice("分组「\(group.name ?? "#\(group.id)")」专属倍率设置（PUT /admin/groups/:id/rate-multipliers）")
                        } label: {
                            Label("专属倍率", systemImage: "percent")
                        }
                        Button {
                            viewModel.notice("分组「\(group.name ?? "#\(group.id)")」专属 RPM 设置（PUT /admin/groups/:id/rpm-overrides）")
                        } label: {
                            Label("专属 RPM", systemImage: "gauge.with.needle")
                        }
                    }
                }
            }
        }
        .navigationTitle("分组管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.openCreate()
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.showEditSheet) {
            GroupEditSheet(
                group: viewModel.editingGroup,
                onSave: { name, description, platform, rate, isExclusive, subscriptionType in
                    Task {
                        await viewModel.save(
                            name: name, description: description, platform: platform,
                            rate: rate, isExclusive: isExclusive, subscriptionType: subscriptionType
                        )
                    }
                },
                onDelete: viewModel.editingGroup == nil ? nil : {
                    Task { await viewModel.delete(viewModel.editingGroup!) }
                }
            )
        }
        .refreshable { await viewModel.reload() }
        .task { await viewModel.reloadIfNeeded() }
        .overlay {
            if viewModel.isLoading, viewModel.groups.isEmpty { LoadingView() }
        }
        .alert("提示", isPresented: $viewModel.showResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.resultMessage)
        }
    }
}

// MARK: - 分组信息卡

struct GroupRow: View {
    let group: AccountGroup
    let usage: GroupUsageSummary?
    let capacity: GroupCapacitySummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.name ?? "分组 #\(group.id)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                statusPill
            }

            if let description = group.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                LabeledRow("平台", group.platform?.uppercased())
                LabeledRow("计费类型", group.billingDisplay)
                LabeledRow("费率倍数", group.rateMultiplier.map { "\($0)x" })
                LabeledRow("类型", group.typeDisplay)
                LabeledRow("账号数", accountsText)
                LabeledRow("容量", capacityText)
                LabeledRow("用量", usageText)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusPill: some View {
        let text = group.status?.isEmpty == false ? group.status! : "正常"
        let color: Color = text == "正常" || text == "active" ? .green : .orange
        return Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var accountsText: String? {
        guard group.accountCount != nil || group.activeAccountCount != nil else { return nil }
        var parts: [String] = []
        if let active = group.activeAccountCount { parts.append("可用:\(active)个账号") }
        if let total = group.accountCount { parts.append("总量:\(total)个账号") }
        return parts.joined(separator: " · ")
    }

    /// 容量 = 实时并发 / 并发上限（capacity-summary）
    private var capacityText: String? {
        if let cap = capacity, cap.concurrencyMax > 0 {
            return "\(cap.concurrencyUsed) / \(cap.concurrencyMax)"
        }
        return nil
    }

    /// 用量 = 今日 / 昨日 / 累计（usage-summary）
    private var usageText: String? {
        guard let usage else { return nil }
        return "今日\(Fmt.usd(usage.todayCost)) · 昨日\(Fmt.usd(usage.yesterdayCost)) · 累计\(Fmt.usd(usage.totalCost))"
    }
}

// MARK: - 新建/编辑 Sheet

/// 分组表单：名称 / 描述 / 平台 / 费率倍数 / 类型（is_exclusive）/ 计费类型（subscription_type）
/// 保存体对照 CreateGroupRequest / UpdateGroupRequest json 键
struct GroupEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var descriptionText: String
    @State private var platform: String
    @State private var rateText: String
    @State private var isExclusive: Bool
    @State private var subscriptionType: String
    @State private var isRunning = false

    let existing: AccountGroup?
    let onSave: (String, String, String, Double, Bool, String) async -> Void
    let onDelete: (() async -> Void)?

    init(
        group: AccountGroup?,
        onSave: @escaping (String, String, String, Double, Bool, String) async -> Void,
        onDelete: (() async -> Void)? = nil
    ) {
        existing = group
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: group?.name ?? "")
        _descriptionText = State(initialValue: group?.description ?? "")
        _platform = State(initialValue: group?.platform ?? "openai")
        _rateText = State(initialValue: group.map { String(format: "%.3g", $0.rateMultiplier ?? 0.1) } ?? "0.1")
        _isExclusive = State(initialValue: group?.isExclusive ?? false)
        _subscriptionType = State(initialValue: group?.subscriptionType ?? "standard")
    }

    /// platform 契约值（CreateGroupRequest oneof 枚举）
    private let platforms = [
        "anthropic", "openai", "gemini", "antigravity", "grok",
        "kimi", "zhipu", "deepseek", "composite",
    ]
    /// subscription_type 契约值
    private let subscriptionTypes = ["standard", "subscription"]

    private var rate: Double { Double(rateText.trimmingCharacters(in: .whitespaces)) ?? 0.1 }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称（必填）", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("描述", text: $descriptionText)
                        .autocorrectionDisabled()
                    Picker("平台", selection: $platform) {
                        ForEach(platforms, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("费率倍数（如 0.1）", text: $rateText)
                        .keyboardType(.decimalPad)
                        .font(.body.monospaced())
                    Toggle("私有分组（is_exclusive）", isOn: $isExclusive)
                    Picker("计费类型", selection: $subscriptionType) {
                        ForEach(subscriptionTypes, id: \.self) { Text($0).tag($0) }
                    }
                }

                if onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            guard let onDelete else { return }
                            isRunning = true
                            Task {
                                await onDelete()
                                isRunning = false
                                dismiss()
                            }
                        } label: {
                            Label("删除分组", systemImage: "trash")
                        }
                        .disabled(isRunning)
                    }
                }
            }
            .navigationTitle(existing == nil ? "新建分组" : "编辑分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        isRunning = true
                        Task {
                            await onSave(
                                trimmed, descriptionText, platform, rate,
                                isExclusive, subscriptionType
                            )
                            isRunning = false
                            dismiss()
                        }
                    }
                    .disabled(isRunning || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class GroupListViewModel {
    var groups: [AccountGroup] = []
    var usageSummaries: [GroupUsageSummary] = []
    var capacitySummaries: [GroupCapacitySummary] = []
    var isLoading = false
    var error: Error?

    var showEditSheet = false
    var editingGroup: AccountGroup?
    var showResult = false
    var resultMessage = ""

    private var loadedOnce = false
    private var client: APIClient? { AppStateHolder.shared.client }

    func usage(for group: AccountGroup) -> GroupUsageSummary? {
        usageSummaries.first { $0.groupId == group.id }
    }

    func capacity(for group: AccountGroup) -> GroupCapacitySummary? {
        capacitySummaries.first { $0.groupId == group.id }
    }

    func reloadIfNeeded() async {
        guard !loadedOnce else { return }
        loadedOnce = true
        await reload()
    }

    func openCreate() {
        editingGroup = nil
        showEditSheet = true
    }

    func openEdit(_ group: AccountGroup) {
        editingGroup = group
        showEditSheet = true
    }

    func notice(_ message: String) {
        resultMessage = message
        showResult = true
    }

    func reload() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page: Page<AccountGroup> = try await client.page(
                "/admin/groups", query: PageQuery(pageSize: 200)
            )
            groups = page.items
            error = nil
        } catch {
            self.error = error
        }
        // 汇总端点失败不阻塞分组列表（对应区块显示 "-"）
        await loadSummaries()
    }

    private func loadSummaries() async {
        guard let client else { return }
        do {
            let usages: [GroupUsageSummary] = try await client.request(
                "GET", "/admin/groups/usage-summary"
            )
            usageSummaries = usages
        } catch {
            usageSummaries = []
        }
        do {
            let capacities: [GroupCapacitySummary] = try await client.request(
                "GET", "/admin/groups/capacity-summary"
            )
            capacitySummaries = capacities
        } catch {
            capacitySummaries = []
        }
    }

    /// 创建 / 更新，body 对照 CreateGroupRequest / UpdateGroupRequest
    /// （name / description / platform / rate_multiplier / is_exclusive / subscription_type）
    func save(
        name: String, description: String, platform: String,
        rate: Double, isExclusive: Bool, subscriptionType: String
    ) async {
        guard let client else { return }
        struct Body: Encodable {
            let name: String
            let description: String
            let platform: String
            let rateMultiplier: Double
            let isExclusive: Bool
            let subscriptionType: String

            enum CodingKeys: String, CodingKey {
                case name, description, platform
                case rateMultiplier = "rate_multiplier"
                case isExclusive = "is_exclusive"
                case subscriptionType = "subscription_type"
            }
        }
        let body = Body(
            name: name, description: description, platform: platform,
            rateMultiplier: rate, isExclusive: isExclusive, subscriptionType: subscriptionType
        )
        do {
            if let existing = editingGroup {
                let _: EmptyData = try await client.request(
                    "PUT", "/admin/groups/\(existing.id)", body: body
                )
                resultMessage = "分组「\(name)」已更新。"
            } else {
                let _: EmptyData = try await client.request(
                    "POST", "/admin/groups", body: body
                )
                resultMessage = "分组「\(name)」已创建。"
            }
            await reload()
        } catch {
            resultMessage = "保存失败：\(error.localizedDescription)"
        }
        showResult = true
    }

    /// 复制分组（POST /admin/groups/:id/duplicate，服务端原生复制）
    func duplicate(_ group: AccountGroup) async {
        guard let client else { return }
        do {
            let _: EmptyData = try await client.request(
                "POST", "/admin/groups/\(group.id)/duplicate"
            )
            resultMessage = "分组「\(group.name ?? "#\(group.id)")」已复制。"
            await reload()
        } catch {
            resultMessage = "复制失败：\(error.localizedDescription)"
        }
        showResult = true
    }

    /// 删除（DELETE /admin/groups/:id）
    func delete(_ group: AccountGroup) async {
        guard let client else { return }
        do {
            let _: EmptyData = try await client.request(
                "DELETE", "/admin/groups/\(group.id)"
            )
            resultMessage = "分组「\(group.name ?? "#\(group.id)")」已删除。"
            await reload()
        } catch {
            resultMessage = "删除失败：\(error.localizedDescription)"
        }
        showResult = true
    }
}
