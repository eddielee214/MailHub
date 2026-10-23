import CoreImage.CIFilterBuiltins
import SwiftUI

/// 一条分享链接：二维码 + 地址 + 复制/系统分享。创建完成页和分享详情共用
struct ShareLinkCard: View {
    let url: URL
    var showQR = true
    @State private var copied = false

    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            if showQR, let qr = QRCode.image(for: url.absoluteString) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .padding(DS.Spacing.m)
                    .background(.white, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.separator))
                    .accessibilityLabel("分享链接二维码")
            }
            Text(url.absoluteString)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .textSelection(.enabled)
            HStack(spacing: DS.Spacing.m) {
                Button {
                    Privacy.shared.copy(url.absoluteString)
                    copied = true
                } label: {
                    Label(copied ? "已复制" : "复制链接", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .bold()
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget)
                        .foregroundStyle(.white)
                        .background(copied ? DS.Palette.success : DS.Palette.accent, in: Capsule())
                }
                .buttonStyle(.pressable)
                ShareLink(item: url) {
                    Label("发送", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget)
                        .background(DS.Palette.surface, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
            .animation(DS.Motion.snappy, value: copied)
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// 分享的有效期/可见范围/访问情况，管理列表和详情共用
enum ShareText {
    static func expiry(_ share: EmailShare) -> String {
        switch share.state {
        case .revoked: return "已撤销"
        case .expired: return "已过期"
        case .active:
            if share.neverExpires == true { return "永久有效" }
            guard let date = MailDate.parse(share.expiresAt) else { return "有效" }
            let left = date.timeIntervalSinceNow
            switch left {
            case ..<3600: return "剩 \(max(1, Int(left / 60))) 分钟"
            case ..<86400: return "剩 \(Int(left / 3600)) 小时"
            default: return "剩 \(Int(left / 86400)) 天"
            }
        }
    }

    static func scope(_ share: EmailShare) -> String {
        share.maxEmailCount.map { "最新 \($0) 封" } ?? "全部邮件"
    }

    static func access(_ share: EmailShare) -> String {
        RelativeTime.text(share.lastAccessedAt).map { "\($0)访问过" } ?? "还没人打开"
    }
}
