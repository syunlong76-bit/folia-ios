import UIKit

// 封面调色板提取（舞台用）：把封面降采样到 12×12 后按简单统计
// 派生 PaletteTokens——只出语义色，不出原始像素（协议冻结面）。
// 规则：平均色压暗为背景；平均色提亮为 primary；采样点里饱和度
// 最高的一簇取均值为 accent；明暗按平均亮度判，文字色随之定。
enum StagePalette {

    static func tokens(from image: UIImage) -> PaletteTokens {
        guard let averages = sample(image) else { return .neutralDark }
        let (avg, accentAvg) = averages
        let luminance = 0.2126 * avg.r + 0.7152 * avg.g + 0.0722 * avg.b
        let isDark = luminance < 0.55
        let background = mix(avg, toward: isDark ? 0 : 1, amount: isDark ? 0.45 : 0.25)
        let primary = mix(avg, toward: 1, amount: 0.35)
        let accent = accentAvg ?? mix(avg, toward: 1, amount: 0.55)
        let text: UIColor = isDark ? .white : UIColor(white: 0.08, alpha: 1)
        let secondary = mix(avg, toward: isDark ? 1 : 0, amount: 0.45)
        return PaletteTokens(
            background: UIColor(red: background.r, green: background.g, blue: background.b, alpha: 1),
            primary: UIColor(red: primary.r, green: primary.g, blue: primary.b, alpha: 1),
            secondary: UIColor(red: secondary.r, green: secondary.g, blue: secondary.b, alpha: 1),
            text: text,
            accent: UIColor(red: accent.r, green: accent.g, blue: accent.b, alpha: 1),
            isDark: isDark)
    }

    private struct RGB { var r: CGFloat; var g: CGFloat; var b: CGFloat }

    private static func mix(_ c: RGB, toward target: CGFloat, amount: CGFloat) -> RGB {
        RGB(r: c.r + (target - c.r) * amount,
            g: c.g + (target - c.g) * amount,
            b: c.b + (target - c.b) * amount)
    }

    /// 返回（全体平均色， 高饱和簇平均色）。
    private static func sample(_ image: UIImage) -> (RGB, RGB?)? {
        let side = 12
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = image.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        var sum = RGB(r: 0, g: 0, b: 0)
        var accentSum = RGB(r: 0, g: 0, b: 0)
        var accentCount: CGFloat = 0
        var count: CGFloat = 0
        for i in 0..<(side * side) {
            let r = CGFloat(pixels[i * 4]) / 255
            let g = CGFloat(pixels[i * 4 + 1]) / 255
            let b = CGFloat(pixels[i * 4 + 2]) / 255
            sum.r += r; sum.g += g; sum.b += b
            count += 1
            let maxC = max(r, g, b), minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            if saturation > 0.45 && maxC > 0.25 {
                accentSum.r += r; accentSum.g += g; accentSum.b += b
                accentCount += 1
            }
        }
        guard count > 0 else { return nil }
        let avg = RGB(r: sum.r / count, g: sum.g / count, b: sum.b / count)
        let accent = accentCount >= 3
            ? RGB(r: accentSum.r / accentCount, g: accentSum.g / accentCount, b: accentSum.b / accentCount)
            : nil
        return (avg, accent)
    }
}
