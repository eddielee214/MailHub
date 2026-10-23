import SwiftUI

struct SettingsView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss
    @Bindable private var privacy = Privacy.shared
    @State private var confirmLogout = false
    @State private var lockError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(get: { !privacy.loadRemoteImages }, set: { privacy.loadRemoteImages = !$0 })) {
                        row("阻止远程图片", "eye.slash.fill",
                            "邮件里的图片、样式、字体不自动从外网加载，发件人无法知道你是否打开了邮件")
                    }
                    NavigationLink {
                        TrustedSendersView()
                    } label: {
                        HStack {
                            row("信任的发件人", "person.crop.circle.badge.checkmark", nil)
                            Spacer()
                            Text("\(privacy.trustedSenders.count)").foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $privacy.confirmLinks) {
                        row("打开链接前确认", "link", "先显示真实网址，防止伪装成正规网站的钓鱼链接")
                    }
                } header: {
                    Text("邮件")
                }

                Section {
                    Toggle(isOn: Binding(get: { privacy.appLock }, set: setAppLock)) {
                        row("\(privacy.biometryName) 解锁", "faceid", "打开 App 或从后台切回来时需要验证")
                    }
                    Toggle(isOn: $privacy.hideInSwitcher) {
                        row("离开时隐藏内容", "rectangle.on.rectangle.slash", "多任务界面里看不到邮件")
                    }
                    Toggle(isOn: $privacy.clipboardExpires) {
                        row("剪贴板 1 分钟后清除", "doc.on.clipboard", "复制的验证码和邮箱到时自动清除，也不同步到其他设备")
                    }
                    if let lockError {
                        Text(lockError).font(.footnote).foregroundStyle(DS.Palette.danger)
                    }
                } header: {
                    Text("本机隐私")
                } footer: {
                    Text("这些设置只保存在这台手机上。")
                }

                Section("服务器") {
                    LabeledContent("地址", value: api.serverURL.absoluteString)
                    Button("退出登录", role: .destructive) { confirmLogout = true }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .confirmationDialog("退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    dismiss()
                    Task { await api.logout() }
                }
            }
        }
    }

    /// 设置项：单色小图标 + 标题 + 说明
    private func row(_ title: String, _ icon: String, _ detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 开 App 锁前先验证一次，确认这台手机能用 Face ID / 密码，免得把自己锁在外面
    private func setAppLock(_ on: Bool) {
        lockError = nil
        guard on else { privacy.appLock = false; return }
        Task {
            if await privacy.authenticate() {
                privacy.appLock = true
            } else {
                lockError = "验证没有通过，未开启"
            }
        }
    }
}

struct TrustedSendersView: View {
    @Bindable private var privacy = Privacy.shared

    var body: some View {
        List {
            if privacy.trustedSenders.isEmpty {
                ContentUnavailableView("没有信任的发件人", systemImage: "person.crop.circle.badge.checkmark",
                                       description: Text("在邮件里点\"始终显示此发件人的图片\"会加到这里"))
            }
            ForEach(privacy.trustedSenders, id: \.self) { sender in
                HStack(spacing: 12) {
                    Avatar(text: sender, size: 32)
                    Text(sender).lineLimit(1)
                }
            }
            .onDelete { privacy.trustedSenders.remove(atOffsets: $0) }
        }
        .navigationTitle("信任的发件人")
        .toolbar { if !privacy.trustedSenders.isEmpty { EditButton() } }
    }
}
