import SwiftUI

/// 服务器新建 / 编辑
struct ServerEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var server: ServerConfig

    let onSave: (ServerConfig) -> Void

    init(server: ServerConfig, onSave: @escaping (ServerConfig) -> Void) {
        _server = State(initialValue: server)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（如：生产环境）", text: $server.name)
                    TextField("地址（https://api.example.com）", text: $server.baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("服务器")
                } footer: {
                    Text("填 sub2api 部署的外部地址即可，无需带 /api/v1 后缀。")
                }
            }
            .navigationTitle(server.name.isEmpty ? "添加服务器" : "编辑服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(server)
                        dismiss()
                    }
                    .disabled(server.baseURL.isEmpty)
                }
            }
        }
    }
}
