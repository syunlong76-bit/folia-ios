# M1 播放内核自查记录（M1-SELFCHECK.md）

实施者：M1 子代理。日期：2026-11-14。范围：只 M1（native-arch.md §13 检查单逐项核对）。
本机为 Linux VM、无 Xcode：凡标「未测」的项均为本地无法验证，需 GitHub Actions
（xcodebuild 编译）与 Miller 真机验收；凡标「代码完成」的项均为静态核对通过，
绝不冒充已在真机上验过。

## 文件清单（本次新增 / 修改）

新增（`ios-shell/Sources/Native/`）：
- `Core/Audio/AudioPlaybackProtocol.swift` — PlaybackState 三态、AudioPlaybackProtocol、FoliaTrack
- `Core/Audio/PlaybackEngine.swift` — A/B 双轨播放内核
- `Core/Audio/QueueManager.swift` — 唯一改曲入口、测试队列、熔断
- `Core/Audio/NowPlayingController.swift` — 锁屏 / 控制中心唯一写入点
- `Core/Network/EdgeOneAPIClient.swift` — Netlify 主 / EdgeOne 备、网易云四方法、Range 探测
- `Core/Network/RangeStreamResourceLoader.swift` — folia-stream Range 切片代理
- `Core/Storage/DatabaseManager.swift` — 四表 + user_version 迁移框架 + upsertTrack

修改：
- `ios-shell/project.yml` — deployment target iOS 17（options / target / IPHONEOS_DEPLOYMENT_TARGET 三处同步）；
  MARKETING_VERSION 3.1、CURRENT_PROJECT_VERSION 2；新增 OTHER_LDFLAGS `-lsqlite3`
  （DatabaseManager 用 `import SQLite3`，系统库需显式链接）。

未动：`MainViewController.swift`、M2 文件、folia-major 源码、Netlify 设置、Info.plist
（Info.plist 的版本键是 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` 变量，
只需改 project.yml；UIBackgroundModes 核对为仅 `audio`，未加 AirPlay/PiP）。

注：`Sources/Native/Features/` 下的 `WebEffectBridge.swift` 与 `RenderStateCenter.swift`
为并行作业的 M2 文件（非本次创建、未改动）。M1 落码时与之做了接口对齐核对（见末节）。

## §13 检查单逐项核对

- [x] 桥 `foliaAction` 注册在创建 WKWebView 之前 — **不适用（M2 范围）**。M1 不含桥代码；
  并行 M2 文件已按此规则实现，本次未核改。
- [x] engine 除 QueueManager 外无调用方 — **已做（grep）**。`engine.load` 调用点唯一：
  `QueueManager.swift:135`（`loadTrackAtCurrentIndex` 内）；`load` 为 internal；
  另 `engine.stop()` 亦只在 QueueManager 内调用。grep 命令与结果见下。
- [x] 中断 / 路由监听已注册；恢复分支先 setActive(true) 再 play — **已做（代码核对）**。
  `PlaybackEngine` 注册 `AVAudioSession.interruptionNotification` 与
  `routeChangeNotification`；中断结束 + shouldResume 时先 `setActive(true)` 再 `play()`，
  激活失败 `NSLog` 报错并直接 return，不静默假装恢复；路由 `.oldDeviceUnavailable` 时暂停。
  未测（无 Xcode，需 Actions/真机）。
- [x] 双轨 observer 各挂 200ms、按 active 取值；状态由 timeControlStatus 派生，无手工 isPlaying 置位 —
  **已做（代码核对）**。`playerA`/`playerB` 各挂 200ms periodic observer 与
  `timeControlStatus` KVO，只认 active 轨；`playbackState` 三态由 KVO 派生；
  `togglePlayPause` 只发意图；`play()`/`pause()`/`load()` 内无 `isPlaying =` 赋值。
  例外说明：`@Published isPlaying` 为 `playbackState` 的派生镜像，唯一写入点在 KVO
  收敛处（`isPlaying = (derived == .playing)`），供 M2 桥订阅 `$isPlaying` 用；
  不是意图式手工置位。见末节「与 M2 的接口对齐」。
- [x] 在线 URL 按 id 现换；DB 无 `remote_stream_url` 播放用途；`streamOrFileURL` 不落库 —
  **已做（代码核对 + 实测）**。QueueManager 播放时按 track id 现换 URL；
  `FoliaTrack` 不含 stream URL 字段；`DatabaseManager.upsertTrack` 不写
  `remote_stream_url` 列，该列仅作元数据缓存、代码中无任何读取作播放地址的路径。
  实测值：2026-11-14 本机 curl Netlify 代理：`/song/url/v1?id=1973665667&level=exhigh`
  回 200、真实 m801 URL、code:200（fee=8 可播）；expi=1200 秒（响应体字段，未逐秒计时）。
- [x] 探测 delegate、响应头判定即 cancel；contentType 按 mime 推导；流式 session 完成即 invalidate —
  **已做（代码核对）**。`resolvePlayableURL` 用 `URLSessionDataDelegate` 探测，
  收到响应头判定 206/200 后立即 cancel，不用 `data(for:)` 拉整首歌；
  `contentType` 按响应 mimeType 或 URL 后缀经 `UTType` 推导，推不出返回 nil（禁硬编码 mp3）；
  流式 session 与探测 session 均在完成时 `finishTasksAndInvalidate`。
  302 策略：默认跟随（m801.music.126.net 实测直连通，无需特殊 header/cookie）。
  未测（无 Xcode，需 Actions/真机拉流验证）。
- [x] 封面缩放在后台队列；失败跳歌有熔断；`requestedLength == -1` 分支存在 —
  **已做（代码核对）**。封面等比缩至 600px 在 `DispatchQueue.global(qos: .utility)` 做；
  失败跳歌 + 熔断：连续失败达 `queue.count`（整队一轮）后 `engine.stop()` 并回调
  `onFatalError`，不无限循环；`RangeStreamResourceLoader` 含 `requestedLength == -1`
  分支（开区间 `bytes=<offset>-`）。未测（无 Xcode，需 Actions/真机）。
- [x] 锁屏只经 `syncNowPlaying(elapsed:rate)` 写入；200ms 周期不写锁屏 —
  **已做（grep）**。`MPNowPlayingInfoCenter.nowPlayingInfo` 的赋值点只在
  `NowPlayingController.syncNowPlaying` 内（两处：有曲 / 无曲清空）；
  200ms observer 只推 `onTimeSync`，不写锁屏；写入点只限切歌/toggle（KVO 收敛）/
  seek 完成/中断/路由/封面后到。`MPNowPlayingInfoCenter.playbackState` 同步设置。
  未测（无 Xcode，需 Miller 真机验收锁屏各项）。
- [x] deployment target iOS 17（project.yml 与 target 设置同步）；版本 3.1 (2) —
  **已做**。project.yml 三处（options / target / IPHONEOS_DEPLOYMENT_TARGET）均为 17.0；
  MARKETING_VERSION 3.1、CURRENT_PROJECT_VERSION 2；Info.plist 用变量引用，无需另改。
  未测（无 Xcode，需 Actions 生成工程后核对）。
- [ ] 文档代码按伪代码对待；`xcodebuild` 编译通过为第一道门禁 —
  **未测（无 Xcode，需 Actions）**。文档（骨架 / docx）代码未整段粘贴，均为按口径重写；
  本机逐行自查过 Swift 语法与 iOS 17 API 可用性，但未经编译器验证，**不承诺编译通过**。
  已知待编译验证的点：`import SQLite3` + OTHER_LDFLAGS 链接、KVO 闭包签名、
  `@Published` 在非 ObservableObject 的 QueueManager 上的 `$queue` 订阅、
  `sqlite3_bind_text` 的 String→CChar 桥接、`withCheckedContinuation` 的 delegate 持有。

## 量化实测值（本次实际测到的）

- Netlify 代理路由实测（2026-11-14，本机 curl，全部 200）：
  `/api/netease/search`（keywords=海屿你）、`/api/netease/song/url/v1?id=1973665667`
  （回真实 m801 URL）、`/api/netease/lyric?id=1973665667`（回 LRC 文本）、
  `/api/netease/playlist/detail?id=19723756`（飙升榜，254KB）。
  结论：客户端 path 前缀定为 `/search`、`/song/url/v1`、`/lyric`、`/playlist/detail`
  （不抄 docx 的 `/cloudsearch`）。QQ/Kugou 的同名路由未实测，见「未落下来的项」。
- 测试曲元数据（搜索接口实测）：id 1973665667《海屿你》，歌手 马也_Crabbit，
  专辑 海屿你，duration 295940ms（295.94s），fee=8。注意搜索接口返回新形状
  （`artists`/`duration`/`album`，非 docx 的 `ar`/`dt`/`al`），DTO 已按实测形状写、
  旧键仅作回退；专辑 `picUrl` 字段实测缺失，故测试曲 artworkURL 为 nil
  （锁屏暂无封面，待 M3 封面链路补齐）。
- seek 延迟、进度一致性、首帧出声耗时、锁屏/后台音频：**未测（无 Xcode，需 Actions/真机）**。
  路线图目标 seek 提交延迟 <100ms，待真机实测后补数。

## 锁屏 / 后台音频（只标代码完成，待 Miller 真机验收）

- TC-01 在线单曲出声 + 后台续播：代码完成，待 Miller 真机验收。
- TC-02 seek 精准（本地 .zero / 在线 2s）：代码完成，待 Miller 真机验收。
- TC-03 队列推进 / 上一首 / 下一首：代码完成，待 Miller 真机验收。
- TC-05 锁屏 / 控制中心 / 耳机线控全项：代码完成，待 Miller 真机验收。
- 冷启动 / 切页无白闪：M2 范围，本次未做。

## 未落下来的项及卡点

1. **xcodebuild 编译验证**：本地无 Xcode，未编译。第一道门禁待 Actions 跑
   `.github/workflows/build-ipa.yml`（已跑通的流水线）验证；若编译报错，优先按
   本文件「已知待编译验证的点」排查。
2. **QQ / 酷狗业务方法**：取流与搜索 DTO 未实测核对。`fetchSongStreamURL(provider:)`
   对 qq/kugou 抛 `EdgeOneError.providerUnverified`（TODO 已写）；`searchRaw` 留作
   M3 核对形状的逃生口。已知：QQ search 用当前参数回 400（参数待核对，arch §6 已记），
   不卡 M1。QQ/酷狗函数源码已确认存在（`edgeone-qq`、`edgeone-kugou` 的
   `[[default]].js` + 模块表），但路由参数与响应体形状未逐项核对。
3. **M1 无 UI 调用方**：本次只落内核，未接任何 UI 入口（M2 桥接通后由桥调用；
   闭环入口已留 `QueueManager.playTestQueue()`，一键装载测试队列并起播《海屿你》）。
   在 M2 接入前，内核在 App 内不会被实例化（单例均为 lazy）。
4. **暂停时不单独落播放流水**：`PlaybackEngine` 在切歌 / 完播 / 入后台 / 退出时
   落 `play_history`（累计 ≥15 秒才记）；单次暂停未单独落库（恢复续听属同一段聆听，
   避免一行多次拆分）。若定版要求暂停即落库，需另行改动（M3 登记项⑤的口径待定版）。
5. **测试曲无封面**：搜索接口不返回专辑 picUrl，测试曲 artworkURL 为 nil；
   锁屏封面链路（搜索→封面 URL→缓存→600px）待 M3 补齐。

## 与 M2 的接口对齐（本次核对发现并已处理）

并行 M2 的 `WebEffectBridge.swift` 订阅了以下 M1 符号，M1 已按此对齐（未改 M2 文件）：
- `engine.$isPlaying` → PlaybackEngine 增加 `@Published isPlaying`（派生镜像，
  唯一写入点为 KVO 收敛处，见上）。
- `engine.$currentTime` / `engine.$currentTrack` → 已是 `@Published`。
- `QueueManager.shared.$queue` / `.$currentIndex` → queue/currentIndex 改为 `@Published`。
- `QueueManager.shared.playNext(manual:)` / `.playPrevious()` → 同步方法，内部经
  runOnMain 回主线程（未用 @MainActor 隔离，避免 M2 非隔离上下文调用时编译报错）。
- `engine.togglePlayPause()` / `.seek(to:)` / `.currentTrack` → 已有；engine 方法要求
  主线程调用（M2 桥回调在主线程，符合）。

## grep 核对命令（可复现）

- `grep -rn "engine.load" Sources/` → 调用点唯一 `QueueManager.swift:135`。
- `grep -rn "AVPlayerItem(url:" Sources/` → 仅注释提及，无直建。
- `grep -rn "isPlaying\s*=" Sources/Native/` → 仅 KVO 收敛处一处赋值。
- `grep -rn "nowPlayingInfo\s*=" Sources/Native/` → 仅 `NowPlayingController.syncNowPlaying` 内。
- `grep -rn "requestedLength == -1" Sources/Native/` → `RangeStreamResourceLoader` 分支存在。
