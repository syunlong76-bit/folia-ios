import UIKit
import QuartzCore
import Combine

// 3.7 (62) WD 簇舞台支撑件：
//  - LyricDerivation62：协议缺口的推导层。LyricLine 冻结面无
//    isChorus / agentId / 译文字段，本层只做「能推导的推导」并
//    逐处标注近似口径，不改协议结构、不冒充真数据。
//  - StageEnergy62：无频谱数据源时的能量近似（宿主
//    requiresSpectrum=false）。以播放位置的确定性正弦混合给出
//    0...1 能量与低频量，供镜台 audioReactivity / 时计 bass /
//    花火节拍近似消费；标注为近似，不冒充真频谱。
//  - StyleSwapTransition62：样式切换转场帮助类（供 WA/集成在
//    StageVC.swapRenderer 接线；未接线前不生效，见交付报告）。

// MARK: - 协议缺口推导

enum LyricDerivation62 {

    /// 副歌近似：归一化后重复出现 ≥2 次的非空行视为副歌行
    /// （流行歌副歌重复演唱是最强信号）。单次出现的行不判。
    /// 返回副歌行 id 集合；渲染器据此触发副歌形态（cadenza 涟漪 /
    /// claddagh 辉光 / monet 副字幕轨高亮），面板标注「重复行推导」。
    static func chorusLineIds(in lines: [LyricLine]) -> Set<Int> {
        var counts: [String: Int] = [:]
        for line in lines {
            let key = normalized(line.text)
            if key.count >= 2 { counts[key, default: 0] += 1 }
        }
        var result = Set<Int>()
        for line in lines {
            let key = normalized(line.text)
            if key.count >= 2, (counts[key] ?? 0) >= 2 { result.insert(line.id) }
        }
        return result
    }

    /// 段落近似（sonnet blockIndex / songPart）：以空行样间奏行
    /// （空文本或纯省略号）与重复块边界切段，返回每行段序号。
    static func segmentIndexByLineId(in lines: [LyricLine]) -> [Int: Int] {
        var map: [Int: Int] = [:]
        var segment = 0
        var previousWasGap = true
        for line in lines {
            let isGap = normalized(line.text).isEmpty || isInterludeText(line.text)
            if isGap {
                if !previousWasGap { segment += 1 }
                map[line.id] = segment
                previousWasGap = true
            } else {
                map[line.id] = segment
                previousWasGap = false
            }
        }
        return map
    }

    static func isInterludeText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        let stripped = trimmed.filter { $0 != "." && $0 != "…" && $0 != " " }
        return stripped.isEmpty
    }

    /// 群唱发送者近似（cappella agentId）：协议无 agentId，以行序
    /// 在头像池内轮换出伪 agent 序号（0...pool-1），与渲染器既有
    /// sequencing 并存——本函数只供头像选图，不改消息左右编排。
    static func pseudoAgentIndex(lineIndex: Int, poolCount: Int) -> Int {
        guard poolCount > 0 else { return 0 }
        return ((lineIndex % poolCount) + poolCount) % poolCount
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
    }
}

// MARK: - 能量近似（无频谱数据源）

enum StageEnergy62 {

    /// 确定性伪能量：多正弦混合，周期与歌词行节奏无关、只随播放
    /// 位置变，seek 后同位置同值（可复现）。真频谱接入后替换本层。
    static func level(at position: TimeInterval) -> Double {
        let t = max(position, 0)
        let v = 0.55 + 0.25 * sin(t * 2.1) + 0.20 * sin(t * 5.7 + 1.3)
        return min(1, max(0, v))
    }

    /// 低频近似（pendolo bass / diorama 包络低频分量）。
    static func bass(at position: TimeInterval) -> Double {
        let t = max(position, 0)
        let beat = pow(max(0, sin(t * .pi * 2 * 0.85)), 3.0)
        return min(1, max(0.05, beat * 0.9 + 0.08 * sin(t * 0.7)))
    }

    /// 节拍触发近似（hanabi 节拍烟花）：以 0.85Hz 基准节拍相位
    /// 跨越整数界判触发；行首时刻额外强制触发一次（见渲染器接线）。
    static func beatPhase(at position: TimeInterval) -> Double {
        let t = max(position, 0)
        return t * 0.85 - floor(t * 0.85)
    }
}

// MARK: - 样式切换转场（待 WA/集成接线）

/// 样式切换转场帮助类：旧渲染器层快照淡出 + 新层首帧淡入。
/// 预期接线（StageViewController.swapRenderer，WA 文件域）：
/// ```
/// let transition = StyleSwapTransition62(container: rendererContainer)
/// transition.begin(oldView: renderer?.view)   // 换装前
/// // ... 旧 unmount / 新 mount ...
/// transition.finish(newView: renderer?.view)  // 换装后
/// ```
/// 未接线时本类零副作用；接线状态以交付报告标注为准，不算已落。
final class StyleSwapTransition62 {

    private let container: UIView
    private var snapshotView: UIView?

    init(container: UIView) {
        self.container = container
    }

    /// 换装前：抓旧层快照盖在容器顶层（新层在其下装配）。
    func begin(oldView: UIView?) {
        snapshotView?.removeFromSuperview()
        snapshotView = nil
        guard let oldView, oldView.superview === container,
              let snap = oldView.snapshotView(afterScreenUpdates: false) else { return }
        snap.frame = oldView.frame
        container.addSubview(snap)
        snapshotView = snap
    }

    /// 换装后：新层自 0 淡入（系统弹簧），快照同步淡出后自撤。
    func finish(newView: UIView?) {
        if let newView {
            newView.alpha = 0
            UIView.animate(withDuration: 0.45, delay: 0,
                           usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2,
                           options: [.beginFromCurrentState]) {
                newView.alpha = 1
            }
        }
        guard let snap = snapshotView else { return }
        snapshotView = nil
        UIView.animate(withDuration: 0.35, animations: { snap.alpha = 0 },
                       completion: { _ in snap.removeFromSuperview() })
        Breadcrumbs.log("stage62.swapTransition applied=1")
    }
}

// MARK: - 每首歌随机歌词动画（§6）

/// 切歌自动随机：订阅 PlaybackEngine.$currentTrack，开关开时在
/// 切歌边沿从洗牌袋（与三击轮换同袋）取下一式，写入
/// StageStyleStore.currentStyleId 并广播 .foliaStyleRandom62。
/// 舞台已打开时的实时换装需宿主订阅该通知调
/// applyNativeStyleSelection（WA 文件域，一行接线，见报告待接线项）；
/// 未打开时下次开台即按新样式（StageVC 开台读 currentStyleId）。
final class RandomStylePerSong62 {

    static let shared = RandomStylePerSong62()
    private var cancellable: AnyCancellableRef62?
    private var lastTrackId: String?
    private var started = false

    private init() {}

    func startIfNeeded() {
        guard !started else { return }
        started = true
        let box = AnyCancellableRef62()
        box.sink = PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self, let track else { return }
                guard track.id != self.lastTrackId else { return }
                let isFirst = self.lastTrackId == nil
                self.lastTrackId = track.id
                guard !isFirst else { return }
                guard SettingsStore.randomPerSongEnabled62 else { return }
                let current = StageStyleStore.currentStyleId
                guard let draw = StageStyleCycleBag.shared.next(currentStyleId: current)
                else { return }
                StageStyleStore.currentStyleId = draw.styleId
                Breadcrumbs.log("stage62.randomPerSong track=\(track.id) style=\(draw.styleId) round=\(draw.round)")
                NotificationCenter.default.post(name: .foliaStyleRandom62, object: nil)
            }
        cancellable = box
    }
}

/// Combine AnyCancellable 的简易持有盒（避免在类属性里写泛型）。
final class AnyCancellableRef62 {
    var sink: AnyCancellable?
}

extension Notification.Name {
    /// 每首歌随机已选出新样式（宿主舞台可订阅后走选样式通路）。
    static let foliaStyleRandom62 = Notification.Name("FoliaStyleRandom62")
    /// 舞台背景模式变更（选择器写入后广播，StageBackdrop62 宿主刷新）。
    static let foliaBackdropMode62Changed = Notification.Name("FoliaBackdropMode62Changed")
}
