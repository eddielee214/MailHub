import Foundation

// 网页"管理"类功能的接口：账号编辑/批量操作、分组标签、Token 刷新管理、转发、发信、临时邮箱、OAuth、导出。

extension APIClient {
    /// 大多数写操作只返回 success/message
    struct MessageResult: Decodable {
        let message: String?
    }

    // MARK: 单个账号

    func accountDetail(id: Int) async throws -> AccountDetail {
        struct R: Decodable { let account: AccountDetail }
        let r: R = try await send("GET", "/api/accounts/\(id)")
        return r.account
    }

    /// 服务端更新接口没传的字段会被重置成默认值(分组 1、状态 active、转发关)，
    /// 所以总是带上完整字段；密码类字段只在用户改过时才传(不传 = 保留原值)
    struct AccountUpdate: Encodable {
        var email: String
        var account_type: String
        var provider: String
        var client_id: String
        var refresh_token: String
        var authorization_type: String
        var imap_host: String
        var imap_port: Int
        var imap_password: String?
        var password: String?
        var group_id: Int
        var remark: String
        var status: String
        var forward_enabled: Bool
        var proxy_url: String
        var fallback_proxy_url_1: String
        var fallback_proxy_url_2: String
        var aliases: [String]
        var tag_ids: [Int]
    }

    func updateAccount(id: Int, _ update: AccountUpdate) async throws -> MessageResult {
        try await send("PUT", "/api/accounts/\(id)", body: update)
    }

    func deleteAccount(id: Int) async throws {
        let _: Empty = try await send("DELETE", "/api/accounts/\(id)")
    }

    func reauthorize(accountId: Int, redirectedURL: String) async throws -> MessageResult {
        struct Body: Encodable { let redirected_url: String }
        return try await send("POST", "/api/accounts/\(accountId)/reauthorize", body: Body(redirected_url: redirectedURL))
    }

    func refreshLogs(accountId: Int? = nil, limit: Int = 50) async throws -> [RefreshLog] {
        struct R: Decodable { let logs: [RefreshLog] }
        let path = accountId.map { "/api/accounts/\($0)/refresh-logs" } ?? "/api/accounts/refresh-logs"
        let r: R = try await send("GET", path, query: [URLQueryItem(name: "limit", value: String(limit))])
        return r.logs
    }

    // MARK: 批量操作

    private struct IDs: Encodable { let account_ids: [Int] }

    func batchMove(_ ids: [Int], groupId: Int) async throws -> MessageResult {
        struct Body: Encodable { let account_ids: [Int]; let group_id: Int }
        return try await send("POST", "/api/accounts/batch-update-group", body: Body(account_ids: ids, group_id: groupId))
    }

    func batchStatus(_ ids: [Int], active: Bool) async throws -> MessageResult {
        struct Body: Encodable { let account_ids: [Int]; let status: String }
        return try await send("POST", "/api/accounts/batch-update-status",
                              body: Body(account_ids: ids, status: active ? "active" : "inactive"))
    }

    func batchForwarding(_ ids: [Int], enabled: Bool) async throws -> MessageResult {
        struct Body: Encodable { let account_ids: [Int]; let forward_enabled: Bool }
        return try await send("POST", "/api/accounts/batch-update-forwarding", body: Body(account_ids: ids, forward_enabled: enabled))
    }

    func batchTag(_ ids: [Int], tagId: Int, add: Bool) async throws -> MessageResult {
        struct Body: Encodable { let account_ids: [Int]; let tag_id: Int; let action: String }
        return try await send("POST", "/api/accounts/tags", body: Body(account_ids: ids, tag_id: tagId, action: add ? "add" : "remove"))
    }

    func batchDelete(_ ids: [Int]) async throws -> MessageResult {
        try await send("POST", "/api/accounts/batch-delete", body: IDs(account_ids: ids))
    }

    // MARK: 分组和标签

    struct GroupInput: Encodable {
        var name: String
        var description: String
        var color: String
        var proxy_url: String
        var parent_id: Int?

        // parent_id 为 nil 时也要显式发 null(表示一级分组)
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(description, forKey: .description)
            try c.encode(color, forKey: .color)
            try c.encode(proxy_url, forKey: .proxy_url)
            try c.encode(parent_id, forKey: .parent_id)
        }

        enum CodingKeys: String, CodingKey { case name, description, color, proxy_url, parent_id }
    }

    func saveGroup(id: Int?, _ input: GroupInput) async throws -> MessageResult {
        if let id {
            return try await send("PUT", "/api/groups/\(id)", body: input)
        }
        return try await send("POST", "/api/groups", body: input)
    }

    func deleteGroup(id: Int) async throws -> MessageResult {
        try await send("DELETE", "/api/groups/\(id)")
    }

    func groupDetail(id: Int) async throws -> GroupDetail {
        struct R: Decodable { let group: GroupDetail }
        let r: R = try await send("GET", "/api/groups/\(id)")
        return r.group
    }

    func createTag(name: String, color: String) async throws -> MessageResult {
        struct Body: Encodable { let name: String; let color: String }
        return try await send("POST", "/api/tags", body: Body(name: name, color: color))
    }

    func deleteTag(id: Int) async throws -> MessageResult {
        try await send("DELETE", "/api/tags/\(id)")
    }

    // MARK: Token 刷新管理

    func refreshStatusList(status: String, query: String, page: Int, pageSize: Int = 100) async throws -> RefreshStatusPage {
        try await send("GET", "/api/accounts/refresh-status-list", query: [
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ])
    }

    func failedRefreshes() async throws -> [RefreshLog] {
        struct R: Decodable { let logs: [RefreshLog] }
        let r: R = try await send("GET", "/api/accounts/refresh-logs/failed")
        return r.logs
    }

    func retryRefresh(accountId: Int) async throws -> RefreshResult {
        try await send("POST", "/api/accounts/\(accountId)/retry-refresh", body: Empty())
    }

    func stopFullRefresh() async throws -> MessageResult {
        try await send("POST", "/api/accounts/stop-full-refresh", body: Empty())
    }

    enum RefreshKind {
        case all, failed, selected([Int])
        /// 由 App 逐个调用单账号刷新，账号之间等 interval 秒(服务端的间隔是全局设置，不能按次指定)
        case sequence([RefreshTarget], interval: Int)
    }

    struct RefreshTarget: Hashable {
        let id: Int
        let email: String
    }

    /// 某个分组(含子分组，nil = 全部)里启用中的 Outlook 账号；IMAP 账号没有 Token 可刷
    func refreshableAccounts(groupId: Int?) async throws -> [MailAccount] {
        var items = [
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "10000"),
        ]
        if let groupId { items.append(URLQueryItem(name: "group_id", value: String(groupId))) }
        let page: AccountPage = try await send("GET", "/api/accounts", query: items)
        return page.accounts.filter { $0.isOutlook && $0.isActive }
    }

    /// 顺序刷新：发出和服务端 SSE 一样的事件，进度页不用区分来源。取消外层 Task 即停止
    private func sequentialRefresh(_ targets: [RefreshTarget], interval: Int) -> AsyncThrowingStream<RefreshEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let total = targets.count
                var ok = 0, failed = 0
                func event(_ type: String, current: Int? = nil, target: RefreshTarget? = nil, status: String? = nil,
                           message: String? = nil, error: String? = nil, seconds: Int? = nil) -> RefreshEvent {
                    RefreshEvent(type: type, total: total, current: current, accountId: target?.id, email: target?.email,
                                 status: status, message: message, errorMessage: error, tokenRotated: nil,
                                 successCount: ok, failedCount: failed, seconds: seconds)
                }
                continuation.yield(event("start", current: 0))
                for (index, target) in targets.enumerated() {
                    if Task.isCancelled { break }
                    continuation.yield(event("progress", current: index, target: target))
                    do {
                        let r = try await refreshToken(accountId: target.id)
                        ok += 1
                        continuation.yield(event("account_result", current: index + 1, target: target,
                                                 status: "success", message: r.message ?? "刷新成功"))
                    } catch is CancellationError {
                        break
                    } catch {
                        failed += 1
                        continuation.yield(event("account_result", current: index + 1, target: target,
                                                 status: "failed", error: error.localizedDescription))
                    }
                    if index < total - 1, interval > 0 {
                        continuation.yield(event("delay", current: index + 1, seconds: interval))
                        do { try await Task.sleep(for: .seconds(interval)) } catch { break }
                    }
                }
                continuation.yield(event(Task.isCancelled ? "stopped" : "complete", current: Task.isCancelled ? nil : total))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 全量刷新 / 重试失败 / 刷新选中：服务端用 SSE 一条条推进度。
    /// 返回的流在 complete/error/stopped 后结束；调用方取消 Task 即断开(服务端继续跑完)
    func refreshStream(_ kind: RefreshKind) -> AsyncThrowingStream<RefreshEvent, Error> {
        if case .sequence(let targets, let interval) = kind {
            return sequentialRefresh(targets, interval: interval)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let path: String
                    switch kind {
                    case .all:
                        path = "/api/accounts/refresh-all"
                    case .failed:
                        path = "/api/accounts/refresh-failed-stream"
                    case .sequence:
                        return
                    case .selected(let ids):
                        // 选中刷新要先建任务，再订阅它的事件流
                        struct Body: Encodable { let account_ids: [Int] }
                        struct R: Decodable { let taskId: String }
                        let r: R = try await send("POST", "/api/accounts/refresh-selected-stream", body: Body(account_ids: ids))
                        path = "/api/accounts/refresh-selected-stream/\(r.taskId)"
                    }
                    var request = try makeRequest("GET", path, query: [], body: nil as Empty?, csrf: false)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 3600
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        var data = Data()
                        for try await b in bytes { data.append(b) }
                        try checkStatus(data: data, response: response)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let event = try? decoder.decode(RefreshEvent.self, from: Data(json.utf8)) else { continue }
                        continuation.yield(event)
                        if ["complete", "error", "stopped", "conflict"].contains(event.type) { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 转发

    func forwardingLogs(accountId: Int? = nil, failedOnly: Bool = false, limit: Int = 50) async throws -> [ForwardingLog] {
        struct R: Decodable { let logs: [ForwardingLog] }
        let path: String
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let accountId {
            path = "/api/accounts/\(accountId)/forwarding-logs"
            if failedOnly { query.append(URLQueryItem(name: "failed_only", value: "true")) }
        } else {
            path = failedOnly ? "/api/accounts/forwarding-logs/failed" : "/api/accounts/forwarding-logs"
        }
        let r: R = try await send("GET", path, query: query)
        return r.logs
    }

    func triggerForwardingCheck() async throws -> MessageResult {
        try await send("POST", "/api/accounts/trigger-forwarding-check", body: Empty())
    }

    // MARK: 写邮件(Outlook Graph，纯文本)

    func sendMail(accountId: Int, recipients: [String], subject: String, body: String) async throws -> MessageResult {
        struct Body: Encodable { let account_id: Int; let recipients: [String]; let subject: String; let body: String }
        return try await send("POST", "/api/outlook/send-mail",
                              body: Body(account_id: accountId, recipients: recipients, subject: subject, body: body))
    }

    // MARK: 临时邮箱

    func tempEmails() async throws -> [TempEmail] {
        struct R: Decodable { let emails: [TempEmail] }
        let r: R = try await send("GET", "/api/temp-emails")
        return r.emails
    }

    struct TempGenerate: Encodable {
        var provider: String
        var prefix: String?
        var domain: String?
        var username: String?
        var password: String?
        var channel_id: Int?
    }

    func generateTempEmail(_ input: TempGenerate) async throws -> String {
        struct R: Decodable { let email: String }
        let r: R = try await send("POST", "/api/temp-emails/generate", body: input)
        return r.email
    }

    func deleteTempEmail(_ email: String) async throws {
        let _: Empty = try await send("DELETE", "/api/temp-emails/\(pathEscape(email))")
    }

    func tempMessages(_ email: String, refresh: Bool) async throws -> [TempMailSummary] {
        struct R: Decodable { let emails: [TempMailSummary]? }
        let path = "/api/temp-emails/\(pathEscape(email))"
        let r: R = refresh
            ? try await send("POST", path + "/refresh", body: Empty())
            : try await send("GET", path + "/messages")
        return r.emails ?? []
    }

    func tempMessage(_ email: String, id: String) async throws -> TempMailDetail {
        struct R: Decodable { let email: TempMailDetail }
        let r: R = try await send("GET", "/api/temp-emails/\(pathEscape(email))/messages/\(pathEscape(id))")
        return r.email
    }

    func duckmailDomains() async throws -> [String] {
        struct R: Decodable { let domains: [DomainItem] }
        let r: R = try await send("GET", "/api/duckmail/domains")
        return r.domains.map(\.domain)
    }

    func cloudflareChannels() async throws -> [CloudflareChannel] {
        struct R: Decodable { let channels: [CloudflareChannel] }
        let r: R = try await send("GET", "/api/cloudflare/channels")
        return r.channels
    }

    func cloudflareDomains(channelId: Int) async throws -> [String] {
        struct R: Decodable { let domains: [DomainItem] }
        let r: R = try await send("GET", "/api/cloudflare/domains",
                                  query: [URLQueryItem(name: "channel_id", value: String(channelId))])
        return r.domains.map(\.domain)
    }

    // MARK: OAuth 助手

    struct AuthURL: Decodable {
        let authUrl: String
        let clientId: String?
        let redirectUri: String?
    }

    func oauthURL() async throws -> AuthURL {
        try await send("GET", "/api/oauth/auth-url")
    }

    func exchangeToken(redirectedURL: String) async throws -> OAuthTokenResult {
        struct Body: Encodable { let redirected_url: String }
        return try await send("POST", "/api/oauth/exchange-token", body: Body(redirected_url: redirectedURL))
    }

    // MARK: 导出(先用登录密码换一次性令牌)

    func exportAccounts(password: String, accountIds: [Int]?) async throws -> URL {
        struct Verify: Encodable { let password: String }
        struct Token: Decodable { let verifyToken: String }
        let token: Token = try await send("POST", "/api/export/verify", body: Verify(password: password))
        let request: URLRequest
        if let accountIds {
            struct Body: Encodable { let account_ids: [Int]; let verify_token: String }
            request = try makeRequest("POST", "/api/accounts/export-selected", query: [],
                                      body: Body(account_ids: accountIds, verify_token: token.verifyToken), csrf: true)
        } else {
            request = try makeRequest("GET", "/api/accounts/export",
                                      query: [URLQueryItem(name: "verify_token", value: token.verifyToken)],
                                      body: nil as Empty?, csrf: false)
        }
        let (data, response) = try await session.data(for: request)
        try checkStatus(data: data, response: response)
        let file = try TempFiles.newFolder()
            .appending(path: "MailHub-accounts-\(Date.now.formatted(.iso8601.year().month().day())).txt")
        try data.write(to: file)
        return file
    }
}

struct GroupDetail: Decodable {
    let id: Int
    let name: String
    let description: String?
    let color: String?
    let proxyUrl: String?
    let parentId: Int?
}
