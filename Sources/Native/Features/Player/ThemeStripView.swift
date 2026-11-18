import SpriteKit
import UIKit

/// 主题场景带（3.7 (13.4) 草地首期，DS37 定版形态）：贴在迷你台
/// 上方、与台同宽、高 104pt 的 SpriteKit 横卷。静态画味由莫奈
/// 风带图承担（Resources/ThemeArt），活物精灵 ≤10、单一 30fps
/// 行为时钟；进度即地面——地面暖光与花开由外部 fraction 驱动
/// （StageProgressDriver 回调，与台内轨道同源）。
/// 图层纪律（Miller 2026-11-18 纠正）：场景只在带内与台内轨道
/// 层，歌曲名等文字层永远压顶，场景不侵入文字区。
/// 互动（DS37 Q8）：命中只认活物与地面花丛，空白处 hitTest
/// 放行给下层（墙平移不被吞）；点活物受惊逃跑（状态机+冷却），
/// 点地面花丛散花瓣。高速飞行的鸟不可点。
final class ThemeStripView: SKView {

    private let meadowScene = MeadowScene()

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        ignoresSiblingOrder = true
        preferredFramesPerSecond = 30
        meadowScene.scaleMode = .resizeFill
        meadowScene.backgroundColor = .clear
        presentScene(meadowScene)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 进度（0–1）：地面光严格跟随；花开集合按 DS37 语义——
    /// 单曲内开过的不凋谢，seek 回退时超出部分淡出、再前进恢复。
    func setFraction(_ fraction: Double) {
        meadowScene.setFraction(fraction)
    }

    /// 切歌时由宿主下发当前曲 id：变了就重置花开集合。
    func setTrack(id: String) {
        meadowScene.setTrack(id: id)
    }

    /// 暂停请求与隐藏状态合并生效：strip 被隐藏（无当前曲）时
    /// 场景自动停转，不靠宿主另行通知（审查低危修正）。
    private var requestedPaused = true

    func setPaused(_ paused: Bool) {
        requestedPaused = paused
        applyPause()
    }

    override var isHidden: Bool {
        didSet { applyPause() }
    }

    private func applyPause() {
        let effective = requestedPaused || isHidden
        isPaused = effective
        meadowScene.isPaused = effective
    }

    /// 只有活物与地面花丛认领触摸，其余点位放行给下层视图。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, meadowScene.isInteractivePoint(point, in: self) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// 草地场景：带图打底 + 地面光/花开 + 蜂蝶鸟云 + 互动。
final class MeadowScene: SKScene {

    // MARK: 结构与素材

    private var built = false
    private var backgroundNode: SKSpriteNode?
    private var glowNode: SKSpriteNode?
    private var blooms: [(node: SKSpriteNode, fx: Double, phase: Double, bloomed: Bool)] = []
    private var clouds: [(node: SKSpriteNode, speed: CGFloat)] = []
    private var bees: [Bee] = []
    private var butterfly: Butterfly?
    private var bird: Bird?
    private var petals: [(node: SKSpriteNode, vel: CGVector, life: Double)] = []

    private var fraction: Double = 0
    private var trackId: String?
    private var lastStepTime: TimeInterval = 0
    private var elapsed: Double = 0
    private var fleeEvents: [TimeInterval] = []

    private static let groundBandHeight: CGFloat = 26

    private final class Bee {
        let node: SKSpriteNode
        var target = CGPoint.zero
        var timer: Double = 0
        var fleeUntil: TimeInterval = -1
        var cooldownUntil: TimeInterval = -1
        init(node: SKSpriteNode) { self.node = node }
    }

    private final class Butterfly {
        let node: SKSpriteNode
        var t: Double = 0
        var fleeUntil: TimeInterval = -1
        var fleePos = CGPoint.zero
        var cooldownUntil: TimeInterval = -1
        init(node: SKSpriteNode) { self.node = node }
    }

    private final class Bird {
        let node: SKSpriteNode
        var active = false
        var nextAt: Double = 5
        init(node: SKSpriteNode) { self.node = node }
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        buildIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layout()
    }

    private func buildIfNeeded() {
        guard !built else { return }
        built = true

        if let url = Bundle.main.url(forResource: "meadow-strip",
                                     withExtension: "png",
                                     subdirectory: "ThemeArt"),
           let image = UIImage(contentsOfFile: url.path) {
            let bg = SKSpriteNode(texture: SKTexture(image: image))
            bg.zPosition = -10
            addChild(bg)
            backgroundNode = bg
        }

        let glow = SKSpriteNode(texture: Self.glowTexture())
        glow.anchorPoint = CGPoint(x: 0, y: 0)
        glow.position = .zero
        glow.blendMode = .add
        glow.zPosition = -5
        addChild(glow)
        glowNode = glow

        // 地面花开点（14 个，与样片同构）
        let palettes: [(petal: UIColor, core: UIColor)] = [
            (UIColor(red: 0.886, green: 0.282, blue: 0.239, alpha: 1), UIColor(red: 1, green: 0.824, blue: 0.243, alpha: 1)),
            (UIColor(red: 0.478, green: 0.373, blue: 0.816, alpha: 1), UIColor(red: 1, green: 0.914, blue: 0.659, alpha: 1)),
            (.white, UIColor(red: 1, green: 0.71, blue: 0.18, alpha: 1)),
            (UIColor(red: 0.949, green: 0.761, blue: 0.188, alpha: 1), UIColor(red: 1, green: 0.953, blue: 0.769, alpha: 1)),
            (UIColor(red: 0.937, green: 0.498, blue: 0.69, alpha: 1), UIColor(red: 1, green: 0.941, blue: 0.965, alpha: 1)),
        ]
        for i in 0..<14 {
            let (petal, core) = palettes[i % palettes.count]
            let node = SKSpriteNode(texture: Self.flowerTexture(petal: petal, core: core))
            node.size = CGSize(width: 15, height: 15)
            node.setScale(0)
            node.zPosition = 2
            addChild(node)
            blooms.append((node, 0.045 + Double(i) / 13.0 * 0.91,
                           Double(i) * 1.37, false))
        }

        for i in 0..<2 {
            let cloud = SKSpriteNode(texture: Self.cloudTexture())
            let w: CGFloat = i == 0 ? 74 : 104
            cloud.size = CGSize(width: w, height: w * 0.32)
            cloud.zPosition = -2
            cloud.alpha = 0.85
            addChild(cloud)
            clouds.append((cloud, 1.6 + CGFloat(i) * 0.7))
            cloud.position = CGPoint(x: 60 + CGFloat(i) * 180, y: 0) // y 在 layout 里定
            cloud.userData = ["homeY": NSNumber(value: 96 - i * 9)]
        }

        for i in 0..<2 {
            let node = SKSpriteNode(texture: Self.beeTexture())
            node.size = CGSize(width: 26, height: 22)
            node.zPosition = 5
            addChild(node)
            let bee = Bee(node: node)
            bee.node.position = CGPoint(x: 70 + i * 180, y: 50 + i * 12)
            bee.target = bee.node.position
            bee.timer = 1 + Double(i)
            bees.append(bee)
        }

        let bfNode = SKSpriteNode(texture: Self.butterflyTexture())
        bfNode.size = CGSize(width: 28, height: 22)
        bfNode.zPosition = 5
        addChild(bfNode)
        butterfly = Butterfly(node: bfNode)

        let birdNode = SKSpriteNode(texture: Self.birdTexture())
        birdNode.size = CGSize(width: 30, height: 13)
        birdNode.position = CGPoint(x: -60, y: -60)
        birdNode.zPosition = 4
        addChild(birdNode)
        bird = Bird(node: birdNode)

        layout()
    }

    private func layout() {
        guard built, size.width > 0 else { return }
        backgroundNode?.size = size
        backgroundNode?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        glowNode?.size = CGSize(width: size.width, height: Self.groundBandHeight)
        applyFraction()
        for bloom in blooms {
            bloom.node.position = CGPoint(
                x: CGFloat(bloom.fx) * size.width,
                y: 6 + CGFloat(Int(bloom.fx * 977) % 5))
        }
        for cloud in clouds {
            let homeY = (cloud.node.userData?["homeY"] as? NSNumber)?.doubleValue ?? 96
            cloud.node.position.y = size.height - (104 - CGFloat(homeY)) - 8
        }
    }

    // MARK: 进度

    func setFraction(_ newFraction: Double) {
        fraction = min(max(newFraction, 0), 1)
        applyFraction()
    }

    func setTrack(id: String) {
        guard trackId != id else { return }
        trackId = id
        for i in blooms.indices where blooms[i].bloomed {
            blooms[i].bloomed = false
            blooms[i].node.removeAllActions()
            blooms[i].node.setScale(0)
        }
    }

    private func applyFraction() {
        glowNode?.xScale = CGFloat(fraction)
        for i in blooms.indices {
            let shouldBloom = fraction >= blooms[i].fx - 0.012
            if shouldBloom != blooms[i].bloomed {
                blooms[i].bloomed = shouldBloom
                blooms[i].node.removeAllActions()
                blooms[i].node.run(SKAction.scale(
                    to: shouldBloom ? 1 : 0, duration: 0.18))
            }
        }
    }

    // MARK: 行为时钟（30fps 节流）

    override func update(_ currentTime: TimeInterval) {
        guard built else { return }
        if lastStepTime == 0 { lastStepTime = currentTime; return }
        let dt = currentTime - lastStepTime
        guard dt >= 1.0 / 30.0 else { return }
        lastStepTime = currentTime
        elapsed += dt
        step(dt: min(dt, 0.05))
    }

    private func step(dt: Double) {
        let w = size.width, h = size.height
        guard w > 0 else { return }
        let groundY = Self.groundBandHeight

        for cloud in clouds {
            var x = cloud.node.position.x + cloud.speed * CGFloat(dt)
            if x > w + 60 { x = -70 }
            cloud.node.position.x = x
        }
        for bloom in blooms where bloom.bloomed {
            bloom.node.zRotation = CGFloat(sin(elapsed * 1.6 + bloom.phase)) * 0.07
        }
        for bee in bees {
            if elapsed < bee.fleeUntil {
                move(bee.node, toward: bee.target, speed: 150, dt: dt)
            } else {
                bee.timer -= dt
                if bee.timer <= 0 {
                    bee.timer = 2.2 + Double.random(in: 0..<2.4)
                    let dip = Double.random(in: 0..<1) < 0.45
                    bee.target = CGPoint(
                        x: CGFloat.random(in: 26...max(w - 26, 27)),
                        y: dip ? groundY + 2 + CGFloat.random(in: 0..<5)
                               : CGFloat.random(in: 34..<78))
                }
                move(bee.node, toward: bee.target, speed: 27, dt: dt)
                bee.node.position.y += CGFloat(sin(elapsed * 9 + bee.target.x)) * 0.3
            }
        }
        if let bf = butterfly {
            if elapsed < bf.fleeUntil {
                bf.node.position.x += (bf.fleePos.x - bf.node.position.x) * CGFloat(min(dt * 5, 1))
                bf.node.position.y += (bf.fleePos.y - bf.node.position.y) * CGFloat(min(dt * 5, 1))
            } else {
                bf.t += dt
                bf.node.position = CGPoint(
                    x: w / 2 + CGFloat(sin(bf.t * 0.45)) * 128,
                    y: 52 + CGFloat(sin(bf.t * 0.9)) * 24)
                bf.node.zRotation = CGFloat(sin(bf.t * 0.9)) * 0.14
            }
            bf.node.xScale = 0.84 + 0.16 * abs(sin(elapsed * 9))
        }
        if let bird {
            if !bird.active, elapsed > bird.nextAt {
                bird.active = true
                bird.node.position.x = -40
            }
            if bird.active {
                bird.node.position.x += 34 * CGFloat(dt)
                bird.node.position.y = h - 14 + CGFloat(sin(bird.node.position.x * 0.05)) * 3
                if bird.node.position.x > w + 40 {
                    bird.active = false
                    bird.nextAt = elapsed + Double.random(in: 9..<16)
                    bird.node.position = CGPoint(x: -60, y: -60)
                }
            }
        }
        // 花瓣：手动积分（重力+消散）。元组是值类型，必须按下标
        // 回写，闭包里改副本不会生效（花瓣会永生）。
        var pi = petals.count - 1
        while pi >= 0 {
            petals[pi].life -= dt
            if petals[pi].life <= 0 {
                petals[pi].node.removeFromParent()
                petals.remove(at: pi)
            } else {
                petals[pi].vel.dy -= 26 * CGFloat(dt)
                petals[pi].node.position.x += petals[pi].vel.dx * CGFloat(dt)
                petals[pi].node.position.y += petals[pi].vel.dy * CGFloat(dt)
                petals[pi].node.alpha = CGFloat(min(petals[pi].life / 0.35, 1))
                petals[pi].node.zRotation += CGFloat(dt) * 2.4
            }
            pi -= 1
        }
    }

    private func move(_ node: SKSpriteNode, toward target: CGPoint, speed: CGFloat, dt: Double) {
        let dx = target.x - node.position.x
        let dy = target.y - node.position.y
        let dist = hypot(dx, dy)
        guard dist > 0.5 else { return }
        let stepLen = min(speed * CGFloat(dt), dist)
        node.position.x += dx / dist * stepLen
        node.position.y += dy / dist * stepLen
    }

    // MARK: 互动（DS37 Q8）

    func isInteractivePoint(_ viewPoint: CGPoint, in view: SKView) -> Bool {
        let p = convertPoint(fromView: viewPoint)
        if critter(at: p) != nil { return true }
        return p.y <= Self.groundBandHeight && p.y >= 0
    }

    private func critter(at p: CGPoint) -> (node: SKSpriteNode, kind: String)? {
        for bee in bees where elapsed >= bee.fleeUntil {
            if hypot(p.x - bee.node.position.x, p.y - bee.node.position.y) < 17 {
                return (bee.node, "bee")
            }
        }
        if let bf = butterfly, elapsed >= bf.fleeUntil {
            if hypot(p.x - bf.node.position.x, p.y - bf.node.position.y) < 24 {
                return (bf.node, "butterfly")
            }
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let p = touch.location(in: self)
        if let hit = critter(at: p) {
            flee(node: hit.node)
        } else if p.y <= Self.groundBandHeight {
            petalBurst(at: p)
        }
    }

    /// 受惊逃跑：冷却与并发上限按 DS37（单体 6s、全局 10s 内
    /// ≤3 次、同屏 ≤2 个同时逃跑）。
    private func flee(node: SKSpriteNode) {
        fleeEvents = fleeEvents.filter { elapsed - $0 < 10 }
        guard fleeEvents.count < 3 else { return }
        let fleeingCount = bees.filter { elapsed < $0.fleeUntil }.count
            + ((butterfly.map { elapsed < $0.fleeUntil } ?? false) ? 1 : 0)
        guard fleeingCount < 2 else { return }
        let dest = CGPoint(x: CGFloat.random(in: 30...(max(size.width - 30, 31))),
                           y: CGFloat.random(in: 66..<92))
        // 逃跑时长按距离给足：150pt/s 赶不到的远距离不再 1.6s
        // 硬切回游荡（审查低危修正，「窜出一截又回头」）。
        let fleeDuration = min(max(Double(hypot(dest.x - node.position.x,
                                                dest.y - node.position.y)) / 150 + 0.6, 1.6), 3.2)
        if let bee = bees.first(where: { $0.node === node }) {
            guard elapsed >= bee.cooldownUntil else { return }
            bee.target = dest
            bee.fleeUntil = elapsed + fleeDuration
            bee.cooldownUntil = elapsed + 6
        } else if let bf = butterfly, bf.node === node {
            guard elapsed >= bf.cooldownUntil else { return }
            bf.fleePos = dest
            bf.fleeUntil = elapsed + fleeDuration
            bf.cooldownUntil = elapsed + 6
        } else { return }
        fleeEvents.append(elapsed)
    }

    private func petalBurst(at p: CGPoint) {
        let colors: [UIColor] = [
            UIColor(red: 0.886, green: 0.282, blue: 0.239, alpha: 1),
            UIColor(red: 0.478, green: 0.373, blue: 0.816, alpha: 1),
            .white,
            UIColor(red: 0.949, green: 0.761, blue: 0.188, alpha: 1),
        ]
        for i in 0..<7 {
            let node = SKSpriteNode(texture: Self.petalTexture(color: colors[i % colors.count]))
            node.size = CGSize(width: 6, height: 6)
            node.position = p
            node.zPosition = 6
            addChild(node)
            let angle = Double.random(in: 0..<(2 * Double.pi))
            let power = CGFloat.random(in: 14..<36)
            petals.append((node, CGVector(dx: cos(angle) * power,
                                          dy: abs(sin(angle)) * power + 12), 0.62))
        }
    }

    // MARK: 运行时绘制纹理（占位精灵，原生正式版换同风格绘制帧）

    private static func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    static func flowerTexture(petal: UIColor, core: UIColor) -> SKTexture {
        let img = renderer(size: CGSize(width: 24, height: 24)).image { ctx in
            let c = ctx.cgContext
            petal.setFill()
            for (dx, dy) in [(0.0, -5.6), (5.3, -1.7), (3.3, 4.6), (-3.3, 4.6), (-5.3, -1.7)] {
                c.fillEllipse(in: CGRect(x: 12 + dx - 4.1, y: 12 + dy - 4.1, width: 8.2, height: 8.2))
            }
            core.setFill()
            c.fillEllipse(in: CGRect(x: 12 - 3.1, y: 12 - 3.1, width: 6.2, height: 6.2))
        }
        return SKTexture(image: img)
    }

    static func beeTexture() -> SKTexture {
        let img = renderer(size: CGSize(width: 36, height: 30)).image { ctx in
            let c = ctx.cgContext
            UIColor.white.withAlphaComponent(0.8).setFill()
            c.fillEllipse(in: CGRect(x: 5, y: 1, width: 15, height: 9))
            UIColor.white.withAlphaComponent(0.55).setFill()
            c.fillEllipse(in: CGRect(x: 18, y: 0, width: 13, height: 8))
            let body = UIBezierPath(ovalIn: CGRect(x: 7.5, y: 11, width: 21, height: 15))
            UIColor(red: 0.961, green: 0.725, blue: 0.129, alpha: 1).setFill()
            body.fill()
            c.saveGState()
            body.addClip()
            UIColor(red: 0.29, green: 0.204, blue: 0.098, alpha: 1).setFill()
            for x in [13.5, 19.0, 24.5] { c.fill(CGRect(x: x, y: 11, width: 3.2, height: 15)) }
            c.restoreGState()
            UIColor(red: 0.169, green: 0.11, blue: 0.031, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 7.6, y: 16, width: 4, height: 4))
        }
        return SKTexture(image: img)
    }

    static func butterflyTexture() -> SKTexture {
        let img = renderer(size: CGSize(width: 40, height: 32)).image { ctx in
            let c = ctx.cgContext
            UIColor(red: 0.651, green: 0.471, blue: 0.91, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 2, y: 3, width: 18, height: 13))
            c.fillEllipse(in: CGRect(x: 20, y: 3, width: 18, height: 13))
            UIColor(red: 0.541, green: 0.361, blue: 0.839, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 5.4, y: 16, width: 14, height: 10))
            c.fillEllipse(in: CGRect(x: 20.6, y: 16, width: 14, height: 10))
            UIColor(red: 0.227, green: 0.165, blue: 0.094, alpha: 1).setFill()
            c.fill(CGRect(x: 18.4, y: 6, width: 3.2, height: 19))
        }
        return SKTexture(image: img)
    }

    static func birdTexture() -> SKTexture {
        let img = renderer(size: CGSize(width: 34, height: 14)).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 2, y: 10))
            path.addQuadCurve(to: CGPoint(x: 17, y: 9), controlPoint: CGPoint(x: 9, y: 1))
            path.addQuadCurve(to: CGPoint(x: 32, y: 10), controlPoint: CGPoint(x: 25, y: 1))
            path.lineWidth = 2.4
            path.lineCapStyle = .round
            UIColor(red: 0.2, green: 0.255, blue: 0.227, alpha: 1).setStroke()
            path.stroke()
        }
        return SKTexture(image: img)
    }

    static func cloudTexture() -> SKTexture {
        let img = renderer(size: CGSize(width: 100, height: 34)).image { ctx in
            let c = ctx.cgContext
            for (rect, alpha) in [
                (CGRect(x: 18, y: 10, width: 64, height: 18), 0.5),
                (CGRect(x: 30, y: 4, width: 40, height: 20), 0.45),
                (CGRect(x: 8, y: 14, width: 84, height: 13), 0.35),
            ] as [(CGRect, CGFloat)] {
                UIColor.white.withAlphaComponent(alpha).setFill()
                c.fillEllipse(in: rect)
            }
        }
        return SKTexture(image: img)
    }

    static func petalTexture(color: UIColor) -> SKTexture {
        let img = renderer(size: CGSize(width: 10, height: 10)).image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 1.5, y: 1.5, width: 7, height: 7))
        }
        return SKTexture(image: img)
    }

    static func glowTexture() -> SKTexture {
        let img = renderer(size: CGSize(width: 64, height: 26)).image { ctx in
            let c = ctx.cgContext
            let colors = [UIColor(red: 1, green: 0.69, blue: 0.26, alpha: 0.55).cgColor,
                          UIColor(red: 1, green: 0.69, blue: 0.26, alpha: 0.14).cgColor,
                          UIColor(red: 1, green: 0.69, blue: 0.26, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 0.7, 1]) {
                c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 26),
                                     end: CGPoint(x: 0, y: 0), options: [])
            }
        }
        return SKTexture(image: img)
    }
}
