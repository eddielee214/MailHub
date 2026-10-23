import SwiftUI
import WebKit

/// 微软 OAuth 授权：在 App 内打开服务端给的授权链接，登录后微软会跳转到回调地址(默认 http://localhost:8080)，
/// 这里在跳转那一刻截下完整地址交给服务端换 Token，不用手动复制地址栏。
struct OAuthFlowView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss

    let title: String
    /// 拿到回调地址后做什么(换 Token、重新授权)；抛错会显示在页面上并允许重试
    let onRedirect: (String) async throws -> Void

    @State private var authURL: URL?
    @State private var redirectPrefix = "http://localhost:8080"
    @State private var working = false
    @State private var error: String?
    @State private var manualURL = ""
    @State private var showManual = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let authURL {
                    OAuthWebView(url: authURL, redirectPrefix: redirectPrefix) { url in handle(url) }
                        .ignoresSafeArea(edges: .bottom)
                } else if error == nil {
                    ProgressView("正在获取授权链接…")
                }
                if working {
                    Color(.systemBackground).opacity(0.85).ignoresSafeArea()
                    ProgressView("正在换取 Token…")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.danger)
                        .padding(DS.Spacing.m)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("粘贴回调地址") { showManual = true }
                }
            }
            .alert("粘贴回调地址", isPresented: $showManual) {
                TextField("http://localhost:8080/?code=…", text: $manualURL)
                Button("提交") { handle(manualURL) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("如果是在别的浏览器里完成的授权，把最后跳转到的完整地址粘贴到这里。")
            }
            .task { await loadURL() }
        }
    }

    private func loadURL() async {
        do {
            let r = try await api.oauthURL()
            if let redirect = r.redirectUri, !redirect.isEmpty { redirectPrefix = redirect }
            authURL = URL(string: r.authUrl)
            if authURL == nil { error = "服务器返回的授权链接无效" }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handle(_ url: String) {
        guard !working, url.contains("code=") else {
            error = "地址里没有授权码(code=)，请确认已完成登录授权"
            return
        }
        working = true
        error = nil
        Task {
            do {
                try await onRedirect(url)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

private struct OAuthWebView: UIViewRepresentable {
    let url: URL
    let redirectPrefix: String
    let onRedirect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(redirectPrefix: redirectPrefix, onRedirect: onRedirect) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 每次都是干净的登录环境，不和其他账号的微软登录状态串
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let redirectPrefix: String
        let onRedirect: (String) -> Void
        private var done = false

        init(redirectPrefix: String, onRedirect: @escaping (String) -> Void) {
            self.redirectPrefix = redirectPrefix
            self.onRedirect = onRedirect
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url?.absoluteString else { return .allow }
            if url.hasPrefix(redirectPrefix) {
                if !done {
                    done = true
                    onRedirect(url)
                }
                return .cancel
            }
            return .allow
        }
    }
}
