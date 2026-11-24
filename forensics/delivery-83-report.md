# (83) 交付报告 — 2026-11-24

- 分支：`release-83`（自 `release-82` dd942f2c 拉出），施工提交 `4063fdb3`
- CI：`45395833597` **success**（build 2m14s）
- IPA：`~/workspace/folia-deploy/build83/Folia-83.ipa`，**48,724,015 字节**
- 验包五项全过：①ZIP/Payload 结构（Folia.app 在位）；②CFBundleVersion 主 App 与 Widgets 均为 **83**；③Web chunk 含三 base（`/api/netease`、`/api/qq`、`/api/kugou` 均命中 `WebEffect/assets/providerRegistry-*.js`）；④入场母带 md5 `8aed0fb4a5e9a0f500184f8a7dae45a9` 与定版一致；⑤新代码符号入二进制实证（`NativeCoverLoader.prefetch82(source:wall:)` 新签名、`HomeWallViewController.prefetchWall83`、`IslandWave83View`、`wit83.live`、`minibar.fm83`、`wall.hit83`、`dbltap83`、`crash83`、`deck83 mode` 均可检出；`pf83`/`isl.cov83`/`wall.q83` 的日志首段 ≤15 字节、被 Swift 小字符串内联编码、不入字符串表，属正常，已以符号表复核代码在包内）。

## 逐条落点

### 1. 快拖墙面还是黑 —— 根因已证实，按定案修四件
定案（`forensics/log-diagnosis-2026-11-24-82session.md`）：取图管线不慢（dec78 wait/dec 个位数 ms、starve=0），快滑时 cell 存活短于完成延迟、回调被 currentUrl 守卫丢弃，砖面只剩明度 0.23 深色占位成片显黑；配置瞬间有真图的砖仅 29%。

- **①占位明度止血**：`NativeCoverLoader.placeholderColor` 明度 0.23 → **0.45**（饱和/色相不变）。占位图渐变与无缓存兜底底色同源同升，快滑时砖面读作彩色砖而非黑洞。
- **②prefetch82 真接线（如实说明）**：(82) 声称落地的 `prefetch82` **全仓零调用、从未运行，系 (82) 假交付**，本包纠正。两面墙各加 `prefetchWall83(dirX:dirY:source:)`：在 `scrollViewDidScroll` 按滚动方向调用——以相机世界视口为心、运动方向侧扩一屏、余侧扩 0.35 屏，取实例环内条目（queueIndex 去重）按 cell 同式 tier（实例世界 rect × cameraScale × 屏幕 scale → `wallTier`）喂 `prefetch82`（.prefetch 低优先级、跳过已缓存）；触发节流＝实例集身份变化即喂、否则 0.3s。`prefetch82` 新增计数：每次调用落 **`pf83`**（`wall/src/n/trig/tot`：本次入队数、累计触发、累计入队），下轮日志可数。注：两墙原有 UIKit `prefetchItemsAt` 通路与本函数无关、未动。
- **③入墙预热**：数据落地即以 dir=(0,0) 调同一 helper（`src=warm`）——主页墙在 `applyWallData` 末、曲目墙在种子落地与每批分页拼接后，把当前在场实例环封面按已解码档批量喂缓存；warm 即使全命中缓存也落一行 pf83（n=0 可读）。
- **④hit 口径修正**：`WallScrollMetrics.flush()` 在 tile78 同窗新增 **`wall.hit83`**（rate=sync/(sync+phImg+blank)×100，cell 同步命中口径）。`wall.ph82` 的 loader 口径保留，但其按「发出的请求」计、异步回填也算 hit，**结构性高估**砖面真实到图率——自本版起判读以 hit83 为准、ph82 只作管线侧参考。
- 另保留上一轮已落的 `wall.q83`（快滑窗 fly/dec/fmax/did 取证）。

### 2. 双击播放台闪退 —— 已定行、已修（口径升级）
- 定行：Miller 发来 `201414.ips`（解析存 `forensics/crash-diagnosis-2026-11-24-201414.md`）：**EXC_CRASH/SIGABRT，未捕获 NSException（约束激活抛掷）**，非内存/野指针。栈：双击→`openNativeStageFromWall`→present→`viewDidLoad`→`buildLayout`→`buildStageBar` 内部约束段。原嫌疑 `refreshPlayButton`/`refreshLikeButton` 不在栈里，**已排除**。
- 成因：(82) 提交 **90aa29c1** 按「模式钮/爪印不上台」删了 `stageModeButton`/`stagePawButton` 的 addSubview，却漏删 `StageViewController.swift` 原 :3122–3135 的跨视图约束块——两钮 superview 恒 nil、无共同祖先，`NSLayoutConstraint.activate` 必抛，**(82) 开台 100% 必崩**（与 (82) 会话「舞台从未成功打开、present.done 全窗 0 次」互证）。
- 修法：整段删除该约束块（注释＋activate），代码留墓碑注释记成因。两钮存储对象、`refreshStageModeButton` 回刷、爪印回调**全保留不动**。
- 配套复查：①删除后全仓锚点约束引用 `stageModeButton`/`stagePawButton` ＝ **0**（其余引用均为对象自身属性/菜单/回调，安全）；②同型残留全仓扫描（设 `translatesAutoresizingMaskIntoConstraints=false` 的标识符共 180 个）：脚本初筛出 5 个「未见 addSubview 且被锚点约束引用」嫌疑（artView、avatarView、discWrap、qrImageView、tabScroll），逐个核实均为 `addArrangedSubview` 或数组批量 addSubview 装配的误报，**无第二处同型残留**。
- 原计划的 ph83 六处相位行**已取消**（定行后无夹逼必要，未入包；`wit83.live` 名册同步去除 ph 字段）。
- 保留 `dbltap83` 双击全路径同步落盘链（recv→zone→call→guard0/done→appear）与启动时 `crash83` 上一会话尾巴回收，作为本条的运行时自证。
- **验收标准（待真机）**：双击播放台开台成功，且日志出现 `stage.present.done` / `dbltap83 step=done`。

### 3. 关灯点亮带放大＋启动复位（`light83`）
- 放大：`WallPosterCell.applyLightFocusZoom83`——关灯焦点砖的**封面图本体**（只动 imageView、不动整砖布局）以墙面平时点按展开的共享弹簧同参放大（0.45s / damping 0.86 / velocity 0.2，即 `animateHeroExpansion` 同曲线同参数，不另写一版），目标 scale 1.1、焦点砖 zPosition 抬升；焦点转移时旧砖随全墙重刷同曲线收回；configure 直落位、广播重刷走动画；`prepareForReuse` 清 transform/状态防复用带大图。焦点判定与压暗在 `applyLight82` 内同拍收口。`setFocus` 同拍落 `light83 focus … zoom=1`。
- 启动复位：`WallLight82.resetOnEntry83(source:)`——冷启动（AppDelegate，src=launch）与每次回前台（SceneDelegate `sceneWillEnterForeground`，src=fg）自动恢复开灯并清焦点；已是开灯且无焦点时幂等无痕；会话内不进后台则状态不变。落 `light83 reset src=… was=… focus=…`。

### 4. 岛中央簇改版（`isl.cov83`）
- 音符 ♪ 退役，新 `IslandWave83View`：5 根圆角竖条（宽 2.6、间距 1.25、高 16，基线高低 0.44/0.81/0.56/0.94/0.5），播放时各条相位错开 0.07s、0.9s 一轮高低跳动（居中对称伸缩，苹果 Live Activity 风），暂停静止压暗（alpha 0.55）。几何位不变（封面 24×24＋间 5＋声波 18，簇宽仍 47）。
- 横屏隐藏：`positionMirrorCenter81()` 按存根状态统一裁决 `active && !suppressed && isPortrait` 才显示——横屏中央簇整体隐藏（封面与声波都不显示），旋转经 layoutSubviews 自动重裁、转回竖屏自动恢复，不依赖宿主再 publish。
- 见证：`isl.cov83`（page/on/sup/land/wave，含 resend 重发拍）。

### 5. 小白条对齐（`minibar.fm83`）—— 图像量测账
量测对象为 Miller 两张全屏截图（均 1179×2556 px ＝ 393×852 pt @3x，iPhone 14 Pro）：

| 项 | 图三系统 home 横线（实测 px） | 换算 pt | 我方原值 | (83) 改后 |
|---|---|---|---|---|
| 宽 | x 380–799 → 420 px | **140** | 134（三宿主写死） | **140**（三宿主约束＋`DeckLayout82.collapsedTrackWidth`） |
| 高 | y 2517–2531 → 15 px | **5** | 5 | 5（不变） |
| 底边距屏底 | 2556−2532 → 24 px | **8** | 轨带落在屏底上方 15–20 pt | **8**（见下公式） |
| 圆角 | 胶囊形 ≈7.5 px | **2.5** | 2.5 | 2.5（不变） |

- 图一我方收起条同位置量得亮度 ≈89/255（≈白 35% 叠近黑底），与收起轨渲染（轨道白 0.25–0.35、进度 0 时填充为 0）一致，证明图一里那条就是我方轨、错位不在宽高而在**底锚**：(78) 把收起底锚常数改成 24.5 后，轨带（容器高 16、轨底 −5.5、高 5）落在屏底上方 inset−24.5+5.5 … 实算 15–20 pt，比系统带（8–13 pt）高 7 pt。
- 修法：三宿主 `apply…Bottom77` 收起常量改公式 **C = inset − 2.5**（竖屏 inset 34 → 31.5、横屏 inset 21 → 18.5，随 inset 公式化、不再写死常数），轨带恰落 8–13 pt 与系统横线逐项重合；进度填充仍在条内表达。
- 见证：`minibar.fm83`（host/col/tw/th/gap/r/orient），收起态恒落 `tw=140 th=5 gap=8 r=2.5`。

### 6. 播放台按网页版重做（三宿主同构同值）
- 高度：`DeckLayout82.expandedHeight` 与 `MiniBarQuickRowView.expandedBarHeight`（唯一出处）132 → **106**。三段版式（台高 106 实算）：歌名行 top 9（高约 17，底 26）／控制行居台中心（播放 48 → 29–77）／进度行轨底 = 台底 −14（轨 88–92、高 4），段间无重叠；seek 命中带仍锚轨顶 −9、高 27（79–106）。
- 第一行：歌名**居中**（centerX 定心、左右 ≥/≤ 钳 20）；封面/歌手视图保留（刷新代码照常写）但隐藏不上台面；点按分域的「封面区」判定改挂标题帧（点歌名＝定位当前曲，语义与点头像一致）。
- 第二行控制簇：模式钮（左端灰圆 38，UIMenu 四档顺序/循环/单曲/随机，与控制台同源同字、off 压暗、逐钮 `tap82` 落痕＋`deck83 mode` 见证）→ 上一曲 36 → 播放/暂停（**白色大圆 48＋深色字形**，回刷只换图不换 tint/底）→ 下一曲 36 → 列表钮（右端 38，走 `QueuePanelViewController.present` 既有入口）。上一曲/下一曲按 Miller 明令保留（图三网页版无此二钮，以明令为准）。
- 第三行进度：左时间、细轨、右时间、控制台入口（右端 30 圆钮、与轨同心，图三右下 sliders 位）。
- 把手：花朵图与容器 20 → **14**（小圆点量级），领先常量半宽 −10 → −7（三宿主 `set…Progress` 同步）；四主题皮肤本就 13 pt 不动。收起态压平 0.25 旧制保留。
- 舞台侧：既有 `stageModeButton` 是 (55) 模板对象、(82) 起不上台，**不误用**——另加实际上台的 `stageModeButton83`/`stageListButton83`（菜单动作同源、选档后两钮回刷互同步）；`applyStageBarSlots` 的 prev/next 写死宽度 40 → 36 同步。
- 新钮全部加入三宿主 contents alpha/interactive 名单与点按/拖动分域名单；四页同台同尺寸、5 秒收起规则、E 毛玻璃质感不变；(82) 已过的台面控制命中修法（识别器豁免 UIControl＋逐钮 tap82）未动。

### 7. 衔接不回退
控制台、开灯波浪、宠物沉降、岛台词、AI 导演、下一首预备、三击切特效、逐歌记忆、汪汪队规则均未触碰其逻辑；版本号 project.yml 两处（主 App＋Widgets）82 → 83，`CURRENT_PROJECT_VERSION` 不动。

## 见证名册（wit83.live）
`q=1 dbl=1 light=1 cov=1 fm=1 pf=1 hit=1` → `wall.q83` / `dbltap83`(+`crash83`) / `light83` / `isl.cov83` / `minibar.fm83` / `pf83` / `wall.hit83`，均 ≤15 字节。

## 未定案清单（全部待真机/下轮日志，不自宣通过）
1. 黑屏四修的真机效果：快滑时 hit83 rate 是否显著高于 (82) 窗的 29%、pf83 触发/入队计数是否如期落痕——待 (83) 会话日志判读。
2. 闪退修复验收：真机双击开台成功＋日志 `stage.present.done` 出现（本包代码侧已定行删除，仍以真机为终判）。
3. 关灯焦点放大手感（scale 1.1 与弹簧同参）与启动复位时机待真机确认；岛声波跳动观感与横屏隐藏待真机确认。
4. 小白条四项对齐为量测＋公式推导结论，最终以 Miller 截图对照为准。
5. 新台面布局（106 高、模式/列表回台）待真机验收；图标字形仍为 DeckGlyph 临时套（J/K/L/M 待 Miller 挑定后只换工厂出处）。
6. 横屏全项在 (82) 窗无样本，本包横屏相关（岛簇隐藏、fm83 横屏字段）同样待真机补测。

## iOS 适配自查
- 横竖屏双向：台面宽度仍按竖屏定版居中（横屏不拉伸）；收起轨底锚随 safeArea inset 公式化（竖 34/横 21 各自成立）；岛中央簇横屏整体隐藏、旋转经 layoutSubviews 自动重裁；三宿主形态函数横竖屏同式。
- 安全区/灵动岛：收起轨带落系统横线带 8–13 pt（与 home indicator 逐项重合为本条目标）；展开台底锚 −10 不变；岛簇落位仍在岛框中心、未侵系统件。
- 系统手势不冲突：本包未新增手势；模式钮 UIMenu 为系统菜单语义；新钮均为 UIControl、沿 (82) 识别器豁免通路，不与边缘返回/下拉关闭/长按切主题冲突（长按祖先识别器对 UIControl 落点拒收的既有纪律覆盖新钮）。
- 深色外观与字号：台面恒深色毛玻璃（E 定版）；歌名 14pt semibold、时间 11pt，与旧台一致、无低于旧版的可读项；声波条白色对黑岛底对比充足。
- 目标机型（iPhone 14 Pro，393×852 pt）：量测即按本机截图分辨率换算；控制行最宽布局（模式 38＋间隙＋中央簇＋列表 38）在 369 pt 台宽内无重叠（逐项算过：模式右界 52 < 上一曲左界 98.5）。
- 动画：焦点放大用系统弹簧（0.45/0.86）；声波为 Core Animation 关键帧（系统 easeInEaseOut）；无线性匀速/突兀跳变新增。
