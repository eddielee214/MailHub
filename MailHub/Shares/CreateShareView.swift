import SwiftUI

/// 分享邮箱：选有效期和可看范围 → 生成链接(二维码/复制/发送)
struct CreateShareView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let account: MailAccount
    var onCreated: () -> Void = {}

    private enum Duration: Hashable, CaseIterable {
        case hour, day, week, month, forever, custom
        var title: String {
            switch self {
            case .hour: "1 小时"
            case .day: "24 小时"
            case .week: "7 天"
            case .month: "30 天"
            case .forever: "永不过期"
            case .custom: "自定义"
            }
        }
        var minutes: Int? {
            switch self {
            case .hour: 60
            case .day: 1440
            case .week: 10080
            case .month: 43200
            case .forever, .custom: nil
            }
        }
    }

    @State private var duration: Duration = .day
    @State private var customMinutes = 120
    @State private var limitCount = false
    @State private var maxCount = 5
    @State private var creating = false
    @State private var error: String?
    @State private var created: EmailShare?
    @Namespace private var chips

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    HStack(spacing: DS.Spacing.m) {
                        Avatar(text: account.email)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.email).font(.subheadline).bold().lineLimit(1).truncationMode(.middle)
                            Text("拿到链接的人不用登录，就能查看这个邮箱的邮件")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if let created, let url = api.shareLink(created) {
                        VStack(spacing: DS.Spacing.m) {
                            Label("分享链接已生成", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(DS.Palette.success)
                            Text("\(ShareText.expiry(created)) · \(ShareText.scope(created))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ShareLinkCard(url: url)
                        }
                        .frame(maxWidth: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    } else {
                        form
                            .transition(.opacity)
                    }
                }
                .padding(DS.Spacing.screen)
            }
            .navigationTitle("分享邮箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(created == nil ? "取消" : "完成") { dismiss() }
                }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                Text("有效期").font(.subheadline).bold()
                FlowChips(items: Duration.allCases, selected: duration, title: \.title, namespace: chips) { d in
                    withAnimation(DS.Motion.adaptive(DS.Motion.snappy, reduceMotion: reduceMotion)) { duration = d }
                }
                if duration == .custom {
                    Stepper(value: $customMinutes, in: 5...525_600, step: customMinutes < 60 ? 5 : 30) {
                        Text("\(customMinutes) 分钟")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(customMinutes)))
                    }
                    .padding(.top, DS.Spacing.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if duration == .forever {
                    Label("永久链接只能手动撤销，适合长期交给别人用的邮箱", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.warning)
                        .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                Toggle(isOn: $limitCount.animation(DS.Motion.snappy)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("只给看最新几封").font(.subheadline).bold()
                        Text("收件箱和垃圾箱合计，只显示当前最新的 N 封")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if limitCount {
                    Stepper(value: $maxCount, in: 1...50) {
                        Text("最新 \(maxCount) 封")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(maxCount)))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.danger)
            }

            Button(action: create) {
                ZStack {
                    Text("生成分享链接").bold().opacity(creating ? 0 : 1)
                    if creating { ProgressView().tint(.white) }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white)
                .background(DS.Palette.accent, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(creating)
        }
        .animation(DS.Motion.snappy, value: duration)
    }

    private func create() {
        creating = true
        error = nil
        Task {
            do {
                let share = try await api.createShare(
                    accountId: account.id,
                    durationMinutes: duration.minutes ?? customMinutes,
                    neverExpires: duration == .forever,
                    maxEmailCount: limitCount ? maxCount : nil)
                withAnimation(DS.Motion.panel) { created = share }
                onCreated()
            } catch {
                self.error = error.localizedDescription
            }
            creating = false
        }
    }
}

/// 一组等宽单选标签，三列对齐排布
struct FlowChips<Item: Hashable>: View {
    let items: [Item]
    let selected: Item
    let title: KeyPath<Item, String>
    var namespace: Namespace.ID?
    let onSelect: (Item) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.s), count: 3),
                  spacing: 0) {
            ForEach(items, id: \.self) { item in
                FilterChip(title: item[keyPath: title], selected: item == selected, namespace: namespace,
                           expands: true) {
                    onSelect(item)
                }
            }
        }
    }
}
