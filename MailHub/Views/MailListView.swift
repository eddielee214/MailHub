import SwiftUI

struct MailListView: View {
    @Environment(APIClient.self) private var api
    let account: MailAccount

    @State private var folder: MailFolder = .inbox
    @State private var mails: [MailSummary] = []
    @State private var hasMore = false
    @State private var loading = false
    /// 已经显示着缓存/留存的列表，正在后台去邮箱取最新的
    @State private var syncing = false
    @State private var error: String?
    @State private var methodLabel: String?
    @State private var generation = 0
    @State private var toast: String?
    @State private var fabCollapsed = false
    @State private var copyCount = 0
    @State private var showCreateShare = false
    @State private var showShareHistory = false
    @State private var showEdit = false
    @State private var showCompose = false
    @Namespace private var folderSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.screen, bottom: DS.Spacing.s, trailing: DS.Spacing.screen))

            if let error, mails.isEmpty {
                ContentUnavailableView("收信失败", systemImage: "exclamationmark.triangle", description: Text(error))
                    .listRowSeparator(.hidden)
            }
            ForEach($mails, id: \.listKey) { $mail in
                ZStack {
                    NavigationLink {
                        MailDetailView(account: account.email, mail: mail, folder: folder,
                                   composeAccount: account.isOutlook ? account : nil) {
                            withAnimation(DS.Motion.snappy) { mail.isRead = true }
                        } onDelete: {
                            withAnimation(DS.Motion.snappy) { mails.removeAll { $0.listKey == mail.listKey } }
                        }
                    } label: { EmptyView() }
                    .opacity(0)
                    MailRow(mail: mail, showFolder: folder == .all) { code in copy(code, label: "验证码 \(code)") }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DS.Spacing.s, leading: DS.Spacing.screen, bottom: DS.Spacing.s, trailing: DS.Spacing.screen))
                .swipeActions(edge: .trailing) {
                    Button("删除", systemImage: "trash", role: .destructive) { delete(mail) }
                }
                .swipeActions(edge: .leading) {
                    if mail.isRead == false {
                        Button("已读", systemImage: "envelope.open") { markRead(mail) }
                            .tint(DS.Palette.accent)
                    }
                }
                .contextMenu {
                    if let code = mail.code {
                        Button("复制验证码 \(code)", systemImage: "number") { copy(code, label: "验证码") }
                    }
                    Button("复制主题", systemImage: "doc.on.doc") { copy(mail.subject ?? "", label: "主题") }
                    Button("复制发件人", systemImage: "person") { copy(MailAddress(mail.from).address, label: "发件人") }
                    if mail.isRead == false {
                        Button("标为已读", systemImage: "envelope.open") { markRead(mail) }
                    }
                    Button("删除", systemImage: "trash", role: .destructive) { delete(mail) }
                }
                .onAppear {
                    if mail.listKey == mails.last?.listKey, hasMore { Task { await load(reset: false) } }
                }
            }
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
            if !loading, error == nil, mails.isEmpty {
                ContentUnavailableView("没有邮件", systemImage: "tray", description: Text("\(folder.title)是空的"))
                    .listRowSeparator(.hidden)
            }
            Color.clear.frame(height: 72).listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle(account.email)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            FloatingButton(title: "复制邮箱", systemImage: "doc.on.doc", collapsed: fabCollapsed) {
                copy(account.email, label: "邮箱")
            }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { old, new in
            if new < 24 { fabCollapsed = false } else if new - old > 8 { fabCollapsed = true } else if old - new > 8 { fabCollapsed = false }
        }
        .sensoryFeedback(.success, trigger: copyCount)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("更多", systemImage: "ellipsis.circle") {
                    if account.isOutlook {
                        Button("写邮件", systemImage: "square.and.pencil") { showCompose = true }
                    }
                    Button("编辑账号", systemImage: "pencil") { showEdit = true }
                    Section {
                        Button("分享此邮箱", systemImage: "link.badge.plus") { showCreateShare = true }
                        Button("分享记录", systemImage: "clock.arrow.circlepath") { showShareHistory = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateShare) { CreateShareView(account: account) }
        .sheet(isPresented: $showShareHistory) { ShareManagementView(account: account) }
        .sheet(isPresented: $showEdit) { AccountEditView(accountId: account.id) }
        .sheet(isPresented: $showCompose) { ComposeView(account: account) }
        // 下拉刷新时保留现有列表，取回来再替换
        .refreshable { await load(reset: true, background: !mails.isEmpty) }
        .task(id: folder) { await open() }
        .onChange(of: mails) { store() }
        .toast($toast)
    }

    /// 文件夹按钮(网页的黑底选中态) + 读取方式标签(网页的 "Graph API")
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.s) {
                    ForEach(MailFolder.allCases) { f in
                        FilterChip(title: f.title, systemImage: f.icon, tint: f.tint, selected: folder == f,
                                   namespace: folderSpace) {
                            withAnimation(DS.Motion.adaptive(DS.Motion.snappy, reduceMotion: reduceMotion)) { folder = f }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text(folder.title)
                    .font(.title3)
                    .bold()
                    .contentTransition(.opacity)
                if !mails.isEmpty {
                    Text("\(mails.count)\(hasMore ? "+" : "")")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(mails.count)))
                }
                Spacer()
                if syncing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在同步")
                        .transition(.opacity)
                }
                if let methodLabel {
                    Text(methodLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(DS.Palette.surface, in: Capsule())
                }
            }
            .animation(DS.Motion.snappy, value: syncing)
        }
    }

    private var cacheKey: String { "\(account.email)|\(folder.rawValue)" }

    /// 打开文件夹：有这次看过的列表、或服务器留存了邮件，就先显示出来，再在后台去邮箱取最新的。
    /// 去微软/IMAP 取信要几秒，网页版也是这么做的
    private func open() async {
        if let cached = api.mailListCache[cacheKey] {
            show(cached.mails, hasMore: cached.hasMore, method: cached.method)
            await load(reset: true, background: true)
            return
        }
        // 换到没看过的文件夹：先清掉上一个文件夹的邮件，免得在它上面操作
        loading = true
        withAnimation(DS.Motion.snappy) { mails = [] }
        // 服务端设置里没开"本地保留邮件"时这里是空的，很快返回，接着照常取
        if let local = try? await api.emails(account: account.email, folder: folder, skip: 0, local: true),
           let list = local.emails, !list.isEmpty {
            guard !Task.isCancelled else { return }
            show(list, hasMore: local.hasMore ?? false, method: local.method)
            await load(reset: true, background: true)
        } else {
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
    }

    private func show(_ list: [MailSummary], hasMore: Bool, method: String?) {
        withAnimation(DS.Motion.snappy) { mails = list }
        self.hasMore = hasMore
        methodLabel = method
        error = nil
        loading = false
    }

    private func store() {
        guard !mails.isEmpty else { return }
        api.mailListCache[cacheKey] = MailListCacheEntry(mails: mails, hasMore: hasMore, method: methodLabel)
    }

    /// background：列表已经有内容，只在标题旁转个小圈，失败也保留现有列表
    private func load(reset: Bool, background: Bool = false) async {
        if !reset && loading { return }
        generation += 1
        let current = generation
        if background { syncing = true } else { loading = true }
        if reset && !background { error = nil }
        defer {
            if current == generation {
                loading = false
                syncing = false
            }
        }
        do {
            let r = try await api.emails(account: account.email, folder: folder, skip: reset ? 0 : mails.count)
            guard current == generation, !Task.isCancelled else { return }
            let incoming = r.emails ?? []
            if reset {
                // 换文件夹/下拉刷新：整页淡入替换，避免内容突然跳变
                withAnimation(DS.Motion.snappy) { mails = incoming }
            } else {
                let known = Set(mails.map(\.listKey))
                mails += incoming.filter { !known.contains($0.listKey) }
            }
            hasMore = r.hasMore ?? false
            methodLabel = r.method
            store()
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            if background {
                toast = "同步失败：\(error.localizedDescription)"
                return
            }
            if reset { mails = [] }
            hasMore = false
            self.error = error.localizedDescription
        }
    }

    private func markRead(_ mail: MailSummary) {
        Task {
            do {
                try await api.markRead(account: account.email, mails: [mail], folder: folder)
                if let i = mails.firstIndex(where: { $0.listKey == mail.listKey }) {
                    withAnimation(DS.Motion.snappy) { mails[i].isRead = true }
                }
            } catch {
                toast = "标记失败：\(error.localizedDescription)"
            }
        }
    }

    private func delete(_ mail: MailSummary) {
        Task {
            do {
                try await api.delete(account: account.email, mails: [mail], folder: folder)
                withAnimation(DS.Motion.snappy) { mails.removeAll { $0.listKey == mail.listKey } }
                toast = "已删除"
            } catch {
                toast = "删除失败：\(error.localizedDescription)"
            }
        }
    }

    private func copy(_ text: String, label: String) {
        Privacy.shared.copy(text)
        copyCount += 1
        toast = "已复制\(label)"
    }
}

extension MailFolder {
    var tint: Color {
        switch self {
        case .inbox: DS.Palette.accent
        case .junkemail: DS.Palette.warning
        case .deleteditems: Color(red: 0.40, green: 0.44, blue: 0.50)
        case .all: DS.Palette.accentDeep
        }
    }

    var icon: String {
        switch self {
        case .inbox: "tray"
        case .junkemail: "exclamationmark.octagon"
        case .deleteditems: "trash"
        case .all: "tray.2"
        }
    }
}

extension MailSummary {
    var code: String? { VerificationCode.find(in: [subject, bodyPreview]) }
}

/// Gmail 式邮件行：头像、发件人(未读加粗)、时间、主题、两行预览，下面是验证码/附件胶囊
struct MailRow: View {
    let mail: MailSummary
    let showFolder: Bool
    let onCopyCode: (String) -> Void

    private var unread: Bool { mail.isRead == false }

    var body: some View {
        let sender = MailAddress(mail.from)
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            SenderAvatar(sender)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(sender.display)
                        .font(.subheadline.weight(unread ? .bold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(MailDate.short(mail.date))
                        .font(.caption.weight(unread ? .bold : .regular))
                        .foregroundStyle(unread ? .primary : .secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mail.subject?.isEmpty == false ? mail.subject! : "(无主题)")
                        .font(.subheadline.weight(unread ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if unread {
                        Circle().fill(DS.Palette.accent).frame(width: 8, height: 8)
                            .accessibilityLabel("未读")
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                if let preview = mail.bodyPreview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                let code = mail.code
                if code != nil || mail.hasAttachments == true || showFolder {
                    HStack(spacing: DS.Spacing.s) {
                        if let code { CodeChip(code: code) { onCopyCode(code) } }
                        if mail.hasAttachments == true {
                            HStack(spacing: 3) {
                                Image(systemName: "paperclip")
                                Text("附件")
                            }
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .overlay(Capsule().stroke(DS.Palette.separator))
                        }
                        if showFolder, let folder = mail.folder, let f = MailFolder(rawValue: folder) {
                            Text(f.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(DS.Palette.surface, in: Capsule())
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
