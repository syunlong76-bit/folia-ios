import UIKit
import QuartzCore

// 汪汪队开大会（3.7 (53) J）：手绘贴纸风幕布与灯光（v3 定版）。
//
// 程序绘制（CAShapeLayer/UIBezierPath），无图片素材：
//  - 底景：深紫渐变 + 中央柔光 + 星点 + 奶油舞台板（透视横纹）
//    + 独唱位金色脚圈，静态一层绘制（PetConcertBackdropView）。
//  - 侧幕：粉色立幕，内缘按 v3 波形呼吸摆动；奶油镶边 + 褶皱
//    条纹 + 底边 scallop；开幕 1.35s easeOutBack 弹性拉开。
//  - 垂幔：7 扇 scallop 垂幔（粉底 + 奶油面）+ 流苏圆点 +
//    星星/爱心/爪印点缀，点缀低频错峰闪烁（缩放脉动）。
//  - 脚灯：11 盏圆点脚灯，逐盏错相脉动。
//  - 追光：光锥 + 脚下光池 + 身周柔光，逐帧跟随独唱者贝塞尔
//    位置；无独唱者时按 v3 口径在中场缓摆。
//  - 洗光：整场染色随相位（前奏紫/轮唱暖金/间奏蓝紫振荡/
//    告别转暖），间奏另有三束摇摆光束与五彩纸屑——氛围层，
//    降级顺序最先砍（atmosphereReduced），歌词可读性永不砍。
//
// 更新节流：路径类（幕布/垂幔/点缀）以 15Hz 重算，追光/洗光
// 逐帧跟随（仅属性赋值）。坐标一律先在参考画布 1080×1920
// 里算，再 × (bounds/参考) 换算。

enum PetConcertPalette {
    static let outline = UIColor(red: 110/255, green: 74/255, blue: 47/255, alpha: 1)
    static let cream = UIColor(red: 253/255, green: 243/255, blue: 227/255, alpha: 1)
    static let cream2 = UIColor(red: 251/255, green: 238/255, blue: 214/255, alpha: 1)
    static let pink = UIColor(red: 247/255, green: 200/255, blue: 211/255, alpha: 1)
    static let pinkDeep = UIColor(red: 238/255, green: 165/255, blue: 184/255, alpha: 1)
    static let pinkFold = UIColor(red: 242/255, green: 184/255, blue: 197/255, alpha: 1)
    static let pinkFoldHi = UIColor(red: 249/255, green: 215/255, blue: 222/255, alpha: 1)
    static let peach = UIColor(red: 255/255, green: 217/255, blue: 176/255, alpha: 1)
    static let mint = UIColor(red: 191/255, green: 232/255, blue: 216/255, alpha: 1)
    static let lav = UIColor(red: 217/255, green: 205/255, blue: 242/255, alpha: 1)
    static let sky = UIColor(red: 190/255, green: 220/255, blue: 245/255, alpha: 1)
    static let gold = UIColor(red: 243/255, green: 197/255, blue: 92/255, alpha: 1)
    static let decoColors: [UIColor] = [mint, lav, peach, sky, pinkDeep, gold]
    static let backdropTop = UIColor(red: 46/255, green: 33/255, blue: 66/255, alpha: 1)
    static let backdropBottom = UIColor(red: 30/255, green: 22/255, blue: 48/255, alpha: 1)
    static let floorA = UIColor(red: 247/255, green: 227/255, blue: 195/255, alpha: 1)
    static let floorB = UIColor(red: 243/255, green: 214/255, blue: 174/255, alpha: 1)
    static let floorLine = UIColor(red: 196/255, green: 164/255, blue: 120/255, alpha: 1)
    static let bubbleFill = UIColor(red: 255/255, green: 250/255, blue: 238/255, alpha: 1)
    static let bubbleText = UIColor(red: 62/255, green: 45/255, blue: 32/255, alpha: 1)
}

// MARK: - 静态底景（渐变/柔光/星点/舞台板/脚圈）

final class PetConcertBackdropView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let w = bounds.width, h = bounds.height
        let sx = w / PetConcertConst.refW, sy = h / PetConcertConst.refH
        // 深紫竖向渐变。
        let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [PetConcertPalette.backdropTop.cgColor,
                     PetConcertPalette.backdropBottom.cgColor] as CFArray,
            locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: .zero,
                               end: CGPoint(x: 0, y: h), options: [])
        // 中央柔光（径向，白紫低 alpha）。
        let glowCenter = CGPoint(x: w / 2, y: 710 * sy)
        let glow = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor(red: 120/255, green: 100/255, blue: 170/255,
                             alpha: 0.20).cgColor,
                     UIColor.clear.cgColor] as CFArray,
            locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0,
                               endCenter: glowCenter, endRadius: 460 * sx,
                               options: [.drawsAfterEndLocation])
        // 星点（种子固定 110 颗）。
        var rng = ConcertRNG(seed: 7)
        UIColor(red: 235/255, green: 228/255, blue: 255/255, alpha: 1).setFill()
        for _ in 0..<110 {
            let x = CGFloat(rng.next(in: 0...Double(PetConcertConst.refW))) * sx
            let y = CGFloat(rng.next(in: 0...1500)) * sy
            let r = CGFloat(rng.next(in: 1.5...4)) * sx
            let a = rng.next(in: 0.14...0.39)
            UIColor(red: 235/255, green: 228/255, blue: 255/255,
                    alpha: CGFloat(a)).setFill()
            UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r,
                                        width: r * 2, height: r * 2)).fill()
        }
        // 奶油舞台板：9 带透视横纹（y 边按 (i/9)^1.35 收分）。
        let y0 = PetConcertConst.floorTopY * sy, y1 = h
        var edges: [CGFloat] = []
        for i in 0...9 {
            edges.append(y0 + (y1 - y0) * pow(CGFloat(i) / 9, 1.35))
        }
        for i in 0..<9 {
            (i % 2 == 0 ? PetConcertPalette.floorA
                : PetConcertPalette.floorB).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: edges[i], width: w,
                                      height: edges[i + 1] - edges[i])).fill()
            PetConcertPalette.floorLine.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: edges[i], width: w,
                                      height: max(1, 3 * sy))).fill()
        }
        // 独唱位金色脚圈（双圈）。
        let ringCenter = CGPoint(x: PetConcertConst.soloX * sx,
                                 y: PetConcertConst.soloRingY * sy)
        let ringRect = CGRect(x: ringCenter.x - 152 * sx,
                              y: ringCenter.y - 34 * sy,
                              width: 304 * sx, height: 68 * sy)
        let ring = UIBezierPath(ovalIn: ringRect)
        ring.lineWidth = 11 * sx
        UIColor(red: 240/255, green: 203/255, blue: 120/255, alpha: 1).setStroke()
        ring.stroke()
        let ring2 = UIBezierPath(ovalIn: ringRect)
        ring2.lineWidth = 4 * sx
        UIColor(red: 255/255, green: 224/255, blue: 148/255, alpha: 1).setStroke()
        ring2.stroke()
    }
}

// MARK: - 点缀图形（星星/爱心/爪印，UIBezierPath 程序绘制）

enum PetConcertDeco {
    static func starPath(center: CGPoint, size: CGFloat, rotation: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for i in 0..<10 {
            let ang = rotation + CGFloat(i) * .pi / 5 - .pi / 2
            let rad = i % 2 == 0 ? size : size * 0.48
            let p = CGPoint(x: center.x + rad * cos(ang),
                            y: center.y + rad * sin(ang))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.close()
        return path
    }

    static func heartPath(center: CGPoint, size: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for i in 0...40 {
            let u = CGFloat(i) / 40 * 2 * .pi
            let x = 16 * pow(sin(u), 3)
            let y = 13 * cos(u) - 5 * cos(2 * u) - 2 * cos(3 * u) - cos(4 * u)
            let p = CGPoint(x: center.x + x * size / 17,
                            y: center.y - y * size / 17)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.close()
        return path
    }

    static func pawPath(center: CGPoint, size: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let main = CGRect(x: center.x - size * 0.52, y: center.y - size * 0.05,
                          width: size * 1.04, height: size * 0.80)
        path.append(UIBezierPath(ovalIn: main))
        let toes: [(CGFloat, CGFloat, CGFloat)] = [
            (-0.62, -0.42, 0.30), (-0.21, -0.62, 0.32),
            (0.21, -0.62, 0.32), (0.62, -0.42, 0.30),
        ]
        for (dx, dy, rr) in toes {
            let r = rr * size
            path.append(UIBezierPath(ovalIn: CGRect(
                x: center.x + dx * size - r / 2, y: center.y + dy * size - r / 2,
                width: r, height: r)))
        }
        return path
    }

    static func path(kind: Int, center: CGPoint, size: CGFloat,
                     rotation: CGFloat) -> UIBezierPath {
        switch kind {
        case 0: return starPath(center: center, size: size, rotation: rotation)
        case 1: return heartPath(center: center, size: size)
        default: return pawPath(center: center, size: size)
        }
    }
}

// MARK: - 动态幕布/灯光层

final class PetConcertCurtainView: UIView {

    /// 氛围降级（内存警告/降级链触发）：关光束与纸屑、停闪烁，
    /// 幕布摆动与追光保留（身份特征 + 便宜）。
    var atmosphereReduced = false

    private let washView = UIView()
    private var beamLayers: [CAShapeLayer] = []
    private let coneLayer = CAShapeLayer()
    private let poolView = UIImageView()
    private let haloView = UIImageView()
    private var sideFill: [CAShapeLayer] = []     // L/R
    private var sideFold: [[CAShapeLayer]] = []   // L/R × 3
    private var sideHem: [CAShapeLayer] = []
    private var sideEdge: [CAShapeLayer] = []
    private var valancePink = CAShapeLayer()
    private var valanceCream = CAShapeLayer()
    private var valanceEdge = CAShapeLayer()
    private var tasselLayer = CAShapeLayer()
    private var decoLayers: [CAShapeLayer] = []
    private var footGlowLayers: [CAShapeLayer] = []
    private var footCoreLayer = CAShapeLayer()
    private var confettiLayers: [CALayer] = []

    private struct DecoSpec {
        var kind: Int
        var x: CGFloat      // 垂幔点缀：参考 px；侧幕点缀：横向分数
        var y: CGFloat
        var size: CGFloat
        var color: UIColor
        var phase: Double
        var onValance: Bool
    }
    private var decos: [DecoSpec] = []
    private var lastPathUpdate: TimeInterval = -1
    private var confetti: [(layer: CALayer, x0: CGFloat, y0: CGFloat,
                            vy: CGFloat, phase: Double, size: CGFloat,
                            rotV: Double)] = []
    private var confettiBursts: [TimeInterval] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        buildLayers()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func buildLayers() {
        washView.isUserInteractionEnabled = false
        addSubview(washView)
        for _ in 0..<3 {
            let beam = CAShapeLayer()
            beam.fillColor = UIColor.white.cgColor
            layer.addSublayer(beam)
            beamLayers.append(beam)
        }
        // 追光：光池（径向渐变贴图）→ 身周柔光 → 光锥。
        poolView.image = Self.radialGlowImage()
        poolView.isUserInteractionEnabled = false
        addSubview(poolView)
        haloView.image = Self.radialGlowImage()
        haloView.isUserInteractionEnabled = false
        addSubview(haloView)
        coneLayer.fillColor = UIColor(red: 255/255, green: 238/255,
                                      blue: 190/255, alpha: 0.26).cgColor
        layer.addSublayer(coneLayer)
        // 侧幕。
        for _ in 0..<2 {
            let fill = CAShapeLayer()
            fill.fillColor = PetConcertPalette.pink.cgColor
            layer.addSublayer(fill)
            sideFill.append(fill)
            var folds: [CAShapeLayer] = []
            for f in 0..<3 {
                let fold = CAShapeLayer()
                fold.fillColor = nil
                fold.strokeColor = (f % 2 == 0 ? PetConcertPalette.pinkFold
                    : PetConcertPalette.pinkFoldHi).cgColor
                fold.lineCap = .round
                layer.addSublayer(fold)
                folds.append(fold)
            }
            sideFold.append(folds)
            let hem = CAShapeLayer()
            hem.fillColor = nil
            hem.strokeColor = PetConcertPalette.cream.cgColor
            hem.lineCap = .round
            layer.addSublayer(hem)
            sideHem.append(hem)
            let edge = CAShapeLayer()
            edge.fillColor = nil
            edge.strokeColor = PetConcertPalette.outline.cgColor
            edge.lineCap = .round
            layer.addSublayer(edge)
            sideEdge.append(edge)
        }
        // 垂幔。
        valancePink.fillColor = PetConcertPalette.pink.cgColor
        layer.addSublayer(valancePink)
        valanceCream.fillColor = PetConcertPalette.cream.cgColor
        layer.addSublayer(valanceCream)
        valanceEdge.fillColor = nil
        valanceEdge.strokeColor = PetConcertPalette.outline.cgColor
        valanceEdge.lineCap = .round
        layer.addSublayer(valanceEdge)
        tasselLayer.fillColor = PetConcertPalette.peach.cgColor
        tasselLayer.strokeColor = PetConcertPalette.outline.cgColor
        layer.addSublayer(tasselLayer)
        // 点缀规格（v3 VAL_DECOS 13 + SIDE_DECOS 9，种子 42）。
        var rng = ConcertRNG(seed: 42)
        for i in 0..<13 {
            decos.append(DecoSpec(
                kind: i % 3,
                x: 70 + CGFloat(i) * 78 + CGFloat(rng.next(in: -16...16)),
                y: CGFloat(rng.next(in: 42...138)),
                size: CGFloat(rng.next(in: 15...24)),
                color: PetConcertPalette.decoColors[i % 6],
                phase: rng.next(in: 0...(2 * Double.pi)), onValance: true))
        }
        for i in 0..<9 {
            decos.append(DecoSpec(
                kind: (i + 1) % 3,
                x: 0.16 + 0.68 * CGFloat((i * 37) % 10) / 9,
                y: 300 + CGFloat(i) * 148,
                size: CGFloat(rng.next(in: 15...23)),
                color: PetConcertPalette.decoColors[(i + 2) % 6],
                phase: rng.next(in: 0...(2 * Double.pi)), onValance: false))
        }
        for spec in decos {
            let deco = CAShapeLayer()
            deco.fillColor = spec.color.cgColor
            deco.strokeColor = PetConcertPalette.outline.cgColor
            layer.addSublayer(deco)
            decoLayers.append(deco)
        }
        // 脚灯。
        for _ in 0..<PetConcertConst.footlightCount {
            let glow = CAShapeLayer()
            glow.fillColor = UIColor(red: 255/255, green: 220/255,
                                     blue: 140/255, alpha: 0.18).cgColor
            layer.addSublayer(glow)
            footGlowLayers.append(glow)
        }
        footCoreLayer.fillColor = UIColor(red: 255/255, green: 243/255,
                                          blue: 207/255, alpha: 1).cgColor
        footCoreLayer.strokeColor = PetConcertPalette.outline.cgColor
        layer.addSublayer(footCoreLayer)
        // 纸屑（间奏氛围，60 片上限，复用图层）。
        var crng = ConcertRNG(seed: 99)
        for _ in 0..<60 {
            let piece = CALayer()
            piece.backgroundColor = PetConcertPalette
                .decoColors[Int(crng.next(in: 0...5))].cgColor
            piece.cornerRadius = 2
            piece.isHidden = true
            layer.addSublayer(piece)
            confettiLayers.append(piece)
            confetti.append((piece,
                             CGFloat(crng.next(in: 140...940)),
                             CGFloat(crng.next(in: -60...260)),
                             CGFloat(crng.next(in: 250...430)),
                             crng.next(in: 0...(2 * Double.pi)),
                             CGFloat(crng.next(in: 7...14)),
                             crng.next(in: 1.5...3.2)))
        }
    }

    private static func radialGlowImage() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let ctx = context.cgContext
            let grad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(red: 255/255, green: 244/255, blue: 200/255,
                                 alpha: 0.85).cgColor,
                         UIColor.clear.cgColor] as CFArray,
                locations: [0, 1])!
            let center = CGPoint(x: 128, y: 128)
            ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: 128,
                                   options: [])
        }
    }

    /// 间奏开始时由渲染方登记两次纸屑爆发时刻。
    func scheduleConfetti(bursts: [TimeInterval]) {
        confettiBursts = bursts
    }

    // MARK: 逐帧更新

    /// - singerPos: 独唱者当前中心（本视图坐标）；nil 时追光中场缓摆。
    /// - singerFeetY: 独唱者脚底 y（本视图坐标）。
    func update(t: TimeInterval, phase: ConcertPhase,
                params: (amp: Double, freq: Double,
                         twinkleFreq: Double, twinkleAmp: Double),
                singerPos: CGPoint?, singerFeetY: CGFloat?,
                interludeIntensity: Double) {
        let w = bounds.width, h = bounds.height
        guard w > 0 else { return }
        let sx = w / PetConcertConst.refW, sy = h / PetConcertConst.refH

        // 洗光（逐帧，仅颜色赋值）。
        washView.frame = bounds
        washView.backgroundColor = washColor(t: t, phase: phase,
                                             intensity: interludeIntensity)

        // 追光（逐帧跟随）。
        let target: CGPoint
        if let singerPos {
            target = singerPos
        } else {
            target = CGPoint(x: (540 + 180 * sin(0.5 * t)) * sx, y: 980 * sy)
        }
        let apex = CGPoint(x: w / 2, y: 40 * sy)
        let cone = UIBezierPath()
        cone.move(to: CGPoint(x: apex.x - 11 * sx, y: apex.y))
        cone.addLine(to: CGPoint(x: apex.x + 11 * sx, y: apex.y))
        cone.addLine(to: CGPoint(x: target.x + 108 * sx, y: target.y + 60 * sy))
        cone.addLine(to: CGPoint(x: target.x - 108 * sx, y: target.y + 60 * sy))
        cone.close()
        coneLayer.path = cone.cgPath
        let feetY = singerFeetY ?? (1490 * sy)
        poolView.frame = CGRect(x: target.x - 130 * sx, y: feetY - 26 * sy,
                                width: 260 * sx, height: 52 * sy)
        poolView.alpha = 0.55
        haloView.frame = CGRect(x: target.x - 105 * sx, y: target.y - 80 * sy,
                                width: 210 * sx, height: 160 * sy)
        haloView.alpha = 0.35

        // 路径类 15Hz 节流。
        guard t - lastPathUpdate >= 1.0 / 15.0 || lastPathUpdate < 0 else { return }
        lastPathUpdate = t
        updateCurtains(t: t, params: params, sx: sx, sy: sy)
        updateBeams(t: t, params: params, phase: phase, sx: sx, sy: sy)
        updateFootlights(t: t, sx: sx, sy: sy)
        updateConfetti(t: t, sx: sx, sy: sy)
    }

    private func washColor(t: TimeInterval, phase: ConcertPhase,
                           intensity: Double) -> UIColor {
        switch phase {
        case .dropping, .formation:
            return UIColor(red: 168/255, green: 158/255, blue: 220/255, alpha: 0.08)
        case .preludeChat, .singing1, .singing2:
            return UIColor(red: 255/255, green: 206/255, blue: 120/255, alpha: 0.10)
        case .interlude:
            let u = CGFloat(0.5 + 0.5 * sin(t * 1.4)) * CGFloat(intensity)
            return UIColor(red: (110 + 90 * u) / 255, green: (160 - 10 * u) / 255,
                           blue: 1, alpha: 0.11)
        case .farewell, .ended:
            return UIColor(red: 255/255, green: 176/255, blue: 160/255, alpha: 0.09)
        }
    }

    /// 开幕进度（easeOutBack，1.35s）。
    private func curtainOpenU(t: TimeInterval) -> CGFloat {
        if t >= PetConcertConst.curtainOpenDuration { return 1 }
        let u = max(0, t / PetConcertConst.curtainOpenDuration)
        let c1 = PetConcertConst.curtainOpenBackC1
        let c3 = c1 + 1
        let v = 1 + c3 * pow(u - 1, 3) + c1 * pow(u - 1, 2)
        return CGFloat(v)
    }

    private func innerX(y: CGFloat, t: TimeInterval,
                        params: (amp: Double, freq: Double,
                                 twinkleFreq: Double, twinkleAmp: Double),
                        openU: CGFloat) -> CGFloat {
        let xin = PetConcertConst.curtainClosedX
            + (PetConcertConst.curtainOpenX - PetConcertConst.curtainClosedX) * openU
        let wave = PetConcertConst.swayAmpA
            * sin(y * 0.010 + CGFloat(1.1 * t * params.freq))
            + PetConcertConst.swayAmpB
            * sin(y * 0.023 - CGFloat(0.7 * t * params.freq))
        return xin + CGFloat(params.amp) * wave
    }

    private func updateCurtains(
        t: TimeInterval,
        params: (amp: Double, freq: Double, twinkleFreq: Double, twinkleAmp: Double),
        sx: CGFloat, sy: CGFloat
    ) {
        let w = bounds.width
        let openU = curtainOpenU(t: t)
        let outer: CGFloat = -60
        var ys: [CGFloat] = []
        var y: CGFloat = 168
        while y <= 1568 { ys.append(y); y += 70 }

        for side in 0..<2 { // 0 = 左，1 = 右（镜像）
            let mirror: (CGFloat) -> CGFloat = { side == 0 ? $0 : PetConcertConst.refW - $0 }
            let edge: [CGPoint] = ys.map {
                CGPoint(x: mirror(innerX(y: $0, t: t, params: params, openU: openU)),
                        y: $0)
            }
            // 底边 scallop 回到外缘。
            var poly: [CGPoint] = [CGPoint(x: mirror(outer), y: 150)]
            poly += edge
            let bx0 = innerX(y: 1568, t: t, params: params, openU: openU)
            for i in 1...12 {
                let u = CGFloat(i) / 12
                let bx = bx0 + (outer - bx0) * u
                let by = 1568 + 26 * sin(u * .pi * 3) * (1 - u * 0.3)
                poly.append(CGPoint(x: mirror(bx), y: by))
            }
            poly.append(CGPoint(x: mirror(outer), y: 1610))
            let path = UIBezierPath()
            for (i, p) in poly.enumerated() {
                let pt = CGPoint(x: p.x * sx, y: p.y * sy)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.close()
            sideFill[side].path = path.cgPath
            // 褶皱条纹（跟随波形、按开合压缩）。
            let xin = PetConcertConst.curtainClosedX
                + (PetConcertConst.curtainOpenX - PetConcertConst.curtainClosedX) * openU
            for (f, frac) in [0.22, 0.45, 0.68].enumerated() {
                let line = UIBezierPath()
                for (i, yy) in ys.enumerated() {
                    let ix = innerX(y: yy, t: t, params: params, openU: openU)
                    let fx = outer + (ix - outer) * CGFloat(frac)
                    let pt = CGPoint(x: mirror(fx) * sx, y: yy * sy)
                    if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                }
                sideFold[side][f].path = line.cgPath
                sideFold[side][f].lineWidth = 15 * sx
            }
            _ = xin
            // 奶油镶边 + 棕色轮廓（沿内缘 + 底边）。
            let hem = UIBezierPath()
            let edgeLine = UIBezierPath()
            for (i, p) in edge.enumerated() {
                let hemPt = CGPoint(x: (p.x + (side == 0 ? 12 : -12)) * sx, y: p.y * sy)
                let edgePt = CGPoint(x: p.x * sx, y: p.y * sy)
                if i == 0 { hem.move(to: hemPt); edgeLine.move(to: edgePt) }
                else { hem.addLine(to: hemPt); edgeLine.addLine(to: edgePt) }
            }
            for i in 1...12 {
                let u = CGFloat(i) / 12
                let bx = bx0 + (outer - bx0) * u
                let by = 1568 + 26 * sin(u * .pi * 3) * (1 - u * 0.3)
                edgeLine.addLine(to: CGPoint(x: mirror(bx) * sx, y: by * sy))
            }
            sideHem[side].path = hem.cgPath
            sideHem[side].lineWidth = 13 * sx
            sideEdge[side].path = edgeLine.cgPath
            sideEdge[side].lineWidth = 6 * sx
        }

        // 垂幔：7 扇 scallop。
        let n = PetConcertConst.valanceSwags
        let sw = PetConcertConst.refW / CGFloat(n)
        let base = PetConcertConst.valanceBaseY
        let depth = PetConcertConst.valanceDepth
        func scallopEdge(offsetY: CGFloat) -> [CGPoint] {
            var pts: [CGPoint] = []
            let steps = 8
            for i in 0..<n {
                for j in 0...steps {
                    let u = CGFloat(j) / CGFloat(steps)
                    let x = CGFloat(i) * sw + u * sw
                    let dip = sin(u * .pi) * depth
                    let sway = CGFloat(params.amp) * 4
                        * sin(CGFloat(0.9 * t * params.freq) + CGFloat(i) * 1.1)
                    pts.append(CGPoint(x: x, y: base + dip + sway + offsetY))
                }
            }
            return pts
        }
        func bandPath(offsetY: CGFloat) -> UIBezierPath {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: -20 * sx, y: -10 * sy))
            path.addLine(to: CGPoint(x: (PetConcertConst.refW + 20) * sx, y: -10 * sy))
            for p in scallopEdge(offsetY: offsetY).reversed() {
                path.addLine(to: CGPoint(x: p.x * sx, y: p.y * sy))
            }
            path.close()
            return path
        }
        valancePink.path = bandPath(offsetY: 0).cgPath
        valanceCream.path = bandPath(offsetY: -30).cgPath
        let edgePath = UIBezierPath()
        for (i, p) in scallopEdge(offsetY: 0).enumerated() {
            let pt = CGPoint(x: p.x * sx, y: p.y * sy)
            if i == 0 { edgePath.move(to: pt) } else { edgePath.addLine(to: pt) }
        }
        valanceEdge.path = edgePath.cgPath
        valanceEdge.lineWidth = 6 * sx
        // 流苏圆点（扇接点）。
        let tassels = UIBezierPath()
        for i in 0...n {
            let x = CGFloat(i) * sw
            let yy = base + CGFloat(params.amp) * 4
                * sin(CGFloat(0.9 * t * params.freq) + CGFloat(i) * 1.1)
            tassels.append(UIBezierPath(ovalIn: CGRect(
                x: (x - 8) * sx, y: (yy + 14) * sy,
                width: 16 * sx, height: 16 * sy)))
        }
        tasselLayer.path = tassels.cgPath
        tasselLayer.lineWidth = 3 * sx

        // 点缀（位置随幕布开合/波形，缩放错峰闪烁）。
        let twinkleAmp = atmosphereReduced ? 0 : params.twinkleAmp
        for (index, spec) in decos.enumerated() {
            let decoLayer = decoLayers[index]
            let scale = 1 + CGFloat(twinkleAmp)
                * sin(CGFloat(params.twinkleFreq) * CGFloat(t) + CGFloat(spec.phase))
            let size = spec.size * scale
            let center: CGPoint
            if spec.onValance {
                center = CGPoint(x: spec.x * sx, y: spec.y * sy)
            } else {
                // 侧幕点缀：横向分数落在当前幕布宽度内，左右各一份
                // 用同一图层画两侧（path 内含两形）。
                let xin = PetConcertConst.curtainClosedX
                    + (PetConcertConst.curtainOpenX - PetConcertConst.curtainClosedX) * openU
                let lx = outer + (xin - outer) * spec.x
                    + CGFloat(params.amp) * 4
                    * sin(spec.y * 0.010 + CGFloat(1.1 * t * params.freq)) * spec.x
                let left = CGPoint(x: lx * sx, y: spec.y * sy)
                let right = CGPoint(x: (PetConcertConst.refW - lx) * sx, y: spec.y * sy)
                let combined = UIBezierPath()
                combined.append(PetConcertDeco.path(
                    kind: spec.kind, center: left, size: size * sx,
                    rotation: 0.15 * sin(CGFloat(t) + CGFloat(spec.phase))))
                combined.append(PetConcertDeco.path(
                    kind: spec.kind, center: right, size: size * sx,
                    rotation: 0.15 * sin(CGFloat(t) + CGFloat(spec.phase))))
                decoLayer.path = combined.cgPath
                decoLayer.lineWidth = max(1.5, size * sx * 0.13)
                continue
            }
            decoLayer.path = PetConcertDeco.path(
                kind: spec.kind, center: center, size: size * sx,
                rotation: spec.kind == 0
                    ? 0.15 * sin(CGFloat(t) + CGFloat(spec.phase)) : 0).cgPath
            decoLayer.lineWidth = max(1.5, size * sx * 0.13)
        }
        _ = w
    }

    private func updateBeams(
        t: TimeInterval,
        params: (amp: Double, freq: Double, twinkleFreq: Double, twinkleAmp: Double),
        phase: ConcertPhase, sx: CGFloat, sy: CGFloat
    ) {
        let active = !atmosphereReduced
            && (phase == .interlude || phase == .singing1 || phase == .singing2)
        let colors: [UIColor] = [
            UIColor(red: 255/255, green: 170/255, blue: 200/255, alpha: 1),
            UIColor(red: 150/255, green: 190/255, blue: 255/255, alpha: 1),
            UIColor(red: 200/255, green: 170/255, blue: 255/255, alpha: 1),
        ]
        for (i, beam) in beamLayers.enumerated() {
            guard active else { beam.path = nil; continue }
            let ox: CGFloat = [180, 540, 900][i]
            let tx = ox + 250 * sin(CGFloat(0.35 * t * params.freq) + CGFloat(i) * 2.1)
            let alpha: CGFloat = phase == .interlude ? 0.24 : 0.18
            beam.fillColor = colors[i].withAlphaComponent(alpha).cgColor
            let path = UIBezierPath()
            path.move(to: CGPoint(x: (ox - 13) * sx, y: 45 * sy))
            path.addLine(to: CGPoint(x: (ox + 13) * sx, y: 45 * sy))
            path.addLine(to: CGPoint(x: (tx + 100) * sx, y: 1520 * sy))
            path.addLine(to: CGPoint(x: (tx - 100) * sx, y: 1520 * sy))
            path.close()
            beam.path = path.cgPath
        }
    }

    private func updateFootlights(t: TimeInterval, sx: CGFloat, sy: CGFloat) {
        let cores = UIBezierPath()
        for i in 0..<PetConcertConst.footlightCount {
            let x = (90 + CGFloat(i) * 90) * sx
            let y = PetConcertConst.footlightY * sy
            cores.append(UIBezierPath(ovalIn: CGRect(
                x: x - 13 * sx, y: y - 13 * sy, width: 26 * sx, height: 26 * sy)))
            let pulse = 0.75 + 0.25 * sin(2 * t + Double(i) * 0.8)
            let r = 30 * sx * CGFloat(pulse)
            footGlowLayers[i].path = UIBezierPath(ovalIn: CGRect(
                x: x - r, y: y - r, width: r * 2, height: r * 2)).cgPath
        }
        footCoreLayer.path = cores.cgPath
        footCoreLayer.lineWidth = 3 * sx
    }

    private func updateConfetti(t: TimeInterval, sx: CGFloat, sy: CGFloat) {
        let show = !atmosphereReduced && !confettiBursts.isEmpty
        for (i, piece) in confetti.enumerated() {
            guard show else { piece.layer.isHidden = true; continue }
            let burst = confettiBursts[i % confettiBursts.count]
            let dt = t - burst
            guard dt >= 0, dt <= 1.8 else { piece.layer.isHidden = true; continue }
            piece.layer.isHidden = false
            let x = (piece.x0 + 26 * sin(3 * CGFloat(dt) + CGFloat(piece.phase))) * sx
            let y = (piece.y0 + piece.vy * CGFloat(dt)) * sy
            let fade = dt > 1.2 ? 1 - (dt - 1.2) / 0.6 : 1
            piece.layer.opacity = Float(max(0, fade))
            let size = piece.size * sx * 1.4
            piece.layer.frame = CGRect(x: x, y: y, width: size, height: size * 0.5)
            piece.layer.transform = CATransform3DMakeRotation(
                CGFloat(piece.phase) + CGFloat(dt) * CGFloat(piece.rotV) * 0.4, 0, 0, 1)
        }
    }
}
