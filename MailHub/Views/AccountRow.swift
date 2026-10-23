import SwiftUI

/// 首页一行：头像 | 邮箱 + 时间 / 类型与标签 / 别名 / 备注，文字从 DS.Size.textInset 起排
struct AccountRow: View {
    let account: MailAccount
    var refreshing = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            Avatar(text: account.email)
                .saturation(account.isActive ? 1 : 0)
                .opacity(account.isActive ? 1 : 0.5)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(account.email)
                        .font(.subheadline)
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(account.isActive ? .primary : .secondary)
                    Spacer(minLength: DS.Spacing.xs)
                    status
                }
                HStack(spacing: DS.Spacing.xs) {
                    ProviderPill(provider: account.provider)
                    if account.forwardEnabled == true {
                        Text("转")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DS.Palette.success)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(DS.Palette.success.opacity(0.12), in: Capsule())
                            .accessibilityLabel("已开启转发")
                    }
                    if !account.isActive {
                        Text("已停用")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(DS.Palette.surface, in: Capsule())
                    }
                    ForEach(account.tags ?? []) { TagChip(tag: $0) }
                }
                .lineLimit(1)
                if let aliases = account.aliases, !aliases.isEmpty {
                    Text("别名：" + aliases.joined(separator: " / "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let remark = account.remark, !remark.isEmpty {
                    Text(remark)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .animation(DS.Motion.snappy, value: refreshing)
    }

    /// 右上角：刷新中转圈 / 刷新失败 / 上次刷新时间
    @ViewBuilder
    private var status: some View {
        if refreshing {
            Label("刷新中", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(DS.Palette.warning)
                .symbolEffect(.rotate, options: .repeat(.continuous))
                .transition(.opacity)
        } else if account.refreshFailed {
            Label("刷新失败", systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.danger)
                .transition(.opacity)
        } else if let time = RelativeTime.text(account.lastRefreshAt) {
            Text(time)
                .font(.caption)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }
}
