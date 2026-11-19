import UIKit

/// 播放页角落陪伴宠物（3.7 (24)，纯新增；规格 = scene-mapping.md
/// 「陪伴池规格」终版口径，Miller 2026-11-19 03:07 定）：
/// - 自主漫游：只在宿主给定的边缘区域（region 的周界）移动，
///   不进中央、不遮歌词与控件（region 由舞台页给到歌词容器
///   范围，周界即其四边内侧）。
/// - 点按反应：本体帧重播 + 位移小跳——只用素材本体帧与位移
///   变换，不新增绘制、不改帧（互动红线）。
/// - 可拖动：拖到任意位置松手后吸附到最近的周界点。
/// - 长按收起：收起状态持久化（StickerSettings），设置页贴纸
///   分区可重新放出。
/// - 轮换：每首歌随机换一只（同首不换）；cat-09 每约 5 首从
///   右缘客串滑过一次（彩蛋密度宁低勿高）。
final class CompanionPetView: UIView {

    static let petSize: CGFloat = 72

    /// 漫游区域（宿主坐标系，即本视图在父视图中的活动范围）。
    var roamRegion: CGRect = .zero {
        didSet {
            if roamRegion != oldValue, !isDragging {
                clampCenterToPerimeter()
            }
        }
    }
    /// 长按收起时回调（宿主可据此落面包屑/刷新设置页开关）。
    var onDismissedByLongPress: (() -> Void)?

    private let stickerView = StickerView()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var targetCorner = 0
    private var idleUntil: CFTimeInterval = 0
    private var isDragging = false
    private var dragOffset: CGPoint = .zero
    private var roaming = false

    private let pool = ["dog-01", "dog-15", "dog-18", "dog-19", "dog-25", "dog-23"]
    private var currentPoolIndex = 0
    private var lastTrackId: String?
    private var trackChangeCount = 0
    private var cameoView: StickerView?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.petSize, height: Self.petSize))
        stickerView.showsTileBackground = true
        stickerView.frame = bounds
        stickerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(stickerView)
        stickerView.setSticker(pool[0], mode: .loop)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.55
        addGestureRecognizer(longPress)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - 生命周期（宿主驱动）

    func startRoaming() {
        guard StickerSettings.companionEnabled else {
            isHidden = true
            return
        }
        isHidden = false
        roaming = true
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = false
        if roamRegion != .zero, !isDragging {
            clampCenterToPerimeter()
        }
    }

    func stopRoaming() {
        roaming = false
        displayLink?.isPaused = true
        lastTimestamp = 0
    }

    /// 切歌轮换（宿主在曲目变化时调用；同首重复调用不换）。
    func setTrack(id: String) {
        guard id != lastTrackId else { return }
        lastTrackId = id
        trackChangeCount += 1
        if trackChangeCount % 5 == 0 {
            playCameo()
        }
        var next = currentPoolIndex
        if pool.count > 1 {
            while next == currentPoolIndex {
                next = Int.random(in: 0..<pool.count)
            }
        }
        currentPoolIndex = next
        stickerView.setSticker(pool[next], mode: .loop)
    }

    // MARK: - 漫游

    /// 中心活动范围（region 内缩半个身位后的周界矩形）。
    private var centerRect: CGRect {
        roamRegion.insetBy(dx: Self.petSize / 2, dy: Self.petSize / 2)
    }

    private func perimeterPoint(_ t: CGFloat) -> CGPoint {
        // t ∈ [0,1) 沿周界（自左上顺时针）。
        let r = centerRect
        guard r.width > 0, r.height > 0 else { return center }
        let perimeter = 2 * (r.width + r.height)
        var d = (t.truncatingRemainder(dividingBy: 1)) * perimeter
        if d < 0 { d += perimeter }
        if d < r.width {
            return CGPoint(x: r.minX + d, y: r.minY)
        }
        d -= r.width
        if d < r.height {
            return CGPoint(x: r.maxX, y: r.minY + d)
        }
        d -= r.height
        if d < r.width {
            return CGPoint(x: r.maxX - d, y: r.maxY)
        }
        d -= r.width
        return CGPoint(x: r.minX, y: r.maxY - d)
    }

    private var perimeterT: CGFloat = 0.75 // 初始：底边中点附近

    private func clampCenterToPerimeter() {
        guard roamRegion != .zero else { return }
        center = perimeterPoint(perimeterT)
    }

    private func nearestPerimeterT(to point: CGPoint) -> CGFloat {
        // 在周界上采样找最近点（采样 200 点，足够平滑）。
        var bestT: CGFloat = perimeterT
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 0...200 {
            let t = CGFloat(i) / 200
            let p = perimeterPoint(t)
            let dist = hypot(p.x - point.x, p.y - point.y)
            if dist < bestDist {
                bestDist = dist
                bestT = t
            }
        }
        return bestT
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard roaming, !isDragging, roamRegion != .zero, !isHidden else {
            lastTimestamp = 0
            return
        }
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }
        let dt = min(link.timestamp - lastTimestamp, 0.05)
        lastTimestamp = link.timestamp
        if link.timestamp < idleUntil { return }
        let r = centerRect
        let perimeter = 2 * (r.width + r.height)
        guard perimeter > 0 else { return }
        let speed: CGFloat = 15 // pt/s，慢速陪伴不抢眼
        perimeterT += CGFloat(dt) * speed / perimeter
        if perimeterT >= 1 {
            perimeterT -= 1
            // 每绕完一圈随机停歇一次。
            if Bool.random() {
                idleUntil = link.timestamp + Double.random(in: 2...5)
            }
        }
        // 到达四个角点附近时小概率停歇。
        let cornerTs: [CGFloat] = [0, r.width / perimeter,
                                   (r.width + r.height) / perimeter,
                                   (2 * r.width + r.height) / perimeter]
        for corner in cornerTs {
            if abs(perimeterT - corner) < 0.002, Double.random() < 0.3 {
                idleUntil = link.timestamp + Double.random(in: 1.5...4)
            }
        }
        center = perimeterPoint(perimeterT)
    }

    // MARK: - 手势

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        let location = gesture.location(in: superview)
        switch gesture.state {
        case .began:
            isDragging = true
            dragOffset = CGPoint(x: center.x - location.x, y: center.y - location.y)
        case .changed:
            var target = CGPoint(x: location.x + dragOffset.x,
                                 y: location.y + dragOffset.y)
            target.x = min(max(target.x, roamRegion.minX + 10),
                           roamRegion.maxX - 10)
            target.y = min(max(target.y, roamRegion.minY + 10),
                           roamRegion.maxY - 10)
            center = target
        case .ended, .cancelled:
            isDragging = false
            perimeterT = nearestPerimeterT(to: center)
            let snapped = perimeterPoint(perimeterT)
            UIView.animate(withDuration: 0.35, delay: 0,
                           usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3,
                           options: [.curveEaseOut]) {
                self.center = snapped
            }
            idleUntil = CACurrentMediaTime() + 1.2
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // 反应只用本体帧（重播）+ 位移（小跳），不自编动作。
        stickerView.restart()
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut]) {
            self.transform = CGAffineTransform(translationX: 0, y: -10)
        } completion: { _ in
            UIView.animate(withDuration: 0.45, delay: 0,
                           usingSpringWithDamping: 0.55, initialSpringVelocity: 0.4,
                           options: [.curveEaseOut]) {
                self.transform = .identity
            }
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        StickerSettings.companionEnabled = false
        stopRoaming()
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn]) {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            self.isHidden = true
            self.alpha = 1
            self.transform = .identity
        }
        onDismissedByLongPress?()
    }

    // MARK: - cat-09 客串（每约 5 首从右缘滑过一次）

    private func playCameo() {
        guard let superview, roamRegion != .zero, cameoView == nil else { return }
        let size: CGFloat = 64
        let cameo = StickerView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        cameo.center = CGPoint(x: roamRegion.maxX + size,
                               y: roamRegion.minY + roamRegion.height * 0.35)
        cameo.setSticker("cat-09", mode: .loop)
        superview.addSubview(cameo)
        cameoView = cameo
        UIView.animate(withDuration: 4.2, delay: 0.4, options: [.curveLinear]) {
            cameo.center = CGPoint(x: self.roamRegion.minX - size,
                                   y: cameo.center.y)
        } completion: { _ in
            cameo.removeFromSuperview()
            if self.cameoView === cameo { self.cameoView = nil }
        }
    }
}
