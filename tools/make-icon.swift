// MailHub 图标：收发室信件格子(3×3)，中间一格朱红并插着一封信。纯色，无渐变。
// 用法: swift icon.swift <输出.png> [尺寸=1024]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let out = args[1]
let N = args.count > 2 ? Int(args[2])! : 1024
let s = CGFloat(N) / 1024

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let ink = rgb(0x17213A)      // 底：墨蓝
let slot = rgb(0x2A3858)     // 空格子
let vermilion = rgb(0xE8553A) // 有信的格子
let paper = rgb(0xF4EFE6)    // 信纸
let fold = rgb(0xD9D0C1)     // 信封折线

let ctx = CGContext(data: nil, width: N, height: N, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// 坐标系翻成左上角原点，方便按设计稿写
ctx.translateBy(x: 0, y: CGFloat(N)); ctx.scaleBy(x: 1, y: -1)
ctx.setShouldAntialias(true)

ctx.setFillColor(ink); ctx.fill(CGRect(x: 0, y: 0, width: N, height: N))

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 3×3 格子：宽 216、高 146，列距 28、行距 60(信从中间格露出的那截落在行距里，不压到上一格)
let w: CGFloat = 216, h: CGFloat = 146, gap: CGFloat = 28, rowGap: CGFloat = 60
let x0 = (1024 - (3 * w + 2 * gap)) / 2
let y0 = (1024 - (3 * h + 2 * rowGap)) / 2 + 8
for row in 0..<3 {
    for col in 0..<3 {
        let r = CGRect(x: (x0 + CGFloat(col) * (w + gap)) * s, y: (y0 + CGFloat(row) * (h + rowGap)) * s,
                       width: w * s, height: h * s)
        let isMail = row == 1 && col == 1
        ctx.addPath(rounded(r, 26 * s))
        ctx.setFillColor(isMail ? vermilion : slot)
        ctx.fillPath()
    }
}

// 中间格子里插着的信：比格子窄，从格子上沿露出一截，微微倾斜
let cx = (x0 + w + gap + w / 2) * s
let top = (y0 + h + rowGap) * s
ctx.saveGState()
ctx.translateBy(x: cx, y: top + 50 * s)
ctx.rotate(by: -6 * .pi / 180)
let letter = CGRect(x: -80 * s, y: -92 * s, width: 160 * s, height: 116 * s)
ctx.addPath(rounded(letter, 10 * s))
ctx.setFillColor(paper); ctx.fillPath()
// 信封盖的 V 形折线
ctx.setStrokeColor(fold)
ctx.setLineWidth(9 * s)
ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: letter.minX + 14 * s, y: letter.minY + 14 * s))
ctx.addLine(to: CGPoint(x: 0, y: letter.minY + 62 * s))
ctx.addLine(to: CGPoint(x: letter.maxX - 14 * s, y: letter.minY + 14 * s))
ctx.strokePath()
ctx.restoreGState()

// 信插在格子里：格子下半截盖住信的下部
let front = CGRect(x: (x0 + w + gap) * s, y: top + 52 * s, width: w * s, height: (h - 52) * s)
ctx.addPath(CGPath(roundedRect: front, cornerWidth: 26 * s, cornerHeight: 26 * s, transform: nil))
ctx.setFillColor(vermilion); ctx.fillPath()
ctx.fill(CGRect(x: front.minX, y: front.minY, width: front.width, height: 30 * s))

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
