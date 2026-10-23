import SwiftUI

// 视觉风格：结构学 Gmail 移动端(圆形头像、胶囊搜索栏、侧边抽屉、悬浮按钮)，
// 细节学 outlookEmail 网页(邮箱类型标签、"别名:"、"x 分钟前")。颜色、间距、动效统一取自 DS。

/// 圆形字母头像，颜色由文字稳定地算出来(同一个发件人每次同色)
struct Avatar: View {
    let text: String
    var size: CGFloat = DS.Size.avatar

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    private var initial: String {
        let s = text.trimmingCharacters(in: CharacterSet(charactersIn: " \"'<"))
        return s.first.map { String($0).uppercased() } ?? "?"
    }

    private var color: Color {
        // 不用 hashValue：每次启动随机，颜色会变
        let sum = text.lowercased().unicodeScalars.reduce(UInt32(0)) { ($0 &* 31) &+ $1.value }
        return DS.Palette.avatars[Int(sum % UInt32(DS.Palette.avatars.count))]
    }
}

/// 网页里的邮箱类型标签。用浅底彩字而不是实心，免得和主按钮抢视线
struct ProviderPill: View {
    let provider: String?

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var tint: Color {
        switch provider ?? "outlook" {
        case "outlook": Color(red: 0.06, green: 0.42, blue: 0.74)   // 微软蓝 #0F6CBD
        case "gmail": Color(red: 0.80, green: 0.22, blue: 0.18)
        case "qq": Color(red: 0.07, green: 0.47, blue: 0.78)
        case "163", "126": Color(red: 0.10, green: 0.52, blue: 0.62)
        case "yahoo": Color(red: 0.42, green: 0.18, blue: 0.75)
        case "aliyun": Color(red: 0.82, green: 0.38, blue: 0.06)
        default: .secondary
        }
    }

    private var label: String {
        switch provider ?? "outlook" {
        case "outlook": "Outlook"
        case "gmail": "Gmail"
        case "qq": "QQ"
        case "yahoo": "Yahoo"
        case "aliyun": "阿里"
        case "custom", "auto": "IMAP"
        case let other: other
        }
    }
}

struct TagChip: View {
    let tag: MailTag

    var body: some View {
        Text(tag.name)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color(hex: tag.color) ?? .gray, in: Capsule())
    }
}

/// 一排可切换的标签(文件夹、分组)。选中背景是同一块色块，
/// 传入 namespace 时它会在标签之间滑过去(matchedGeometryEffect)，而不是这里灭那里亮。
struct FilterChip: View {
    let title: String
    var systemImage: String?
    /// 分组自己的颜色；nil 用主色
    var tint: Color?
    var count: Int?
    let selected: Bool
    var namespace: Namespace.ID?
    /// 撑满可用宽度(放在等宽网格里时用)
    var expands = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(tint ?? .secondary))
                }
                Text(title)
                if let count {
                    Text("\(count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                        .contentTransition(.numericText())
                }
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? .white : .primary)
            .frame(maxWidth: expands ? .infinity : nil)
            .padding(.horizontal, DS.Spacing.m)
            .frame(height: 34)
            .background {
                if selected {
                    Capsule().fill(tint ?? DS.Palette.accent)
                        .modifier(MatchedIfPossible(id: "chip", namespace: namespace))
                } else {
                    Capsule().fill(DS.Palette.surface)
                }
            }
            // 视觉 34pt，点击区域补到 44pt
            .frame(minHeight: DS.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MatchedIfPossible: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Gmail 右下角的悬浮按钮：往下滚时收成圆形只剩图标，往上滚展开文字
struct FloatingButton: View {
    let title: String
    let systemImage: String
    var collapsed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                if !collapsed {
                    Text(title)
                        .bold()
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, collapsed ? 0 : 20)
            .frame(width: collapsed ? 56 : nil, height: 56)
            .background(DS.Palette.accent, in: RoundedRectangle(cornerRadius: DS.Radius.fab))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(title)
        .padding(.trailing, DS.Spacing.screen)
        .padding(.bottom, DS.Spacing.m)
        .animation(DS.Motion.snappy, value: collapsed)
    }
}

/// 验证码胶囊：点一下复制，图标变成对勾 1.5 秒，并轻震一下
struct CodeChip: View {
    let code: String
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        Button {
            action()
            copied = true
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text(code).monospacedDigit()
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .imageScale(.small)
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(copied ? DS.Palette.success : DS.Palette.accent)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(copied ? DS.Palette.success.opacity(0.12) : DS.Palette.accentSoft, in: Capsule())
            .animation(DS.Motion.snappy, value: copied)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
        .accessibilityLabel("复制验证码 \(code)")
    }
}

enum RelativeTime {
    /// 和网页一样："刚刚 / x 分钟前 / x 小时前 / x 天前"，超过 30 天显示日期
    static func text(_ s: String?) -> String? {
        guard let date = MailDate.parse(s) else { return nil }
        let seconds = Date.now.timeIntervalSince(date)
        switch seconds {
        case ..<60: return "刚刚"
        case ..<3600: return "\(Int(seconds / 60)) 分钟前"
        case ..<86400: return "\(Int(seconds / 3600)) 小时前"
        case ..<(86400 * 30): return "\(Int(seconds / 86400)) 天前"
        default: return date.formatted(date: .numeric, time: .omitted)
        }
    }
}

/// "名字 <addr>" 拆成名字和地址
struct MailAddress {
    let name: String
    let address: String

    init(_ raw: String?) {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        if let lt = s.firstIndex(of: "<"), let gt = s.lastIndex(of: ">"), lt < gt {
            name = s[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            address = String(s[s.index(after: lt)..<gt])
        } else {
            name = ""
            address = s
        }
    }

    var display: String { name.isEmpty ? (address.isEmpty ? "(未知发件人)" : address) : name }
}
