import ImageIO
import SwiftUI

/// 发件人头像：常见大厂用内置的品牌图标(按发件域名匹配，不联网)；
/// 设置里打开"联网获取发件人图标"后，没内置的再去取网站图标；都没有就是字母头像。
struct SenderAvatar: View {
    let sender: MailAddress
    var size: CGFloat = DS.Size.avatar

    private let privacy = Privacy.shared
    @State private var favicon: UIImage?

    init(_ sender: MailAddress, size: CGFloat = DS.Size.avatar) {
        self.sender = sender
        self.size = size
    }

    /// 只传地址(信任的发件人列表)
    init(address: String, size: CGFloat = DS.Size.avatar) {
        self.init(MailAddress(address), size: size)
    }

    private var domain: String {
        guard let at = sender.address.lastIndex(of: "@") else { return "" }
        return sender.address[sender.address.index(after: at)...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " >")).lowercased()
    }

    var body: some View {
        if let brand = Brand.match(domain) {
            BrandMark(brand: brand, size: size)
        } else if let favicon {
            Circle()
                .fill(.white)
                .frame(width: size, height: size)
                .overlay {
                    Image(uiImage: favicon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: size * 0.62, height: size * 0.62)
                }
                .overlay(Circle().strokeBorder(DS.Palette.separator, lineWidth: 0.5))
                .accessibilityHidden(true)
                .transition(.opacity)
        } else {
            Avatar(text: sender.display, size: size)
                .task(id: privacy.loadSenderIcons ? domain : "") {
                    guard privacy.loadSenderIcons, SenderIconStore.allows(domain) else { return }
                    let image = await SenderIconStore.shared.icon(for: domain)
                    withAnimation(DS.Motion.snappy) { favicon = image }
                }
        }
    }
}

/// 品牌色圆底 + 白色(浅色品牌用黑色)图形，和字母头像同样大小
struct BrandMark: View {
    let brand: Brand
    var size: CGFloat = DS.Size.avatar

    var body: some View {
        let luminance = brand.luminance
        let glyph: Color = luminance > 0.55 ? .black : .white
        Circle()
            .fill(Color(rgb: brand.rgb))
            .frame(width: size, height: size)
            .overlay {
                switch brand.mark {
                case .icon(let slug):
                    Image("brand-\(slug)")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: size * 0.5, height: size * 0.5)
                        .foregroundStyle(glyph)
                case .text(let text):
                    Text(text)
                        .font(.system(size: size * (text.count > 1 ? 0.36 : 0.44), weight: .bold, design: .rounded))
                        .foregroundStyle(glyph)
                case .microsoft:
                    // 微软的四色方块：图标库里没有，几何图形直接画
                    let s = size * 0.2, gap = size * 0.03
                    Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                        GridRow {
                            Rectangle().fill(Color(rgb: 0xF25022)).frame(width: s, height: s)
                            Rectangle().fill(Color(rgb: 0x7FBA00)).frame(width: s, height: s)
                        }
                        GridRow {
                            Rectangle().fill(Color(rgb: 0x00A4EF)).frame(width: s, height: s)
                            Rectangle().fill(Color(rgb: 0xFFB900)).frame(width: s, height: s)
                        }
                    }
                }
            }
            // 黑色品牌在深色模式、浅灰底在浅色模式里会和背景糊在一起，加一圈细边
            .overlay {
                if luminance < 0.05 || luminance > 0.85 {
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                }
            }
            .accessibilityHidden(true)
    }
}

/// 内置的品牌：图形来自 Simple Icons(CC0，见 tools/make-brand-icons.py)，
/// 图标库里没有的(应品牌方要求移除的)用品牌色 + 文字
struct Brand {
    enum Mark {
        /// Assets 里的 brand-<slug>
        case icon(String)
        case text(String)
        case microsoft
    }

    let mark: Mark
    let rgb: UInt32

    /// 相对亮度，决定图形用白色还是黑色
    var luminance: Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb >> 16 & 0xFF) + 0.7152 * channel(rgb >> 8 & 0xFF) + 0.0722 * channel(rgb & 0xFF)
    }

    /// 按发件域名找品牌：先整个域名，再逐级去掉前缀(accountprotection.microsoft.com → microsoft.com)
    static func match(_ domain: String) -> Brand? {
        // 个人邮箱(xx@aliyun.com)不算品牌，品牌的通知邮件一般来自子域名(notice.aliyun.com)
        guard !SenderIconStore.personalDomains.contains(domain) else { return nil }
        var labels = domain.split(separator: ".")
        while labels.count >= 2 {
            if let brand = table[labels.joined(separator: ".")] { return brand }
            labels.removeFirst()
        }
        return nil
    }

    private static let table: [String: Brand] = {
        var t: [String: Brand] = [:]
        for (domains, mark, rgb) in entries {
            for d in domains.split(separator: " ") { t[String(d)] = Brand(mark: mark, rgb: rgb) }
        }
        return t
    }()

    /// 只收发信方是公司的域名。gmail.com、outlook.com、qq.com 这类个人邮箱域名不放，免得每个人都显示成品牌
    private static let entries: [(String, Mark, UInt32)] = [
        // 账号与 AI
        ("microsoft.com microsoftonline.com", .microsoft, 0xF3F3F3),
        ("google.com", .icon("google"), 0x4285F4),
        ("youtube.com", .icon("youtube"), 0xFF0000),
        ("apple.com", .icon("apple"), 0x000000),
        ("openai.com", .text("AI"), 0x000000),
        ("anthropic.com", .icon("anthropic"), 0x191919),
        ("claude.ai claude.com", .icon("claude"), 0xD97757),
        ("mistral.ai", .icon("mistralai"), 0xFA520F),
        ("perplexity.ai", .icon("perplexity"), 0x1FB8CD),
        ("deepseek.com", .icon("deepseek"), 0x5786FE),
        ("huggingface.co", .icon("huggingface"), 0xFFD21E),
        ("cursor.com cursor.sh", .icon("cursor"), 0x000000),
        // 开发与云
        ("github.com", .icon("github"), 0x181717),
        ("gitlab.com", .icon("gitlab"), 0xFC6D26),
        ("cloudflare.com", .icon("cloudflare"), 0xF38020),
        ("vercel.com", .icon("vercel"), 0x000000),
        ("netlify.com", .icon("netlify"), 0x00C7B7),
        ("supabase.com supabase.io", .icon("supabase"), 0x3FCF8E),
        ("docker.com", .icon("docker"), 0x2496ED),
        ("digitalocean.com", .icon("digitalocean"), 0x0080FF),
        ("vultr.com", .icon("vultr"), 0x007BFC),
        ("hetzner.com hetzner.de", .icon("hetzner"), 0xD50C2D),
        ("ovh.com ovhcloud.com", .icon("ovh"), 0x123F6D),
        ("aliyun.com alibabacloud.com", .icon("alibabacloud"), 0xFF6A00),
        ("namecheap.com", .icon("namecheap"), 0xDE3723),
        ("godaddy.com", .icon("godaddy"), 0x1BDBDB),
        ("porkbun.com", .icon("porkbun"), 0xEF7878),
        ("tailscale.com", .icon("tailscale"), 0x242424),
        ("replit.com", .icon("replit"), 0xF26207),
        ("jetbrains.com", .icon("jetbrains"), 0x000000),
        ("npmjs.com", .icon("npm"), 0xCB3837),
        ("sentry.io", .icon("sentry"), 0x362D59),
        ("postman.com getpostman.com", .icon("postman"), 0xFF6C37),
        ("render.com", .icon("render"), 0x000000),
        ("railway.app railway.com", .icon("railway"), 0x0B0D0E),
        // 协作与社交
        ("discord.com discordapp.com", .icon("discord"), 0x5865F2),
        ("telegram.org", .icon("telegram"), 0x26A5E4),
        ("x.com twitter.com", .icon("x"), 0x000000),
        ("facebook.com facebookmail.com", .icon("facebook"), 0x0866FF),
        ("meta.com metamail.com", .icon("meta"), 0x0467DF),
        ("instagram.com", .icon("instagram"), 0xFF0069),
        ("whatsapp.com", .icon("whatsapp"), 0x25D366),
        ("signal.org", .icon("signal"), 0x3B45FD),
        ("line.me", .icon("line"), 0x00C300),
        ("reddit.com redditmail.com", .icon("reddit"), 0xFF4500),
        ("tiktok.com", .icon("tiktok"), 0x000000),
        ("snapchat.com", .icon("snapchat"), 0xFFFC00),
        ("pinterest.com", .icon("pinterest"), 0xBD081C),
        ("quora.com", .icon("quora"), 0xB92B27),
        ("medium.com", .icon("medium"), 0x000000),
        ("substack.com", .icon("substack"), 0xFF6719),
        ("patreon.com", .icon("patreon"), 0x000000),
        ("linkedin.com", .text("in"), 0x0A66C2),
        ("notion.so notion.com makenotion.com", .icon("notion"), 0x000000),
        ("slack.com", .text("S"), 0x4A154B),
        ("zoom.us zoom.com", .icon("zoom"), 0x0B5CFF),
        ("dropbox.com dropboxmail.com", .icon("dropbox"), 0x0061FF),
        ("figma.com", .icon("figma"), 0xF24E1E),
        ("atlassian.com atlassian.net", .icon("atlassian"), 0x0052CC),
        ("trello.com", .icon("trello"), 0x0052CC),
        ("asana.com", .icon("asana"), 0xF06A6A),
        ("linear.app", .icon("linear"), 0x5E6AD2),
        ("adobe.com", .text("A"), 0xFA0F00),
        ("duckduckgo.com", .icon("duckduckgo"), 0xDE5833),
        ("mozilla.org mozilla.com", .icon("mozilla"), 0x161616),
        // 购物、娱乐、出行
        ("amazon.com amazon.cn amazon.co.jp", .text("a"), 0xFF9900),
        ("ebay.com", .icon("ebay"), 0xE53238),
        ("shopify.com", .icon("shopify"), 0x7AB55C),
        ("aliexpress.com", .icon("aliexpress"), 0xFF4747),
        ("netflix.com", .icon("netflix"), 0xE50914),
        ("spotify.com", .icon("spotify"), 0x1ED760),
        ("steampowered.com steamcommunity.com", .icon("steam"), 0x000000),
        ("epicgames.com", .icon("epicgames"), 0x313131),
        ("playstation.com", .icon("playstation"), 0x0070D1),
        ("twitch.tv", .icon("twitch"), 0x9146FF),
        ("uber.com", .icon("uber"), 0x000000),
        ("airbnb.com", .icon("airbnb"), 0xFF5A5F),
        // 支付与金融
        ("paypal.com", .icon("paypal"), 0x002991),
        ("stripe.com", .icon("stripe"), 0x635BFF),
        ("wise.com", .icon("wise"), 0x9FE870),
        ("revolut.com", .icon("revolut"), 0x191C1F),
        ("chase.com", .icon("chase"), 0x117ACA),
        ("visa.com", .icon("visa"), 0x1A1F71),
        ("mastercard.com", .icon("mastercard"), 0xEB001B),
        ("americanexpress.com aexp.com", .icon("americanexpress"), 0x2E77BC),
        ("hsbc.com hsbc.com.hk", .icon("hsbc"), 0xDB0011),
        ("binance.com", .icon("binance"), 0xF0B90B),
        ("okx.com", .icon("okx"), 0x000000),
        ("coinbase.com", .icon("coinbase"), 0x0052FF),
        ("kucoin.com", .icon("kucoin"), 0x01BC8D),
        ("cmbchina.com", .text("招"), 0xC8102E),
        ("icbc.com.cn", .text("工"), 0xC7000B),
        ("ccb.com", .text("建"), 0x0052A2),
        ("boc.cn bankofchina.com", .text("中"), 0xB81C22),
        // 国内
        ("alipay.com", .icon("alipay"), 0x1677FF),
        ("wechat.com", .icon("wechat"), 0x07C160),
        ("taobao.com", .icon("taobao"), 0xE94F20),
        ("alibaba.com", .icon("alibabadotcom"), 0xFF6A00),
        ("jd.com", .text("京"), 0xE1251B),
        ("bilibili.com", .icon("bilibili"), 0x00A1D6),
        ("zhihu.com", .icon("zhihu"), 0x0084FF),
        ("xiaohongshu.com", .icon("xiaohongshu"), 0xFF2442),
        ("meituan.com", .icon("meituan"), 0xFFD100),
        ("bytedance.com", .icon("bytedance"), 0x3C8CFF),
        ("huawei.com huaweicloud.com", .icon("huawei"), 0xFF0000),
        ("xiaomi.com mi.com", .icon("xiaomi"), 0xFF6900),
        ("baidu.com", .icon("baidu"), 0x2932E1),
    ]
}

/// 联网取发件人网站图标(DuckDuckGo 的图标服务)。只放内存，不写磁盘；取不到的记下来不再重试
final class SenderIconStore {
    static let shared = SenderIconStore()

    private var icons: [String: UIImage] = [:]
    private var missing: Set<String> = []
    private var pending: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    /// 个人邮箱域名的图标是邮箱服务商的，不代表发件人，不去取
    static let personalDomains: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "msn.com",
        "yahoo.com", "icloud.com", "me.com", "mac.com", "aol.com", "proton.me", "protonmail.com",
        "gmx.com", "gmx.de", "mail.ru", "yandex.ru", "yandex.com", "zoho.com",
        "qq.com", "foxmail.com", "163.com", "126.com", "yeah.net", "sina.com", "sohu.com", "aliyun.com",
    ]

    static func allows(_ domain: String) -> Bool {
        domain.contains(".") && !personalDomains.contains(domain)
    }

    func icon(for domain: String) async -> UIImage? {
        if let image = icons[domain] { return image }
        if missing.contains(domain) { return nil }
        if let task = pending[domain] { return await task.value }
        let task = Task { await fetch(domain) }
        pending[domain] = task
        let image = await task.value
        pending[domain] = nil
        if let image { icons[domain] = image } else { missing.insert(domain) }
        return image
    }

    private func fetch(_ domain: String) async -> UIImage? {
        guard let host = domain.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Self.largestImage(in: data)
    }

    /// .ico 里常有好几种尺寸，挑最大的那张；太小(16px)放大会糊，宁可用字母头像
    private static func largestImage(in data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let best = (0..<CGImageSourceGetCount(source))
            .compactMap { CGImageSourceCreateImageAtIndex(source, $0, nil) }
            .max { $0.width < $1.width }
        guard let best, best.width >= 32 else { return nil }
        return UIImage(cgImage: best)
    }
}

extension Color {
    /// 0xRRGGBB
    init(rgb: UInt32) {
        self.init(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}
