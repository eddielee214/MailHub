import SwiftUI

extension Color {
    /// 服务端分组/标签颜色是 #rrggbb
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

/// 底部短暂提示，设成非 nil 显示，2 秒后自动消失。从底部升起、原路退回
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Label(message, systemImage: icon(for: message))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .padding(.horizontal, DS.Spacing.l).padding(.vertical, DS.Spacing.m)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.bottom, 84)
                    .padding(.horizontal, DS.Spacing.xl)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .id(message)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(DS.Motion.panel) { self.message = nil }
                    }
            }
        }
        .animation(DS.Motion.panel, value: message)
    }

    private func icon(for message: String) -> String {
        if message.contains("失败") { return "exclamationmark.circle.fill" }
        if message.hasPrefix("正在") { return "arrow.triangle.2.circlepath" }
        return "checkmark.circle.fill"
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

enum MailDate {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()
    private static let fallbacks: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss",
        "EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z",  // IMAP 的 RFC 2822 日期
    ].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = $0
        return f
    }

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return isoFractional.date(from: s) ?? iso.date(from: s) ?? fallbacks.lazy.compactMap { $0.date(from: s) }.first
    }

    /// 今天显示时间，今年显示月日，更早显示年月日；解析不了就原样显示
    static func short(_ s: String?) -> String {
        guard let date = parse(s) else { return s ?? "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "昨天" }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.defaultDigits).day())
        }
        return date.formatted(date: .numeric, time: .omitted)
    }

    static func full(_ s: String?) -> String {
        guard let date = parse(s) else { return s ?? "" }
        return date.formatted(date: .abbreviated, time: .standard)
    }
}

/// 从邮件主题/正文里找验证码：优先找"验证码/code"附近的 4–8 位数字或字母数字串
enum VerificationCode {
    static func find(in texts: [String?]) -> String? {
        let text = texts.compactMap { $0 }.joined(separator: "\n")
        let keyword = #"(?:验证码|校验码|动态码|确认码|安全代码|安全码|代码|驗證碼|code|Code|CODE|OTP|otp|PIN)"#
        let patterns = [
            // 关键词后面隔几个字(不跨行)的数字，例如"安全代码: 384920""code is 527301"
            keyword + #"[^0-9\n]{0,25}?(?<![0-9])([0-9]{4,8})(?![0-9])"#,
            #"(?<![0-9])([0-9]{4,8})(?![0-9])[^0-9A-Za-z\n]{0,20}"# + keyword,
            keyword + #"[^0-9A-Za-z\n]{0,20}([A-Z0-9]{6,8})(?![A-Za-z0-9])"#,
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let m = re.firstMatch(in: text, range: range), let r = Range(m.range(at: 1), in: text) {
                let code = String(text[r])
                // 排除年份这类误报
                if code.count == 4, let n = Int(code), (1990...2100).contains(n) { continue }
                if code.contains(where: \.isNumber) { return code }
            }
        }
        return nil
    }

    /// HTML 正文去标签后再找，避免匹配到样式和链接里的数字
    static func plainText(fromHTML html: String) -> String {
        var s = html
        for p in [#"<style[\s\S]*?</style>"#, #"<script[\s\S]*?</script>"#, #"<[^>]+>"#] {
            s = s.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return s.replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
