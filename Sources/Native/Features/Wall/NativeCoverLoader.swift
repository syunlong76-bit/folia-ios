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
///
/// (72) 歌单页封面提速（Miller (71) 报：滑快了黑屏）：①在途
/// 合并——同 URL 并发只发一份；②优先级调度——同时在途网络
/// 取图 ≤4（解码并发硬线同值），可见 cell 的请求恒排在预取
/// 前面，快滑时新行不再排在过期预取后面干等；③主色占位——
/// 解码时顺带算 1px 平均色入色缓存，cell 无图时先垫封面主
/// 色块（再无缓存则按地址哈希给暗调色），不许纯黑；④埋点
/// cvr.stat 每 40 次网络取图汇总命中/慢载，断点可量。
final class NativeCoverLoader {

    static let shared = NativeCoverLoader()

    static let sizeSteps = [256, 512, 1024]
    static let maxSize = 1200

    /// 取图优先级：可见 cell 高、视口外预取低（调度排序用）。
    enum LoadPriority: Int {
        case prefetch = 0
        case visible = 1
    }

    /// 并发调度（actor 串行）：在途网络取图上限 4；等待者按
    /// 优先级出队（同级 FIFO）。槽位在等待者间直接交接、
    /// running 不增减，无等待者时 release 才减一。
    private actor LoadScheduler {
        private var running = 0
        private let limit = 4
        private var waiters: [(priority: Int,
                                continuation: CheckedContinuation<Void, Never>)] = []

        func acquire(priority: Int) async {
            if running < limit {
                running += 1
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append((priority, continuation))
                waiters.sort { $0.priority > $1.priority }
            }
        }

        func release() {
            if waiters.isEmpty {
                running -= 1
            } else {
                waiters.removeFirst().continuation.resume()
            }
        }
    }

    private let cache = NSCache<NSString, UIImage>()
    /// (72) 主色缓存（与图缓存同键）：解码成功时顺带写入。
    private let colorCache = NSCache<NSString, UIColor>()
    private let scheduler = LoadScheduler()
    /// (72) 在途合并表（同 URL 一份 Task，多方 await 同结果）。
    private var inFlightLoads: [String: Task<UIImage?, Never>] = [:]
    private let inFlightLock = NSLock()
    /// (72) 埋点计数（网络取图口径）：hits/misses/slow(>800ms)。
    private var statHits = 0
    private var statMisses = 0
    private var statSlow = 0
    private var statLoadsSinceLog = 0
    private let statLock = NSLock()
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
            self?.colorCache.removeAllObjects()
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

    /// 同图任一档位的已缓存图（P4 升档空窗兜底）：目标档未命中时用
    /// 低档图顶上，不让大卡露空白。候选档 = 内嵌档（若有）+ 档位表 +
    /// 顶档，跳过 excludingTier（调用方已查）。
    func cachedImageAnyTier(raw: String, excludingTier: Int) -> UIImage? {
        var candidates = Self.sizeSteps + [Self.maxSize]
        if raw.hasPrefix("/img/"), let embedded = Self.embeddedTier(in: raw) {
            candidates.insert(embedded, at: 0)
        }
        for tier in candidates where tier != excludingTier {
            guard let url = proxiedURLString(raw, tier: tier) else { continue }
            if let image = cache.object(forKey: url as NSString) { return image }
        }
        return nil
    }

    /// (72) 某 URL 已解码图的主色（占位用）；未解码过为 nil。
    func dominantColor(for urlString: String) -> UIColor? {
        colorCache.object(forKey: urlString as NSString)
    }

    /// (72) 同图任一档的主色（目标档未解码时用低档色顶占位，
    /// 与 cachedImageAnyTier 同口径）。
    func dominantColorAnyTier(raw: String, excludingTier: Int) -> UIColor? {
        var candidates = Self.sizeSteps + [Self.maxSize]
        if raw.hasPrefix("/img/"), let embedded = Self.embeddedTier(in: raw) {
            candidates.insert(embedded, at: 0)
        }
        for tier in candidates where tier != excludingTier {
            guard let url = proxiedURLString(raw, tier: tier) else { continue }
            if let color = colorCache.object(forKey: url as NSString) { return color }
        }
        return nil
    }

    /// (72) 无任何缓存时的兜底占位色：按地址哈希取暗调色
    /// （低饱和、低明度），同图恒同色、不许纯黑。
    static func placeholderColor(for raw: String) -> UIColor {
        var hash: UInt64 = 5381
        for byte in raw.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return UIColor(hue: CGFloat(hash % 360) / 360,
                       saturation: 0.28, brightness: 0.23, alpha: 1)
    }

    private func noteStat(hit: Bool) {
        statLock.lock()
        if hit {
            statHits += 1
        } else {
            statMisses += 1
            statLoadsSinceLog += 1
        }
        let shouldLog = statLoadsSinceLog >= 40
        if shouldLog { statLoadsSinceLog = 0 }
        let snapshot = (statHits, statMisses, statSlow)
        statLock.unlock()
        if shouldLog {
            Breadcrumbs.log("cvr.stat hit=\(snapshot.0)"
                + " miss=\(snapshot.1) slow=\(snapshot.2)")
        }
    }

    private func noteSlowLoad() {
        statLock.lock()
        statSlow += 1
        statLock.unlock()
    }

    /// 加载并按档降采样解码；同 URL 全局一份（NSCache）。
    /// (72)：在途合并 + 优先级调度（见类头注）。
    func image(for urlString: String, tier: Int,
               priority: LoadPriority = .visible) async -> UIImage? {
        let key = urlString as NSString
        if let cached = cache.object(forKey: key) {
            noteStat(hit: true)
            return cached
        }
        inFlightLock.lock()
        if let existing = inFlightLoads[urlString] {
            inFlightLock.unlock()
            return await existing.value
        }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.loadFromNetwork(
                urlString: urlString, tier: tier, priority: priority)
        }
        inFlightLoads[urlString] = task
        inFlightLock.unlock()
        let result = await task.value
        inFlightLock.lock()
        inFlightLoads[urlString] = nil
        inFlightLock.unlock()
        return result
    }

    private func loadFromNetwork(urlString: String, tier: Int,
                                 priority: LoadPriority) async -> UIImage? {
        let key = urlString as NSString
        if let cached = cache.object(forKey: key) {
            noteStat(hit: true)
            return cached
        }
        guard let url = URL(string: urlString) else { return nil }
        noteStat(hit: false)
        let started = Date()
        await scheduler.acquire(priority: priority.rawValue)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetchDataWithConnectRetry(url)
        } catch {
            await scheduler.release()
            FoliaFileLog.write("cover", "native load error tier=\(tier) url=\(urlString)")
            return nil
        }
        await scheduler.release()
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            // 失败留痕（地址是 base64 载荷、无明文主机）：下次封面
            // 问题凭日志定位，不靠猜。
            FoliaFileLog.write("cover", "native load bad status tier=\(tier) url=\(urlString)")
            return nil
        }
        let decoded = await Task.detached(priority: .utility) {
            (image: Self.downsample(data: data, targetPixels: tier),
             color: Self.averageColor(data: data))
        }.value
        if Date().timeIntervalSince(started) > 0.8 { noteSlowLoad() }
        if let image = decoded.image {
            cache.setObject(image, forKey: key, cost: data.count)
            if let color = decoded.color {
                colorCache.setObject(color, forKey: key)
            }
        } else {
            FoliaFileLog.write("cover", "native decode failed tier=\(tier) url=\(urlString)")
        }
        return decoded.image
    }

    /// -1004 断连自愈（与 NativeDataClient 同口径）：(73)
    /// 改走 ensureAlive——探针实测判死后 restart 强制重建，
    /// 等新监听真 ready 再重发一次（(72) 的 start()+
    /// waitUntilAlive 在挂起静默死亡时整体失效，见
    /// NativeDataClient 同名注释）。
    private func fetchDataWithConnectRetry(_ url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            _ = await LocalServer.shared.ensureAlive(timeout: 3)
            return try await session.data(from: url)
        }
    }

    /// (72) 1px 平均色：缩略图降到 1px 后读其唯一像素。
    private static func averageColor(data: Data) -> UIColor? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(
            data as CFData, options as CFDictionary) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbOptions as CFDictionary) else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 255]
        let drawn = pixel.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return UIColor(red: CGFloat(pixel[0]) / 255,
                       green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255, alpha: 1)
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
