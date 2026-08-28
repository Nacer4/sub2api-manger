import SwiftUI

/// 登录页：选择/新建服务器 + 面板账号（含 2FA）或 Admin API Key
struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = LoginViewModel()

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                credentialSection
                loginButton
            }
            .navigationTitle("Sub2Admin")
            .alert("登录失败", isPresented: $viewModel.showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .sheet(isPresented: $viewModel.showServerSheet) {
                ServerEditSheet(server: viewModel.draftServer) { saved in
                    viewModel.applyServer(saved)
                }
            }
        }
    }

    // MARK: - 服务器

    private var serverSection: some View {
        Section("服务器") {
            if viewModel.servers.isEmpty {
                Button {
                    viewModel.newServer()
                } label: {
                    Label("添加 sub2api 服务器", systemImage: "plus")
                }
            } else {
                Picker("服务器", selection: $viewModel.selectedServerId) {
                    ForEach(viewModel.servers) { server in
                        Text(server.name.isEmpty ? server.baseURL : server.name).tag(Optional(server.id))
                    }
                }
                .onChange(of: viewModel.selectedServerId) { _, newId in
                    viewModel.selectServer(newId)
                }

                Button {
                    viewModel.newServer()
                } label: {
                    Label("添加服务器", systemImage: "plus")
                }

                if let selected = viewModel.selectedServer {
                    Button {
                        viewModel.editServer(selected)
                    } label: {
                        Label("编辑当前服务器", systemImage: "pencil")
                    }
                }
            }
        }
    }

    // MARK: - 凭证

    @ViewBuilder
    private var credentialSection: some View {
        Section {
            Picker("认证方式", selection: $viewModel.authMode) {
                Text("面板账号").tag(ServerConfig.AuthMode.jwt)
                Text("Admin API Key").tag(ServerConfig.AuthMode.adminKey)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            switch viewModel.authMode {
            case .jwt:
                TextField("邮箱", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码", text: $viewModel.password)

                // 开启 2FA 的账号：第一步登录后进入此步骤
                if let masked = viewModel.pending2FAEmail {
                    Text("账号 \(masked) 已开启两步验证，请输入 6 位验证码")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("2FA 验证码", text: $viewModel.totp)
                        .keyboardType(.numberPad)
                }
            case .adminKey:
                SecureField("admin- 开头的 API Key", text: $viewModel.adminKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("凭证")
        } footer: {
            if viewModel.authMode == .adminKey {
                Text("Admin API Key 可在管理后台「系统设置 → Admin API Key」中生成。敏感操作（导出、备份等）仍需要 TOTP 二次验证。")
            } else if viewModel.pending2FAEmail != nil {
                Text("验证码来自你的身份验证器 App（TOTP）。")
            }
        }
    }

    private var loginButton: some View {
        Section {
            Button {
                Task {
                    if viewModel.pending2FAEmail != nil {
                        await viewModel.submit2FA(appState)
                    } else {
                        await viewModel.login(appState)
                    }
                }
            } label: {
                if viewModel.isLoggingIn {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("登录中…")
                    }
                } else if viewModel.pending2FAEmail != nil {
                    Text("验证并登录").frame(maxWidth: .infinity)
                } else {
                    Text("登录").frame(maxWidth: .infinity)
                }
            }
            .disabled(!viewModel.canLogin || viewModel.isLoggingIn)
            .buttonStyle(.borderedProminent)
            .listRowBackground(Color.clear)

            if viewModel.pending2FAEmail != nil {
                Button("返回重新输入密码") {
                    viewModel.cancel2FA()
                }
                .font(.footnote)
                .listRowBackground(Color.clear)
            }
        }
    }
}

@Observable
final class LoginViewModel {
    var servers: [ServerConfig] = ServerStore.shared.servers
    var selectedServerId: UUID?
    var selectedServer: ServerConfig?
    var authMode: ServerConfig.AuthMode = .jwt

    var email = ""
    var password = ""
    var totp = ""
    var adminKey = ""

    var isLoggingIn = false
    var showError = false
    var errorMessage = ""

    /// 2FA 第一步返回的临时令牌与脱敏邮箱
    var pending2FATempToken: String?
    var pending2FAEmail: String?

    var showServerSheet = false
    var draftServer = ServerConfig.newPlaceholder()

    var canLogin: Bool {
        guard let server = selectedServer, !server.baseURL.isEmpty else { return false }
        switch authMode {
        case .jwt:
            if pending2FAEmail != nil { return totp.count == 6 }
            return !email.isEmpty && !password.isEmpty
        case .adminKey: return !adminKey.isEmpty
        }
    }

    init() {
        selectedServerId = ServerStore.shared.activeServerId
        selectedServer = ServerStore.shared.activeServer
        if let server = selectedServer {
            authMode = server.authMode
            if server.authMode == .adminKey { adminKey = server.adminKey }
        }
    }

    func newServer() {
        draftServer = ServerConfig.newPlaceholder()
        showServerSheet = true
    }

    func editServer(_ server: ServerConfig) {
        draftServer = server
        showServerSheet = true
    }

    func applyServer(_ saved: ServerConfig) {
        ServerStore.shared.upsert(saved)
        servers = ServerStore.shared.servers
        if selectedServer?.id == saved.id || selectedServer == nil {
            selectedServer = saved
            selectedServerId = saved.id
            ServerStore.shared.setActive(saved)
        }
    }

    func selectServer(_ id: UUID?) {
        selectedServer = servers.first { $0.id == id }
        if let server = selectedServer {
            authMode = server.authMode
        }
    }

    func login(_ appState: AppState) async {
        guard var server = selectedServer else { return }
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            switch authMode {
            case .jwt:
                server.authMode = .jwt
                server.adminKey = ""
                ServerStore.shared.upsert(server)
                let outcome = try await APIClient.login(
                    server: server, email: email, password: password
                )
                if case let .needs2FA(tempToken) = outcome {
                    // 进入 2FA 第二步（脱敏邮箱由接口返回，此处显示占位）
                    pending2FATempToken = tempToken
                    if pending2FAEmail == nil {
                        pending2FAEmail = MaskedEmail.mask(email) ?? email
                    }
                    return
                }
            case .adminKey:
                server.authMode = .adminKey
                server.adminKey = adminKey
                ServerStore.shared.upsert(server)
                // 立即验证 Key 有效性
                let client = APIClient(server: server)
                let _: DashboardSnapshot = try await client.request("GET", "/admin/dashboard/stats")
            }
            appState.switchServer(server)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// 2FA 第二步
    func submit2FA(_ appState: AppState) async {
        guard let server = selectedServer,
              let tempToken = pending2FATempToken else { return }
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            try await APIClient.login2FA(server: server, tempToken: tempToken, totpCode: totp)
            appState.switchServer(server)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func cancel2FA() {
        pending2FATempToken = nil
        pending2FAEmail = nil
        totp = ""
    }
}

/// 邮箱脱敏（2FA 第二步前本地显示用）
enum MaskedEmail {
    static func mask(_ email: String) -> String? {
        guard let at = email.firstIndex(of: "@"), at != email.startIndex else { return nil }
        let name = String(email[email.startIndex..<at])
        let domain = String(email[at...])
        guard name.count > 2 else { return name + "***" + domain }
        return String(name.prefix(2)) + "***" + domain
    }
}
