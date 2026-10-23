import SwiftUI

struct LoginView: View {
    @Environment(APIClient.self) private var api
    @State private var server = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?
    /// 每次登录失败加一，驱动输入框晃动和错误震动
    @State private var failures = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    AppBadge(size: 76)
                    Text("MailHub").font(.largeTitle.weight(.bold))
                    Text("登录你的 outlookEmail 服务器")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    field(icon: "server.rack") {
                        // verbatim：避免提示里的网址被识别成蓝色链接
                        TextField(text: $server, prompt: Text(verbatim: "服务器地址，如 https://mail.example.com")) {
                            Text("服务器地址")
                        }
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    field(icon: "lock") {
                        SecureField("登录密码", text: $password)
                            .textContentType(.password)
                            .focused($passwordFocused)
                            .submitLabel(.go)
                            .onSubmit(login)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.danger)
                            .padding(.horizontal, DS.Spacing.xs)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                // 密码错误：左右轻晃一下(像 iOS 解锁密码输错)
                .keyframeAnimator(initialValue: 0.0, trigger: failures) { [reduceMotion] content, x in
                    content.offset(x: reduceMotion ? 0 : x)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(-10, duration: 0.07)
                        SpringKeyframe(9, duration: 0.07)
                        SpringKeyframe(-6, duration: 0.07)
                        SpringKeyframe(3, duration: 0.07)
                        SpringKeyframe(0, duration: 0.1)
                    }
                }
                .sensoryFeedback(.error, trigger: failures)
                .animation(DS.Motion.snappy, value: error)

                Button(action: login) {
                    ZStack {
                        Text("登录").opacity(loading ? 0 : 1)
                        if loading { ProgressView().tint(.white) }
                    }
                    .bold()
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.white)
                    .background(DS.Palette.accent, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(loading || password.isEmpty || server.isEmpty)
                .opacity(password.isEmpty || server.isEmpty ? 0.5 : 1)

                Text("使用网页版的登录密码。登录后长期有效，App 不保存密码。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if server.isEmpty, api.hasServer { server = api.serverURL.absoluteString }
            passwordFocused = true
        }
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            content()
        }
        .padding(.horizontal, DS.Spacing.l)
        .frame(height: 52)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card - 2))
    }

    private func login() {
        guard !loading, !password.isEmpty else { return }
        loading = true
        error = nil
        Task {
            do {
                try await api.login(server: server, password: password)
            } catch {
                self.error = error.localizedDescription
                failures += 1
            }
            loading = false
        }
    }
}
