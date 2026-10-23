import SwiftUI

/// OAuth 助手(网页设置里的"获取 Token")：微软授权 → 拿到 Client ID + Refresh Token → 复制或直接导入成账号
struct OAuthHelperView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss

    let groups: [MailGroup]
    /// 首页当前分组；导入时默认放这里
    var initialGroupId: Int?
    var onImported: () -> Void = {}

    @State private var showFlow = false
    @State private var token: OAuthTokenResult?
    @State private var email = ""
    @State private var password = ""
    @State private var groupId = 1
    @State private var importing = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showFlow = true
                    } label: {
                        Label(token == nil ? "登录微软账号并授权" : "重新授权", systemImage: "person.badge.key")
                            .bold()
                    }
                } footer: {
                    Text("在页面里登录要导入的 Outlook / Hotmail 账号并同意授权。完成后会自动拿到 Refresh Token，不用复制地址栏。")
                }

                if let token {
                    Section("授权结果") {
                        tokenRow("Client ID", token.clientId ?? "")
                        tokenRow("Refresh Token", token.refreshToken ?? "")
                    }
                    Section {
                        TextField("邮箱地址", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("账号密码(可选)", text: $password)
                        Picker("导入到分组", selection: $groupId) {
                            ForEach(groups) { Text($0.name).tag($0.id) }
                        }
                        Button(action: importAccount) {
                            if importing { ProgressView() } else { Text("导入为新账号").bold() }
                        }
                        .disabled(importing || !email.contains("@"))
                    } header: {
                        Text("导入")
                    } footer: {
                        Text("填上刚才登录的邮箱即可导入；也可以只复制 Token 自己用。")
                    }
                    .transition(.opacity)
                }

                if let message {
                    Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.success) }
                }
                if let error {
                    Section { Text(error).foregroundStyle(DS.Palette.danger) }
                }
            }
            .animation(DS.Motion.snappy, value: token == nil)
            .navigationTitle("获取 Refresh Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .sheet(isPresented: $showFlow) {
                OAuthFlowView(title: "微软授权") { url in
                    let r = try await api.exchangeToken(redirectedURL: url)
                    guard r.refreshToken?.isEmpty == false else { throw APIError(message: "没有拿到 Refresh Token") }
                    token = r
                    message = nil
                    error = nil
                }
            }
            .onAppear {
                if let initialGroupId, groups.contains(where: { $0.id == initialGroupId }) {
                    groupId = initialGroupId
                } else if !groups.contains(where: { $0.id == groupId }), let first = groups.first {
                    groupId = first.id
                }
            }
        }
    }

    private func tokenRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text(title).font(.subheadline).bold()
                Spacer()
                Button("复制", systemImage: "doc.on.doc") { Privacy.shared.copy(value) }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: DS.Size.tapTarget, minHeight: DS.Size.tapTarget)
            }
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private func importAccount() {
        guard let token else { return }
        importing = true
        error = nil
        let line = [email.trimmingCharacters(in: .whitespaces), password, token.clientId ?? "", token.refreshToken ?? ""]
            .joined(separator: "----")
        Task {
            do {
                let r = try await api.importAccounts(text: line, provider: "outlook", format: "client_id_refresh_token",
                                                     groupId: groupId, imapHost: "", imapPort: nil)
                message = r.message ?? "已导入"
                onImported()
            } catch {
                self.error = error.localizedDescription
            }
            importing = false
        }
    }
}
