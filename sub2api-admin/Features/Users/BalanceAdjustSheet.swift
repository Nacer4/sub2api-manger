import SwiftUI

/// 余额调整（POST /admin/users/:id/balance）
struct BalanceAdjustSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var operation = "add"
    @State private var amountText = ""
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showError = false

    let user: User
    let onDone: (Double) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("当前余额") {
                    Text(Fmt.usd(user.balance))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.orange)
                }

                Section("调整") {
                    Picker("操作", selection: $operation) {
                        Text("增加").tag("add")
                        Text("扣减").tag("subtract")
                        Text("设为").tag("set")
                    }
                    TextField("金额（USD）", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    TextField("备注（可选）", text: $note)
                } header: {
                    Text("备注")
                } footer: {
                    Text("操作会记录到用户的余额变动历史，并计入审计日志。")
                }
            }
            .navigationTitle("调整余额")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") {
                        Task { await submit() }
                    }
                    .disabled(amountText.isEmpty || isSubmitting)
                }
            }
            .alert("提交失败", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func submit() async {
        guard let client = AppStateHolder.shared.client else { return }
        // 金额非法时给出提示而非静默失败
        guard let amount = Double(amountText) else {
            errorMessage = "金额格式不正确，请输入数字（如 10 或 10.5）"
            showError = true
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let delta: Double
        switch operation {
        case "add": delta = amount
        case "subtract": delta = -amount
        default: delta = 0
        }

        let body = BalanceOperation(
            operation: operation,
            amount: amount,
            note: note.isEmpty ? nil : note,
            idempotencyKey: UUID().uuidString
        )
        do {
            let _: EmptyData = try await client.request(
                "POST", "/admin/users/\(user.id)/balance", body: body
            )
            onDone(delta)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
