import SwiftUI

/// Gmail 式左侧抽屉：上面是分组树(网页左栏)，下面是标签多选。
/// 选中行的色块在行之间滑动；拖动/开关由外面(AccountListView)控制。
struct GroupDrawer: View {
    let groups: [(group: MailGroup, depth: Int)]
    let tags: [MailTag]
    let allCount: Int
    let server: String
    @Binding var groupId: Int?
    @Binding var tagIds: Set<Int>
    let onSelectGroup: (Int?) -> Void
    let onImport: () -> Void
    let onSettings: () -> Void
    let onShares: () -> Void
    let onRefreshCenter: () -> Void
    let onTempEmails: () -> Void
    let onForwarding: () -> Void
    let onOAuth: () -> Void
    let onManageTags: () -> Void
    /// nil = 新建分组
    let onEditGroup: (MailGroup?) -> Void
    let onRefreshGroup: (MailGroup) -> Void
    let onNewSubgroup: (MailGroup) -> Void
    /// 服务端"临时邮箱"分组里的邮箱数
    var tempCount = 0
    let onLogout: () -> Void

    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.m) {
                AppBadge(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MailHub").font(.title3).bold()
                    Text(server).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.m)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    row(title: "全部账号", icon: "tray.2", color: nil, count: allCount,
                        selected: groupId == nil, depth: 0) { onSelectGroup(nil) }

                    row(title: "临时邮箱", icon: "timer", color: nil, count: tempCount,
                        selected: false, depth: 0, action: onTempEmails)

                    sectionHeader("分组", action: "新建") { onEditGroup(nil) }
                    ForEach(groups, id: \.group.id) { item in
                        row(title: item.group.name, icon: nil, color: Color(hex: item.group.color) ?? .gray,
                            count: item.group.descendantAccountCount ?? item.group.accountCount ?? 0,
                            selected: groupId == item.group.id, depth: item.depth) { onSelectGroup(item.group.id) }
                            .contextMenu {
                                Button("编辑分组", systemImage: "pencil") { onEditGroup(item.group) }
                                // 最多三级：第三级下面不能再建
                                if item.depth < 2 {
                                    Button("新建子分组", systemImage: "folder.badge.plus") { onNewSubgroup(item.group) }
                                }
                                Button("刷新此分组 Token", systemImage: "arrow.triangle.2.circlepath") {
                                    onRefreshGroup(item.group)
                                }
                            }
                    }

                    sectionHeader("标签(任选)", action: "管理", perform: onManageTags)
                    ForEach(tags) { tag in tagRow(tag) }

                    Divider().padding(.vertical, DS.Spacing.s)
                    plainRow("导入账号", icon: "square.and.arrow.down", action: onImport)
                    plainRow("Token 刷新管理", icon: "key", action: onRefreshCenter)
                    plainRow("分享管理", icon: "link", action: onShares)
                    plainRow("转发记录", icon: "paperplane", action: onForwarding)
                    plainRow("获取 Refresh Token", icon: "key.viewfinder", action: onOAuth)
                    plainRow("设置与隐私", icon: "gearshape", action: onSettings)
                    plainRow("退出登录", icon: "rectangle.portrait.and.arrow.right", action: onLogout)
                        .foregroundStyle(DS.Palette.danger)
                }
                .padding(.trailing, DS.Spacing.m)
                .padding(.vertical, DS.Spacing.s)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }

    private func sectionHeader(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            sectionTitle(text)
            Spacer()
            Button(action, action: perform)
                .font(.footnote.weight(.semibold))
                .padding(.top, DS.Spacing.l).padding(.bottom, DS.Spacing.xs)
                .frame(minHeight: DS.Size.tapTarget)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.l).padding(.bottom, DS.Spacing.xs)
    }

    /// Gmail 抽屉的选中样式：右侧圆角的色块贴着左边，在行之间滑动
    private func row(title: String, icon: String?, color: Color?, count: Int, selected: Bool, depth: Int,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.l) {
                Group {
                    if let icon {
                        Image(systemName: icon)
                    } else {
                        Circle().fill((color ?? .gray)).frame(width: 10, height: 10)
                    }
                }
                .frame(width: 22)
                Text(title)
                    .fontWeight(selected ? .semibold : .regular)
                    .lineLimit(1)
                Spacer()
                Text("\(count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            .foregroundStyle(selected ? DS.Palette.accent : .primary)
            .padding(.leading, DS.Spacing.l + CGFloat(depth) * 18).padding(.trailing, DS.Spacing.l)
            .frame(height: DS.Size.tapTarget)
            .background {
                if selected {
                    UnevenRoundedRectangle(bottomTrailingRadius: 22, topTrailingRadius: 22)
                        .fill(DS.Palette.accentSoft)
                        .matchedGeometryEffect(id: "selected", in: selection)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tagRow(_ tag: MailTag) -> some View {
        let on = tagIds.contains(tag.id)
        let color = Color(hex: tag.color) ?? .gray
        return Button {
            withAnimation(DS.Motion.snappy) {
                if on { tagIds.remove(tag.id) } else { tagIds.insert(tag.id) }
            }
        } label: {
            HStack(spacing: DS.Spacing.l) {
                Image(systemName: "tag.fill")
                    .foregroundStyle(color)
                    .frame(width: 22)
                Text(tag.name).lineLimit(1)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? color : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, DS.Spacing.l)
            .frame(height: DS.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func plainRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(DrawerLabelStyle())
                .padding(.horizontal, DS.Spacing.l)
                .frame(height: DS.Size.tapTarget)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}

/// 抽屉里图标固定 22pt 宽，文字和上面的分组名对齐
private struct DrawerLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DS.Spacing.l) {
            configuration.icon.frame(width: 22)
            configuration.title
        }
    }
}
