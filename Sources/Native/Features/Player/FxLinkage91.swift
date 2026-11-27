import UIKit
import QuartzCore

/// port91（任务 2）：四特效联动协调器——特效开着时，封面砖与
/// 在场宠物随特效联动（样板 Space folia-91-yang-ban 联动视图
/// 定版形态/数值移植）：
/// - 风：可见封面砖以不同相位小角度掀动（主倾角 1.5–3.5°、
///   阵风 1.5s 后转 0.45–0.85° 无限摇摆、周期 2.3–3.7s）＋
///   宠物轻晃偏身（rotate −1.4°→0.9°、skewX −2.4°→−4.4°、
///   2.6s 交替）；
/// - 雪：封面砖顶部雪檐随开雪时长渐厚（高 11 封顶、7s 长满、
///   每砖延迟 i×0.16s）＋宠物头顶积雪（4.6s 长成、5.3s 抖
///   落＋5 颗雪粒飞散、周期 7s 重来）；
/// - 孔明灯：按距离给附近封面砖加暖色提亮（alpha＝
///   max(0,1−d/155)×0.62 逐帧算）＋宠物仰头（rotate −5.5°、
///   上移 2pt，灯程进度 0.16–0.86 间成立）；
/// - 烟花：爆点附近封面随花色提亮一拍（峰值 .34/760ms）＋
///   宠物跳跃（−9pt、560ms、逐只延迟 60ms）。
///
/// 接入面：各宿主把封面图视图（cover）与其容器（container，
/// 叠加层挂靠处）注册进来；宠物注册其 actor 视图。只动
/// transform/opacity/亮度类合成器属性，不改布局占位；关特
/// 效时联动干净复位（雪檐 0.5s 淡出、提亮归零、宠物复位）。
/// 风开时宠物 transform 由轻晃独占，仰头/跳跃让位（样板未
/// 定义三者叠加口径，报告注明）。
final class FxLinkage91 {

    static let shared = FxLinkage91()

    private final class TileRec {
        weak var cover: UIView?
        weak var container: UIView?
        let index: Int
        /// (92) 加码 2：表面标签（wall/alt/stage），触发自证用。
        let surface: String
        var cap: UIView?
        var glow: UIView?
        var windOn = false
        var baseScale: CGFloat = 1
        init(cover: UIView, container: UIView, index: Int, surface: String) {
            self.cover = cover
            self.container = container
            self.index = index
            self.surface = surface
        }
    }

    private final class PetRec {
        weak var view: UIView?
        /// (92) 加码 2：表面标签（minibar/concert/island）。
        let surface: String
        /// (92) 任务 3：覆层宠物——宿主自有 transform 状态机
        /// （演唱会/岛），联动只许走覆层通道（光晕/落雪附着/
        /// 仰头贴纸），绝不写宠物本体 transform。
        let overlayOnly: Bool
        var pile: UIView?
        var glowOverlay: UIView?
        var lookSticker: UIView?
        var lookUp = false
        var nextShake: CFTimeInterval = 0
        var lastJump: CFTimeInterval = 0
        init(view: UIView, surface: String, overlayOnly: Bool) {
            self.view = view
            self.surface = surface
            self.overlayOnly = overlayOnly
        }
    }

    private var tiles: [ObjectIdentifier: TileRec] = [:]
    private var pets: [ObjectIdentifier: PetRec] = [:]
    private var nextIndex = 0
    private var link: CADisplayLink?
    private var wasWind = false
    private var wasSnow = false
    private var wasLanterns = false
    private var snowOnAt: CFTimeInterval = 0

    private init() {
        GlobalFx87.shared.onFwBurst91 = { [weak self] point, color in
            self?.fireworksBurst(at: point, color: color)
        }
    }

    // MARK: 注册

    func registerTile(cover: UIView, container: UIView, surface: String = "wall") {
        let key = ObjectIdentifier(cover)
        if tiles[key] == nil {
            tiles[key] = TileRec(cover: cover, container: container,
                                 index: nextIndex, surface: surface)
            nextIndex += 1
        }
        ensureLink()
        // 注册时特效已开的，立即补上当前联动态。
        let fx = GlobalFx87.shared
        if let rec = tiles[key] {
            if fx.isWind { startWindTile(rec) }
            if fx.isSnow { growSnowTile(rec) }
        }
    }

    func unregisterTile(cover: UIView) {
        let key = ObjectIdentifier(cover)
        guard let rec = tiles[key] else { return }
        resetTile(rec, animated: false)
        tiles[key] = nil
    }

    func registerPet(_ view: UIView, surface: String = "minibar") {
        let key = ObjectIdentifier(view)
        if pets[key] == nil {
            pets[key] = PetRec(view: view, surface: surface, overlayOnly: false)
        }
        ensureLink()
        let fx = GlobalFx87.shared
        if let rec = pets[key] {
            if fx.isWind { startWindPet(rec) }
            if fx.isSnow { growSnowPet(rec) }
        }
    }

    /// (92) 任务 3：覆层宠物注册（演唱会演员/岛宠物）——宿
    /// 主自有 transform 状态机，联动只走覆层通道：落雪附着
    /// （子视图雪堆）、孔明灯暖光覆层＋仰头贴纸、烟花闪光
    /// 覆层；风的本体轻晃与爱心跳跃不适用于本类（会与宿主
    /// 状态机抢 transform），分别以覆层闪光/不触发替代，
    /// 报告注明。
    func registerPetOverlay(_ view: UIView, surface: String) {
        let key = ObjectIdentifier(view)
        if pets[key] == nil {
            pets[key] = PetRec(view: view, surface: surface, overlayOnly: true)
        }
        ensureLink()
        let fx = GlobalFx87.shared
        if let rec = pets[key], fx.isSnow { growSnowPet(rec) }
    }

    func unregisterPet(_ view: UIView) {
        let key = ObjectIdentifier(view)
        guard let rec = pets[key] else { return }
        rec.pile?.removeFromSuperview()
        rec.pile = nil
        rec.glowOverlay?.removeFromSuperview()
        rec.glowOverlay = nil
        rec.lookSticker?.removeFromSuperview()
        rec.lookSticker = nil
        if let v = rec.view, !rec.overlayOnly {
            v.layer.removeAllAnimations()
            v.transform = .identity
        }
        pets[key] = nil
    }

    // MARK: (92) 加码 2：联动触发自证

    /// 每种特效在每个表面首次真触发时落一条，同（特效，
    /// 表面）每会话只落一次防刷屏——真机日志可逐项对账
    /// 「开某特效→某表面动了」。
    private var linkProof92: Set<String> = []

    private func proof92(fx: String, surface: String) {
        let key = "\(fx)|\(surface)"
        guard !linkProof92.contains(key) else { return }
        linkProof92.insert(key)
        Breadcrumbs.log("p92 link \(fx) on \(surface)")
    }

    /// 覆层宠物在场判据：岛宠物视图不进视图树（层嫁接），
    /// window 恒 nil，改判 layer 已挂载；普通宠物仍判 window。
    private func petPresent(_ rec: PetRec, _ v: UIView) -> Bool {
        rec.overlayOnly ? v.layer.superlayer != nil : v.window != nil
    }

    // MARK: 显示链与状态迁移

    private func ensureLink() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        // (92) 任务 8：联动链同样设 60 上限（旧实现常驻全速，
        // 120Hz 机型上与引擎链叠加成倍开销）。
        l.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// (92) 任务 8：孔明灯全表遍历限频计数（每 3 拍一趟）。
    private var tickCount92 = 0

    @objc private func tick() {
        // 失效注册回收（cell 复用/宠物下台均有显式注销，此为兜底）。
        tiles = tiles.filter { $0.value.cover != nil }
        pets = pets.filter { $0.value.view != nil }
        if tiles.isEmpty && pets.isEmpty {
            link?.invalidate()
            link = nil
            return
        }
        let fx = GlobalFx87.shared
        if fx.isWind != wasWind {
            wasWind = fx.isWind
            if fx.isWind {
                tiles.values.forEach { startWindTile($0) }
                pets.values.forEach { startWindPet($0) }
                Breadcrumbs.log("p91 link wind=1")
            } else {
                tiles.values.forEach { stopWindTile($0) }
                pets.values.forEach { stopWindPet($0) }
                Breadcrumbs.log("p91 link wind=0")
            }
        }
        if fx.isSnow != wasSnow {
            wasSnow = fx.isSnow
            if fx.isSnow {
                snowOnAt = CACurrentMediaTime()
                tiles.values.forEach { growSnowTile($0) }
                pets.values.forEach { growSnowPet($0) }
                Breadcrumbs.log("p91 link snow=1")
            } else {
                tiles.values.forEach { clearSnowTile($0) }
                pets.values.forEach { clearSnowPet($0) }
                Breadcrumbs.log("p91 link snow=0")
            }
        }
        tickCount92 += 1
        if fx.isLanterns {
            // (92) 任务 8：暖光逐帧全表遍历改每 3 拍一趟
            // （≈20Hz，慢变量无感），爆点节流另见 processBurst92。
            if tickCount92 % 3 == 0 { updateLanternGlow() }
            wasLanterns = true
        } else if wasLanterns {
            wasLanterns = false
            for rec in tiles.values {
                guard let glow = rec.glow else { continue }
                UIView.animate(withDuration: 0.3) { glow.alpha = 0 }
            }
            for rec in pets.values {
                if rec.overlayOnly {
                    // (92) 任务 3：覆层宠物收灯——覆层淡出、
                    // 仰头贴纸收起，本体 transform 不碰。
                    rec.lookUp = false
                    if let o = rec.glowOverlay {
                        UIView.animate(withDuration: 0.3) { o.alpha = 0 }
                    }
                    if let s = rec.lookSticker {
                        UIView.animate(withDuration: 0.3) { s.alpha = 0 }
                    }
                    continue
                }
                guard rec.lookUp else { continue }
                rec.lookUp = false
                if !GlobalFx87.shared.isWind, let v = rec.view {
                    UIView.animate(withDuration: 0.35, delay: 0,
                                   usingSpringWithDamping: 0.8,
                                   initialSpringVelocity: 0.3) {
                        v.transform = .identity
                    }
                }
            }
            Breadcrumbs.log("p91 link ln=0")
        }
        if fx.isSnow { tickSnowPets() }
    }

    // MARK: 风

    private func currentScale(_ view: UIView) -> CGFloat {
        let t = view.transform
        let s = (t.a * t.a + t.b * t.b).squareRoot()
        return s > 0.01 ? s : 1
    }

    private func tileTransform(_ rec: TileRec, angle: CGFloat, dy: CGFloat) -> CGAffineTransform {
        var t = CGAffineTransform(scaleX: rec.baseScale, y: rec.baseScale)
        t = t.rotated(by: angle)
        t = t.translatedBy(x: 0, y: dy)
        return t
    }

    private func startWindTile(_ rec: TileRec) {
        guard let cover = rec.cover, !rec.windOn else { return }
        rec.windOn = true
        proof92(fx: "wind", surface: rec.surface)
        rec.baseScale = currentScale(cover)
        let i = rec.index
        let deg = (1.5 + Double((i * 53) % 21) / 10.0) * (i % 2 == 0 ? 1 : -1)
        let rad = CGFloat(deg * .pi / 180)
        let dy: CGFloat = i % 3 == 0 ? -3 : 0
        let delay = Double((i % 4) * 110 + (i / 4) * 70 + (i * 29) % 60) / 1000.0
        UIView.animate(withDuration: 1.5, delay: delay,
                       options: [.curveEaseInOut, .beginFromCurrentState]) {
            cover.transform = self.tileTransform(rec, angle: rad, dy: dy)
        } completion: { _ in
            guard rec.windOn, GlobalFx87.shared.isWind else { return }
            let ampDeg = 0.45 + Double((i * 37) % 41) / 100.0
            let amp = CGFloat(ampDeg * .pi / 180) * (deg > 0 ? 1 : -1)
            let dur = 2.3 + Double((i * 29) % 15) / 10.0
            UIView.animate(withDuration: dur, delay: 0,
                           options: [.repeat, .autoreverse, .curveEaseInOut,
                                     .beginFromCurrentState]) {
                cover.transform = self.tileTransform(
                    rec, angle: rad * 0.35 + amp, dy: dy)
            }
        }
    }

    private func stopWindTile(_ rec: TileRec) {
        guard let cover = rec.cover else { rec.windOn = false; return }
        rec.windOn = false
        cover.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.62, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3,
                       options: [.beginFromCurrentState]) {
            cover.transform = CGAffineTransform(
                scaleX: rec.baseScale, y: rec.baseScale)
        }
    }

    private func petLean(rotDeg: CGFloat, skewDeg: CGFloat, tx: CGFloat) -> CGAffineTransform {
        var t = CGAffineTransform(rotationAngle: rotDeg * .pi / 180)
        t.c = tan(skewDeg * .pi / 180)
        t.tx = tx
        return t
    }

    private func startWindPet(_ rec: PetRec) {
        // (92) 任务 3：覆层宠物不走本体轻晃（transform 归宿主）。
        guard !rec.overlayOnly, let v = rec.view else { return }
        proof92(fx: "wind", surface: rec.surface)
        v.layer.removeAllAnimations()
        v.transform = petLean(rotDeg: -1.4, skewDeg: -2.4, tx: 0)
        UIView.animate(withDuration: 2.6, delay: 0,
                       options: [.repeat, .autoreverse, .curveEaseInOut]) {
            v.transform = self.petLean(rotDeg: 0.9, skewDeg: -4.4, tx: 2.5)
        }
    }

    private func stopWindPet(_ rec: PetRec) {
        guard !rec.overlayOnly, let v = rec.view else { return }
        v.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.62, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3) {
            v.transform = .identity
        }
    }

    // MARK: 雪

    /// (93) A4：联动雪檐/雪堆常驻上限——旧实现开雪时给每
    /// 块已注册砖＋每只宠物各建一只 UIView 全量常驻（墙
    /// 砖可达数百），是雪开启窗增量的联动侧构成。改：雪
    /// 檐全局 ≤120、雪堆 ≤24，超出不再新建（联动观感由
    /// 在场砖/宠承担）；停雪回收走既有 clear 路径（0.5s
    /// 淡出后 removeFromSuperview，rec.cap/pile 置 nil）。
    private static let snowCapLimit93 = 120
    private static let snowPileLimit93 = 24

    private func growSnowTile(_ rec: TileRec) {
        guard let cover = rec.cover, let container = rec.container,
              rec.cap == nil else { return }
        // (93) A4：不在窗的砖（已回收/未挂载）不建檐＋上限。
        guard cover.window != nil else { return }
        guard tiles.values.filter({ $0.cap != nil }).count
                < FxLinkage91.snowCapLimit93 else { return }
        proof92(fx: "snow", surface: rec.surface)
        let cap = UIView()
        cap.backgroundColor = UIColor.white.withAlphaComponent(0.95)
        cap.layer.cornerRadius = 6
        cap.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        cap.isUserInteractionEnabled = false
        let f = cover.frame
        cap.frame = CGRect(x: f.minX, y: f.minY, width: f.width, height: 11)
        cap.layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        cap.center = CGPoint(x: f.midX, y: f.minY)
        cap.transform = CGAffineTransform(scaleX: 1, y: 0.02)
        if let glow = rec.glow {
            container.insertSubview(cap, aboveSubview: glow)
        } else {
            container.insertSubview(cap, aboveSubview: cover)
        }
        rec.cap = cap
        UIView.animate(withDuration: 7, delay: Double(rec.index) * 0.16,
                       options: [.curveEaseOut]) {
            cap.transform = .identity
        }
    }

    private func clearSnowTile(_ rec: TileRec) {
        guard let cap = rec.cap else { return }
        rec.cap = nil
        UIView.animate(withDuration: 0.5, animations: { cap.alpha = 0 }) { _ in
            cap.removeFromSuperview()
        }
    }

    private func growSnowPet(_ rec: PetRec) {
        guard let v = rec.view, rec.pile == nil else { return }
        // (93) A4：雪堆全局上限（见 snowCapLimit93 注释）。
        guard pets.values.filter({ $0.pile != nil }).count
                < FxLinkage91.snowPileLimit93 else { return }
        proof92(fx: "snow", surface: rec.surface)
        let pile = UIView()
        pile.backgroundColor = UIColor.white.withAlphaComponent(0.96)
        pile.layer.cornerRadius = 6
        pile.isUserInteractionEnabled = false
        let w: CGFloat = 27, h: CGFloat = 12
        pile.frame = CGRect(x: (v.bounds.width - w) / 2, y: 0, width: w, height: h)
        pile.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        pile.center = CGPoint(x: v.bounds.midX, y: h)
        pile.transform = CGAffineTransform(scaleX: 0.25, y: 0.25)
        v.addSubview(pile)
        rec.pile = pile
        rec.nextShake = CACurrentMediaTime() + 5.3
        UIView.animate(withDuration: 4.6, delay: 0, options: [.curveEaseOut]) {
            pile.transform = .identity
        }
    }

    private func clearSnowPet(_ rec: PetRec) {
        guard let pile = rec.pile else { return }
        rec.pile = nil
        UIView.animate(withDuration: 0.5, animations: { pile.alpha = 0 }) { _ in
            pile.removeFromSuperview()
        }
    }

    /// 宠物积雪周期：到点抖落（±5° 快摇 0.48s＋雪粒飞散＋雪
    /// 堆缩回），随后 4.6s 重新长成、周期 7s。
    private func tickSnowPets() {
        let now = CACurrentMediaTime()
        for rec in pets.values {
            guard let v = rec.view, let pile = rec.pile,
                  rec.nextShake > 0, now >= rec.nextShake else { continue }
            rec.nextShake = now + 7.0
            // (92) 任务 3：覆层宠物只抖雪堆/飞雪粒，不摇本体。
            if !rec.overlayOnly && !GlobalFx87.shared.isWind {
                UIView.animateKeyframes(withDuration: 0.48, delay: 0) {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.33) {
                        v.transform = CGAffineTransform(rotationAngle: -5 * .pi / 180)
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.33, relativeDuration: 0.33) {
                        v.transform = CGAffineTransform(rotationAngle: 5 * .pi / 180)
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.66, relativeDuration: 0.34) {
                        v.transform = .identity
                    }
                }
            }
            spawnSnowDots(from: pile)
            UIView.animate(withDuration: 0.3) {
                pile.transform = CGAffineTransform(scaleX: 0.25, y: 0.25)
            } completion: { _ in
                guard GlobalFx87.shared.isSnow, rec.pile === pile else { return }
                UIView.animate(withDuration: 4.6, delay: 0, options: [.curveEaseOut]) {
                    pile.transform = .identity
                }
            }
        }
    }

    private func spawnSnowDots(from pile: UIView) {
        guard let host = pile.superview?.superview ?? pile.superview else { return }
        let origin = pile.convert(CGPoint(x: pile.bounds.midX, y: pile.bounds.midY), to: host)
        for i in 0..<5 {
            let dot = UIView(frame: CGRect(x: origin.x - 2, y: origin.y - 2, width: 4, height: 4))
            dot.backgroundColor = .white
            dot.layer.cornerRadius = 2
            dot.isUserInteractionEnabled = false
            host.addSubview(dot)
            let dx = CGFloat((i - 2) * 9)
            UIView.animate(withDuration: 0.52, delay: 0, options: [.curveEaseOut]) {
                dot.center = CGPoint(x: origin.x + dx, y: origin.y + 16)
                dot.alpha = 0
            } completion: { _ in dot.removeFromSuperview() }
        }
    }

    // MARK: 孔明灯暖光

    private func glowView(_ rec: TileRec) -> UIView {
        if let glow = rec.glow { return glow }
        let glow = UIView()
        glow.backgroundColor = UIColor(red: 1, green: 170 / 255, blue: 70 / 255, alpha: 1)
        glow.alpha = 0
        glow.isUserInteractionEnabled = false
        if let cover = rec.cover {
            glow.frame = cover.frame
            glow.layer.cornerRadius = cover.layer.cornerRadius
        }
        if let container = rec.container, let cover = rec.cover {
            container.insertSubview(glow, aboveSubview: cover)
        }
        rec.glow = glow
        return glow
    }

    /// (92) 任务 3：覆层宠物的暖光覆层（填满宠物本体、暖色、
    ///  alpha 由灯距逐趟算）——不写本体 transform。
    private func petGlowOverlay(_ rec: PetRec) -> UIView {
        if let o = rec.glowOverlay { return o }
        let o = UIView()
        o.backgroundColor = UIColor(red: 1, green: 170 / 255, blue: 70 / 255, alpha: 1)
        o.alpha = 0
        o.isUserInteractionEnabled = false
        o.layer.cornerRadius = 6
        if let v = rec.view {
            o.frame = v.bounds
            o.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            v.addSubview(o)
        }
        rec.glowOverlay = o
        return o
    }

    /// (92) 任务 3：覆层宠物的仰头贴纸层——宠物本体不许转
    /// 头时，以头顶星贴纸的显隐表达「仰头看灯」（与普通宠
    /// 物的本体仰头同触发条件）。
    private func petLookSticker(_ rec: PetRec) -> UIView {
        if let s = rec.lookSticker { return s }
        let iv = UIImageView(image: DeckGlyph82.image(.starFill, pointSize: 12))
        iv.tintColor = UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
        iv.alpha = 0
        iv.isUserInteractionEnabled = false
        if let v = rec.view {
            iv.frame = CGRect(x: v.bounds.midX - 6, y: -14, width: 12, height: 12)
            v.addSubview(iv)
        }
        rec.lookSticker = iv
        return iv
    }

    private func updateLanternGlow() {
        let frames = GlobalFx87.shared.lanternFrames91()
        guard !frames.isEmpty else { return }
        for rec in tiles.values {
            guard let cover = rec.cover, cover.window != nil else { continue }
            let center = cover.convert(
                CGPoint(x: cover.bounds.midX, y: cover.bounds.midY), to: nil)
            var best: CGFloat = 0
            for f in frames {
                let d = hypot(center.x - f.center.x, center.y - f.center.y)
                best = max(best, max(0, 1 - d / 155) * 0.62)
            }
            let glow = glowView(rec)
            glow.frame = cover.frame
            if glow.backgroundColor != UIColor(red: 1, green: 170 / 255, blue: 70 / 255, alpha: 1) {
                glow.backgroundColor = UIColor(red: 1, green: 170 / 255, blue: 70 / 255, alpha: 1)
            }
            glow.alpha = best
            if best > 0.02 { proof92(fx: "ln", surface: rec.surface) }
        }
        // 宠物仰头：任一灯在宠物附近且灯程进度 0.16–0.86。
        let screenH = UIScreen.main.bounds.height
        for rec in pets.values {
            guard let v = rec.view, petPresent(rec, v) else { continue }
            let center = v.convert(CGPoint(x: v.bounds.midX, y: v.bounds.midY), to: nil)
            var shouldLook = false
            var nearest: CGFloat = .greatestFiniteMagnitude
            for f in frames {
                let progress = 1 - f.center.y / screenH
                let d = hypot(center.x - f.center.x, center.y - f.center.y)
                nearest = min(nearest, d)
                if progress > 0.16 && progress < 0.86 && d < 220 {
                    shouldLook = true
                    break
                }
            }
            if rec.overlayOnly {
                // (92) 任务 3：覆层通道——暖光覆层 alpha 随灯
                // 距、仰头以头顶星贴纸显隐表达，本体不动。
                let overlay = petGlowOverlay(rec)
                overlay.backgroundColor = UIColor(
                    red: 1, green: 170 / 255, blue: 70 / 255, alpha: 1)
                let target = nearest.isFinite
                    ? max(0, 1 - nearest / 220) * 0.5 : 0
                overlay.alpha = target
                if target > 0.02 { proof92(fx: "ln", surface: rec.surface) }
                if shouldLook != rec.lookUp {
                    rec.lookUp = shouldLook
                    let sticker = petLookSticker(rec)
                    UIView.animate(withDuration: 0.35) {
                        sticker.alpha = shouldLook ? 1 : 0
                    }
                }
                continue
            }
            if shouldLook != rec.lookUp {
                rec.lookUp = shouldLook
                if shouldLook { proof92(fx: "ln", surface: rec.surface) }
                if !GlobalFx87.shared.isWind {
                    UIView.animate(withDuration: 0.35, delay: 0,
                                   usingSpringWithDamping: 0.8,
                                   initialSpringVelocity: 0.3) {
                        v.transform = shouldLook
                            ? CGAffineTransform(rotationAngle: -5.5 * .pi / 180)
                                .translatedBy(x: 0, y: -2)
                            : .identity
                    }
                }
            }
        }
    }

    // MARK: 烟花

    /// (92) 任务 8：爆点节流状态——50ms 内连爆合并为一趟。
    private var pendingBurst92: (point: CGPoint, color: UIColor)?
    private var burstFlushArmed92 = false
    private var lastBurstPass92: CFTimeInterval = 0

    private func fireworksBurst(at point: CGPoint, color: UIColor) {
        // (92) 任务 8：同帧/连爆合并——50ms 内的后续爆点只
        // 更新待办（保留最后一发），到点一趟全表遍历，防烟
        // 花连发时逐爆点全表扫描叠加引擎绘制成卡顿源。
        let now = CACurrentMediaTime()
        if now - lastBurstPass92 < 0.05 {
            pendingBurst92 = (point, color)
            if !burstFlushArmed92 {
                burstFlushArmed92 = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self else { return }
                    self.burstFlushArmed92 = false
                    if let pending = self.pendingBurst92 {
                        self.pendingBurst92 = nil
                        self.processBurst92(at: pending.point, color: pending.color)
                    }
                }
            }
            return
        }
        processBurst92(at: point, color: color)
    }

    private func processBurst92(at point: CGPoint, color: UIColor) {
        lastBurstPass92 = CACurrentMediaTime()
        for rec in tiles.values {
            guard let cover = rec.cover, cover.window != nil else { continue }
            let center = cover.convert(
                CGPoint(x: cover.bounds.midX, y: cover.bounds.midY), to: nil)
            let d = hypot(center.x - point.x, center.y - point.y)
            guard d < 280 else { continue }
            let glow = glowView(rec)
            glow.frame = cover.frame
            glow.backgroundColor = color
            glow.layer.removeAllAnimations()
            glow.alpha = 0
            proof92(fx: "fw", surface: rec.surface)
            UIView.animate(withDuration: 0.12, animations: { glow.alpha = 0.34 }) { _ in
                UIView.animate(withDuration: 0.76) { glow.alpha = 0 }
            }
        }
        let now = CACurrentMediaTime()
        for (i, rec) in pets.values.enumerated() {
            guard let v = rec.view, now - rec.lastJump > 0.5 else { continue }
            rec.lastJump = now
            if rec.overlayOnly {
                // (92) 任务 3：覆层宠物以闪光覆层欢呼，本体不跳。
                guard petPresent(rec, v) else { continue }
                proof92(fx: "fw", surface: rec.surface)
                flashPetOverlay(rec, color: color)
                continue
            }
            if GlobalFx87.shared.isWind { continue }
            proof92(fx: "fw", surface: rec.surface)
            let base = rec.lookUp
                ? CGAffineTransform(rotationAngle: -5.5 * .pi / 180).translatedBy(x: 0, y: -2)
                : CGAffineTransform.identity
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                UIView.animate(withDuration: 0.28, delay: 0,
                               usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8) {
                    v.transform = base.translatedBy(x: 0, y: -9)
                } completion: { _ in
                    UIView.animate(withDuration: 0.28, delay: 0,
                                   usingSpringWithDamping: 0.6, initialSpringVelocity: 0.4) {
                        v.transform = base
                    }
                }
            }
        }
    }

    /// (92) 任务 3/6：覆层宠物闪光一拍（烟花欢呼与爱心反应
    /// 共用）：覆层以给定色冲亮再淡出，本体零位移。
    private func flashPetOverlay(_ rec: PetRec, color: UIColor) {
        let overlay = petGlowOverlay(rec)
        overlay.backgroundColor = color
        overlay.layer.removeAllAnimations()
        overlay.alpha = 0
        UIView.animate(withDuration: 0.12, animations: { overlay.alpha = 0.4 }) { _ in
            UIView.animate(withDuration: 0.76) { overlay.alpha = 0 }
        }
    }

    // MARK: (92) 任务 6：爱心宠物反应

    /// 封面/A·B 爱心点亮且云端同步成功后由格子调用：变换宠
    /// 物跳一拍（与烟花跳同弹簧/同让位规则）、覆层宠物闪光
    /// 一拍；只动宠物、不动封面砖。取消喜欢与云端失败回滚
    /// 不调本方法（调用方纪律，见三处 heartTapped91）。
    func petHeartReaction92() {
        let now = CACurrentMediaTime()
        for (i, rec) in pets.values.enumerated() {
            guard let v = rec.view else { continue }
            if rec.overlayOnly {
                guard petPresent(rec, v) else { continue }
                flashPetOverlay(rec, color: UIColor(
                    red: 1, green: 0.45, blue: 0.55, alpha: 1))
                continue
            }
            guard now - rec.lastJump > 0.5,
                  !GlobalFx87.shared.isWind else { continue }
            rec.lastJump = now
            let base = rec.lookUp
                ? CGAffineTransform(rotationAngle: -5.5 * .pi / 180).translatedBy(x: 0, y: -2)
                : CGAffineTransform.identity
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                UIView.animate(withDuration: 0.28, delay: 0,
                               usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8) {
                    v.transform = base.translatedBy(x: 0, y: -9)
                } completion: { _ in
                    UIView.animate(withDuration: 0.28, delay: 0,
                                   usingSpringWithDamping: 0.6, initialSpringVelocity: 0.4) {
                        v.transform = base
                    }
                }
            }
        }
    }

    // MARK: 复位

    private func resetTile(_ rec: TileRec, animated: Bool) {
        if rec.windOn, let cover = rec.cover {
            rec.windOn = false
            cover.layer.removeAllAnimations()
            cover.transform = CGAffineTransform(scaleX: rec.baseScale, y: rec.baseScale)
        }
        rec.cap?.removeFromSuperview()
        rec.cap = nil
        rec.glow?.removeFromSuperview()
        rec.glow = nil
    }
}
