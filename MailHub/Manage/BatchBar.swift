import SwiftUI
import UIKit

/// 批量选择时底部的操作栏(对应网页的批量操作)
struct BatchBar: View {
    let count: Int
    let groups: [MailGroup]
    let tags: [MailTag]
    let onMove: (Int) -> Void
    let onTag: (Int, Bool) -> Void
    let onStatus: (Bool) -> Void
    let onForwarding: (Bool) -> Void
    let onRefresh: () -> Void
    let onCopy: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(groups.filter { !$0.isTempEmailGroup }) { g in
                    Button(String(repeating: "  ", count: max(0, (g.level ?? 1) - 1)) + g.name) { onMove(g.id) }
                }
            } label: { item("移动", "folder") }

            Menu {
                Section("添加标签") {
                    ForEach(tags) { t in Button(t.name, systemImage: "tag") { onTag(t.id, true) } }
                }
                Section("移除标签") {
                    ForEach(tags) { t in Button(t.name, systemImage: "tag.slash") { onTag(t.id, false) } }
                }
            } label: { item("标签", "tag") }
            .disabled(tags.isEmpty)

            Button(action: onRefresh) { item("刷新", "arrow.triangle.2.circlepath") }

            Menu {
                Button("复制邮箱", systemImage: "doc.on.doc", action: onCopy)
                Button("导出账号", systemImage: "square.and.arrow.up", action: onExport)
                Section("状态") {
                    Button("启用", systemImage: "checkmark.circle") { onStatus(true) }
                    Button("停用", systemImage: "pause.circle") { onStatus(false) }
                }
                Section("自动转发") {
                    Button("开启转发", systemImage: "paperplane") { onForwarding(true) }
                    Button("关闭转发", systemImage: "paperplane.circle") { onForwarding(false) }
                }
                Section {
                    Button("删除 \(count) 个账号", systemImage: "trash", role: .destructive, action: onDelete)
                }
            } label: { item("更多", "ellipsis.circle") }
        }
        .disabled(count == 0)
        .opacity(count == 0 ? 0.5 : 1)
        .padding(.horizontal, DS.Spacing.s)
        .padding(.top, DS.Spacing.s)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func item(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget)
        .contentShape(Rectangle())
    }
}

/// 系统分享面板(导出文件用；ShareLink 不能在异步拿到文件后再弹出)
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 可以被 .sheet(item:) 弹出的文件
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// 需要登录密码二次验证的操作(导出)
struct PasswordPrompt: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let onSubmit: (String) -> Void
    @State private var password = ""

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            SecureField("网页登录密码", text: $password)
            Button("确定") {
                onSubmit(password)
                password = ""
            }
            Button("取消", role: .cancel) { password = "" }
        } message: {
            Text(message)
        }
    }
}

extension View {
    func passwordPrompt(_ isPresented: Binding<Bool>, title: String, message: String,
                        onSubmit: @escaping (String) -> Void) -> some View {
        modifier(PasswordPrompt(isPresented: isPresented, title: title, message: message, onSubmit: onSubmit))
    }
}
