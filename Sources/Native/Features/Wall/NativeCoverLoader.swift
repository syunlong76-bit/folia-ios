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

    /// 把数据链给的封面地址（可能已是 /img 相对路径，也可能是漏网的
    /// CDN 绝对地址）规范成本地 /img 绝对地址并换到目标档。
    /// 非图片代理形态的地址原样返回（加载失败走占位）。
    func proxiedURLString(_ raw: String, tier: Int) -> String? {
        let port = LocalServer.shared.port
        guard port != 0 else { return nil }
        if raw.hasPrefix("/img/") {
            let base = raw.split(separator: "?", maxSplits: 1).first.map(String.init) ?? raw
            return "http://127.0.0.1:\(port)\(base)?w=\(tier)"
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            let encoded = Data(raw.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return "http://127.0.0.1:\(port)/img/\(encoded)?w=\(tier)"
        }
        return nil
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
                return nil
            }
            let image = await Task.detached(priority: .utility) {
                Self.downsample(data: data, targetPixels: tier)
            }.value
            if let image {
                cache.setObject(image, forKey: key, cost: data.count)
            }
            return image
        } catch {
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
