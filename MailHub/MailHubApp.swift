import SwiftUI

@main
struct MailHubApp: App {
    @State private var api = APIClient()

    init() {
        // 清掉上次留下的附件和导出文件
        TempFiles.purge()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(api)
        }
    }
}

struct RootView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.scenePhase) private var phase
    private let privacy = Privacy.shared
    /// 开了 App 锁时，冷启动和每次从后台回来都先锁上
    @State private var locked = Privacy.shared.appLock
    @State private var authenticating = false

    var body: some View {
        screens
            .overlay {
                if locked {
                    LockScreen(biometry: privacy.biometryName) { Task { await unlock() } }
                } else if phase != .active && privacy.hideInSwitcher {
                    PrivacyCover()
                }
            }
            .onChange(of: phase) { _, new in
                if new == .background, privacy.appLock { locked = true }
                if new == .active, locked { Task { await unlock() } }
            }
            .task { if locked { await unlock() } }
    }

    @ViewBuilder
    private var screens: some View {
        #if DEBUG
        if let screen = DemoMode.screen, let demo = DemoScreen(screen: screen) {
            demo
        } else {
            content
        }
        #else
        content
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch api.isLoggedIn {
        case nil:
            ProgressView("正在连接服务器…")
                .task { await api.checkSession() }
        case false?:
            LoginView()
        case true?:
            AccountListView()
        }
    }

    private func unlock() async {
        // Face ID 弹窗本身会让 App 变成 inactive 再回到 active，防止重复弹
        guard !authenticating else { return }
        authenticating = true
        if await privacy.authenticate() { locked = false }
        authenticating = false
    }
}

/// 离开 App 时盖在最上面，多任务界面只看到这个
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial)
            AppBadge(size: 72)
        }
        .ignoresSafeArea()
    }
}

struct LockScreen: View {
    let biometry: String
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
            VStack(spacing: 20) {
                AppBadge(size: 76)
                Text("MailHub 已锁定").font(.title3.weight(.semibold))
                Button(action: onUnlock) {
                    Label("使用 \(biometry) 解锁", systemImage: biometry == "Face ID" ? "faceid" : "lock.open")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 24).padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(DS.Palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .ignoresSafeArea()
    }
}

/// App 图标(信件格子)，登录页、锁屏、抽屉顶部共用
struct AppBadge: View {
    var size: CGFloat = 76

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225))
            .accessibilityHidden(true)
    }
}
