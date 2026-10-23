import QuickLook
import SwiftUI
import WebKit

struct MailDetailView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss

    let account: String
    let mail: MailSummary
    let folder: MailFolder
    /// Outlook 账号可以回复(Graph 发信)；IMAP 账号为 nil
    var composeAccount: MailAccount?
    var onRead: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var detail: MailDetail?
    @State private var error: String?
    @State private var code: String?
    @State private var showDetails = false
    @State private var bodyHeight: CGFloat = 1
    @State private var downloading: String?
    @State private var previewURL: URL?
    @State private var confirmDelete = false
    @State private var toast: String?
    @State private var showImagesOnce = false
    @State private var pendingLink: URL?
    @State private var codeCopied = false
    @State private var showReply = false
    @State private var downloadingAll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let privacy = Privacy.shared

    private var sender: MailAddress { MailAddress(detail?.from ?? mail.from) }

    private var allowRemote: Bool {
        privacy.loadRemoteImages || showImagesOnce || privacy.isTrusted(sender.address)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                subjectLine
                senderLine
                if showDetails {
                    detailsCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let code {
                    codeCard(code)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
                attachments
            }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.top, DS.Spacing.s)

            if let detail {
                if !allowRemote, detail.bodyType == "html", RemoteContent.detect(in: detail.body ?? "") {
                    remoteBlockedBanner
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
                MailBodyView(html: MailHTML.wrap(detail, allowRemote: allowRemote), height: $bodyHeight) { url in
                    if privacy.confirmLinks { pendingLink = url } else { UIApplication.shared.open(url) }
                }
                    .frame(height: bodyHeight)
                    .padding(.top, DS.Spacing.s)
                    .transition(.opacity)
            } else if let error {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
                    .padding(.top, 40)
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if composeAccount != nil {
                    Button("回复", systemImage: "arrowshape.turn.up.left") { showReply = true }
                }
                Button("删除", systemImage: "trash") { confirmDelete = true }
                Menu("更多", systemImage: "ellipsis") {
                    Button("复制主题", systemImage: "doc.on.doc") {
                        copy(detail?.subject ?? mail.subject ?? "", label: "主题")
                    }
                    Button("复制发件人地址", systemImage: "person") { copy(sender.address, label: "发件人") }
                }
            }
        }
        .confirmationDialog("永久删除这封邮件？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: delete)
        }
        .confirmationDialog("打开链接？", isPresented: Binding(
            get: { pendingLink != nil }, set: { if !$0 { pendingLink = nil } }
        ), titleVisibility: .visible, presenting: pendingLink) { url in
            Button("在浏览器中打开") { UIApplication.shared.open(url) }
            Button("复制链接") { copy(url.absoluteString, label: "链接") }
        } message: { url in
            Text("将打开 \(url.host() ?? url.scheme ?? "")\n\n\(url.absoluteString)")
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showReply) {
            if let composeAccount {
                ComposeView(account: composeAccount, replyTo: sender.address,
                            replySubject: detail?.subject ?? mail.subject ?? "")
            }
        }
        .toast($toast)
        .sensoryFeedback(.success, trigger: codeCopied) { _, new in new }
        .animation(DS.Motion.adaptive(DS.Motion.snappy, reduceMotion: reduceMotion), value: allowRemote)
        .task { await load() }
    }

    // MARK: 头部(Gmail 式)

    private var subjectLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(detail?.subject ?? mail.subject ?? "(无主题)")
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            Text(MailFolder(rawValue: mail.folder ?? folder.rawValue)?.title ?? folder.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 4))
                .fixedSize()
        }
    }

    private var senderLine: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(text: sender.display)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(sender.display)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(MailDate.short(detail?.date ?? mail.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    withAnimation(DS.Motion.adaptive(DS.Motion.snappy, reduceMotion: reduceMotion)) { showDetails.toggle() }
                } label: {
                    HStack(spacing: 2) {
                        Text("发给 " + recipientsSummary).lineLimit(1)
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                            .rotationEffect(.degrees(showDetails ? 180 : 0))
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showDetails ? "收起收件人详情" : "展开收件人详情")
            }
            Spacer(minLength: 0)
        }
    }

    private var recipientsSummary: String {
        let to = (detail?.to ?? mail.to ?? "").split(separator: ",").map { MailAddress(String($0)).display }
        guard let first = to.first else { return "(无)" }
        return to.count > 1 ? "\(first) 等 \(to.count) 人" : first
    }

    private var detailsCard: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            detailRow("发件人", detail?.from ?? mail.from)
            detailRow("收件人", detail?.to ?? mail.to)
            if let cc = detail?.cc, !cc.isEmpty { detailRow("抄送", cc) }
            detailRow("日期", MailDate.full(detail?.date ?? mail.date))
        }
        .font(.caption)
        .textSelection(.enabled)
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.chip + 2))
    }

    private func detailRow(_ label: String, _ value: String?) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Text(value ?? "")
        }
    }

    /// Gmail 式的"图片未显示"提示
    private var remoteBlockedBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("为保护隐私，已阻止远程图片", systemImage: "eye.slash")
                .font(.subheadline.weight(.semibold))
            Text("远程图片可能被用来追踪你是否打开了邮件、何时打开、IP 位置。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: DS.Spacing.s) {
                Button("显示图片") { showImagesOnce = true }
                    .buttonStyle(.bordered)
                    .tint(DS.Palette.warning)
                if !sender.address.isEmpty {
                    Button("始终显示此发件人的图片") { privacy.trust(sender.address) }
                        .buttonStyle(.borderless)
                        .lineLimit(1)
                }
            }
            .font(.caption.weight(.medium))
            .controlSize(.small)
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.warningSoft, in: RoundedRectangle(cornerRadius: DS.Radius.card))
        .padding(.horizontal, DS.Spacing.screen)
        .padding(.top, DS.Spacing.s)
    }

    private func codeCard(_ code: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("验证码").font(.caption).foregroundStyle(.secondary)
                Text(code)
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .textSelection(.enabled)
            }
            Spacer()
            // 这一屏唯一的实心主按钮；点了变绿色"已复制"
            Button {
                copy(code, label: "验证码 \(code)")
                codeCopied = true
            } label: {
                Label(codeCopied ? "已复制" : "复制", systemImage: codeCopied ? "checkmark" : "doc.on.doc")
                    .bold()
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Spacing.l)
                    .frame(height: DS.Size.tapTarget)
                    .background((codeCopied ? DS.Palette.success : DS.Palette.accent), in: Capsule())
            }
            .buttonStyle(.pressable)
            .animation(DS.Motion.snappy, value: codeCopied)
            .task(id: codeCopied) {
                guard codeCopied else { return }
                try? await Task.sleep(for: .seconds(2))
                codeCopied = false
            }
        }
        .padding(DS.Spacing.l)
        .background(DS.Palette.accentSoft, in: RoundedRectangle(cornerRadius: DS.Radius.card))
    }

    @ViewBuilder
    private var attachments: some View {
        let files = (detail?.attachments ?? []).filter { $0.isInline != true }
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(files.count) 个附件").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if files.count > 1 {
                        Button(action: downloadAll) {
                            if downloadingAll { ProgressView().controlSize(.small) } else { Text("全部下载(ZIP)") }
                        }
                        .font(.footnote.weight(.semibold))
                        .disabled(downloadingAll || downloading != nil)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(files) { file in
                            Button { open(file) } label: { AttachmentCard(file: file, loading: downloading == file.id) }
                                .buttonStyle(.pressable)
                                .disabled(downloading != nil)
                        }
                    }
                }
            }
        }
    }

    // MARK: 操作

    private func load() async {
        // 列表预览里有验证码就先显示，正文加载完再用正文的结果
        code = mail.code
        do {
            let d = try await api.emailDetail(account: account, mail: mail, folder: folder)
            let text = d.bodyType == "html" ? VerificationCode.plainText(fromHTML: d.body ?? "") : d.body
            withAnimation(DS.Motion.panel) {
                detail = d
                code = VerificationCode.find(in: [d.subject, text]) ?? code
            }
            if mail.isRead == false {
                try? await api.markRead(account: account, mails: [mail], folder: folder)
                onRead()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func open(_ file: MailAttachment) {
        downloading = file.id
        Task {
            do {
                previewURL = try await api.downloadAttachment(account: account, mail: mail, folder: folder, attachment: file)
            } catch {
                toast = "下载失败：\(error.localizedDescription)"
            }
            downloading = nil
        }
    }

    private func downloadAll() {
        downloadingAll = true
        Task {
            do {
                previewURL = try await api.downloadAllAttachments(account: account, mail: mail, folder: folder)
            } catch {
                toast = "下载失败：\(error.localizedDescription)"
            }
            downloadingAll = false
        }
    }

    private func delete() {
        Task {
            do {
                try await api.delete(account: account, mails: [mail], folder: folder)
                onDelete()
                dismiss()
            } catch {
                toast = "删除失败：\(error.localizedDescription)"
            }
        }
    }

    private func copy(_ text: String, label: String) {
        Privacy.shared.copy(text)
        toast = "已复制\(label)"
    }
}

struct AttachmentCard: View {
    let file: MailAttachment
    let loading: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.15)).frame(width: 36, height: 36)
                if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon).foregroundStyle(tint)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name ?? "附件").font(.caption.weight(.medium)).lineLimit(1)
                if let size = file.size {
                    Text(size.formatted(.byteCount(style: .file))).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(DS.Spacing.s + 2)
        .frame(width: 190, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: DS.Radius.chip + 2))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.chip + 2).stroke(DS.Palette.separator))
    }

    private var kind: String { (file.contentType ?? "").lowercased() }
    private var icon: String {
        if kind.hasPrefix("image/") { return "photo" }
        if kind.contains("pdf") { return "doc.richtext" }
        if kind.contains("zip") || kind.contains("compressed") { return "doc.zipper" }
        return "doc"
    }
    private var tint: Color {
        if kind.hasPrefix("image/") { return DS.Palette.success }
        if kind.contains("pdf") { return DS.Palette.danger }
        return DS.Palette.accent
    }
}

/// 邮件正文：不跑邮件里的脚本，点链接用系统浏览器打开。
/// 本身不滚动，高度随内容报给外面的 ScrollView，这样头部和正文一起滚(Gmail 那样)；
/// 比屏幕宽的邮件(常见 600px 固定宽度)整体缩放到屏宽。
struct MailBodyView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    /// 点了邮件里的链接(由外面决定直接打开还是先确认)
    var onLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .white
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        context.coordinator.observe(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onLink = onLink
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        web.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?
        var onLink: (URL) -> Void = { _ in }
        private var height: Binding<CGFloat>
        private var observation: NSKeyValueObservation?

        init(height: Binding<CGFloat>) { self.height = height }

        func observe(_ web: WKWebView) {
            // 图片晚到、缩放之后内容高度还会变，跟着更新
            observation = web.scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, change in
                guard let h = change.newValue?.height else { return }
                Task { @MainActor in self?.setHeight(h) }
            }
        }

        private func setHeight(_ h: CGFloat) {
            guard h > 1, abs(height.wrappedValue - h) > 1 else { return }
            height.wrappedValue = h
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // evaluateJavaScript 是 App 注入的脚本，不受 allowsContentJavaScript 限制
            webView.evaluateJavaScript("""
            (function () {
              var w = document.documentElement.scrollWidth, v = window.innerWidth;
              if (w > v + 2) { document.body.style.zoom = v / w; }
              return document.body.getBoundingClientRect().height * (parseFloat(document.body.style.zoom) || 1)
                + 24;
            })()
            """) { [weak self] result, _ in
                if let h = result as? Double { self?.setHeight(CGFloat(h)) }
            }
            // 有的邮件排版要等一下才稳定，再量一次
            Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(for: .milliseconds(400))
                if let h = webView?.scrollView.contentSize.height { self?.setHeight(h) }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.navigationType == .linkActivated, let url = action.request.url {
                onLink(url)
                return .cancel
            }
            // 只允许加载我们自己给的 HTML；邮件里的跳转、meta refresh 一律拦下
            return action.request.url?.absoluteString == "about:blank" ? .allow : .cancel
        }
    }
}
