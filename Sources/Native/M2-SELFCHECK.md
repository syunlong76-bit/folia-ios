# M2 自查记录（M2-SELFCHECK.md）

实施者：M2 子代理。日期：2026-11-14。范围：只 M2（native-arch.md §9/§10）。
本机为 Linux VM、无 Xcode：凡标「未测」的项均为本地无法验证，需 GitHub Actions
（xcodebuild 编译）与 Miller 真机验收；凡标「代码完成」的项均为静态核对通过，
绝不冒充已在真机上验过。锁屏 / 后台 / 白闪等一律只标「代码完成，待 Miller 真机验收」。

## 文件清单（本次新增 / 修改）

新增（`ios-shell/Sources/Native/`，M1 落地后接口已逐项对齐，见末节）：
- `Features/WebBridge/WebEffectBridge.swift` — 桥、快照 DTO、滚动日志、弱引用 handler
- `Features/WebBridge/PassthroughWebView.swift` — 手势穿透框架（默认空区域）
- `Features/Player/MiniPlayerView.swift` — 原生悬浮迷你条（全 App 唯一播放条）
- `Features/Player/FullPlayerContainer.swift` — 全屏播放容器（原生顶栏＋Slider）
- `Features/Player/RenderStateCenter.swift` — app 级渲染激活状态中心

新增（`ios-shell/Resources/WebEffect/`）：
- `folia-bridge.js` — 插值协议 + gated Logger（任务 B）
- `index.html` — POC 占位可视化壳（非 Folia 构建产物，见“未落下的项 1”）
- `STRIP-PLAN.md` — 真实剥离包的 folia-major 改动点清单（待协调员批准）

修改：
- `ios-shell/Sources/MainViewController.swift` — 最小集成（+87 行）：
  import Combine/SwiftUI、两个 UIHostingController 悬浮/常驻挂载、迷你条与容器可见性订阅、
  桥 minimize 回调接 RenderStateCenter。LocalServer 与 `/__bridge/*` 未动。
- `ios-shell/project.yml` — **M2 未动**。工作区中该文件的修改（iOS 17 / 3.1(2) /
  `-lsqlite3`）是并行 M1 的，见其 M1-SELFCHECK.md。M2 缺口：该文件仍缺
  `Resources/WebEffect` 的 folder-reference 资源条目（见“未落下的项 2”）。

未动：M1 的 Core 文件、folia-major 源码（mtime 证实：其未提交改动均为 06:31 UTC
之前，M2 会话 15:25 UTC 开始后未碰）、Netlify 设置。

## §9 桥协议逐项核对

- [x] `foliaAction` 注册在创建 WKWebView 之前 — **代码完成（grep）**。
  `WebEffectBridge.swift:292` `config.userContentController.add(weakHandler, name: "foliaAction")`，
  `:295` 才 `PassthroughWebView(frame: .zero, configuration: config)`。
  另用可后设 delegate 的 `WeakScriptMessageHandler` 解决“self 尚不存在”的注册时序。
- [x] `WeakScriptMessageHandler` 防泄漏 — **代码完成**。
- [x] `dispatchToJS` 的 type 改 `BridgeEvent` 枚举 — **代码完成**。
  11 个 case（state/progress/seek/queue/artwork/lyrics/theme/snapshot/renderState/
  buffering/spectrum）；spectrum 只定型、POC 前不发；未知值前端直接忽略。
- [x] 200ms 周期 + rAF + `performance.now()` 本地插值，禁 60Hz evaluateJavaScript — **代码完成**。
  桥订阅 `PlaybackEngine.$currentTime`（不占 `onTimeSync` 单回调）；JS 热路径无 console 输出。
- [x] rate 定义域 [0,2]、只保留 anchor＋elapsed×rate 乘法 — **代码完成（node 实测）**。
  `clampRate` 上限 2；`getInterpolatedTime` 只有一种乘法。
- [x] 拖进度只预览、松手才发 seek — **代码完成**。原生 Slider（`isScrubbing` 锁定，
  松手才 `engine.seek`）；JS 侧 `previewSeek`（只改本地锚点）/`commitSeek`（发 seek 动作）。
- [x] seek 竞态三件套 — **代码完成（桥侧 + 引擎侧双份）**。
  ① 松手 seek 立即推乐观锚点（桥 `noteSeekStarted`）；② pendingSeek 期间周期 observer
  跳过推送（桥侧 `handleEngineTime` + M1 引擎内 `pendingSeek` 各一份）；③ 完成回调回推
  真实位置（桥：落点 ±2s 或 3s 超时后推锚点；引擎：seek 完成回调 `currentTime = resolved`）。
  注：M1 的 `seek(to:)` 会立即发布 `currentTime = target`，桥侧 pendingSeek 会随即解除，
  属于防御性重复，不冲突。
- [x] `pauseRender` 停 rAF；`renderState(false)` 加 `folia-frozen` 类停 CSS 动画并停 rAF — **代码完成**。
  `folia-frozen` 下 `animation-play-state: paused`、heavy-canvas 隐藏；占位壳 CSS 已含该规则。
- [x] `setRenderActive` 幂等、恢复必重发；页面未加载完时缓存待发、didFinish 时补发；
  初始未打开播放页时 renderState 为 inactive — **代码完成**。
  `applyRenderActive` 幂等（`lastSentRenderActive`），未加载时进 `pendingRenderActive`，
  didFinish 时先补发再推快照；`folia-bridge.js` 加载时不自启 rAF，初始即 `folia-frozen`。
- [x] 全量状态快照 `pushSnapshot`（`WebSnapshotDTO`）取代逐字段补发 — **代码完成**。
  track（含 isLiked/artworkRef）、lrc、renderActive、theme（含 backgroundMode）、
  queue 当前±3 摘要、initialTime、rate；didFinish/reload 恢复与切歌统一走快照。
  歌词来源：桥在切歌时向 `EdgeOneAPIClient.fetchLyricText` 现取网易云歌词（已接好，
  失败记 "" 不再请求，到后经 `pushLyricsEvent` 补发）；QQ/酷狗/本地暂无歌词源，
  isLiked 默认 false（`DatabaseManager` 无收藏查询方法，见“未落下的项 4”）。
- [x] 恢复即推锚点 — **代码完成**。中心 `isActive` false→true 时桥补发一次锚点；
  另暴露 `repushAnchor()` 供中断恢复 play 后调用（引擎 KVO 翻转时 `$isPlaying`
  订阅已会推一次 state 锚点，双通道不冲突）。
- [x] 特效页进程自愈 + 防抖 — **代码完成**。
  `webViewWebContentProcessDidTerminate` → reload → didFinish 后快照恢复；
  60 秒内 ≥3 次停自动 reload 并落盘报错（`lastFatalError` + 滚动日志），
  人工重试入口 `retryAfterFatalError()` 已留。
- [x] 透明白闪处置 — **代码完成，待 Miller 真机验收（录屏）**。
  html/body 强制 transparent（占位壳 CSS）；WebView didFinish 前 alpha=0，
  完成后 150ms 渐入。
- [x] 两层时钟口径 — **已记录**。层间允许 0–200ms 相位差，歌词逐字 ±200ms 即合格；
  切歌/seek 事件即时推锚点；不承诺逐帧对齐。**未测**（无真机）。
- [x] 手势穿透框架 — **代码完成（框架 only）**。`PassthroughWebView.hitTest`，
  默认 `passthroughRects` 为空；桥已改用该类创建 WebView（空区域下行为与 WKWebView 一致）。
- [x] 无障碍 / 误触 — **代码完成**。歌词容器禁长按菜单与文本选择（桥 `hardenLyricsContainer` +
  占位壳 CSS/`role="text"`）、装饰层 `aria-hidden`、歌词区 `role="text"`。
- [x] 日志纪律 — **代码完成（node 实测脱敏）**。
  JS gated Logger（release 只放行 warn/error；200ms/rAF 路径零 console 输出；
  环形缓冲上限 200 条）；`log` 动作 fire-and-forget、只发 warn/error、info 不过桥；
  过桥与落盘禁 cookie/token/带签名参数的完整音频 URL（JS 与原生双侧脱敏）；
  原生侧同键每秒 ≤10 条去抖、超限丢弃计数入日志文件；沙盒滚动日志上限 2MB 双文件轮换，
  同步打 Xcode Console（NSLog）。

## §10 M2 播放面构成逐项核对

- [ ] **WebEffect 静态包（真实剥离版）— 未做，见“未落下的项 1”。**
  占位壳已交付（产物文件 `PlayerBottomBar` / `FloatingPlayerControls` /
  `MediaSession` / `<audio>` 字符串 0 命中，`data-folia-transport` CSS 兜底 1 处，
  html/body transparent，`folia-bridge.js` 相对路径加载）。
  真实 Folia 可视化壳须改 folia-major，改动点清单在 `STRIP-PLAN.md`。
- [x] `MiniPlayerView` — **代码完成**。悬浮卡片＋顶部 2pt 细进度条＋封面/歌名歌手/
  播放暂停/下一首；只订阅 `@Published`（`currentTrack/isPlaying/currentTime/duration`），
  未占 `onTimeSync` 单回调。**多播说明**：M1 未提供多播机制，桥与迷你条各自订阅
  `@Published`，互不顶掉，属 Published 订阅兜底（M1 自查亦按此对齐）。
  封面：远程走 AsyncImage，本地 file URL 走 UIImage 加载；测试曲 artworkURL 为 nil
  时显示占位符（M1 已知缺口：搜索接口不返回专辑 picUrl）。
- [x] `FullPlayerContainer` — **代码完成**。原生顶栏（收起＋曲名）＋底部原生 Slider
  精准进度（`isScrubbing` 拖动锁定，松手才 seek）＋上一首/播放暂停/下一首；
  位移用 GeometryReader 实测高度（代码中无 `UIScreen.main` 调用，仅注释提及）；
  spring 动画结束后同步 `webView.isHidden`；`onChange` 用 iOS 17 新签名
  （`{ _, open in }`）。`WebEffectView` 包装 `bridge.webView`。
- [x] `RenderStateCenter` — **代码完成**。app 级，汇总「前台＋播放页展开＋未休眠」；
  前台默认取 UIApplication 通知，另留 `setForeground(_:)` 供 scenePhase 喂入；
  `WebEffectBridge` 订阅中心状态，不再私自 `setRenderActive`（桥内该方法已改为
  私有 `applyRenderActive`，不再对外暴露）。
- [x] 常驻 WebView＋位移切换（零白屏思路）— **代码完成**。WebView 由桥单例持有，
  容器只包装不重建；收起时位移出屏 + `isHidden` 同步，离屏不进合成。
- [x] `MainRootView` 的休眠调度改走中心 — **适用方式调整**。本工程是 UIKit 壳，
  无 `MainRootView`；等价集成已落在 `MainViewController.setupNativePlayerUI()`，
  展开/收起唯一来源就是 `RenderStateCenter.isFullPlayerOpen`。

## 量化自查（实测值 / 未测）

- JS 协议 node 桩实测（`node --check` 通过 + 桩 DOM 驱动）：
  快照 `{initialTime: 12.5, rate: 1}` → `getInterpolatedTime()` = **12.50**；
  progress `{t: 20, rate: 1}` 后 → **20.00**；`lyricLineAt(3)` = 0、`lyricLineAt(6)` = 1；
  未知事件类型静默忽略；`Logger.warn` 过桥消息实测脱敏为
  `…url=https://m801.music.126.net/x.mp3`（查询串 `?auth=…&expires=…` 已剥掉）；
  rate=5 输入后锚点仍以 clamp 后的速率计（`clampRate` 上限 2）。
- seek 延迟、进度一致性（200ms 锚点 vs 实际音频时钟）：**未测（无 Xcode/真机，
  需 Actions/真机）**。只做了代码级核对：引擎 200ms observer、桥 200ms 订阅、
  seek 三件套双份、在线 tolerance 2s（M1 引擎内）。
- Swift 语法：本机逐行自查 + 括号平衡全 0（6 个 Swift 文件：`{}`/`()`/`[]` 净 0）；
  **未经 xcodebuild，见“未落下的项 3”**。注：写入时个别空格被归一化
  （如 `frame:.zero`、`pushStateEvent()}`），语义无影响，已逐行复核。
- WebEffect 产物校验（占位壳）：transport/音频元素/媒体会话字符串 **0 命中**
  （`grep -r "PlayerBottomBar\|FloatingPlayerControls\|MediaSession\|<audio"`，
  仅 `index.html` + `folia-bridge.js` 两个产物文件）；`data-folia-transport` CSS 兜底 1 处。

## 未落下的项及卡点 / 退路

1. **真实 WebEffect 剥离包（Folia 可视化壳）— 未做**。卡点：`build-v7/player/` 是完整版
   （transport 字符串 10+ chunk 命中、含 MediaSession 注册与双 `<audio>` deck），
   构建期剔除必须改 folia-major（新增 `FOLIA_SURFACE=player-visual` Vite 插件 +
   独立可视化入口，见 `Resources/WebEffect/STRIP-PLAN.md`），按任务纪律未自行改。
   退路：占位壳已接通整条链路（桥协议/快照/歌词高亮/主题/队列/冻结），原生播放、
   迷你条、容器均可先行真机验证；真实包获批落地后只替换 `Resources/WebEffect/` 产物，
   桥协议与原生侧不动。
2. **`project.yml` 缺 `Resources/WebEffect` 资源条目 — 未做（M1/协调员负责）**。
   现状：桥按 `Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WebEffect")`
   加载；若工程未把该目录打进包，桥会打日志 + `assertionFailure`，不静默白屏。
   需补的一行（folder reference，与现有 `Resources/Web` 同式）：
   ```yaml
   - path: Resources/WebEffect
     type: folder
   ```
   加在 `targets.Folia.sources` 内。M2 按任务纪律未改 `project.yml`。
3. **xcodebuild 编译 — 未测**。本机无 Xcode。已知待编译验证的点：
   `QueueManager` 未标 `@MainActor`（M1 特意如此，避免 M2 非隔离上下文调用报错）；
   `@Published` 订阅、`guard let self else` 简写、`onChange(of:)` 双参签名、
   `PassthroughWebView` 子类化 WKWebView、`UIHostingController` 泛型具名化均按 iOS 17 /
   现代 Swift 写法核对过，但未经编译器验证，**不承诺编译通过**。
4. **歌词 / 收藏字段现状**：歌词已接通网易云现取（桥内缓存 + 后到补发），
   QQ/酷狗/本地无歌词源；`isLiked` 默认 false（`DatabaseManager` 只有 `upsertTrack` /
   `fetchTrack`，无收藏查询方法；收藏切换回调 `onToggleLikeRequested` 已留待 M3 注入）。
   快照里 `lrc` 为 "" 时占位壳只显示曲名，不报错。
5. **锁屏 / 后台 / 白闪 — 代码完成，待 Miller 真机验收**。GitHub Actions 测不了
   锁屏与后台音频，禁止冒充已验。相关真机验收点：TC-01（在线单曲出声＋后台续播）、
   TC-02（seek 精准：本地 .zero / 在线 2s）、TC-05（锁屏/控制中心/耳机线控）、
   冷启动/切页无白闪（真机录屏）。
6. **`onTimeSync` 单回调现状**：桥改走 `@Published` 订阅，未占用该回调；M1 自查已按此对齐
   （M1 在引擎注释中写明该回调“供 M2 WebEffectBridge”，但实际对齐清单以 `@Published`
   为准）。该回调目前无任何订阅方，属闲置单消费者槽位，不影响功能。

## 与 M1 的接口对齐（M1 落地后逐项复核）

- `PlaybackEngine.shared.$currentTime / $isPlaying / $currentTrack / $playbackState`
  → 均为 `@Published`，桥已订阅；`togglePlayPause()` / `seek(to:)` 均为主线程方法，
  桥回调在主线程，符合。
- `QueueManager.shared.$queue / $currentIndex` → `@Published`；`playNext(manual:)` /
  `playPrevious()` 为同步方法，内部经 `runOnMain` 回主线程。
- `FoliaTrack` 字段与 `AudioSourceType`（netease/qq/kugou/local）与桥/迷你条用法一致；
  `artworkURL: URL?`，无 `displayArtworkURL`（docx 旧名，未用）。
- `EdgeOneAPIClient.fetchLyricText(songId:)`（网易云 `/lyric`，自 strip `ncm_` 前缀）
  已被桥调用；`QueueManager.playTestQueue()` 可作闭环入口（M1 留的测试队列）。
