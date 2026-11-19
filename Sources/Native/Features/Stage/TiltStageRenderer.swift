import UIKit

// 倾诉 tilt（M2' 照搬对齐版）：按 folia-major 网页版
// tilt/VisualizerTilt.tsx 的展示行为逐项实现。依据文件：
// VisualizerTilt.tsx、tilt/tuning.ts、tilt/entry.tsx、types.ts
// （DEFAULT_TILT_TUNING）、utils/lyrics/sentenceLayout.ts、
// utils/lyrics/renderHints.ts、utils/lyrics/graphemeTiming.ts、
// utils/iosWebKit.ts（lyricViewportUnit，iOS 取 vmin）。
// 对齐要点：
// - 画面只呈现当前一行：整行先按概率分成 1–4 个分段
// （determineLineCount + SentenceLayout），分段在纵列里居中
// 堆叠（段间 gap 12pt、视口宽 ≥640 时 16pt），按时间顺序
// 逐段揭示（段 start − 0.25s 起算），无当前行时画面空白
// （waitingForMusic 三份语言文件均为空串，与 classic 同）。
// - 「倾斜」在源码里不是容器透视/旋转：全行至多一个分段被
// 抽中为 tilt 段（概率 0.35），该段用斜体细字重（300）、
// 字距 0.15em，段内字素按奇偶交替上下错落 ±fontPx/6；
// 其余段为正体 400 字重、字距 0.08em。源码全文无
// perspective / rotate / skew 容器变换，故原生不臆造
// CATransform3D 透视；斜体在 Songti 无斜体字形，原生以
// 逐字斜切矩阵（c = −0.22）近似，差异见回报档案。
// - 逐字行为与 GlowWord 三态机不同源：tilt 无辉光扫光、无
// 词姿态随机、无 passed 态；字素只有「延迟淡入（段内序
// ×0.04/0.05s）+ 唱到时脉冲放大（sin 脉冲 + 0.25 余辉，
// 峰值 tilt 段 ×1.18 / 普通段 ×1.15）」。故不复用
// GlowWordView（强行复用会引入网页没有的辉光与姿态），
// 只复用 LyricStageRootView、StageFonts、StageLyricUnits
// （逐字时序来源）、ClassicStageRenderer.activeIndex
// （当前行判定）与种子随机公式 fract(sin(x)·10000)；
// tilt 自己的 seededRandom 入参为 sin(seed·1000+offset)，
// 在本文件内按源码另行实现，不与 stageSeededRandom 混用。
// - 调音参数（splitProbability 0.75 / tiltStyleProbability
// 0.35 / colorScheme default）来自 DEFAULT_TILT_TUNING；
// 协议快照无 tuning 字段，原生取默认值，colorScheme 的
// 其余三档（swap/accentAll/primaryAll）无数据源未落。
// - 整行呼吸浮动源码没有（那是 classic/partita 侧的
// lyricContainerFloat），本样式不加。
// 时钟纪律不变：只消费宿主 frameTick 的锚点位置，不自建
// 时钟源；逐字脉冲在 frameTick 内按位置直接算，不跑定时器。
final class TiltStageRenderer: NSObject, LyricStageRenderer {

let view: UIView
let capabilities = LyricStageCapabilities(
supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

private let rootView = LyricStageRootView()
private var lineContainer: UIView?
private var segmentViews: [TiltSegmentView] = []
private var currentLayout: TiltLayoutData?
private var context: LyricStageContext?
private var snapshot: LyricStageSnapshot?
private var isActive = false
private var activeLineId: Int? = nil
private var visibleSegmentIndex = -1
private var builtTrackId: String? = nil
private var builtLineCount = -1
private var builtViewportSize: CGSize =.zero
private var layoutCache: [Int: TiltLayoutData] = [:]
private var layoutCacheOrder: [Int] = []

override init() {
view = rootView
super.init()
rootView.backgroundColor =.clear
rootView.onLayout = { [weak self] in self?.performLayout()}
}

// MARK: LyricStageRenderer

func mount(context: LyricStageContext) {
self.context = context
}

func applySnapshot(_ snapshot: LyricStageSnapshot) {
self.snapshot = snapshot
// 布局依赖视口（字号按 vmin、可用宽按视口宽）：视口
// 变（旋转）时缓存与当前行一并失效重建（同 partita）。
let viewportChanged = snapshot.viewport.size!= builtViewportSize
&& builtViewportSize!=.zero
if snapshot.track?.id!= builtTrackId
|| snapshot.lines.count!= builtLineCount
|| viewportChanged {
builtTrackId = snapshot.track?.id
builtLineCount = snapshot.lines.count
layoutCache.removeAll()
layoutCacheOrder.removeAll()
clearLine()
}
rootView.setNeedsLayout()
}

func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
isActive = active && state!=.destroyed
// 本样式无自持时钟/呼吸层，inactive 时 frameTick 自行
// 守门即停掉全部逐帧工作（脉冲只在 frameTick 内算）。
}

func frameTick(position: TimeInterval) {
guard isActive, let snapshot else { return}
let idx = ClassicStageRenderer.activeIndex(in: snapshot.lines, at: position)
if idx!= activeLineId {
transitionLine(to: idx, position: position)
}
guard let layout = currentLayout, let lineIndex = activeLineId,
snapshot.lines.indices.contains(lineIndex) else { return}
let line = snapshot.lines[lineIndex]
// 可见段序号（源码 useLayoutEffect 口径）：最后一个
// start − 0.25 ≤ position 的段；position 在
// [行 start − 0.1, renderEnd] 之外时为 −1（全隐）。
// renderEnd 原生以行 end + 0.35 近似（与 classic 的
// activeIndex 余像同值，见档案）。
var target = -1
if position >= line.start - 0.1 && position <= line.end + 0.35 {
for i in layout.segments.indices {
if position >= layout.segmentTimings[i].start - 0.25 {
target = i
}
}
}
if target!= visibleSegmentIndex {
visibleSegmentIndex = target
for (i, segmentView) in segmentViews.enumerated() {
segmentView.setVisible(i <= target, animated: true)
}
}
for segmentView in segmentViews {
segmentView.updatePulse(position: position)
}
}

func unmount() {
isActive = false
clearLine()
layoutCache.removeAll()
layoutCacheOrder.removeAll()
context = nil
snapshot = nil
}

// MARK: 行切换

private func clearLine() {
lineContainer?.removeFromSuperview()
lineContainer = nil
segmentViews = []
currentLayout = nil
activeLineId = nil
visibleSegmentIndex = -1
}

private func transitionLine(to idx: Int?, position: TimeInterval) {
// 旧行出场：整容器淡出 0.45s easeInOut 后移除（源码
// 外层 motion.div exit；段级 exit 偏移并入容器淡出，
// 见档案）。
if let old = lineContainer {
lineContainer = nil
segmentViews = []
UIView.animate(withDuration: 0.45, delay: 0,
options: [.curveEaseInOut]) {
old.alpha = 0
} completion: { _ in old.removeFromSuperview()}
}
activeLineId = idx
currentLayout = nil
visibleSegmentIndex = -1
guard let idx, let snapshot,
snapshot.lines.indices.contains(idx) else { return}
let line = snapshot.lines[idx]
let layout = layoutFor(line: line)
currentLayout = layout

let container = UIView()
container.isUserInteractionEnabled = false
var views: [TiltSegmentView] = []
for (i, segment) in layout.segments.enumerated() {
let segmentView = TiltSegmentView(
segment: segment,
fontSize: layout.fontSizes[i],
font: layout.fonts[i],
color: segment.isTilt? snapshot.palette.accent
: snapshot.palette.primary,
charTimings: layout.charTimings[i],
yOffset: layout.yOffset)
views.append(segmentView)
container.addSubview(segmentView)
}
lineContainer = container
segmentViews = views
rootView.addSubview(container)
layoutContainer(container)

// 构建后按当前位定格（中途进台/seek 落位）：已到揭示
// 时刻的段直接摆到落定态，不补播入场动画。
var target = -1
if position >= line.start - 0.1 && position <= line.end + 0.35 {
for i in layout.segments.indices {
if position >= layout.segmentTimings[i].start - 0.25 {
target = i
}
}
}
visibleSegmentIndex = target
for (i, segmentView) in views.enumerated() {
segmentView.setVisible(i <= target, animated: false)
segmentView.updatePulse(position: position)
}
// 新行入场：整容器淡入（源码 initial opacity 0 →
// animate 1；源码未给该层 transition，原生取 0.3s
// easeOut，与 classic 行入场同时长）。
container.alpha = 0
UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
container.alpha = 1
}
}

private func layoutContainer(_ container: UIView) {
guard let layout = currentLayout else { return}
let bounds = rootView.bounds
let gap = segmentGap()
var totalHeight: CGFloat = 0
for size in layout.segmentSizes { totalHeight += size.height}
if layout.segmentSizes.count > 1 {
totalHeight += gap * CGFloat(layout.segmentSizes.count - 1)
}
let width = layout.segmentSizes.map { $0.width}.max()?? 0
container.frame = CGRect(
x: (bounds.width - width) / 2,
y: (bounds.height - totalHeight) / 2,
width: width, height: totalHeight)
var cursorY: CGFloat = 0
for (i, segmentView) in segmentViews.enumerated() {
let size = layout.segmentSizes[i]
segmentView.frame = CGRect(
x: (width - size.width) / 2, y: cursorY,
width: size.width, height: size.height)
cursorY += size.height + gap
}
}

/// 段间纵距：源码 gap-y-3（12pt），sm（≥640pt 宽）gap-y-4。
private func segmentGap() -> CGFloat {
viewportSize().width >= 640? 16: 12
}

private func viewportSize() -> CGSize {
if let size = snapshot?.viewport.size, size.width > 0, size.height > 0 {
return size
}
return rootView.bounds.size
}

// MARK: 布局构建（VisualizerTilt.buildTiltLayout 逐项对应）

private func layoutFor(line: LyricLine) -> TiltLayoutData {
if let cached = layoutCache[line.id] { return cached}
let layout = buildLayout(line: line)
layoutCache[line.id] = layout
layoutCacheOrder.append(line.id)
if layoutCacheOrder.count > 48 {
let evict = layoutCacheOrder.removeFirst()
layoutCache.removeValue(forKey: evict)
}
return layout
}

private func buildLayout(line: LyricLine) -> TiltLayoutData {
// DEFAULT_TILT_TUNING（types.ts）：协议无 tuning 通道，
// 取默认值；lyricsFontScale 的原生落点为视口
// dynamicTypeScale（本期恒 1，同 still 口径）。
let splitProbability = 0.75
let tiltStyleProbability = 0.35
let fontScale = snapshot?.viewport.dynamicTypeScale?? 1

let viewport = viewportSize()
let viewportWidth = viewport.width > 0? viewport.width: 390
let vmin = min(viewportWidth, viewport.height > 0? viewport.height: viewportWidth)
// 测量基准（源码 measureMaxPx）：max(视口宽 × 0.06875,
// 5.625rem × fontScale)；可用宽 = max(320, 视口宽) × 0.85。
let measureBasePx = max(viewportWidth * 0.06875, 90 * fontScale)
let availableWidth = max(320, viewportWidth) * 0.85
let normalMeasureFont = Self.songtiRegular(size: measureBasePx)
let tiltMeasureFont = StageFonts.light(size: measureBasePx)

let fullText = line.text
let trimmedCount = fullText.trimmingCharacters(in:.whitespaces).count
let isEllipsisOnly = Self.isEllipsisOnly(fullText)

var segmentTexts: [String]
if isEllipsisOnly {
segmentTexts = [fullText]
} else {
let numLines = Self.determineLineCount(
charCount: trimmedCount, seed: line.start,
splitProbability: splitProbability)
segmentTexts = TiltSentenceSplitter.splitIntoSentences(
text: fullText, targetCount: numLines, seed: line.start)
}

// tilt 段抽选：每段先掷 roll（offset 100+i），中选者
// 再掷一次（offset 200）挑唯一 tilt 段。
var candidates: [Int] = []
for i in segmentTexts.indices {
let roll = Self.tiltSeededRandom(seed: line.start, offset: 100 + Double(i))
if roll < tiltStyleProbability { candidates.append(i)}
}
var tiltIndex = -1
if!candidates.isEmpty {
let pick = Int((Self.tiltSeededRandom(seed: line.start, offset: 200)
* Double(candidates.count)).rounded(.down))
tiltIndex = candidates[min(pick, candidates.count - 1)]
}

var segments: [TiltSegmentData] = []
var offsetAccum = 0
for (i, rawText) in segmentTexts.enumerated() {
let leading = rawText.count - rawText.drop(while: { $0 == " " || $0 == "\t"}).count
let trimmed = rawText.trimmingCharacters(in:.whitespaces)
segments.append(TiltSegmentData(
text: trimmed, isTilt: i == tiltIndex,
isShortLastLine: false, charOffset: offsetAccum + leading))
offsetAccum += rawText.count
}

func measure(_ text: String, font: UIFont) -> CGFloat {
(text as NSString).size(withAttributes: [.font: font]).width
}

var scaleMultiplier: CGFloat = 1
let tiltWidths = segments.filter { $0.isTilt}
.map { measure($0.text, tiltMeasureFont)}
let normalWidths = segments.filter {!$0.isTilt}
.map { measure($0.text, normalMeasureFont)}
let tiltWidth = tiltWidths.max()?? 0
let normalWidth = normalWidths.max()?? 0
let tiltOverflow = tiltWidth > 0? tiltWidth / availableWidth: 0
let normalOverflow = normalWidth > 0? normalWidth / availableWidth: 0
let maxOverflow = max(tiltOverflow, normalOverflow)

if maxOverflow > 1 {
if maxOverflow >= 1.6 {
// RESPLIT_THRESHOLD：重切更多段再定缩放。
let targetWidth = availableWidth * (1.6 - 0.15)
let totalEstWidth = measure(fullText, normalMeasureFont)
let extra = min(4, max(segments.count + 1,
Int((totalEstWidth / targetWidth).rounded(.up))))
if extra > segments.count {
let reTexts = TiltSentenceSplitter.splitIntoSentences(
text: fullText, targetCount: extra, seed: line.start)
var reSegments: [TiltSegmentData] = []
var reOffset = 0
for rawText in reTexts {
let leading = rawText.count
- rawText.drop(while: { $0 == " " || $0 == "\t"}).count
let trimmed = rawText.trimmingCharacters(in:.whitespaces)
reSegments.append(TiltSegmentData(
text: trimmed, isTilt: false,
isShortLastLine: false, charOffset: reOffset + leading))
reOffset += rawText.count
}
if!reSegments.isEmpty {
let roll = Self.tiltSeededRandom(seed: line.start, offset: 300)
if roll < tiltStyleProbability {
let picked = Int((Self.tiltSeededRandom(
seed: line.start, offset: 301)
* Double(reSegments.count)).rounded(.down))
reSegments[min(picked, reSegments.count - 1)].isTilt = true
}
}
var postScale: CGFloat = 1
if let tiltSeg = reSegments.first(where: { $0.isTilt}) {
let w = measure(tiltSeg.text, tiltMeasureFont)
if w > availableWidth {
postScale = max(0.5, availableWidth / w)
}
} else if let widest = reSegments.filter({!$0.isTilt})
.map({ measure($0.text, normalMeasureFont)}).max() {
if widest > availableWidth {
postScale = max(0.55, availableWidth / widest)
}
}
segments = Self.markShortLastLine(reSegments)
return finishLayout(line: line, segments: segments,
scaleMultiplier: postScale,
fontScale: fontScale, vmin: vmin,
viewportWidth: viewportWidth)
}
}
if tiltOverflow >= normalOverflow && tiltWidth > 0 {
scaleMultiplier = max(0.5, availableWidth / tiltWidth)
} else if normalWidth > 0 {
scaleMultiplier = max(0.55, availableWidth / normalWidth)
}
}

segments = Self.markShortLastLine(segments)
return finishLayout(line: line, segments: segments,
scaleMultiplier: scaleMultiplier,
fontScale: fontScale, vmin: vmin,
viewportWidth: viewportWidth)
}

/// 由最终分段组装布局：字号、字体、段尺寸、段时序、逐字时序。
private func finishLayout(line: LyricLine, segments: [TiltSegmentData],
scaleMultiplier: CGFloat, fontScale: CGFloat,
vmin: CGFloat, viewportWidth: CGFloat) -> TiltLayoutData {
builtViewportSize = viewportSize()
let base = fontScale * scaleMultiplier
// tiltFontPx（源码 TiltLine）：min(视口宽 × 0.06875 ×
// base, 5.625rem × base)；yOffset = tiltFontPx / 6。
let tiltFontPx = min(viewportWidth * 0.06875 * base, 90 * base)
let yOffset = tiltFontPx / 6

var fontSizes: [CGFloat] = []
var fonts: [UIFont] = []
var sizes: [CGSize] = []
for segment in segments {
// 字号 clamp(3.125rem×s, 6.875vmin×s, 5.625rem×s)；
// 普通段短末段 ×1.18（shortLastBoost），tilt 段无。
let boost: CGFloat = segment.isShortLastLine &&!segment.isTilt? 1.18: 1
let s = base * boost
let size = max(50 * s, min(6.875 * vmin / 100 * s, 90 * s))
fontSizes.append(size)
// 字重：普通 400 / tilt 300（resolveThemeFontWeight
// 的 fallback；主题自带 fontWeight 时网页整体覆盖，
// 协议无此字段，未落）。
let font = segment.isTilt? StageFonts.light(size: size)
: Self.songtiRegular(size: size)
fonts.append(font)
let height = size * (segment.isTilt? 1.25: 1.35)
let width = TiltSegmentView.measureWidth(
text: segment.text, font: font, fontSize: size,
isTilt: segment.isTilt)
sizes.append(CGSize(width: width, height: height))
}

let timings = segmentTimings(for: line, segments: segments)
var charTimings: [[TiltCharTiming]] = []
for (i, segment) in segments.enumerated() {
charTimings.append(buildCharTimings(
line: line, segment: segment,
segmentStart: timings[i].start, segmentEnd: timings[i].end))
}
return TiltLayoutData(
segments: segments, scaleMultiplier: scaleMultiplier,
fontSizes: fontSizes, fonts: fonts, segmentSizes: sizes,
segmentTimings: timings, charTimings: charTimings,
yOffset: yOffset)
}

// MARK: 时序（segmentTimings / buildCharTimings 对应）

/// 全行非空白字素的逐字时序（以 StageLyricUnits 的单元
/// 为源：单元内字素均分，与网页 buildWordGraphemeTimings
/// 无音节数据时的 even 口径一致；YRC 逐字戳在场时单元即
/// 真词，时序随之为真戳）。
private func lineCharTimings(for line: LyricLine) -> [TiltCharTiming] {
let units = StageLyricUnits.units(for: line)
var result: [TiltCharTiming] = []
for unit in units {
let graphemes = unit.text.filter {!$0.isWhitespace}
guard!graphemes.isEmpty else { continue}
let span = max(unit.end - unit.start, 0.05)
for (j, _) in graphemes.enumerated() {
result.append(TiltCharTiming(
charIndex: result.count,
start: unit.start + span * Double(j) / Double(graphemes.count),
end: unit.start + span * Double(j + 1) / Double(graphemes.count)))
}
}
return result
}

/// 段在全行非空白字素序中的起始下标。
private func nonSpaceOffset(fullText: String, charOffset: Int) -> Int {
let graphemes = Array(fullText)
var count = 0
for i in 0..<min(charOffset, graphemes.count) {
if!graphemes[i].isWhitespace { count += 1}
}
return count
}

private func segmentTimings(for line: LyricLine,
segments: [TiltSegmentData]) -> [(start: TimeInterval, end: TimeInterval)] {
let units = StageLyricUnits.units(for: line)
// 每个单元覆盖的非空白字素区间（与 lineCharTimings 同序）。
var unitRanges: [(start: Int, end: Int, timeStart: TimeInterval, timeEnd: TimeInterval)] = []
var cursor = 0
for unit in units {
let count = unit.text.filter {!$0.isWhitespace}.count
unitRanges.append((cursor, cursor + count, unit.start, unit.end))
cursor += count
}
return segments.map { segment in
let segStart = nonSpaceOffset(fullText: line.text, charOffset: segment.charOffset)
let segCount = segment.text.filter {!$0.isWhitespace}.count
let segEnd = segStart + segCount
let overlapping = unitRanges.filter { $0.start < segEnd && $0.end > segStart}
if let first = overlapping.first, let last = overlapping.last {
return (first.timeStart, last.timeEnd)
}
// 源码兜底：段无词时 start = 行 start、end =
// getLineRenderEndTime；原生以行 end + 0.35 近似。
return (line.start, line.end + 0.35)
}
}

private func buildCharTimings(line: LyricLine, segment: TiltSegmentData,
segmentStart: TimeInterval,
segmentEnd: TimeInterval) -> [TiltCharTiming] {
let nonSpaceCount = segment.text.filter {!$0.isWhitespace}.count
guard nonSpaceCount > 0 else { return []}
let global = lineCharTimings(for: line)
let start = nonSpaceOffset(fullText: line.text, charOffset: segment.charOffset)
if global.count >= start + nonSpaceCount {
// 与网页一致：切片后 charIndex 重排为段内序。
return (0..<nonSpaceCount).map { i in
let t = global[start + i]
return TiltCharTiming(charIndex: i, start: t.start, end: t.end)
}
}
// 源码兜底：时序数与段字素数对不上时整段均分，
// 总时长下限 0.3s。
let totalDuration = max(segmentEnd - segmentStart, 0.3)
let avg = totalDuration / Double(nonSpaceCount)
return (0..<nonSpaceCount).map { i in
TiltCharTiming(charIndex: i,
start: segmentStart + Double(i) * avg,
end: segmentStart + Double(i + 1) * avg)
}
}

// MARK: 布局

private func performLayout() {
let bounds = rootView.bounds
guard bounds.width > 0, bounds.height > 0 else { return}
// 视口宽变化（旋转）时字号/分段宽度口径随之变：
// applySnapshot 已清缓存，这里重建当前行。
if let container = lineContainer {
if builtViewportSize!=.zero
&& snapshot?.viewport.size!= builtViewportSize,
let idx = activeLineId {
let position = context?.positionNow()?? 0
lineContainer?.removeFromSuperview()
lineContainer = nil
segmentViews = []
activeLineId = nil
transitionLine(to: idx, position: position)
} else {
layoutContainer(container)
}
}
}

// MARK: 源码常量与判定（类内静态工具）

/// Songti 正体 400（StageFonts 只有 700/300 两档，400 在
/// 本文件内取 STSongti-SC-Regular，缺失时系统正体）。
static func songtiRegular(size: CGFloat) -> UIFont {
UIFont(name: "STSongti-SC-Regular", size: size)
??.systemFont(ofSize: size, weight:.regular)
}

/// tilt 专用种子随机（源码 seededRandom）：fract(sin(seed
/// × 1000 + offset) × 10000)。与 GlowWordEngine 的
/// stageSeededRandom（sin(x) 本值）入参口径不同，不混用。
static func tiltSeededRandom(seed: Double, offset: Double) -> Double {
let x = sin(seed * 1000 + offset) * 10000
return x - floor(x)
}

/// determineLineCount：CHAR_REF_LENGTH 20、LOG_OFFSET 4、
/// 阈值 [0.45, 1.05, 1.7]；字数口径原生以字素数近似
/// JS 的 UTF-16 length（BMP 内一致，见档案）。
static func determineLineCount(charCount: Int, seed: Double,
splitProbability: Double) -> Int {
let normalized = log(Double(charCount) + 4) / log(24)
let jitter = tiltSeededRandom(seed: seed, offset: 1) * 0.6 + 0.7
let score = normalized * jitter * splitProbability
if score < 0.45 { return 1}
if score < 1.05 { return 2}
if score < 1.7 { return 3}
return 4
}

/// 纯省略号行（源码 /^[\s.…·。]+$/）不分段。
static func isEllipsisOnly(_ text: String) -> Bool {
let trimmed = text.trimmingCharacters(in:.whitespaces)
guard!trimmed.isEmpty else { return false}
let allowed: Set<Character> = [" ", ".", "…", "·", "。", "\t"]
return trimmed.allSatisfy { allowed.contains($0) || $0.isWhitespace}
}

/// markShortLastLine：末段非 tilt、修剪后 ≤2 字且长度
/// ×2 ≤ 前段长度时标短末段（渲染时字号 ×1.18）。
static func markShortLastLine(_ input: [TiltSegmentData]) -> [TiltSegmentData] {
var segs = input
guard segs.count >= 2 else { return segs}
let last = segs[segs.count - 1]
if last.isTilt || last.text.count > 2 { return segs}
let prev = segs[segs.count - 2]
if last.text.count * 2 <= prev.text.count {
segs[segs.count - 1].isShortLastLine = true
}
return segs
}

/// 逐字脉冲强度（源码 getCharPulseIntensity）：时长夹在
/// [0.2, 0.9]（原始下限 0.05）；段内 sin(π·p) 升降，
/// 段后以 duration × 1.2 的斜坡爬到 0.25 余辉并保持。
static func charPulseIntensity(currentTime: TimeInterval,
start: TimeInterval,
end: TimeInterval) -> CGFloat {
let rawDuration = max(end - start, 0.05)
let duration = min(max(rawDuration, 0.2), 0.9)
let elapsed = currentTime - start
if elapsed < 0 { return 0}
if elapsed <= duration {
return CGFloat(sin(elapsed / duration *.pi))
}
let afterElapsed = elapsed - duration
let afterglowRamp = duration * 1.2
if afterElapsed >= afterglowRamp { return 0.25}
return CGFloat(0.25 * (afterElapsed / afterglowRamp))
}
}

// MARK: - 布局数据

private struct TiltSegmentData {
var text: String
var isTilt: Bool
var isShortLastLine: Bool
var charOffset: Int
}

private struct TiltCharTiming {
var charIndex: Int
var start: TimeInterval
var end: TimeInterval
}

private struct TiltLayoutData {
var segments: [TiltSegmentData]
var scaleMultiplier: CGFloat
var fontSizes: [CGFloat]
var fonts: [UIFont]
var segmentSizes: [CGSize]
var segmentTimings: [(start: TimeInterval, end: TimeInterval)]
var charTimings: [[TiltCharTiming]]
var yOffset: CGFloat
}

// MARK: - 分段视图

/// 一个分段的视图：逐字素单元（外层 wrapper 管淡入与错落
/// 位移，内层 label 管脉冲缩放与斜切），段级管进出场位移/
/// 缩放/透明。动画曲线为源码 framer-motion 的
/// cubic-bezier(0.25, 0.46, 0.45, 0.94)。
private final class TiltSegmentView: UIView {

private struct CharCell {
var wrapper: UIView
var label: UILabel
var isSpace: Bool
var visualIndex: Int
var timingIndex: Int
}

private let segment: TiltSegmentData
private let charTimings: [TiltCharTiming]
private let yOffset: CGFloat
private var cells: [CharCell] = []
private(set) var isShown = false

init(segment: TiltSegmentData, fontSize: CGFloat, font: UIFont,
color: UIColor, charTimings: [TiltCharTiming], yOffset: CGFloat) {
self.segment = segment
self.charTimings = charTimings
self.yOffset = yOffset
super.init(frame:.zero)
isUserInteractionEnabled = false

let letterSpacing = fontSize * (segment.isTilt? 0.15: 0.08)
let spaceWidth = fontSize * (segment.isTilt? 0.35: 0.25)
let segmentHeight = fontSize * (segment.isTilt? 1.25: 1.35)
var cursor: CGFloat = 0
var visualIndex = 0
for grapheme in segment.text.map({ String($0)}) {
let isSpace = grapheme.allSatisfy { $0.isWhitespace}
let wrapper = UIView()
wrapper.isUserInteractionEnabled = false
let label = UILabel()
label.text = isSpace? "\u{00A0}": grapheme
label.font = font
label.textColor = color
label.isUserInteractionEnabled = false
label.sizeToFit()
let width = isSpace? spaceWidth: label.bounds.width
let height = label.bounds.height
label.frame = CGRect(x: 0, y: 0, width: width, height: height)
if segment.isTilt &&!isSpace {
// 斜体近似：逐字斜切（见头部注释）。
label.transform = CGAffineTransform(
a: 1, b: 0, c: -0.22, d: 1, tx: 0, ty: 0)
}
wrapper.frame = CGRect(
x: cursor, y: (segmentHeight - height) / 2,
width: width, height: height)
wrapper.addSubview(label)
addSubview(wrapper)
let timingIndex = isSpace? -1: visualIndex
if!isSpace { visualIndex += 1}
cells.append(CharCell(
wrapper: wrapper, label: label, isSpace: isSpace,
visualIndex: timingIndex, timingIndex: timingIndex))
cursor += width + letterSpacing
}
applyHiddenPose(animated: false)
}

@available(*, unavailable)
required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented")}

/// 段宽测量（与 init 内的逐字排布同口径，供布局阶段定尺寸）。
static func measureWidth(text: String, font: UIFont,
fontSize: CGFloat, isTilt: Bool) -> CGFloat {
let letterSpacing = fontSize * (isTilt? 0.15: 0.08)
let spaceWidth = fontSize * (isTilt? 0.35: 0.25)
var width: CGFloat = 0
var count = 0
for grapheme in text.map({ String($0)}) {
if grapheme.allSatisfy({ $0.isWhitespace}) {
width += spaceWidth
} else {
width += (grapheme as NSString)
.size(withAttributes: [.font: font]).width
}
count += 1
}
if count > 1 { width += letterSpacing * CGFloat(count - 1)}
return width
}

// MARK: 姿态与显隐

private func hiddenTransform() -> CGAffineTransform {
if segment.isTilt {
return CGAffineTransform(translationX: 0, y: 24)
.scaledBy(x: 0.92, y: 0.92)
}
return CGAffineTransform(translationX: 0, y: 20)
}

private func charHiddenOffset(visualIndex: Int, isSpace: Bool) -> CGFloat {
guard segment.isTilt,!isSpace else { return 0}
let stagger: CGFloat = visualIndex % 2 == 0? -1: 1
return stagger * yOffset * 2
}

private func charShownOffset(visualIndex: Int, isSpace: Bool) -> CGFloat {
guard segment.isTilt,!isSpace else { return 0}
let stagger: CGFloat = visualIndex % 2 == 0? -1: 1
return stagger * yOffset
}

private func applyHiddenPose(animated: Bool) {
let apply = {
self.transform = self.hiddenTransform()
self.alpha = 0
for cell in self.cells {
cell.wrapper.alpha = 0
cell.wrapper.transform = CGAffineTransform(
translationX: 0,
y: self.charHiddenOffset(visualIndex: cell.visualIndex,
isSpace: cell.isSpace))
}
}
if animated {
Self.bezierAnimator(duration: segment.isTilt? 0.6: 0.55,
animations: apply).startAnimation()
} else { apply()}
}

/// 显隐切换（源码 TiltLine 的 initial/animate 两态）：段级
/// 0.55s（普通）/0.6s（tilt），字素 0.5s + 段内序延迟
/// （普通 ×0.04、tilt ×0.05，空格无延迟）。
func setVisible(_ visible: Bool, animated: Bool) {
guard visible!= isShown ||!animated else {
if visible { return}
return
}
isShown = visible
if!visible {
applyHiddenPose(animated: animated)
return
}
let segmentApply = {
self.transform =.identity
self.alpha = 1
}
if animated {
Self.bezierAnimator(duration: segment.isTilt? 0.6: 0.55,
animations: segmentApply).startAnimation()
} else { segmentApply()}
for cell in cells {
let delay = animated &&!cell.isSpace
? Double(cell.visualIndex) * (segment.isTilt? 0.05: 0.04): 0
let apply = {
cell.wrapper.alpha = 1
cell.wrapper.transform = CGAffineTransform(
translationX: 0,
y: self.charShownOffset(visualIndex: cell.visualIndex,
isSpace: cell.isSpace))
}
if animated {
Self.bezierAnimator(duration: 0.5, animations: apply)
.startAnimation(afterDelay: delay)
} else { apply()}
}
}

/// 逐字脉冲（frameTick 驱动）：scale = 1 + 强度 ×（tilt
/// 0.18 / 普通 0.15）；源码靠 MotionValue + CSS 0.06s
/// 过渡平滑，原生逐帧直设（60fps 下更跟手，见档案）。
func updatePulse(position: TimeInterval) {
guard isShown else { return}
for cell in cells {
if cell.isSpace { continue}
var scale: CGFloat = 1
if cell.timingIndex >= 0 && cell.timingIndex < charTimings.count {
let timing = charTimings[cell.timingIndex]
let intensity = TiltStageRenderer.charPulseIntensity(
currentTime: position, start: timing.start, end: timing.end)
scale = 1 + intensity * (segment.isTilt? 0.18: 0.15)
}
if segment.isTilt {
cell.label.transform = CGAffineTransform(
a: scale, b: 0, c: -0.22 * scale, d: scale, tx: 0, ty: 0)
} else {
cell.label.transform = CGAffineTransform(scaleX: scale, y: scale)
}
}
}

/// 源码 framer-motion 曲线 cubic-bezier(0.25, 0.46, 0.45, 0.94)。
static func bezierAnimator(duration: TimeInterval,
animations: @escaping () -> Void) -> UIViewPropertyAnimator {
let params = UICubicTimingParameters(
controlPoint1: CGPoint(x: 0.25, y: 0.46),
controlPoint2: CGPoint(x: 0.45, y: 0.94))
return UIViewPropertyAnimator(
duration: duration, timingParameters: params, animations: animations)
}
}

// MARK: - 句子分段（SentenceLayout.splitIntoSentences 对应）

/// 源码 SentenceLayout 的原生移植：五级切分（标点 → 括号
/// 引号 → 西文词块 → CJK 空格 → 特殊符）逐级切到目标段数，
/// 不足时 secondarySplit 补切、过量时 mergeSentences 并最
/// 短对。字数口径以字素计（源码为 JS UTF-16 length，BMP
/// 内一致）。secondarySplit 的 Intl.Segmenter 词边界原生
/// 无对应物，以「CJK 逐字/空格/标点邻接为边界、取最接近
/// 中点的边界」近似，差异见档案。
private enum TiltSentenceSplitter {

static func splitIntoSentences(text: String, targetCount: Int, seed: Double) -> [String] {
if targetCount <= 1 { return [text]}
var sentences = [text]
for level in 1...5 {
if sentences.count >= targetCount { break}
sentences = sentences.flatMap { splitByLevel($0, level)}
}
var result = sentences
if result.count < targetCount {
result = secondarySplit(result, targetCount: targetCount)
}
if result.count > targetCount {
result = mergeSentences(result, targetCount: targetCount)
}
return result
}

private static func splitByLevel(_ text: String, _ level: Int) -> [String] {
switch level {
case 1: return splitByPunctuation(text)
case 2: return splitByBracketsQuotes(text)
case 3: return splitByWesternWords(text)
case 4: return splitCJKBySpace(text)
case 5: return splitBySpecialChars(text)
default: return [text]
}
}

// 一级：标点（标点串 + 其后空格归前段）。
private static func splitByPunctuation(_ text: String) -> [String] {
let punct: Set<Character> = ["，", "。", "；", "！", "？", "、", "…", "·",
".", ",", ";", "!", "?"]
let chars = Array(text)
var result: [String] = []
var current = ""
var i = 0
while i < chars.count {
let ch = chars[i]
current.append(ch)
if punct.contains(ch) {
i += 1
while i < chars.count && punct.contains(chars[i]) {
current.append(chars[i]); i += 1
}
while i < chars.count && chars[i].isWhitespace {
current.append(chars[i]); i += 1
}
result.append(current)
current = ""
} else {
i += 1
}
}
if!current.isEmpty { result.append(current)}
return result.isEmpty? [text]: result
}

// 二级：括号/引号最外层配对（递归切 before/配对段/rest）。
private static func splitByBracketsQuotes(_ text: String) -> [String] {
let pairs: [(String, String)] = [
("「", "」"), ("『", "』"), ("《", "》"), (""),
("｛", "｝"), ("［", "］"), ("[", "]"), ("（", "）"),
("(", ")"), ("\"", "\""), ("'", "'"),
]
let chars = Array(text).map { String($0)}
var best: (open: Int, close: Int)? = nil
for (openStr, closeStr) in pairs {
guard let openIdx = chars.firstIndex(of: openStr) else { continue}
var closeIdx: Int? = nil
if openIdx + 1 < chars.count {
for j in (openIdx + 1)..<chars.count where chars[j] == closeStr {
closeIdx = j
break
}
}
guard let close = closeIdx else { continue}
if best == nil || openIdx < best!.open
|| (openIdx == best!.open && close > best!.close) {
best = (openIdx, close)
}
}
guard let found = best else { return [text]}
var result: [String] = []
let before = chars[0..<found.open].joined()
let paired = chars[found.open...found.close].joined()
let rest = found.close + 1 < chars.count
? chars[(found.close + 1)...].joined(): ""
if!before.isEmpty { result.append(contentsOf: splitByBracketsQuotes(before))}
result.append(paired)
if!rest.isEmpty { result.append(contentsOf: splitByBracketsQuotes(rest))}
return result.count > 1? result: [text]
}

// 三级：含 CJK 时把多词西文块切成独立段。
private static func splitByWesternWords(_ text: String) -> [String] {
guard hasCJK(text) else { return [text]}
let pattern = "[a-zA-Z0-9]+(?:[a-zA-Z0-9'\\-]*[a-zA-Z0-9]+)?"
+ "(?:\\s+[a-zA-Z0-9]+(?:[a-zA-Z0-9'\\-]*[a-zA-Z0-9]+)?)+"
+ "[.,;:!?。，；：！？]?\\s*"
guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text]}
let nsText = text as NSString
let matches = regex.matches(
in: text, range: NSRange(location: 0, length: nsText.length))
var hasMultiWordBlock = false
for match in matches {
let block = nsText.substring(with: match.range)
let words = block.split(whereSeparator: { $0.isWhitespace}).count
if words > 1 { hasMultiWordBlock = true; break}
}
guard hasMultiWordBlock,!matches.isEmpty else { return [text]}
var parts: [String] = []
var lastIndex = 0
for match in matches {
let blockStart = match.range.location
let blockEnd = blockStart + match.range.length
let before = nsText.substring(
with: NSRange(location: lastIndex, length: blockStart - lastIndex))
let block = nsText.substring(with: match.range)
if shouldSkipBoundary(fullText: text, beforeBlock: before) {
parts.append(before + block)
} else if blockStart > lastIndex {
parts.append(before)
parts.append(block)
} else {
parts.append(block)
}
lastIndex = blockEnd
}
if lastIndex < nsText.length {
parts.append(nsText.substring(from: lastIndex))
}
let filtered = parts.filter {!$0.isEmpty}
return filtered.count > 1? filtered: [text]
}

private static func shouldSkipBoundary(fullText: String, beforeBlock: String) -> Bool {
guard let last = beforeBlock.last else { return false}
if last == "-" { return true}
if last == ":" || last == "：" || last == "/" || last == "／"
|| last == "|" || last == "｜" {
return fullText.filter { $0 == last}.count >= 2
}
return false
}

// 四级：CJK 块内空格切分（全角空格恒切；半角空格在
// CJK 字后切；其余空格跟随当前块）。
private static func splitCJKBySpace(_ text: String) -> [String] {
guard hasCJK(text) else { return [text]}
var segments: [String] = []
var current = ""
var inCjkBlock = false
for ch in text {
if isCJK(ch) {
current.append(ch)
inCjkBlock = true
} else if ch.isLetter || ch.isNumber {
current.append(ch)
} else if ch.isWhitespace {
if ch == "　" &&!current.isEmpty {
current.append(ch)
segments.append(current)
current = ""
inCjkBlock = false
} else if inCjkBlock &&!current.isEmpty,
let last = current.last, isCJK(last) {
current.append(ch)
segments.append(current)
current = ""
inCjkBlock = false
} else if current.isEmpty &&!segments.isEmpty {
segments[segments.count - 1].append(ch)
} else {
current.append(ch)
}
} else {
if current.isEmpty &&!segments.isEmpty {
segments[segments.count - 1].append(ch)
} else {
current.append(ch)
}
}
}
if!current.isEmpty {
if!segments.isEmpty && current.allSatisfy({ $0.isWhitespace}) {
segments[segments.count - 1] += current
} else {
segments.append(current)
}
}
return segments.count > 1? segments: [text]
}

// 五级：特殊符（分隔符串归前段）。
private static func splitBySpecialChars(_ text: String) -> [String] {
let separators: Set<Character> = ["：", ":", "/", "／", "\\", "|", "｜", "~", "～"]
let chars = Array(text)
var result: [String] = []
var current = ""
var i = 0
var sawSeparator = false
while i < chars.count {
if separators.contains(chars[i]) {
sawSeparator = true
while i < chars.count && separators.contains(chars[i]) {
current.append(chars[i]); i += 1
}
if!current.isEmpty {
result.append(current)
current = ""
}
} else {
current.append(chars[i]); i += 1
}
}
if!current.isEmpty { result.append(current)}
guard sawSeparator, result.count > 1 else { return [text]}
return result
}

// 补切：候选段（>2 字）里按平衡分取最优段，在最接近
// 中点的词边界处切开（边界近似见头部注释）。
private static func secondarySplit(_ input: [String], targetCount: Int) -> [String] {
var sentences = input
while sentences.count < targetCount {
var best: (index: Int, splitPos: Int, score: Double)? = nil
for (index, sentence) in sentences.enumerated() {
let chars = Array(sentence)
guard chars.count > 2 else { continue}
var boundaries: [Int] = []
for pos in 1..<chars.count {
let prev = chars[pos - 1]
let cur = chars[pos]
if isCJK(prev) || isCJK(cur) || prev.isWhitespace
|| cur.isWhitespace || isPunctuation(prev) {
boundaries.append(pos)
}
}
guard!boundaries.isEmpty else { continue}
let mid = Double(chars.count) / 2
var bestPos = boundaries[0]
var bestDist = Double.greatestFiniteMagnitude
for pos in boundaries {
let dist = abs(Double(pos) - mid)
if dist < bestDist { bestDist = dist; bestPos = pos}
}
let balance = 1 - abs(Double(bestPos) - mid) / mid
let score = balance * 10 + Double(boundaries.count + 1)
if best == nil || score > best!.score {
best = (index, bestPos, score)
}
}
guard let chosen = best else { break}
let chars = Array(sentences[chosen.index])
let first = String(chars[0..<chosen.splitPos])
let second = String(chars[chosen.splitPos...])
sentences.replaceSubrange(
chosen.index...chosen.index, with: [first, second])
}
return sentences
}

// 并段：反复合并相邻最短对直到目标段数。
private static func mergeSentences(_ input: [String], targetCount: Int) -> [String] {
var sentences = input
while sentences.count > targetCount {
var bestIndex = 0
var shortest = Int.max
for i in 0..<(sentences.count - 1) {
let combined = sentences[i].count + sentences[i + 1].count
if combined < shortest {
shortest = combined
bestIndex = i
}
}
let merged = sentences[bestIndex] + sentences[bestIndex + 1]
sentences.replaceSubrange(bestIndex...(bestIndex + 1), with: [merged])
}
return sentences
}

private static func hasCJK(_ text: String) -> Bool {
text.contains { isCJK($0)}
}

private static func isCJK(_ ch: Character) -> Bool {
guard let scalar = ch.unicodeScalars.first else { return false}
let v = scalar.value
return (0x4E00...0x9FA5).contains(v) || (0x3040...0x30FF).contains(v)
|| (0xAC00...0xD7AF).contains(v)
}

private static func isPunctuation(_ ch: Character) -> Bool {
let punct: Set<Character> = ["，", "。", "；", "！", "？", "、", "…", "·",
".", ",", ";", "!", "?", "：", ":"]
return punct.contains(ch)
}
}
