import UIKit
import QuartzCore

// 雾笺 nebbia 全原生移植（3.7 (57) 工作流 B8，网页标样式第八/最末）：
// 雨夜公交车窗起雾，手指在雾上逐字写歌词，擦开处透出窗外街景，
// 写完慢慢起雾或被手指抹掉。依据文件：folia-major/src/components/
// visualizer/nebbia/ 全目录（约 60 文件 7500 行，WebGL2 多通道）。
//
// ── 小样验证与呈现选型（DS R55 警告：nebbia 是 GPU/内存陷阱）──
// 最小原型 = 单层雾 + 当前行歌词，先算负载再定全量构成：
//  · 网页版每帧：全屏场景着色器（楼群/霓虹程序化生成）+ 雾预
//    渲染 2–3 通道（1/4、1/8 分辨率 RGBA16F）+ 0.5 倍擦除遮罩
//    + 水珠折射主通道，全屏像素着色 ≥ 8–12 Mpx/帧且每像素带
//    FBM 噪声——iPhone 14 Pro 全屏 1179×2556 ≈ 3.01 Mpx，直译
//    必破 P95 16.7ms 与舞台纹理预算，判不过红线，不直译。
//  · 原生选型 = 离屏烘焙 + 图层合成（照 Monet 烘焙纪律）：
//    窗外场景、雾纹理、凝露层、羽化遮罩全部「参数/尺寸/调色
//    板变化时」在后台队列烘焙成图（UIGraphics 绘制，非逐帧），
//    呈现层只有 UIImageView / CAGradientLayer / UILabel 的图层
//    属性动画。每帧（frameTick）零栅格化、零全屏重绘、无任何
//    实时高斯模糊（羽化遮罩是烘焙期多层叠画，不是逐帧滤镜）。
//  · 负载估算（14 Pro 竖屏 393×852pt）：烘焙纹理总量 ≤ 5MB
//    （场景长边钳 1024px ≈ 1.9MB、雾 1/4 缩 ≤ 288px ≈ 0.3MB×2、
//    凝露 ≤ 768px ≈ 1.2MB、水母/光斑小图 < 0.5MB），远低于舞台
//    纹理 200–250MB 线；逐帧合成 = 约 8 层纹理四边形 + ≤ 3 行
//    × ≤ 44 个字形标签 + ≤ 56 颗水珠视图，均为合成器混合、无
//    片元程序，P95 帧宽裕。结论：估算过线，按此构成落全量，
//    降级点见文件尾自查（笔顺/折射/节拍联动等数据源缺口）。
//
// ── 渲染面分辨率钳制 ──
// 场景图：像素长边 ≤ 1024（按 bounds 宽高比出图，横竖屏同钳）；
// 雾纹理：bounds 的 1/4（网页 FOG_DIV=4）且长边 ≤ 288px；
// 凝露图：0.5 倍 bounds 且长边 ≤ 768px；羽化遮罩：行矩形 0.5
// 倍。renderScale（tuning.render）非 global 时按倍率乘钳制
// 上限（0.5×→512 / 2×→2048），仍不触 250MB 线（2× 时场景
// ≈ 7.6MB）。旋转/尺寸变化按新 bounds 重烘（旧图保留至新图
// 落地，不闪空）。
//
// 时钟纪律：歌词同步元素（逐字擦出/起雾/抹除/聚光灯目标）只
// 由宿主 frameTick(position) 推进；雾漂移、水母、气泡、雪落
// 这类环境动画走图层动画（任务书允许）；聚光灯弹簧的平滑时
// 钟与网页 NebbiaSpot 同构（自平滑时钟追播放时间）。
// 数据只从 snapshot/context 取：封面位图协议不下发，窗外配
// 色由 PaletteTokens 按网页 nebbiaPalette.ts 规则派生。

// MARK: - 确定性随机（网页 visualizerSeedHash.ts 逐位对译）

/// FNV-1a 32 位（JS charCodeAt = UTF-16 码元，逐一对齐）+
/// mulberry32 随机流（createVisualizerRng）。构图挑选、涂鸦、
/// 消失方式、出现方式的随机抽签与网页同源同序。
private struct NebbiaRng {
    var state: UInt32

    init(seed: UInt32) { state = seed }

    init(stringSeed: String) { state = NebbiaRng.fnv1a(stringSeed) }

    static func fnv1a(_ value: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for unit in value.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 16777619
        }
        return hash
    }

    mutating func next() -> Double {
        state = state &+ 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (1 | t)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

private func nebbiaClamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    min(hi, max(lo, v))
}
private func nebbiaSmooth(_ t: Double) -> Double {
    let x = nebbiaClamp(t, 0, 1)
    return x * x * (3 - 2 * x)
}

// MARK: - 调色板派生（nebbiaPalette.ts 对译，输入 = 协议 PaletteTokens）

private struct NebbiaPalette {
    var sky0: UIColor
    var sky1: UIColor
    var la: UIColor
    var lb: UIColor
    var lc: UIColor
}

private func nebbiaRGB(_ color: UIColor) -> (r: Double, g: Double, b: Double) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (Double(r), Double(g), Double(b))
}

private func nebbiaHSL(_ c: (r: Double, g: Double, b: Double))
    -> (h: Double, s: Double, l: Double) {
    let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
    let l = (mx + mn) / 2, d = mx - mn
    if d == 0 { return (0, 0, l) }
    let s = d / (1 - abs(2 * l - 1))
    let h: Double
    if mx == c.r { h = ((c.g - c.b) / d + 6).truncatingRemainder(dividingBy: 6) }
    else if mx == c.g { h = (c.b - c.r) / d + 2 }
    else { h = (c.r - c.g) / d + 4 }
    return (h / 6, s, l)
}

private func nebbiaFromHSL(_ hsl: (h: Double, s: Double, l: Double)) -> UIColor {
    let (h, s, l) = hsl
    func k(_ n: Double) -> Double { (n + h * 12).truncatingRemainder(dividingBy: 12) }
    let a = s * min(l, 1 - l)
    func f(_ n: Double) -> Double {
        l - a * max(-1, min(k(n) - 3, min(9 - k(n), 1)))
    }
    return UIColor(red: CGFloat(f(0)), green: CGFloat(f(8)),
                   blue: CGFloat(f(4)), alpha: 1)
}

/// 网页 resolveNebbiaPalette：天色两档 + 三个灯光色（强调色
/// 打头，其余取够鲜艳的主题色，不够把强调色转色相补上）。
/// 协议无 wordColors，候选只取 secondary / primary 两色。
private func nebbiaResolvePalette(_ tokens: PaletteTokens) -> NebbiaPalette {
    let accent = nebbiaRGB(tokens.accent)
    let bg = nebbiaRGB(tokens.background)
    func asLight(_ rgb: (r: Double, g: Double, b: Double))
        -> (r: Double, g: Double, b: Double) {
        let hsl = nebbiaHSL(rgb)
        let out = nebbiaFromHSL((hsl.h, max(0.55, hsl.s),
                                 min(0.78, max(0.6, hsl.l))))
        return nebbiaRGB(out)
    }
    func asSky(_ rgb: (r: Double, g: Double, b: Double), _ lightness: Double) -> UIColor {
        let hsl = nebbiaHSL(rgb)
        return nebbiaFromHSL((hsl.h, min(0.55, hsl.s), lightness))
    }
    let vivid = [tokens.secondary, tokens.primary].map { nebbiaRGB($0) }.filter {
        let hsl = nebbiaHSL($0)
        return hsl.s > 0.3 && hsl.l > 0.25 && hsl.l < 0.9
    }
    let ah = nebbiaHSL(accent)
    func rotated(_ turns: Double) -> (r: Double, g: Double, b: Double) {
        nebbiaRGB(nebbiaFromHSL(((ah.h + turns).truncatingRemainder(dividingBy: 1),
                                 ah.s, ah.l)))
    }
    let lbRaw = vivid.count > 0 ? vivid[0] : rotated(0.55)
    let lcRaw = vivid.count > 1 ? vivid[1] : rotated(0.9)
    let skyMix = (r: bg.r * 0.7 + accent.r * 0.3,
                  g: bg.g * 0.7 + accent.g * 0.3,
                  b: bg.b * 0.7 + accent.b * 0.3)
    return NebbiaPalette(
        sky0: asSky(bg, 0.05),
        sky1: asSky(skyMix, 0.14),
        la: nebbiaFromHSL(nebbiaHSL(asLight(accent))),
        lb: nebbiaFromHSL(nebbiaHSL(asLight(lbRaw))),
        lc: nebbiaFromHSL(nebbiaHSL(asLight(lcRaw))))
}

// MARK: - 逐字源数据（nebbiaChars.ts 对译）

/// emoji → 图标名（网页 EMOJI_ICON 同表）；原生无 lucide 线稿
/// 数据源，图标以同义文字符号呈现（见 nebbiaIconGlyph）。
private let nebbiaEmojiIcon: [String: String] = [
    "❤": "Heart", "♥": "Heart", "💗": "Heart",
    "⭐": "Star", "★": "Star", "☆": "Star",
    "🌙": "Moon", "☀": "Sun", "🌞": "Sun",
    "🎵": "Music", "♪": "Music2", "🎶": "Music",
    "🌸": "Flower", "✿": "Flower2", "🌷": "Flower2",
    "✨": "Sparkles", "☁": "Cloud", "🌧": "CloudRain",
    "☂": "Umbrella", "☔": "Umbrella", "🐱": "Cat",
    "😊": "Smile", "🙂": "Smile", "❄": "Snowflake",
    "🍃": "Leaf", "🌿": "Leaf", "🪶": "Feather",
]

/// 图标名 → 原生呈现字形（线稿图标的数据缺口降级，语义对应）。
private func nebbiaIconGlyph(_ name: String) -> String {
    switch name {
    case "Heart": return "♥"
    case "Star": return "★"
    case "Moon": return "☾"
    case "Sun": return "☀"
    case "Music", "Music2": return "♪"
    case "Flower", "Flower2": return "✿"
    case "Sparkles": return "✦"
    case "Cloud": return "☁"
    case "CloudRain": return "☔"
    case "Umbrella": return "☂"
    case "Cat": return "🐱"
    case "Smile": return "☺"
    case "Snowflake": return "❄"
    case "Leaf": return "☘"
    case "Feather": return "🪶"
    default: return "✦"
    }
}

/// 网页 NEBBIA_DEFAULT_DOODLES（句尾涂鸦池）。
private let nebbiaDefaultDoodles = ["Heart", "Star", "Moon", "Music",
                                    "Flower", "Sparkles", "CloudRain",
                                    "Umbrella", "Smile", "Leaf"]

/// 一个字（源）：webCh 是网页口径的字符串（图标为
/// "icon:<名>"，参与排版散列），text 是原生呈现字形。
private struct NebbiaSourceChar {
    var webCh: String
    var text: String
    var isIcon: Bool
    var t: TimeInterval
    var d: TimeInterval
}

private struct NebbiaSourceLine {
    var chars: [NebbiaSourceChar]
    var words: [[Int]]
    var t: TimeInterval
    var end: TimeInterval
    var next: TimeInterval
    var credits: Int = 0   // 0 无 / 1 曲名 / 2 歌手
}

/// 协议行 → 逐字源：有逐字戳（YRC）时按词内字素均分词时段
/// （网页 buildLineGraphemeTimeline 同口径）；无戳时整行字素
/// 在演唱窗（span × singingRatio，(43) 路3 同口径）内均分。
/// 词分组以 StageLyricUnits 的单元为词（CJK 逐字成词、拉丁
/// 按词——网页走分词器，用户分词/词典原生无数据源，差异注
/// 明在报告）；标点并入前词、片假名串并回（mergeWords）。
private func nebbiaSourceChars(for line: LyricLine)
    -> (chars: [NebbiaSourceChar], words: [[Int]]) {
    var chars: [NebbiaSourceChar] = []
    var words: [[Int]] = []
    func appendChar(_ grapheme: String, _ t: TimeInterval, _ d: TimeInterval) {
        let bare = grapheme.replacingOccurrences(of: "\u{FE0F}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
        if let icon = nebbiaEmojiIcon[bare] ?? nebbiaEmojiIcon[grapheme] {
            chars.append(NebbiaSourceChar(
                webCh: "icon:\(icon)", text: nebbiaIconGlyph(icon),
                isIcon: true, t: t, d: d))
        } else {
            chars.append(NebbiaSourceChar(
                webCh: grapheme, text: grapheme, isIcon: false, t: t, d: d))
        }
    }
    if let lineWords = line.words, !lineWords.isEmpty {
        for word in lineWords {
            let graphemes = Array(word.text)
            guard !graphemes.isEmpty else { continue }
            let span = max(word.end - word.start, 0.01)
            var group: [Int] = []
            for (i, g) in graphemes.enumerated() {
                let t = word.start + span * Double(i) / Double(graphemes.count)
                appendChar(String(g), t, span / Double(graphemes.count))
                group.append(chars.count - 1)
            }
            if !group.isEmpty { words.append(group) }
        }
    } else {
        let units = StageLyricUnits.units(for: line)
        let ratio = min(max(line.singingRatio, 0.3), 1)
        let span = max((line.end - line.start) * ratio, 0.1)
        let totalGraphemes = max(line.text.count, 1)
        var offset = 0
        for unit in units {
            let graphemes = Array(unit.text)
            var group: [Int] = []
            for g in graphemes {
                let t = line.start + span * Double(offset) / Double(totalGraphemes)
                let d = span / Double(totalGraphemes)
                appendChar(String(g), t, d)
                group.append(chars.count - 1)
                offset += 1
            }
            if !group.isEmpty { words.append(group) }
        }
        // 空白占份额（与 StageLyricUnits 的偏移口径一致，源
        // 字符不产出）：units 已按含空白的总字素数均分，偏移
        // 由 tokenize 推进，此处无需再补。
        _ = offset
    }
    return (chars, nebbiaMergeWords(chars: chars, words: words))
}

private let nebbiaPunctSet: Set<String> = ["，", "。", "、", "！", "？",
                                           "!", "?", ",", ".", "・", "…"]
private func nebbiaIsKatakana(_ ch: String) -> Bool {
    ch.unicodeScalars.allSatisfy { (0x30A0...0x30FF).contains($0.value) }
}

/// mergeWords 对译：标点词并入前词；纯片假名词与前一纯片假
/// 名词相邻时并回。
private func nebbiaMergeWords(chars: [NebbiaSourceChar], words: [[Int]]) -> [[Int]] {
    var out: [[Int]] = []
    for w in words {
        let kata = w.allSatisfy { nebbiaIsKatakana(chars[$0].webCh) }
        if let last = out.last {
            let lastKata = last.allSatisfy { nebbiaIsKatakana(chars[$0].webCh) }
            let allPunct = w.allSatisfy { nebbiaPunctSet.contains(chars[$0].webCh) }
            if allPunct || (kata && lastKata && w[0] == (last.last ?? -2) + 1) {
                out[out.count - 1].append(contentsOf: w)
                continue
            }
        }
        out.append(w)
    }
    return out
}

/// 整首逐字源（buildNebbiaLines 对译 + appendNebbiaCredits）：
/// 种子 = 曲目 id 的 FNV（网页 seed 由宿主给歌曲种子串，原生
/// 以 track.id 等价）；涂鸦抽签顺序与网页一致（rng 只在「有
/// 末字、无现成图标」时才取第一值）。
private func nebbiaBuildSource(lines: [LyricLine], trackId: String?,
                               title: String?, artist: String?,
                               doodle: Double, credits: Bool) -> [NebbiaSourceLine] {
    let seedString = trackId ?? "nebbia"
    let base = NebbiaRng.fnv1a(seedString)
    var out: [NebbiaSourceLine] = []
    for (index, line) in lines.enumerated() {
        var (chars, words) = nebbiaSourceChars(for: line)
        var rng = NebbiaRng(seed: (base &+ UInt32(bitPattern:
            Int32(truncatingIfNeeded: (index + 1) &* 977)) &+ 31))
        if let last = chars.last, !chars.contains(where: { $0.isIcon }) {
            if rng.next() < doodle {
                let at = last.t + last.d
                chars.append(NebbiaSourceChar(
                    webCh: " ", text: " ", isIcon: false, t: at, d: 0))
                let pick = nebbiaDefaultDoodles[
                    min(Int(rng.next() * Double(nebbiaDefaultDoodles.count)),
                        nebbiaDefaultDoodles.count - 1)]
                chars.append(NebbiaSourceChar(
                    webCh: "icon:\(pick)", text: nebbiaIconGlyph(pick),
                    isIcon: true, t: at + 0.08, d: 1.1))
                words.append([chars.count - 1])
            }
        }
        let end = max(line.start, line.end)
        let next = index + 1 < lines.count ? lines[index + 1].start : .infinity
        out.append(NebbiaSourceLine(chars: chars, words: words,
                                    t: line.start, end: end, next: next))
    }
    // 片尾（nebbiaCredits.ts 的原生等价）：曲名、歌手各成一
    // 行源，t = 末行 end + 0.3（网页细则为末行唱完后排写，
    // 时序近似见报告），字时段名义 0.3s 逐字推进。
    if credits, let title, !title.isEmpty {
        let start = (lines.last.map { max($0.end, $0.start) } ?? 0) + 0.3
        func creditLine(_ text: String, _ t: TimeInterval, _ kind: Int) -> NebbiaSourceLine {
            var cs: [NebbiaSourceChar] = []
            var ws: [[Int]] = []
            for (i, g) in Array(text).enumerated() {
                cs.append(NebbiaSourceChar(
                    webCh: String(g), text: String(g), isIcon: false,
                    t: t + Double(i) * 0.3, d: 0.3))
                ws.append([i])
            }
            return NebbiaSourceLine(chars: cs, words: ws, t: t,
                                    end: t + Double(cs.count) * 0.3,
                                    next: .infinity, credits: kind)
        }
        out.append(creditLine(title, start, 1))
        if let artist, !artist.isEmpty {
            let titleLine = out[out.count - 1]
            out.append(creditLine(artist, titleLine.end + 0.9, 2))
        }
    }
    return out
}

// MARK: - 词块与角色（nebbiaBlocks.ts 对译）

private func nebbiaIsWideChar(_ ch: String) -> Bool {
    guard let v = ch.unicodeScalars.first?.value else { return false }
    return (0x3000...0x9FFF).contains(v) || (0xFF00...0xFFEF).contains(v)
}

private func nebbiaIsCJK(_ ch: String) -> Bool {
    guard let v = ch.unicodeScalars.first?.value else { return false }
    return (0x3040...0x30FF).contains(v) || (0x3400...0x9FFF).contains(v)
        || (0xF900...0xFAFF).contains(v)
}

/// 横排时一个字占的宽（× 字号），advanceOf 对译。
private func nebbiaAdvanceOf(_ ch: NebbiaSourceChar) -> Double {
    if ch.isIcon { return 1.1 }
    let s = ch.webCh
    if s == " " { return 0.32 }
    if ["，", "。", "、", "・", "．"].contains(s) { return 0.5 }
    if nebbiaIsWideChar(s) { return 1 }
    if ["i", "l", ".", ",", "'", "!", "|", ":", ";"].contains(s) { return 0.3 }
    if ["m", "w", "M", "W"].contains(s) { return 0.72 }
    return 0.5
}

private enum NebbiaRole {
    case hero, semi, support, particle
    var scale: Double {
        switch self {
        case .hero: return 2.0
        case .semi: return 1.35
        case .support: return 1
        case .particle: return 0.78
        }
    }
    var scaleFast: Double {
        switch self {
        case .hero: return 1.55
        case .semi: return 1.18
        case .support: return 1
        case .particle: return 0.85
        }
    }
}

private let nebbiaParticles: Set<String> = Set(
    "的了着过吗呢吧啊呀嘛之与和是也都就还又被把给のがをにはへとでやもねよなかしてたっ".map(String.init))

/// assignRoles 对译：主词（字数×14 + 时长×18 打分最高）、
/// 副主词（词数 ≥4、离主词 ≥2、分数 ≥ 主词 35%、至少两字）、
/// 单字虚词缩小。
private func nebbiaAssignRoles(chars: [NebbiaSourceChar],
                               words: [[Int]]) -> [NebbiaRole] {
    func score(_ w: [Int]) -> Double {
        let len = w.filter { !chars[$0].webCh.trimmingCharacters(
            in: .whitespaces).isEmpty }.count
        let t0 = chars[w[0]].t
        let last = chars[w[w.count - 1]]
        return Double(min(len, 8)) * 14
            + nebbiaClamp(last.t + last.d - t0, 0, 2.5) * 18
    }
    let scores = words.map(score)
    var hero = 0
    for (i, s) in scores.enumerated() where s > scores[hero] { hero = i }
    var semi = -1
    if words.count >= 4 {
        for (i, w) in words.enumerated() {
            if i == hero || abs(i - hero) < 2 || w.count < 2
                || scores[i] < scores[hero] * 0.35 { continue }
            if semi < 0 || scores[i] > scores[semi] { semi = i }
        }
    }
    return words.enumerated().map { (i, w) in
        if i == hero && words.count > 1 { return .hero }
        if i == semi { return .semi }
        if w.count == 1 && nebbiaParticles.contains(chars[w[0]].webCh) {
            return .particle
        }
        return .support
    }
}

private struct NebbiaBlockWord {
    var idx: [Int]
    var scale: Double
    var cjk: Bool
}

private struct NebbiaBlock {
    var role: NebbiaRole
    var words: [NebbiaBlockWord]
}

/// makeBlocks 对译：虚词先并前块；还多就把相邻、都不是主次
/// 词、合起来最短的两块并起来，直到 ≤ maxBlocks。
private func nebbiaMakeBlocks(chars: [NebbiaSourceChar], words: [[Int]],
                              roles: [NebbiaRole], fast: Bool,
                              maxBlocks: Int) -> [NebbiaBlock] {
    func isCjkWord(_ w: [Int]) -> Bool {
        w.allSatisfy {
            nebbiaIsCJK(chars[$0].webCh) || nebbiaPunctSet.contains(chars[$0].webCh)
        }
    }
    var blocks: [NebbiaBlock] = []
    for (i, w) in words.enumerated() {
        let role = roles[i]
        let word = NebbiaBlockWord(
            idx: w, scale: fast ? role.scaleFast : role.scale, cjk: isCjkWord(w))
        if role == .particle, let last = blocks.last,
           last.role != .hero, last.role != .semi {
            blocks[blocks.count - 1].words.append(word)
        } else {
            blocks.append(NebbiaBlock(role: role, words: [word]))
        }
    }
    func len(_ b: NebbiaBlock) -> Int { b.words.reduce(0) { $0 + $1.idx.count } }
    func strong(_ b: NebbiaBlock) -> Bool { b.role == .hero || b.role == .semi }
    while blocks.count > maxBlocks {
        var bi = -1, bl = Int.max
        for i in 0..<(blocks.count - 1) {
            if strong(blocks[i]) || strong(blocks[i + 1]) { continue }
            let l = len(blocks[i]) + len(blocks[i + 1])
            if l < bl { bl = l; bi = i }
        }
        if bi < 0 { break }
        blocks[bi] = NebbiaBlock(role: .support,
                                 words: blocks[bi].words + blocks[bi + 1].words)
        blocks.remove(at: bi + 1)
    }
    return blocks
}

// MARK: - 块测量与构图（nebbiaCompositions.ts 对译）

private struct NebbiaMeasureItem {
    var k: Int
    var off: Double
    var s: Double
    var rot: Double   // 弧度
    var punct: Bool
}

private struct NebbiaMeasured {
    var vertical: Bool
    var items: [NebbiaMeasureItem]
    var w: Double
    var h: Double
}

private struct NebbiaPlacedItem {
    var k: Int
    var x: Double
    var y: Double
    var s: Double
    var rot: Double
}

private let nebbiaFlowGap = 0.3
private let nebbiaStackGap = 0.32
private let nebbiaTurnInVertical: Set<String> = ["ー", "—", "～", "〜", "…", "-"]

/// measureBlock 对译（'h' 横排 / 'v' 竖排）。网页的
/// complexScale（按 AnimCJK 笔画数放大生僻字）依赖笔顺数据
/// 集，原生无数据源，未落（差异见报告）。
private func nebbiaMeasureBlock(_ block: NebbiaBlock,
                                chars: [NebbiaSourceChar],
                                vertical: Bool) -> NebbiaMeasured {
    var items: [NebbiaMeasureItem] = []
    var pen = 0.0, thick = 0.0
    for (wi, w) in block.words.enumerated() {
        if wi > 0 {
            let gap = (block.words[wi - 1].cjk && w.cjk ? 0.04 : 0.24)
                * (vertical && w.cjk ? 0 : 1)
            pen += gap
        }
        for k in w.idx {
            let ch = chars[k]
            let vertCjk = vertical && w.cjk
            let a: Double
            if vertCjk {
                a = nebbiaPunctSet.contains(ch.webCh) ? 0.55 : 1.02
            } else {
                a = nebbiaAdvanceOf(ch)
            }
            let rot = vertical && (!w.cjk || nebbiaTurnInVertical.contains(ch.webCh))
                ? Double.pi / 2 : 0
            let s = w.scale
            items.append(NebbiaMeasureItem(
                k: k, off: pen + a * s / 2, s: s, rot: rot,
                punct: vertCjk && nebbiaPunctSet.contains(ch.webCh)))
            pen += a * s
            thick = max(thick, s)
        }
    }
    return vertical
        ? NebbiaMeasured(vertical: true, items: items, w: thick, h: pen)
        : NebbiaMeasured(vertical: false, items: items, w: pen, h: thick)
}

/// emitBlock 对译：量好的块放到中心 (cx, cy)。
private func nebbiaEmitBlock(_ m: NebbiaMeasured, _ cx: Double, _ cy: Double,
                             _ out: inout [NebbiaPlacedItem]) {
    for it in m.items {
        if !m.vertical {
            out.append(NebbiaPlacedItem(
                k: it.k, x: cx - m.w / 2 + it.off, y: cy + m.h / 2 - it.s / 2,
                s: it.s, rot: 0))
        } else {
            out.append(NebbiaPlacedItem(
                k: it.k, x: cx + (it.punct ? it.s * 0.3 : 0),
                y: cy - m.h / 2 + it.off - (it.punct ? it.s * 0.2 : 0),
                s: it.s, rot: it.rot))
        }
    }
}

private func nebbiaHasTurned(_ m: NebbiaMeasured) -> Int {
    m.items.contains { $0.rot != 0 } ? 1 : 0
}

private struct NebbiaCompositionResult {
    var items: [NebbiaPlacedItem]
    var vRot: Int
}

/// 几行块（flowRows 对译）：行内底边对齐，行间按真实行高叠。
private func nebbiaFlowRows(blocks: [NebbiaBlock], chars: [NebbiaSourceChar],
                            rows: [[Int]], shifts: [Double]) -> NebbiaCompositionResult {
    var out: [NebbiaPlacedItem] = []
    let rowMs = rows.map { $0.map { nebbiaMeasureBlock(blocks[$0], chars: chars, vertical: false) } }
    let rowW = rowMs.map {
        $0.reduce(0) { $0 + $1.w } + nebbiaFlowGap * Double(max($0.count - 1, 0))
    }
    let widest = rowW.max() ?? 0
    var y = 0.0
    for (ri, ms) in rowMs.enumerated() {
        let rh = ms.map { $0.h }.max() ?? 0
        var x = -rowW[ri] / 2 + shifts[ri] * widest
        for m in ms {
            nebbiaEmitBlock(m, x + m.w / 2, y + rh - m.h / 2, &out)
            x += m.w + nebbiaFlowGap
        }
        y += rh + nebbiaStackGap
    }
    return NebbiaCompositionResult(items: out, vRot: 0)
}

/// 九种构图（COMPOSITIONS 对译；放不下返回 nil）。
private func nebbiaComposition(_ name: NebbiaLayout, blocks: [NebbiaBlock],
                               hero: Int, chars: [NebbiaSourceChar])
    -> NebbiaCompositionResult? {
    let n = blocks.count
    func m(_ i: Int, _ v: Bool) -> NebbiaMeasured {
        nebbiaMeasureBlock(blocks[i], chars: chars, vertical: v)
    }
    switch name {
    case .ribbon:
        return nebbiaFlowRows(blocks: blocks, chars: chars,
                              rows: [Array(0..<n)], shifts: [0])
    case .lines2:
        guard n >= 2 else { return nil }
        let ms = (0..<n).map { m($0, false) }
        let total = ms.reduce(0) { $0 + $1.w }
        var acc = 0.0, cut = 1, best = Double.infinity
        for (i, mm) in ms.enumerated() {
            acc += mm.w
            if i < n - 1 && abs(acc - total / 2) < best {
                best = abs(acc - total / 2); cut = i + 1
            }
        }
        return nebbiaFlowRows(blocks: blocks, chars: chars,
                              rows: [Array(0..<cut), Array(cut..<n)],
                              shifts: [-0.12, 0.12])
    case .lines3:
        guard n >= 3 else { return nil }
        let ms = (0..<n).map { m($0, false) }
        let total = ms.reduce(0) { $0 + $1.w }
        var rows: [[Int]] = [[]]
        var acc = 0.0
        for (i, mm) in ms.enumerated() {
            if !rows[rows.count - 1].isEmpty && rows.count < 3
                && (acc + mm.w / 2 > total / 3 * Double(rows.count)
                    || n - i <= 3 - rows.count) {
                rows.append([])
            }
            rows[rows.count - 1].append(i)
            acc += mm.w
        }
        guard rows.count == 3 else { return nil }
        return nebbiaFlowRows(blocks: blocks, chars: chars,
                              rows: rows, shifts: [-0.14, 0.1, -0.04])
    case .cross:
        let h = hero
        guard n >= 3, n <= 7 else { return nil }
        let top = h / 2
        let right = Int(ceil(Double(n - 1 - h) / 2))
        if top == 0 && h + right + 1 >= n { return nil }
        var out: [NebbiaPlacedItem] = []
        let hm = m(h, false)
        nebbiaEmitBlock(hm, 0, 0, &out)
        var vRot = 0
        // 左横排（主词左侧的块，自近及远）
        var x = -hm.w / 2 - nebbiaStackGap
        var i = h - 1
        while i >= top {
            let mm = m(i, false)
            nebbiaEmitBlock(mm, x - mm.w / 2, (hm.h - mm.h) / 2, &out)
            x -= mm.w + nebbiaFlowGap
            i -= 1
        }
        // 上竖列
        var y = -hm.h / 2 - nebbiaStackGap
        i = top - 1
        while i >= 0 {
            let mm = m(i, true)
            vRot += nebbiaHasTurned(mm)
            nebbiaEmitBlock(mm, 0, y - mm.h / 2, &out)
            y -= mm.h + nebbiaStackGap
            i -= 1
        }
        // 右横排
        x = hm.w / 2 + nebbiaStackGap
        i = h + 1
        while i <= h + right {
            let mm = m(i, false)
            nebbiaEmitBlock(mm, x + mm.w / 2, (hm.h - mm.h) / 2, &out)
            x += mm.w + nebbiaFlowGap
            i += 1
        }
        // 下竖列
        y = hm.h / 2 + nebbiaStackGap
        i = h + right + 1
        while i < n {
            let mm = m(i, true)
            vRot += nebbiaHasTurned(mm)
            nebbiaEmitBlock(mm, 0, y + mm.h / 2, &out)
            y += mm.h + nebbiaStackGap
            i += 1
        }
        return NebbiaCompositionResult(items: out, vRot: vRot)
    case .pillar:
        let h = hero
        guard n >= 2, n <= 6 else { return nil }
        var out: [NebbiaPlacedItem] = []
        let hm = m(h, true)
        var vRot = nebbiaHasTurned(hm)
        nebbiaEmitBlock(hm, 0, 0, &out)
        let topY = -hm.h / 2 + 0.15
        func side(_ from: Int, _ to: Int, _ dirX: Double) {
            var cols: [[NebbiaMeasured]] = [[]]
            var yy = topY
            var i = from
            while i != to {
                let mm = m(i, true)
                vRot += nebbiaHasTurned(mm)
                if yy + mm.h > hm.h / 2 + 0.6 && !cols[cols.count - 1].isEmpty {
                    cols.append([]); yy = topY
                }
                cols[cols.count - 1].append(mm)
                yy += mm.h + nebbiaStackGap
                i += 1
            }
            var colX = dirX * (hm.w / 2 + nebbiaFlowGap)
            for col in (dirX > 0 ? cols : Array(cols.reversed())) {
                yy = topY
                for mm in col {
                    nebbiaEmitBlock(mm, colX + dirX * mm.w / 2, yy + mm.h / 2, &out)
                    yy += mm.h + nebbiaStackGap
                }
                colX += dirX * ((col.map { $0.w }.max() ?? 0) + nebbiaFlowGap)
            }
        }
        side(0, h, -1)
        side(h + 1, n, 1)
        return NebbiaCompositionResult(items: out, vRot: vRot)
    case .header:
        let h = hero
        guard n >= 3, n - 1 - h >= 2 else { return nil }
        var out: [NebbiaPlacedItem] = []
        let hm = m(h, false)
        nebbiaEmitBlock(hm, 0, 0, &out)
        if h > 0 {
            let ms = (0..<h).map { m($0, false) }
            let rowW = ms.reduce(0) { $0 + $1.w } + nebbiaFlowGap * Double(h - 1)
            let rowH = ms.map { $0.h }.max() ?? 0
            var x = -rowW / 2
            let y = -hm.h / 2 - nebbiaStackGap - rowH / 2
            for mm in ms {
                nebbiaEmitBlock(mm, x + mm.w / 2, y + (rowH - mm.h) / 2, &out)
                x += mm.w + nebbiaFlowGap
            }
        }
        var y = hm.h / 2 + nebbiaStackGap
        let leftX = -hm.w * 0.22 - nebbiaFlowGap / 2
        let rightX = hm.w * 0.22 + nebbiaFlowGap / 2
        var i = h + 1
        while i < n {
            let a = m(i, false)
            let b = i + 1 < n ? m(i + 1, false) : nil
            let rh = max(a.h, b?.h ?? 0)
            nebbiaEmitBlock(a, leftX - a.w / 2, y + rh - a.h / 2, &out)
            if let b { nebbiaEmitBlock(b, rightX + b.w / 2, y + rh - b.h / 2, &out) }
            y += rh + nebbiaStackGap
            i += 2
        }
        return NebbiaCompositionResult(items: out, vRot: 0)
    case .badge:
        guard n >= 3, n <= 7, hero == 0 else { return nil }
        var out: [NebbiaPlacedItem] = []
        let hm = m(0, true)
        let ms = (1..<n).map { m($0, false) }
        let colW = max(ms.map { $0.w }.max() ?? 0, hm.h * 0.9)
        nebbiaEmitBlock(hm, hm.w / 2, hm.h / 2, &out)
        var x = hm.w + nebbiaFlowGap, y = 0.0, rowH = 0.0
        func leftEdge() -> Double { y < hm.h ? hm.w + nebbiaFlowGap : 0 }
        for mm in ms {
            if x > leftEdge() && x + mm.w > hm.w + nebbiaFlowGap + colW {
                y += rowH + nebbiaStackGap; x = leftEdge(); rowH = 0
            }
            nebbiaEmitBlock(mm, x + mm.w / 2, y + mm.h / 2, &out)
            x += mm.w + nebbiaFlowGap
            rowH = max(rowH, mm.h)
        }
        return NebbiaCompositionResult(items: out, vRot: nebbiaHasTurned(hm))
    case .columns:
        guard n >= 2, n <= 5 else { return nil }
        let anyLatin = blocks.contains { b in
            b.words.contains { w in w.idx.contains { !nebbiaIsCJK(chars[$0].webCh)
                && !nebbiaPunctSet.contains(chars[$0].webCh) && !chars[$0].isIcon } }
        }
        guard !anyLatin else { return nil }
        var out: [NebbiaPlacedItem] = []
        var x = 0.0
        for i in 0..<n {
            let mm = m(i, true)
            nebbiaEmitBlock(mm, x + mm.w / 2, mm.h / 2 + Double(i % 2) * 0.5, &out)
            x += mm.w + nebbiaStackGap
        }
        return NebbiaCompositionResult(items: out, vRot: 0)
    case .orbit:
        let h = hero
        guard n >= 4, n <= 7 else { return nil }
        var out: [NebbiaPlacedItem] = []
        let hm = m(h, false)
        nebbiaEmitBlock(hm, 0, 0, &out)
        struct Rect { var x0, x1, y0, y1: Double }
        var rects: [Rect] = [Rect(x0: -hm.w / 2, x1: hm.w / 2,
                                  y0: -hm.h / 2, y1: hm.h / 2)]
        func sep(_ a: Rect, _ b: Rect) -> Double {
            max(a.x0 - b.x1, b.x0 - a.x1, a.y0 - b.y1, b.y0 - a.y1)
        }
        var ang = -Double.pi * 0.75
        var vRot = 0
        let base = hypot(hm.w, hm.h) / 2 + nebbiaStackGap
        for i in 0..<n where i != h {
            var r = base, a = ang
            var rect: Rect? = nil
            var mm = m(i, false)
            var tries = 0
            while tries < 600 && rect == nil {
                mm = m(i, abs(cos(a)) > 0.75)
                let cx = cos(a) * r * 1.25, cy = sin(a) * r * 0.8
                let c = Rect(x0: cx - mm.w / 2, x1: cx + mm.w / 2,
                             y0: cy - mm.h / 2, y1: cy + mm.h / 2)
                if rects.allSatisfy({ sep($0, c) >= nebbiaFlowGap }) {
                    rect = c
                } else {
                    a += 0.08
                    if tries % 80 == 79 { r += 0.5 }
                }
                tries += 1
            }
            guard let placedRect = rect else { return nil }
            rects.append(placedRect)
            vRot += nebbiaHasTurned(mm)
            nebbiaEmitBlock(mm, (placedRect.x0 + placedRect.x1) / 2,
                            (placedRect.y0 + placedRect.y1) / 2, &out)
            ang = a + 0.5
        }
        return NebbiaCompositionResult(items: out, vRot: vRot)
    }
}

/// 构图偏好分（COMPOSITION_BIAS，越小越常用）。
private let nebbiaCompositionBias: [NebbiaLayout: Double] = [
    .ribbon: 12, .lines2: 10, .lines3: 14, .cross: 0, .pillar: 1,
    .header: 1, .badge: 4, .columns: 2, .orbit: 4,
]
private let nebbiaSimpleCompositions: Set<NebbiaLayout> = [.ribbon, .lines2, .lines3]

// MARK: - 排版结果与整首排版（nebbiaScene.ts / nebbiaLayout.ts 对译）

private struct NebbiaCharPlan {
    var text: String
    var isIcon: Bool
    var t: TimeInterval
    var d: TimeInterval
    var x: CGFloat = 0
    var y: CGFloat = 0
    var size: CGFloat = 0       // 字号 pt
    var rot: CGFloat = 0        // 弧度
    var writeStart: TimeInterval = 0
    var writeDur: TimeInterval = 0
    var appearDur: TimeInterval = 0
    var warpScaleX: CGFloat = 1
    var warpSkew: CGFloat = 0
    var warpScaleY: CGFloat = 1
    var beadRngSeed: UInt32 = 0
}

private struct NebbiaLinePlan {
    var index: Int
    var chars: [NebbiaCharPlan]
    var t: TimeInterval
    var end: TimeInterval
    var next: TimeInterval
    var fadeMode: NebbiaFadeStyle
    var fogAt: TimeInterval
    var fadeDur: TimeInterval
    var rect: CGRect = .zero
    var isCredits: Bool = false
    var appearBreath: Bool = false
    var breathStart: TimeInterval = .infinity
    var doneAt: TimeInterval = 0
}

/// 一句的消失方式（lineModeOf 对译：两种都开按种子随机）。
private func nebbiaLineMode(fade: [NebbiaFadeStyle], idx: Int,
                            seedHash: UInt32) -> NebbiaFadeStyle {
    if fade.count == 1 { return fade[0] }
    var rng = NebbiaRng(seed: seedHash &+ UInt32(bitPattern:
        Int32(truncatingIfNeeded: idx &* 977)) &+ 3)
    return rng.next() < 0.5 ? .fog : .fingers
}

/// 写完后开始起雾的时刻（fogStartOf 对译）。
private func nebbiaFogStart(end: TimeInterval, next: TimeInterval,
                            hold: Double) -> TimeInterval {
    min(next, end + 6) + hold
}

/// 整首排版：构图候选打分（layoutNebbiaSong 对译，省去
/// linger 多留权重——原生同屏存活行数以 3 为上限，旧行按
/// fogAt 排期起雾/让位，不做多留博弈，差异见报告）、
/// 出现排期（applyAppear 对译）、片尾居中（creditsCandidate
/// 对译）。字形笔顺数据缺失：naturalWriteTime 的 glyph.total
/// / 笔画数以同种子伪量代替（量级对齐 AnimCJK 常见区间
/// total 2.0–4.0、笔画 4–12），书写总时长口径不变。
private func nebbiaLayoutSong(source: [NebbiaSourceLine],
                              tuning: NebbiaTuningValues,
                              width W: Double, height H: Double,
                              fontScale: Double, seedHash: UInt32)
    -> [NebbiaLinePlan] {
    let mx = W * 0.05, my = H * 0.07
    let sMin = max(26, H * 0.065) * fontScale
    let sMax = H * 0.14 * fontScale
    // 消失时刻表（fogAt / goneAt 先行算出，排版避让要用）。
    let modes = source.enumerated().map {
        $0.element.credits > 0 ? NebbiaFadeStyle.fog
            : nebbiaLineMode(fade: tuning.fade, idx: $0.offset, seedHash: seedHash)
    }
    func fadeDur(_ i: Int) -> Double {
        tuning.refog + (modes[i] == .fog ? 0 : 2.5)
    }
    let creditsAt = source.first(where: { $0.credits > 0 })?.t ?? .infinity
    func fogAt(_ i: Int) -> TimeInterval {
        if source[i].credits > 0 { return .infinity }
        let base = nebbiaFogStart(end: source[i].end, next: source[i].next,
                                  hold: tuning.hold)
        let beforeCredits = max(source[i].end + 0.5, creditsAt - fadeDur(i) * 0.6)
        return min(base, beforeCredits)
    }
    func goneAt(_ i: Int) -> TimeInterval { fogAt(i) + fadeDur(i) }

    struct PlacedBox { var x0, x1, y0, y1: Double; var until, fog: TimeInterval }
    var placed: [PlacedBox] = []
    var recent: [NebbiaLayout] = []
    var prevCenter: (x: Double, y: Double)? = nil
    var titleBox: (x0: Double, x1: Double, y0: Double, y1: Double)? = nil

    func bbox(_ items: [NebbiaPlacedItem])
        -> (x0: Double, x1: Double, y0: Double, y1: Double, w: Double, h: Double) {
        var x0 = Double.infinity, x1 = -Double.infinity
        var y0 = Double.infinity, y1 = -Double.infinity
        for it in items {
            x0 = min(x0, it.x - it.s / 2); x1 = max(x1, it.x + it.s / 2)
            y0 = min(y0, it.y - it.s / 2); y1 = max(y1, it.y + it.s / 2)
        }
        return (x0, x1, y0, y1, x1 - x0, y1 - y0)
    }

    var plans: [NebbiaLinePlan] = []

    for (li, line) in source.enumerated() {
        let chars = line.chars
        var rng = NebbiaRng(seed: NebbiaRng.fnv1a(
            chars.map { $0.webCh }.joined()) &+ UInt32(bitPattern:
                Int32(truncatingIfNeeded: li &* 7919)))
        let visible = chars.filter {
            !$0.webCh.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let fast = !visible.isEmpty
            && (line.end - line.t) / Double(visible.count) < 0.22
        let words = line.words
        if words.isEmpty || chars.isEmpty {
            // 无词可排（网页 layoutNebbiaSong 的空词守卫等价）：
            // 占位空计划，位置居中。
            plans.append(NebbiaLinePlan(
                index: li, chars: [], t: line.t, end: line.end, next: line.next,
                fadeMode: modes[li], fogAt: fogAt(li), fadeDur: fadeDur(li),
                isCredits: line.credits > 0))
            placed.append(PlacedBox(x0: W / 2, x1: W / 2, y0: H / 2, y1: H / 2,
                                    until: goneAt(li), fog: fogAt(li)))
            continue
        }
        var chosen: (name: NebbiaLayout, items: [NebbiaPlacedItem],
                     bb: (x0: Double, x1: Double, y0: Double, y1: Double, w: Double, h: Double),
                     s: Double, cx: Double, cy: Double)? = nil

        if line.credits > 0 {
            // 片尾：曲名横排居中偏上（放不下两行），歌手其下。
            let blocks = nebbiaMakeBlocks(
                chars: chars, words: words,
                roles: words.map { _ in .support }, fast: false, maxBlocks: 9)
            let ctxHero = 0
            var res = line.credits == 2
                ? nebbiaComposition(.ribbon, blocks: blocks, hero: ctxHero, chars: chars)
                : nil
            if res == nil {
                let one = nebbiaComposition(.ribbon, blocks: blocks, hero: ctxHero, chars: chars)
                if let one {
                    let bb0 = bbox(one.items)
                    let fits = min(sMax * 1.15, (W - mx * 2) * 0.8 / bb0.w) >= sMin
                    res = (fits ? nil : nebbiaComposition(
                        .lines2, blocks: blocks, hero: ctxHero, chars: chars)) ?? one
                }
            }
            if let res {
                let bb = bbox(res.items)
                let cap = line.credits == 1 ? sMax * 1.15 : sMax * 0.55
                let s = min(cap, (W - mx * 2) * 0.8 / bb.w, H * 0.32 / bb.h)
                let bw = bb.w * s, bh = bb.h * s
                let cy = line.credits == 1 || titleBox == nil
                    ? H * 0.42
                    : titleBox!.y1 + bh / 2 + s * 0.6
                let box = (x0: W / 2 - bw / 2, x1: W / 2 + bw / 2,
                           y0: cy - bh / 2, y1: cy + bh / 2)
                if line.credits == 1 { titleBox = box }
                chosen = (.ribbon, res.items, bb, s, W / 2, cy)
            }
        }

        if chosen == nil {
            let roles = nebbiaAssignRoles(chars: chars, words: words)
            let busy: [(box: PlacedBox, w: Double)] = placed
                .filter { $0.until > line.t - 0.3 }
                .map { p in
                    let w = line.t <= p.fog ? 1
                        : 0.6 + 0.4 * nebbiaClamp(
                            (p.until - line.t) / max(0.001, p.until - p.fog), 0, 1)
                    return (p, w)
                }
            var bestScore = Double.infinity
            for maxBlocks in [5, 7] {
                let blocks = nebbiaMakeBlocks(
                    chars: chars, words: words, roles: roles,
                    fast: fast, maxBlocks: maxBlocks)
                let heroIdx = max(0, blocks.firstIndex(where: { $0.role == .hero }) ?? 0)
                for name in NebbiaLayout.allCases where tuning.layouts.contains(name) {
                    guard let res = nebbiaComposition(
                        name, blocks: blocks, hero: heroIdx, chars: chars),
                          !res.items.isEmpty else { continue }
                    let bb = bbox(res.items)
                    let maxH = H * (name == .ribbon ? 0.28 : 0.5)
                    let maxW = (W - mx * 2)
                        * (nebbiaSimpleCompositions.contains(name) ? 0.94 : 0.68)
                    let sFit = min(maxW / bb.w, maxH / bb.h, sMax)
                    if sFit < sMin * 0.75 { continue }
                    let sCandidates = [sFit, sFit * 0.8, sFit * 0.64, sFit * 0.5]
                        .enumerated().filter { $0.offset == 0 || $0.element >= sMin * 0.75 }
                        .map { $0.element }
                    for s in sCandidates {
                        let bw = bb.w * s, bh = bb.h * s
                        for fx in [0.5, 0.3, 0.7] {
                            for fy in [0.25, 0.42, 0.58, 0.75] {
                                let cx = nebbiaClamp(fx * W, mx + bw / 2, W - mx - bw / 2)
                                let cy = nebbiaClamp(fy * H, my + bh / 2, H - my - bh / 2)
                                let pad = s * 0.3
                                let padBox = (x0: cx - bw / 2 - pad, x1: cx + bw / 2 + pad,
                                              y0: cy - bh / 2 - pad, y1: cy + bh / 2 + pad)
                                var score = 0.0
                                for b in busy {
                                    let ow = max(0, min(padBox.x1, b.box.x1)
                                        - max(padBox.x0, b.box.x0))
                                    let oh = max(0, min(padBox.y1, b.box.y1)
                                        - max(padBox.y0, b.box.y0))
                                    score += ow * oh / (bw * bh) * 1000 * b.w
                                }
                                score -= s / H * 100
                                if s < sMin {
                                    score += 40 + (sMin - s) / sMin * 200
                                }
                                score += nebbiaCompositionBias[name] ?? 0
                                score += Double(res.vRot) * (fast ? 10 : 4)
                                if fast && !nebbiaSimpleCompositions.contains(name) {
                                    score += 6
                                }
                                if maxBlocks == 7 && blocks.count <= 5 {
                                    score += 100
                                }
                                if let rep = recent.lastIndex(of: name) {
                                    score += [18.0, 9.0, 4.0][recent.count - 1 - rep]
                                }
                                if let prev = prevCenter,
                                   abs(prev.x - cx) < W * 0.08,
                                   abs(prev.y - cy) < H * 0.08 {
                                    score += 8
                                }
                                score += abs(cy - H * 0.5) / H * 8
                                score += rng.next() * 8
                                if score < bestScore {
                                    bestScore = score
                                    chosen = (name, res.items, bb, s, cx, cy)
                                }
                            }
                        }
                    }
                }
            }
            if chosen == nil {
                // 实在放不下：三行兜底（网页同口径，不受 layouts 限制）。
                let blocks = nebbiaMakeBlocks(
                    chars: chars, words: words, roles: roles,
                    fast: true, maxBlocks: 9)
                let res = nebbiaComposition(.lines3, blocks: blocks, hero: 0, chars: chars)
                    ?? nebbiaComposition(.lines2, blocks: blocks, hero: 0, chars: chars)
                    ?? nebbiaComposition(.ribbon, blocks: blocks, hero: 0, chars: chars)
                if let res {
                    let bb = bbox(res.items)
                    let s = min(sMax, (W - mx * 2) / bb.w, (H - my * 2) / bb.h)
                    chosen = (.lines3, res.items, bb, s, W / 2, H / 2)
                }
            }
        }

        guard let pick = chosen else {
            // 无字可排（纯空白行）：给一个空计划占位。
            plans.append(NebbiaLinePlan(
                index: li, chars: [], t: line.t, end: line.end, next: line.next,
                fadeMode: modes[li], fogAt: fogAt(li), fadeDur: fadeDur(li),
                isCredits: line.credits > 0))
            placed.append(PlacedBox(x0: W / 2, x1: W / 2, y0: H / 2, y1: H / 2,
                                    until: goneAt(li), fog: fogAt(li)))
            continue
        }

        let box = (x0: pick.cx - pick.bb.w * pick.s / 2,
                   x1: pick.cx + pick.bb.w * pick.s / 2,
                   y0: pick.cy - pick.bb.h * pick.s / 2,
                   y1: pick.cy + pick.bb.h * pick.s / 2)
        placed.append(PlacedBox(x0: box.x0, x1: box.x1, y0: box.y0, y1: box.y1,
                                until: goneAt(li), fog: fogAt(li)))
        recent.append(pick.name)
        if recent.count > 3 { recent.removeFirst() }
        prevCenter = (pick.cx, pick.cy)

        // 落到屏幕坐标 + 手写歪斜（layoutNebbiaSong 尾段对译，
        // rng 取值序：tilt 一次，其后每字 s/x/y/rot 各一次）。
        let tilt = (rng.next() - 0.5) * 0.04 * tuning.jitter
        var byK: [Int: NebbiaPlacedItem] = [:]
        for it in pick.items { byK[it.k] = it }
        let bbCx = (pick.bb.x0 + pick.bb.x1) / 2
        let bbCy = (pick.bb.y0 + pick.bb.y1) / 2
        var charPlans: [NebbiaCharPlan] = []
        var lastX = pick.cx, lastY = pick.cy, lastS = pick.s
        for (ci, ch) in chars.enumerated() {
            var plan = NebbiaCharPlan(
                text: ch.text, isIcon: ch.isIcon, t: ch.t, d: ch.d,
                beadRngSeed: UInt32(bitPattern: Int32(truncatingIfNeeded:
                    li &* 131 &+ ci &* 17 &+ 5)))
            if let it = byK[ci] {
                let s = it.s * pick.s * (1 + (rng.next() - 0.5) * 0.08 * tuning.jitter)
                let x = pick.cx + (it.x - bbCx) * pick.s
                    + (rng.next() - 0.5) * pick.s * 0.04 * tuning.jitter
                let y = pick.cy + (it.y - bbCy) * pick.s
                    + (x - pick.cx) * tilt
                    + (rng.next() - 0.5) * pick.s * 0.05 * tuning.jitter
                plan.x = CGFloat(x); plan.y = CGFloat(y)
                plan.size = CGFloat(s)
                plan.rot = CGFloat(it.rot + (rng.next() - 0.5) * 0.08 * tuning.jitter + tilt)
                lastX = x; lastY = y; lastS = s
            } else {
                plan.x = CGFloat(lastX); plan.y = CGFloat(lastY)
                plan.size = CGFloat(lastS)
            }
            charPlans.append(plan)
        }

        // 手写变形（warpGlyph 的原生近似）：逐字从其装饰种子
        // rng 取斜切/胖瘦（网页按笔画点变形，原生以仿射代之）。
        for i in charPlans.indices where !charPlans[i].text
            .trimmingCharacters(in: .whitespaces).isEmpty {
            var wrng = NebbiaRng(seed: charPlans[i].beadRngSeed)
            _ = wrng.next()   // 与伪字形量共用流的占位（见下）
            _ = wrng.next()
            let w = tuning.warp
            charPlans[i].warpSkew = CGFloat((wrng.next() - 0.5) * 0.22 * w)
            charPlans[i].warpScaleX = CGFloat(1 + (wrng.next() - 0.5) * 0.16 * w)
            charPlans[i].warpScaleY = CGFloat(1 + (wrng.next() - 0.5) * 0.12 * w)
        }

        var plan = NebbiaLinePlan(
            index: li, chars: charPlans, t: line.t, end: line.end,
            next: line.next, fadeMode: modes[li], fogAt: fogAt(li),
            fadeDur: fadeDur(li),
            rect: CGRect(x: CGFloat(box.x0), y: CGFloat(box.y0),
                         width: CGFloat(box.x1 - box.x0),
                         height: CGFloat(box.y1 - box.y0)),
            isCredits: line.credits > 0)
        nebbiaApplyAppear(&plan, tuning: tuning, idx: li, seedHash: seedHash)
        plans.append(plan)
    }
    // 片尾歌手等曲名写完（alignCredits 对译）：歌手行整体后
    // 移到曲名末字写完 + 0.4s。
    let titleIdx = source.firstIndex(where: { $0.credits == 1 })
    let artistIdx = source.firstIndex(where: { $0.credits == 2 })
    if let ti = titleIdx, let ai = artistIdx,
       plans.indices.contains(ti), plans.indices.contains(ai) {
        let written = plans[ti].chars.filter {
            !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if let last = written.last {
            let firstWt = plans[ai].chars.first?.writeStart ?? 0
            let shift = max(0, last.writeStart + last.writeDur + 0.4 - firstWt)
            if shift > 0 {
                for i in plans[ai].chars.indices {
                    plans[ai].chars[i].writeStart += shift
                }
            }
        }
    }
    return plans
}

/// 一句的出现排期（applyAppear 对译）：书写两式按种子挑一；
/// 慢慢显现也开着时，压到 0.3 倍都写不完的句子改显现；只开
/// 显现就句句显现。自然书写时长以伪字形量代真笔顺（见
/// nebbiaLayoutSong 头注），公式 = (total×0.28 + (笔数−1)
/// ×0.06) / writeSpeed 与网页逐字一致。
private func nebbiaApplyAppear(_ plan: inout NebbiaLinePlan,
                               tuning: NebbiaTuningValues,
                               idx: Int, seedHash: UInt32) {
    let kinds = tuning.appear.filter { $0 != .fade }
    let canFade = tuning.appear.contains(.fade)
    var kind: NebbiaAppearStyle? = nil
    if !kinds.isEmpty {
        var rng = NebbiaRng(seed: seedHash &+ UInt32(bitPattern:
            Int32(truncatingIfNeeded: idx &* 613)) &+ 11)
        kind = kinds[min(Int(rng.next() * Double(kinds.count)), kinds.count - 1)]
    }
    let glyphIdx = plan.chars.indices.filter {
        !plan.chars[$0].text.trimmingCharacters(in: .whitespaces).isEmpty
    }
    guard !glyphIdx.isEmpty else {
        plan.doneAt = plan.end
        return
    }
    var nat: [Double] = []
    for ci in glyphIdx {
        var grng = NebbiaRng(seed: plan.chars[ci].beadRngSeed)
        let total = 2.0 + grng.next() * 2.0
        let strokes = 4 + grng.next() * 9
        nat.append((total * 0.28 + (strokes - 1) * 0.06)
            / max(tuning.writeSpeed, 0.01))
    }
    let until = plan.isCredits ? Double.infinity
        : max(plan.next.isFinite ? plan.next : plan.end, plan.end)
    func schedule(_ k: Double) -> (starts: [Double], end: Double) {
        var end = -Double.infinity
        var starts: [Double] = []
        for (j, ci) in glyphIdx.enumerated() {
            let t0 = max(plan.chars[ci].t, end)
            starts.append(t0)
            end = t0 + nat[j] * k
        }
        return (starts, end)
    }
    var k = 1.0
    if schedule(1).end > until {
        var lo = 0.3, hi = 1.0
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            if schedule(mid).end > until { hi = mid } else { lo = mid }
        }
        k = lo
    }
    let scheduled = schedule(k)
    let fade = kind == nil || (canFade && scheduled.end > until + 0.001)
    for (j, ci) in glyphIdx.enumerated() {
        plan.chars[ci].writeStart = scheduled.starts[j]
        plan.chars[ci].writeDur = nat[j] * k
        plan.chars[ci].appearDur = fade
            ? nebbiaClamp(plan.chars[ci].d * 3, 0.35, 1.2) : 0
    }
    if kind == .breath && !fade {
        plan.appearBreath = true
        plan.breathStart = scheduled.starts[0] - 1.2 - 0.3
    }
    var done = plan.end
    for ci in glyphIdx {
        let c = plan.chars[ci]
        done = max(done, c.appearDur > 0
            ? c.t + c.appearDur : c.writeStart + c.writeDur)
    }
    plan.doneAt = done
}

// MARK: - 离屏烘焙（场景 / 雾 / 凝露 / 羽化 / 水母）
//
// 全部在后台队列出图、主线程贴入；参数键不变不重烘。绘制用
// UIGraphics（CPU 光栅）但只在切歌/换色/旋转/改参时发生，
// 逐帧路径零光栅。分辨率钳制见文件头。

/// 出图尺寸：points 尺寸 × 每点像素数，像素长边钳到 cap。
private func nebbiaBakeSize(points: CGSize, cap: CGFloat)
    -> (size: CGSize, scale: CGFloat) {
    let longPt = max(points.width, points.height)
    guard longPt > 0 else { return (points, 1) }
    let pxPerPt = min(3, cap / longPt)
    return (CGSize(width: points.width * pxPerPt,
                   height: points.height * pxPerPt), pxPerPt)
}

private func nebbiaRenderer(size: CGSize, opaque: Bool) -> UIGraphicsImageRenderer {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = opaque
    return UIGraphicsImageRenderer(size: size, format: format)
}

/// 窗外场景烘焙：night = 雨夜街景（天色渐变 + 楼群剪影/亮窗
/// + 霓虹光斑 + 湿路面倒影 + 车灯，按 scenery 开关逐项）；
/// aquarium = 梦海流萤底（深水渐变 + 光柱 + 沙底 + 海草，
/// 水母/气泡是独立视图层不在此图）；backdrop 不出图（nil）。
/// 画布宽 = bounds 宽 × 1.25（车速漂移余量）。
private func nebbiaBakeScene(points: CGSize, palette: NebbiaPalette,
                             tokens: PaletteTokens, tuning: NebbiaTuningValues,
                             cap: CGFloat) -> UIImage? {
    guard tuning.behind != .backdrop else { return nil }
    let (size, _) = nebbiaBakeSize(points: points, cap: cap)
    guard size.width >= 8, size.height >= 8 else { return nil }
    let sx = size.width / points.width
    let sy = size.height / points.height
    var rng = NebbiaRng(seed: 0x9E37_79B9)
    let renderer = nebbiaRenderer(size: size, opaque: true)
    return renderer.image { ctx in
        let cg = ctx.cgContext
        let rect = CGRect(origin: .zero, size: size)
        if tuning.behind == .aquarium {
            // 深水渐变（上浅下深，混一点灯光色）。
            let top = nebbiaFromHSL((0.52, 0.55, 0.16))
            let bottom = nebbiaFromHSL((0.58, 0.6, 0.05))
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [top.cgColor, bottom.cgColor] as CFArray,
                                  locations: [0, 1])!
            cg.drawLinearGradient(grad, start: .zero,
                                  end: CGPoint(x: 0, y: size.height), options: [])
            // 水面光柱：四条斜向半透明白多边形。
            cg.setFillColor(UIColor.white.withAlphaComponent(0.05).cgColor)
            for i in 0..<4 {
                let x0 = size.width * (0.12 + 0.22 * CGFloat(i))
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x0, y: 0))
                path.addLine(to: CGPoint(x: x0 + 26 * sx, y: 0))
                path.addLine(to: CGPoint(x: x0 - 60 * sx, y: size.height * 0.7))
                path.addLine(to: CGPoint(x: x0 - 110 * sx, y: size.height * 0.7))
                path.closeSubpath()
                cg.addPath(path)
                cg.fillPath()
            }
            // 光晕（灯光色，弱）。
            for color in [palette.la, palette.lb] {
                let cx = size.width * CGFloat(0.25 + rng.next() * 0.5)
                let cy = size.height * CGFloat(0.2 + rng.next() * 0.3)
                let r = CGFloat(60 + rng.next() * 90) * sx
                let g2 = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [color.withAlphaComponent(0.13).cgColor,
                                             color.withAlphaComponent(0).cgColor] as CFArray,
                                    locations: [0, 1])!
                cg.drawRadialGradient(g2, startCenter: CGPoint(x: cx, y: cy),
                                      startRadius: 0, endCenter: CGPoint(x: cx, y: cy),
                                      endRadius: r, options: [])
            }
            // 沙底。
            cg.setFillColor(UIColor(red: 0.16, green: 0.14, blue: 0.08, alpha: 1).cgColor)
            let sand = CGMutablePath()
            sand.move(to: CGPoint(x: 0, y: size.height * 0.93))
            for i in 0...8 {
                sand.addLine(to: CGPoint(
                    x: size.width * CGFloat(i) / 8,
                    y: size.height * (0.93 + CGFloat(rng.next()) * 0.02)))
            }
            sand.addLine(to: CGPoint(x: size.width, y: size.height))
            sand.addLine(to: CGPoint(x: 0, y: size.height))
            sand.closeSubpath()
            cg.addPath(sand)
            cg.fillPath()
            // 海草：底部竖起的波浪带（填充路径）。
            cg.setFillColor(UIColor(red: 0.05, green: 0.25, blue: 0.12, alpha: 0.8).cgColor)
            for _ in 0..<9 {
                let bx = CGFloat(rng.next()) * size.width
                let bh = CGFloat(50 + rng.next() * 130) * sy
                let bw = CGFloat(5 + rng.next() * 6) * sx
                let weed = CGMutablePath()
                weed.move(to: CGPoint(x: bx - bw / 2, y: size.height))
                weed.addQuadCurve(to: CGPoint(x: bx + bw, y: size.height - bh),
                                  control: CGPoint(x: bx + bw * 1.6,
                                                   y: size.height - bh * 0.5))
                weed.addQuadCurve(to: CGPoint(x: bx + bw / 2, y: size.height),
                                  control: CGPoint(x: bx - bw,
                                                   y: size.height - bh * 0.5))
                weed.closeSubpath()
                cg.addPath(weed)
                cg.fillPath()
            }
            return
        }
        // ── night 雨夜街景 ──
        let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [palette.sky0.cgColor, palette.sky1.cgColor] as CFArray,
                             locations: [0, 1])!
        cg.drawLinearGradient(sky, start: .zero,
                              end: CGPoint(x: 0, y: size.height), options: [])
        let horizon = size.height * 0.62
        // 霓虹光斑（scenery.lights，亮度 × neon）。
        var blobCenters: [(x: CGFloat, y: CGFloat, color: UIColor)] = []
        if tuning.scenery.contains(.lights) {
            let colors = [palette.la, palette.lb, palette.lc]
            for i in 0..<7 {
                let color = colors[i % colors.count]
                let cx = size.width * CGFloat(0.06 + rng.next() * 0.88)
                let cy = horizon + size.height * CGFloat(rng.next() * 0.2)
                let r = CGFloat(40 + rng.next() * 95) * sx
                let alpha = CGFloat(0.34 * min(tuning.neon, 2) / 2 + 0.08)
                let g2 = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [color.withAlphaComponent(alpha).cgColor,
                                             color.withAlphaComponent(0).cgColor] as CFArray,
                                    locations: [0, 1])!
                cg.drawRadialGradient(g2, startCenter: CGPoint(x: cx, y: cy),
                                      startRadius: 0, endCenter: CGPoint(x: cx, y: cy),
                                      endRadius: r, options: [])
                blobCenters.append((cx, cy, color))
            }
        }
        // 楼群剪影 + 亮窗（scenery.buildings）。
        if tuning.scenery.contains(.buildings) {
            cg.setFillColor(palette.sky0.withAlphaComponent(0.88).cgColor)
            var bx: CGFloat = -10
            while bx < size.width + 10 {
                let bw = CGFloat(26 + rng.next() * 70) * sx
                let bh = size.height * CGFloat(0.16 + rng.next() * 0.3)
                let bRect = CGRect(x: bx, y: size.height * 0.97 - bh,
                                   width: bw, height: bh)
                cg.fill(bRect)
                // 亮窗：少量暖/冷小点。
                let windows = Int(rng.next() * 9)
                for _ in 0..<windows {
                    let wx = bx + CGFloat(rng.next()) * max(bw - 4 * sx, 1)
                    let wy = bRect.minY + CGFloat(rng.next()) * max(bh - 5 * sy, 1)
                    cg.setFillColor((rng.next() > 0.4
                        ? palette.la : UIColor.white)
                        .withAlphaComponent(CGFloat(0.1 + rng.next() * 0.3)).cgColor)
                    cg.fill(CGRect(x: wx, y: wy, width: 2.2 * sx, height: 3 * sy))
                }
                cg.setFillColor(palette.sky0.withAlphaComponent(0.88).cgColor)
                bx += bw + CGFloat(2 + rng.next() * 14) * sx
            }
        }
        // 湿路面（scenery.road）：底部暗带 + 光斑倒影竖纹。
        if tuning.scenery.contains(.road) {
            let roadY = size.height * 0.88
            cg.setFillColor(UIColor.black.withAlphaComponent(0.32).cgColor)
            cg.fill(CGRect(x: 0, y: roadY, width: size.width,
                           height: size.height - roadY))
            for blob in blobCenters {
                let streakW = CGFloat(5 + rng.next() * 12) * sx
                let g3 = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [blob.color.withAlphaComponent(0.16).cgColor,
                                             blob.color.withAlphaComponent(0).cgColor] as CFArray,
                                    locations: [0, 1])!
                let from = CGPoint(x: blob.x, y: roadY)
                cg.saveGState()
                cg.beginPath()
                cg.addRect(CGRect(x: blob.x - streakW / 2, y: roadY,
                                  width: streakW, height: size.height - roadY))
                cg.clip()
                cg.drawLinearGradient(g3, start: from,
                                      end: CGPoint(x: blob.x, y: size.height),
                                      options: [])
                cg.restoreGState()
            }
            // 车灯（scenery.cars）：成对亮点 + 光晕 + 红尾灯。
            if tuning.scenery.contains(.cars) {
                for _ in 0..<5 {
                    let cx = size.width * CGFloat(0.08 + rng.next() * 0.84)
                    let cy = roadY + (size.height - roadY) * CGFloat(0.25 + rng.next() * 0.6)
                    let spread = CGFloat(7 + rng.next() * 9) * sx
                    let warm = UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 1)
                    for dx in [-spread, spread] {
                        let g4 = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: [warm.withAlphaComponent(0.5).cgColor,
                                                     warm.withAlphaComponent(0).cgColor] as CFArray,
                                            locations: [0, 1])!
                        cg.drawRadialGradient(g4, startCenter: CGPoint(x: cx + dx, y: cy),
                                              startRadius: 0,
                                              endCenter: CGPoint(x: cx + dx, y: cy),
                                              endRadius: 9 * sx, options: [])
                        cg.setFillColor(warm.withAlphaComponent(0.9).cgColor)
                        cg.fillEllipse(in: CGRect(x: cx + dx - 1.6 * sx, y: cy - 1.6 * sy,
                                                  width: 3.2 * sx, height: 3.2 * sy))
                    }
                    cg.setFillColor(UIColor.red.withAlphaComponent(0.55).cgColor)
                    cg.fillEllipse(in: CGRect(x: cx - spread * 2.4, y: cy - 1.2 * sy,
                                              width: 2.4 * sx, height: 2.4 * sy))
                }
            }
        }
        _ = rect
    }
}

/// 雾纹理烘焙（1/4 缩，网页 FOG_DIV=4；两变体种子不同，叠加
/// 漂移出层次）：基色 + 数百团低透明软斑（低分出图 + 放大线
/// 性采样即软边，不用任何模糊滤镜）。
private func nebbiaBakeFog(points: CGSize, palette: NebbiaPalette,
                           tokens: PaletteTokens, behind: NebbiaBehind,
                           variant: Int, cap: CGFloat) -> UIImage? {
    let quarter = CGSize(width: points.width / 4, height: points.height / 4)
    let (size, _) = nebbiaBakeSize(points: quarter, cap: cap)
    guard size.width >= 8, size.height >= 8 else { return nil }
    var rng = NebbiaRng(seed: variant == 0 ? 0x51F7 : 0xA31C)
    let base: UIColor
    if behind == .backdrop {
        // 网页 seeThrough 的雾色：日间乳白 / 夜间深色（mistTint）。
        base = tokens.isDark
            ? UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
            : UIColor(red: 0.86, green: 0.89, blue: 0.92, alpha: 1)
    } else {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        palette.sky1.getRed(&r, green: &g, blue: &b, alpha: &a)
        base = UIColor(red: r + (1 - r) * 0.42, green: g + (1 - g) * 0.42,
                       blue: b + (1 - b) * 0.45, alpha: 1)
    }
    let renderer = nebbiaRenderer(size: size, opaque: true)
    return renderer.image { ctx in
        let cg = ctx.cgContext
        cg.setFillColor(base.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        for _ in 0..<460 {
            let cx = CGFloat(rng.next()) * size.width
            let cy = CGFloat(rng.next()) * size.height
            let r = CGFloat(6 + rng.next() * 30)
            let light = rng.next() > 0.42
            let color = light
                ? UIColor.white.withAlphaComponent(CGFloat(0.03 + rng.next() * 0.09))
                : UIColor.black.withAlphaComponent(CGFloat(0.02 + rng.next() * 0.06))
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [color.cgColor,
                                        color.withAlphaComponent(0).cgColor] as CFArray,
                               locations: [0, 1])!
            cg.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy),
                                  startRadius: 0, endCenter: CGPoint(x: cx, y: cy),
                                  endRadius: r, options: [])
        }
    }
}

/// 凝露层烘焙（玻璃 = dew）：透明底 + 细密冷凝水珠 + 高光点。
private func nebbiaBakeDew(points: CGSize, tuning: NebbiaTuningValues,
                           cap: CGFloat) -> UIImage? {
    let half = CGSize(width: points.width / 2, height: points.height / 2)
    let (size, _) = nebbiaBakeSize(points: half, cap: cap)
    guard size.width >= 8, size.height >= 8 else { return nil }
    var rng = NebbiaRng(seed: 0xDE17)
    let renderer = nebbiaRenderer(size: size, opaque: false)
    let count = Int(260 * tuning.dew)
    return renderer.image { ctx in
        let cg = ctx.cgContext
        for _ in 0..<count {
            let cx = CGFloat(rng.next()) * size.width
            let cy = CGFloat(rng.next()) * size.height
            let r = CGFloat(0.8 + rng.next() * 2.2) * CGFloat(tuning.dewSize)
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [UIColor.white.withAlphaComponent(0.26).cgColor,
                                        UIColor.white.withAlphaComponent(0.04).cgColor] as CFArray,
                               locations: [0, 1])!
            cg.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy),
                                  startRadius: 0, endCenter: CGPoint(x: cx, y: cy),
                                  endRadius: r, options: [])
            if rng.next() < 0.22 * tuning.dewGlint {
                cg.setFillColor(UIColor.white.withAlphaComponent(
                    CGFloat(0.5 * min(tuning.dewGlint, 1.5))).cgColor)
                cg.fillEllipse(in: CGRect(x: cx - r * 0.3, y: cy - r * 0.35,
                                          width: r * 0.5, height: r * 0.5))
            }
        }
    }
}

/// 羽化遮罩烘焙（擦出贴片的软边）：透明底上多层内缩圆角矩
/// 形叠加，alpha 向中心累积——不用模糊滤镜。
private func nebbiaBakeFeather() -> UIImage? {
    let size = CGSize(width: 160, height: 112)
    let renderer = nebbiaRenderer(size: size, opaque: false)
    return renderer.image { ctx in
        let cg = ctx.cgContext
        let steps = 16
        for i in 0..<steps {
            let inset = CGFloat(i) / CGFloat(steps) * 34
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset * 0.7)
            let path = CGPath(roundedRect: rect,
                              cornerWidth: 26, cornerHeight: 26, transform: nil)
            cg.addPath(path)
            cg.setFillColor(UIColor.white.withAlphaComponent(0.14).cgColor)
            cg.fillPath()
        }
    }
}

/// 水母剪影烘焙（伞盖 + 触手线），按灯光色出图。
private func nebbiaBakeJelly(color: UIColor) -> UIImage? {
    let size = CGSize(width: 120, height: 150)
    let renderer = nebbiaRenderer(size: size, opaque: false)
    return renderer.image { ctx in
        let cg = ctx.cgContext
        // 伞盖：半圆穹 + 波浪下缘。
        let dome = CGMutablePath()
        dome.move(to: CGPoint(x: 14, y: 62))
        dome.addArc(center: CGPoint(x: 60, y: 62), radius: 46,
                    startAngle: .pi, endAngle: 0, clockwise: false)
        for i in 0..<5 {
            let x = 106 - CGFloat(i) * 18.4
            dome.addQuadCurve(to: CGPoint(x: x - 18.4, y: 62),
                              control: CGPoint(x: x - 9.2, y: 74))
        }
        dome.closeSubpath()
        cg.addPath(dome)
        cg.setFillColor(color.withAlphaComponent(0.5).cgColor)
        cg.fillPath()
        cg.addPath(dome)
        cg.setFillColor(color.withAlphaComponent(0.22).cgColor)
        cg.fillPath()
        // 内腔高光。
        cg.setFillColor(UIColor.white.withAlphaComponent(0.20).cgColor)
        cg.fillEllipse(in: CGRect(x: 38, y: 30, width: 44, height: 30))
        // 触手：五条波浪线。
        cg.setStrokeColor(color.withAlphaComponent(0.5).cgColor)
        cg.setLineWidth(3)
        cg.setLineCap(.round)
        for i in 0..<5 {
            let x = 24 + CGFloat(i) * 18
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: 64))
            path.addQuadCurve(to: CGPoint(x: x - 4, y: 108),
                              control: CGPoint(x: x + 7, y: 86))
            path.addQuadCurve(to: CGPoint(x: x + 2, y: 142),
                              control: CGPoint(x: x - 8, y: 126))
            cg.addPath(path)
            cg.strokePath()
        }
    }
}

// MARK: - 一句的视图（擦出贴片 + 逐字标签 + 哈气 + 抹除）

/// 一句在屏上的全部视图。frame = 计划 rect；内部坐标以 rect
/// 左上为原点。每帧由渲染器以 update(position:sceneFrame:
/// sceneImage:) 推进：逐字揭示（书写 = 遮罩横向擦出 + 贴片
/// 淡入；显现 = 整体淡入，appearDur 口径）、哈气、起雾 /
/// 手指抹除、水珠装饰。全部是图层属性赋值，无光栅化。
private final class NebbiaLineView: UIView {

    let plan: NebbiaLinePlan
    private var labels: [UILabel] = []
    private var patchLayers: [CALayer] = []
    private var clipMasks: [CALayer?] = []
    private let breathView: UIView
    private let breathGradient = CAGradientLayer()
    private let smearA = UIView()
    private let smearB = UIView()
    private let beadsView = UIView()
    private var completed: Set<Int> = []
    private let strokeFactor: CGFloat

    init(plan: NebbiaLinePlan, palette: PaletteTokens,
         strokeWidth: Double, feather: UIImage?) {
        self.plan = plan
        self.strokeFactor = CGFloat(min(max(strokeWidth / 0.09, 0.6), 1.6))
        var labels: [UILabel] = []
        var patches: [CALayer] = []
        var masks: [CALayer?] = []
        breathView = UIView()
        super.init(frame: plan.rect)
        isUserInteractionEnabled = false
        // 哈气白气（breath 出现式 / 让位哈气的呈现层）：径向
        // 白渐变，初始隐藏，update 里按时刻推进。
        breathView.isUserInteractionEnabled = false
        breathView.alpha = 0
        breathGradient.type = .radial
        breathGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        breathGradient.endPoint = CGPoint(x: 1, y: 0.5)
        breathGradient.colors = [
            UIColor.white.withAlphaComponent(0.55).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
        ]
        breathView.layer.addSublayer(breathGradient)
        breathView.frame = bounds.insetBy(dx: -bounds.width * 0.12,
                                          dy: -bounds.height * 0.3)
        breathGradient.frame = breathView.bounds
        addSubview(breathView)
        // 擦出贴片专用层容器（在字形标签之下成组，避免逐字
        // 交错添加时后字的贴片压住先字的标签）。
        let patchesView = UIView(frame: bounds)
        patchesView.isUserInteractionEnabled = false
        addSubview(patchesView)

        let textColor = palette.text
        for char in plan.chars {
            // 擦出贴片：窗外场景的对应区域，羽化边；随字揭示。
            let patch = CALayer()
            let pw = max(char.size * 0.9, 10) * strokeFactor
            let ph = char.size * 1.3
            patch.frame = CGRect(x: char.x - plan.rect.minX - pw / 2,
                                 y: char.y - plan.rect.minY - ph / 2,
                                 width: pw, height: ph)
            patch.opacity = 0
            if let feather, let cg = feather.cgImage {
                let mask = CALayer()
                mask.contents = cg
                mask.frame = CGRect(origin: .zero, size: patch.frame.size)
                patch.mask = mask
            }
            patchesView.layer.addSublayer(patch)
            patches.append(patch)

            let label = UILabel()
            label.text = char.text
            label.font = StageFonts.bold(size: char.size)
            label.textColor = textColor
            label.textAlignment = .center
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.45
            label.layer.shadowRadius = 3
            label.layer.shadowOffset = CGSize(width: 0, height: 1)
            label.sizeToFit()
            let w = max(label.bounds.width, char.size * 0.4)
            let h = max(label.bounds.height, char.size * 1.1)
            label.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            label.center = CGPoint(x: char.x - plan.rect.minX,
                                   y: char.y - plan.rect.minY)
            var t = CGAffineTransform(rotationAngle: char.rot)
            t = t.scaledBy(x: char.warpScaleX, y: char.warpScaleY)
            let shear = CGAffineTransform(a: 1, b: 0, c: char.warpSkew,
                                          d: 1, tx: 0, ty: 0)
            label.transform = shear.concatenating(t)
            label.alpha = 0
            // 书写式：逐字遮罩（黑块宽度随揭示进度），图层属
            // 性赋值推进；显现式不用遮罩、走 alpha。
            if char.appearDur <= 0 && !char.isIcon {
                let mask = CALayer()
                mask.backgroundColor = UIColor.black.cgColor
                mask.frame = CGRect(x: 0, y: -h * 0.2, width: 0, height: h * 1.4)
                label.layer.mask = mask
                masks.append(mask)
            } else {
                masks.append(nil)
            }
            addSubview(label)
            labels.append(label)
        }
        self.labels = labels
        self.patchLayers = patches
        self.clipMasks = masks

        beadsView.isUserInteractionEnabled = false
        addSubview(beadsView)
        for smear in [smearA, smearB] {
            smear.isUserInteractionEnabled = false
            smear.backgroundColor = UIColor.white.withAlphaComponent(0.16)
            smear.layer.cornerRadius = 15
            smear.bounds = CGRect(x: 0, y: 0, width: 30,
                                  height: max(bounds.height * 0.5, 34))
            smear.alpha = 0
            addSubview(smear)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    /// 逐字揭示进度：书写按 writeStart/writeDur，显现按
    /// t/appearDur（与 nebbiaScene 的 startOf/doneOf 同义）。
    private func reveal(_ char: NebbiaCharPlan, at position: TimeInterval) -> Double {
        if char.appearDur > 0 {
            return nebbiaClamp((position - char.t) / char.appearDur, 0, 1)
        }
        return nebbiaClamp((position - char.writeStart)
            / max(char.writeDur, 0.01), 0, 1)
    }

    /// 本帧推进。sceneFrame/sceneImage 给擦出贴片对齐窗外
    /// （场景漂移时 contentsRect 随之修正）；返回 false 表示
    /// 本句已完全消失、渲染器可回收。
    func update(position: TimeInterval, sceneFrame: CGRect,
                sceneImage: UIImage?) -> Bool {
        let plan = self.plan
        if position < plan.t - 0.05 && !plan.isCredits { return true }
        // 整句不透明度：fog 式起雾（fogAt 起、fadeDur 内平滑
        // 吞没，yieldFactor 的平滑曲线同族）；片尾不起雾。
        var lineAlpha: CGFloat = 1
        if plan.fadeMode == .fog && !plan.isCredits
            && position > plan.fogAt {
            lineAlpha = CGFloat(1 - nebbiaSmooth(
                (position - plan.fogAt) / max(plan.fadeDur, 0.01)))
        }
        // fingers 式抹除进度。
        var smearQ = 0.0
        if plan.fadeMode == .fingers && !plan.isCredits
            && position > plan.fogAt {
            smearQ = nebbiaClamp((position - plan.fogAt)
                / max(plan.fadeDur, 0.01), 0, 1)
        }
        let w = bounds.width
        // 两根手指的往返前锋（fadeDur 内去回各一趟）。
        let frontTravel = smearQ * 2 * Double(w)
        if smearQ > 0 && smearQ < 1 {
            let phase = smearQ * 2
            let fx = phase <= 1 ? phase : 2 - phase
            for (i, smear) in [smearA, smearB].enumerated() {
                smear.center = CGPoint(
                    x: CGFloat(fx) * w,
                    y: bounds.height * (i == 0 ? 0.36 : 0.64))
                smear.alpha = 0.8
            }
        } else {
            smearA.alpha = 0
            smearB.alpha = 0
        }
        // 哈气（出现式）：写前 1.5s 鼓开（breathSpread 1.2 +
        // 0.3 提前量），唱完 + breathHold 1s 后用 breathFade
        // 8s 散掉（NEBBIA_FIXED 常量）。
        if plan.appearBreath {
            var a: CGFloat = 0
            if position >= plan.breathStart {
                let spread = nebbiaClamp((position - plan.breathStart) / 1.2, 0, 1)
                a = CGFloat(spread) * 0.5
                if position > plan.end + 1 {
                    a *= CGFloat(1 - nebbiaClamp(
                        (position - plan.end - 1) / 8, 0, 1))
                }
                breathView.transform = CGAffineTransform(
                    scaleX: CGFloat(0.7 + 0.3 * spread),
                    y: CGFloat(0.7 + 0.3 * spread))
            }
            breathView.alpha = a
        }
        for (i, char) in plan.chars.enumerated() {
            let label = labels[i]
            let patch = patchLayers[i]
            let isBlank = char.text.trimmingCharacters(
                in: .whitespaces).isEmpty
            if isBlank {
                label.alpha = 0
                patch.opacity = 0
                continue
            }
            let p = reveal(char, at: position)
            // 抹除：前锋扫过的字先没（去程按 x、回程按镜像 x）。
            var erase = 0.0
            if smearQ > 0 {
                let cx = Double(char.x - plan.rect.minX)
                let e1 = nebbiaClamp((min(frontTravel, Double(w)) - cx) / 50 + 0.5, 0, 1)
                let e2 = frontTravel > Double(w)
                    ? nebbiaClamp((frontTravel - Double(w)
                        - (Double(w) - cx)) / 50 + 0.5, 0, 1) : 0
                erase = max(e1, e2)
            }
            let vis = CGFloat(p) * lineAlpha * CGFloat(1 - erase)
            if char.appearDur > 0 || char.isIcon {
                label.alpha = vis
            } else {
                label.alpha = lineAlpha * CGFloat(1 - erase)
                if let mask = clipMasks[i] {
                    let full = label.bounds.width
                    mask.frame = CGRect(x: 0, y: -label.bounds.height * 0.2,
                                        width: full * CGFloat(p),
                                        height: label.bounds.height * 1.4)
                }
            }
            // 贴片对齐窗外场景：contentsRect 按场景图在根坐
            // 标的当前帧（漂移后）换算。
            if let sceneImage, let cg = sceneImage.cgImage,
               sceneFrame.width > 0, sceneFrame.height > 0 {
                patch.contents = cg
                let rootX = plan.rect.minX + patch.frame.minX
                let rootY = plan.rect.minY + patch.frame.minY
                patch.contentsRect = CGRect(
                    x: (rootX - sceneFrame.minX) / sceneFrame.width,
                    y: (rootY - sceneFrame.minY) / sceneFrame.height,
                    width: patch.frame.width / sceneFrame.width,
                    height: patch.frame.height / sceneFrame.height)
                patch.opacity = Float(vis) * 0.96
            } else {
                patch.opacity = 0
            }
            if p >= 1 && !completed.contains(i) {
                completed.insert(i)
                spawnBeads(for: char)
            }
        }
        if plan.isCredits { return true }
        return position <= plan.fogAt + plan.fadeDur + 0.05
    }

    /// 写完一个字后的水珠装饰（nebbiaScene.decorate 的呈现
    /// 近似）：擦痕边小水珠（概率 = NEBBIA_FIXED.beads 0.35）、
    /// 收笔大水珠（字号 ≥ endBeadMin 48）、偶发下淌（drip
    /// 0.25 × 0.22）。随机流与排版共用该字的装饰种子（跳过
    /// 伪字形/变形已取的 4 个值）。
    private func spawnBeads(for char: NebbiaCharPlan) {
        var rng = NebbiaRng(seed: char.beadRngSeed)
        for _ in 0..<4 { _ = rng.next() }
        let cx = char.x - plan.rect.minX
        let cy = char.y - plan.rect.minY
        for _ in 0..<3 {
            if rng.next() > 0.35 { continue }
            let r = CGFloat(1.6 + pow(rng.next(), 2.2) * 3.6)
            let dot = UIView()
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.5)
            dot.layer.cornerRadius = r / 2
            dot.bounds = CGRect(x: 0, y: 0, width: r, height: r)
            dot.center = CGPoint(
                x: cx + CGFloat(rng.next() - 0.5) * char.size * 0.9,
                y: cy + char.size * 0.42)
            dot.isUserInteractionEnabled = false
            beadsView.addSubview(dot)
        }
        if char.size >= 48 && rng.next() < 1 {
            let r = CGFloat(4 + rng.next() * 3)
            let dot = UIView()
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.55)
            dot.layer.cornerRadius = r / 2
            dot.bounds = CGRect(x: 0, y: 0, width: r, height: r)
            dot.center = CGPoint(x: cx + char.size * 0.36,
                                 y: cy + char.size * 0.44)
            dot.isUserInteractionEnabled = false
            beadsView.addSubview(dot)
        }
        if rng.next() < 0.25 * 0.22 {
            let len = CGFloat(30 + rng.next() * 130)
            let dur = 2 + rng.next() * 3.5
            let drip = UIView()
            drip.backgroundColor = UIColor.white.withAlphaComponent(0.45)
            let r = CGFloat(3.2 + rng.next() * 2.6)
            drip.layer.cornerRadius = r / 2
            drip.bounds = CGRect(x: 0, y: 0, width: r, height: r)
            drip.center = CGPoint(x: cx, y: cy + char.size * 0.4)
            drip.isUserInteractionEnabled = false
            beadsView.addSubview(drip)
            UIView.animate(withDuration: dur, delay: 0.3, options: [.curveEaseIn]) {
                drip.center.y += len
                drip.alpha = 0
            } completion: { _ in drip.removeFromSuperview() }
        }
    }
}

// MARK: - 根视图（触摸只落舞台内小控件，其余穿透给宿主）

private final class NebbiaRootView: UIView {
    var onLayout: (() -> Void)?
    weak var interactiveView: UIView?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 小控件区域交给控件本身；其余区域回落到根视图（内部
        // 子视图全部禁交互，super 命中恒为根视图自身），宿主
        // 挂在渲染器视图或其祖先上的手势照常触发。
        if let iv = interactiveView, !iv.isHidden, iv.alpha > 0.01 {
            let p = convert(point, to: iv)
            if iv.bounds.contains(p) {
                return iv.hitTest(p, with: event)
            }
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - 渲染器

final class NebbiaStageRenderer: LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: true, requiresSpectrum: false, supportsLineSeek: true)

    private let rootView = NebbiaRootView()
    private let shakeView = UIView()
    private let sceneView = UIImageView()
    private let aquaView = UIView()
    private let spotView = UIView()
    private let poolA = CAGradientLayer()
    private let poolB = CAGradientLayer()
    private let beamA = UIView()
    private let beamB = UIView()
    private let beamGradientA = CAGradientLayer()
    private let beamGradientB = CAGradientLayer()
    private let fogA = UIImageView()
    private let fogB = UIImageView()
    private let linesView = UIView()
    private let glassView = UIView()
    private let dewView = UIImageView()
    private let dropView = UIView()
    private let controlBar = UIView()
    private let behindSegment = UISegmentedControl(items: ["街景", "水族", "背景"])
    private let glassSegment = UISegmentedControl(items: ["雨窗", "凝露", "融雪"])

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false

    private var plans: [NebbiaLinePlan] = []
    private var plansKey = ""
    private var lineViews: [Int: NebbiaLineView] = [:]
    private var featherImage: UIImage?

    private let bakeQueue = DispatchQueue(label: "folia.nebbia.bake", qos: .utility)
    private var bakeGeneration = 0
    private var sceneKey = ""
    private var sceneImage: UIImage?
    private var jellyImages: [UIImage] = []

    // 聚光灯（NebbiaSpot 的状态：自平滑时钟 + 临界阻尼弹簧）。
    private var spotT: TimeInterval = -1
    private var spotPos = CGPoint.zero
    private var spotVel = CGPoint.zero
    private var spotRadius: CGFloat = 40
    private var spotRadiusVel: CGFloat = 0
    private var spotI: CGFloat = 0
    private var spotInit = false

    private var lastWall: CFTimeInterval = 0
    private var lastPosition: TimeInterval = -1
    private var rainAcc: Double = 0
    private var snowAcc: Double = 0
    private var dropCount = 0
    private var flakeCount = 0
    private var fxRng = NebbiaRng(seed: 0xBEE5)
    private var nextBumpAt: CFTimeInterval = 0
    private var driftX: CGFloat = 0

    init() {
        view = rootView
        rootView.backgroundColor = .clear
        for v in [shakeView, aquaView, spotView, linesView, glassView, dropView] {
            v.isUserInteractionEnabled = false
        }
        sceneView.contentMode = .scaleToFill
        sceneView.isUserInteractionEnabled = false
        fogA.contentMode = .scaleToFill
        fogB.contentMode = .scaleToFill
        fogA.isUserInteractionEnabled = false
        fogB.isUserInteractionEnabled = false
        dewView.contentMode = .scaleToFill
        dewView.isUserInteractionEnabled = false
        shakeView.addSubview(sceneView)
        shakeView.addSubview(aquaView)
        shakeView.addSubview(fogA)
        shakeView.addSubview(fogB)
        // 聚光灯压在雾上、歌词下：网页在同一着色器里让光同时
        // 照亮雾面，原生分层下放雾下会被不透明雾纹理盖没。
        shakeView.addSubview(spotView)
        shakeView.addSubview(linesView)
        glassView.addSubview(dewView)
        glassView.addSubview(dropView)
        shakeView.addSubview(glassView)
        rootView.addSubview(shakeView)
        // 聚光灯层：光池（径向）在上、光束（线性渐变视图）在下。
        for pool in [poolA, poolB] {
            pool.type = .radial
            pool.startPoint = CGPoint(x: 0.5, y: 0.5)
            pool.endPoint = CGPoint(x: 1, y: 0.5)
            pool.opacity = 0
            spotView.layer.addSublayer(pool)
        }
        for (beam, grad) in [(beamA, beamGradientA), (beamB, beamGradientB)] {
            grad.startPoint = CGPoint(x: 0, y: 0.5)
            grad.endPoint = CGPoint(x: 1, y: 0.5)
            beam.layer.addSublayer(grad)
            beam.isUserInteractionEnabled = false
            beam.alpha = 0
            spotView.addSubview(beam)
        }
        buildControlBar()
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    /// 舞台内小控件（底账两组切换命令的等价落点）：
    /// 「窗外」三选 ↔ 命令面板 visualizer-nebbia-behind-cycle
    /// （雨夜街景/梦海流萤/背景轮换）；「玻璃」三选 ↔
    /// visualizer-nebbia-glass-cycle（雨窗/凝露/融雪轮换）。
    /// 分段直选是轮换命令的超集，写同一 NebbiaTuningStore，
    /// 渲染器经 0.25s 缓存至多 0.25s 后重排/重烘。
    private func buildControlBar() {
        controlBar.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.88)
        controlBar.layer.cornerRadius = 14
        controlBar.layer.borderWidth = 0.5
        controlBar.layer.borderColor = UIColor.separator.cgColor
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        func caption(_ text: String) -> UILabel {
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabel
            return label
        }
        for seg in [behindSegment, glassSegment] {
            seg.setTitleTextAttributes(
                [.font: UIFont.systemFont(ofSize: 12)], for: .normal)
            seg.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        behindSegment.addTarget(self, action: #selector(behindSegChanged),
                                for: .valueChanged)
        glassSegment.addTarget(self, action: #selector(glassSegChanged),
                               for: .valueChanged)
        stack.addArrangedSubview(caption("窗外"))
        stack.addArrangedSubview(behindSegment)
        stack.addArrangedSubview(caption("玻璃"))
        stack.addArrangedSubview(glassSegment)
        controlBar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: controlBar.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: -8),
        ])
        rootView.addSubview(controlBar)
        rootView.interactiveView = controlBar
    }

    @objc private func behindSegChanged() {
        guard NebbiaBehind.allCases.indices.contains(behindSegment.selectedSegmentIndex)
        else { return }
        NebbiaTuningStore.behind = NebbiaBehind.allCases[behindSegment.selectedSegmentIndex]
    }

    @objc private func glassSegChanged() {
        guard NebbiaGlass.allCases.indices.contains(glassSegment.selectedSegmentIndex)
        else { return }
        NebbiaTuningStore.glass = NebbiaGlass.allCases[glassSegment.selectedSegmentIndex]
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        // (61) WC：入口统一过对比钳制——下游 palette.* 全走保护副本。
        var snapshot = snapshot
        snapshot.palette = snapshot.palette.contrastProtected()
        let trackChanged = snapshot.track?.id != self.snapshot?.track?.id
        self.snapshot = snapshot
        if trackChanged {
            plans = []
            plansKey = ""
            clearLineViews()
            spotInit = false
            spotT = -1
            lastPosition = -1
        }
        rootView.backgroundColor = NebbiaTuningStore.behind == .backdrop
            ? .clear : snapshot.palette.background
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        // 环境图层动画随启停冻结/恢复（照 Monet 的 layer.speed 纪律）。
        shakeView.layer.speed = isActive ? 1 : 0
        if isActive { lastWall = 0 }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let now = CACurrentMediaTime()
        let tuning = NebbiaTuningStore.valuesCached(now: now)
        let dtWall = lastWall > 0 ? min(max(now - lastWall, 0), 0.05) : 1.0 / 60
        lastWall = now
        if lastPosition >= 0 && abs(position - lastPosition) > 2 {
            clearLineViews()   // seek 跳变：旧行视图整体回收重建
        }
        ensureScene(tuning: tuning, snapshot: snapshot)
        applyFogState(tuning: tuning)
        ensurePlans(tuning: tuning, snapshot: snapshot)
        syncControlBar(tuning: tuning)
        updateBus(tuning: tuning, now: now)
        updateLines(position: position, tuning: tuning, snapshot: snapshot)
        updateSpot(position: position, tuning: tuning, dt: dtWall)
        updateGlass(tuning: tuning, position: position, dt: dtWall)
        lastPosition = position
    }

    func unmount() {
        isActive = false
        bakeGeneration += 1
        context = nil
        snapshot = nil
        clearLineViews()
        sceneView.image = nil
        fogA.image = nil
        fogB.image = nil
        dewView.image = nil
        sceneImage = nil
        jellyImages = []
        rootView.layer.removeAllAnimations()
        shakeView.layer.removeAllAnimations()
    }

    // MARK: 布局

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        shakeView.frame = bounds
        sceneView.frame = CGRect(x: driftX, y: 0,
                                 width: bounds.width * 1.25, height: bounds.height)
        aquaView.frame = bounds
        spotView.frame = bounds
        fogA.frame = bounds.insetBy(dx: -24, dy: -24)
        fogB.frame = bounds.insetBy(dx: -24, dy: -24)
        linesView.frame = bounds
        glassView.frame = bounds
        dewView.frame = bounds
        dropView.frame = bounds
        let barWidth = min(bounds.width - 24, 460)
        let safeBottom = rootView.safeAreaInsets.bottom
        controlBar.frame = CGRect(
            x: (bounds.width - barWidth) / 2,
            y: bounds.height - safeBottom - 52 - 8,
            width: barWidth, height: 52)
    }

    private func clearLineViews() {
        for (_, v) in lineViews { v.removeFromSuperview() }
        lineViews = [:]
    }

    // MARK: 烘焙调度

    private func paletteSignature(_ p: PaletteTokens) -> String {
        func hex(_ c: UIColor) -> String {
            let v = nebbiaRGB(c)
            return "\(Int(v.r * 255))-\(Int(v.g * 255))-\(Int(v.b * 255))"
        }
        return [hex(p.background), hex(p.primary), hex(p.secondary),
                hex(p.accent), p.isDark ? "d" : "l"].joined(separator: "/")
    }

    /// 场景/雾/凝露/水母的烘焙键：窗外、 scenery、玻璃、凝露
    /// 参数、调色板、尺寸桶（8pt）、render 倍率。键变才重烘。
    private func ensureScene(tuning: NebbiaTuningValues,
                             snapshot: LyricStageSnapshot) {
        let bounds = rootView.bounds
        guard bounds.width > 40, bounds.height > 40 else { return }
        let bucket = "\(Int(bounds.width / 8))x\(Int(bounds.height / 8))"
        let key = [
            tuning.behind.rawValue,
            tuning.scenery.map { $0.rawValue }.joined(separator: "."),
            tuning.glass.rawValue,
            "\(tuning.dew)/\(tuning.dewSize)/\(tuning.dewGlint)",
            "\(tuning.neon)",
            paletteSignature(snapshot.palette),
            bucket,
            tuning.renderScale,
        ].joined(separator: "|")
        if key == sceneKey { return }
        sceneKey = key
        bakeGeneration += 1
        let generation = bakeGeneration
        let palette = nebbiaResolvePalette(snapshot.palette)
        let tokens = snapshot.palette
        let scenePoints = CGSize(width: bounds.width * 1.25, height: bounds.height)
        let fogPoints = bounds.size
        let capBase: CGFloat = 1024
        let cap = capBase * CGFloat(NebbiaTuningStore.renderScaleValue ?? 1)
        bakeQueue.async { [weak self] in
            let scene = nebbiaBakeScene(points: scenePoints, palette: palette,
                                        tokens: tokens, tuning: tuning, cap: cap)
            let fog0 = nebbiaBakeFog(points: fogPoints, palette: palette,
                                     tokens: tokens, behind: tuning.behind,
                                     variant: 0, cap: 288)
            let fog1 = nebbiaBakeFog(points: fogPoints, palette: palette,
                                     tokens: tokens, behind: tuning.behind,
                                     variant: 1, cap: 288)
            let dew = tuning.glass == .dew
                ? nebbiaBakeDew(points: fogPoints, tuning: tuning, cap: 768) : nil
            let jellies = tuning.behind == .aquarium
                ? [palette.la, palette.lb, palette.lc].compactMap { nebbiaBakeJelly(color: $0) }
                : []
            DispatchQueue.main.async {
                guard let self, generation == self.bakeGeneration else { return }
                self.sceneImage = scene
                self.sceneView.image = scene
                self.fogA.image = fog0
                self.fogB.image = fog1
                self.dewView.image = dew
                self.jellyImages = jellies
                self.applyFogState(tuning: tuning)
                self.rebuildAqua(tuning: tuning)
            }
        }
        // 雾浓度即时生效（不等烘焙）：先按当前图调 alpha。
        applyFogState(tuning: tuning)
    }

    private func applyFogState(tuning: NebbiaTuningValues) {
        fogA.alpha = CGFloat(tuning.mist)
        fogB.alpha = CGFloat(tuning.mist) * 0.55
        if fogA.layer.animation(forKey: "nebbia.fogDriftA") == nil {
            let anim = CABasicAnimation(keyPath: "position.x")
            anim.byValue = 18
            anim.duration = 26
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fogA.layer.add(anim, forKey: "nebbia.fogDriftA")
            let animB = CABasicAnimation(keyPath: "position.y")
            animB.byValue = -12
            animB.duration = 34
            animB.autoreverses = true
            animB.repeatCount = .infinity
            animB.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fogB.layer.add(animB, forKey: "nebbia.fogDriftB")
        }
        dewView.isHidden = tuning.glass != .dew
    }

    // MARK: 水族箱（水母 + 气泡，环境图层动画）

    private func rebuildAqua(tuning: NebbiaTuningValues) {
        for v in aquaView.subviews { v.removeFromSuperview() }
        guard tuning.behind == .aquarium, !jellyImages.isEmpty else { return }
        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        var rng = NebbiaRng(seed: 0xA00A)
        let count = min(Int(tuning.jellies.rounded()), 12)
        for i in 0..<count {
            let size = CGFloat(40 + rng.next() * 36) * CGFloat(tuning.jellySize)
            let img = jellyImages[i % jellyImages.count]
            let iv = UIImageView(image: img)
            iv.bounds = CGRect(x: 0, y: 0, width: size, height: size * 1.25)
            iv.center = CGPoint(x: bounds.width * CGFloat(0.08 + rng.next() * 0.84),
                                y: bounds.height * CGFloat(0.15 + rng.next() * 0.6))
            iv.isUserInteractionEnabled = false
            aquaView.addSubview(iv)
            // 漂移（闭环往返）+ 伞盖脉动（缩放呼吸）。
            let drift = CAKeyframeAnimation(keyPath: "position")
            let cx = iv.center.x, cy = iv.center.y
            drift.values = [
                NSValue(cgPoint: CGPoint(x: cx, y: cy)),
                NSValue(cgPoint: CGPoint(x: cx + CGFloat(rng.next() * 36 - 18),
                                         y: cy - CGFloat(14 + rng.next() * 26))),
                NSValue(cgPoint: CGPoint(x: cx + CGFloat(rng.next() * 24 - 12),
                                         y: cy + CGFloat(rng.next() * 10))),
                NSValue(cgPoint: CGPoint(x: cx, y: cy)),
            ]
            drift.duration = 9 + rng.next() * 7
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            iv.layer.add(drift, forKey: "nebbia.jellyDrift")
            let pulse = CABasicAnimation(keyPath: "transform.scale.y")
            pulse.fromValue = 1
            pulse.toValue = 0.92
            pulse.duration = 1.5 + rng.next()
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            iv.layer.add(pulse, forKey: "nebbia.jellyPulse")
        }
        // 气泡：底部升起的小圆，数量 ∝ bubbles。
        let bubbleCount = Int(tuning.bubbles * 10)
        for _ in 0..<bubbleCount {
            let r = CGFloat(2 + rng.next() * 5)
            let b = UIView()
            b.backgroundColor = UIColor.white.withAlphaComponent(0.28)
            b.layer.cornerRadius = r / 2
            b.layer.borderWidth = 0.6
            b.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            b.bounds = CGRect(x: 0, y: 0, width: r, height: r)
            b.center = CGPoint(x: bounds.width * CGFloat(rng.next()),
                               y: bounds.height + 8)
            b.isUserInteractionEnabled = false
            aquaView.addSubview(b)
            let rise = CABasicAnimation(keyPath: "position.y")
            rise.fromValue = bounds.height + 8
            rise.toValue = -16
            rise.duration = 7 + rng.next() * 7
            rise.beginTime = CACurrentMediaTime() - rng.next() * 10
            rise.repeatCount = .infinity
            b.layer.add(rise, forKey: "nebbia.bubbleRise")
        }
    }

    // MARK: 排版调度

    /// 排版键：曲目、行数、尺寸、字号档 + 影响排版的 tuning
    /// 子集（网页 LAYOUT_KEYS 全量 + strokeWidth 影响行视图）。
    private func ensurePlans(tuning: NebbiaTuningValues,
                             snapshot: LyricStageSnapshot) {
        let bounds = rootView.bounds
        guard bounds.width > 40, bounds.height > 40 else { return }
        let key = [
            snapshot.track?.id ?? "-",
            "\(snapshot.lines.count)",
            "\(Int(bounds.width))x\(Int(bounds.height))",
            "\(snapshot.viewport.dynamicTypeScale)",
            tuning.appear.map { $0.rawValue }.joined(separator: "."),
            tuning.fade.map { $0.rawValue }.joined(separator: "."),
            tuning.layouts.map { $0.rawValue }.joined(separator: "."),
            "\(tuning.credits)/\(tuning.jitter)/\(tuning.warp)/\(tuning.hold)",
            "\(tuning.refog)/\(tuning.writeSpeed)/\(tuning.doodle)",
            "\(tuning.strokeWidth)",
            paletteSignature(snapshot.palette),
        ].joined(separator: "|")
        if key == plansKey { return }
        plansKey = key
        clearLineViews()
        let source = nebbiaBuildSource(
            lines: snapshot.lines, trackId: snapshot.track?.id,
            title: snapshot.track?.title, artist: snapshot.track?.artist,
            doodle: tuning.doodle, credits: tuning.credits)
        plans = nebbiaLayoutSong(
            source: source, tuning: tuning,
            width: Double(bounds.width), height: Double(bounds.height),
            fontScale: Double(snapshot.viewport.dynamicTypeScale),
            seedHash: NebbiaRng.fnv1a(snapshot.track?.id ?? "nebbia"))
        if featherImage == nil { featherImage = nebbiaBakeFeather() }
    }

    private func syncControlBar(tuning: NebbiaTuningValues) {
        if let idx = NebbiaBehind.allCases.firstIndex(of: tuning.behind),
           behindSegment.selectedSegmentIndex != idx {
            behindSegment.selectedSegmentIndex = idx
        }
        if let idx = NebbiaGlass.allCases.firstIndex(of: tuning.glass),
           glassSegment.selectedSegmentIndex != idx {
            glassSegment.selectedSegmentIndex = idx
        }
        controlBar.isHidden = false
    }

    // MARK: 行视图生命周期

    private func updateLines(position: TimeInterval, tuning: NebbiaTuningValues,
                             snapshot: LyricStageSnapshot) {
        let sceneFrame = sceneView.frame
        // 回收：已消失 / 被 seek 甩到身后太远的行。
        for (idx, v) in Array(lineViews) {
            guard plans.indices.contains(idx) else {
                v.removeFromSuperview()
                lineViews[idx] = nil
                continue
            }
            let plan = plans[idx]
            let alive = v.update(position: position, sceneFrame: sceneFrame,
                                 sceneImage: sceneImage)
            if !alive || position < plan.t - 1 {
                v.removeFromSuperview()
                lineViews[idx] = nil
            }
        }
        // 建行：进入时间窗且同屏未满 3 行（片尾行不受限）。
        for plan in plans {
            if lineViews[plan.index] != nil { continue }
            let inWindow = position >= plan.t - 0.05
                && (plan.isCredits || position <= plan.fogAt + plan.fadeDur)
            guard inWindow else { continue }
            if !plan.isCredits && lineViews.count >= 3 {
                // 让位近似：最旧一行快速淡出回收（网页让位/
                // 哈气盖掉的降级，见报告）。
                if let oldest = lineViews.keys.min(),
                   let old = lineViews[oldest] {
                    lineViews[oldest] = nil
                    UIView.animate(withDuration: 0.4) { old.alpha = 0 }
                    completion: { _ in old.removeFromSuperview() }
                }
            }
            let lv = NebbiaLineView(plan: plan, palette: snapshot.palette,
                                    strokeWidth: tuning.strokeWidth,
                                    feather: featherImage)
            lineViews[plan.index] = lv
            linesView.addSubview(lv)
            _ = lv.update(position: position, sceneFrame: sceneFrame,
                          sceneImage: sceneImage)
        }
    }

    // MARK: 聚光灯（nebbiaSpot.ts 对译）

    private func updateSpot(position: TimeInterval, tuning: NebbiaTuningValues,
                            dt: CFTimeInterval) {
        let bounds = rootView.bounds
        let enabled = tuning.spot > 0 && tuning.scenery.contains(.spot)
        // 自平滑时钟（dt=0 或偏差 > 0.25 直接对齐）。
        if spotT < 0 || dt == 0 || abs(position - spotT) > 0.25 {
            spotT = position
        } else {
            spotT += (position - spotT) * (1 - exp(-dt / 0.3))
        }
        // 当前正在写的字（从后往前找，startOf/doneOf 同网页）。
        var target: (x: Double, y: Double, s: Double)? = nil
        for plan in plans.reversed() {
            if spotT < plan.t - 0.05 || spotT > plan.doneAt + 0.8 { continue }
            func startOf(_ c: NebbiaCharPlan) -> TimeInterval {
                c.appearDur > 0 ? c.t : c.writeStart
            }
            func doneOf(_ c: NebbiaCharPlan) -> TimeInterval {
                startOf(c) + (c.appearDur > 0 ? c.appearDur : c.writeDur)
            }
            _ = doneOf
            var k = -1
            for (i, c) in plan.chars.enumerated() {
                let blank = c.text.trimmingCharacters(in: .whitespaces).isEmpty
                if !blank && startOf(c) <= spotT
                    && (k < 0 || startOf(c) >= startOf(plan.chars[k])) {
                    k = i
                }
            }
            if k < 0 { continue }
            let c = plan.chars[k]
            var next: NebbiaCharPlan? = nil
            for i in (k + 1)..<plan.chars.count
            where !plan.chars[i].text.trimmingCharacters(in: .whitespaces).isEmpty {
                next = plan.chars[i]
                break
            }
            if let n = next {
                let u = nebbiaSmooth((spotT - startOf(c))
                    / max(0.05, startOf(n) - startOf(c)))
                target = (Double(c.x) + (Double(n.x) - Double(c.x)) * u,
                          Double(c.y) + (Double(n.y) - Double(c.y)) * u,
                          Double(c.size) + (Double(n.size) - Double(c.size)) * u)
            } else {
                target = (Double(c.x), Double(c.y), Double(c.size))
            }
            break
        }
        if let t = target, enabled {
            if !spotInit || dt == 0 {
                spotPos = CGPoint(x: t.x, y: t.y)
                spotRadius = CGFloat(t.s)
                spotVel = .zero
                spotRadiusVel = 0
                spotInit = true
            } else {
                // 临界阻尼弹簧，时间常数 0.1s，分步积分（网页同法）。
                let w = 1.0 / 0.1
                let steps = max(1, Int(ceil(dt / 0.008)))
                let h = dt / Double(steps)
                for _ in 0..<steps {
                    spotVel.x += CGFloat(
                        (w * w * (t.x - Double(spotPos.x)) - 2 * w * Double(spotVel.x)) * h)
                    spotPos.x += spotVel.x * CGFloat(h)
                    spotVel.y += CGFloat(
                        (w * w * (t.y - Double(spotPos.y)) - 2 * w * Double(spotVel.y)) * h)
                    spotPos.y += spotVel.y * CGFloat(h)
                    spotRadiusVel += CGFloat(
                        (w * w * (t.s - Double(spotRadius)) - 2 * w * Double(spotRadiusVel)) * h)
                    spotRadius += spotRadiusVel * CGFloat(h)
                }
            }
        }
        let iTarget: CGFloat = (target != nil && enabled) ? 1 : 0
        if dt == 0 {
            spotI = iTarget
        } else {
            let tau = iTarget > 0 ? 0.15 : 0.5
            spotI += (iTarget - spotI) * CGFloat(1 - exp(-dt / tau))
        }
        let strength = CGFloat(min(tuning.spot, 2) / 2) * spotI
        spotView.isHidden = strength < 0.01
        guard !spotView.isHidden else { return }
        let palette = snapshot.map { nebbiaResolvePalette($0.palette) }
        let light = palette?.la ?? UIColor(red: 1, green: 0.81, blue: 0.54, alpha: 1)
        let r = max(spotRadius * 2.3, 30)
        for pool in [poolA, poolB] {
            pool.frame = CGRect(x: spotPos.x - r, y: spotPos.y - r,
                                width: r * 2, height: r * 2)
            pool.colors = [light.withAlphaComponent(0.30 * strength).cgColor,
                           light.withAlphaComponent(0).cgColor]
            pool.opacity = 1
        }
        poolB.opacity = 0.6
        // 两束光：源在底部（spotX 与其镜像），指向当前字。
        let sources = [CGPoint(x: bounds.width * CGFloat(tuning.spotX),
                               y: bounds.height + 30),
                       CGPoint(x: bounds.width * CGFloat(1 - tuning.spotX),
                               y: bounds.height + 30)]
        for (i, beam) in [beamA, beamB].enumerated() {
            let src = sources[i]
            let dx = spotPos.x - src.x, dy = spotPos.y - src.y
            let len = hypot(dx, dy)
            guard len > 1 else { beam.alpha = 0; continue }
            beam.bounds = CGRect(x: 0, y: 0, width: len, height: 110)
            beam.center = CGPoint(x: (src.x + spotPos.x) / 2,
                                  y: (src.y + spotPos.y) / 2)
            beam.transform = CGAffineTransform(rotationAngle: atan2(dy, dx))
            beam.alpha = 0.55 * strength
            let grad = i == 0 ? beamGradientA : beamGradientB
            grad.frame = beam.bounds
            grad.colors = [light.withAlphaComponent(0.16).cgColor,
                           light.withAlphaComponent(0).cgColor]
        }
    }

    // MARK: 玻璃效果（雨点 / 凝露 / 雪）

    private func updateGlass(tuning: NebbiaTuningValues,
                             position: TimeInterval, dt: CFTimeInterval) {
        dewView.isHidden = tuning.glass != .dew
        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        let singing = plans.contains {
            position >= $0.t && position <= $0.end
        }
        switch tuning.glass {
        case .rain:
            guard tuning.rainHit > 0 else { return }
            rainAcc += dt * tuning.rainHit * (singing ? 15 : 5)
            while rainAcc >= 1 && dropCount < 56 {
                rainAcc -= 1
                spawnDrop(tuning: tuning, big: false)
            }
            if rainAcc > 4 { rainAcc = 4 }
            // 吐字大雨点：有字恰在本帧跨过开写时刻时砸一颗。
            if tuning.rainBig > 0, lastPosition >= 0 {
                for plan in plans where position >= plan.t && position <= plan.doneAt {
                    for c in plan.chars where c.appearDur <= 0
                        && lastPosition < c.writeStart && position >= c.writeStart {
                        spawnDrop(tuning: tuning, big: true)
                    }
                }
            }
        case .snow:
            guard tuning.snow > 0 else { return }
            snowAcc += dt * tuning.snow * 9
            while snowAcc >= 1 && flakeCount < 40 {
                snowAcc -= 1
                spawnFlake(tuning: tuning)
            }
            if snowAcc > 4 { snowAcc = 4 }
        case .dew:
            break
        }
    }

    /// 随机落点：避开正在唱的那句（网页疏雨轻车的躲避口径，
    /// 3 次重试）。
    private func dropPoint(tuning: NebbiaTuningValues, big: Bool) -> CGPoint {
        let bounds = rootView.bounds
        var point = CGPoint.zero
        for _ in 0..<3 {
            point = CGPoint(x: bounds.width * CGFloat(fxRng.next()),
                            y: bounds.height * CGFloat(fxRng.next()))
            let inActive = plans.contains {
                lastPosition >= $0.t && lastPosition <= $0.end
                    && $0.rect.insetBy(dx: -8, dy: -8).contains(point)
            }
            if !inActive { break }
        }
        return point
    }

    private func spawnDrop(tuning: NebbiaTuningValues, big: Bool) {
        let r: CGFloat = big
            ? CGFloat(4 + fxRng.next() * 4) * CGFloat(tuning.rainBig)
            : CGFloat(1 + fxRng.next() * 2.2)
        guard r > 0.4 else { return }
        let drop = UIView()
        drop.backgroundColor = UIColor.white.withAlphaComponent(big ? 0.6 : 0.45)
        drop.layer.cornerRadius = r / 2
        drop.bounds = CGRect(x: 0, y: 0, width: r, height: r)
        drop.center = dropPoint(tuning: tuning, big: big)
        drop.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        drop.isUserInteractionEnabled = false
        dropView.addSubview(drop)
        dropCount += 1
        UIView.animate(withDuration: 0.15) {
            drop.transform = .identity
        } completion: { [weak self] _ in
            guard let self else { return }
            // 三成水珠下淌（斜落随车速/窗外雨向；其余静挂后淡出）。
            if self.fxRng.next() < 0.3 {
                let len = CGFloat(30 + self.fxRng.next() * 120)
                let slant: CGFloat = tuning.rain == .slant
                    ? -len * 0.3 * CGFloat(min(tuning.busSpeed, 1.5)) : 0
                UIView.animate(withDuration: Double(1 + self.fxRng.next() * 1.5),
                               delay: 0.3, options: [.curveEaseIn]) {
                    drop.center = CGPoint(x: drop.center.x + slant,
                                          y: drop.center.y + len)
                    drop.alpha = 0
                } completion: { _ in
                    drop.removeFromSuperview()
                    self.dropCount = max(0, self.dropCount - 1)
                }
            } else {
                UIView.animate(withDuration: 0.6, delay: 0.5 + self.fxRng.next()) {
                    drop.alpha = 0
                } completion: { _ in
                    drop.removeFromSuperview()
                    self.dropCount = max(0, self.dropCount - 1)
                }
            }
        }
    }

    private func spawnFlake(tuning: NebbiaTuningValues) {
        let bounds = rootView.bounds
        let r = CGFloat(2.5 + fxRng.next() * 4) * CGFloat(tuning.snowSize)
        let flake = UIView()
        flake.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        flake.layer.cornerRadius = r / 2
        flake.bounds = CGRect(x: 0, y: 0, width: r, height: r)
        let startX = bounds.width * CGFloat(fxRng.next())
        flake.center = CGPoint(x: startX, y: -8)
        flake.isUserInteractionEnabled = false
        dropView.addSubview(flake)
        flakeCount += 1
        // 三成粘住：中途停住、按 snowMelt 化掉；其余落到底淡出。
        let sticks = fxRng.next() < 0.3
        let stopY = sticks
            ? bounds.height * CGFloat(0.15 + fxRng.next() * 0.7)
            : bounds.height + 8
        let fall = Double(stopY / 26) * (0.7 + fxRng.next() * 0.6)
        UIView.animate(withDuration: max(fall, 1.5), delay: 0,
                       options: [.curveEaseInOut]) {
            flake.center = CGPoint(x: startX + CGFloat(self.fxRng.next() * 30 - 15),
                                   y: stopY)
        } completion: { [weak self] _ in
            guard let self else { return }
            let melt = sticks ? 2.5 / max(tuning.snowMelt, 0.25) : 0.4
            UIView.animate(withDuration: melt) {
                flake.alpha = 0
                flake.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
            } completion: { _ in
                flake.removeFromSuperview()
                self.flakeCount = max(0, self.flakeCount - 1)
            }
        }
    }

    // MARK: 车速漂移与颠簸

    private func updateBus(tuning: NebbiaTuningValues, now: CFTimeInterval) {
        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        // 街景漂移：场景图宽 1.25 倍，x 在 [-0.25W, 0] 内随
        // 车速循环（busSpeed=0 时居中静止）；水族箱不漂。
        if tuning.behind == .night && tuning.busSpeed > 0 {
            let span = Double(bounds.width) * 0.25
            let travelled = (now * 9 * tuning.busSpeed).truncatingRemainder(
                dividingBy: span)
            driftX = CGFloat(-travelled)
        } else {
            driftX = -bounds.width * 0.125
        }
        if abs(sceneView.frame.minX - driftX) > 0.5 {
            sceneView.frame = CGRect(x: driftX, y: 0,
                                     width: bounds.width * 1.25,
                                     height: bounds.height)
        }
        // 颠簸：街景随机间隔弹簧式一颠（水族箱不颠，网页同
        // 口径）；智能动感「疏雨轻车」的底鼓联动无数据源，
        // 保持随机颠簸（见报告）。
        if tuning.behind == .night && tuning.bump > 0 && isActive {
            if nextBumpAt == 0 {
                nextBumpAt = now + 2 + fxRng.next() * 4
            } else if now >= nextBumpAt {
                nextBumpAt = now + 2.5 + fxRng.next() * 4.5
                let b = CGFloat(tuning.bump)
                let jolt = CAKeyframeAnimation(keyPath: "transform.translation.y")
                jolt.values = [0, -3.2 * b, 1.6 * b, -0.6 * b, 0]
                jolt.keyTimes = [0, 0.3, 0.55, 0.8, 1]
                jolt.duration = 0.5
                jolt.timingFunction = CAMediaTimingFunction(name: .easeOut)
                shakeView.layer.add(jolt, forKey: "nebbia.bump")
            }
        }
    }
}
