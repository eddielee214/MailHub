import SwiftUI

/// 首页顶部的卡片：Outlook Token 健康状况(数据来自网页的"Token 刷新管理")。
/// 墨蓝纯色底(和 App 图标同色)，数字变化时滚动过渡。
struct StatsCard: View {
    let stats: RefreshStats

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Label("Token 状态", systemImage: "key.fill")
                    .font(.subheadline)
                    .bold()
                Spacer()
                if let last = RelativeTime.text(stats.lastRefreshTime) {
                    Text("上次全量刷新 \(last)").font(.caption)
                }
            }
            .foregroundStyle(.white)
            HStack(spacing: 0) {
                item("Outlook", stats.total, .white)
                item("正常", stats.successCount, Color(red: 0.73, green: 0.97, blue: 0.80))
                item("失败", stats.failedCount, Color(red: 1.0, green: 0.80, blue: 0.80))
                item("未刷新", stats.neverCount, .white.opacity(0.8))
            }
            if let total = stats.total, total > 0 {
                // 正常 / 失败 / 未刷新 的比例条，颜色和上面的数字一一对应
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        bar(stats.successCount, total, geo.size.width, Color(red: 0.53, green: 0.94, blue: 0.67))
                        bar(stats.failedCount, total, geo.size.width, Color(red: 0.99, green: 0.65, blue: 0.65))
                        bar(stats.neverCount, total, geo.size.width, .white.opacity(0.45))
                    }
                }
                .frame(height: 6)
                .background(.white.opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding(DS.Spacing.l)
        .background(DS.Palette.ink, in: RoundedRectangle(cornerRadius: DS.Radius.largeCard))
        .animation(DS.Motion.panel, value: stats.successCount)
        .animation(DS.Motion.panel, value: stats.failedCount)
        .accessibilityElement(children: .combine)
    }

    private func item(_ title: String, _ value: Int?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value ?? 0)")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(value ?? 0)))
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bar(_ value: Int?, _ total: Int, _ width: CGFloat, _ color: Color) -> some View {
        let w = max(0, width * CGFloat(value ?? 0) / CGFloat(total))
        return Rectangle().fill(color).frame(width: w)
    }
}
