# (96) 取证改造零痕迹 — 断点诊断

任务：只诊断、不落码。输入事实：(96) IPA 二进制里 p96 系列面包屑在位（交付验包已核）；但 Miller 导出的日志（`~/workspace/user/files/upload-6b1cb135.txt`，1201 行）仍是旧两段结构（上一会话尾巴恰 200 行＋本会话 999 行），p96 全文件零条、无孤儿标记、闪退会话第三次缺席（判读 `forensics/log-96-verdict.md`）。源码：release-96 分支。

## 断点定案（一句话）

**断点在导出层，两处叠加**：① Miller 用的旧查看器只拼 `folia-prev-tail.log`（200 行）＋两份轮换文件的最后 1000 行，(96) 新增的 `folia-prev-session-full.log` 与 `folia-fx-events.log` 全仓没有任何读取入口——写了也永远进不了导出；② 1000 行 cap 把本会话头部（含全部启动见证行 `p96 session begin` / `p96 wit` / `p94 wit` / `wit78…86` / `prevtail.save`）截掉。**Emit 层与存储层按代码走查无断点。**

## 一、Emit 层：未断（逐项证据）

- `p96 session begin`：`FoliaBridgeLogStore.init`（`Sources/Native/Features/WebBridge/WebEffectBridge.swift:172–177`）——单例首访即先跑 `preservePreviousSessionTail()`，随后 `writeSync(level: "info", module: "crumb", message: "p96 session begin id=\(Self.sessionID96)")`。首访发生在 `AppDelegate.swift:74` 的 `Breadcrumbs.witnessBoot78()`（及此前数行 `Breadcrumbs.log`），无条件执行；`writeSync` 是同步落盘（`:312–322`，`ioQueue.sync { appendToFile }`）。
- `p96 wit` / `p94 wit`：`Breadcrumbs.swift:165–172`，`witnessBoot94()` 内 `log("p96 wit fx=1 wd=1 panic=1 log=1")` ＋ `FxEventLog96.checkOrphanOnLaunch()`，由 `witnessBoot78()`（`:153`）调用，启动必经。
- `p96 setx enter / guard-skip`：`GlobalFx87.swift:1190–1244`，四个 setX 入口 guard 前落行；`p96 forceStop`（`:1034`，`logSync`）、`p96 wd audit`（`:1093`、`:1116`）。**事件驱动**——留存会话里无特效开关，零条是预期内，不是 emit 故障。
- 门控未挡：`logCaptureEnabled62`（`SettingsStore62C.swift:137`，默认开）、`bridgeLogWriteEnabled62`（`:214`，默认开）；Miller 导出物满是 crumb 行，证实采集开着。
- 节流未吞：`write()` 的高频聚合只命中 `wall.cache / pf83 / cvr.stat / wall.dec78 / p94 web resize` 五前缀（`WebEffectBridge.swift:280–286`），并注明 fx 类永不节流；p96 行不在节流前缀内。
- Emit 侧唯一残留风险（次要，非主断点）：`Breadcrumbs.log` 是异步写（`ioQueue.async`），崩溃紧接着发生的事件行可能在队列排空前丢失；仅 `forceStop` 与 `session begin` 用了 `writeSync`。这是 (63) 已知口径。

## 二、存储层：写入无断点，缺失的是读取入口（见第三段）

- 轮换文件：`appendToFile`（`WebEffectBridge.swift:342–362`），2MB 双文件轮换，下标存 UserDefaults（`folia.log.index`），目录 `Caches/folia-logs/folia-bridge-{0,1}.log`。
- `folia-prev-session-full.log`：`preservePreviousSessionTail()`（`:184–216`）内同步写（4MB 截断），每次启动都写。写入无断点。
- `folia-fx-events.log` ＋ `folia-fx-active.json`：`FxEventLog96`（`:426–525`），`record` 用 `ioQueue.sync` ＋ `handle.synchronize()`（fsync），`markActive/markCleared` 原子写。写入无断点；但只在特效事件发生时才写——留存会话无特效事件，文件可能不存在或为空，属预期内。
- 存储侧唯一未确认项（非主断点）：闪退会话在轮换文件里零行。按代码它应在轮换文件里（异步写毫秒级落盘），除非①崩溃发生在启动后极短时间内、异步队列未排空；②2MB 轮换翻转删掉了它所在的文件（`appendToFile` 翻转时 `removeItem` 另一文件，墙面高频日志下数分钟即可翻转一次）。②是合理解释但无直接证据；待导出修复后复现再定。

## 三、导出层：主断点，两处（均已证实）

### E1 — (96) 两个新文件零读取入口

- Miller 导出物的首行 `—— 上一会话尾巴（自动留存）——` 与 `Sources/SettingsViewController.swift:1675–1680` 的拼接格式逐字一致，证明他用的是**旧查看器 `BridgeLogViewController`**（入口 `SettingsViewController.swift:1141` `logTapped()`）。其 `viewDidLoad`（`:1668–1673`）只读两样：

```swift
let tail = FoliaBridgeLogStore.shared.prevTailText()              // folia-prev-tail.log，200 行
let recent = FoliaBridgeLogStore.shared.recentLogText(maxLines: 1000)
let text = tail.isEmpty ? recent
    : "—— 上一会话尾巴（自动留存）——\n" + tail
        + "\n—— 本会话 ——\n" + recent
```

- 全仓 grep：`folia-prev-session-full.log` 唯一出现处是写入点（`WebEffectBridge.swift:207`）；`folia-fx-events.log` 唯一出现处在 `FxEventLog96` 内部；`prevTailText()`（`:222–227`）只读 `folia-prev-tail.log`；`recentLogText`（`:368–385`）只读两份轮换文件。**结论：(96) 的两个新取证文件没有任何代码路径能进入 Miller 的导出物。**
- 新全量查看器 `BridgeLog62ViewController`（`Panels62.swift:612`）用 `recentLogText(maxLines: 100_000)`，同样不读两个新文件；且 Miller 没用它（导出物格式不符）。

### E2 — 1000 行 cap 截掉会话头

- `recentLogText(maxLines: 1000)` 取两份轮换文件合并后的最后 1000 行。启动见证行（`wit78…86`、`p94 wit`、`p96 wit`、`p96 session begin`、`prevtail.save`）全部落在会话头部（init ＋ AppDelegate 启动时）。Miller 本次导出会话在导出前已写 ＞1000 行（可见的 999 行只是尾部，段首 10:15:04 已是歌单墙中途、无任何启动行），头部被 cap 截掉。
- 导出物 grep 验证：`p96|p94 wit|session begin|prevtail.save` 全文件 **0 条**——与 cap 截断一致，无需 emit 故障假设。

## 四、为什么 (96) 漏了它

(96) A4 只改了写入侧（新文件＋聚合节流），没改任何读取/导出代码。交付验包只核了二进制字面量在位（emit 的必要条件），没核导出物里出现特征行（充分条件）。修复停在落盘，没走到用户实际拿到的导出文件。

## 五、(97) 最小修复清单

1. **`BridgeLogViewController.viewDidLoad`（`SettingsViewController.swift:1668–1673`）**：导出拼接追加两段——`folia-prev-session-full.log` 全文（截后 4MB）与 `folia-fx-events.log`（＋`.old`）全文；并把 `recentLogText(maxLines: 1000)` 的 cap 提至与新查看器一致（或改为全量）。顺序定死：尾巴 → 全量快照 → fx 事件 → 本会话，每段带分隔行。
2. **同步改 `BridgeLog62ViewController`（`Panels62.swift:612`）**：`allLines` 的来源同样追加两个新文件，否则两个查看器口径分裂。
3. **兜底（防 cap 再截头）**：导出时把当前会话的 `p96 session begin` 行单独检索置顶，或把 `recentLogText` 改为「会话头 N 行＋最近 M 行」而非纯尾部截断。
4. **修复后自证清单（必须逐项在真机导出物里 grep 到，才算修到执行路径）**：`p96 session begin` ≥1、`p96 wit` ≥1、`prevtail.save` ≥1、上一会话全量快照段存在（为空时标注 `prev-session-full: empty`）、fx 事件段存在（无事件时标注 `fx events: none`——缺席与未读无法区分，必须显式标注）。
5. **闪退会话缺席的跟进**：修复 1–2 后让 Miller 复现一次排版闪退再导出；若闪退会话仍不在 `folia-prev-session-full.log` 段内，再查轮换翻转删文件（`appendToFile` `:352–358` 的 `removeItem`）是否为删因，届时再定是否把快照改成「每次退后台/崩溃边界即时写」而非仅启动时写。
