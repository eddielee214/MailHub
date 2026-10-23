import SwiftUI

/// 分享管理：所有分享链接(或某一个邮箱的)，按状态筛选，可复制、发送、撤销、删除
struct ShareManagementView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 传了就只看这个邮箱的分享，并可以直接新建
    var account: MailAccount?

    @State private var shares: [EmailShare] = []
    @State private var filter: EmailShare.State? = .active
    @State private var loading = true
    @State private var error: String?
    @State private var detail: EmailShare?
    @State private var showCreate = false
    @State private var pendingDelete: EmailShare?
    @State private var toast: String?
    @Namespace private var chips

    private var visible: [EmailShare] {
        guard let filter else { return shares }
        return shares.filter { $0.state == filter }
    }

    var body: some View {
        NavigationStack {
            List {
                filterBar
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.screen, bottom: DS.Spacing.s, trailing: DS.Spacing.screen))

                if let error, shares.isEmpty {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
                        .listRowSeparator(.hidden)
                }
                ForEach(visible) { share in
                    Button { detail = share } label: { ShareRow(share: share, showEmail: account == nil) }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: DS.Spacing.s, leading: DS.Spacing.screen, bottom: DS.Spacing.s, trailing: DS.Spacing.screen))
                        .swipeActions(edge: .trailing) {
                            Button("删除", systemImage: "trash", role: .destructive) { pendingDelete = share }
                            if share.state == .active {
                                Button("撤销", systemImage: "nosign") { revoke(share) }
                                    .tint(DS.Palette.warning)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if share.state == .active, let url = api.shareLink(share) {
                                Button("复制", systemImage: "doc.on.doc") { copy(url) }
                                    .tint(DS.Palette.accent)
                            }
                        }
                        .contextMenu {
                            if share.state == .active, let url = api.shareLink(share) {
                                Button("复制链接", systemImage: "doc.on.doc") { copy(url) }
                                ShareLink("发送链接", item: url)
                                Button("撤销", systemImage: "nosign") { revoke(share) }
                            }
                            Button("删除记录", systemImage: "trash", role: .destructive) { pendingDelete = share }
                        }
                        .transition(.opacity)
                }
                if loading && shares.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                }
                if !loading, error == nil, visible.isEmpty {
                    ContentUnavailableView(
                        emptyTitle, systemImage: "link",
                        description: Text(account == nil ? "在账号上左滑或长按，选\"分享邮箱\"" : "点右上角 + 新建一个分享链接"))
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .refreshable { await load() }
            .navigationTitle(account == nil ? "分享管理" : "分享记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                if account != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("新建分享", systemImage: "plus") { showCreate = true }
                    }
                }
            }
            .sheet(item: $detail) { share in
                ShareDetailSheet(share: share) { updated in
                    replace(updated)
                } onDelete: {
                    withAnimation(DS.Motion.snappy) { shares.removeAll { $0.id == share.id } }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showCreate) {
                if let account {
                    CreateShareView(account: account) { Task { await load() } }
                }
            }
            .confirmationDialog("删除这条分享记录？", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible, presenting: pendingDelete) { share in
                Button("删除", role: .destructive) { delete(share) }
            } message: { share in
                Text(share.state == .active ? "链接会立即失效，记录也会一起删掉。" : "只删除记录。")
            }
            .toast($toast)
            .task { await load() }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .active?: "没有有效的分享"
        case .expired?: "没有过期的分享"
        case .revoked?: "没有撤销的分享"
        case nil: "还没有分享过邮箱"
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.s) {
                FilterChip(title: "全部", count: shares.count, selected: filter == nil, namespace: chips) { select(nil) }
                ForEach(EmailShare.State.allCases) { state in
                    FilterChip(title: state.title, count: shares.filter { $0.state == state }.count,
                               selected: filter == state, namespace: chips) { select(state) }
                }
            }
        }
    }

    private func select(_ state: EmailShare.State?) {
        withAnimation(DS.Motion.adaptive(DS.Motion.snappy, reduceMotion: reduceMotion)) { filter = state }
    }

    private func load() async {
        loading = true
        do {
            let list = try await api.shares(accountId: account?.id)
            withAnimation(DS.Motion.snappy) { shares = list }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func replace(_ share: EmailShare) {
        withAnimation(DS.Motion.snappy) {
            if let i = shares.firstIndex(where: { $0.id == share.id }) { shares[i] = share }
        }
    }

    private func revoke(_ share: EmailShare) {
        Task {
            do {
                replace(try await api.revokeShare(id: share.id))
                toast = "已撤销，链接立即失效"
            } catch {
                toast = "撤销失败：\(error.localizedDescription)"
            }
        }
    }

    private func delete(_ share: EmailShare) {
        Task {
            do {
                try await api.deleteShare(id: share.id)
                withAnimation(DS.Motion.snappy) { shares.removeAll { $0.id == share.id } }
                toast = "已删除"
            } catch {
                toast = "删除失败：\(error.localizedDescription)"
            }
        }
    }

    private func copy(_ url: URL) {
        Privacy.shared.copy(url.absoluteString)
        toast = "已复制分享链接"
    }
}

struct ShareRow: View {
    let share: EmailShare
    var showEmail = true

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: DS.Size.avatar, height: DS.Size.avatar)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(showEmail ? (share.email ?? "") : "分享 #\(share.id)")
                        .font(.subheadline)
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: DS.Spacing.xs)
                    Text(ShareText.expiry(share))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tint)
                }
                Text("\(ShareText.scope(share)) · \(ShareText.access(share))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let created = RelativeTime.text(share.createdAt) {
                    Text("\(created)创建")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .opacity(share.state == .active ? 1 : 0.7)
        .contentShape(Rectangle())
    }

    private var icon: String {
        switch share.state {
        case .active: "link"
        case .expired: "clock"
        case .revoked: "nosign"
        }
    }

    private var tint: Color {
        switch share.state {
        case .active: DS.Palette.success
        case .expired: .secondary
        case .revoked: DS.Palette.warning
        }
    }
}

/// 点开一条分享：二维码 + 链接 + 撤销/删除
struct ShareDetailSheet: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State var share: EmailShare
    let onUpdate: (EmailShare) -> Void
    let onDelete: () -> Void
    @State private var working = false
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.xl) {
                    VStack(spacing: DS.Spacing.xs) {
                        Text(share.email ?? "").font(.headline).lineLimit(1).truncationMode(.middle)
                        Text("\(ShareText.expiry(share)) · \(ShareText.scope(share)) · \(ShareText.access(share))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)
                    }
                    if share.state == .active, let url = api.shareLink(share) {
                        ShareLinkCard(url: url)
                            .transition(.opacity)
                    } else {
                        Label(share.state == .revoked ? "这个链接已经撤销，打开会提示无效" : "这个链接已经过期",
                              systemImage: share.state == .revoked ? "nosign" : "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(DS.Spacing.l)
                            .frame(maxWidth: .infinity)
                            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(DS.Palette.danger)
                    }
                    // 次要操作用文字按钮，实心主按钮只留给"复制链接"
                    HStack(spacing: DS.Spacing.xl) {
                        if share.state == .active {
                            Button("撤销链接", systemImage: "nosign", action: revoke)
                                .foregroundStyle(DS.Palette.warning)
                        }
                        Button("删除记录", systemImage: "trash", role: .destructive) { confirmDelete = true }
                            .foregroundStyle(DS.Palette.danger)
                    }
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minHeight: DS.Size.tapTarget)
                    .disabled(working)
                }
                .padding(DS.Spacing.screen)
                .animation(DS.Motion.panel, value: share.state)
            }
            .navigationTitle("分享链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .confirmationDialog("删除这条分享记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive, action: delete)
            }
            .sensoryFeedback(.warning, trigger: share.state)
        }
    }

    private func revoke() {
        working = true
        Task {
            do {
                let updated = try await api.revokeShare(id: share.id)
                share = updated
                onUpdate(updated)
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }

    private func delete() {
        working = true
        Task {
            do {
                try await api.deleteShare(id: share.id)
                onDelete()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
