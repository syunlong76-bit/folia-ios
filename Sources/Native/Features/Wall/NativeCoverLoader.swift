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
    /// (84) 修 b：新增 warm（入墙预热）最低档——预热只许在
    /// 可见与滚动预取都无等待时出队，治冷启预热风暴压住
    /// 可见请求（(83) 日志 dec78 wait 最大 1922ms 的滞留窗）。
    enum LoadPriority: Int {
        case warm = -1
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
        /// (78) 第 6 条量测：等待队列峰值深度（dec78 汇总取
        /// 走并清零）——快滑黑砖到底是不是堵在取图队列里，
        /// 下轮日志凭此定案，不再靠猜。
        private var peakWaiting = 0

        func acquire(priority: Int) async {
            if running < limit {
                running += 1
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append((priority, continuation))
                waiters.sort { $0.priority > $1.priority }
                peakWaiting = max(peakWaiting, waiters.count)
            }
        }

        func takePeakWaiting() -> Int {
            defer { peakWaiting = 0 }
            return peakWaiting
        }

        func release() {
            if waiters.isEmpty {
                running -= 1
            } else {
                waiters.removeFirst().continuation.resume()
            }
        }
    }

    /// (84) 修 b：解码并发闸——此前解码走 Task.detached 无
    /// 上限，冷启预热＋滚动预取同涌时解码任务无界堆积
    /// （dec78 的 wait 只量网络槽等待、解码段无账）。本闸
    /// 上限 4（与取图并发硬线同值），等待者按优先级出队
    /// （visible＞prefetch＞warm），峰值队列深度供 dec84
    /// 见证取走。
    private actor DecodeGate84 {
        private var running = 0
        private let limit = 4
        private var waiters: [(priority: Int,
                                continuation: CheckedContinuation<Void, Never>)] = []
        private var peakWaiting = 0

        func acquire(priority: Int) async {
            if running < limit {
                running += 1
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append((priority, continuation))
                waiters.sort { $0.priority > $1.priority }
                peakWaiting = max(peakWaiting, waiters.count)
            }
        }

        func takePeakWaiting() -> Int {
            defer { peakWaiting = 0 }
            return peakWaiting
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
    /// (84) 修 b：解码并发闸（见 DecodeGate84）。
    private let decodeGate84 = DecodeGate84()
    /// (84) 修 b：预取在途上限（准入控制，statLock 守）——
    /// 滚动预取同时在途 ≤24、入墙预热 ≤8，超出即丢弃计数
    /// （pf84 的 drp），不许再现 (83) 一次入队 509 张的风暴。
    private var pfOutstanding84: [LoadPriority: Int] = [:]
    /// (84) pf84 转化见证（statLock 守）：预取实际入队的
    /// 缓存键集合与其中已被 cell configure 请求过的键集
    /// 合——转化率＝|交集|/|入队|，由 WallScrollMetrics 冲
    /// 刷 pf84。集合超 6000 键整体重置（防无界增长）。
    private var pfEnqueuedKeys84 = Set<String>()
    private var pfConvertedKeys84 = Set<String>()
    private var pfDropped84 = 0
    /// (84) dec84 见证累加（statLock 守）：自上次取走以来
    /// 各优先级的网络槽等待最大值（与 dec78 的 wait 对照，
    /// 判预取风暴是否还压得住可见请求）。
    private var dec84WaitMax: [Int: Int] = [:]
    /// (72) 在途合并表（同 URL 一份 Task，多方 await 同结果）。
    private var inFlightLoads: [String: Task<UIImage?, Never>] = [:]
    private let inFlightLock = NSLock()
    /// (72) 埋点计数（网络取图口径）：hits/misses/slow(>800ms)。
    private var statHits = 0
    private var statMisses = 0
    private var statSlow = 0
    private var statLoadsSinceLog = 0
    private let statLock = NSLock()
    /// (78) 第 6 条解码侧量测（与 cvr.stat 分开记）：每 40 次
    /// 网络取图汇总一行 wall.dec78——队列等待（排队深度与耗
    /// 时）与解码耗时分开计，配合 cell 侧 wall.tile78（占位
    /// 计数）区分「砖未绘制」与「解码未完成」：tile78 空占
    /// 位多＋dec78 队列深＝取图/解码堵；tile78 空占位多＋
    /// dec78 队列浅＝请求根本没发出去（查 cell 配置/实例
    /// 集）；tile78 正常而画面黑＝绘制层问题（查实例/帧）。
    private var decSamples = 0
    private var decWaitSumMs = 0
    private var decWaitMaxMs = 0
    private var decTimeSumMs = 0
    private var decTimeMaxMs = 0
    private var decStarved = 0
    private let session: URLSession
    private var memoryObserver: NSObjectProtocol?

    private init() {
        // (82) 第 1 条：墙缓存扩容——(81) 会话命中率约 2%
        // （hit7/miss320）是黑屏根子之一；在全应用硬线内
        // （墙缓存 LRU ≤120–180MB）提到 160MB，且成本改按
        // 解码后像素字节计（旧口径用压缩字节 data.count，
        // 低估真实占用约 10 倍、LRU 淘汰节奏失真）。
        cache.totalCostLimit = 160 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // (78) 第 6 条：内存警告落痕（wall.dec78 memwarn）
            // ——整墙同时变占位的头号嫌疑事件之一（清缓存后
            // 若同窗再遇 reloadData，全墙 cell 重新配置、全
            // 部露占位约 1 秒，与 (77) 录屏的 1.2s 黑窗形态
            // 吻合），下轮日志先看本行与黑窗时刻对不对位。
            // 主色缓存本版起不清：它体量极小、正是占位救命
            // 色，清了只会让占位退回哈希色、无任何收益。
            Breadcrumbs.log("wall.dec78 memwarn=1")
            self?.cache.removeAllObjects()
        }
    }

    /// (84) 第 4 条修 a：墙砖像素量**单源表达式**——预取侧
    /// 与 cell 配置侧对同一砖必须用同一公式产出同一缓存
    /// 键。此前预取侧＝世界边长×cameraScale×屏幕 scale、
    /// 配置侧＝布局帧边长×屏幕 scale（帧经布局取整/变换
    /// 后与世界式不等），两键可分叉、预取暖错键。本式为
    /// 唯一出处：入参恒为**世界 rect 边长**与当前
    /// cameraScale；网格形态无相机（cameraScale=1、世界
    /// 边长＝帧边长）同式成立。
    static func wallPixelExtent(worldExtent: Double,
                                cameraScale: Double) -> Double {
        worldExtent * cameraScale * Double(UIScreen.main.scale)
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

    /// (83) 第 1 条取证：解码在途计数（loadFromNetwork 解
    /// 码段前后增减，statLock 守）——与在途任务数一起供
    /// 滚动窗 wall.q83 同窗落痕：快滑黑屏时段到底堵在
    /// 「任务排队」还是「解码在途」，下轮日志凭此分流，
    /// 本版只补取证、不改调度逻辑（日志未到不许猜修）。
    private var decInFlight83 = 0

    /// (83) 第 1 条取证：当前在途加载任务数（排队＋取图
    /// ＋解码全含）与正在解码数，同步读（滚动窗冲刷点用）。
    func loadDepth83() -> (fly: Int, dec: Int) {
        inFlightLock.lock()
        let fly = inFlightLoads.count
        inFlightLock.unlock()
        statLock.lock()
        let dec = decInFlight83
        statLock.unlock()
        return (fly, dec)
    }

    /// (82) 第 1 条：ph82 统计增量（wall.ph82 见证用）——
    /// 返回自上次取走以来的 hit/miss 增量并推进基线。
    private var phHitBaseline82 = 0
    private var phMissBaseline82 = 0

    func takeStatsDelta82() -> (hit: Int, miss: Int) {
        statLock.lock()
        defer { statLock.unlock() }
        let delta = (statHits - phHitBaseline82, statMisses - phMissBaseline82)
        phHitBaseline82 = statHits
        phMissBaseline82 = statMisses
        return delta
    }

    /// (82) 第 1 条：占位图（主题色块＋音符字形）——砖在封
    /// 面未就位时画它而不是只垫一层近黑底色：(81) 判读实
    /// 证旧哈希色明度 0.23 在真机上读作纯黑。占位图带对角
    /// 渐变＋居中半透明 ♪，按地址哈希色生成、同图恒同图，
    /// 小缓存（按色键，≤64 张）。
    /// (83) 黑屏定案①：(82) 会话日志证实快滑时砖面只剩占
    /// 位、0.23 明度成片读作黑——占位底色明度提到 0.45
    /// （placeholderColor），先把黑感止住（真图到达率由
    /// prefetch83 真接线与入墙预热另治）。
    private let placeholderCache82 = NSCache<NSString, UIImage>()

    func placeholderImage(for raw: String, size: CGFloat = 96) -> UIImage {
        let base = Self.placeholderColor(for: raw)
        let key = "\(base.hashValue)-\(Int(size))" as NSString
        if let cached = placeholderCache82.object(forKey: key) { return cached }
        let side = max(size, 48)
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side))
        let image = renderer.image { context in
            let cg = context.cgContext
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            base.getRed(&r, green: &g, blue: &b, alpha: &a)
            let lighter = UIColor(red: min(r * 1.5 + 0.06, 1),
                                  green: min(g * 1.5 + 0.06, 1),
                                  blue: min(b * 1.5 + 0.06, 1), alpha: 1)
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [lighter.cgColor, base.cgColor] as CFArray,
                locations: [0, 1])!
            cg.drawLinearGradient(gradient,
                                  start: CGPoint(x: 0, y: 0),
                                  end: CGPoint(x: side, y: side),
                                  options: [])
            // 居中音符：读作「音乐占位」而非黑洞。
            let glyph = "♪" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: side * 0.42, weight: .light),
                .foregroundColor: UIColor.white.withAlphaComponent(0.28),
            ]
            let glyphSize = glyph.size(withAttributes: attrs)
            glyph.draw(at: CGPoint(x: (side - glyphSize.width) / 2,
                                   y: (side - glyphSize.height) / 2),
                       withAttributes: attrs)
        }
        placeholderCache82.setObject(image, forKey: key)
        return image
    }

    /// (83) 黑屏定案②③见证计数：pf83 触发次数与实际入队
    /// 预取量（statLock 守）——(82) 本函数全仓零调用、从未
    /// 运行（假交付，见 (83) 报告）；本版两面墙滚动回调按
    /// 方向真接线＋入墙预热，落痕须下轮日志数得到。
    private var pfTrig83 = 0
    private var pfItems83 = 0

    /// (82) 第 1 条：快滑方向预取入口（宿主在滚动回调里按
    /// 方向把即将入视的封面先喂进来，走 .prefetch 低优先
    /// 级、不与可见砖抢 4 个取图槽）。
    /// (83) 真接线：两面墙 scrollViewDidScroll 按方向调用
    /// （src=scroll）、数据落地入墙预热调用（src=warm）；
    /// 每次调用落 pf83（trig 累计触发、n 本次入队、tot
    /// 累计入队），warm 即使全命中缓存也落一行（n=0 可读）。
    func prefetch82(_ items: [(raw: String, tier: Int)],
                    source: String = "scroll", wall: String = "?") {
        // (84) 修 b：优先级按来源分档（warm 最低）＋在途准
        // 入上限（scroll ≤24／warm ≤8，超限丢弃计数 drp）；
        // 实际入队的键登记 pf84 供转化率见证。
        let priority: LoadPriority = source == "warm" ? .warm : .prefetch
        let cap = source == "warm" ? 8 : 24
        var enqueued = 0
        for item in items {
            guard let url = proxiedURLString(item.raw, tier: item.tier) else { continue }
            if cachedImage(for: url) != nil { continue }
            statLock.lock()
            let outstanding = pfOutstanding84[priority] ?? 0
            if outstanding >= cap {
                pfDropped84 += 1
                statLock.unlock()
                continue
            }
            pfOutstanding84[priority] = outstanding + 1
            if pfEnqueuedKeys84.count > 6000 {
                pfEnqueuedKeys84.removeAll()
                pfConvertedKeys84.removeAll()
            }
            pfEnqueuedKeys84.insert(url)
            statLock.unlock()
            enqueued += 1
            Task {
                _ = await self.image(for: url, tier: item.tier, priority: priority)
                self.statLock.lock()
                self.pfOutstanding84[priority] =
                    max(0, (self.pfOutstanding84[priority] ?? 1) - 1)
                self.statLock.unlock()
            }
        }
        statLock.lock()
        pfTrig83 += 1
        pfItems83 += enqueued
        let trig = pfTrig83, tot = pfItems83
        statLock.unlock()
        if enqueued > 0 || source == "warm" {
            Breadcrumbs.log("pf83 wall=\(wall) src=\(source)"
                + " n=\(enqueued) trig=\(trig) tot=\(tot)")
        }
    }

    /// (84) pf84 转化见证登记：cell configure 每次算出请求
    /// 键时调用——键若曾被预取入队，记一次转化（同一键多
    /// 次 configure 只记一次，口径＝入队键被真实需求命中
    /// 的比例）。
    func noteConfigure84(urlString: String) {
        statLock.lock()
        if pfEnqueuedKeys84.contains(urlString) {
            pfConvertedKeys84.insert(urlString)
        }
        statLock.unlock()
    }

    /// (84) pf84 快照（累计口径，不重置）：入队键数／已转
    /// 化键数／准入丢弃数。
    func takePf84() -> (enq: Int, conv: Int, drp: Int) {
        statLock.lock()
        defer { statLock.unlock() }
        return (pfEnqueuedKeys84.count, pfConvertedKeys84.count, pfDropped84)
    }

    /// (84) dec84 快照（取走重置）：各优先级网络槽等待最
    /// 大值（vis/pre/warm）＋解码闸峰值队列——与 (83) 日志
    /// dec78 的 wait 最大 1922ms 对照判读。
    func takeDec84() async -> (vis: Int, pre: Int, warm: Int, dqpk: Int) {
        statLock.lock()
        let snapshot = dec84WaitMax
        dec84WaitMax = [:]
        statLock.unlock()
        let dqpk = await decodeGate84.takePeakWaiting()
        return (snapshot[LoadPriority.visible.rawValue] ?? 0,
                snapshot[LoadPriority.prefetch.rawValue] ?? 0,
                snapshot[LoadPriority.warm.rawValue] ?? 0, dqpk)
    }

    /// (72) 无任何缓存时的兜底占位色：按地址哈希取色，同
    /// 图恒同色、不许纯黑。(83) 黑屏定案①：明度 0.23→0.45
    /// ——(82) 日志证实快滑时配置瞬间有真图的砖仅 29%、其
    /// 余只剩占位，0.23 在真机成片读作纯黑；0.45 起占位
    /// 读作彩色砖面、黑感先消（饱和不变、色相仍按哈希）。
    static func placeholderColor(for raw: String) -> UIColor {
        var hash: UInt64 = 5381
        for byte in raw.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return UIColor(hue: CGFloat(hash % 360) / 360,
                       saturation: 0.28, brightness: 0.45, alpha: 1)
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

    /// (78) 第 6 条：单次网络取图的队列等待＋解码耗时入账；
    /// 满 40 个样本汇总一行 wall.dec78 并清零（队列峰值向
    /// 调度器现取）。starve＝可见优先级在队列里干等 >500ms
    /// 的次数——快滑时新行封面被堵在队列里的直接计数。
    private func noteDec78(waitMs: Int, decMs: Int?,
                           priority: LoadPriority) async {
        statLock.lock()
        decSamples += 1
        decWaitSumMs += waitMs
        decWaitMaxMs = max(decWaitMaxMs, waitMs)
        if let decMs {
            decTimeSumMs += decMs
            decTimeMaxMs = max(decTimeMaxMs, decMs)
        }
        if priority == .visible && waitMs > 500 { decStarved += 1 }
        let ready = decSamples >= 40
        var snapshot: (n: Int, waitAvg: Int, waitMax: Int,
                       decAvg: Int, decMax: Int, starved: Int)?
        if ready {
            snapshot = (decSamples,
                        decWaitSumMs / max(decSamples, 1), decWaitMaxMs,
                        decTimeSumMs / max(decSamples, 1), decTimeMaxMs,
                        decStarved)
            decSamples = 0
            decWaitSumMs = 0
            decWaitMaxMs = 0
            decTimeSumMs = 0
            decTimeMaxMs = 0
            decStarved = 0
        }
        statLock.unlock()
        guard let snapshot else { return }
        let peak = await scheduler.takePeakWaiting()
        Breadcrumbs.log("wall.dec78 n=\(snapshot.n) qpk=\(peak)"
            + " wait=\(snapshot.waitAvg)/\(snapshot.waitMax)ms"
            + " dec=\(snapshot.decAvg)/\(snapshot.decMax)ms"
            + " starve=\(snapshot.starved)")
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
        // (78) 第 6 条：队列等待单独计时（acquire 前后）。
        let waitStart = Date()
        await scheduler.acquire(priority: priority.rawValue)
        let waitMs = Int(Date().timeIntervalSince(waitStart) * 1000)
        // (84) dec84 见证：网络槽等待按优先级记最大值（冲
        // 刷点 takeDec84 取走，与 dec78 同窗对照）。
        statLock.lock()
        dec84WaitMax[priority.rawValue] =
            max(dec84WaitMax[priority.rawValue] ?? 0, waitMs)
        statLock.unlock()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetchDataWithConnectRetry(url)
        } catch {
            await scheduler.release()
            await noteDec78(waitMs: waitMs, decMs: nil, priority: priority)
            FoliaFileLog.write("cover", "native load error tier=\(tier) url=\(urlString)")
            return nil
        }
        await scheduler.release()
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            // 失败留痕（地址是 base64 载荷、无明文主机）：下次封面
            // 问题凭日志定位，不靠猜。
            await noteDec78(waitMs: waitMs, decMs: nil, priority: priority)
            FoliaFileLog.write("cover", "native load bad status tier=\(tier) url=\(urlString)")
            return nil
        }
        // (78) 第 6 条：解码耗时单独计时（降采样＋主色同段）。
        // (83) 第 1 条取证：解码在途计数同段增减（wall.q83 读）。
        // (84) 修 b：解码段过并发闸（上限 4、按优先级出队）
        // ——此前 detached 无界，预热/预取风暴时解码堆积无账。
        let decStart = Date()
        await decodeGate84.acquire(priority: priority.rawValue)
        statLock.lock()
        decInFlight83 += 1
        statLock.unlock()
        let decoded = await Task.detached(priority: .utility) {
            (image: Self.downsample(data: data, targetPixels: tier),
             color: Self.averageColor(data: data))
        }.value
        statLock.lock()
        decInFlight83 -= 1
        statLock.unlock()
        await decodeGate84.release()
        let decMs = Int(Date().timeIntervalSince(decStart) * 1000)
        await noteDec78(waitMs: waitMs, decMs: decMs, priority: priority)
        if Date().timeIntervalSince(started) > 0.8 { noteSlowLoad() }
        if let image = decoded.image {
            // (82) 第 1 条：成本按解码像素字节（与压缩字节取大）。
            let pixelBytes = Int(image.size.width * image.scale)
                * Int(image.size.height * image.scale) * 4
            cache.setObject(image, forKey: key, cost: max(data.count, pixelBytes))
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
