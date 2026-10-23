import SwiftUI

/// Token 刷新记录(全局或单个账号)
struct RefreshLogsView: View {
    @Environment(APIClient.self) private var api
    var accountId: Int?

    @State private var logs: [RefreshLog] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error, logs.isEmpty {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
            }
            ForEach(logs) { log in
                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    Image(systemName: log.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(log.succeeded ? DS.Palette.success : DS.Palette.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        if accountId == nil, let email = log.accountEmail {
                            Text(email).font(.subheadline).bold().lineLimit(1).truncationMode(.middle)
                        }
                        Text(log.succeeded ? (log.message ?? "刷新成功") : (log.errorMessage ?? "刷新失败"))
                            .font(.subheadline)
                            .foregroundStyle(log.succeeded ? .primary : DS.Palette.danger)
                            .lineLimit(3)
                            .textSelection(.enabled)
                        Text([log.typeLabel, MailDate.full(log.createdAt)].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !loading, error == nil, logs.isEmpty {
                ContentUnavailableView("还没有刷新记录", systemImage: "clock")
            }
        }
        .overlay { if loading && logs.isEmpty { ProgressView() } }
        .navigationTitle("刷新记录")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let list = try await api.refreshLogs(accountId: accountId, limit: 100)
            withAnimation(DS.Motion.snappy) { logs = list }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

/// 转发记录(全局或单个账号)，全局时可以立即触发一次转发检查
struct ForwardingLogsView: View {
    @Environment(APIClient.self) private var api
    var accountId: Int?

    @State private var failedOnly = false
    @State private var logs: [ForwardingLog] = []
    @State private var loading = true
    @State private var error: String?
    @State private var triggering = false
    @State private var toast: String?
    @Namespace private var chips

    var body: some View {
        List {
            HStack(spacing: DS.Spacing.s) {
                FilterChip(title: "全部", selected: !failedOnly, namespace: chips) { select(false) }
                FilterChip(title: "仅失败", selected: failedOnly, namespace: chips) { select(true) }
            }
            .listRowSeparator(.hidden)

            if let error, logs.isEmpty {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
            }
            ForEach(logs) { log in
                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    Image(systemName: log.succeeded ? "paperplane.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(log.succeeded ? DS.Palette.success : DS.Palette.danger)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        if accountId == nil, let email = log.accountEmail {
                            Text(email).font(.subheadline).bold().lineLimit(1).truncationMode(.middle)
                        }
                        Text(channelLabel(log.channel) + (log.succeeded ? " 转发成功" : " 转发失败"))
                            .font(.subheadline)
                        if let err = log.errorMessage, !err.isEmpty {
                            Text(err).font(.caption).foregroundStyle(DS.Palette.danger).lineLimit(3)
                        }
                        Text(MailDate.full(log.createdAt)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !loading, error == nil, logs.isEmpty {
                ContentUnavailableView(failedOnly ? "没有失败记录" : "还没有转发记录", systemImage: "paperplane")
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay { if loading && logs.isEmpty { ProgressView() } }
        .navigationTitle("转发记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if accountId == nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("立即检查", systemImage: "arrow.triangle.2.circlepath") { trigger() }
                        .disabled(triggering)
                }
            }
        }
        .refreshable { await load() }
        .task(id: failedOnly) { await load() }
        .toast($toast)
    }

    private func channelLabel(_ channel: String?) -> String {
        switch channel {
        case "smtp": "邮件"
        case "telegram": "Telegram"
        default: channel ?? ""
        }
    }

    private func select(_ failed: Bool) {
        withAnimation(DS.Motion.snappy) { failedOnly = failed }
    }

    private func load() async {
        do {
            let list = try await api.forwardingLogs(accountId: accountId, failedOnly: failedOnly, limit: 100)
            withAnimation(DS.Motion.snappy) { logs = list }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func trigger() {
        triggering = true
        Task {
            do {
                let r = try await api.triggerForwardingCheck()
                toast = r.message ?? "已触发转发检查"
                try? await Task.sleep(for: .seconds(2))
                await load()
            } catch {
                toast = "触发失败：\(error.localizedDescription)"
            }
            triggering = false
        }
    }
}
