import SwiftUI

/// 设置：服务器管理 → 系统信息 → 登出
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                serverSection
                sessionSection
                systemSection
                aboutSection
            }
            .navigationTitle("设置")
            .task { await viewModel.loadVersion() }
            .sheet(isPresented: $viewModel.showServerSheet) {
                if let editing = viewModel.editingServer {
                    ServerEditSheet(server: editing) { saved in
                        appState.serverStore.upsert(saved)
                        appState.refreshServer()
                        viewModel.servers = appState.serverStore.servers
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddSheet) {
                ServerEditSheet(server: ServerConfig.newPlaceholder()) { saved in
                    appState.serverStore.upsert(saved)
                    viewModel.servers = appState.serverStore.servers
                }
            }
            .confirmationDialog("删除服务器？", isPresented: $viewModel.showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let server = viewModel.deletingServer {
                        appState.serverStore.delete(server)
                        viewModel.servers = appState.serverStore.servers
                        appState.refreshServer()
                    }
                }
            } message: {
                Text("将清除该服务器的登录凭证。")
            }
        }
    }

    // MARK: - 服务器管理

    private var serverSection: some View {
        Section("服务器") {
            ForEach(viewModel.servers) { server in
                Button {
                    appState.switchServer(server)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name.isEmpty ? server.baseURL : server.name)
                                .foregroundStyle(.primary)
                            Text(server.baseURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if server.id == appState.activeServer?.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        viewModel.deletingServer = server
                        viewModel.showDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button {
                        viewModel.editingServer = server
                        viewModel.showServerSheet = true
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                }
            }

            Button {
                viewModel.showAddSheet = true
            } label: {
                Label("添加服务器", systemImage: "plus")
            }
        }
    }

    // MARK: - 会话

    private var sessionSection: some View {
        Section("当前会话") {
            if let server = appState.activeServer {
                LabeledRow("服务器", server.name.isEmpty ? server.baseURL : server.name)
                LabeledRow("认证方式", server.authMode == .jwt ? "JWT（面板账号）" : "Admin API Key")
            }
            Button(role: .destructive) {
                appState.sessionEnded()
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    // MARK: - 系统

    private var systemSection: some View {
        Section("系统") {
            if viewModel.isCheckingVersion {
                HStack { ProgressView().controlSize(.small); Text("检查更新…") }
            } else {
                LabeledRow("服务端版本", viewModel.version?.version)
                LabeledRow("构建时间", Fmt.date(viewModel.version?.buildDate))
            }
            Button {
                Task { await viewModel.loadVersion(force: true) }
            } label: {
                Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledRow("应用", "Sub2Admin 0.1.0")
            LabeledRow("开源项目", "Wei-Shaw/sub2api")
        }
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    var servers: [ServerConfig] = ServerStore.shared.servers
    var version: SystemVersion?
    var isCheckingVersion = false

    var showServerSheet = false
    var showAddSheet = false
    var showDeleteConfirm = false
    var editingServer: ServerConfig?
    var deletingServer: ServerConfig?

    private var loadedOnce = false

    func loadVersion(force: Bool = false) async {
        if loadedOnce && !force { return }
        loadedOnce = true
        guard let client = AppStateHolder.shared.client else { return }
        isCheckingVersion = true
        defer { isCheckingVersion = false }
        version = try? await client.request("GET", "/admin/system/version")
    }
}
