import SwiftUI

struct ImportAccountsView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss

    let groups: [MailGroup]
    /// 首页当前选中的分组；有就默认导入到这里，没有(看"全部")才用默认分组
    var initialGroupId: Int?
    var onImported: () -> Void

    @State private var provider = "outlook"
    @State private var format = "client_id_refresh_token"
    @State private var groupId = 1
    @State private var text = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var importing = false
    @State private var result: String?
    @State private var error: String?

    private static let providers: [(String, String)] = [
        ("outlook", "Outlook / Hotmail"), ("auto", "自动识别(IMAP)"), ("gmail", "Gmail"), ("qq", "QQ 邮箱"),
        ("163", "163 邮箱"), ("126", "126 邮箱"), ("yahoo", "Yahoo"), ("aliyun", "阿里邮箱"), ("custom", "自定义 IMAP"),
    ]

    private var formatHint: String {
        switch provider {
        case "outlook":
            format == "client_id_refresh_token"
                ? "每行：邮箱----密码----ClientID----RefreshToken"
                : "每行：邮箱----密码----RefreshToken----ClientID"
        case "custom": "每行：邮箱----IMAP密码----IMAP主机----IMAP端口(主机和端口也可以在上面统一填)"
        default: "每行：邮箱----IMAP密码(授权码)"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("邮箱类型", selection: $provider) {
                        ForEach(Self.providers, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    if provider == "outlook" {
                        Picker("字段顺序", selection: $format) {
                            Text("ClientID 在前").tag("client_id_refresh_token")
                            Text("RefreshToken 在前").tag("refresh_token_client_id")
                        }
                    }
                    if provider == "custom" {
                        TextField("IMAP 主机", text: $imapHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("IMAP 端口", text: $imapPort)
                            .keyboardType(.numberPad)
                    }
                    Picker("导入到分组", selection: $groupId) {
                        ForEach(groups) { Text($0.name).tag($0.id) }
                    }
                }
                Section {
                    TextEditor(text: $text)
                        .font(.caption.monospaced())
                        .frame(minHeight: 180)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("从剪贴板粘贴", systemImage: "doc.on.clipboard") {
                        if let s = UIPasteboard.general.string { text = s }
                    }
                } header: {
                    Text("账号")
                } footer: {
                    Text(formatHint)
                }
                if let result {
                    Section { Text(result).foregroundStyle(DS.Palette.success) }
                }
                if let error {
                    Section { Text(error).foregroundStyle(DS.Palette.danger) }
                }
            }
            .navigationTitle("导入账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if importing {
                        ProgressView()
                    } else {
                        Button("导入", action: submit)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
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

    private func submit() {
        importing = true
        result = nil
        error = nil
        Task {
            do {
                let r = try await api.importAccounts(text: text, provider: provider, format: format, groupId: groupId,
                                                     imapHost: imapHost, imapPort: Int(imapPort))
                result = r.message ?? "新增 \(r.addedCount ?? 0) 个，跳过 \(r.skippedCount ?? 0) 个，无效 \(r.invalidCount ?? 0) 行"
                if (r.addedCount ?? 0) > 0 {
                    text = ""
                    onImported()
                }
            } catch {
                self.error = error.localizedDescription
            }
            importing = false
        }
    }
}
