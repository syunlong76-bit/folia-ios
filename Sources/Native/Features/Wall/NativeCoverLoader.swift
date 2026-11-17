import Foundation
import ImageIO
import UIKit

/// M1 阶段 3：原生墙封面加载。走 LocalServer 的 /img 代理（与 Web
/// 同一条取图管线：磁盘缓存、并发闸、降采样都在代理侧），原生只做
/// 内存缓存 + 按档解码，不另起直连 CDN 的第二条管线。
///
/// 档位（源码定版 coverUrl.ts）：COVER_SIZE_STEPS [256, 512, 1024]
/// + 顶档 1200；sizePx = max(宽,高) × 相机scale × DPR，向上取档。
/// 内存层 NSCache 只是水位（规格 R2/DS 第十九轮）：内存警告时显式全清。
final class NativeCoverLoader {

    static let shared = NativeCoverLoader()

    static let sizeSteps = [256, 512, 1024]
    static let maxSize = 1200

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var memoryObserver: NSObjectProtocol?

    private init() {
        cache.totalCostLimit = 96 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    /// 按显示像素量选档（向上取档，超顶用 1200）。
    static func tier(forPixelExtent pixelExtent: Double) -> Int {
        for step in sizeSteps where Double(step) >= pixelExtent { return step }
        return maxSize
    }

    /// 墙面实际取档（3.7 (6) 真机问题修复）：数据链给的 /img 地址里
    /// 已带网关按字段选好的档（歌单 coverImgUrl 墙档 384、曲目 picUrl
    /// 640），那正是 Web 墙在用的档、也是 /img 磁盘缓存里已有的变体。
    /// 原生若按帧尺寸一律重取 1024/1200，每张都是冷取（缓存键含 w），
    /// 主页墙首开全墙冷图、并发闸只有 3——真机表现为封面久不出来。
    /// 规则：沿用内嵌档；只有真正的大卡（像素量 > 900，如展开卡/头条
    /// 大海报）才升到 1024。非 /img 地址走原选档。
    static func wallTier(raw: String, pixelExtent: Double) -> Int {
        if raw.hasPrefix("/img/"), let embedded = embeddedTier(in: raw) {
            return pixelExtent > 900 ? max(embedded, 1024) : embedded
        }
        return tier(forPixelExtent: pixelExtent)
    }

    /// 解析 /img 地址里已有的 ?w= 档位。
    private static func embeddedTier(in raw: String) -> Int? {
        guard let query = raw.split(separator: "?", maxSplits: 1).last else { return nil }
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0] == "w" { return Int(kv[1]) }
        }
        return nil
    }

    /// 把数据链给的封面地址（可能已是 /img 相对路径，也可能是漏网的
    /// CDN 绝对地址）规范成本地 /img 绝对地址并换到目标档。
    /// 非图片代理形态的地址原样返回（加载失败走占位）。
    func proxiedURLString(_ raw: String, tier: Int) -> String? {
        let port = LocalServer.shared.port
        guard port != 0 else { return nil }
        if raw.hasPrefix("/img/") {
            let base = raw.split(separator: "?", maxSplits: 1).first.map(String.init) ?? raw
            return "http://127.0.0.1:\(port)\(Self.upgradedImgPath(base))?w=\(tier)"
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            let encoded = Self.base64URL(Self.upgradedHTTPS(raw))
            return "http://127.0.0.1:\(port)/img/\(encoded)?w=\(tier)"
        }
        return nil
    }

    /// 3.7 (7) 封面全灭根因修复：网易云歌单 coverImgUrl 是 http:// 明文
    /// 地址（曲目 picUrl 是 https://），App 的 ATS 只给本机开了例外，
    /// 代理取 http 原图、原生跟随兜底跳转都会被拦——歌单封面全灭、
    /// 曲目封面无事。同一图片 http/https 返回字节一致（实测），一律
    /// 先升 https 再进代理。/img 载荷里烘焙的旧 http 地址同理：解码、
    /// 升级、重编码（顺带绕开代理磁盘缓存里的旧响应）。
    private static func upgradedHTTPS(_ url: String) -> String {
        url.hasPrefix("http://") ? "https://" + url.dropFirst(7) : url
    }

    private static func upgradedImgPath(_ path: String) -> String {
        guard path.hasPrefix("/img/") else { return path }
        let payload = String(path.dropFirst(5))
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let decoded = String(data: data, encoding: .utf8),
              decoded.hasPrefix("http://") else { return path }
        return "/img/" + base64URL(upgradedHTTPS(decoded))
    }

    private static func base64URL(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 同步查内存缓存（cell 配置时用：命中直接上图，不走异步，
    /// 避免 reloadData 重建 cell 时先清空再异步回图的一帧闪黑）。
    func cachedImage(for urlString: String) -> UIImage? {
        cache.object(forKey: urlString as NSString)
    }

    /// 加载并按档降采样解码；同 URL 全局一份（NSCache）。
    func image(for urlString: String, tier: Int) async -> UIImage? {
        let key = urlString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                // 失败留痕（地址是 base64 载荷、无明文主机）：下次封面
                // 问题凭日志定位，不靠猜。
                FoliaFileLog.write("cover", "native load bad status tier=\(tier) url=\(urlString)")
                return nil
            }
            let image = await Task.detached(priority: .utility) {
                Self.downsample(data: data, targetPixels: tier)
            }.value
            if let image {
                cache.setObject(image, forKey: key, cost: data.count)
            } else {
                FoliaFileLog.write("cover", "native decode failed tier=\(tier) url=\(urlString)")
            }
            return image
        } catch {
            FoliaFileLog.write("cover", "native load error tier=\(tier) url=\(urlString)")
            return nil
        }
    }

    private static func downsample(data: Data, targetPixels: Int) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPixels
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
