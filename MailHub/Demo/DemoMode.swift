#if DEBUG
import Foundation

/// 截图自查用的演示模式：只在 Debug 构建里存在，且只有带启动参数时才开启，
///   xcrun simctl launch <设备> <Bundle ID> -MailHubDemo YES [-MailHubDemoScreen mails|detail|drawer|login|settings|lock]
/// 开启后所有请求由 DemoURLProtocol 返回假数据，不连服务器。
enum DemoMode {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "MailHubDemo") }
    static var screen: String? { enabled ? UserDefaults.standard.string(forKey: "MailHubDemoScreen") : nil }
}

nonisolated final class DemoURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url?.path ?? ""
        let folder = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "folder" }?.value ?? "inbox"
        // 刷新进度是 SSE：一次把几条事件都吐出来
        if path == "/api/accounts/refresh-all" {
            let events: [[String: Any]] = [
                ["type": "start", "total": 98],
                ["type": "account_result", "current": 61, "total": 98, "email": "alice.chen@example.com",
                 "status": "success", "message": "刷新成功，Token 已更新", "success_count": 58, "failed_count": 3],
                ["type": "account_result", "current": 62, "total": 98, "email": "erin.zhao@example.com",
                 "status": "failed", "error_message": "AADSTS70000: invalid_grant", "success_count": 58, "failed_count": 4],
                ["type": "progress", "current": 63, "total": 98, "email": "carol.wu@example.com",
                 "success_count": 58, "failed_count": 4],
            ]
            let body = events.map { "data: " + String(decoding: try! JSONSerialization.data(withJSONObject: $0), as: UTF8.self) + "\n\n" }.joined()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            // 不结束连接，模拟"进行中"
            return
        }
        let json: Any
        switch path {
        case "/login": json = ["success": true]
        case "/api/csrf-token": json = ["csrf_token": "demo"]
        case "/api/groups": json = ["success": true, "groups": Self.groups]
        case "/api/tags": json = ["success": true, "tags": Self.tags]
        case "/api/accounts/refresh-status-list":
            json = ["success": true, "items": Self.accounts.filter { ($0["provider"] as? String) == "outlook" }, "total": 4,
                    "stats": ["total": 98, "success_count": 91, "failed_count": 3, "never_count": 4, "last_refresh_time": Self.ago(7200)]]
        case _ where path.hasPrefix("/api/accounts/") && Int(path.split(separator: "/").last ?? "") != nil:
            json = ["success": true, "account": Self.accounts[0].merging([
                "client_id": "00000000-0000-0000-0000-000000000000", "refresh_token": "demo-refresh-token",
                "password": "Passw0rd!", "has_password": true, "remark": "主力号", "group_id": 1,
                "proxy_url": "", "authorization_type": "graph", "forward_enabled": true,
                "aliases": ["alice.chen+1@example.com", "alice.c@example.com"]]) { _, new in new }]
        case "/api/temp-emails":
            json = ["success": true, "emails": [
                ["id": 1, "email": "k8x2qv@gpt.example.com", "provider": "gptmail", "created_at": Self.ago(1800)],
                ["id": 2, "email": "demo123@duck.example.com", "provider": "duckmail", "created_at": Self.ago(86400)],
                ["id": 3, "email": "sales@mail.example.com", "provider": "cloudflare", "cloudflare_channel_name": "主渠道",
                 "created_at": Self.ago(3 * 86400), "tags": [["id": 2, "name": "待验证", "color": "#ef6c00"]]],
            ]]
        case _ where path.hasPrefix("/api/temp-emails/") && path.hasSuffix("/messages"):
            json = ["success": true, "emails": [
                ["id": 101, "from": "Discord <noreply@discord.com>", "subject": "Verify Email Address for Discord",
                 "body_preview": "Your Discord verification code is 482913. It expires in 10 minutes.",
                 "timestamp": Int(Date.now.timeIntervalSince1970) - 120],
                ["id": 102, "from": "Notion Team <team@makenotion.com>", "subject": "Your Notion login code",
                 "body_preview": "Here is your login code: 735204", "timestamp": Int(Date.now.timeIntervalSince1970) - 3600],
            ]]
        case "/api/accounts/refresh-stats":
            json = ["success": true, "stats": ["total": 98, "success_count": 91, "failed_count": 3, "never_count": 4,
                                               "last_refresh_time": Self.ago(2 * 3600)]]
        case "/api/accounts", "/api/accounts/search":
            json = ["success": true, "accounts": Self.accounts, "total": 128, "has_more": false]
        case "/api/email-shares" where request.httpMethod == "POST":
            json = ["success": true, "share": Self.share(9, "alice.chen@example.com", expires: -86400, count: 5)]
        case "/api/email-shares":
            json = ["success": true, "shares": [
                Self.share(1, "alice.chen@example.com", expires: -3 * 3600, count: 5, accessed: 600),
                Self.share(2, "bob.lee@example.com", expires: nil, count: nil, accessed: 2 * 86400),
                Self.share(3, "carol.wu@example.com", expires: -6 * 86400, count: 1),
                Self.share(4, "dave.lin@example.com", expires: 3600, count: nil, accessed: 5 * 86400),
                Self.share(5, "erin.zhao@example.com", expires: -86400, count: 10, revoked: true),
            ]]
        case _ where path.hasPrefix("/api/email-shares/") && path.hasSuffix("/cancel"):
            json = ["success": true, "share": Self.share(1, "alice.chen@example.com", expires: -3600, count: 5, revoked: true)]
        case _ where path.hasPrefix("/api/emails/"):
            let list = folder == "inbox" ? Self.emails : Array(Self.emails.suffix(2))
            json = ["success": true, "emails": list, "has_more": folder == "inbox", "method": "Graph API"]
        case _ where path.hasPrefix("/api/email/"):
            json = ["success": true, "email": Self.detail]
        default: json = ["success": true]
        }
        let data = try! JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func ago(_ seconds: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date.now.addingTimeInterval(-seconds))
    }

    /// expires: 距离过期的秒数取负(负数=还没过期，正数=已过期)，nil=永久
    static func share(_ id: Int, _ email: String, expires: Double?, count: Int?, accessed: Double? = nil,
                      revoked: Bool = false) -> [String: Any] {
        let expired = (expires ?? -1) > 0
        var s: [String: Any] = [
            "id": id, "account_id": 1, "email": email, "never_expires": expires == nil,
            "status": revoked ? "revoked" : (expired ? "expired" : "active"),
            "created_at": ago(2 * 86400), "share_url": "http://127.0.0.1:5000/share/email/demo-token-\(id)",
        ]
        if let expires { s["expires_at"] = ago(expires) }
        if let count { s["max_email_count"] = count }
        if let accessed { s["last_accessed_at"] = ago(accessed) }
        if revoked { s["revoked_at"] = ago(3600) }
        return s
    }

    private static func iso(_ seconds: Double) -> String {
        ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-seconds))
    }

    nonisolated(unsafe) static let groups: [[String: Any]] = [
        ["id": 99, "name": "临时邮箱", "color": "#00bcd4", "level": 1, "account_count": 7],
        ["id": 1, "name": "默认分组", "color": "#666666", "level": 1, "account_count": 12, "descendant_account_count": 12],
        ["id": 13, "name": "待改密码", "color": "#f57c00", "level": 1, "account_count": 80, "descendant_account_count": 101],
        ["id": 14, "name": "已出售", "color": "#43a047", "parent_id": 13, "level": 2, "account_count": 21, "descendant_account_count": 21],
        ["id": 15, "name": "注册用", "color": "#1e88e5", "level": 1, "account_count": 15, "descendant_account_count": 15],
    ]

    nonisolated(unsafe) static let tags: [[String: Any]] = [
        ["id": 1, "name": "已注册", "color": "#2e7d32"],
        ["id": 2, "name": "待验证", "color": "#ef6c00"],
        ["id": 3, "name": "主力", "color": "#6a1b9a"],
    ]

    nonisolated(unsafe) static let accounts: [[String: Any]] = [
        ["id": 1, "email": "alice.chen@example.com", "provider": "outlook", "account_type": "outlook",
         "aliases": ["alice.chen+1@example.com"], "group_color": "#666666", "status": "active",
         "last_refresh_at": ago(60), "last_refresh_status": "success", "tags": [["id": 3, "name": "主力", "color": "#6a1b9a"]]],
        ["id": 2, "email": "bob.lee@example.com", "provider": "outlook", "account_type": "outlook",
         "forward_enabled": true, "aliases": ["bob.lee@example.com"], "group_color": "#666666",
         "status": "active", "last_refresh_at": ago(7 * 3600), "last_refresh_status": "success"],
        ["id": 3, "email": "carol.wu@example.com", "provider": "outlook", "account_type": "outlook",
         "group_color": "#666666", "status": "active", "last_refresh_at": ago(7 * 3600), "last_refresh_status": "success",
         "tags": [["id": 1, "name": "已注册", "color": "#2e7d32"], ["id": 2, "name": "待验证", "color": "#ef6c00"]]],
        ["id": 4, "email": "dave.lin@example.com", "provider": "126", "account_type": "imap",
         "group_color": "#666666", "status": "active", "last_refresh_at": ago(7 * 3600), "last_refresh_status": "success"],
        ["id": 5, "email": "erin.zhao@example.com", "provider": "outlook", "account_type": "outlook",
         "remark": "111", "group_color": "#f57c00", "status": "active", "last_refresh_at": ago(8 * 3600),
         "last_refresh_status": "failed", "last_refresh_error": "AADSTS70000: invalid_grant"],
        ["id": 6, "email": "frank.he@example.com", "provider": "gmail", "account_type": "imap",
         "remark": "Google 测试号", "group_color": "#1e88e5", "status": "active", "last_refresh_at": ago(2 * 86400)],
        ["id": 7, "email": "grace@example.com", "provider": "qq", "account_type": "imap",
         "group_color": "#1e88e5", "status": "inactive", "last_refresh_at": ago(5 * 86400)],
    ]

    nonisolated(unsafe) static let emails: [[String: Any]] = [
        ["id": "m1", "subject": "Microsoft 帐户安全代码", "from": "Microsoft 帐户团队 <account-security-noreply@accountprotection.microsoft.com>",
         "to": "alice.chen@example.com", "date": iso(300), "is_read": false, "has_attachments": false,
         "body_preview": "请将以下安全代码用于 Microsoft 帐户 ni*****@example.com。安全代码: 384920 如果你无法识别该帐户，请单击此处删除你的电子邮件。",
         "folder": "inbox", "id_mode": "graph"],
        ["id": "m2", "subject": "Your ChatGPT code is 527301", "from": "OpenAI <noreply@tm.openai.com>",
         "to": "alice.chen@example.com", "date": iso(3600), "is_read": false, "has_attachments": false,
         "body_preview": "Enter this temporary verification code to continue: 527301. If you didn't try to sign in, you can safely ignore this email.",
         "folder": "inbox", "id_mode": "graph"],
        ["id": "m3", "subject": "[GitHub] Please verify your device", "from": "GitHub <noreply@github.com>",
         "to": "alice.chen@example.com", "date": iso(26 * 3600), "is_read": true, "has_attachments": false,
         "body_preview": "Hey alice! A sign in attempt requires further verification because we did not recognize your device.",
         "folder": "inbox", "id_mode": "graph"],
        ["id": "m4", "subject": "您的 10 月账单已出", "from": "招商银行信用卡 <ccsvc@message.cmbchina.com>",
         "to": "alice.chen@example.com", "date": iso(4 * 86400), "is_read": true, "has_attachments": true,
         "body_preview": "尊敬的客户：您本期账单金额为 ¥3,268.40，到期还款日 11 月 8 日。详情请查看附件电子账单。",
         "folder": "inbox", "id_mode": "graph"],
        ["id": "m5", "subject": "Welcome to Outlook.com", "from": "Outlook Team <no-reply@microsoft.com>",
         "to": "alice.chen@example.com", "date": iso(40 * 86400), "is_read": true, "has_attachments": false,
         "body_preview": "Get the most out of your new account. Here are a few tips to help you get started.",
         "folder": "inbox", "id_mode": "graph"],
    ]

    nonisolated(unsafe) static let detail: [String: Any] = [
        "id": "m1", "subject": "Microsoft 帐户安全代码",
        "from": "Microsoft 帐户团队 <account-security-noreply@accountprotection.microsoft.com>",
        "to": "alice.chen@example.com", "cc": "", "date": iso(300), "body_type": "html",
        "body": """
        <table width="640" cellpadding="0" cellspacing="0" style="font-family:Segoe UI,Arial;border:1px solid #ddd">
        <tr><td style="background:#2672ec;color:#fff;padding:24px;font-size:28px">
        <img src="https://img-prod-cms-rt-microsoft-com.akamaized.net/cms/api/am/imageFileData/RE1Mu3b" width="108" height="23"> Microsoft 帐户</td></tr>
        <tr><td style="padding:24px;font-size:15px;color:#333">
        <p style="font-size:34px;color:#2672ec;margin:0 0 16px">安全代码</p>
        <p>请将以下安全代码用于 Microsoft 帐户 <a href="mailto:ni*****@example.com">ni*****@example.com</a>。</p>
        <p>安全代码: <b style="font-size:20px">384920</b></p>
        <p>如果你无法识别该帐户 ni*****@example.com，可以<a href="https://account.live.com">单击此处</a>以从该帐户中删除你的电子邮件地址。</p>
        <p>谢谢!<br>Microsoft 帐户团队</p>
        <img src="https://example.com/track/open.gif?id=demo" width="1" height="1"></td></tr></table>
        """,
        "attachments": [
            ["id": "a1", "name": "安全提示.pdf", "content_type": "application/pdf", "size": 182_340, "is_inline": false],
            ["id": "a2", "name": "logo.png", "content_type": "image/png", "size": 9_120, "is_inline": false],
        ],
    ]
}
#endif

#if DEBUG
import SwiftUI

/// 演示模式下直接打开某个页面，省得在模拟器里点
struct DemoScreen: View {
    let screen: String

    init?(screen: String) {
        guard ["mails", "detail", "login", "settings", "lock", "shares", "share-create", "share-detail",
              "edit", "refresh", "refresh-run", "temp", "temp-mails", "compose", "oauth", "tags", "group", "refresh-setup"].contains(screen) else { return nil }
        self.screen = screen
    }

    var body: some View {
        let data = try! JSONSerialization.data(withJSONObject: DemoURLProtocol.accounts[0])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let account = try! decoder.decode(MailAccount.self, from: data)
        let mailData = try! JSONSerialization.data(withJSONObject: DemoURLProtocol.emails[0])
        let mail = try! decoder.decode(MailSummary.self, from: mailData)
        return NavigationStack {
            switch screen {
            case "mails": MailListView(account: account)
            case "detail": MailDetailView(account: account.email, mail: mail, folder: .inbox)
            case "settings": SettingsView()
            case "edit": AccountEditView(accountId: account.id)
            case "refresh": RefreshCenterView()
            case "refresh-run": RefreshRunView(kind: .all)
            case "refresh-setup": RefreshSetupView(initialGroupId: 1)
            case "temp": TempEmailListView()
            case "temp-mails":
                TempMailListView(temp: TempEmail(id: 1, email: "k8x2qv@gpt.example.com", provider: "gptmail",
                                                 createdAt: nil, cloudflareChannelName: nil, tags: nil))
            case "compose": ComposeView(account: account)
            case "oauth": OAuthHelperView(groups: [])
            case "tags": TagManageView()
            case "group": GroupEditView(group: nil, groups: [])
            case "shares": ShareManagementView()
            case "share-create": CreateShareView(account: account)
            case "share-detail":
                ShareDetailSheet(share: try! decoder.decode(EmailShare.self, from: JSONSerialization.data(
                    withJSONObject: DemoURLProtocol.share(1, account.email, expires: -3 * 3600, count: 5, accessed: 600))),
                                 onUpdate: { _ in }, onDelete: {})
            case "lock": LockScreen(biometry: "Face ID") {}
            default: LoginView()
            }
        }
    }
}
#endif
