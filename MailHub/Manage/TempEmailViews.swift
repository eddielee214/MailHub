import SwiftUI

/// 临时邮箱(GPTMail / DuckMail / Cloudflare)：列表、生成、删除
struct TempEmailListView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var emails: [TempEmail] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showGenerate = false
    @State private var pendingDelete: TempEmail?
    @State private var toast: String?
    @State private var copyCount = 0

    var body: some View {
        NavigationStack {
            List {
                if let error, emails.isEmpty {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
                        .listRowSeparator(.hidden)
                }
                ForEach(emails) { temp in
                    NavigationLink {
                        TempMailListView(temp: temp)
                    } label: {
                        HStack(spacing: DS.Spacing.m) {
                            Avatar(text: temp.email)
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text(temp.email).font(.subheadline).bold().lineLimit(1).truncationMode(.middle)
                                HStack(spacing: DS.Spacing.xs) {
                                    Text(temp.providerLabel)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(DS.Palette.surface, in: Capsule())
                                    ForEach(temp.tags ?? []) { TagChip(tag: $0) }
                                    if let created = RelativeTime.text(temp.createdAt) {
                                        Text("\(created)创建").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .lineLimit(1)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: DS.Spacing.s, leading: DS.Spacing.screen,
                                              bottom: DS.Spacing.s, trailing: DS.Spacing.screen))
                    .swipeActions(edge: .leading) {
                        Button("复制", systemImage: "doc.on.doc") { copy(temp.email) }.tint(DS.Palette.accent)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("删除", systemImage: "trash", role: .destructive) { pendingDelete = temp }
                    }
                    .contextMenu {
                        Button("复制邮箱", systemImage: "doc.on.doc") { copy(temp.email) }
                        Button("删除", systemImage: "trash", role: .destructive) { pendingDelete = temp }
                    }
                }
                if !loading, error == nil, emails.isEmpty {
                    ContentUnavailableView("还没有临时邮箱", systemImage: "timer",
                                           description: Text("点右上角 + 生成一个"))
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .overlay { if loading && emails.isEmpty { ProgressView() } }
            .refreshable { await load() }
            .navigationTitle("临时邮箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("生成", systemImage: "plus") { showGenerate = true }
                }
            }
            .sheet(isPresented: $showGenerate) {
                TempGenerateView { email in
                    copy(email)
                    Task { await load() }
                }
            }
            .confirmationDialog("删除 \(pendingDelete?.email ?? "")？", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible, presenting: pendingDelete) { temp in
                Button("删除", role: .destructive) { delete(temp) }
            }
            .sensoryFeedback(.success, trigger: copyCount)
            .toast($toast)
            .task { await load() }
        }
    }

    private func load() async {
        do {
            let list = try await api.tempEmails()
            withAnimation(DS.Motion.snappy) { emails = list }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func copy(_ email: String) {
        Privacy.shared.copy(email)
        copyCount += 1
        toast = "已复制 \(email)"
    }

    private func delete(_ temp: TempEmail) {
        Task {
            do {
                try await api.deleteTempEmail(temp.email)
                withAnimation(DS.Motion.snappy) { emails.removeAll { $0.id == temp.id } }
                toast = "已删除"
            } catch {
                toast = "删除失败：\(error.localizedDescription)"
            }
        }
    }
}

/// 生成临时邮箱：按提供商要求填不同字段
struct TempGenerateView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss
    let onCreated: (String) -> Void

    @State private var provider = "gptmail"
    @State private var prefix = ""
    @State private var domain = ""
    @State private var username = ""
    @State private var password = ""
    @State private var channels: [CloudflareChannel] = []
    @State private var channelId: Int?
    @State private var domains: [String] = []
    @State private var loadingDomains = false
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("提供商", selection: $provider) {
                    Text("GPTMail").tag("gptmail")
                    Text("DuckMail").tag("duckmail")
                    Text("Cloudflare").tag("cloudflare")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                switch provider {
                case "duckmail":
                    Section {
                        domainPicker
                        TextField("用户名(至少 3 位)", text: $username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("密码(至少 6 位)", text: $password)
                    } footer: {
                        Text("DuckMail 需要用户名和密码来创建和读取邮箱。")
                    }
                case "cloudflare":
                    Section {
                        Picker("渠道", selection: $channelId) {
                            ForEach(channels) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                        domainPicker
                        TextField("用户名(留空随机)", text: $username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    } footer: {
                        if channels.isEmpty { Text("还没有 Cloudflare 渠道，请先在网页设置里添加。") }
                    }
                default:
                    Section {
                        TextField("前缀(留空随机)", text: $prefix)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("域名(留空随机)", text: $domain)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(DS.Palette.danger) }
                }
            }
            .navigationTitle("生成临时邮箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if creating { ProgressView() } else { Button("生成", action: create).bold() }
                }
            }
            .task(id: provider) { await loadOptions() }
            .task(id: channelId) { if provider == "cloudflare" { await loadDomains() } }
        }
    }

    @ViewBuilder
    private var domainPicker: some View {
        if loadingDomains {
            LabeledContent("域名") { ProgressView() }
        } else if domains.isEmpty {
            TextField("域名", text: $domain).textInputAutocapitalization(.never).autocorrectionDisabled()
        } else {
            Picker("域名", selection: $domain) {
                ForEach(domains, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private func loadOptions() async {
        error = nil
        domains = []
        domain = ""
        switch provider {
        case "duckmail":
            await loadDomains()
        case "cloudflare":
            channels = (try? await api.cloudflareChannels())?.filter { $0.enabled != false } ?? []
            if channelId == nil { channelId = channels.first?.id } else { await loadDomains() }
        default:
            break
        }
    }

    private func loadDomains() async {
        loadingDomains = true
        do {
            if provider == "duckmail" {
                domains = try await api.duckmailDomains()
            } else if let channelId {
                domains = try await api.cloudflareDomains(channelId: channelId)
            }
            domain = domains.first ?? ""
        } catch {
            self.error = error.localizedDescription
        }
        loadingDomains = false
    }

    private func create() {
        creating = true
        error = nil
        let trimmed = { (s: String) -> String? in
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        var input = APIClient.TempGenerate(provider: provider)
        switch provider {
        case "duckmail":
            input.domain = trimmed(domain)
            input.username = trimmed(username)
            input.password = password
        case "cloudflare":
            input.channel_id = channelId
            input.domain = trimmed(domain)
            input.username = trimmed(username)
        default:
            input.prefix = trimmed(prefix)
            input.domain = trimmed(domain)
        }
        Task {
            do {
                let email = try await api.generateTempEmail(input)
                onCreated(email)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            creating = false
        }
    }
}

/// 某个临时邮箱的邮件列表；下拉刷新会让服务端立即去拉新邮件
struct TempMailListView: View {
    @Environment(APIClient.self) private var api
    let temp: TempEmail

    @State private var mails: [TempMailSummary] = []
    @State private var loading = true
    @State private var error: String?
    @State private var toast: String?
    @State private var copyCount = 0

    var body: some View {
        List {
            if let error, mails.isEmpty {
                ContentUnavailableView("收信失败", systemImage: "exclamationmark.triangle", description: Text(error))
                    .listRowSeparator(.hidden)
            }
            ForEach(mails) { mail in
                ZStack {
                    NavigationLink { TempMailDetailView(temp: temp, mailId: mail.id) } label: { EmptyView() }
                        .opacity(0)
                    TempMailRow(mail: mail) { code in
                        Privacy.shared.copy(code)
                        copyCount += 1
                        toast = "已复制验证码 \(code)"
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DS.Spacing.s, leading: DS.Spacing.screen,
                                          bottom: DS.Spacing.s, trailing: DS.Spacing.screen))
            }
            if !loading, error == nil, mails.isEmpty {
                ContentUnavailableView("还没有邮件", systemImage: "tray", description: Text("下拉刷新收信"))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay { if loading && mails.isEmpty { ProgressView() } }
        .refreshable { await load(refresh: true) }
        .navigationTitle(temp.email)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            FloatingButton(title: "复制邮箱", systemImage: "doc.on.doc") {
                Privacy.shared.copy(temp.email)
                copyCount += 1
                toast = "已复制邮箱"
            }
        }
        .sensoryFeedback(.success, trigger: copyCount)
        .toast($toast)
        .task { await load(refresh: false) }
    }

    private func load(refresh: Bool) async {
        do {
            let list = try await api.tempMessages(temp.email, refresh: refresh)
            withAnimation(DS.Motion.snappy) { mails = list }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct TempMailRow: View {
    let mail: TempMailSummary
    let onCopyCode: (String) -> Void

    var body: some View {
        let sender = MailAddress(mail.from)
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            SenderAvatar(sender)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(sender.display).font(.subheadline).bold().lineLimit(1)
                    Spacer(minLength: DS.Spacing.xs)
                    if let date = mail.dateValue {
                        Text(MailDate.short(ISO8601DateFormatter().string(from: date)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(mail.subject?.isEmpty == false ? mail.subject! : "(无主题)")
                    .font(.subheadline)
                    .lineLimit(1)
                if let preview = mail.bodyPreview, !preview.isEmpty {
                    Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if let code = VerificationCode.find(in: [mail.subject, mail.bodyPreview]) {
                    CodeChip(code: code) { onCopyCode(code) }.padding(.top, DS.Spacing.xs)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// 临时邮件详情：复用普通邮件的正文渲染(远程图片拦截、链接确认、验证码)
struct TempMailDetailView: View {
    @Environment(APIClient.self) private var api
    let temp: TempEmail
    let mailId: String

    @State private var detail: MailDetail?
    @State private var code: String?
    @State private var error: String?
    @State private var bodyHeight: CGFloat = 1
    @State private var pendingLink: URL?
    @State private var showImages = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    Text(detail.subject ?? "(无主题)").font(.title2.weight(.semibold)).textSelection(.enabled)
                    HStack(spacing: DS.Spacing.m) {
                        SenderAvatar(MailAddress(detail.from))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MailAddress(detail.from).display).font(.subheadline).bold().lineLimit(1)
                            Text(MailDate.full(detail.date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let code {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("验证码").font(.caption).foregroundStyle(.secondary)
                                Text(code).font(.system(.title, design: .monospaced).bold()).textSelection(.enabled)
                            }
                            Spacer()
                            CodeChip(code: code) {
                                Privacy.shared.copy(code)
                                toast = "已复制验证码 \(code)"
                            }
                        }
                        .padding(DS.Spacing.l)
                        .background(DS.Palette.accentSoft, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                    }
                    if !showImages, !Privacy.shared.loadRemoteImages, detail.bodyType == "html",
                       RemoteContent.detect(in: detail.body ?? "") {
                        Button("显示远程图片", systemImage: "eye") { withAnimation { showImages = true } }
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, DS.Spacing.s)

                MailBodyView(html: MailHTML.wrap(detail, allowRemote: showImages || Privacy.shared.loadRemoteImages),
                             height: $bodyHeight) { url in
                    if Privacy.shared.confirmLinks { pendingLink = url } else { UIApplication.shared.open(url) }
                }
                .frame(height: bodyHeight)
                .padding(.top, DS.Spacing.s)
            } else if let error {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
                    .padding(.top, 40)
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("打开链接？", isPresented: Binding(
            get: { pendingLink != nil }, set: { if !$0 { pendingLink = nil } }
        ), titleVisibility: .visible, presenting: pendingLink) { url in
            Button("在浏览器中打开") { UIApplication.shared.open(url) }
        } message: { url in
            Text(url.absoluteString)
        }
        .toast($toast)
        .task {
            do {
                let d = try await api.tempMessage(temp.email, id: mailId).asMailDetail
                let text = d.bodyType == "html" ? VerificationCode.plainText(fromHTML: d.body ?? "") : d.body
                withAnimation(DS.Motion.panel) {
                    detail = d
                    code = VerificationCode.find(in: [d.subject, text])
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
