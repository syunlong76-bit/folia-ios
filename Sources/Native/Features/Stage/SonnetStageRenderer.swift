import UIKit
import QuartzCore

// 商籁 sonnet（3.7 (57) 工作流 B3 全量原生移植）：按 folia-major
// 网页版 sonnet/ 目录（Pixi 2D 确定性 MG 歌词 PV 导演）的核心构
// 成逐项实现。依据文件：sonnetProgram.ts（镜头程序）、
// sonnetSceneBuilder.ts（场景构成与字号公式）、
// sonnetTypographyLayout.ts / sonnetTypographyRoles.ts（角色与
// 字阶）、sonnetShotFlowLayouts.ts（流式排版与全局适配）、
// sonnetPosterBlocksLayout.ts（海报块分区流）、
// sonnetGlyphLayout.ts（字形坐标与入场向量）、sonnetMotion.ts
// （镜头路径 / 呼吸 / 缓动）、sonnetTransitions.ts +
// sonnetSceneFrame.ts（转场）、sonnetGuides.ts（引导线）、
// sonnetFrameDecor.ts（开放框装饰）、sonnetCredits.ts（片尾海
// 报）、sonnetPostProcess.ts（后处理量）、tuning.ts（调参）。
//
// 移植口径：
//  - 镜头程序骨架（段落切分 / 分类 / 镜头分组 / 相机种子 / 转
//    场选择）逐函数移植 sonnetProgram.ts；协议 LyricLine 无
//    blockIndex / songPart / isChorus 字段，metadata 边界与副
//    歌判定只能按时间间隔与文本标点近似（见 compileProgram）。
//  - 语义分段：网页走 wordSegmentation 词典分词；原生以协议既
//    有 StageLyricUnits（YRC 真戳或字素均分）为段，段 = 词单
//    元，isWordLike 恒真；标点粘连（sticky）由 tokenize 的拉
//    丁串合并近似。
//  - 呈现以 CoreAnimation/CoreGraphics 图层复刻 Pixi 2D 构成：
//    海报块色块、引导线贝塞尔、开放框、巨型装饰字、字形逐字
//    入场均为程序化绘制 / UILabel 活字，无纹理图集（纹理内存
//    ≈ 颗粒噪声小图一张，远低于 200MB 红线）。
//  - 逐帧求值全部是 position 的纯函数（网页 sonnetMotion 的
//    absolute-time 口径）：seek 与连续播放同帧一致；不自建时
//    钟源，只消费宿主 frameTick(position)。
//  - 未落项（ShotMg 全部主题变体等）逐项列在交付报告对照表，
//    本文件内以「近似」注释标明落点。

// MARK: - 确定性散列（visualizerSeedHash.ts 逐函数移植）

/// FNV-1a 32 位（网页 hashVisualizerSeed，UTF-16 码元序）。
private func sonnetHash(_ value: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for unit in value.utf16 {
        hash ^= UInt32(unit)
        hash = hash &* 16_777_619
    }
    return hash
}

private func sonnetClamp01(_ v: Double) -> Double { min(1, max(0, v)) }
private func sonnetClamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    min(hi, max(lo, v))
}

// MARK: - 缓动（sonnetMotion.ts 逐函数移植）

private func sonnetCubicCoordinate(_ p1: Double, _ p2: Double, _ t: Double) -> Double {
    let inv = 1 - t
    return 3 * inv * inv * t * p1 + 3 * inv * t * t * p2 + t * t * t
}

private func sonnetCubicBezier(_ x1: Double, _ y1: Double,
                               _ x2: Double, _ y2: Double,
                               _ value: Double) -> Double {
    let target = sonnetClamp01(value)
    if target == 0 || target == 1 { return target }
    var low = 0.0, high = 1.0, parameter = target
    for _ in 0..<12 {
        let x = sonnetCubicCoordinate(x1, x2, parameter)
        if x < target { low = parameter } else { high = parameter }
        parameter = (low + high) / 2
    }
    return sonnetCubicCoordinate(y1, y2, parameter)
}

private func sonnetEaseInOut(_ v: Double) -> Double {
    sonnetCubicBezier(0.65, 0, 0.35, 1, v)
}
private func sonnetEaseEnter(_ v: Double) -> Double {
    sonnetCubicBezier(0.22, 1, 0.36, 1, v)
}
private func sonnetExpoOut(_ v: Double) -> Double {
    v == 1 ? 1 : 1 - pow(2, -10 * v)
}

// MARK: - 镜头程序（sonnetProgram.ts 移植）

private enum SonnetShotKind: String, CaseIterable {
    case editorialColumn = "editorial-column"
    case typeImpact = "type-impact"
    case fragmentCollage = "fragment-collage"
    case trackingRibbon = "tracking-ribbon"
    case maskReveal = "mask-reveal"
    case posterBlocks = "poster-blocks"
    case quietTableau = "quiet-tableau"
}

private enum SonnetParagraphKind {
    case breath, verse, lift, chorus, `break`, outro
}

private enum SonnetTransitionKind: String, CaseIterable {
    case fastBlur = "fast-blur"
    case monoGlitch = "mono-glitch"
    case cameraPull = "camera-pull"
}

private struct SonnetSegment {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var isWordLike: Bool { true }
    var visibleLength: Int {
        text.filter { !$0.isWhitespace }.count
    }
}

private struct SonnetShotProgram {
    var kind: SonnetShotKind
    var start: TimeInterval
    var end: TimeInterval
    var lineIndices: [Int]
    var cameraX: Double
    var cameraY: Double
    var cameraZoom: Double
    var cameraRotation: Double
}

private struct SonnetParagraphProgram {
    var kind: SonnetParagraphKind
    var start: TimeInterval
    var end: TimeInterval
    var lineIndices: [Int]
    var shots: [SonnetShotProgram]
    var transitionKind: SonnetTransitionKind?
    var transitionStart: TimeInterval
    var transitionEnd: TimeInterval
}

/// 无重复选择（网页 chooseWithoutRepeat：散列起点轮转避开前值）。
private func sonnetChoose<T: Equatable>(_ choices: [T], seed: String,
                                        previous: T?) -> T {
    let start = Int(sonnetHash(seed)) % choices.count
    for offset in 0..<choices.count {
        let candidate = choices[(start + offset) % choices.count]
        if candidate != previous { return candidate }
    }
    return choices[start]
}

// MARK: - 排版（sonnetTypographyLayout / Roles / GlyphLayout 移植）

private enum SonnetRole {
    case hero, semiHero, support, decoration
}

private struct SonnetPlacement {
    var segmentIndex: Int
    var role: SonnetRole
    var fontScale: CGFloat
    var width: CGFloat
    var height: CGFloat
    var x: CGFloat          // 相对画布中心
    var y: CGFloat
    var rotation: CGFloat   // 弧度
    var enterX: CGFloat
    var enterY: CGFloat
    var vertical: Bool
    var timingPhase: Double
}

private struct SonnetGlyphEntry {
    var label: UILabel
    var baseX: CGFloat      // 镜头容器坐标
    var baseY: CGFloat
    var enterX: CGFloat
    var enterY: CGFloat
    var entryRotation: CGFloat
    var finalRotation: CGFloat
    var start: TimeInterval
    var settle: TimeInterval
    var isDecoration: Bool
}

// MARK: - 渲染器

final class SonnetStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: true, requiresSpectrum: false, supportsLineSeek: false)

    private let rootView = LyricStageRootView()
    /// 镜头容器：相机（shot 路径 + 呼吸 + 程序相机）与转场变换
    /// 都落这一层，内部为 MG 层 / 引导层 / 文字层（网页
    /// scene container 同构）。
    private let cameraView = UIView()
    private let mgView = UIView()          // 背景 MG + 海报块 + 固定几何
    private let decorView = UIView()       // 巨型装饰字（文字层之下）
    private let guideView = UIView()       // 引导线
    private let textView = UIView()        // 字形
    private let frameOverlayView = UIView()  // 外框（不随镜头动）
    private let frameBorderLayer = CAShapeLayer()
    private var frameLabels: [UILabel] = []
    private let creditsView = UIView()     // 片尾海报
    private var creditsLabels: [UILabel] = []
    private var creditsExtras: [UIView] = []
    private let vignetteLayer = CAGradientLayer()
    private let grainView = UIView()
    private let backdropView = UIView()
    private let fallbackLabel = UILabel()

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false

    // 镜头程序（按 track.id + 行数编译一次，旋转时只重排版）。
    private var program: [SonnetParagraphProgram] = []
    private var segmentsByLine: [Int: [SonnetSegment]] = [:]
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var builtSeed = ""

    // 当前镜头场景（有界：只持当前 shot 的视图，切换即拆）。
    private var sceneParagraphIndex = -1
    private var sceneShotIndex = -1
    private var sceneKey = ""
    private var glyphEntries: [SonnetGlyphEntry] = []
    private var guideEntries: [(layer: CAShapeLayer, start: TimeInterval,
                                end: TimeInterval, maxAlpha: CGFloat)] = []
    private var frameDecorEntries: [(view: UIView, start: TimeInterval,
                                     end: TimeInterval, rotation: CGFloat)] = []
    private var shotBaseX: CGFloat = 0
    private var shotBaseY: CGFloat = 0
    private var currentTuning = SonnetTuningSnapshot.defaults
    private var lastPosition: TimeInterval = 0

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        rootView.clipsToBounds = true
        backdropView.isUserInteractionEnabled = false
        rootView.addSubview(backdropView)
        cameraView.isUserInteractionEnabled = false
        rootView.addSubview(cameraView)
        for layer in [mgView, decorView, guideView, textView] {
            layer.isUserInteractionEnabled = false
            cameraView.addSubview(layer)
        }
        frameOverlayView.isUserInteractionEnabled = false
        frameBorderLayer.fillColor = UIColor.clear.cgColor
        frameOverlayView.layer.addSublayer(frameBorderLayer)
        rootView.addSubview(frameOverlayView)
        vignetteLayer.type = .radial
        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignetteLayer.endPoint = CGPoint(x: 1, y: 1)
        vignetteLayer.locations = [0, 1]
        vignetteLayer.colors = [UIColor.clear.cgColor,
                                UIColor.black.cgColor]
        rootView.layer.addSublayer(vignetteLayer)
        grainView.isUserInteractionEnabled = false
        grainView.alpha = 0
        rootView.addSubview(grainView)
        creditsView.isUserInteractionEnabled = false
        creditsView.alpha = 0
        rootView.addSubview(creditsView)
        fallbackLabel.numberOfLines = 0
        fallbackLabel.textAlignment = .center
        fallbackLabel.isUserInteractionEnabled = false
        fallbackLabel.alpha = 0
        rootView.addSubview(fallbackLabel)
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        // (61) WC：入口统一过对比钳制——下游 palette.* 全走保护副本。
        var snapshot = snapshot
        snapshot.palette = snapshot.palette.contrastProtected()
        self.snapshot = snapshot
        if snapshot.track?.id != builtTrackId
            || snapshot.lines.count != builtLineCount {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
            builtSeed = snapshot.track?.id ?? "sonnet"
            compileProgram(lines: snapshot.lines, seed: builtSeed)
            sceneKey = ""
            sceneParagraphIndex = -1
            sceneShotIndex = -1
        }
        backdropView.backgroundColor = snapshot.palette.background
        updateFrameOverlay()
        updateCreditsContent()
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if !isActive {
            // inactive 停一切逐帧工作：frameTick 自行守门，无自
            // 建时钟 / 动画源待停（全部变换由 frameTick 纯函数
            // 求值，无 CAAnimation 常驻）。
        }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, snapshot != nil else { return }
        lastPosition = position
        currentTuning = SonnetTuningStore.cachedSnapshot(
            now: CACurrentMediaTime())
        let tuning = currentTuning

        guard !program.isEmpty else {
            updateFallback(position: position)
            return
        }
        fallbackLabel.alpha = 0

        // 当前段落 / 镜头（网页 findSonnetParagraphIndexAtTime /
        // findSonnetActiveShotIndex：自后向前取 start ≤ time）。
        let pIdx = paragraphIndex(at: position)
        let paragraph = program[pIdx]
        var sIdx = 0
        for i in paragraph.shots.indices.reversed() {
            if position >= paragraph.shots[i].start { sIdx = i; break }
        }
        let key = "\(pIdx)/\(sIdx)/\(Int(rootView.bounds.width))x\(Int(rootView.bounds.height))/\(tuning.showOnlyText)/\(tuning.showGuide)/\(tuning.showBackgroundMg)/\(tuning.showFixedGeo)/\(tuning.showGiantDecorativeText)/\(tuning.showBackgroundDecor)/\(tuning.mgDensity)"
        if key != sceneKey {
            sceneParagraphIndex = pIdx
            sceneShotIndex = sIdx
            // 构建失败（bounds 未就绪等）不提交键，下一帧重试。
            sceneKey = buildScene(paragraphIndex: pIdx, shotIndex: sIdx)
                ? key : ""
        }
        let shot = paragraph.shots[sIdx]

        // —— 镜头（sonnetMotion.resolveShotMotionFrame + 呼吸）——
        let progress = sonnetClamp01(
            (position - shot.start) / max(shot.end - shot.start, 0.001))
        let pathProgress = shotPathProgress(kind: shot.kind, progress: progress)
        let motion = shotMotionFrame(kind: shot.kind, eased: pathProgress,
                                     linear: progress)
        let breath = cameraBreath(time: position, phase: Double(pIdx) * 1.7)
        // 呼吸在歌词揭示完成后 1.2s 内渐入（resolveSonnetBreathWeight）。
        let revealDone = shot.start + 0.65
        let breathWeight = sonnetEaseInOut(
            sonnetClamp01((position - revealDone) / 1.2))
        let intensity = tuning.cameraIntensity
        let camX = (shot.cameraX + motion.x + breath.x * breathWeight)
            * intensity
        let camY = (shot.cameraY + motion.y + breath.y * breathWeight)
            * intensity
        let camScale = max(0.5, shot.cameraZoom * motion.scale
            * (1 + breath.scale * breathWeight * intensity))
        let camRotation = (shot.cameraRotation + motion.rotation
            + breath.rotation * breathWeight) * intensity

        // —— 转场（sonnetSceneFrame：shot 转场优先、否则段落转场）——
        let transition = sceneTransitionFrame(paragraphIndex: pIdx,
                                              shotIndex: sIdx,
                                              position: position)

        // —— 合成到镜头容器 ——
        let bounds = rootView.bounds
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(
            x: camX * bounds.width + transition.x * bounds.width,
            y: camY * bounds.height + transition.y * bounds.height)
        transform = transform.rotated(by: camRotation + transition.rotation)
        let scale = camScale * transition.scale
        transform = transform.scaledBy(x: scale, y: scale)
        cameraView.transform = transform
        // 转场 blur 在原生以透明 + 微缩放近似（Pixi BlurFilter 无
        // 低成本等价；见报告）。glitch 以水平撕裂位移近似。
        let glitchX = transition.glitch > 0.01
            ? CGFloat(sin(transition.glitchSeed * 977.0) * transition.glitch * 14)
            : 0
        cameraView.transform = cameraView.transform
            .translatedBy(x: glitchX, y: 0)
        cameraView.alpha = transition.alpha

        // —— 字形逐帧（glyphLayout 的绝对时间求值）——
        let typoMotion = max(tuning.typographyMotion, 0)
        for entry in glyphEntries {
            let span = max(entry.settle - entry.start, 0.001)
            let raw = sonnetClamp01((position - entry.start) / span)
            // 入场进度走 ExpoOut（resolveSegmentProgress 同张力口径）。
            let p = sonnetExpoOut(raw)
            let dx = entry.enterX * CGFloat(1 - p) * CGFloat(typoMotion)
            let dy = entry.enterY * CGFloat(1 - p) * CGFloat(typoMotion)
            var t = CGAffineTransform(translationX: dx, y: dy)
            t = t.rotated(by: entry.entryRotation * CGFloat(1 - p)
                + entry.finalRotation)
            entry.label.transform = t
            entry.label.alpha = entry.isDecoration
                ? CGFloat(0.10 * p) : CGFloat(p)
        }
        // 引导线：cue 窗内描线生长后淡出（sonnetGuides 口径）。
        for guide in guideEntries {
            let span = max(guide.end - guide.start, 0.001)
            let p = sonnetClamp01((position - guide.start) / span)
            guide.layer.strokeEnd = CGFloat(sonnetEaseEnter(p))
            guide.layer.opacity = Float(
                guide.maxAlpha * (p < 0.7 ? CGFloat(p / 0.7)
                                  : CGFloat(1 - (p - 0.7) / 0.3)))
        }
        // 开放框装饰：随段入场描入（frameDecor 的 growth 口径近似）。
        for decor in frameDecorEntries {
            let span = max(decor.end - decor.start, 0.001)
            let p = sonnetClamp01((position - decor.start) / span)
            decor.view.alpha = CGFloat(0.85 * sonnetEaseEnter(p))
            let s = CGFloat(0.96 + 0.04 * sonnetExpoOut(p))
            decor.view.transform = CGAffineTransform(rotationAngle: decor.rotation)
                .scaledBy(x: s, y: s)
        }

        updatePostProcess()
        updateCredits(position: position)
    }

    func unmount() {
        isActive = false
        context = nil
        snapshot = nil
        teardownScene()
        program = []
        segmentsByLine = [:]
        grainView.backgroundColor = nil
        for label in creditsLabels { label.removeFromSuperview() }
        creditsLabels = []
        for extra in creditsExtras { extra.removeFromSuperview() }
        creditsExtras = []
    }

    // MARK: 镜头程序编译（sonnetProgram.ts）

    private func compileProgram(lines: [LyricLine], seed: String) {
        segmentsByLine = [:]
        for line in lines {
            segmentsByLine[line.id] = StageLyricUnits.units(for: line).map {
                SonnetSegment(text: $0.text, start: $0.start, end: $0.end)
            }
        }
        guard !lines.isEmpty else { program = []; return }

        // 段落间隔阈值：中位间隔 × 2.5，钳 [1.25, 3.5]。
        var gaps: [Double] = []
        for i in 1..<lines.count {
            let gap = lines[i].start - min(lines[i - 1].end, lines[i].start)
            if gap > 0 { gaps.append(gap) }
        }
        let threshold: Double
        if gaps.isEmpty {
            threshold = 1.25
        } else {
            let sorted = gaps.sorted()
            let mid = sorted.count / 2
            let median = sorted.count % 2 == 0
                ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
            threshold = sonnetClamp(median * 2.5, 1.25, 3.5)
        }

        // 按阈值切段（协议无 blockIndex/songPart，metadata 边界缺失）。
        var drafts: [[LyricLine]] = []
        var current: [LyricLine] = []
        for (index, line) in lines.enumerated() {
            if index > 0 {
                let previous = lines[index - 1]
                let renderEnd = min(previous.end, line.start)
                if line.start - renderEnd >= threshold, !current.isEmpty {
                    drafts.append(contentsOf: splitOversized(current))
                    current = []
                }
            }
            current.append(line)
        }
        if !current.isEmpty { drafts.append(contentsOf: splitOversized(current)) }

        var previousShotKind: SonnetShotKind? = nil
        var previousTransition: SonnetTransitionKind? = nil
        program = drafts.enumerated().map { (pIndex, draftLines) in
            let kind = classifyParagraph(lines: draftLines,
                                         index: pIndex, total: drafts.count)
            let shots = buildShots(lines: draftLines, kind: kind,
                                   paragraphIndex: pIndex, seed: seed,
                                   previousKind: &previousShotKind)
            let start = draftLines.first?.start ?? 0
            let end = draftLines.last?.end ?? start
            let nextStart = pIndex + 1 < drafts.count
                ? drafts[pIndex + 1].first?.start : nil
            var transitionKind: SonnetTransitionKind? = nil
            var tStart = end, tEnd = end
            if let nextStart {
                transitionKind = sonnetChoose(
                    SonnetTransitionKind.allCases,
                    seed: "\(seed):\(pIndex):transition",
                    previous: previousTransition)
                if let chosen = transitionKind {
                    previousTransition = chosen
                }
                let gap = nextStart - end
                let duration = min(0.3, max(0.16, gap > 0 ? gap * 0.5 : 0.2))
                tEnd = nextStart
                tStart = max(start, nextStart - duration)
            }
            return SonnetParagraphProgram(
                kind: kind, start: start, end: end,
                lineIndices: draftLines.map { $0.id }, shots: shots,
                transitionKind: transitionKind,
                transitionStart: tStart, transitionEnd: tEnd)
        }
    }

    /// 超限拆分（网页 splitOversizedDraft：>6 行或跨度 >18s 时
    /// 在最大间隔处切，递归至合规）。
    private func splitOversized(_ lines: [LyricLine]) -> [[LyricLine]] {
        var remaining = lines
        var output: [[LyricLine]] = []
        var guardCount = 0
        while remaining.count > 6
            || (remaining.count > 1
                && (remaining.last!.end - remaining.first!.start) > 18) {
            guardCount += 1
            if guardCount > 1000 { break }
            var bestSplit = min(4, remaining.count - 1)
            var bestGap = -Double.infinity
            if remaining.count > 3 {
                for offset in 2..<(remaining.count - 1) {
                    let gap = remaining[offset].start - remaining[offset - 1].end
                    if gap > bestGap { bestGap = gap; bestSplit = offset }
                }
            }
            bestSplit = max(1, bestSplit)
            output.append(Array(remaining[..<bestSplit]))
            remaining = Array(remaining[bestSplit...])
        }
        output.append(remaining)
        return output
    }

    /// 段落分类（网页 classifyParagraph；isChorus/songPart 协议
    /// 无字段，副歌/桥段判定以文本关键词近似，其余逐项照搬）。
    private func classifyParagraph(lines: [LyricLine], index: Int,
                                   total: Int) -> SonnetParagraphKind {
        let texts = lines.map { $0.text }
        if texts.contains(where: {
            sonnetTextContains($0, keywords: ["chorus", "副歌"])
        }) { return .chorus }
        if texts.contains(where: {
            sonnetTextContains($0, keywords: ["bridge", "break", "間奏", "ブリッジ"])
        }) {
            return .break
        }
        if index == total - 1 { return .outro }
        let duration = (lines.last?.end ?? 0) - (lines.first?.start ?? 0)
        let segmentCount = lines.reduce(0) {
            $0 + (segmentsByLine[$1.id]?.filter { $0.visibleLength > 0 }.count ?? 0)
        }
        let punctuation = texts.reduce(0) {
            $0 + $1.filter { "!?!?…".contains($0) }.count
        }
        if duration <= 3.5 || segmentCount <= 3 { return .breath }
        if punctuation >= 2 || Double(segmentCount) / max(duration, 1) > 2.5 {
            return .lift
        }
        return .verse
    }

    /// 镜头分组与选型（网页 groupShotLines + buildShots）：
    /// 每镜 ≤4 行且跨度 ≤6s；选型无重复轮转；breath 首镜短词
    /// → quiet-tableau，chorus 的 quiet → type-impact；相机自
    /// 散列字节逐项推导（x ±0.09 / y ±0.07 / zoom 基线按镜型 /
    /// rotation ±0.04）。
    private func buildShots(lines: [LyricLine], kind: SonnetParagraphKind,
                            paragraphIndex: Int, seed: String,
                            previousKind: inout SonnetShotKind?)
        -> [SonnetShotProgram] {
        var groups: [[LyricLine]] = []
        var group: [LyricLine] = []
        var groupStart: TimeInterval = 0
        for line in lines {
            if group.isEmpty {
                group = [line]
                groupStart = line.start
            } else if group.count < 4, line.end - groupStart <= 6.0 {
                group.append(line)
            } else {
                groups.append(group)
                group = [line]
                groupStart = line.start
            }
        }
        if !group.isEmpty { groups.append(group) }

        return groups.enumerated().map { (shotIndex, shotLines) in
            let signature = shotLines.map { $0.text }.joined(separator: "|")
            var shotKind = sonnetChoose(
                SonnetShotKind.allCases,
                seed: "\(seed):\(paragraphIndex):\(shotIndex):\(signature)",
                previous: previousKind)
            let wordCount = shotLines.reduce(0) {
                $0 + (segmentsByLine[$1.id]?.filter { $0.isWordLike }.count ?? 0)
            }
            if kind == .breath, shotIndex == 0, wordCount <= 2 {
                shotKind = .quietTableau
            }
            if kind == .chorus, shotKind == .quietTableau {
                shotKind = .typeImpact
            }
            previousKind = shotKind
            let random = sonnetHash(
                "\(seed):\(paragraphIndex):\(shotIndex):camera")
            let zoomRandom = Double((random >> 16) & 255) / 255
            let zoomBase = shotKind == .posterBlocks ? 1.02
                : shotKind == .quietTableau ? 1.12 : 1.22
            let zoomSpan = shotKind == .posterBlocks ? 0.16
                : shotKind == .quietTableau ? 0.20 : 0.26
            return SonnetShotProgram(
                kind: shotKind,
                start: shotLines.first?.start ?? 0,
                end: shotLines.last?.end ?? 0,
                lineIndices: shotLines.map { $0.id },
                cameraX: (Double(random & 255) / 255 - 0.5) * 0.18,
                cameraY: (Double((random >> 8) & 255) / 255 - 0.5) * 0.14,
                cameraZoom: zoomBase + zoomRandom * zoomSpan,
                cameraRotation: (Double((random >> 24) & 255) / 255 - 0.5) * 0.08)
        }
    }

    private func paragraphIndex(at position: TimeInterval) -> Int {
        for i in program.indices.reversed() {
            if position >= program[i].start { return i }
        }
        return 0
    }

    // MARK: 镜头运动（sonnetMotion.ts）

    /// 镜头路径进度（网页 resolveShotPathProgress）。
    private func shotPathProgress(kind: SonnetShotKind,
                                  progress: Double) -> Double {
        let linear = sonnetClamp01(progress)
        switch kind {
        case .trackingRibbon, .fragmentCollage, .quietTableau, .posterBlocks:
            return linear * 0.55 + sonnetEaseInOut(linear) * 0.45
        default:
            if linear < 0.18 {
                return sonnetExpoOut(linear / 0.18) * 0.22
            }
            if linear < 0.78 {
                return 0.22 + ((linear - 0.18) / 0.6) * 0.56
            }
            let settle = (linear - 0.78) / 0.22
            return 0.78 + (1 - (1 - settle) * (1 - settle)) * 0.22
        }
    }

    /// 镜头运动帧（网页 resolveShotMotionFrame 七镜型表逐项照搬；
    /// type-impact 的 scale 含入场冲击分量，按 linear 单独算）。
    private func shotMotionFrame(kind: SonnetShotKind, eased: Double,
                                 linear: Double)
        -> (x: Double, y: Double, scale: Double, rotation: Double) {
        switch kind {
        case .editorialColumn:
            return (-0.055 + eased * 0.095, 0.025 - eased * 0.04,
                    0.98 + eased * 0.07, -0.006 + eased * 0.01)
        case .typeImpact:
            let impact = (1 - sonnetExpoOut(min(linear / 0.18, 1))) * 0.22
            return (-0.035 + eased * 0.07, 0.018 - eased * 0.028,
                    1 + impact + eased * 0.08, -0.01 + eased * 0.016)
        case .fragmentCollage:
            return (-0.045 + eased * 0.085,
                    0.028 - sin(eased * .pi) * 0.055,
                    0.97 + eased * 0.09, -0.014 + eased * 0.028)
        case .trackingRibbon:
            return (-0.16 + eased * 0.28, 0.05 - eased * 0.085,
                    0.98 + eased * 0.07, 0.008 - eased * 0.014)
        case .maskReveal:
            return (0.035 - eased * 0.065, 0.1 - eased * 0.135,
                    0.96 + eased * 0.12, -0.006 + eased * 0.009)
        case .posterBlocks:
            return (-0.012 + eased * 0.024, 0.008 - eased * 0.016,
                    0.99 + eased * 0.025, -0.0015 + eased * 0.003)
        case .quietTableau:
            return (-0.022 + eased * 0.04, 0.014 - eased * 0.025,
                    1 + eased * 0.028, -0.002 + eased * 0.003)
        }
    }

    /// 相机呼吸（网页 resolveSonnetCameraBreath：双频正弦合成，
    /// 幅值 x/y 0.006 / scale 0.002 / rotation 0.0015）。
    private func cameraBreath(time: TimeInterval, phase: Double)
        -> (x: Double, y: Double, scale: Double, rotation: Double) {
        let tau = time * .pi * 2
        return (
            (sin(tau * 0.13 + phase) * 0.65
                + sin(tau * 0.31 + phase * 1.7) * 0.35) * 0.006,
            (cos(tau * 0.11 + phase * 2.3) * 0.65
                + sin(tau * 0.29 + phase * 0.9) * 0.35) * 0.006,
            sin(tau * 0.09 + phase * 1.3) * 0.002,
            sin(tau * 0.07 + phase * 2.9) * 0.0015)
    }

    // MARK: 转场（sonnetTransitions.ts + sonnetSceneFrame.ts）

    private struct TransitionFrame {
        var x: Double = 0
        var y: Double = 0
        var scale: Double = 1
        var rotation: Double = 0
        var alpha: Double = 1
        var blur: Double = 0
        var glitch: Double = 0
        var glitchSeed: Double = 0
        var isIdle: Bool {
            alpha == 1 && blur == 0 && glitch == 0 && scale == 1
        }
    }

    /// 单种转场求值（网页 resolveSonnetTransitionEffectFrame）。
    private func transitionEffect(kind: SonnetTransitionKind,
                                  phaseExit: Bool, progress: Double,
                                  seed: Int) -> TransitionFrame {
        let linear = sonnetClamp01(progress)
        let eased = sonnetEaseInOut(linear)
        let amount = phaseExit ? eased : 1 - eased
        switch kind {
        case .fastBlur:
            return TransitionFrame(alpha: 1 - amount * (phaseExit ? 1 : 0.82),
                                   blur: amount * 14)
        case .monoGlitch:
            let step = floor(linear * 14)
            let alpha = phaseExit && linear > 0.86
                ? 1 - (linear - 0.86) / 0.14 : 1
            return TransitionFrame(alpha: alpha, glitch: amount,
                                   glitchSeed: Double(seed) * 0.0001 + step * 0.173)
        case .cameraPull:
            return TransitionFrame(alpha: 1 - amount * (phaseExit ? 1 : 0.72))
        }
    }

    /// 场景转场帧（网页 resolveSonnetSceneTransitionFrame：shot
    /// 边界转场非空闲时优先，否则段落入场/出场转场）。
    private func sceneTransitionFrame(paragraphIndex pIdx: Int,
                                      shotIndex sIdx: Int,
                                      position: TimeInterval) -> TransitionFrame {
        let enabled = currentTuning.enableTransitions
        guard enabled else { return TransitionFrame() }
        let paragraph = program[pIdx]
        let seed = Int(sonnetHash("\(builtSeed):\(pIdx):transition-frame") & 0xFFFFFF)

        // shot 边界转场（sonnetTransitions.resolveSonnetShotTransitionFrame）。
        let shots = paragraph.shots
        if shots.count >= 2 {
            func boundaryKind(_ boundary: Int) -> SonnetTransitionKind {
                let mixed = UInt32(truncatingIfNeeded: seed)
                    ^ UInt32(truncatingIfNeeded: (boundary + 1) &* 0x9e3779b1)
                return SonnetTransitionKind.allCases[
                    Int(mixed) % SonnetTransitionKind.allCases.count]
            }
            if sIdx > 0 {
                let current = shots[sIdx]
                let previous = shots[sIdx - 1]
                let duration = min(0.24, max(0.14,
                    (current.start - previous.start) * 0.18))
                if position <= current.start + duration {
                    let frame = transitionEffect(
                        kind: boundaryKind(sIdx - 1), phaseExit: false,
                        progress: (position - current.start) / max(duration, 0.001),
                        seed: seed + sIdx * 97)
                    if !frame.isIdle { return frame }
                }
            }
            if sIdx + 1 < shots.count {
                let current = shots[sIdx]
                let next = shots[sIdx + 1]
                let duration = min(0.24, max(0.14,
                    (next.start - current.start) * 0.18))
                let start = next.start - duration
                if position >= start {
                    let frame = transitionEffect(
                        kind: boundaryKind(sIdx), phaseExit: true,
                        progress: (position - start) / duration,
                        seed: seed + (sIdx + 1) * 97)
                    if !frame.isIdle { return frame }
                }
            }
        }

        // 段落入场（承接上一段 transitionOut）。
        if pIdx > 0, let previous = program[pIdx - 1].transitionKind {
            let duration = max(0.16, min(0.3,
                program[pIdx - 1].transitionEnd - program[pIdx - 1].transitionStart))
            let sinceStart = position - paragraph.start
            if sinceStart >= 0, sinceStart <= duration {
                return transitionEffect(kind: previous, phaseExit: false,
                                        progress: sinceStart / duration,
                                        seed: seed)
            }
        }
        // 段落出场。
        if paragraph.transitionKind != nil,
           position >= paragraph.transitionStart {
            let span = max(paragraph.transitionEnd - paragraph.transitionStart, 0.001)
            return transitionEffect(kind: paragraph.transitionKind!,
                                    phaseExit: true,
                                    progress: (position - paragraph.transitionStart) / span,
                                    seed: seed)
        }
        return TransitionFrame()
    }

    // MARK: 场景构建

    private func teardownScene() {
        for sub in [mgView, decorView, guideView, textView] {
            for child in Array(sub.subviews) { child.removeFromSuperview() }
            for layer in Array(sub.layer.sublayers ?? []) {
                layer.removeFromSuperlayer()
            }
        }
        glyphEntries = []
        guideEntries = []
        frameDecorEntries = []
    }

    @discardableResult
    private func buildScene(paragraphIndex pIdx: Int, shotIndex sIdx: Int) -> Bool {
        teardownScene()
        guard let snapshot, program.indices.contains(pIdx) else { return false }
        let paragraph = program[pIdx]
        guard paragraph.shots.indices.contains(sIdx) else { return false }
        let shot = paragraph.shots[sIdx]
        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return false }
        let tuning = currentTuning
        let palette = snapshot.palette
        let showOnlyText = tuning.showOnlyText
        let showMG = !showOnlyText && tuning.showBackgroundMg
        let showFixedGeo = !showOnlyText && tuning.showFixedGeo
        let showDecor = !showOnlyText && tuning.showBackgroundDecor
        let showGiant = !showOnlyText && tuning.showGiantDecorativeText
        let showGuide = !showOnlyText && tuning.showGuide

        // 本镜段（按行序展开 StageLyricUnits 段）。
        var segments: [SonnetSegment] = []
        for lineId in shot.lineIndices {
            segments.append(contentsOf: segmentsByLine[lineId] ?? [])
        }
        segments = segments.filter { $0.visibleLength > 0 }
        guard !segments.isEmpty else { return true }

        // 基础字号（sonnetSceneBuilder：clamp(24, 112,
        // width / max(7, wordCount×2.15) × heroScale × fontScale)；
        // fontScale = 视口 dynamicTypeScale，本期恒 1）。
        let wordCount = max(1, segments.count)
        let heroScale: CGFloat = shot.kind == .typeImpact ? 1.55
            : shot.kind == .quietTableau ? 0.82 : 1
        let baseFontSize = max(24, min(112,
            (bounds.width / max(7, CGFloat(wordCount) * 2.15)) * heroScale))

        buildBackgroundMG(shot: shot, paragraph: paragraph,
                          showMG: showMG, showFixedGeo: showFixedGeo,
                          showDecor: showDecor, palette: palette)

        let placements = layoutPlacements(
            segments: segments, shotKind: shot.kind,
            width: bounds.width, height: bounds.height,
            baseFontSize: baseFontSize)

        // 镜头容器以画布中心为原点摆位（网页 pivot = hero 坐标、
        // position = 画布中心 + camera 偏移的等价落点：原生把
        // placements 的中心原点坐标 + 画布中心合成绝对坐标）。
        shotBaseX = bounds.width * CGFloat(0.5 + shot.cameraX)
        shotBaseY = bounds.height * CGFloat(0.48 + shot.cameraY)
            + (sIdx % 2 == 1 ? bounds.height * 0.025 : -bounds.height * 0.025)
        if shot.kind == .posterBlocks {
            shotBaseX = bounds.width * 0.5
            shotBaseY = bounds.height * 0.5
        }

        // 巨型装饰字（typographyLayout 的 decoration 段：hero 的
        // 放大副本，fontScale ×3.5 钳 [2.8, 5.5]、低透明、微旋转）。
        if showGiant {
            for placement in placements where placement.role == .hero {
                let segment = segments[placement.segmentIndex]
                let decoScale = max(2.8, min(placement.fontScale * 3.5, 5.5))
                let label = UILabel()
                label.text = segment.text
                label.font = StageFonts.light(size: baseFontSize * decoScale)
                label.textColor = palette.secondary.withAlphaComponent(0.5)
                label.alpha = 0.10
                label.sizeToFit()
                label.center = CGPoint(
                    x: shotBaseX + placement.x - bounds.width * 0.1,
                    y: shotBaseY + placement.y)
                label.transform = CGAffineTransform(rotationAngle: -0.15)
                decorView.addSubview(label)
            }
        }

        // 字形（sonnetGlyphLayout）：逐段逐字素坐标与入场向量。
        let shotDuration = max(shot.end - shot.start, 0.001)
        let preferred = min(1.8, max(0.65, shotDuration * 0.42))
        let motionDuration = min(preferred, shotDuration * 0.72)
        var glyphBudget = 180
        for placement in placements {
            let segment = segments[placement.segmentIndex]
            let fontSize = baseFontSize * placement.fontScale
            let isEmphasis = placement.role == .hero
                || placement.role == .semiHero
            let font = StageFonts.bold(size: fontSize)
            let chars = Array(segment.text)
            let usePerGlyph = glyphBudget >= chars.count
            if usePerGlyph { glyphBudget -= chars.count }
            // 字素进给：横排 = 实测宽（下限 0.2em）；竖排 = 0.9em。
            var advances: [CGFloat] = []
            for ch in chars {
                if placement.vertical {
                    advances.append(fontSize * 0.9)
                } else {
                    let w = (String(ch) as NSString)
                        .size(withAttributes: [.font: font]).width
                    advances.append(max(fontSize * 0.2, w))
                }
            }
            let total = advances.reduce(0, +)
            var cursor: CGFloat = -total / 2
            let cosine = cos(placement.rotation)
            let sine = sin(placement.rotation)
            if usePerGlyph {
                for (index, ch) in chars.enumerated() {
                    let advance = advances[index]
                    let localX = placement.vertical ? 0 : cursor + advance / 2
                    let localY = placement.vertical ? cursor + advance / 2 : 0
                    cursor += advance
                    if ch.isWhitespace { continue }
                    let label = UILabel()
                    label.text = String(ch)
                    label.font = font
                    label.textColor = palette.primary
                    label.layer.shadowColor = (isEmphasis
                        ? palette.primary : palette.accent).cgColor
                    label.layer.shadowOpacity = isEmphasis ? 0.55 : 0.35
                    label.layer.shadowRadius = 6
                    label.layer.shadowOffset = .zero
                    // textureResolution 落点：字形栅格超采样倍率
                    // （网页纹理分辨率同语义，钳 [1, 3] 防爆内存）。
                    label.layer.contentsScale = min(3, max(1,
                        CGFloat(tuning.textureResolution)))
                    label.sizeToFit()
                    let baseX = shotBaseX + placement.x
                        + localX * cosine - localY * sine
                    let baseY = shotBaseY + placement.y
                        + localX * sine + localY * cosine
                    label.center = CGPoint(x: baseX, y: baseY)
                    textView.addSubview(label)
                    let stagger: CGFloat = index % 2 == 0 ? -1 : 1
                    let glyphStart = segment.start
                        + (segment.end - segment.start)
                        * Double(index) / Double(max(chars.count, 1))
                    glyphEntries.append(SonnetGlyphEntry(
                        label: label, baseX: baseX, baseY: baseY,
                        enterX: placement.enterX
                            + (placement.vertical ? stagger * fontSize * 0.28 : 0),
                        enterY: placement.enterY
                            + (placement.vertical ? 0 : stagger * fontSize * 0.24),
                        entryRotation: stagger
                            * (isEmphasis ? 0.055 : 0.035),
                        finalRotation: placement.rotation,
                        start: glyphStart,
                        settle: glyphStart + motionDuration,
                        isDecoration: placement.role == .decoration))
                }
            } else {
                // 字形预算耗尽：整段一标签入场（保镜头构成不丢段）。
                let label = UILabel()
                label.text = segment.text
                label.font = font
                label.textColor = palette.primary
                label.sizeToFit()
                let baseX = shotBaseX + placement.x
                let baseY = shotBaseY + placement.y
                label.center = CGPoint(x: baseX, y: baseY)
                textView.addSubview(label)
                glyphEntries.append(SonnetGlyphEntry(
                    label: label, baseX: baseX, baseY: baseY,
                    enterX: placement.enterX, enterY: placement.enterY,
                    entryRotation: 0.035,
                    finalRotation: placement.rotation,
                    start: segment.start,
                    settle: segment.start + motionDuration,
                    isDecoration: placement.role == .decoration))
            }

            // 引导线（sonnetGuides：lead = clamp(0.2...0.38,
            // 0.18 + 段时长×0.1)，终点 = 段开始 + 0.65）。
            if showGuide {
                addGuide(segment: segment, placement: placement,
                         fontSize: fontSize, isEmphasis: isEmphasis,
                         palette: palette)
            }
            // 开放框装饰（sonnetFrameDecor：散列命中率 0.4）。
            if showDecor {
                addFrameDecor(segment: segment, placement: placement,
                              palette: palette)
            }
        }
        // 海报块色块在文字之下、MG 之上（poster-blocks 镜型）。
        if shot.kind == .posterBlocks, showMG {
            addPosterBlockFills(placements: placements, segments: segments,
                                palette: palette)
        }
        return true
    }

    /// 背景层（sonnetSceneBuilder 的场景背景 + sonnetShotMg 的
    /// 程序化近似）：底色微染 + 密度横线（density =
    /// round(4 + mgDensity×5)，种子点位公式照搬）；固定几何 =
    /// 种子圆环/十字线（sonnetFixedGeoVariants 的构成近似）。
    private func buildBackgroundMG(shot: SonnetShotProgram,
                                   paragraph: SonnetParagraphProgram,
                                   showMG: Bool, showFixedGeo: Bool,
                                   showDecor: Bool,
                                   palette: PaletteTokens) {
        let bounds = rootView.bounds
        guard showMG || showFixedGeo else { return }
        let seed = Int(sonnetHash("\(builtSeed):p\(sceneParagraphIndex)") & 0xFFFFFF)
        if showMG {
            let density = Int((4 + currentTuning.mgDensity * 5).rounded())
            let path = UIBezierPath()
            for index in 0..<density {
                let x = CGFloat((seed + index * 97) % 997) / 997 * bounds.width
                let y = CGFloat((seed + index * 193) % 991) / 991 * bounds.height
                let length = CGFloat(32 + (seed + index * 43) % 180)
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: min(bounds.width, x + length), y: y))
            }
            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.strokeColor = palette.accent.cgColor
            layer.lineWidth = 1
            layer.opacity = 0.16
            mgView.layer.addSublayer(layer)
        }
        if showFixedGeo {
            // 固定几何近似：画布四分点圆环 + 对角十字（种子选位）。
            let geo = CAShapeLayer()
            let path = UIBezierPath()
            let cx = bounds.width * (0.25 + CGFloat(seed % 3) * 0.25)
            let cy = bounds.height * (0.25 + CGFloat((seed >> 3) % 3) * 0.25)
            let radius = min(bounds.width, bounds.height) * 0.16
            path.append(UIBezierPath(arcCenter: CGPoint(x: cx, y: cy),
                                     radius: radius, startAngle: 0,
                                     endAngle: .pi * 2, clockwise: true))
            path.move(to: CGPoint(x: cx - radius * 1.3, y: cy))
            path.addLine(to: CGPoint(x: cx + radius * 1.3, y: cy))
            path.move(to: CGPoint(x: cx, y: cy - radius * 1.3))
            path.addLine(to: CGPoint(x: cx, y: cy + radius * 1.3))
            geo.path = path.cgPath
            geo.strokeColor = palette.secondary.cgColor
            geo.fillColor = UIColor.clear.cgColor
            geo.lineWidth = 1
            geo.opacity = 0.30
            mgView.layer.addSublayer(geo)
        }
        if showDecor {
            // 背景装饰近似：种子散点小方/小圆（粒子层构成）。
            let dots = CAShapeLayer()
            let path = UIBezierPath()
            for index in 0..<14 {
                let x = CGFloat((seed + index * 131) % 997) / 997 * bounds.width
                let y = CGFloat((seed + index * 57) % 991) / 991 * bounds.height
                path.append(UIBezierPath(
                    rect: CGRect(x: x, y: y, width: 3, height: 3)))
            }
            dots.path = path.cgPath
            dots.fillColor = palette.secondary.cgColor
            dots.opacity = 0.35
            mgView.layer.addSublayer(dots)
        }
    }

    /// 海报块底色块（sonnetPosterBlocksLayout 的 zone 底衬近似：
    /// hero/semi-hero 段背后垫 accent/secondary 半透明块）。
    private func addPosterBlockFills(placements: [SonnetPlacement],
                                     segments: [SonnetSegment],
                                     palette: PaletteTokens) {
        for placement in placements
        where placement.role == .hero || placement.role == .semiHero {
            let block = UIView()
            block.backgroundColor = (placement.role == .hero
                ? palette.accent : palette.secondary).withAlphaComponent(0.16)
            block.frame = CGRect(
                x: shotBaseX + placement.x - placement.width / 2 - 10,
                y: shotBaseY + placement.y - placement.height / 2 - 6,
                width: placement.width + 20, height: placement.height + 12)
            block.transform = CGAffineTransform(rotationAngle: placement.rotation)
            mgView.addSubview(block)
        }
    }

    /// 引导线（sonnetGuides.createSonnetGuide 的贝塞尔近似：
    /// 自 enter 向量端点三次贝塞尔收束到段中心，hero 6 形 /
    /// support 3 形的小几何以端点小十字近似）。
    private func addGuide(segment: SonnetSegment, placement: SonnetPlacement,
                          fontSize: CGFloat, isEmphasis: Bool,
                          palette: PaletteTokens) {
        let lead = min(0.38, max(0.2, 0.18 + (segment.end - segment.start) * 0.1))
        let startX = placement.enterX != 0 ? placement.enterX
            : (placement.timingPhase < 0.5 ? -1 : 1) * fontSize * 1.8
        let startY = placement.enterY != 0 ? placement.enterY : -fontSize * 0.9
        let center = CGPoint(x: shotBaseX + placement.x,
                             y: shotBaseY + placement.y)
        let path = UIBezierPath()
        let p0 = CGPoint(x: center.x + startX, y: center.y + startY)
        path.move(to: p0)
        path.addCurve(to: center,
                      controlPoint1: CGPoint(x: center.x + startX * 0.6,
                                             y: center.y + startY * 0.4),
                      controlPoint2: CGPoint(x: center.x + startX * 0.2,
                                             y: center.y + startY * 0.1))
        // 端点定位标（小十字）。
        path.move(to: CGPoint(x: center.x - 5, y: center.y))
        path.addLine(to: CGPoint(x: center.x + 5, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - 5))
        path.addLine(to: CGPoint(x: center.x, y: center.y + 5))
        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.strokeColor = (isEmphasis ? palette.accent
                             : palette.secondary).cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = isEmphasis ? 1.8 : 1
        layer.strokeEnd = 0
        guideView.layer.addSublayer(layer)
        guideEntries.append((layer: layer,
                             start: segment.start - lead,
                             end: segment.start + 0.65,
                             maxAlpha: isEmphasis ? 0.82 : 0.55))
    }

    /// 开放框（sonnetFrameDecor：命中率 0.4、四角不闭合 + 角饰；
    /// 原生以四条带角距的边线 + 角点小方近似，变体取散列 %4
    /// 决定角饰为方/圆）。
    private func addFrameDecor(segment: SonnetSegment,
                               placement: SonnetPlacement,
                               palette: PaletteTokens) {
        let hash = sonnetHash(
            "\(segment.text):\(segment.start):frame-decor")
        guard Double(hash & 1023) / 1024 < 0.4 else { return }
        let variant = Int(hash >> 10) % 4
        let pad: CGFloat = 8
        let halfW = placement.width / 2 + pad
        let halfH = placement.height / 2 + pad
        let gap: CGFloat = min(10, halfW * 0.3)
        let container = UIView()
        container.center = CGPoint(x: shotBaseX + placement.x,
                                   y: shotBaseY + placement.y)
        container.bounds = CGRect(x: 0, y: 0,
                                  width: halfW * 2, height: halfH * 2)
        container.transform = CGAffineTransform(rotationAngle: placement.rotation)
        container.alpha = 0
        let path = UIBezierPath()
        // 四边（角距 gap 不闭合，顺时针）。
        let corners = [CGPoint(x: -halfW, y: -halfH), CGPoint(x: halfW, y: -halfH),
                       CGPoint(x: halfW, y: halfH), CGPoint(x: -halfW, y: halfH)]
        for side in 0..<4 {
            let from = corners[side]
            let to = corners[(side + 1) % 4]
            let dx: CGFloat = to.x == from.x ? 0 : (to.x > from.x ? 1 : -1)
            let dy: CGFloat = to.y == from.y ? 0 : (to.y > from.y ? 1 : -1)
            path.move(to: CGPoint(x: from.x + dx * gap + halfW,
                                  y: from.y + dy * gap + halfH))
            path.addLine(to: CGPoint(x: to.x - dx * gap + halfW,
                                     y: to.y - dy * gap + halfH))
        }
        if variant % 2 == 0 {
            for corner in corners {
                path.append(UIBezierPath(
                    rect: CGRect(x: corner.x + halfW - 2.5,
                                 y: corner.y + halfH - 2.5,
                                 width: 5, height: 5)))
            }
        } else {
            for corner in corners {
                path.append(UIBezierPath(
                    arcCenter: CGPoint(x: corner.x + halfW, y: corner.y + halfH),
                    radius: 3, startAngle: 0, endAngle: .pi * 2,
                    clockwise: true))
            }
        }
        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.strokeColor = palette.secondary.cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1
        container.layer.addSublayer(layer)
        textView.addSubview(container)
        frameDecorEntries.append((view: container, start: segment.start,
                                  end: segment.end,
                                  rotation: placement.rotation))
    }

    // MARK: 排版（sonnetTypographyLayout.ts + Roles + FlowLayouts）

    /// 角色评分（sonnetTypographyRoles.scoreSonnetHeroSegment：
    /// min(可见长, 8)×14 + min(时长, 2.5)×18）。
    private func heroScore(_ segment: SonnetSegment) -> Double {
        Double(min(segment.visibleLength, 8)) * 14
            + min(2.5, max(0, segment.end - segment.start)) * 18
    }

    private func layoutPlacements(segments: [SonnetSegment],
                                  shotKind: SonnetShotKind,
                                  width: CGFloat, height: CGFloat,
                                  baseFontSize: CGFloat) -> [SonnetPlacement] {
        // —— 角色（每段集口径：网页按行算 hero/semi 后再全局取
        // hero；原生段集 = 本镜全部段，逐项套同一规则）——
        var heroIndex = segments.firstIndex { $0.isWordLike } ?? 0
        var bestScore = -Double.infinity
        for (index, segment) in segments.enumerated() where segment.visibleLength > 0 {
            let score = heroScore(segment)
            if score > bestScore { bestScore = score; heroIndex = index }
        }
        // semi-hero（Roles 常量：最小间隔 2 / 最小可见长 2 /
        // 词数门槛 4 / 分数比 0.35 / 多词门槛 9 取第二名）。
        var semiIndices: [Int] = []
        let wordLikeCount = segments.filter { $0.visibleLength > 0 }.count
        if wordLikeCount >= 4, segments.indices.contains(heroIndex) {
            let threshold = heroScore(segments[heroIndex]) * 0.35
            let candidates = segments.indices.filter {
                $0 != heroIndex
                    && segments[$0].visibleLength >= 2
                    && abs($0 - heroIndex) >= 2
                    && heroScore(segments[$0]) >= threshold
            }
            let heroLeansEarly = heroIndex <= (segments.count - 1) / 2
            let primarySide = candidates.filter {
                heroLeansEarly ? $0 > heroIndex : $0 < heroIndex
            }
            let secondarySide = candidates.filter {
                heroLeansEarly ? $0 < heroIndex : $0 > heroIndex
            }
            func bestOf(_ list: [Int]) -> Int? {
                list.max { heroScore(segments[$0]) < heroScore(segments[$1]) }
            }
            if let primary = bestOf(primarySide) ?? bestOf(secondarySide) {
                semiIndices.append(primary)
                if wordLikeCount >= 9 {
                    let rest = secondarySide.filter { abs($0 - primary) >= 2 }
                    if let secondary = bestOf(rest) { semiIndices.append(secondary) }
                }
            }
        }

        // —— 字阶（typographyLayout 的 shotKind 表；变体种子 =
        // 可见长总和 + 段数，与网页 layoutVariantSeed 同公式）——
        let variantSeed = segments.reduce(0) { $0 + max($1.visibleLength, 1) }
            + segments.count
        let editorialVariant = variantSeed % 5
        let tableauVariant = variantSeed % 4
        var heroFontScale: CGFloat = 3.0
        var supportFontScale: CGFloat = 1.15
        var verticalEmphasis = false
        switch shotKind {
        case .editorialColumn:
            if editorialVariant == 3 {
                heroFontScale = 3.8; supportFontScale = 1.3
            } else if editorialVariant == 4 {
                heroFontScale = 4.2; supportFontScale = 1.25
                verticalEmphasis = true
            } else {
                heroFontScale = editorialVariant == 2 ? 3.2 : 4.0
                supportFontScale = 1.2
                verticalEmphasis = editorialVariant != 2
            }
        case .typeImpact:
            heroFontScale = 5.5; supportFontScale = 1.5
        case .fragmentCollage:
            heroFontScale = 3.2; supportFontScale = 1.35
        case .trackingRibbon:
            heroFontScale = 3.5; supportFontScale = 1.5
        case .maskReveal:
            heroFontScale = 4.5; supportFontScale = 1.6
            verticalEmphasis = true
        case .posterBlocks:
            heroFontScale = 4.4; supportFontScale = 1.15
        case .quietTableau:
            heroFontScale = 3.0; supportFontScale = 1.15
            verticalEmphasis = tableauVariant == 0 || tableauVariant == 1
        }

        var boxes: [SonnetLayoutBox] = segments.enumerated().map { (index, segment) in
            let isHero = index == heroIndex
            let isSemi = semiIndices.contains(index)
            let fontScale = isHero ? heroFontScale
                : isSemi ? max(supportFontScale * 1.35, heroFontScale * 0.72)
                : supportFontScale
            let vertical = (isHero || isSemi) && verticalEmphasis
                && segment.text.unicodeScalars.contains {
                    (0x4E00...0x9FFF).contains($0.value)
                        || (0x3040...0x30FF).contains($0.value)
                        || (0xAC00...0xD7AF).contains($0.value)
                }
            let fontSize = baseFontSize * fontScale
            let font = StageFonts.bold(size: fontSize)
            var measuredWidth: CGFloat
            var measuredHeight: CGFloat
            if vertical {
                let chars = Array(segment.text).filter { !$0.isWhitespace }
                let maxGlyph = chars.map {
                    (String($0) as NSString)
                        .size(withAttributes: [.font: font]).width
                }.max() ?? fontSize
                measuredWidth = max(maxGlyph, fontSize * 0.2)
                measuredHeight = CGFloat(max(1, chars.count)) * fontSize * 0.9
            } else {
                measuredWidth = (segment.text as NSString)
                    .size(withAttributes: [.font: font]).width
                measuredHeight = fontSize * 1.2
            }
            // 82% 安全下缩（typographyLayout 的 fitScale）。
            var fit: CGFloat = 1
            if measuredWidth > width * 0.82 {
                fit = min(fit, width * 0.82 / measuredWidth)
            }
            if measuredHeight > height * 0.82 {
                fit = min(fit, height * 0.82 / measuredHeight)
            }
            return SonnetLayoutBox(index: index,
                       role: isHero ? .hero : isSemi ? .semiHero : .support,
                       fontScale: fontScale * fit,
                       width: measuredWidth * fit,
                       height: measuredHeight * fit,
                       vertical: vertical)
        }
        guard !boxes.isEmpty else { return [] }

        // —— 间距（resolveSonnetFlowGaps：flow = clamp(base×0.35,
        // 16, 40)，stack = max(24, flow×1.35)）——
        let flowGap = min(40, max(16, baseFontSize * 0.35))
        let stackGap = max(24, flowGap * 1.35)

        // —— 全局适配（placeWithGlobalFit：等比缩放重试阶梯，
        // 安全区半宽 0.48W / 半高 0.46H）——
        let snapshotBoxes = boxes
        for globalScale: CGFloat in [1, 0.92, 0.84, 0.76, 0.68, 0.6, 0.52] {
            for i in boxes.indices {
                boxes[i].fontScale = snapshotBoxes[i].fontScale * globalScale
                boxes[i].width = snapshotBoxes[i].width * globalScale
                boxes[i].height = snapshotBoxes[i].height * globalScale
            }
            placeBoxes(&boxes, heroIndex: heroIndex, shotKind: shotKind,
                       width: width, height: height,
                       flowGap: flowGap, stackGap: stackGap,
                       tableauVariant: tableauVariant)
            let fits = boxes.allSatisfy {
                abs($0.x) + $0.width / 2 <= width * 0.48 + 0.5
                    && abs($0.y) + $0.height / 2 <= height * 0.46 + 0.5
            }
            if fits { break }
        }

        // 时序相位（typographyLayout：段中点在全镜时间轴的归一化）。
        let midpoints = segments.map { ($0.start + $0.end) / 2 }
        let tStart = midpoints.min() ?? 0
        let tEnd = midpoints.max() ?? 0
        return boxes.map { box in
            let phase = tEnd - tStart > 0.001
                ? (midpoints[box.index] - tStart) / (tEnd - tStart)
                : Double(box.index) / Double(max(1, segments.count - 1))
            return SonnetPlacement(
                segmentIndex: box.index,
                role: box.role,
                fontScale: box.fontScale,
                width: box.width, height: box.height,
                x: box.x, y: box.y, rotation: box.rotation,
                enterX: box.role == .hero ? 0 : (box.index % 2 == 0 ? 30 : -30),
                enterY: box.role == .hero ? height * 0.15 : 0,
                vertical: box.vertical,
                timingPhase: phase)
        }
    }

    /// 各镜型的流式落位（sonnetShotFlowLayouts 的构成口径简化
    /// 落点：扫描序 = 时间序、hero 为锚、support 折行流排）。
    private func placeBoxes(_ boxes: inout [SonnetLayoutBox], heroIndex: Int,
                            shotKind: SonnetShotKind,
                            width: CGFloat, height: CGFloat,
                            flowGap: CGFloat, stackGap: CGFloat,
                            tableauVariant: Int) {
        guard boxes.indices.contains(heroIndex) else { return }
        switch shotKind {
        case .trackingRibbon:
            // 单行缎带：hero 居中，其余按序左右展开。
            boxes[heroIndex].x = 0
            boxes[heroIndex].y = 0
            var cursor = -boxes[heroIndex].width / 2 - flowGap
            for i in (0..<heroIndex).reversed() {
                boxes[i].x = cursor - boxes[i].width / 2
                boxes[i].y = (i % 2 == 0 ? 10 : -10)
                cursor -= boxes[i].width + flowGap
            }
            cursor = boxes[heroIndex].width / 2 + flowGap
            for i in (heroIndex + 1)..<boxes.count {
                boxes[i].x = cursor + boxes[i].width / 2
                boxes[i].y = (i % 2 == 0 ? 10 : -10)
                cursor += boxes[i].width + flowGap
            }
        case .quietTableau:
            // 静置 tableau：单列，hero 之上为先行段（向上）、
            // 之下为后续段（向下），读序自上而下 = 时间序。
            let horizontalCard = tableauVariant == 2 || tableauVariant == 3
            boxes[heroIndex].x = 0
            boxes[heroIndex].y = horizontalCard ? 0 : -height * 0.1
            var cursorY = boxes[heroIndex].y - boxes[heroIndex].height / 2 - stackGap
            for i in (0..<heroIndex).reversed() {
                boxes[i].x = 0
                boxes[i].y = cursorY - boxes[i].height / 2
                cursorY -= boxes[i].height + stackGap
            }
            cursorY = boxes[heroIndex].y + boxes[heroIndex].height / 2 + stackGap
            for i in (heroIndex + 1)..<boxes.count {
                boxes[i].x = 0
                boxes[i].y = cursorY + boxes[i].height / 2
                cursorY += boxes[i].height + stackGap
            }
        case .posterBlocks:
            // 海报块分区流（posterBlocksLayout 的行流近似）：
            // 按读序左→右折行，hero/semi 为大区、support 填充。
            let maxRowWidth = width * 0.84
            var cursorX: CGFloat = -maxRowWidth / 2
            var cursorY: CGFloat = -height * 0.30
            var rowHeight: CGFloat = 0
            for i in boxes.indices {
                if cursorX + boxes[i].width > maxRowWidth / 2, cursorX > -maxRowWidth / 2 {
                    cursorX = -maxRowWidth / 2
                    cursorY += rowHeight + stackGap
                    rowHeight = 0
                }
                boxes[i].x = cursorX + boxes[i].width / 2
                boxes[i].y = cursorY + boxes[i].height / 2
                cursorX += boxes[i].width + flowGap
                rowHeight = max(rowHeight, boxes[i].height)
            }
            // 整块纵向居中回正。
            let totalHeight = cursorY + rowHeight + height * 0.30
            for i in boxes.indices { boxes[i].y -= totalHeight / 2 }
        default:
            // editorial-column / type-impact / fragment-collage /
            // mask-reveal 的 cross-stack 近似：hero 居中偏上，
            // support 按时间序在 hero 下方折行流排（先行段先排）。
            boxes[heroIndex].x = 0
            boxes[heroIndex].y = -height * 0.08
            let maxRowWidth = width * 0.84
            var cursorX: CGFloat = -maxRowWidth / 2
            var cursorY = boxes[heroIndex].y + boxes[heroIndex].height / 2 + stackGap
            var rowHeight: CGFloat = 0
            let order = boxes.indices.filter { $0 != heroIndex }
            for i in order {
                if cursorX + boxes[i].width > maxRowWidth / 2, cursorX > -maxRowWidth / 2 {
                    cursorX = -maxRowWidth / 2
                    cursorY += rowHeight + stackGap
                    rowHeight = 0
                }
                boxes[i].x = cursorX + boxes[i].width / 2
                boxes[i].y = cursorY + boxes[i].height / 2
                cursorX += boxes[i].width + flowGap
                rowHeight = max(rowHeight, boxes[i].height)
            }
            if shotKind == .fragmentCollage {
                for i in boxes.indices where i != heroIndex {
                    boxes[i].rotation = (i % 2 == 0 ? -1 : 1) * 0.04
                }
            }
        }
    }

    // MARK: 外框（entry 的海报式边框 + sceneBuilder 的主题元数据）

    /// outerFrameMode：none 无 / frame 边框+四角 /
    /// full 再加曲目标题·艺人竖排元数据（网页主题名/描述的原生
    /// 落点为当前曲目元数据，协议无 theme 字段）。
    private func updateFrameOverlay() {
        for label in frameLabels { label.removeFromSuperview() }
        frameLabels = []
        guard let snapshot else {
            frameBorderLayer.path = nil
            return
        }
        let mode = SonnetTuningStore.cachedSnapshot(
            now: CACurrentMediaTime()).outerFrameMode
        guard mode != .none else {
            frameBorderLayer.path = nil
            return
        }
        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        let inset: CGFloat = 14
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let corner: CGFloat = 22
        let path = UIBezierPath()
        // 四角 L 形（不闭合全框，海报式角标）。
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
        ]
        for (point, sx, sy) in corners {
            path.move(to: CGPoint(x: point.x + corner * sx, y: point.y))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x, y: point.y + corner * sy))
        }
        if mode == .full {
            path.append(UIBezierPath(rect: rect))
        }
        frameBorderLayer.path = path.cgPath
        frameBorderLayer.strokeColor = snapshot.palette.primary
            .withAlphaComponent(0.5).cgColor
        frameBorderLayer.lineWidth = 1

        if mode == .full, let track = snapshot.track {
            let titleLabel = UILabel()
            titleLabel.text = track.title.uppercased()
            titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            titleLabel.textColor = snapshot.palette.primary.withAlphaComponent(0.65)
            titleLabel.sizeToFit()
            titleLabel.frame.origin = CGPoint(x: inset + 8, y: inset + 6)
            frameOverlayView.addSubview(titleLabel)
            frameLabels.append(titleLabel)
            if !track.artist.isEmpty {
                let artistLabel = UILabel()
                artistLabel.text = track.artist
                artistLabel.font = .systemFont(ofSize: 12, weight: .regular)
                artistLabel.textColor = snapshot.palette.secondary
                    .withAlphaComponent(0.6)
                artistLabel.sizeToFit()
                artistLabel.frame.origin = CGPoint(
                    x: bounds.width - inset - 8 - artistLabel.bounds.width,
                    y: inset + 6)
                frameOverlayView.addSubview(artistLabel)
                frameLabels.append(artistLabel)
            }
        }
    }

    // MARK: 片尾海报（sonnetCredits.ts）

    private func updateCreditsContent() {
        for label in creditsLabels { label.removeFromSuperview() }
        creditsLabels = []
        for extra in creditsExtras { extra.removeFromSuperview() }
        creditsExtras = []
        guard let snapshot, let track = snapshot.track else { return }
        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        let palette = snapshot.palette
        let left = max(38, bounds.width * 0.105)
        let contentWidth = max(220, bounds.width - left - max(38, bounds.width * 0.09))
        let titleSize = max(42, min(118, bounds.width * 0.088))
        var y = bounds.height * 0.30
        let titleLabel = UILabel()
        titleLabel.text = track.title
        titleLabel.font = StageFonts.bold(size: titleSize)
        titleLabel.textColor = palette.primary
        titleLabel.numberOfLines = 2
        titleLabel.frame = CGRect(x: left, y: y, width: contentWidth,
                                  height: titleSize * 2.4)
        creditsView.addSubview(titleLabel)
        creditsLabels.append(titleLabel)
        y += titleSize * 2.4 + 18
        for detail in [track.artist, track.album] where !detail.isEmpty {
            let label = UILabel()
            label.text = detail
            label.font = .systemFont(ofSize: max(13, min(25, bounds.width * 0.018)),
                                     weight: .medium)
            label.textColor = palette.secondary
            label.frame = CGRect(x: left, y: y, width: contentWidth, height: 30)
            creditsView.addSubview(label)
            creditsLabels.append(label)
            y += 34
        }
        // accent 分隔线（credits 海报的强调线）。
        let rule = UIView()
        rule.backgroundColor = palette.accent
        rule.frame = CGRect(x: left, y: bounds.height * 0.30 - 16,
                            width: 54, height: 3)
        creditsView.addSubview(rule)
        creditsExtras.append(rule)
    }

    /// 片尾帧（resolveSonnetCreditsFrame：歌词 1.25s 失焦退出、
    /// 海报延迟 0.38 后 1.55s 入场，offsetY 0.04、scale 0.965→1；
    /// lyricBlur 原生以透明近似）。
    private func updateCredits(position: TimeInterval) {
        guard let snapshot, let last = snapshot.lines.last else {
            creditsView.alpha = 0
            return
        }
        let elapsed = position - last.end
        guard elapsed > 0 else {
            creditsView.alpha = 0
            cameraView.alpha = min(cameraView.alpha, 1)
            return
        }
        let lyricExit = sonnetEaseInOut(sonnetClamp01(elapsed / 1.25))
        let posterEnter = sonnetEaseInOut(
            sonnetClamp01((elapsed - 0.38) / 1.55))
        creditsView.alpha = CGFloat(posterEnter)
        let offsetY = CGFloat(1 - posterEnter) * 0.04 * rootView.bounds.height
        let scale = CGFloat(0.965 + posterEnter * 0.035)
        creditsView.transform = CGAffineTransform(translationX: 0, y: offsetY)
            .scaledBy(x: scale, y: scale)
        if lyricExit > 0 {
            cameraView.alpha = min(cameraView.alpha, CGFloat(1 - lyricExit))
        }
    }

    // MARK: 后处理（sonnetPostProcess.ts 的量级近似）

    /// glow/颗粒/暗角的原生近似：暗角层不透明度 = vignette 量
    /// （后处理关时网页 vignette=0，但基础暗角保留 0.25 的可读
    /// 性底）；颗粒 = 预生成 64×64 噪声平铺（一次性小图，非无
    /// 界缓存）；contrast/rgbShift/halftone/lens 在原生无滤镜
    /// 链，lensDistortion 以镜头微缩放近似、余项未落（见报告）。
    private func updatePostProcess() {
        let tuning = currentTuning
        let vignette = tuning.postProcessEnabled
            ? tuning.postProcessVignette : 0.3
        vignetteLayer.opacity = Float(min(0.85, vignette * 0.55))
        if tuning.postProcessEnabled, tuning.postProcessGrain > 0 {
            if grainView.backgroundColor == nil {
                grainView.backgroundColor = UIColor(
                    patternImage: Self.makeNoiseImage())
            }
            grainView.alpha = CGFloat(tuning.postProcessGrain * 0.35)
        } else {
            grainView.alpha = 0
        }
    }

    private static func makeNoiseImage() -> UIImage {
        let size = 64
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: size, height: size))
        return renderer.image { context in
            for x in 0..<size {
                for y in 0..<size {
                    let v = CGFloat(stageSeededRandom(Double(x * 131 + y * 57)))
                    context.cgContext.setFillColor(
                        UIColor(white: v, alpha: 0.5).cgColor)
                    context.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    // MARK: 无歌词兜底（VisualizerSonnet 的 fallback 文案位）

    private func updateFallback(position: TimeInterval) {
        teardownScene()
        sceneKey = "fallback"
        guard let snapshot, let track = snapshot.track else {
            fallbackLabel.alpha = 0
            return
        }
        let size = max(32, min(90, rootView.bounds.width * 0.054 * 16 / 10))
        fallbackLabel.font = StageFonts.bold(size: size)
        fallbackLabel.textColor = snapshot.palette.primary
        fallbackLabel.text = track.title
        fallbackLabel.alpha = 1
        creditsView.alpha = 0
    }

    // MARK: 布局

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 1)

        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        backdropView.frame = bounds
        cameraView.frame = bounds
        for layer in [mgView, decorView, guideView, textView] {
            layer.frame = bounds
        }
        frameOverlayView.frame = bounds
        frameBorderLayer.frame = bounds
        vignetteLayer.frame = bounds
        grainView.frame = bounds
        creditsView.frame = bounds
        fallbackLabel.frame = bounds.insetBy(dx: 40, dy: 0)
        // 旋转 / 尺寸变化：场景键含尺寸，下一帧自动重建；外框与
        // 片尾内容即时重排。
        updateFrameOverlay()
        updateCreditsContent()
    }
}

// MARK: - 文本近似判定（classifyParagraph 的关键词口径）

private func sonnetTextContains(_ text: String, keywords: [String]) -> Bool {
    let lower = text.lowercased()
    return keywords.contains { lower.contains($0) }
}

/// 排版盒（sonnetShotFlowLayouts 的 SonnetFlowLayoutBox 子集）。
private struct SonnetLayoutBox {
    var index: Int
    var role: SonnetRole
    var fontScale: CGFloat
    var width: CGFloat
    var height: CGFloat
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotation: CGFloat = 0
    var vertical: Bool
}
