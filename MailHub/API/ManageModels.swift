import Foundation

/// 服务端有些字段时而是字符串时而是数字(临时邮件的 id、时间戳)，统一转成字符串
struct FlexString: Decodable, Hashable {
    let value: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            value = s
        } else if let i = try? c.decode(Int.self) {
            value = String(i)
        } else if let d = try? c.decode(Double.self) {
            value = String(Int(d))
        } else {
            value = ""
        }
    }
}

/// GET /api/accounts/<id>：编辑页需要的全部字段(含凭据)
struct AccountDetail: Decodable {
    let id: Int
    let email: String
    let password: String?
    let hasPassword: Bool?
    let clientId: String?
    let refreshToken: String?
    let accountType: String?
    let provider: String?
    let authorizationType: String?
    let imapHost: String?
    let imapPort: Int?
    let imapPassword: String?
    let hasImapPassword: Bool?
    let aliases: [String]?
    let forwardEnabled: Bool?
    let proxyUrl: String?
    let fallbackProxyUrl1: String?
    let fallbackProxyUrl2: String?
    let groupId: Int?
    let remark: String?
    let status: String?
    let tags: [MailTag]?

    var isOutlook: Bool { (accountType ?? provider ?? "outlook") == "outlook" }

    enum CodingKeys: String, CodingKey {
        case id, email, password, hasPassword, clientId, refreshToken, accountType, provider, authorizationType
        case imapHost, imapPort, imapPassword, hasImapPassword, aliases, forwardEnabled, proxyUrl
        // convertFromSnakeCase 把 fallback_proxy_url_1 转成 fallbackProxyUrl1
        case fallbackProxyUrl1, fallbackProxyUrl2
        case groupId, remark, status, tags
    }
}

/// 一条 Token 刷新记录(全局/单账号日志、失败快照共用)
struct RefreshLog: Decodable, Identifiable, Hashable {
    let id: Int
    let accountId: Int?
    let accountEmail: String?
    let refreshType: String?
    let status: String?
    let tokenRotated: Bool?
    let message: String?
    let errorMessage: String?
    let createdAt: String?

    var succeeded: Bool { status == "success" }

    var typeLabel: String {
        switch refreshType {
        case "manual": "手动"
        case "scheduled": "定时"
        case "retry", "retry_failed": "重试"
        case "manual_selected": "选中刷新"
        case "single", "manual_single": "单个"
        case "latest": "最近一次"
        default: refreshType ?? ""
        }
    }
}

/// 全量/重试/选中刷新的 SSE 事件，按 type 区分
struct RefreshEvent: Decodable {
    let type: String
    let total: Int?
    let current: Int?
    let accountId: Int?
    let email: String?
    let status: String?
    let message: String?
    let errorMessage: String?
    let tokenRotated: Bool?
    let successCount: Int?
    let failedCount: Int?
    let seconds: Int?
}

/// Token 刷新管理页的分页列表(项目和首页账号是同一种结构)
struct RefreshStatusPage: Decodable {
    let items: [MailAccount]
    let total: Int?
    let stats: RefreshStats?
}

struct ForwardingLog: Decodable, Identifiable, Hashable {
    let id: Int
    let accountId: Int?
    let accountEmail: String?
    let channel: String?
    let status: String?
    let subject: String?
    let errorMessage: String?
    let createdAt: String?

    var succeeded: Bool { status == "success" || status == "sent" }
}

// MARK: 临时邮箱

struct TempEmail: Decodable, Identifiable, Hashable {
    let id: Int
    let email: String
    let provider: String?
    let createdAt: String?
    let cloudflareChannelName: String?
    let tags: [MailTag]?

    var providerLabel: String {
        switch provider ?? "gptmail" {
        case "gptmail": "GPTMail"
        case "duckmail": "DuckMail"
        case "cloudflare": cloudflareChannelName.map { "Cloudflare · \($0)" } ?? "Cloudflare"
        case let other: other
        }
    }
}

struct TempMailSummary: Decodable, Identifiable, Hashable {
    let rawId: FlexString
    let from: String?
    let subject: String?
    let bodyPreview: String?
    let date: FlexString?
    let timestamp: FlexString?

    var id: String { rawId.value }

    enum CodingKeys: String, CodingKey {
        case rawId = "id", from, subject, bodyPreview, date, timestamp
    }

    /// 时间可能是秒级时间戳或 ISO 字符串
    var dateValue: Date? {
        if let t = Double(timestamp?.value ?? ""), t > 0 { return Date(timeIntervalSince1970: t) }
        if let t = Double(date?.value ?? ""), t > 0 { return Date(timeIntervalSince1970: t) }
        return MailDate.parse(date?.value)
    }
}

struct TempMailDetail: Decodable {
    let rawId: FlexString?
    let from: String?
    let to: String?
    let subject: String?
    let body: String?
    let bodyType: String?
    let date: FlexString?
    let timestamp: FlexString?

    enum CodingKeys: String, CodingKey {
        case rawId = "id", from, to, subject, body, bodyType, date, timestamp
    }

    /// 转成普通邮件详情，复用同一个正文渲染(含远程图片拦截)
    var asMailDetail: MailDetail {
        let seconds = Double(timestamp?.value ?? "") ?? 0
        let dateText = seconds > 0
            ? ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
            : date?.value
        return MailDetail(id: rawId?.value ?? "", subject: subject, from: from, to: to, cc: nil, date: dateText,
                          body: body, bodyType: bodyType, attachments: nil)
    }
}

struct DomainItem: Decodable, Hashable {
    let domain: String
}

struct CloudflareChannel: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let enabled: Bool?
}

struct OAuthTokenResult: Decodable {
    let refreshToken: String?
    let clientId: String?
}
