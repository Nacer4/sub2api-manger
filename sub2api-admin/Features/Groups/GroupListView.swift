import SwiftUI

/// 分组管理：列表 + 新建/编辑/删除
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
                onSave: { name, desc, models, priority in
                    Task { await viewModel.save(name: name, description: desc, models: models, priority: priority) }
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

struct GroupRow: View {
    let group: AccountGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.name ?? "分组 #\(group.id)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let priority = group.priority {
                    Text("P\(priority)")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.12), in: .capsule)
                }
            }
            if let desc = group.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let models = group.models, !models.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(models, id: \.self) { model in
                            Text(model)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.1), in: .capsule)
                        }
                    }
                }
            }
            Text("ID \(group.id)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 新建/编辑 Sheet

/// 分组表单：名称 / 描述 / 模型列表（逗号分隔）/ 优先级；编辑模式附加删除
struct GroupEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var desc: String
    @State private var modelsText: String
    @State private var priority: Int
    @State private var isRunning = false

    let existing: AccountGroup?
    let onSave: (String, String, [String], Int) async -> Void
    let onDelete: (() async -> Void)?

    init(
        group: AccountGroup?,
        onSave: @escaping (String, String, [String], Int) async -> Void,
        onDelete: (() async -> Void)? = nil
    ) {
        existing = group
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: group?.name ?? "")
        _desc = State(initialValue: group?.description ?? "")
        _modelsText = State(initialValue: (group?.models ?? []).joined(separator: ", "))
        _priority = State(initialValue: group?.priority ?? 0)
    }

    private var models: [String] {
        modelsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称（必填）", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("描述", text: $desc)
                    Stepper("优先级 \(priority)", value: $priority, in: 0...9999)
                }

                Section {
                    TextField("claude-sonnet-4.5, gpt-5.2-codex", text: $modelsText, axis: .vertical)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(2...4)
                } header: {
                    Text("模型列表")
                } footer: {
                    Text("逗号分隔。请求模型命中分组内模型时路由到该分组。")
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
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        isRunning = true
                        Task {
                            await onSave(
                                name.trimmingCharacters(in: .whitespaces),
                                desc.trimmingCharacters(in: .whitespaces),
                                models,
                                priority
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
    func save(name: String, description: String, models: [String], priority: Int) async {
        guard let client else { return }
        struct Body: Encodable {
            let name: String
            let description: String?
            let models: [String]
            let priority: Int
        }
        let body = Body(
            name: name,
            description: description.isEmpty ? nil : description,
            models: models,
            priority: priority
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
