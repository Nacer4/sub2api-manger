import SwiftUI

/// 分组管理：信息卡展示（平台/计费/倍率/类型/账号数/容量/用量）+ 新建/编辑/删除
/// API：GET/POST /admin/groups，PUT/DELETE /admin/groups/:id
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
                        GroupRow(group: group)
                    }
                    .tint(.primary)
                    .contextMenu {
                        Button {
                            viewModel.copyGroup(group)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        Button {
                            viewModel.notice("分组「\(group.name ?? "#\(group.id)")」专属倍率设置")
                        } label: {
                            Label("专属倍率", systemImage: "percent")
                        }
                        Button {
                            viewModel.notice("分组「\(group.name ?? "#\(group.id)")」专属 RPM 设置")
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
                onSave: { name, platform, billingType, rate, groupType in
                    Task {
                        await viewModel.save(
                            name: name, platform: platform, billingType: billingType,
                            rate: rate, groupType: groupType
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.name ?? "分组 #\(group.id)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                statusPill
            }

            VStack(spacing: 0) {
                LabeledRow("平台", group.platform)
                LabeledRow("计费类型", group.billingType)
                LabeledRow("费率倍数", group.rateMultiplier.map { "\($0)x" })
                LabeledRow("类型", group.groupType)
                LabeledRow("账号数", accountsText)
                LabeledRow("容量", capacityText)
                LabeledRow("用量", usageText)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusPill: some View {
        let text = group.status ?? "正常"
        let color: Color = text == "正常" ? .green : .orange
        return Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var accountsText: String? {
        switch (group.availableAccounts, group.totalAccounts) {
        case let (avail?, total?): return "可用:\(avail)个账号 · 总量:\(total)个账号"
        case let (avail?, nil): return "可用:\(avail)个账号"
        case let (nil, total?): return "总量:\(total)个账号"
        default: return nil
        }
    }

    private var capacityText: String? {
        if let used = group.capacityUsed, let limit = group.capacityLimit {
            return "\(used) / \(limit)"
        }
        return group.capacityLimit.map { "- / \($0)" }
    }

    private var usageText: String? {
        var parts: [String] = []
        if let today = group.todayCost { parts.append("今日\(Fmt.usd(today))") }
        if let yesterday = group.yesterdayCost { parts.append("昨日\(Fmt.usd(yesterday))") }
        if let total = group.totalCost { parts.append("累计\(Fmt.usd(total))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - 新建/编辑 Sheet

/// 分组表单：名称 / 平台 / 计费类型 / 费率倍数 / 类型；编辑模式附加删除
struct GroupEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var platform: String
    @State private var billingType: String
    @State private var rateText: String
    @State private var groupType: String
    @State private var isRunning = false

    let existing: AccountGroup?
    let onSave: (String, String, String, Double, String) async -> Void
    let onDelete: (() async -> Void)?

    init(
        group: AccountGroup?,
        onSave: @escaping (String, String, String, Double, String) async -> Void,
        onDelete: (() async -> Void)? = nil
    ) {
        existing = group
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: group?.name ?? "")
        _platform = State(initialValue: group?.platform ?? "OpenAI")
        _billingType = State(initialValue: group?.billingType ?? "标准（余额）")
        _rateText = State(initialValue: group.map { String(format: "%.3g", $0.rateMultiplier ?? 0.1) } ?? "0.1")
        _groupType = State(initialValue: group?.groupType ?? "公开")
    }

    private let platforms = ["OpenAI", "Claude", "Gemini", "Grok"]
    private let billingTypes = ["标准（余额）", "标准（订阅）", "按量计费"]
    private let groupTypes = ["公开", "私有"]

    private var rate: Double { Double(rateText.trimmingCharacters(in: .whitespaces)) ?? 0.1 }

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
                    Picker("计费类型", selection: $billingType) {
                        ForEach(billingTypes, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("费率倍数（如 0.1）", text: $rateText)
                        .keyboardType(.decimalPad)
                        .font(.body.monospaced())
                    Picker("类型", selection: $groupType) {
                        ForEach(groupTypes, id: \.self) { Text($0).tag($0) }
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
                            await onSave(trimmed, platform, billingType, rate, groupType)
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
    var isLoading = false
    var error: Error?

    var showEditSheet = false
    var editingGroup: AccountGroup?
    var showResult = false
    var resultMessage = ""

    private var loadedOnce = false
    private var client: APIClient? { AppStateHolder.shared.client }

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
    }

    /// 创建 / 更新（对应 POST /admin/groups 与 PUT /admin/groups/:id）
    func save(name: String, platform: String, billingType: String, rate: Double, groupType: String) async {
        guard let client else { return }
        struct Body: Encodable {
            let name: String
            let platform: String
            let billingType: String
            let rateMultiplier: Double
            let groupType: String

            enum CodingKeys: String, CodingKey {
                case name, platform
                case billingType = "billing_type"
                case rateMultiplier = "rate_multiplier"
                case groupType = "group_type"
            }
        }
        let body = Body(
            name: name, platform: platform, billingType: billingType,
            rateMultiplier: rate, groupType: groupType
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

    /// 复制分组配置（新建同配置分组）
    func copyGroup(_ group: AccountGroup) {
        guard let client else { return }
        let name = (group.name ?? "group") + "-copy"
        struct Body: Encodable {
            let name: String
            let platform: String
            let billingType: String
            let rateMultiplier: Double
            let groupType: String

            enum CodingKeys: String, CodingKey {
                case name, platform
                case billingType = "billing_type"
                case rateMultiplier = "rate_multiplier"
                case groupType = "group_type"
            }
        }
        let body = Body(
            name: name,
            platform: group.platform ?? "OpenAI",
            billingType: group.billingType ?? "标准（余额）",
            rateMultiplier: group.rateMultiplier ?? 0.1,
            groupType: group.groupType ?? "公开"
        )
        Task {
            do {
                let _: EmptyData = try await client.request("POST", "/admin/groups", body: body)
                resultMessage = "已复制为分组「\(name)」。"
                await reload()
            } catch {
                resultMessage = "复制失败：\(error.localizedDescription)"
            }
            showResult = true
        }
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
