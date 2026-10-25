import Foundation

// 字段名照 outlookEmail 服务端返回的 JSON(snake_case)，解码时统一转驼峰。
// 服务端很多字段可能缺失或为 null，所以除了 id 之外都给默认值。

struct MailGroup: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let color: String?
    let parentId: Int?
    let level: Int?
    let accountCount: Int?
    let descendantAccountCount: Int?

    /// 临时邮箱分组的账号在另一张表里，普通账号接口读不到
    var isTempEmailGroup: Bool { name == "临时邮箱" }
}

struct MailTag: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let color: String?
}

struct MailAccount: Decodable, Identifiable, Hashable {
    let id: Int
    let email: String
    let aliases: [String]?
    let groupId: Int?
    let groupName: String?
    let groupColor: String?
    let remark: String?
    let status: String?
    let provider: String?
    let accountType: String?
    let forwardEnabled: Bool?
    let lastRefreshAt: String?
    let lastRefreshStatus: String?
    let lastRefreshError: String?
    let tags: [MailTag]?

    var isOutlook: Bool { (accountType ?? provider ?? "outlook") == "outlook" }
    var isActive: Bool { (status ?? "active") == "active" }
    var refreshFailed: Bool { lastRefreshStatus == "failed" }
}

struct AccountPage: Decodable {
    let accounts: [MailAccount]
    let total: Int?
    let hasMore: Bool?
}

enum MailFolder: String, CaseIterable, Identifiable {
    case inbox, junkemail, deleteditems, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inbox: "收件箱"
        case .junkemail: "垃圾箱"
        case .deleteditems: "已删除"
        case .all: "全部"
        }
    }
}

struct MailSummary: Decodable, Identifiable, Hashable {
    let id: String
    let subject: String?
    let from: String?
    let to: String?
    let date: String?
    var isRead: Bool?
    let hasAttachments: Bool?
    let bodyPreview: String?
    let folder: String?
    let idMode: String?

    /// 同一个 id 在 folder=all 里可能来自不同文件夹，列表用这个当唯一键
    var listKey: String { "\(folder ?? "")/\(id)" }

    /// 后续详情/已读/删除要用同一种通道：graph 的 id 走 Graph，uid/sequence 走 IMAP
    var method: String { idMode == "uid" || idMode == "sequence" ? "imap" : "graph" }
}

struct MailListResponse: Decodable {
    let emails: [MailSummary]?
    let hasMore: Bool?
    let method: String?
}

struct MailListCacheEntry {
    var mails: [MailSummary]
    var hasMore: Bool
    var method: String?
}

struct MailAttachment: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let contentType: String?
    let size: Int?
    let isInline: Bool?
}

struct MailDetail: Decodable {
    let id: String
    let subject: String?
    let from: String?
    let to: String?
    let cc: String?
    let date: String?
    let body: String?
    let bodyType: String?
    let attachments: [MailAttachment]?
}

struct ImportResult: Decodable {
    let addedCount: Int?
    let skippedCount: Int?
    let invalidCount: Int?
    let message: String?
}

/// Token 刷新统计(只算启用中的 Outlook 账号)
struct RefreshStats: Decodable {
    let total: Int?
    let successCount: Int?
    let failedCount: Int?
    let neverCount: Int?
    let lastRefreshTime: String?
}

struct RefreshResult: Decodable {
    let message: String?
    let tokenRotated: Bool?
}

/// 邮箱分享链接(网页"分享邮箱/分享管理")：别人打开链接不用登录就能看这个邮箱的邮件
struct EmailShare: Decodable, Identifiable, Hashable {
    let id: Int
    let accountId: Int?
    let email: String?
    let expiresAt: String?
    let neverExpires: Bool?
    /// nil = 不限量；否则只显示收件箱+垃圾箱合计最新 N 封
    let maxEmailCount: Int?
    let revokedAt: String?
    let lastAccessedAt: String?
    let createdAt: String?
    let status: String?
    let shareUrl: String?

    enum State: String, CaseIterable, Identifiable {
        case active, expired, revoked
        var id: String { rawValue }
        var title: String {
            switch self {
            case .active: "有效"
            case .expired: "已过期"
            case .revoked: "已撤销"
            }
        }
    }

    var state: State { State(rawValue: status ?? "") ?? .expired }
}
