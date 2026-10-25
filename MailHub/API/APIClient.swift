import Foundation
import Observation

/// 服务端返回的错误。`error` 字段有时是字符串，有时是带 message 的对象。
struct APIError: LocalizedError {
    let message: String
    var needLogin = false
    var csrfError = false
    var errorDescription: String? { message }
}

/// outlookEmail 完整管理 API 的客户端：密码登录建立 Session Cookie，写操作带 X-CSRFToken。
/// Cookie 由 URLSession 存进 HTTPCookieStorage(服务端是 permanent session，重启 App 仍有效)，
/// 所以 App 不保存登录密码。
@Observable
final class APIClient {
    private static let serverKey = "serverURL"

    /// 还没登录过时是 nil，登录页让用户自己填
    private(set) var serverURL: URL
    /// nil = 还没检查过登录状态
    private(set) var isLoggedIn: Bool?

    private var csrfToken: String?
    /// 看过的邮件列表(账号 + 文件夹)，切回来先显示它再后台刷新。只在内存里，退出登录清空
    @ObservationIgnored var mailListCache: [String: MailListCacheEntry] = [:]
    let session: URLSession
    let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.serverKey) ?? ""
        serverURL = URL(string: saved) ?? URL(string: "about:blank")!
        #if DEBUG
        if DemoMode.enabled { serverURL = URL(string: "https://mail.example.com")! }
        #endif
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        // 响应里有密码和 Refresh Token，不能让系统缓存写到磁盘
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        #if DEBUG
        if DemoMode.enabled { config.protocolClasses = [DemoURLProtocol.self] }
        #endif
        session = URLSession(configuration: config)
    }

    // MARK: 登录

    /// 启动时用已有 Cookie 试一下能不能拿到 CSRF Token，拿到就是已登录
    /// 是否已经填过服务器地址
    var hasServer: Bool { serverURL.host() != nil }

    func checkSession() async {
        guard hasServer else {
            isLoggedIn = false
            return
        }
        do {
            try await fetchCSRFToken()
            isLoggedIn = true
        } catch {
            isLoggedIn = false
        }
    }

    func login(server: String, password: String) async throws {
        var text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), url.host != nil else {
            throw APIError(message: "服务器地址无效")
        }
        serverURL = url
        UserDefaults.standard.set(text, forKey: Self.serverKey)

        struct Body: Encodable {
            let password: String
            let session_duration_days = "permanent"
        }
        do {
            let _: Empty = try await send("POST", "/login", body: Body(password: password), csrf: false)
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            // 公网地址只允许 https，免得登录密码和会话 Cookie 明文传输
            throw APIError(message: "公网服务器必须使用 https://，只有局域网地址可以用 http://")
        }
        try await fetchCSRFToken()
        isLoggedIn = true
    }

    func logout() async {
        var request = URLRequest(url: serverURL.appending(path: "/logout"))
        request.httpMethod = "GET"
        _ = try? await session.data(for: request)
        HTTPCookieStorage.shared.cookies(for: serverURL)?.forEach(HTTPCookieStorage.shared.deleteCookie)
        csrfToken = nil
        mailListCache = [:]
        isLoggedIn = false
    }

    private func fetchCSRFToken() async throws {
        struct CSRF: Decodable { let csrfToken: String? }
        let result: CSRF = try await send("GET", "/api/csrf-token", csrf: false)
        csrfToken = result.csrfToken
    }

    // MARK: 分组、标签、账号

    func groups() async throws -> [MailGroup] {
        struct R: Decodable { let groups: [MailGroup] }
        let r: R = try await send("GET", "/api/groups")
        return r.groups
    }

    func tags() async throws -> [MailTag] {
        struct R: Decodable { let tags: [MailTag] }
        let r: R = try await send("GET", "/api/tags")
        return r.tags
    }

    /// 有关键词走搜索接口，否则走列表接口；两者分页参数相同
    func accounts(query: String, groupId: Int?, tagIds: [Int], offset: Int, limit: Int = 50) async throws -> AccountPage {
        var items = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let groupId { items.append(URLQueryItem(name: "group_id", value: String(groupId))) }
        if !tagIds.isEmpty {
            items.append(URLQueryItem(name: "tag_ids", value: tagIds.map(String.init).joined(separator: ",")))
        }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            return try await send("GET", "/api/accounts", query: items)
        }
        items.append(URLQueryItem(name: "q", value: keyword))
        return try await send("GET", "/api/accounts/search", query: items)
    }

    func importAccounts(text: String, provider: String, format: String, groupId: Int,
                        imapHost: String, imapPort: Int?) async throws -> ImportResult {
        struct Body: Encodable {
            let account_string: String
            let provider: String
            let account_format: String
            let group_id: Int
            let imap_host: String?
            let imap_port: Int?
        }
        let custom = provider == "custom"
        return try await send("POST", "/api/accounts", body: Body(
            account_string: text, provider: provider, account_format: format, group_id: groupId,
            imap_host: custom ? imapHost : nil, imap_port: custom ? imapPort : nil))
    }

    func refreshStats() async throws -> RefreshStats {
        struct R: Decodable { let stats: RefreshStats }
        let r: R = try await send("GET", "/api/accounts/refresh-stats")
        return r.stats
    }

    func refreshToken(accountId: Int) async throws -> RefreshResult {
        try await send("POST", "/api/accounts/\(accountId)/refresh", body: Empty())
    }

    // MARK: 邮箱分享

    func shares(accountId: Int? = nil) async throws -> [EmailShare] {
        struct R: Decodable { let shares: [EmailShare] }
        let query = accountId.map { [URLQueryItem(name: "account_id", value: String($0))] } ?? []
        let r: R = try await send("GET", "/api/email-shares", query: query)
        return r.shares
    }

    /// durationMinutes 在 neverExpires 时忽略；maxEmailCount 为 nil 表示不限量(服务端上限 50)
    func createShare(accountId: Int, durationMinutes: Int, neverExpires: Bool, maxEmailCount: Int?) async throws -> EmailShare {
        struct Body: Encodable {
            let account_id: Int
            let duration_minutes: Int
            let never_expires: Bool
            let max_email_count: Int?
        }
        struct R: Decodable { let share: EmailShare }
        let r: R = try await send("POST", "/api/email-shares", body: Body(
            account_id: accountId, duration_minutes: durationMinutes, never_expires: neverExpires,
            max_email_count: maxEmailCount))
        return r.share
    }

    /// 撤销：链接立即失效，记录保留
    func revokeShare(id: Int) async throws -> EmailShare {
        struct R: Decodable { let share: EmailShare }
        let r: R = try await send("POST", "/api/email-shares/\(id)/cancel", body: Empty())
        return r.share
    }

    func deleteShare(id: Int) async throws {
        let _: Empty = try await send("DELETE", "/api/email-shares/\(id)")
    }

    /// 服务端用自己看到的 Host 拼链接，经过反向代理时可能是内网地址或 http；
    /// 只取路径，拼到 App 登录用的服务器地址上
    func shareLink(_ share: EmailShare) -> URL? {
        guard let raw = share.shareUrl, let url = URL(string: raw) else { return nil }
        let path = url.path(percentEncoded: true)
        guard path.hasPrefix("/share/") else { return url }
        return URL(string: serverURL.absoluteString + path)
    }

    // MARK: 邮件

    /// local = 只读服务器本地留存的邮件(服务端设置里开了"本地保留邮件"才有)，不连微软，很快
    func emails(account: String, folder: MailFolder, skip: Int, top: Int = 20,
                local: Bool = false) async throws -> MailListResponse {
        var query = [
            URLQueryItem(name: "folder", value: folder.rawValue),
            URLQueryItem(name: "skip", value: String(skip)),
            URLQueryItem(name: "top", value: String(top)),
        ]
        if local { query.append(URLQueryItem(name: "source", value: "local")) }
        return try await send("GET", "/api/emails/\(pathEscape(account))", query: query)
    }

    func emailDetail(account: String, mail: MailSummary, folder: MailFolder) async throws -> MailDetail {
        struct R: Decodable { let email: MailDetail }
        // 服务器留存了正文就直接返回，没有再去取(和网页版一样)
        let r: R = try await send("GET", "/api/email/\(pathEscape(account))/\(pathEscape(mail.id))",
                                  query: mailQuery(mail, folder: folder) + [URLQueryItem(name: "prefer_local", value: "1")])
        return r.email
    }

    func markRead(account: String, mails: [MailSummary], folder: MailFolder) async throws {
        let _: Empty = try await send("POST", "/api/emails/mark-read",
                                      body: MailItemsBody(account: account, mails: mails, folder: folder))
    }

    func delete(account: String, mails: [MailSummary], folder: MailFolder) async throws {
        let _: Empty = try await send("POST", "/api/emails/delete",
                                      body: MailItemsBody(account: account, mails: mails, folder: folder))
    }

    /// 附件下载到临时目录，返回本地文件 URL(给分享面板/预览用)
    func downloadAttachment(account: String, mail: MailSummary, folder: MailFolder,
                            attachment: MailAttachment) async throws -> URL {
        let path = "/api/email/\(pathEscape(account))/\(pathEscape(mail.id))/attachments/\(pathEscape(attachment.id))"
        let request = try makeRequest("GET", path, query: mailQuery(mail, folder: folder), body: nil as Empty?, csrf: false)
        let (data, response) = try await session.data(for: request)
        try checkStatus(data: data, response: response)
        let dir = try TempFiles.newFolder()
        let name = attachment.name?.replacingOccurrences(of: "/", with: "_") ?? "attachment"
        let file = dir.appending(path: name.isEmpty ? "attachment" : name)
        try data.write(to: file)
        return file
    }

    /// 全部附件打包成 ZIP 下载
    func downloadAllAttachments(account: String, mail: MailSummary, folder: MailFolder) async throws -> URL {
        let path = "/api/email/\(pathEscape(account))/\(pathEscape(mail.id))/attachments/download-all"
        let request = try makeRequest("GET", path, query: mailQuery(mail, folder: folder), body: nil as Empty?, csrf: false)
        let (data, response) = try await session.data(for: request)
        try checkStatus(data: data, response: response)
        let dir = try TempFiles.newFolder()
        let file = dir.appending(path: "attachments.zip")
        try data.write(to: file)
        return file
    }

    /// 邮件在 folder=all 列表里自带真实文件夹，详情/已读/删除要用它
    private func mailQuery(_ mail: MailSummary, folder: MailFolder) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "method", value: mail.method),
            URLQueryItem(name: "folder", value: mail.folder ?? folder.rawValue),
        ]
        if mail.method == "imap", let mode = mail.idMode {
            items.append(URLQueryItem(name: "id_mode", value: mode))
        }
        return items
    }

    private struct MailItemsBody: Encodable {
        struct Item: Encodable {
            let id: String
            let folder: String
            let id_mode: String
        }
        let email: String
        let method: String
        let folder: String
        let items: [Item]

        init(account: String, mails: [MailSummary], folder: MailFolder) {
            email = account
            method = mails.first?.method ?? "graph"
            self.folder = folder.rawValue
            items = mails.map { Item(id: $0.id, folder: $0.folder ?? folder.rawValue, id_mode: $0.idMode ?? "graph") }
        }
    }

    // MARK: 请求(其他功能在 APIClient+*.swift 里以扩展的形式调用这些方法)

    struct Empty: Codable {}

    func pathEscape(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    func makeRequest<B: Encodable>(_ method: String, _ path: String, query: [URLQueryItem],
                                           body: B?, csrf: Bool) throws -> URLRequest {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = serverURL.path(percentEncoded: true) + path
        if !query.isEmpty {
            components.queryItems = query
            // URLComponents 不转义 +，服务端会把它当空格(邮箱别名里常有 +)
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw APIError(message: "请求地址无效: \(path)") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if csrf, let csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRFToken")
        }
        return request
    }

    func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                    csrf: Bool = true) async throws -> T {
        try await send(method, path, query: query, body: nil as Empty?, csrf: csrf)
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                                  body: B?, csrf: Bool = true) async throws -> T {
        do {
            return try await perform(method, path, query: query, body: body, csrf: csrf)
        } catch let error as APIError where error.csrfError && csrf {
            // CSRF Token 过期(比如服务端重启)：换一个再试一次
            try await fetchCSRFToken()
            return try await perform(method, path, query: query, body: body, csrf: csrf)
        }
    }

    private func perform<T: Decodable, B: Encodable>(_ method: String, _ path: String, query: [URLQueryItem],
                                                     body: B?, csrf: Bool) async throws -> T {
        let request = try makeRequest(method, path, query: query, body: body, csrf: csrf && method != "GET")
        let (data, response) = try await session.data(for: request)
        try checkStatus(data: data, response: response)
        if T.self == Empty.self { return Empty() as! T }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError(message: "无法解析服务器返回的数据(\(path))：\(error.localizedDescription)")
        }
    }

    /// HTTP 状态和 JSON 里的 success=false 都当错误处理；401/need_login 时把登录状态置为未登录
    func checkStatus(data: Data, response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let needLogin = status == 401 || json?["need_login"] as? Bool == true
        if needLogin {
            isLoggedIn = false
            throw APIError(message: "登录已失效，请重新登录", needLogin: true)
        }
        if let json, json["success"] as? Bool == false || status >= 400 {
            throw APIError(message: Self.errorMessage(json) ?? "请求失败(HTTP \(status))",
                           csrfError: json["csrf_error"] as? Bool == true)
        }
        if status >= 400 {
            throw APIError(message: "请求失败(HTTP \(status))")
        }
    }

    private static func errorMessage(_ json: [String: Any]) -> String? {
        if let s = json["error"] as? String, !s.isEmpty { return s }
        if let obj = json["error"] as? [String: Any] {
            return (obj["message"] as? String) ?? (obj["details"] as? String)
        }
        return json["message"] as? String
    }
}
