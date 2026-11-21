import UIKit
import QuartzCore

// 心象 cadenza（M2' 照搬对齐版）：按 folia-major 网页版 cadenza
// （VisualizerCadenza.tsx + cadenzaFragments / cadenzaPlacements /
// cadenzaEnvelopes / cadenzaOverlayNodes / cadenzaPreparedState）
// 的展示行为逐项实现。照搬要点：
//  - 准备态（preparedState）：按视口宽与行长/词数定字号
//    （chooseFontPx + tuning.fontScale 1.12），按 maxWidth
//    （widthRatio 0.72 × 换行压缩）把一行词贪心折成若干布局行，
//    再切成片段（fragment）——原生无 pretext，折行以 UIKit
//    实测词宽贪心等价实现，词不跨行拆分（见档案差异）。
//  - 落点（placements）：强调权重选 hero 词（1.46×scoreBoost），
//    其余词以种子伪随机（seed = 行 start×1000 + 词序×17 +
//    布局行×31 + 片段×13，fract(sin×10000)，与共享件
//    stageSeededRandom 同公式）做碰撞回避螺旋搜索
//    （cadenzaPlacements 的带状碰撞求值在此以等价暴力求和
//    实现，结果一致），passed 漂移沿背离中心方向。
//  - 包络（envelopes）：词三态 waiting/active/passed、辉光
//    包络、正文混色、passed 漂移、整行进出场包络与行时序
//    （renderHints 的 timingClass/transitionTiming）全部按
//    cadenzaEnvelopes.ts 与 renderHints.ts 公式逐项移植；
//    行时序由行时长自行推导（协议行不带 renderHints）。
//  - 逐帧驱动（VisualizerCadenza 的 draw 循环）：动画状态以
//    指数平滑（变换 1−exp(−11dt)、视觉 1−exp(−14dt)、辉光
//    1−exp(−16dt)）向目标迁移，dt 为帧间隔（钳制与网页同），
//    播放位置只消费宿主 frameTick 喂入值，不自建时钟源。
// 数据源降级（协议核对结论，详见交付档案）：
//  - 频谱/能量：宿主 requiresSpectrum=false、无 audioPower
//    数据；网页 energy 只以标量参与 verticalLift 幅度、
//    localFloat 与 glow blurScale，energy=0 时公式自然退化，
//    故按 energy≡0 落地（motionEnergy=0、blurScale=1），
//    requiresSpectrum 填 false。
//  - 逐字戳：经共享 StageLyricUnits 取词时序——有 YRC 覆盖
//    的行用真戳、无覆盖行用行内均分兜底（与网页无逐字数据
//    时 even grapheme timing 同口径）；wordColors 缺失 → 每词颜色恒为
//    palette.accent（网页 resolveWordColor 的回退色）；
//  - isChorus 缺失 → 副歌涟漪永不触发；animationIntensity
//    缺失 → 恒 normal 档（baseMargin 6、baseScale 1.01、
//    passedAlpha 0.82、passedRotate ±6°、透视 1000）；
//  - tuning（(57) C1 接线）：经 CadenzaTuningStore 门面读
//    （UserDefaults "folia.tuning.cadenza."，缺省 =
//    DEFAULT_CADENZA_TUNING：fontScale 1.12、widthRatio 0.72、
//    motionAmount 1、glowIntensity 1、beamIntensity 0 网页已
//    废弃恒 0）；render 分辨率覆盖无 UIKit 画布消费点，仅
//    门面存档（见 CadenzaTuning.swift 文件头注）。
// 时钟纪律不变：只消费宿主 frameTick 的锚点位置。

// MARK: - cadenza 专用数据结构

/// 行时序（renderHints.ts + cadenzaEnvelopes.resolveLineRenderTiming
/// 的原生推导版：协议行只有 start/end，按网页同一阈值推导）。
private struct CadenzaLineTiming {
    var wordRevealMode: Int  // 0 normal / 1 fast / 2 instant
    var transitionMode: Int  // 0 normal / 1 fast / 2 none
    var lineRenderEndTime: TimeInterval
    var lastWordEndTime: TimeInterval
    var linePassHold: TimeInterval
    var enterDuration: TimeInterval
    var exitDuration: TimeInterval
}

private func cadenzaClamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    max(lo, min(hi, v))
}
private func cadenzaMix(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}
private func cadenzaEaseOutCubic(_ v: Double) -> Double {
    1 - pow(1 - cadenzaClamp(v, 0, 1), 3)
}
private func cadenzaEaseInOutQuad(_ v: Double) -> Double {
    let n = cadenzaClamp(v, 0, 1)
    return n < 0.5 ? 2 * n * n : 1 - pow(-2 * n + 2, 2) / 2
}

/// renderHints.getLineTransitionTiming 逐项移植。
private func cadenzaTransitionTiming(rawDuration: Double, transitionMode: Int,
                                     wordRevealMode: Int)
    -> (enter: Double, exit: Double, hold: Double) {
    if transitionMode == 2 {
        return (0, 0, 0)
    }
    if transitionMode == 1 {
        return (cadenzaClamp(rawDuration * 0.45, 0.045, 0.06),
                cadenzaClamp(rawDuration * 0.22, 0.03, 0.04),
                wordRevealMode == 2 ? 0 : 0.03)
    }
    return (min(0.42, max(0.22, max(rawDuration, 0.12) * 0.34)),
            min(0.32, max(0.18, max(rawDuration, 0.12) * 0.18)),
            wordRevealMode == 2 ? 0 : 0.06)
}

/// 由行时长推导完整行时序（阈值 0.10/0.18 与 renderHints 同）。
private func cadenzaResolveTiming(line: LyricLine) -> CadenzaLineTiming {
    let rawDuration = max(line.end - line.start, 0)
    let timingClass: Int = rawDuration < 0.10 ? 2 : (rawDuration < 0.18 ? 1 : 0)
    // timingClass: 0 normal / 1 short / 2 micro；transition 与
    // wordReveal 的映射与 renderHints 的 get*Mode 一一对应。
    let transitionMode: Int = timingClass == 2 ? 2 : (timingClass == 1 ? 1 : 0)
    let wordRevealMode: Int = timingClass == 2 ? 2 : (timingClass == 1 ? 1 : 0)
    let timing = cadenzaTransitionTiming(
        rawDuration: rawDuration, transitionMode: transitionMode,
        wordRevealMode: wordRevealMode)
    let lastWordEnd = line.end
    let linePassStart = max(lastWordEnd, line.start) + timing.hold
    let renderEnd: TimeInterval
    if transitionMode == 2 {
        renderEnd = max(line.end, line.start + 0.067)
    } else if transitionMode == 1 {
        let exitStart = max(line.start + timing.enter + 0.01,
                            linePassStart, line.end - timing.exit)
        renderEnd = max(line.end, exitStart + timing.exit)
    } else {
        let exitStart = max(linePassStart, line.end - timing.exit)
        renderEnd = max(line.end, exitStart + timing.exit)
    }
    return CadenzaLineTiming(
        wordRevealMode: wordRevealMode, transitionMode: transitionMode,
        lineRenderEndTime: renderEnd, lastWordEndTime: lastWordEnd,
        linePassHold: timing.hold,
        enterDuration: timing.enter, exitDuration: timing.exit)
}

// MARK: - 包络（cadenzaEnvelopes.ts 逐项移植）

private enum CadenzaEnvelopes {

    static let activePulseFrequency: Double = 10

    /// getWordStatus：lookahead normal 0.18 / fast 0.045 /
    /// instant 0；instant 的 activeEnd 为整行 renderEnd。
    static func wordStatus(time: TimeInterval, timing: CadenzaLineTiming,
                           wordStart: TimeInterval, wordEnd: TimeInterval) -> Int {
        let lookahead: TimeInterval = timing.wordRevealMode == 1 ? 0.045
            : (timing.wordRevealMode == 2 ? 0 : 0.18)
        let activeEnd = timing.wordRevealMode == 2
            ? timing.lineRenderEndTime : wordEnd
        if time >= wordStart - lookahead && time <= activeEnd { return 1 }
        if time > activeEnd { return 2 }
        return 0
    }

    /// getWordProgress。
    static func wordProgress(time: TimeInterval, timing: CadenzaLineTiming,
                             wordStart: TimeInterval, wordEnd: TimeInterval) -> Double {
        if timing.wordRevealMode == 2 {
            return time < wordStart ? 0 : 1
        }
        let minDuration: TimeInterval = timing.wordRevealMode == 1 ? 0.045 : 0.01
        let duration = max(wordEnd - wordStart, minDuration)
        return cadenzaClamp((time - wordStart) / duration, 0, 1)
    }

    /// getClassicKeyframedGlow：0.3 处达峰的键帧辉光。
    static func keyframedGlow(progress: Double) -> Double {
        if progress <= 0 || progress >= 1 { return 0 }
        if progress < 0.3 {
            return cadenzaEaseOutCubic(progress / 0.3)
        }
        return 1 - cadenzaClamp((progress - 0.3) / 0.7, 0, 1)
    }

    /// getClassicGlowEnvelope（整词辉光包络，三种 reveal 模式）。
    static func glowEnvelope(time: TimeInterval, timing: CadenzaLineTiming,
                             wordStart: TimeInterval, wordEnd: TimeInterval) -> Double {
        if timing.wordRevealMode == 2 {
            if time < wordStart || time > timing.lineRenderEndTime { return 0 }
            let pulseProgress = cadenzaClamp((time - wordStart) / 0.067, 0, 1)
            return keyframedGlow(progress: pulseProgress)
        }
        if timing.wordRevealMode == 1 {
            let duration = max(wordEnd - wordStart, 0.045)
            if time < wordStart { return 0 }
            if time <= wordEnd {
                let progress = cadenzaClamp((time - wordStart) / duration, 0, 1)
                if progress < 0.14 { return cadenzaEaseOutCubic(progress / 0.14) }
                if progress < 0.82 { return 1 }
                return cadenzaMix(1, 0.92, (progress - 0.82) / 0.18)
            }
            let fadeOut = cadenzaClamp((time - wordEnd) / 0.14, 0, 1)
            return pow(1 - fadeOut, 2)
        }
        let duration = max(wordEnd - wordStart, 0.1)
        if time < wordStart { return 0 }
        if time <= wordEnd {
            let progress = cadenzaClamp((time - wordStart) / duration, 0, 1)
            if progress < 0.18 { return cadenzaEaseOutCubic(progress / 0.18) }
            if progress < 0.9 { return 1 }
            return cadenzaMix(1, 0.9, (progress - 0.9) / 0.1)
        }
        let fadeOut = cadenzaClamp((time - wordEnd) / 0.9, 0, 1)
        return 0.9 * pow(1 - fadeOut, 2)
    }

    /// getClassicCharGlow（逐字素辉光；字素时刻缺失时按词内均分，
    /// 与 buildWordGraphemeTimings 的 even 口径一致，调用方已把
    /// 均分时刻填进 glyphTimings）。
    static func charGlow(time: TimeInterval, wordStart: TimeInterval,
                         wordEnd: TimeInterval, glyphIndex: Int,
                         glyphCount: Int,
                         glyphTimings: [(start: TimeInterval, end: TimeInterval)]) -> Double {
        let duration = max(wordEnd - wordStart, 0.1)
        let singleDuration = duration / Double(max(glyphCount, 1))
        let timing: (start: TimeInterval, end: TimeInterval)?
            = glyphIndex < glyphTimings.count ? glyphTimings[glyphIndex] : nil
        let charDuration = timing != nil
            ? max(timing!.end - timing!.start, 0.001)
            : singleDuration
        let charStart = timing?.start ?? (wordStart + singleDuration * Double(glyphIndex))
        let animationDuration = charDuration * 6
        let elapsed = time - charStart
        let activeGlow = elapsed <= 0 ? 0
            : keyframedGlow(progress: elapsed / animationDuration)
        if time <= wordEnd { return activeGlow }
        let fadeOut = pow(1 - cadenzaClamp((time - wordEnd) / 0.9, 0, 1), 2)
        return activeGlow * fadeOut
    }

    /// getClassicBodyMix（正文主色→词色混合量）。
    static func bodyMix(time: TimeInterval, timing: CadenzaLineTiming,
                        wordStart: TimeInterval, wordEnd: TimeInterval) -> Double {
        if timing.wordRevealMode == 2 {
            if time < wordStart { return 0 }
            return time <= timing.lineRenderEndTime ? 1 : 0
        }
        if time < wordStart { return 0 }
        if time <= wordEnd {
            return wordProgress(time: time, timing: timing,
                                wordStart: wordStart, wordEnd: wordEnd)
        }
        let fadeOut = cadenzaClamp(
            (time - wordEnd) / (timing.wordRevealMode == 1 ? 0.12 : 0.8), 0, 1)
        return 1 - fadeOut
    }

    /// getClassicLineEnvelope（整行进出场：透明/缩放/模糊）。
    static func lineEnvelope(time: TimeInterval, line: LyricLine,
                             timing: CadenzaLineTiming)
        -> (opacity: Double, scale: Double, blur: Double) {
        if timing.transitionMode == 2 {
            return (1, 1, 0)
        }
        let lineEndTime = timing.lineRenderEndTime
        let linePassStart = max(timing.lastWordEndTime, line.start)
            + timing.linePassHold
        if timing.transitionMode == 1 {
            let enterDuration = timing.enterDuration
            let exitDuration = timing.exitDuration
            let exitStart = max(line.start + enterDuration + 0.01,
                                linePassStart, lineEndTime - exitDuration)
            let enterProgress = cadenzaEaseOutCubic(
                cadenzaClamp((time - line.start) / enterDuration, 0, 1))
            var opacity = cadenzaMix(0.65, 1, enterProgress)
            var scale = cadenzaMix(0.97, 1, enterProgress)
            var blur = cadenzaMix(4, 0, enterProgress)
            let exitProgress = cadenzaEaseOutCubic(
                cadenzaClamp((time - exitStart) / exitDuration, 0, 1))
            if exitProgress > 0 {
                opacity = cadenzaMix(opacity, 0, exitProgress)
                scale = cadenzaMix(scale, 1.03, exitProgress)
                blur = max(blur, cadenzaMix(0, 6, exitProgress))
            }
            return (cadenzaClamp(opacity, 0, 1), scale, blur)
        }
        let enterDuration = timing.enterDuration
        let exitDuration = timing.exitDuration
        let preEnter = min(0.1, enterDuration * 0.35)
        let enterProgress = cadenzaEaseOutCubic(cadenzaClamp(
            (time - (line.start - preEnter)) / (enterDuration + preEnter), 0, 1))
        var opacity = cadenzaMix(0, 1, enterProgress)
        var scale = cadenzaMix(0.9, 1, enterProgress)
        var blur = cadenzaMix(10, 0, enterProgress)
        let exitStart = max(linePassStart, lineEndTime - exitDuration)
        let exitProgress = cadenzaEaseOutCubic(
            cadenzaClamp((time - exitStart) / exitDuration, 0, 1))
        if exitProgress > 0 {
            opacity *= 1 - exitProgress
            scale = cadenzaMix(scale, 1.1, exitProgress)
            blur = max(blur, cadenzaMix(0, 20, exitProgress))
        }
        return (cadenzaClamp(opacity, 0, 1), scale, blur)
    }

    /// getClassicPassedDrift：词结束后 5s 内 easeInOutQuad 到 1。
    static func passedDrift(time: TimeInterval, wordEnd: TimeInterval) -> Double {
        if time <= wordEnd { return 0 }
        return cadenzaEaseInOutQuad(cadenzaClamp((time - wordEnd) / 5, 0, 1))
    }
}

// MARK: - 落点与准备态

/// 一个落点（cadenzaTypes.WordPlacement 的原生子集）。
private struct CadenzaPlacement {
    var id: String
    var wordIndex: Int
    var text: String
    var wordStart: TimeInterval
    var wordEnd: TimeInterval
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var rotate: CGFloat
    var scale: CGFloat
    var passedRotate: CGFloat
    var passedDriftX: CGFloat
    var passedDriftY: CGFloat
    var entryOffsetX: CGFloat
    var entryOffsetY: CGFloat
    var fragmentStartInWord: Int
    var wordGraphemeCount: Int
    var glyphTimings: [(start: TimeInterval, end: TimeInterval)]
    var emphasis: CGFloat
    var isInterlude: Bool
}

/// 布局行内的一个片段（cadenzaFragments.WordFragment 的原生
/// 子集；原生词不跨行拆分，片段即整词在布局行内的切片）。
private struct CadenzaLayoutFragment {
    var unitIndex: Int
    var startX: CGFloat
    var endX: CGFloat
}

/// 一行的完整准备态（cadenzaPreparedState.PreparedState 对应物）。
private struct CadenzaPreparedState {
    var lineId: Int
    var fontPx: CGFloat
    var lineHeight: CGFloat
    var maxWidth: CGFloat
    var timing: CadenzaLineTiming
    var placements: [CadenzaPlacement]
}

/// 逐帧动画状态（cadenzaTypes.AnimatedPlacementState 对应物；
/// blur 按网页同式推进但原生不渲染逐词模糊，见档案差异）。
private struct CadenzaAnimatedState {
    var x: Double
    var y: Double
    var rotation: Double
    var scale: Double
    var bodyAlpha: Double
    var blur: Double
    var activeMix: Double
    var glowAlpha: Double
    /// 逐词强调弹簧状态（3.7 (50)，与 GlowWord 系同参数）：
    /// 强调值与速度，随本状态同生命周期（跨行同 id 延续）。
    var emphasisValue: Double = 1
    var emphasisVelocity: Double = 0
}

// MARK: - 单词视图（cadenzaOverlayNodes 的原生对应物）

/// 正文层 + 辉光层（逐字素标签靠 CALayer 阴影出晕，与共享
/// GlowWordView 同拟合口径：网页三层 40px text-shadow 以
/// 单层阴影半径 40×0.4=16 近似，强度走 shadowOpacity）。
private final class CadenzaWordView: UIView {

    let placement: CadenzaPlacement
    let glyphs: [String]
    let isCJKText: Bool
    let splitGlow: Bool
    private let contentView = UIView()
    private let bodyLabel = UILabel()
    private var glowLabels: [UILabel] = []
    /// 逐词强调辉光（3.7 (50)）：暖金同文标签，垫在正文之下。
    private let emphasisGlowLabel = UILabel()
    /// 超采样倍率与逻辑字号（强调变换合成用，见 applyEmphasis）。
    private let renderScale: CGFloat
    private let fontPx: CGFloat

    init(placement: CadenzaPlacement, font: UIFont, splitGlow: Bool) {
        self.placement = placement
        self.glyphs = placement.text.map { String($0) }
        self.isCJKText = CadenzaStageRenderer.isCJKText(placement.text)
        self.splitGlow = splitGlow
        // 强调栅格余量（3.7 (50)，与 GlowWordView 同口径）：强
        // 调开启时按词时长预留放大余量（长音 1.9 / 短词 1.38、
        // 上限放宽到 3），否则强调放大后清晰度跌回 (47) 前；
        // 关闭时与 (47) 原口径逐字一致（×1.05、上限 2）。
        let emphasisOn = StageEffectSettings.wordEmphasisEnabled
        let wordDuration = placement.wordEnd - placement.wordStart
        let emphasisHeadroom: CGFloat = emphasisOn
            ? (wordDuration >= 1.0 ? 1.9 : 1.38) : 1
        let rawScaleInit = placement.scale * 1.05 * emphasisHeadroom
        self.renderScale = rawScaleInit <= 1.05
            ? 1 : min(emphasisOn ? 3 : 2, ceil(rawScaleInit * 4) / 4)
        self.fontPx = font.pointSize
        super.init(frame: CGRect(x: 0, y: 0,
                                 width: placement.width,
                                 height: placement.height))
        isUserInteractionEnabled = false
        // 旋转/缩放枢轴 = 网页 overlay anchor（词宽中点、
        // baseline 上方 height×0.42 处）：anchorPoint 取
        // (0.5, 0)，position 即 anchor 点，本地 y 由下方
        // 标签布局把 baseline 落到 height×0.42。
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)

        // 超采样（3.7 (47) 清晰度修复）：词视图由逐帧
        // transform 放大到 placement.scale（hero 词最高约
        // 1.56）为常态，UILabel 按逻辑 bounds 栅格化必然
        // 发软。内部按 renderScale 倍字号/几何构建、内容
        // 容器反向缩放回逻辑尺寸（锚点与本视图同为
        // (0.5, 0)，枢轴不变），逐帧 transform 与包络参数
        // 一字不动。renderScale 的计算（含 (50) 强调余量）
        // 在 init 属性段完成，此处只取用。
        let r = renderScale
        let rFont = font.withSize(font.pointSize * r)
        contentView.layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        contentView.bounds = CGRect(
            x: 0, y: 0,
            width: placement.width * r, height: placement.height * r)
        // 锚点 (0.5, 0) 必须落在父视图顶边中点：用 layer
        // .position 直定锚点位置（center 在非中心锚点下会
        // 按 frame 中心换算、整体上移半高）。
        contentView.layer.position = CGPoint(x: placement.width / 2, y: 0)
        if r != 1 {
            contentView.transform = CGAffineTransform(scaleX: 1 / r, y: 1 / r)
        }
        contentView.isUserInteractionEnabled = false
        addSubview(contentView)

        let labelY = (placement.height * 0.42 - font.ascender) * r
        let glowTexts = splitGlow ? glyphs : [placement.text]
        var gx: CGFloat = 0
        for text in glowTexts {
            let label = UILabel()
            label.text = text
            label.font = rFont
            label.textColor = .white
            label.layer.shadowOffset = .zero
            label.layer.shadowRadius = 16 * r
            label.sizeToFit()
            label.frame = CGRect(x: gx, y: labelY,
                                 width: label.bounds.width,
                                 height: label.bounds.height)
            gx += label.bounds.width
            glowLabels.append(label)
            contentView.addSubview(label)
        }
        // 逐词强调辉光标签（3.7 (50)）：与正文同字同位，暖金
        // 色 + 同色大半径阴影，alpha 恒由 applyEmphasis 驱动
        // （静止 0）；颜色不取样式 accent，与 GlowWord 系同口径。
        emphasisGlowLabel.text = placement.text
        emphasisGlowLabel.font = rFont
        let warmGold = UIColor(red: 1.0, green: 0.76, blue: 0.32, alpha: 1)
        emphasisGlowLabel.textColor = warmGold
        emphasisGlowLabel.layer.shadowColor = warmGold.cgColor
        emphasisGlowLabel.layer.shadowOpacity = 1
        emphasisGlowLabel.layer.shadowRadius = 16 * r
        emphasisGlowLabel.layer.shadowOffset = .zero
        emphasisGlowLabel.sizeToFit()
        emphasisGlowLabel.frame = CGRect(x: 0, y: labelY,
                                         width: emphasisGlowLabel.bounds.width,
                                         height: emphasisGlowLabel.bounds.height)
        emphasisGlowLabel.alpha = 0
        emphasisGlowLabel.isUserInteractionEnabled = false
        contentView.addSubview(emphasisGlowLabel)

        bodyLabel.text = placement.text
        bodyLabel.font = rFont
        bodyLabel.sizeToFit()
        bodyLabel.frame = CGRect(x: 0, y: labelY,
                                 width: bodyLabel.bounds.width,
                                 height: bodyLabel.bounds.height)
        contentView.addSubview(bodyLabel)
    }

    /// 逐词强调合成（3.7 (50)，与 GlowWordView 同口径）：强调
    /// 变换只落 contentView——基底是 init 的 1/renderScale 反
    /// 向缩放，叠加放大与上浮（上浮与逻辑字号成比例、钳 0.8
    /// 倍字号）；渲染方写在本视图上的旋转/缩放是另一层，两
    /// 层互不相扰。枢轴 = contentView 锚点 (0.5, 0)，词自锚
    /// 点生长，与渲染方的 position 定位口径一致。
    func applyEmphasis(_ e: CGFloat) {
        var transform = CGAffineTransform(
            scaleX: 1 / renderScale, y: 1 / renderScale)
        if abs(e - 1) > 0.0005 {
            let floatY = -min((e - 1) * fontPx * 1.1, fontPx * 0.8)
            let emphasis = CGAffineTransform(translationX: 0, y: floatY)
                .scaledBy(x: e, y: e)
            transform = transform.concatenating(emphasis)
        }
        contentView.transform = transform
        emphasisGlowLabel.alpha = min(max((e - 1) / 0.85, 0), 1) * 0.9
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 逐帧写入：正文色/透明与逐字素（或整词）辉光强度。
    func applyFrame(bodyColor: UIColor, bodyAlpha: Double,
                    wordColor: UIColor, glyphIntensities: [Double]) {
        bodyLabel.textColor = bodyColor
        bodyLabel.alpha = CGFloat(bodyAlpha)
        for (index, label) in glowLabels.enumerated() {
            let intensity = index < glyphIntensities.count
                ? glyphIntensities[index] : 0
            let clamped = cadenzaClamp(intensity, 0, 1.6)
            label.textColor = wordColor
            label.layer.shadowColor = wordColor.cgColor
            label.layer.shadowOpacity = Float(min(0.98, clamped))
            label.alpha = CGFloat(min(1, clamped))
        }
    }
}

// MARK: - 渲染器

final class CadenzaStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    // 调参门面（CadenzaTuningStore，C1 接线）：缺省与
    // DEFAULT_CADENZA_TUNING 逐字一致（fontScale 1.12、
    // widthRatio 0.72、motionAmount 1、glowIntensity 1、
    // beamIntensity 恒 0）；面板改动经 0.25s 缓存生效，
    // preparedCache 的指纹含调参快照（见 applySnapshot /
    // frameTick），改参即失效重建（网页 preparedStateContext
    // 的 deps 含 fontScale/widthRatio 同义）。
    private var cacheTuning: CadenzaTuningValues?
    private func tuning() -> CadenzaTuningValues {
        CadenzaTuningStore.valuesCached(now: CACurrentMediaTime())
    }
    /// 预生成缓存上限（网页为无界 Map；原生按行 LRU 封顶 48，
    /// 与 partita 布局缓存同口径）。
    private let preparedCacheLimit = 48
    /// 单行落点（碎片视图）安全上限；超长行截断尾部落点。
    private let maxPlacementsPerLine = 96

    private let rootView = LyricStageRootView()
    private let lineLayer = UIView()
    private var wordViews: [String: CadenzaWordView] = [:]
    private var animatedStates: [String: CadenzaAnimatedState] = [:]
    private var preparedCache: [Int: CadenzaPreparedState] = [:]
    private var preparedCacheOrder: [Int] = []
    private var cacheTrackId: String? = nil
    private var cacheLineCount = -1
    private var cacheViewportSize: CGSize = .zero
    private var cacheAccent: UIColor? = nil

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false
    private var activeLineId: Int? = nil
    private var currentPrepared: CadenzaPreparedState?
    private var lastTickWallTime: TimeInterval? = nil

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        lineLayer.isUserInteractionEnabled = false
        // 网页 lineLayer 的 transformOrigin 为 50% 42%。
        lineLayer.layer.anchorPoint = CGPoint(x: 0.5, y: 0.42)
        rootView.addSubview(lineLayer)
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    static func isCJKText(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FA5).contains(v) || (0x3040...0x30FF).contains(v)
                || (0xAC00...0xD7AF).contains(v) {
                return true
            }
        }
        return false
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
        // 准备态缓存上下文（网页 preparedStateContextKey 的
        // 原生子集）：曲目/行数/视口/强调色任一变化即全清。
        if snapshot.track?.id != cacheTrackId
            || snapshot.lines.count != cacheLineCount
            || snapshot.viewport.size != cacheViewportSize
            || snapshot.palette.accent != cacheAccent
            || tuning() != cacheTuning {
            cacheTrackId = snapshot.track?.id
            cacheLineCount = snapshot.lines.count
            cacheViewportSize = snapshot.viewport.size
            cacheAccent = snapshot.palette.accent
            cacheTuning = tuning()
            preparedCache.removeAll()
            preparedCacheOrder.removeAll()
            clearLineViews()
            activeLineId = nil
            currentPrepared = nil
        }
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if !isActive {
            lastTickWallTime = nil
        }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        // 面板中途改参（无新快照）：指纹一变即失效准备态，
        // 当前行按新参重建（网页 context deps 变化重算同义）。
        if tuning() != cacheTuning {
            cacheTuning = tuning()
            preparedCache.removeAll()
            preparedCacheOrder.removeAll()
            clearLineViews()
            activeLineId = nil
            currentPrepared = nil
        }
        // dt 只用于指数平滑速率（网页 draw 的 performance.now
        // 差分同式，钳制 [1/240, 0.05]、首帧 1/60）；播放位置
        // 只用入参 position，不构成自建时钟源。
        let now = CACurrentMediaTime()
        let dt: Double
        if let last = lastTickWallTime {
            dt = cadenzaClamp(now - last, 1.0 / 240.0, 0.05)
        } else {
            dt = 1.0 / 60.0
        }
        lastTickWallTime = now

        let idx = Self.activeIndex(in: snapshot.lines, at: position)
        if idx != activeLineId {
            transitionLine(to: idx)
        }
        // 预热下一行（网页 prepareActiveAndUpcoming：有当前行
        // 预热 upcoming，无当前行预热第一条未来行）。
        if let idx, snapshot.lines.indices.contains(idx + 1) {
            _ = preparedFor(line: snapshot.lines[idx + 1])
        } else if idx == nil,
                  let upcoming = snapshot.lines.first(where: { $0.start > position }) {
            _ = preparedFor(line: upcoming)
        }

        guard let prepared = currentPrepared, let idx,
              snapshot.lines.indices.contains(idx) else {
            lineLayer.alpha = 0
            return
        }
        drawFrame(prepared: prepared, line: snapshot.lines[idx],
                  position: position, dt: dt)
    }

    func unmount() {
        isActive = false
        lastTickWallTime = nil
        clearLineViews()
        preparedCache.removeAll()
        preparedCacheOrder.removeAll()
        animatedStates.removeAll()
        context = nil
        snapshot = nil
    }

    // MARK: 当前行判定

    /// 当前行 = 最后一个 start ≤ position 的行，且 position
    /// 不超过该行 renderEndTime（网页宿主 currentLineIndex +
    /// getLineRenderEndTime 的等价口径；下一行开始即切走）。
    static func activeIndex(in lines: [LyricLine], at position: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var result: Int? = nil
        for (index, line) in lines.enumerated() {
            if line.start <= position { result = index } else { break }
        }
        guard let idx = result else { return nil }
        let timing = cadenzaResolveTiming(line: lines[idx])
        if position > timing.lineRenderEndTime { return nil }
        return idx
    }

    // MARK: 行切换与视图管理

    private func clearLineViews() {
        for (_, wordView) in wordViews {
            wordView.removeFromSuperview()
        }
        wordViews.removeAll()
    }

    private func transitionLine(to idx: Int?) {
        activeLineId = idx
        clearLineViews()
        currentPrepared = nil
        guard let idx, let snapshot,
              snapshot.lines.indices.contains(idx) else {
            lineLayer.alpha = 0
            return
        }
        let prepared = preparedFor(line: snapshot.lines[idx])
        currentPrepared = prepared
        // 动画状态剪枝（网页每帧按 placementIds 剪枝同式）：
        // 只保留新行落点 id 的状态（同 id 跨行延续为网页原行为）。
        let ids = Set(prepared.placements.map { $0.id })
        animatedStates = animatedStates.filter { ids.contains($0.key) }
        let font = StageFonts.bold(size: prepared.fontPx)
        for placement in prepared.placements {
            let splitGlow = prepared.timing.wordRevealMode == 0
                && !Self.isCJKText(placement.text)
                && placement.text.count > 1
            let wordView = CadenzaWordView(
                placement: placement, font: font, splitGlow: splitGlow)
            wordView.isHidden = true
            lineLayer.addSubview(wordView)
            wordViews[placement.id] = wordView
        }
    }

    // MARK: 逐帧绘制（VisualizerCadenza draw 循环移植）

    private func drawFrame(prepared: CadenzaPreparedState, line: LyricLine,
                           position: TimeInterval, dt: Double) {
        guard let snapshot else { return }
        let viewport = snapshot.viewport.size
        let width = max(viewport.width, 1)
        let height = max(viewport.height, 1)
        let timing = prepared.timing
        let time = position

        // 整行包络：blur 分量原生不渲染（与 classic 样板同口径，
        // 只落 opacity + scale），其余逐项照搬。
        let envelope = CadenzaEnvelopes.lineEnvelope(
            time: time, line: line, timing: timing)
        lineLayer.alpha = CGFloat(envelope.opacity)
        lineLayer.transform = CGAffineTransform(
            scaleX: CGFloat(envelope.scale), y: CGFloat(envelope.scale))

        // energy：宿主无频谱/功率数据，恒 0（见头部降级说明）。
        let energy: Double = 0
        let motionEnergy = energy * tuning().motionAmount
        let verticalLift = sin(time * 2.3) * (3 + motionEnergy * 8)
        let focusY = Double(height) * 0.42 + verticalLift

        let transformAmount = 1 - exp(-11 * dt)
        let visualAmount = 1 - exp(-14 * dt)
        let glowAmount = 1 - exp(-16 * dt)
        let palette = snapshot.palette
        let isInstant = timing.wordRevealMode == 2

        // 绘制序（网页 STATUS_DRAW_ORDER）：waiting → passed
        // → active，active 最后绘制位于最上层。
        let statusOrder = [0, 2, 1]
        var placementIndex = -1
        var ordered: [(placement: CadenzaPlacement, status: Int)] = []
        for status in statusOrder {
            for placement in prepared.placements {
                let s = CadenzaEnvelopes.wordStatus(
                    time: time, timing: timing,
                    wordStart: placement.wordStart, wordEnd: placement.wordEnd)
                if s == status { ordered.append((placement, s)) }
            }
        }
        for (placement, status) in ordered {
            placementIndex += 1
            guard let wordView = wordViews[placement.id] else { continue }
            lineLayer.bringSubviewToFront(wordView)

            let progress = CadenzaEnvelopes.wordProgress(
                time: time, timing: timing,
                wordStart: placement.wordStart, wordEnd: placement.wordEnd)
            _ = progress  // 仅副歌涟漪用；isChorus 数据缺失不触发
            let passedAlpha: Double = isInstant ? 0 : 0.82
            let pulse: Double = (status == 1 && !isInstant)
                ? 1 + sin(time * CadenzaEnvelopes.activePulseFrequency
                          + placement.wordStart * 5) * 0.04 * tuning().motionAmount
                : 1
            let driftProgress = isInstant ? 0
                : CadenzaEnvelopes.passedDrift(time: time, wordEnd: placement.wordEnd)
            let targetScale: Double
            if status == 0 {
                targetScale = isInstant ? Double(placement.scale)
                    : max(Double(placement.scale) * 0.5, 0.5)
            } else if status == 1 {
                targetScale = isInstant ? Double(placement.scale)
                    : Double(placement.scale) * 1.3 * pulse
            } else {
                targetScale = Double(placement.scale)
            }
            let targetRotation: Double
            if status == 0 {
                targetRotation = isInstant ? Double(placement.rotate)
                    : Double(placement.rotate) + 20
            } else if status == 2 {
                targetRotation = isInstant ? Double(placement.rotate)
                    : Double(placement.rotate)
                        + Double(placement.passedRotate) * driftProgress
            } else {
                targetRotation = Double(placement.rotate)
            }
            let localFloatX = sin(time * 1.2 + Double(placementIndex) * 0.6)
                * motionEnergy * 4
            let localFloatY = cos(time * 1.5 + Double(placementIndex) * 0.4)
                * motionEnergy * 2.5
            let passedDriftX = status == 2
                ? Double(placement.passedDriftX) * driftProgress : 0
            let passedDriftY = status == 2
                ? Double(placement.passedDriftY) * driftProgress : 0
            let targetX = Double(width) / 2 + Double(placement.x)
                + localFloatX + passedDriftX
                + (status == 0 ? Double(placement.entryOffsetX) : 0)
            let targetY = focusY + Double(placement.y)
                + localFloatY + passedDriftY
                + (status == 0 ? Double(placement.entryOffsetY) : 0)
            let targetBodyAlpha: Double = status == 0 ? 0
                : (status == 1 ? 1 : passedAlpha)
            let targetBlur: Double = (status == 0 && !isInstant) ? 10 : 0
            let targetActiveMix = CadenzaEnvelopes.bodyMix(
                time: time, timing: timing,
                wordStart: placement.wordStart, wordEnd: placement.wordEnd)
            let targetGlowAlpha = CadenzaEnvelopes.glowEnvelope(
                time: time, timing: timing,
                wordStart: placement.wordStart, wordEnd: placement.wordEnd)

            var state = animatedStates[placement.id]
            if state == nil {
                let shouldInitActive = isInstant && time >= placement.wordStart
                state = CadenzaAnimatedState(
                    x: Double(width) / 2 + Double(placement.x)
                        + Double(placement.entryOffsetX),
                    y: focusY + Double(placement.y)
                        + Double(placement.entryOffsetY),
                    rotation: shouldInitActive ? targetRotation : targetRotation + 16,
                    scale: shouldInitActive ? targetScale
                        : max(Double(placement.scale) * 0.5, 0.5),
                    bodyAlpha: shouldInitActive ? targetBodyAlpha : 0,
                    blur: shouldInitActive ? targetBlur : 10,
                    activeMix: shouldInitActive ? targetActiveMix : 0,
                    glowAlpha: shouldInitActive ? targetGlowAlpha : 0)
            }
            var s = state!
            s.x = cadenzaMix(s.x, targetX, transformAmount)
            s.y = cadenzaMix(s.y, targetY, transformAmount)
            s.rotation = cadenzaMix(s.rotation, targetRotation, transformAmount)
            s.scale = cadenzaMix(s.scale, targetScale, transformAmount)
            s.bodyAlpha = cadenzaMix(s.bodyAlpha, targetBodyAlpha, visualAmount)
            s.blur = cadenzaMix(s.blur, targetBlur, visualAmount)
            s.activeMix = cadenzaMix(s.activeMix, targetActiveMix, visualAmount)
            s.glowAlpha = cadenzaMix(s.glowAlpha, targetGlowAlpha, glowAmount)
            // 逐词强调弹簧（3.7 (50)，与 GlowWord 系同口径同参
            // 数）：stiffness 200 / damping 15.5 按本帧 dt 积分；
            // 目标只在 active 词上非 1——长音按词真实时长
            // （wordEnd−wordStart，源自 StageLyricUnits 同一时
            // 间轴：YRC 真戳或均分×r）爬升至约 1.85 带微浪，
            // 短词 1.30 词尾轻收；唱完弹簧缓落回 1。合成落点
            // 在词视图 contentView（见 applyEmphasis），不扰本
            // 视图的旋转/缩放与包络状态。
            let emphasisTarget: Double
            if StageEffectSettings.emphasisEnabledCached(
                now: CACurrentMediaTime()), status == 1 {
                let dur = max(placement.wordEnd - placement.wordStart, 0.05)
                let p = min(max((time - placement.wordStart) / dur, 0), 1)
                if dur >= 1.0 {
                    emphasisTarget = 1 + 0.85 * pow(p, 0.65)
                        + 0.035 * sin((time - placement.wordStart) * 7.0) * p
                } else {
                    emphasisTarget = 1 + 0.30 * (1 - 0.3 * p)
                }
            } else {
                emphasisTarget = 1
            }
            let springDt = min(max(dt, 0), 0.05)
            let springAccel = -200 * (s.emphasisValue - emphasisTarget)
                - 15.5 * s.emphasisVelocity
            s.emphasisVelocity += springAccel * springDt
            s.emphasisValue += s.emphasisVelocity * springDt
            animatedStates[placement.id] = s

            if s.bodyAlpha < 0.015 && s.glowAlpha < 0.015 {
                wordView.isHidden = true
                continue
            }
            wordView.isHidden = false
            // position = overlay anchor（词宽中点、baseline 上
            // height×0.42）；x 为未缩放左缘 + 宽/2，y 为 baseline。
            wordView.layer.position = CGPoint(
                x: CGFloat(s.x) + placement.width / 2,
                y: CGFloat(s.y) - placement.height * 0.42)
            wordView.transform = CGAffineTransform(
                rotationAngle: CGFloat(s.rotation) * .pi / 180)
                .scaledBy(x: CGFloat(s.scale), y: CGFloat(s.scale))
            wordView.applyEmphasis(CGFloat(s.emphasisValue))

            let bodyColor = Self.mixColor(palette.primary, palette.accent,
                                          amount: s.activeMix)
            let glyphIntensities: [Double]
            if wordView.splitGlow {
                let glyphCount = max(placement.wordGraphemeCount,
                                     wordView.glyphs.count)
                glyphIntensities = wordView.glyphs.indices.map { glyphIndex in
                    let absoluteIndex = placement.fragmentStartInWord + glyphIndex
                    return CadenzaEnvelopes.charGlow(
                        time: time, wordStart: placement.wordStart,
                        wordEnd: placement.wordEnd, glyphIndex: absoluteIndex,
                        glyphCount: glyphCount,
                        glyphTimings: placement.glyphTimings)
                        * cadenzaClamp(s.glowAlpha, 0, 1)
                        * max(tuning().glowIntensity, 0)
                }
            } else {
                let intensity = CadenzaEnvelopes.glowEnvelope(
                    time: time, timing: timing,
                    wordStart: placement.wordStart, wordEnd: placement.wordEnd)
                    * cadenzaClamp(s.glowAlpha, 0, 1)
                    * max(tuning().glowIntensity, 0)
                glyphIntensities = [intensity]
            }
            wordView.applyFrame(bodyColor: bodyColor, bodyAlpha: s.bodyAlpha,
                                wordColor: palette.accent,
                                glyphIntensities: glyphIntensities)
        }
    }

    /// mixColors 的 UIColor 等价（通道线性混合，amount 钳制）。
    private static func mixColor(_ from: UIColor, _ to: UIColor,
                                 amount: Double) -> UIColor {
        let t = CGFloat(cadenzaClamp(amount, 0, 1))
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        return UIColor(red: fr + (tr - fr) * t,
                       green: fg + (tg - fg) * t,
                       blue: fb + (tb - fb) * t,
                       alpha: fa + (ta - fa) * t)
    }

    // MARK: 准备态构建（cadenzaPreparedState + Fragments + Placements）

    private func preparedFor(line: LyricLine) -> CadenzaPreparedState {
        if let cached = preparedCache[line.id] {
            return cached
        }
        let prepared = buildPreparedState(line: line)
        preparedCache[line.id] = prepared
        preparedCacheOrder.append(line.id)
        if preparedCacheOrder.count > preparedCacheLimit {
            let evict = preparedCacheOrder.removeFirst()
            preparedCache.removeValue(forKey: evict)
        }
        return prepared
    }

    /// 词在整行字素流中的偏移（与 StageLyricUnits 的切分同序
    /// 匹配：跳过空白字素，逐个对上 token 文本）。
    private func tokenOffsets(line: LyricLine, units: [StageWordUnit])
        -> [(offset: Int, count: Int)] {
        let graphemes = line.text.map { String($0) }
        var result: [(offset: Int, count: Int)] = []
        var cursor = 0
        for unit in units {
            while cursor < graphemes.count
                    && (graphemes[cursor] == " " || graphemes[cursor] == "\t"
                        || graphemes[cursor] == "　") {
                cursor += 1
            }
            let count = unit.text.count
            result.append((cursor, count))
            cursor += count
        }
        return result
    }

    private func buildPreparedState(line: LyricLine) -> CadenzaPreparedState {
        let timing = cadenzaResolveTiming(line: line)
        guard let snapshot else {
            return CadenzaPreparedState(
                lineId: line.id, fontPx: 36, lineHeight: 44, maxWidth: 0,
                timing: timing, placements: [])
        }
        let viewport = snapshot.viewport.size
        let units = StageLyricUnits.units(for: line)
        let graphemeCount = max(line.text.count, 1)
        let isInterlude = line.text == "......"

        // 字号（cadenzaPreparedState.chooseFontPx + fontScale）。
        let widthBase = cadenzaClamp(Double(viewport.width) * 0.086, 34, 94)
        let lengthPenalty = graphemeCount > 12
            ? min(Double(graphemeCount - 12) * 1.8, 34) : 0
        let densityPenalty = units.count > 7
            ? min(Double(units.count - 7) * 1.5, 18) : 0
        let chosen = cadenzaClamp(
            widthBase - lengthPenalty - densityPenalty, 28, 104)
        let fontPx = CGFloat(cadenzaClamp(
            chosen * tuning().fontScale, 24, 132))
        let font = StageFonts.bold(size: fontPx)
        let lineHeight = CGFloat(
            (Double(fontPx) * (Self.isCJKText(line.text) ? 1.22 : 1.1))
                .rounded())
        let availableWidth = max(viewport.width - 48, 120)
        let minWidth = min(220, availableWidth)
        let wrapCompression: CGFloat = graphemeCount > 12
            ? CGFloat(cadenzaClamp(
                0.92 - Double(graphemeCount - 12) * 0.018, 0.62, 0.92))
            : 0.92
        let compactWidthRatio = CGFloat(tuning().widthRatio) * wrapCompression
        let maxWidth = CGFloat(cadenzaClamp(
            Double(min(viewport.width * compactWidthRatio, 820)),
            Double(minWidth), Double(availableWidth)))

        // 折行（pretext layoutWithLines 的贪心等价）：按 token
        // 实测宽 + 词间空白宽逐个装行，超 maxWidth 换行；单个
        // token 超宽时整词一行（网页 pretext 可词内断行，差异
        // 见档案）。片段 = 布局行内的 token（不跨行拆分）。
        let offsets = tokenOffsets(line: line, units: units)
        let spaceWidth = (" " as NSString)
            .size(withAttributes: [.font: font]).width
        var tokenWidths: [CGFloat] = []
        for unit in units {
            tokenWidths.append((unit.text as NSString)
                .size(withAttributes: [.font: font]).width)
        }
        var layoutLines: [(width: CGFloat, fragments: [CadenzaLayoutFragment])] = []
        var currentFrags: [CadenzaLayoutFragment] = []
        var currentWidth: CGFloat = 0
        for (i, _) in units.enumerated() {
            let gap: CGFloat
            if currentFrags.isEmpty {
                gap = 0
            } else if i > 0, offsets[i].offset > offsets[i - 1].offset
                        + offsets[i - 1].count {
                gap = spaceWidth * CGFloat(
                    offsets[i].offset - offsets[i - 1].offset
                        - offsets[i - 1].count)
            } else {
                gap = 0
            }
            let needed = (currentFrags.isEmpty ? 0 : gap) + tokenWidths[i]
            if !currentFrags.isEmpty && currentWidth + needed > maxWidth {
                layoutLines.append((currentWidth, currentFrags))
                currentFrags = []
                currentWidth = 0
            }
            let startX = currentFrags.isEmpty
                ? 0 : currentWidth + gap
            currentFrags.append(CadenzaLayoutFragment(
                unitIndex: i, startX: startX,
                endX: startX + tokenWidths[i]))
            currentWidth = startX + tokenWidths[i]
        }
        if !currentFrags.isEmpty {
            layoutLines.append((currentWidth, currentFrags))
        }

        let placements = buildPlacements(
            line: line, units: units, layoutLines: layoutLines,
            fontPx: fontPx, lineHeight: lineHeight, maxWidth: maxWidth,
            isInterlude: isInterlude)
        return CadenzaPreparedState(
            lineId: line.id, fontPx: fontPx, lineHeight: lineHeight,
            maxWidth: maxWidth, timing: timing, placements: placements)
    }

    /// 落点构建（cadenzaPlacements.buildWordPlacements 移植；
    /// animationIntensity 恒 normal：baseMargin 6、baseScale 1.01）。
    private func buildPlacements(
        line: LyricLine, units: [StageWordUnit],
        layoutLines: [(width: CGFloat, fragments: [CadenzaLayoutFragment])],
        fontPx: CGFloat, lineHeight: CGFloat, maxWidth: CGFloat,
        isInterlude: Bool
    ) -> [CadenzaPlacement] {
        let seed = line.start * 1000
        let totalHeight = CGFloat(max(layoutLines.count, 1)) * lineHeight
        let baseMargin: CGFloat = 6
        let baseScale: CGFloat = 1.01

        // 强调表（buildEmphasisMap）：候选 = 非拆分主片段，
        // score = semanticWeight + centerBias×0.18，最高者为 hero。
        var emphasisMap: [Int: CGFloat] = [:]
        if !isInterlude {
            let primaryCount = units.count
            var best: (wordIndex: Int, score: Double)? = nil
            for (wordIndex, unit) in units.enumerated() {
                if unit.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }
                let gc = max(unit.text.count, 1)
                let semanticWeight = Self.isCJKText(unit.text)
                    ? 0.18 : min(Double(gc) * 0.08, 0.36)
                let centerBias = 1 - abs(Double(wordIndex)
                    - Double(primaryCount - 1) / 2) / Double(max(primaryCount, 1))
                let score = semanticWeight + centerBias * 0.18
                if best == nil || score > best!.score {
                    best = (wordIndex, score)
                }
            }
            if let hero = best {
                let scoreBoost = 1 + cadenzaClamp(hero.score - 0.48, 0, 0.52)
                emphasisMap[hero.wordIndex] = CGFloat(1.46 * scoreBoost)
            }
        }
        let heroWordIndex = emphasisMap.max(by: { $0.value < $1.value })?.key

        // 布局计划（placementPlans）：先按布局行/片段展开，
        // 再按 emphasis 降序、行序、startX 排序（稳定排序）。
        struct Plan {
            var unitIndex: Int
            var lineIndex: Int
            var fragmentIndex: Int
            var baseX: CGFloat
            var baseY: CGFloat
            var emphasis: CGFloat
            var width: CGFloat
            var height: CGFloat
            var scale: CGFloat
            var collisionWidth: CGFloat
            var collisionHeight: CGFloat
            var padding: CGFloat
        }
        var plans: [Plan] = []
        for (lineIndex, layoutLine) in layoutLines.enumerated() {
            let lineLeft = -layoutLine.width / 2
            let baselineY = -totalHeight / 2 + fontPx
                + CGFloat(lineIndex) * lineHeight
            for (fragmentIndex, fragment) in layoutLine.fragments.enumerated() {
                let emphasis = emphasisMap[fragment.unitIndex] ?? 1
                let width = max(fragment.endX - fragment.startX, fontPx * 0.18)
                let scale = emphasis > 1 ? baseScale * emphasis : baseScale
                let height = fontPx * scale * 0.95
                plans.append(Plan(
                    unitIndex: fragment.unitIndex, lineIndex: lineIndex,
                    fragmentIndex: fragmentIndex,
                    baseX: lineLeft + fragment.startX, baseY: baselineY,
                    emphasis: emphasis, width: width, height: height,
                    scale: scale,
                    collisionWidth: width * scale * (emphasis > 1 ? 1.48 : 1.26),
                    collisionHeight: height * (emphasis > 1 ? 1.36 : 1.24),
                    padding: baseMargin + (emphasis > 1 ? 10 : 2)))
            }
        }
        plans.sort { a, b in
            if abs(a.emphasis - b.emphasis) > 0.001 {
                return a.emphasis > b.emphasis
            }
            if a.lineIndex != b.lineIndex { return a.lineIndex < b.lineIndex }
            return a.baseX < b.baseX
        }
        var primaryPlanByWord: [Int: Plan] = [:]
        for plan in plans where primaryPlanByWord[plan.unitIndex] == nil {
            primaryPlanByWord[plan.unitIndex] = plan
        }
        let heroPlan = heroWordIndex.flatMap { primaryPlanByWord[$0] }
        let heroMetrics: (centerX: CGFloat, centerY: CGFloat, width: CGFloat)?
            = heroPlan.map {
                (centerX: ($0.width * $0.scale) / 2,
                 centerY: -$0.height * 0.46,
                 width: $0.width * $0.scale)
            }

        // 碰撞求值（网页带状索引的等价暴力求和）。
        var occupied: [CGRect] = []
        func evaluateCollision(_ rect: CGRect) -> (intersects: Bool, area: CGFloat) {
            var intersects = false
            var area: CGFloat = 0
            for other in occupied {
                let overlapWidth = max(0, min(rect.maxX, other.maxX)
                    - max(rect.minX, other.minX))
                let overlapHeight = max(0, min(rect.maxY, other.maxY)
                    - max(rect.minY, other.minY))
                if overlapWidth <= 0 || overlapHeight <= 0 { continue }
                intersects = true
                area += overlapWidth * overlapHeight
            }
            return (intersects, area)
        }
        func registerRect(x: CGFloat, baselineY: CGFloat, width: CGFloat,
                          height: CGFloat, padding: CGFloat) {
            occupied.append(CGRect(
                x: x - padding, y: baselineY - height - padding,
                width: width + padding * 2, height: height + padding * 2))
        }

        var placements: [CadenzaPlacement] = []
        for plan in plans {
            if placements.count >= maxPlacementsPerLine { break }
            let unit = units[plan.unitIndex]
            let wordSeed = seed + Double(plan.unitIndex) * 17
                + Double(plan.lineIndex) * 31
                + Double(plan.fragmentIndex) * 13
            let random = { (offset: Double) in
                stageSeededRandom(wordSeed + offset)
            }
            let passedRotate = CGFloat(random(3) - 0.5) * 12
            let step = max(10, (Double(fontPx) * 0.14).rounded())
            let maxRadius: CGFloat = plan.emphasis > 1
                ? max(20, lineHeight * 0.5)
                : max(lineHeight * 2.2, plan.collisionWidth * 0.75, 56)
            var preferredX = plan.emphasis > 1 ? -plan.width / 2 : plan.baseX
            var preferredY = plan.emphasis > 1 ? 0 : plan.baseY

            if !isInterlude && plan.emphasis <= 1, let hero = heroMetrics {
                let wordCenterX = preferredX + plan.width / 2
                let wordCenterY = preferredY - plan.height * 0.46
                var dx = wordCenterX - hero.centerX
                var dy = wordCenterY - hero.centerY
                let distance = hypot(dx, dy)
                if distance < 1 {
                    dx = preferredX >= 0 ? 1 : -1
                    dy = plan.lineIndex % 2 == 0 ? -0.65 : 0.65
                }
                let minSeparation = hero.width * 0.34 + plan.width * 0.52
                    + plan.padding * 2
                if distance < minSeparation {
                    let normalized = max(hypot(dx, dy), 1)
                    let push = minSeparation - distance
                    preferredX += dx / normalized * push
                    preferredY += dy / normalized * push * 0.92
                }
            }

            let horizontalMin = -maxWidth / 2 - 72
            let horizontalMax = maxWidth / 2 + 72
            let verticalMin = -max(totalHeight * 0.9, lineHeight * 1.6)
            let verticalMax = max(totalHeight * 0.9, lineHeight * 1.45)
            var chosenX = preferredX
            var chosenY = preferredY
            var found = false
            var bestFallback = (x: preferredX, y: preferredY,
                                score: CGFloat.infinity)
            let baseAngle: CGFloat = (heroMetrics != nil && plan.emphasis <= 1)
                ? atan2(preferredY, preferredX + plan.width / 2) : 0
            var radius: CGFloat = 0
            while radius <= maxRadius && !found {
                let sampleCount: Int
                if radius == 0 {
                    sampleCount = 1
                } else if plan.emphasis > 1 {
                    sampleCount = 8
                } else {
                    sampleCount = max(12, Int(
                        (Double.pi * 2 * Double(radius)
                            / max(step * 1.1, 10)).rounded()))
                }
                for sampleIndex in 0..<sampleCount {
                    let dx: CGFloat
                    let dy: CGFloat
                    if radius == 0 {
                        dx = 0; dy = 0
                    } else {
                        let angle = baseAngle + CGFloat(sampleIndex)
                            / CGFloat(sampleCount) * .pi * 2
                        let ellipseY = radius * (plan.emphasis > 1 ? 0.8 : 0.92)
                        dx = cos(angle) * radius
                        dy = sin(angle) * ellipseY
                    }
                    let left = preferredX + dx - plan.padding
                    let top = preferredY + dy - plan.collisionHeight
                        - plan.padding
                    let rect = CGRect(
                        x: left, y: top,
                        width: plan.collisionWidth + plan.padding * 2,
                        height: plan.collisionHeight + plan.padding * 2)
                    let withinBounds = left >= horizontalMin
                        && rect.maxX <= horizontalMax
                        && top >= verticalMin && rect.maxY <= verticalMax
                    if !withinBounds { continue }
                    let collision = evaluateCollision(rect)
                    let travel = hypot(dx, dy)
                    let score = collision.area * 2.2 + travel
                    if score < bestFallback.score {
                        bestFallback = (preferredX + dx, preferredY + dy, score)
                    }
                    if !collision.intersects {
                        chosenX = preferredX + dx
                        chosenY = preferredY + dy
                        registerRect(x: chosenX, baselineY: chosenY,
                                     width: plan.collisionWidth,
                                     height: plan.collisionHeight,
                                     padding: plan.padding)
                        found = true
                        break
                    }
                }
                radius += CGFloat(step)
            }
            if !found {
                chosenX = bestFallback.x
                chosenY = bestFallback.y
                registerRect(x: chosenX, baselineY: chosenY,
                             width: plan.collisionWidth,
                             height: plan.collisionHeight,
                             padding: plan.padding)
            }

            let outwardX = chosenX + plan.width / 2
            let outwardY = chosenY - plan.height * 0.46
            let outwardLength = max(hypot(outwardX, outwardY), 1)
            let driftAmount: CGFloat
            if isInterlude {
                driftAmount = 3 + CGFloat(random(6)) * 3
            } else if plan.emphasis > 1 {
                driftAmount = 4 + CGFloat(random(6)) * 4
            } else {
                driftAmount = 5 + CGFloat(random(6)) * 6
            }
            let passedDriftX = outwardX / outwardLength * driftAmount
                + CGFloat(random(7) - 0.5) * 2.4
            let passedDriftY = outwardY / outwardLength * driftAmount * 0.72
                + CGFloat(random(8) - 0.5) * 2

            // 字素均分时刻（buildWordGraphemeTimings even 口径）。
            let glyphCount = max(unit.text.count, 1)
            let span = max(unit.end - unit.start, 0.05)
            var glyphTimings: [(start: TimeInterval, end: TimeInterval)] = []
            for g in 0..<glyphCount {
                glyphTimings.append((
                    unit.start + span * Double(g) / Double(glyphCount),
                    unit.start + span * Double(g + 1) / Double(glyphCount)))
            }
            placements.append(CadenzaPlacement(
                id: "\(unit.text)-\(plan.unitIndex)-\(plan.lineIndex)-\(plan.fragmentIndex)-0",
                wordIndex: plan.unitIndex, text: unit.text,
                wordStart: unit.start, wordEnd: unit.end,
                x: chosenX, y: chosenY,
                width: plan.width, height: plan.height,
                rotate: 0, scale: plan.scale,
                passedRotate: passedRotate,
                passedDriftX: passedDriftX, passedDriftY: passedDriftY,
                entryOffsetX: 0, entryOffsetY: 0,
                fragmentStartInWord: 0,
                wordGraphemeCount: glyphCount,
                glyphTimings: glyphTimings,
                emphasis: plan.emphasis, isInterlude: isInterlude))
        }
        return placements
    }

    // MARK: 布局

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        lineLayer.frame = bounds
        lineLayer.layer.position = CGPoint(
            x: bounds.width / 2, y: bounds.height * 0.42)
    }
}
