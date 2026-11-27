# (97) 第 10 项前置审计：歌词数据通路字级时间戳

- 日期：2026-11-27
- 仓库：`~/workspace/folia-deploy/ios-shell`，分支 `release-97`
- 范围：只审计、未改任何代码。方法：全仓 grep（`LyricParser / YRC / yrc / krc / qrc / word / karaoke / 逐字`）＋逐文件读 LyricRepository.swift（1022 行）、EdgeOneAPIClient.swift 歌词段、LyricParser.swift、LyricStageProtocol.swift、LyricWindowView.swift、WallPrototypeViewController.swift 消费点。
- 背景问题：封面歌词新样式（Apple Music 式卡拉 OK 逐字填充）需要逐字/逐词时间戳——现有链路有没有？

## 0. 总结论

**有，但只在网易云一条腿上全链打通。** 原生侧早在 3.7 (19)/(20) 就接了与网页版同源的 `/lyric/new` → YRC 逐字戳，经双表合并 rebase 后逐行下发，墙面展开卡与原生舞台都在消费。QQ 无（函数端未实装＋只按 LRC 形状假设），酷狗无（客户端明确只要 `fmt=lrc`）。(97) 封面歌词逐字填充：网易云歌可直接用真戳；QQ/酷狗及网易云无 YRC 覆盖的行走既有均分降级（现成口径，见 §4）。

## 1. 每平台结论

| 平台 | 歌词格式 | 字级时间戳 | 证据 |
|---|---|---|---|
| 网易云 | LRC（行级）＋ YRC（逐字）双表 | **有**（逐行可选：有 YRC 覆盖且匹配上的行带真戳，其余行 nil） | 见 §1.1 |
| QQ | 无（函数端 501 未实装）；App 侧按 LRC 文本形状假设 | **无** | 见 §1.2 |
| 酷狗 | LRC（base64 编码文本） | **无**（上游 KRC 逐字格式原生侧从未请求、无解析器） | 见 §1.3 |
| 本地曲库（附带） | LRC 或 YRC（按文件格式判定） | YRC 文件时**有** | `LyricRepository.swift:511-519` `localLyricLines`：`isWordTimed ? parseYRC : parseLRC` |

### 1.1 网易云：有，全链证据

1. 取数：`EdgeOneAPIClient.swift:385-395` `fetchLyricBundle(songId:)` 走 `GET /api/netease/lyric/new`，一次返回 lrc＋yrc。文件头注释（:377-381）实测记录：

   > lrc + yrc（实测 2026-11-19：id 529319768 → 200，yrc version 12、逐字戳齐全）。墙链据此优先用 YRC 派生行时刻与逐字扫光，与 Web 详情页（同走 /lyric/new）同源时刻表

   响应结构 `EdgeOneAPIClient.swift:1006-1011`：`NeteaseLyricNewResponse { lrc: LrcBody?, yrc: LrcBody?, nolyric: Bool? }`，`LrcBody = {version, lyric}` 只取文本。

2. 解析：`LyricRepository.swift` 内 `LyricParsing.parseYRC`（约 :895 起）解析 YRC 行格式 `[startMs,durMs](startMs,durMs,flag)字…`，逐字元组 → `LyricWordStamp(start: wordStart/1000, duration: wordDur/1000, text: wordText)`；元组中途解析失败的行降级 `words=nil`。

3. 合并：`LyricParsing.mergeLyricLines`（:688 起）默认口径 = **行时刻取 LRC、逐字戳取 YRC**，逐行按文本两级匹配（精确键＋折叠键），`rebaseWords`（:832 起）把 YRC 戳整行平移到 LRC 行首、以下一行首为硬边界夹取。匹配不上的行 `words=nil`。

4. 落盘/下发：合并结果即 `LyricRepository.Entry.lines: [LyricLineData]`（:26-28）。覆盖率有面包屑可判读（:336-352）：`withWords` 计数＋`wordSrc=yrc/mixed/uniform`（全行有戳／部分行／全行均分）。

5. 消费（两处都在用真戳）：
   - 墙面展开卡：`WallPrototypeViewController.swift:3731` 把 `lines[idx].words` 传给 `LyricWindowView.setWindow(lineWords:)`，`LyricWindowView.swift:442` `wordSweepProgress(words:now:)` 按真戳算已唱前缀宽＋当前字内插。
   - 原生舞台：`LyricParser.swift:52-84` `stageLines(from:)` 把 `LyricLineData.words` 映射成协议 `LyricLine.words: [LyricWord]?` 进 `LyricStageSnapshot.lines`。

6. 两个会丢戳的设置门（默认均为开/保留，`SettingsStore62B.swift:378-379, 416-417`，default true）：
   - `autoBestLyricEnabled=false` → 不合并 YRC、恒行级（`LyricRepository.swift:231-236`）；
   - `keepPlatformWordLyrics=false` → 出口把 words 全部置 nil（:285-288，舞台出口 :71-75 双保险）；
   - 另 `bestLyricStrategy == "lrcFirst"` 时后处理丢逐字退行级（:248-252）。

### 1.2 QQ：无

- `EdgeOneAPIClient.swift:434-449` `fetchQQLyricText(songmid:)`：注释明示函数端 `/lyric` 路由**未实装**（2026-11-21 实测回 501「/lyric is not implemented」）；响应形状按网易云同族 `{lrc:{lyric}}` **假设**、未经真回包复核。
- `LyricRepository.swift:460-492` `fetchQQEntry`：只 `parseLRC`，`flip` 恒 `"lrc"`；抛错时条目标 `platformPending`，UI 显示「该平台歌词暂未接入」。
- 即函数补齐后按现假设也只有行级 LRC，`words` 恒 nil。QQ 的逐字格式 QRC 原生侧无请求、无解析器（仅网页束解析器支持，见 §3）。

### 1.3 酷狗：无

- `EdgeOneAPIClient.swift:398-432` `fetchKugouLyricText(hash:)`：两步链 `/search/lyric` 取候选 → `/lyric?id=&accesskey=&fmt=lrc&charset=utf8`，`content` 为 base64 LRC 文本（注释：2026-11-21 实测 20/20 供词）。**`fmt=lrc` 是客户端写死只取行级格式**。
- `LyricRepository.swift:406-457` `fetchKugouEntry`：只 `parseLRC`，`words` 恒 nil，`flip` 恒 `"lrc"`。
- 酷狗逐字格式 KRC：原生侧无 `fmt=krc` 请求、无 KRC 解析器（全仓 grep `krc` 在 Swift 源码零命中）。

## 2. 数据结构结论（原文摘录）

仓库行模型 `Sources/Native/Features/Wall/WallPrototypeViewController.swift:16-20`：

```swift
struct LyricLineData {
    let time: Double
    let text: String
    let words: [LyricWordStamp]?
}
```

逐字戳 `Sources/Native/Features/Wall/LyricWindowView.swift:53-57`（秒，绝对时间线）：

```swift
struct LyricWordStamp {
    let start: Double
    let duration: Double
    let text: String
}
```

舞台协议行 `Sources/Native/Features/Stage/LyricStageProtocol.swift:55-77`：

```swift
struct LyricWord: Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

struct LyricLine: Equatable {
    var id: Int
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var words: [LyricWord]? = nil
    var singingRatio: Double = 1
}
```

协议能力位（同文件 :19-33、:40-47）：`LyricStageProtocolInfo.version = 2`，`hostCapabilities.supportsWordSync = true`——v2 变更记录明示语义：宿主可提供逐字数据（来源 /lyric/new 的 YRC、经仓库合并 rebase 后逐行下发），**逐行可选，无戳行 words=nil，消费方必须按既有均分口径降级，不得假设整首全行有戳**。

时间基准：`words[].start/duration` 与 `LyricLineData.time` 同为**曲目内绝对秒**；填充驱动可用引擎 `currentTime`（墙链现行口径）或舞台 `PlaybackAnchor.position(atWallTime:)` 插值（协议 :50-53），与现行扫光同一时钟，无需新时间源。

## 3. 网页版参照对照

- 网页版 `/lyric/new` 取 YRC 的通路在原生侧**有对应物且同源**：即 §1.1 的 `fetchLyricBundle`，注释自述「与 Web 详情页（同走 /lyric/new）同源时刻表」。这正是 (19)/(20) 按「对照移植先查数据通路」补上的那条线，现行默认开启。
- 网页束解析器能力比原生宽：`Resources/WebEffect/assets/lyricsParser.worker-*.js` 内含 `yrc / qrc / krc / awlrc / enhanced-lrc` 五种格式分发；原生 Swift 侧只有 `parseLRC + parseYRC` 两种。差集 = QRC、KRC、enhanced-LRC 三种逐字格式无原生对应物。

## 4. (97) 封面歌词逐字填充的可行路径

### 4.1 有戳时（网易云有 YRC 覆盖的行）——直接可用，不用改数据层

- 数据入口与墙面展开卡同源：`LyricRepository.Entry.lines[idx].words: [LyricWordStamp]?`；或走舞台快照 `LyricLine.words: [LyricWord]?`（start/end 形）。
- 填充算法现成：`LyricWindowView.wordSweepProgress(words:now:)`（LyricWindowView.swift:442）已实现「已唱前缀宽＋当前字按 `frac=(now-start)/duration` 内插」的卡拉 OK 进度，封面样式的前锋亮边/逐字填充可直接复用此口径，只换呈现层。

### 4.2 无戳时（QQ 全部、酷狗全部、网易云未覆盖行）——降级口径（现成，非新发明）

现行生产口径即「整行按行时长匀速扫光」，(97) 沿用即可：

- 行跨度：`WallPrototypeViewController.swift` 当前行时长计算（:3713-3723）`duration = clamp(下一行.time − 本行.time, 0.8, 10) × singingRatio`，末行 `clamp(字数×0.4, 2.5, 8) × r`。
- `singingRatio r` 由仓库标定（`LyricRepository.Entry.singingRatio`：同曲有戳行中位 → 跨曲池中位 → 缺省 0.8），作用是把行尾气口从填充跨度里摘掉，避免填充恒慢于演唱。
- 呈现上：无戳行按 `progress = (now − lineStart) / duration` 对整行宽度线性填充（与有戳行的视觉差异仅在字间节奏不真实）；若样式需要逐字粒度，可按字宽比例把 progress 折算到字，与真戳路径共用同一渲染函数（words 合成均分戳即可，合成点放在消费端、不回写仓库）。

### 4.3 未来接 QRC/KRC 的改造点（本包不做，仅登记）

| 平台 | 改造点 | 前置条件 |
|---|---|---|
| QQ | ① EdgeOne 函数端实装 QQ `/lyric` 路由并返回 QRC（外部依赖，非 App 仓内）；② `EdgeOneAPIClient.fetchQQLyricText`（:442）改取 QRC 字段；③ `LyricParsing` 新增 `parseQRC`；④ `LyricRepository.fetchQQEntry`（:460）改双表合并（可复用 `mergeLyricLines` 形状） | 函数端先行；响应形状须以真回包复核（现假设未验） |
| 酷狗 | ① `EdgeOneAPIClient.fetchKugouLyricText`（:417-424）`fmt=lrc` 改/加 `fmt=krc`；② `LyricParsing` 新增 `parseKRC`（KRC 逐字元组格式，网页束解析器有参照实现可对照）；③ `fetchKugouEntry`（:406）接合并 | 须先实测函数端对 `fmt=krc` 的真实回包（本审计未验，**未确认**） |

## 5. 未确认项

- 网易云 YRC 的逐行覆盖率随歌曲而变（面包屑 `wordSrc` 分 yrc/mixed/uniform 三态），本审计只证通路与结构，未抽样统计当前曲库覆盖比例；(97) 验收时可按日志 `lrc source … withWords=… wordSrc=…` 判读具体歌曲。
- QQ 函数端、酷狗 `fmt=krc` 均为外部/未实测项，结论以仓内代码与 2026-11-21 实测注释为准。
