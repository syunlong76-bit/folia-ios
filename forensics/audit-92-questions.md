# (92) 审计报告 — Miller (91) 真机九问＋日志实证（只读审计）

- 对象：分支 release-91（commit 1682268f）。本报告只读代码与日志取证，未改任何代码。
- 口径：每条给结论（已落／未落／落了但覆盖面有缺口）、证据（文件:行号）、成因（推测处明确标注「推测」）。
- 日志样本：~/workspace/user/files/upload-2c99dec1.txt（1201 行，2026-11-26T16:17:16Z–16:28:02Z，含上一会话尾巴＋本会话两段）。

## 总裁决（对「三样全没生效」的先行回答）

| Miller 质疑 | 审计结论 |
|---|---|
| 点按根治没生效 | **架构已换属实，但有一处实锤缺陷**：(91) 声称迁往「主窗」的浮层宿主与被动识别器，实际挂在了 Fx 窗自己身上（install 时序问题，见第 4/10 节）——点灯看祝福、点任意处补放烟花两条旁路按构造失效；但「特效开着全屏点按皆死」在 (91) 代码里已找不到 (90) 那种整窗吞点结构，此点**未定案**（见第 4 节末）。 |
| 点控制台外不消失 | dim 关闭链代码完整（第 4 节）；但特效卡片层 z 序反转（浮在控制台之上）属实锤，可造成局部点不动＋卡片压控制台。 |
| 特效联动没实现 | **状态源同一、墙面注册链完整**（第 3 节）；但**舞台/播放页零覆盖**是结构性的——在播放页测必然看不到。 |
| p91 面包屑日志 0 条 | 发射通路与 port90 同一套（第 10 节定案）；这份日志窗口内**没有任何能触发 p91 的操作**（无冷启、无控制台、无特效开关），0 条与代码结论不矛盾，但也证明不了 p91 通路真机可用。 |

---

## 1. 播放台图标同步（A4）

**结论：落了但覆盖面有缺口。** 三宿主台面「可见钮」只有播放＋控制台入口两枚（prev/next 三宿主恒隐藏，见下），这两枚字形＋钮面均为 A4；但**点播台附加功能行（MiniBarQuickRowView）整行未同步**——无 A4 玻璃面、多枚字形仍是 SF。Miller 的质疑在这一行成立。

**字形工厂口径**（Deck82.swift:20-87）：A4 手绘只有 coreGlyph（prev/next/play/pause/list，Deck82.swift:89-157）、slidersGlyph91（:158，.console/.sliders 走它）、notesGlyph91（:260，.consoleNotes 双音符）、fxGlyph（:188，fxFirework/fxLantern）。其余 Kind 按工厂设计走 SF Symbols：fxSnow=「snowflake」（:44-47）、fxWind=「wind」（:48-51）、modeRepeat/shuffle/paw/heart/star/layers/speaker/command/help/trash/pencil 全走 SF（:54-87）。A4Chrome91 玻璃面实现在 Deck82.swift:478-503。

**逐宿主逐钮：**

| 宿主 | 钮 | 字形 | A4Chrome91 | 可见性 |
|---|---|---|---|---|
| WallPrototype（歌单墙台） | miniPlayButton | A4 coreGlyph（:842，刷新 :1198） | 有（:863）＋(90) 毛玻璃 | 可见 |
| | miniPrevButton / miniNextButton | A4 coreGlyph（:867/:875） | **无** | **恒隐藏＋宽 0**（applyMiniBarSlots :1141-1150） |
| | miniConsoleButton | A4 notesGlyph91（:892） | 有（:901） | 可见 |
| HomeWall（主页墙台） | miniPlayButton | A4（:1677） | 有（:1698） | 可见 |
| | miniPrev/NextButton | A4（:1702/:1710） | **无** | **恒隐藏**（applySlot :1994-1995） |
| | miniConsoleButton | A4（:1727） | 有（:1736） | 可见 |
| Stage（舞台台） | playButton | A4（刷新 :2157-2158） | 有（:3274）＋毛玻璃 | 可见 |
| | prevButton / nextButton | A4（:3194-3195） | **无** | **恒隐藏＋宽 0**（applySlot :3534-3535） |
| | stageConsoleButton82 | A4（:3264） | 有（:3273） | 可见 |
| | stageModeButton83 / stageListButton83 | DeckGlyph82（.list 为 A4；mode 系列为 SF） | 无 | **未入台面**（对象保留、不 addSubview，:3244-3262 注释与代码） |

**控制台内部**：configureIconButton（ConsolePanel82.swift:916）与 configureTransButton87（:961，顶排 prev/next/play 走它）均加 chrome；fx 四钮加 chrome（:436）；help 钮加 chrome（:475）。但 configureIconButtonSF89（:937）只加 chrome、字形仍是 SF——主题「paintpalette」、去处「square.grid.2x2」、播放器「play.circle」三格至今 SF 字形（设置格已在 (91) 换 sliders 手绘，ConsolePanel82.swift:344-346）。

**缺口（定案）**：
1. **MiniBarQuickRowView（点播台展开时的附加功能行：喜欢/星标/字幕/爪印/面板/命令六钮）未被 (91) 触及**：钮面配置走原生 SF 符号（MiniBarQuickRowView.swift:179-183 `config.image = UIImage(systemName:)`），状态图走 SF 后端 Kind（:253 paw→pawprint.fill、:259 command、:301 heart、:313 star 均为 DeckGlyph82 的 SF 分支；仅 :256 panel 走 .sliders＝A4 手绘）；全文件无 A4Chrome91 调用（grep 0 条）。
2. prev/next 字形虽为 A4，但三宿主恒隐藏（(87) 定版藏进控制台），台面实际上看不到——不算 (91) 漏改，但「同步了」对用户不可见。
3. 收起态细条无钮可漏：收起时封面/标题/歌手/按键整组 alpha=0（WallPrototypeViewController.swift:1921-1932 setMiniBarContentsAlpha），只剩轨道＋花朵把手，把手走 DeckGlyph82.flowerImage（Deck82.swift:306），非 A4 体系、本就不在任务 3 范围。
4. 周边（非台面，供参考）：舞台槽位行 configureStageSlot66 用原生 SF（StageViewController.swift:1429 一带，如 backward.end.fill），alwaysPrev62/alwaysNext62 为 SF chevron.circle.fill（:1291-1299）。

---

## 2. 入场下雪

**结论：未取消——冷启动默认开仍在，(91) 完全没动这条通路。定案。**

证据链：
- 引擎状态纯内存、无持久化：`isSnow` 初值 false（GlobalFx87.swift:347），全文件无 UserDefaults 读写（grep 0 条）——不存在「存了开」的键。
- 默认开通路：`applyDefaultSnow88()`（GlobalFx87.swift:533-537，注释明写「(88) 工坊定案：下雪默认开」）由 **SceneDelegate.swift:20-21 在 scene willConnectTo 里无条件调用一次**——每次冷启动/新场景连接都起雪。
- 引入点：(88) 提交 3b083521（工坊素材定案落码，「下雪默认开＋淡蓝」），对应工坊定案素材值「下雪 开/淡蓝」被写成了冷启默认开，**是的，就是它**。
- (91) 的 diff 不含 SceneDelegate.swift、也不含 applyDefaultSnow88/startSnow 的任何改动（git diff release-90..release-91 核对）。
- 缓解事实：雪起后 12 秒自动停＋融化渐隐（GlobalFx87.swift:1296-1298 stepSnow 计时 setSnow(false)），所以现象是「入场起约 12 秒有雪」，不是常开。

与 Miller 口径的关系（事实陈述）：(91) 任务书十条里没有「取消入场默认雪」一条；他 2026-11-26 22:37 的定版是「四特效全保留」，与「冷启默认开」是两个独立决定——默认开仍按 (88) 工坊定案执行至今。

---

## 3. 特效联动覆盖面＋通路盘点（按收紧口径）

**结论：联动代码落了，覆盖面有结构性缺口（舞台为零）；控制台/引擎/安装三者全局唯一，不存在「他用的不是 (91) 改的那套」——但浮层挂错窗是实锤（详第 4 节）。**

**注册点与覆盖：**
- 封面砖：WallPosterCell.configure 内无条件注册（WallPrototypeViewController.swift:4799 `FxLinkage91.shared.registerTile`），prepareForReuse 注销（:5078）。
- **主页墙在注册表内**：HomeWallViewController 用的就是 WallPosterCell（HomeWallViewController.swift:373 注册、:1145 出队、:1154/:1180 调 `configure(entry:tier:wall:"home")`），与歌单墙同一 configure 路径——主页墙砖确实进联动。
- 歌单 A/B 条目：杂志行/架格 cell 的 configure91 注册（WallPrototypeViewController.swift:5681/:5841），注销 :5664/:5826。
- 宠物：MiniBarPetStage.makeActor 注册（MiniBarPetStage.swift:1096），removeActor 注销（:1427）。MiniBarPetStage 服务于墙宿主与舞台的**迷你台宠物池**。
- **未覆盖（定案）**：舞台演唱会宠物 PetConcertRenderer（独立渲染系、transform 独占，未注册）；灵动岛/停靠层宠物（PetIslandLayer/PetDockLayer，未注册）；**舞台页面本身没有任何砖注册**（舞台不用 WallPosterCell）——在播放页/舞台开特效，联动对象只剩迷你台宠物池，封面联动为零。Miller 若在播放页验联动，看不到是结构必然。

**通路盘点（回应总假设）：**
- 控制台呈现路径**只有一条**：三宿主入口钮全部直达 `ConsolePanel82.present(from:)`（WallPrototypeViewController.swift:1356 与 :1420、HomeWallViewController.swift:2218 与 :2275、StageViewController.swift:2662 与 :3737）。MiniPlayerPanelPresenter 只管队列/设置面板（MiniPlayerView.swift:406/:414/:424），不是第二套控制台；无 WebBridge 呈现的设置台与之并存。
- fx 状态源**同一个**：控制台 fx 钮 fxKindTapped87 调 `GlobalFx87.shared.toggle*`（ConsolePanel82.swift:1105-1116）；FxLinkage91.tick 读的也是 `GlobalFx87.shared`（FxLinkage91.swift:134）。不存在「钮改 A、协调器读 B」。
- install **只有一处**：SceneDelegate.swift:19 调 `GlobalFx87.shared.install(in:)`，install 内有 `if window != nil { return }` 守卫（GlobalFx87.swift:410），无第二处建窗/旧窗复活路径。但 install 抓「主窗」的时机错了——见第 4 节。

---

## 4. 点控制台外消失＋FxOverlayHost91 的 z 序真相

**结论：dim 关闭链本身完整；但 (91) 报告所称「卡片迁主窗浮层」在真机上不成立——浮层宿主与被动识别器实际挂在 Fx 窗（level 1500）上、位于控制台之上。这是本审计最硬的一处实锤缺陷。**

**dim 链（完整）**：控制台以 .overFullScreen 呈现（ConsolePanel82.swift:163-168）；根视图即压暗层（黑 0.45，:175），dimTap 识别器挂根视图（:176-177）；dimTapped85（:745-753）判点在 card85.frame 外即落 `console85 tap el=outside`＋`p91 tap zone=outside` 并 dismiss。控制台内每个钮经 ConsoleFX85.tap 落 `p91 tap zone=<el>`（:1344-1350）。代码层事件链是通的。

**挂错窗（定案，顺序证据）**：
- SceneDelegate.willConnectTo 的执行顺序：**第 19 行先调 GlobalFx87.install，第 105 行才创建主窗**（`let window = UIWindow(windowScene:)`），第 108 行才设 rootViewController。
- install 内部先建好 Fx 窗并设 rootViewController（GlobalFx87.swift:413-424），随后才取「主 window」：`scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first`（:438-439）。此刻场景里只有 Fx 窗一扇窗（主窗尚不存在），该表达式**必然取到 Fx 窗自己**。
- 于是 overlayHost91 被 addSubview 到 Fx 窗（:442-455），被动点按识别器也挂在 Fx 窗（:456-460）。

**后果（按 UIKit 命中规则推导，标注级别）**：
1. **旁路按构造失效（定案级推导）**：识别器挂在 Fx 窗上，只能收到命中 Fx 窗的触摸；普通点按（点灯、点墙面）最终命中主窗内的视图，Fx 窗的识别器不参与该触摸的分发——handlePassiveTap（GlobalFx87.swift:466 起）对正常点按永不触发，`p91 lamp hit` 永不落盘，点灯看祝福与「点任意处补放烟花」双双失效。
2. **z 序反转（定案）**：祝福卡/写灯钮/推荐卡实际住在 level 1500 的 Fx 窗里，**浮在控制台（主窗 level 0 内呈现）之上**；写灯钮在孔明灯开时恒可见（refreshWishButton），其帧内点按会被它截获、下方控制台收不到——局部点不动＋卡压控制台，与 Miller「点其他地方点不动」的描述部分吻合。
3. **FxOverlayHost91 本身不挡 dim**：其 hitTest 仅当点落在可见子视图帧内才交回命中、其余返回 nil（GlobalFx87.swift:304-313）；且控制台呈现时它在另一扇窗、根本不参与主窗内 dim 的命中链。所以「点外不消失」不能归因于这个宿主的 hitTest。

**仍未定案的一点（如实标注）**：「特效开着→全屏点按皆死、控制台不消失」在 (91) 代码里**找不到对应结构**——Fx 根视图已关交互（GlobalFx87.swift:425 `rv.isUserInteractionEnabled = false`，整窗命中应整窗穿透），与 (90) 的旧 hitTest 吞点已不是同一机制。剩余嫌疑（均为推测）：①多场景/场景重连时 install 守卫使 Fx 窗绑定在旧场景、新场景无窗或旧窗残留；②他的操作命中了写灯钮/卡片帧的局部死区被放大感受；③包体与 release-91 的对应关系（但第 10 节日志里有 (91) 独有特征 h=124，倾向就是 91 包）。区分需一份**在他复现点不动的那一分钟内**截取的日志：看 tap82/console85/p91 tap 是否出现即可判读，本次日志不覆盖该时段（第 10 节）。

---

## 5. 宠物召唤按钮丢失

**结论：控制台里的宠物钮不是 (91) 删的——(89)B 就已撤出功能行，(91) 未动它、也没恢复。点播台本体上的爪印召唤钮至今在。**

证据：
- 对象还在、从未入层级：pawButton 声明（ConsolePanel82.swift:61）、configureIconButton 配置＋addTarget（:347-348）、refreshPawButton 回刷（:999-1001）、pawTapped 动作（:1142-1155）全在；但 functionRow 的 arrangedSubviews 是 [modeButton, themeButton89, listButton87, destButton89, playerButton89, settingsButton89]（:354-356），**全文件无 addSubview(pawButton)**（grep 0 条）——钮被配置了但从未被放进任何视图，用户永远看不见。
- 消失点：提交 **669b75b89（(89)B，2026-11-25）**——旧功能行 [modeButton, listButton87, fxButton, pawButton, likeButton, sketchButton] 改为网页 WallTools 6 格构成，paw/like/fx/sketch 一并撤出。代码注释自陈（ConsolePanel82.swift:331-334）：「(87) 的特效/宠物/喜欢/日记本四格撤出本行：…宠物归设置…（paw/like 两钮对象与回刷逻辑保留、不再入行）」。
- (91) 的 diff 对 paw 零改动（git diff release-90..release-91 内无 pawButton 相关行）。
- 仍在的召唤入口：点播台快捷行爪印钮（MiniBarQuickRowView.swift:91 声明、:405-421 pawTapped→PetSummonButton70.performPawToggle77），共享切换核 PetSummonButton70 本体保留（SceneDelegate.swift:120-122 注释）；窗口浮动爪印是更早在 (77)（提交 20792cd2）按 Miller 令退役的，与本次无关。

---

## 6. 烟花卡

**结论：工坊定版参数已落码；卡顿最可能源不在参数、在渲染架构——全屏 CPU 软件光栅＋无帧率上限＋单粒多段描边，三处叠加。**

**参数（已落）**：FxTuning88（GlobalFx87.swift:151-161）：fwSizeMul=0.85、fwDensityMul=1.1、fwGlowMul=1.7、金色默认；爆点光晕 amp 乘 fwGlowMul（:752）；星粒上限 1400（:736 pushSpark 超限丢新）。

**每帧开销（定案，代码事实）**：
1. **全屏 draw(_:) 软件渲染＋无帧率上限**：Fx87RootView.draw（:289-292）调 engine.render（:699 起），每帧整屏 ctx.clear＋四特效全量重绘；引擎 CADisplayLink（:659-665）与联动 CADisplayLink（FxLinkage91.swift:119-123）均未设 preferredFrameRateRange（两文件 grep 0 条）——iPhone 14 Pro 上可跑满 120Hz，等于每秒 120 次全屏 CPU 光栅化。烟花光走 .plusLighter 加色混合（:881），全屏读改写合成。
2. **单粒描边调用量爆炸**：每颗 spark 的拖尾按 hist 逐段单独 strokePath（每段各自 setLineWidth＋stroke，:951-960 一带），再叠一遍宽辉光描边（size×3.6）＋核心描边＋头部椭圆；千级 spark×近十段×120fps＝每秒百万量级路径描边，全在主线程 CGContext。火箭本体每帧用 ctx.setShadow(blur:16) 画（:903-906），CGContext 阴影为离屏通道；光晕每 halo 每帧新建径向渐变填充（fxFillRadial，:863-879）；金雨拖尾 hist 长达 64 点（:990 起）。
3. **联动叠加在同一主线程**：FxLinkage91 的 tick 常驻（只要有 ≥1 砖/宠物注册就不停，墙面场景恒成立），每 tick 做两次字典 filter 分配（FxLinkage91.swift:127-128）；孔明灯开时 updateLanternGlow 每帧遍历全部砖做 cover.convert(to:nil) 坐标换算＋glow 帧/alpha 写（:394-412）；烟花每爆点 fireworksBurst 遍历全部注册砖逐个 convert＋对半径内砖建两段链式 UIView.animate（:445-460），爆点回调挂在引擎每次 burstStar 上（GlobalFx87.swift:754-760），演出期爆点频繁。

另注：因第 2 条默认雪，冷启起渲染环即在跑（雪与烟花同一 draw 通道），烟花不是孤立负载。

---

## 7. 歌词特效横竖屏切换卡帧

**结论：旋转瞬间有三个写死在代码里的重操作，(81) 的盖层管线只是把「侧躺」换成「截图＋等新帧」，固定成本仍在。与 (81) 起的老问题同根：网页歌词层在新尺寸下必须重建渲染表面。**

舞台 viewWillTransition（StageViewController.swift:887 起）逐项：
1. **全屏 WebView 截图**：beginWebRotCover81（:1028-1048）对歌词 WebView 调 `webView.takeSnapshot(with: nil)` 抓全屏快照作转场盖层——整面 WebGL/canvas 表面回读＋位图生成，是旋转第一帧的硬成本。
2. **舞台全量重排＋快照推送**：转场 alongside 里 layoutStage() 全量排版并 pushSnapshot()（:2365-2367，renderer.applySnapshot(makeSnapshot()) 重建并下发舞台状态快照）；若 completion 时几何与转场期所排不一致，再补一整轮（:968 起的 extraRun 逻辑）——一轮旋转可达两次全量布局。
3. **网页层 resize＝纹理重建**：nudgeEffectResize81（WebEffectBridge.swift:1255-1259）向 WebView 派发 JS resize 事件，网页歌词引擎据此按新尺寸重建 canvas/WebGL 渲染目标并全量重绘，揭盖要等新尺寸首帧回执（webfx.rot81 链）。日志旁证（第 10 节样本）：样式切换/尺寸变化附近 webfx.frame dt=356ms（16:25:48）、295/442ms（16:26:52）量级的长帧反复出现，与此机制同类。

附带：GlobalFx87 对旋转**零处理**（全文件 grep viewWillTransition/朝向 0 条），Fx 窗尺寸只在 install 时取 scene.screen.bounds（:411-412）——不是卡帧源，但旋转后特效窗几何是否跟随属未验区（推测风险）。主页墙 viewWillTransition（HomeWallViewController.swift:764）另有墙面重排，量级次于舞台。

---

## 8. 封面点爱心的宠物特效

**结论：原本就没有「点喜欢→宠物反应」这条通路——不是 (91) 绕掉的，是从未接过。定案（全版本回溯）。**

证据：
- 现行全部喜欢路径逐个核对，无一引用宠物/贴纸/舞台反应：封面爱心 heartTapped91（WallPrototypeViewController.swift:4960-4987，只有 Pulse Heart＋LikesStore.toggle＋toast＋云端同步）、A/B 条目爱心（:5731/:5891 同构）、控制台 likeTapped（ConsolePanel82.swift:1158-1177）、点播台快捷行 likeTapped（MiniBarQuickRowView.swift:326 起）、舞台/详情喜欢钮——均止于 toggle＋回刷＋toast。
- 宠物侧零订阅：Stickers/ 与 Stage/ 目录内 grep「foliaLikesChanged91／LikesStore」0 条——(91) 新增的喜欢变更通知没有任何宠物消费者。
- 历史回溯：唯一像「特效」的 PawFirework81（点按爆星＋弹跳）自 (81)（提交 ff8f0de5）引入起**只挂在爪印召唤钮**上（现行调用点 MiniBarQuickRowView.swift:411/:414/:695/:698、ConsolePanel82.swift:1149 均为 pawTapped）；git log -S「PawFirework81.burst」的全部历史版本中，它从未出现在任何 like 处理函数里。
- 所以 (91) 封面爱心新路径（任务 9）不存在「绕过原有宠物通路」一说——任务书本身也没要求爱心带宠物反应。

Miller 记忆的可能来源（推测）：点播台快捷行上爱心与爪印相邻成排，爪印的爆星烟花＋迷你台宠物嬉戏（ambient 行为）与点爱心在同一屏面同时发生，易被记成「点爱心宠物有反应」。

---

## 9. 歌单 A/B 版式点封面黑屏闪屏

**结论：最可能机制已定案到代码路径——点播一次触发至少两次全表 reloadData＋整块歌单头重建，黑底表在重建帧内露空。与第 3 节的 z 序问题不同根。**

证据：
- 点击链不重装配视图：A 杂志式 didSelectRowAt（WallPrototypeViewController.swift:5577-5581）只 deselect＋startQueueAt；B 唱片架 didSelectItemAt 分支（:3871-3874）直调 startQueueAt。applyPlaylistLayout91 只在版式切换时调用（:5491/:5498），点击不经它。
- 闪黑链：startQueueAt（:3742-3764）先同步调 refreshVisiblePlaybackUI（:3761）再 setQueue；refreshVisiblePlaybackUI（:3296-3299）在 A/B 模式下必调 reloadAltPlaylist91（:5521-5531）：杂志式＝`table.tableHeaderView = makeMagazineHeader91()`（**每次新建整块黑底歌单头**，:5534 起）＋`table.reloadData()`；唱片架＝`shelfCollection.reloadData()`。setQueue 后 currentTrack 订阅又调一次 refreshVisiblePlaybackUI——**一次点播≥两次全量 reloadData＋两次换头**，且 $isPlaying 订阅使任何播放/暂停变化都再来一轮。
- 为何露黑：A 表底色纯黑（makeMagazineHeader91 背景 .black、表本体黑底），reloadData 同步拆建全部可见行，封面图异步后到（行内封面占位为白 0.08 底，PlaylistMagazineCell91 init 段）——重建帧内整表先露黑底/空行，即「点封面黑屏闪一下」。B 架 reloadData 同理（定案级别：路径与调用次数为代码定案；「闪的那一帧正是此重建帧」为强推测，无帧级日志佐证）。
- 与 z 序问题（第 3 节原 Q8）的关系：**不同根**。z 序是 applyPlaylistLayout91 装配后切换钮/缝被盖，已由 bringSubviewToFront 处置（:5501-5518）；闪黑是内容重建，不是层级遮挡。两者同在 (91) 任务 8 的代码邻域，但机制独立。

---

## 10. 日志实证（upload-2c99dec1.txt）

**① 发射通路：与 port90 同一套，定案。** 全部 18 处 p91 发射点无一例外走 `Breadcrumbs.log(...)`：GlobalFx87.swift:434（fxwin=pure）、:475（lamp hit）、:1793（wish open）；ConsolePanel82.swift:750（tap zone=outside）、:1349（tap zone=\(el)）；FxLinkage91.swift:140/144/153/157/179（link 系列）；Deck82.swift:92（icon=A4）；WallPrototypeViewController.swift:4968/:5731/:5891（heart）、:5497（plist mode）；WishLanternViewController91.swift:132/:236；WebEffectBridge.swift:2129（toast key）。port90 面包屑同走此函数（GlobalFx87.swift:520、Seam85Views.swift:589）。Breadcrumbs.log 本体（Breadcrumbs.swift:17-23）无开关、无级别过滤、无条件分支——**不存在「p91 用了不同发射方式/被默认关闭」的可能**。注意两处是一次性的：fxwin=pure 只在 install 发一次；icon=A4 有静态守卫 loggedIconA4（Deck82.swift:90-94），每进程只发一次。

**② fxwin=pure 发射点必经，定案。** 它在 GlobalFx87.install() 内（:434），install 由 SceneDelegate.willConnectTo 无条件调用（SceneDelegate.swift:19），且在其后紧跟着 applyDefaultSnow88（:21）。冷启链路上不存在绕过 install 的路径；守卫 `if window != nil return`（:410）只挡重复安装。代码层结论：每次冷启动它必被执行并发射。

**③ 本日志 0 条 p91：与①②不矛盾，但也不构成正证。** 逐项核对本文件内容：
- **全文件无冷启段**：grep「scene.connect」0 条，两段都是进程已在运行中的切片（上一会话尾巴起于 16:17:16 的舞台播放中；本会话起于 16:25:29 的 pet.tick.heartbeat）。fxwin=pure 与 icon=A4 的发射时点（进程启动）整段落在窗口之外。
- **窗口内无任何 p91 触发动作**：console85=0、tap82=0、fx87=0（无人开控制台、无人拨四特效）；他 16:27:57 进设置走的是缝侧栏（日志行 1171 前：`sidebar85 tap dest=settings` 16:27:57.705 → `port90 settings=chips-h/search`），不是控制台；heart 的 193 条命中全部是 pet.tick.**heart**beat，非喜欢动作；plist=0（未切版式）。
- **窗口内确有导航**：home→poster/stage 转场（16:25:47 stage open、16:26:52 presented）、回主页（16:26:53）、歌单缝（16:26:56 port90 seamtilt）、设置（16:27:57）——这些动作本来就不产生 p91 面包屑（p91 只挂在控制台点按/特效状态迁移/爱心/版式切换/点灯/许愿/图标首绘上）。
- **包体是 (91) 的正证在窗口内**：16:25:47.701 `minibar.webrow stage overlay attached h=124`——展开高 124 是 (91) 任务 4 的新值（(90) 为 84）。即：跑的确实是 91 系包，同时本窗口测不到 p91 通路。
- 结论：**0 条 p91 对「发射通路被换掉/被关掉」是反证（通路同一、发射点必经）；对「p91 通路真机是否可用」既不证实也不证伪**——缺的是覆盖他复现故障时段（开控制台＋开特效＋点外）的一份日志。第 4 节「挂错窗」对 lamp hit 的失效推导独立成立，不依赖本日志。

**④ hanabi dt=31399：帧时钟跨后台停顿，非主线程长卡。定案。**
- 出处：日志行 172-173，16:17:47.452Z，style=hanabi 与 style=still **同一毫秒双双**报 dt≈31.4 秒——两个不同样式的帧计时同时跳变，只可能来自共同的墙钟基准被拉长，而非各自渲染耗时。
- 紧随其后（同秒）：`la.fg76 fg=1`、`nowplaying.route begin … armedVia=background`（16:17:47.595-596）——App 正从后台回前台。webfx 帧计时把约 31.4 秒的后台挂起（WebView 被系统冻结）计成了一个帧间隔。footprintMB 同刻 135→156 是回前台后岛层/舞台重建的内存回升（mem tick 16:17:47.521 报 180 后回落），不是这 31 秒里在渲染。
- 反证主线程健康：其前后 tick.pos 连续（29.719 @47.051 → 30.478 @47.810）；本会话 16:26:53.524 的 stage gate 帧统计 mean=16.7ms、p95=16.7ms、n=64。
- 与第 6/7 条的关联：**无直接关联**。hanabi 是网页歌词样式「花火」的 webfx 帧，不是 GlobalFx87 全局烟花（第 6 条）；dt=31399 是挂起伪影，不是旋转长帧（第 7 条）。本日志内与第 7 条同类的真长帧是样式切换/尺寸变化旁的 webfx.frame dt=356（16:25:48.125，lumiere）、dt=295 与 dt=442（16:26:52，fume/lumiere）——0.3–0.45 秒量级、与 swap/resize 机制对位，那才是卡帧判读该用的数。

---

## 附：未定案清单（需新证据才能推进）

1. 「特效开着全屏点按皆死」的 (91) 机制——需故障时段日志（判读点：tap82/console85/p91 tap zone 是否出现、Fx 窗 hidden 状态）。
2. 联动在主页墙真机是否可见——代码链完整，需他回主页墙、开风/雪各录一段屏或导一份含 `p91 link` 判读的日志（开特效瞬间必有 link 迁移行；若 fx 开而 link 行缺，先查 FxLinkage91.tick 是否在跑）。
3. Fx 窗旋转后几何跟随——代码零处理，需横竖屏各截一帧图证。
