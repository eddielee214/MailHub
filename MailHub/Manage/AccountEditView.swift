import SwiftUI

/// 编辑账号：网页账号卡片"编辑"里的全部字段 + 刷新/转发记录、重新授权、删除
struct AccountEditView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss

    let accountId: Int
    /// 调用方已有的分组/标签列表；没传(从邮件页进来)就自己去取
    @State var groups: [MailGroup] = []
    @State var tags: [MailTag] = []
    var onChanged: () -> Void = {}

    @State private var detail: AccountDetail?
    @State private var loadError: String?

    // 可编辑字段(载入详情后填充)
    @State private var remark = ""
    @State private var groupId = 1
    @State private var active = true
    @State private var forwardEnabled = false
    @State private var aliases: [String] = []
    @State private var newAlias = ""
    @State private var tagIds: Set<Int> = []
    @State private var proxy = ""
    @State private var fallback1 = ""
    @State private var fallback2 = ""
    @State private var authorization = ""
    @State private var clientId = ""
    @State private var refreshToken = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    /// 只有改过才提交，nil = 保留原值
    @State private var newPassword: String?
    @State private var newImapPassword: String?

    @State private var revealed = false
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var showReauth = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    form(detail)
                } else if let loadError {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("编辑账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("保存", action: save).bold().disabled(detail == nil)
                    }
                }
            }
            .confirmationDialog("删除这个账号？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除账号", role: .destructive, action: delete)
            } message: {
                Text("账号、别名、分享链接和刷新记录都会删除，无法恢复。")
            }
            .sheet(isPresented: $showReauth) {
                OAuthFlowView(title: "重新授权") { url in
                    let r = try await api.reauthorize(accountId: accountId, redirectedURL: url)
                    toast = r.message ?? "重新授权成功"
                    onChanged()
                }
            }
            .toast($toast)
            .task { await load() }
        }
    }

    @ViewBuilder
    private func form(_ d: AccountDetail) -> some View {
        Form {
            Section {
                HStack(spacing: DS.Spacing.m) {
                    Avatar(text: d.email)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.email).bold().lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        ProviderPill(provider: d.provider)
                    }
                }
                TextField("备注", text: $remark, axis: .vertical)
                Picker("分组", selection: $groupId) {
                    ForEach(groups.filter { !$0.isTempEmailGroup }) { g in
                        Text(String(repeating: "  ", count: max(0, (g.level ?? 1) - 1)) + g.name).tag(g.id)
                    }
                }
                Toggle("启用", isOn: $active)
                Toggle("参与自动转发", isOn: $forwardEnabled)
            } footer: {
                Text("停用后，Token 刷新、自动转发和项目领取都会跳过这个账号。")
            }

            if !tags.isEmpty {
                Section("标签") {
                    FlowLayout(spacing: DS.Spacing.s) {
                        ForEach(tags) { tag in
                            let on = tagIds.contains(tag.id)
                            Button {
                                withAnimation(DS.Motion.snappy) {
                                    if on { tagIds.remove(tag.id) } else { tagIds.insert(tag.id) }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if on { Image(systemName: "checkmark").imageScale(.small) }
                                    Text(tag.name)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, DS.Spacing.m).frame(height: 32)
                                .foregroundStyle(on ? .white : .primary)
                                .background(on ? (Color(hex: tag.color) ?? .gray) : DS.Palette.surface, in: Capsule())
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }

            Section {
                ForEach(aliases, id: \.self) { alias in
                    Text(alias).font(.subheadline.monospaced())
                }
                .onDelete { aliases.remove(atOffsets: $0) }
                HStack {
                    TextField("添加别名邮箱", text: $newAlias)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addAlias)
                    Button("添加", action: addAlias)
                        .disabled(!newAlias.contains("@"))
                }
            } header: {
                Text("别名")
            } footer: {
                Text("主邮箱和别名都能用来查邮件、调对外 API。左滑删除。")
            }

            Section {
                if d.isOutlook {
                    Picker("读取通道", selection: $authorization) {
                        Text("自动(Graph 优先)").tag("")
                        Text("Graph API").tag("graph")
                        Text("IMAP").tag("imap")
                    }
                    secretField("Client ID", text: $clientId)
                    secretField("Refresh Token", text: $refreshToken)
                    passwordRow("账号密码", original: d.password, hasValue: d.hasPassword, value: $newPassword)
                    Button("重新授权(获取新的 Refresh Token)", systemImage: "key.viewfinder") { showReauth = true }
                } else {
                    if d.provider == "custom" {
                        TextField("IMAP 服务器", text: $imapHost)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("端口", text: $imapPort).keyboardType(.numberPad)
                    }
                    passwordRow("IMAP 密码/授权码", original: d.imapPassword, hasValue: d.hasImapPassword, value: $newImapPassword)
                }
                if !revealed {
                    Button("显示凭据", systemImage: "eye") {
                        Task { if await Privacy.shared.authenticate() { withAnimation { revealed = true } } }
                    }
                }
            } header: {
                Text("凭据")
            } footer: {
                Text("显示凭据需要先验证 \(Privacy.shared.biometryName)。")
            }

            Section {
                proxyField("主代理", text: $proxy)
                proxyField("回退代理 1", text: $fallback1)
                proxyField("回退代理 2", text: $fallback2)
            } header: {
                Text("账号代理")
            } footer: {
                Text("三项都留空就继承分组代理。支持 socks5h:// 和 http://，填 direct 表示直连，{mail} 会换成邮箱前缀。")
            }

            Section {
                if d.isOutlook {
                    NavigationLink("Token 刷新记录") { RefreshLogsView(accountId: accountId) }
                }
                NavigationLink("转发记录") { ForwardingLogsView(accountId: accountId) }
            }

            if let error {
                Section { Text(error).foregroundStyle(DS.Palette.danger) }
            }

            Section {
                Button("删除账号", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func secretField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            if revealed {
                TextField(title, text: text)
                    .font(.footnote.monospaced())
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                Text(text.wrappedValue.isEmpty ? "未设置" : "••••••" + text.wrappedValue.suffix(4))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 密码：没显示时只看到圆点；显示后可以直接改(改了才提交)
    private func passwordRow(_ title: String, original: String?, hasValue: Bool?, value: Binding<String?>) -> some View {
        LabeledContent(title) {
            if revealed {
                TextField(title, text: Binding(
                    get: { value.wrappedValue ?? original ?? "" },
                    set: { value.wrappedValue = $0 }
                ))
                .font(.footnote.monospaced())
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            } else {
                Text((original?.isEmpty == false || hasValue == true) ? "••••••••" : "未设置")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func proxyField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(.subheadline.monospaced())
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    private func addAlias() {
        let alias = newAlias.trimmingCharacters(in: .whitespaces).lowercased()
        guard alias.contains("@"), !aliases.contains(alias) else { return }
        withAnimation(DS.Motion.snappy) { aliases.append(alias) }
        newAlias = ""
    }

    private func load() async {
        if groups.isEmpty { groups = (try? await api.groups())?.filter { !$0.isTempEmailGroup } ?? [] }
        if tags.isEmpty { tags = (try? await api.tags()) ?? [] }
        do {
            let d = try await api.accountDetail(id: accountId)
            remark = d.remark ?? ""
            groupId = d.groupId ?? 1
            active = (d.status ?? "active") == "active"
            forwardEnabled = d.forwardEnabled ?? false
            aliases = d.aliases ?? []
            tagIds = Set((d.tags ?? []).map(\.id))
            proxy = d.proxyUrl ?? ""
            fallback1 = d.fallbackProxyUrl1 ?? ""
            fallback2 = d.fallbackProxyUrl2 ?? ""
            authorization = d.authorizationType ?? ""
            clientId = d.clientId ?? ""
            refreshToken = d.refreshToken ?? ""
            imapHost = d.imapHost ?? ""
            imapPort = String(d.imapPort ?? 993)
            withAnimation(DS.Motion.panel) { detail = d }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        guard let d = detail else { return }
        saving = true
        error = nil
        let update = APIClient.AccountUpdate(
            email: d.email,
            account_type: d.isOutlook ? "outlook" : "imap",
            provider: d.provider ?? (d.isOutlook ? "outlook" : "auto"),
            client_id: clientId,
            refresh_token: refreshToken,
            authorization_type: authorization,
            imap_host: imapHost,
            imap_port: Int(imapPort) ?? 993,
            imap_password: newImapPassword,
            password: newPassword,
            group_id: groupId,
            remark: remark,
            status: active ? "active" : "inactive",
            forward_enabled: forwardEnabled,
            proxy_url: proxy.trimmingCharacters(in: .whitespaces),
            fallback_proxy_url_1: fallback1.trimmingCharacters(in: .whitespaces),
            fallback_proxy_url_2: fallback2.trimmingCharacters(in: .whitespaces),
            aliases: aliases,
            tag_ids: Array(tagIds))
        Task {
            do {
                _ = try await api.updateAccount(id: accountId, update)
                onChanged()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }

    private func delete() {
        Task {
            do {
                try await api.deleteAccount(id: accountId)
                onChanged()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
