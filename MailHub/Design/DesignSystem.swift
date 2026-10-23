import SwiftUI

/// 全 App 共用的设计常量：颜色按"角色"命名，间距/圆角/动效都从这里取，保证各页面对齐、风格统一。
///
/// 配色原则：一个主色(蓝)负责"可操作/选中/未读"，状态色各有唯一含义(绿=正常、红=失败/删除、橙=警告)，
/// 分组和标签颜色是用户自己设的分类色，只出现在小圆点和标签上。每个页面只有一个实心主操作。
enum DS {
    // MARK: 颜色(角色)

    enum Palette {
        /// 主色：主按钮、选中态、未读点、验证码。白字在上面对比度 5.2:1
        static let accent = Color(red: 0.145, green: 0.388, blue: 0.922)          // #2563EB
        static let accentDeep = Color(red: 0.118, green: 0.251, blue: 0.686)      // #1E40AF
        static let accentSoft = Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.12)
        /// 墨蓝：App 图标的底色，用在首页统计卡片这类"品牌面"上，白字对比度 15:1
        static let ink = Color(red: 0.090, green: 0.129, blue: 0.227)            // #17213A

        static let success = Color(red: 0.086, green: 0.639, blue: 0.290)         // #16A34A
        static let danger = Color(red: 0.863, green: 0.149, blue: 0.149)          // #DC2626
        static let warning = Color(red: 0.918, green: 0.345, blue: 0.047)         // #EA580C
        static let warningSoft = warning.opacity(0.10)

        /// 搜索栏、未选中标签、信息卡片的底色
        static let surface = Color(.secondarySystemBackground)
        static let separator = Color(.separator)

        /// 字母头像：明度和饱和度相近的一组色相，看起来是一家人
        static let avatars: [Color] = [
            Color(red: 0.86, green: 0.30, blue: 0.27), Color(red: 0.90, green: 0.47, blue: 0.13),
            Color(red: 0.85, green: 0.62, blue: 0.10), Color(red: 0.24, green: 0.64, blue: 0.36),
            Color(red: 0.09, green: 0.60, blue: 0.56), Color(red: 0.16, green: 0.50, blue: 0.86),
            Color(red: 0.31, green: 0.36, blue: 0.80), Color(red: 0.55, green: 0.33, blue: 0.80),
            Color(red: 0.84, green: 0.29, blue: 0.56), Color(red: 0.50, green: 0.40, blue: 0.34),
        ]
    }

    // MARK: 间距与尺寸

    enum Spacing {
        /// 页面左右边距：搜索栏、标签行、卡片、列表行全部对齐到这条线
        static let screen: CGFloat = 16
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Size {
        static let avatar: CGFloat = 40
        /// 头像右边文字的起点(16 + 40 + 12)，标题、分隔线都对齐这里
        static let textInset: CGFloat = Spacing.screen + avatar + Spacing.m
        /// Apple 要求的最小点击区域
        static let tapTarget: CGFloat = 44
    }

    enum Radius {
        static let chip: CGFloat = 10
        static let card: CGFloat = 16
        static let largeCard: CGFloat = 20
        static let fab: CGFloat = 18
    }

    // MARK: 动效

    /// 默认弹簧都是临界阻尼(不回弹)，只有跟手甩出去的手势才带一点回弹。
    enum Motion {
        /// 按压反馈：快、轻
        static let press = Animation.spring(response: 0.22, dampingFraction: 1)
        /// 选中态移动、展开收起
        static let snappy = Animation.spring(response: 0.32, dampingFraction: 1)
        /// 抽屉、提示条等较大的面板
        static let panel = Animation.spring(response: 0.38, dampingFraction: 1)
        /// 手势甩动后落位，带一点点回弹
        static let fling = Animation.spring(response: 0.38, dampingFraction: 0.86)

        /// 系统"减弱动态效果"打开时，位移/缩放换成短暂淡入淡出
        static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.15) : animation
        }
    }
}

/// 所有可点的卡片、标签、悬浮按钮：按下立刻缩到 97%，松手弹回
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}
