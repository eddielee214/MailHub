import Foundation
import LocalAuthentication
import Observation
import UIKit
import UniformTypeIdentifiers

/// 隐私相关设置，存在本机 UserDefaults(不上传服务器)。
@Observable
final class Privacy {
    static let shared = Privacy()

    private let defaults = UserDefaults.standard

    /// 自动加载邮件里的远程图片/样式/字体。关掉时这些请求都被拦截，发件人看不到你打开了邮件
    var loadRemoteImages: Bool { didSet { defaults.set(loadRemoteImages, forKey: "privacy.loadRemoteImages") } }
    /// 始终加载远程图片的发件人地址(小写)
    var trustedSenders: [String] { didSet { defaults.set(trustedSenders, forKey: "privacy.trustedSenders") } }
    /// 点邮件里的链接时先显示真实地址
    var confirmLinks: Bool { didSet { defaults.set(confirmLinks, forKey: "privacy.confirmLinks") } }
    /// 打开 App 要 Face ID / 锁屏密码
    var appLock: Bool { didSet { defaults.set(appLock, forKey: "privacy.appLock") } }
    /// 离开 App 时遮住内容(多任务界面看不到邮件)
    var hideInSwitcher: Bool { didSet { defaults.set(hideInSwitcher, forKey: "privacy.hideInSwitcher") } }
    /// 复制的内容 1 分钟后从剪贴板清除，且不通过"通用剪贴板"同步到其他设备
    var clipboardExpires: Bool { didSet { defaults.set(clipboardExpires, forKey: "privacy.clipboardExpires") } }

    private init() {
        defaults.register(defaults: [
            "privacy.loadRemoteImages": false,
            "privacy.confirmLinks": true,
            "privacy.appLock": false,
            "privacy.hideInSwitcher": true,
            "privacy.clipboardExpires": true,
        ])
        loadRemoteImages = defaults.bool(forKey: "privacy.loadRemoteImages")
        trustedSenders = defaults.stringArray(forKey: "privacy.trustedSenders") ?? []
        confirmLinks = defaults.bool(forKey: "privacy.confirmLinks")
        appLock = defaults.bool(forKey: "privacy.appLock")
        hideInSwitcher = defaults.bool(forKey: "privacy.hideInSwitcher")
        clipboardExpires = defaults.bool(forKey: "privacy.clipboardExpires")
    }

    func isTrusted(_ sender: String) -> Bool {
        trustedSenders.contains(sender.lowercased())
    }

    func trust(_ sender: String) {
        let s = sender.lowercased()
        guard !s.isEmpty, !trustedSenders.contains(s) else { return }
        trustedSenders.append(s)
    }

    func copy(_ text: String) {
        let item = [UTType.plainText.identifier: text]
        if clipboardExpires {
            UIPasteboard.general.setItems([item], options: [
                .localOnly: true,
                .expirationDate: Date.now.addingTimeInterval(60),
            ])
        } else {
            UIPasteboard.general.setItems([item])
        }
    }

    /// 设备有没有 Face ID / Touch ID / 锁屏密码可用
    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "锁屏密码"
        }
    }

    func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "输入密码"
        // deviceOwnerAuthentication：生物识别失败可以退回锁屏密码
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁 MailHub")) ?? false
    }
}

/// 邮件 HTML 里会不会去外网拉东西(图片、样式、字体、追踪像素)
enum RemoteContent {
    static func detect(in html: String) -> Bool {
        let patterns = [
            #"<img[^>]+src\s*=\s*["']?\s*(https?:)?//"#,
            #"url\(\s*["']?\s*(https?:)?//"#,
            #"<link[^>]+href\s*=\s*["']?\s*(https?:)?//"#,
            #"background\s*=\s*["']?\s*(https?:)?//"#,
            #"@import"#,
        ]
        return patterns.contains { html.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }
}
