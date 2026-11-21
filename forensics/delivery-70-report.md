# (70) 交付报告 — 删 17 式原生移植 / 取证修复六条 / 问号改灯泡

- 分支：release-70（自 release-69 / 1d84819f），CFBundleVersion 70。
- 依据：forensics-2026-11-21-67-uitaps.md（A/B/C 取证）、forensics-2026-11-21-67-webruntime.md（运行位结构）、delivery-67-report.md。
- 状态口径：以下均为**代码已改＋静态自检过**；编译以 CI 首轮为准，本机无 Swift 工具链；真机未验，不预宣通过。

---

## A 组 · 删 17 式原生移植（Miller 真机验网页切换后下令）

### 结构改动

- **注册表**（LyricStageProtocol.swift）：17 式 `factory=nil`、`isNativeAvailable=false`、摘 `tuningPanelFactory`；新增只增计算属性 `LyricStageStyleInfo.isStagePresentable`（原生渲染或网页嵌入任一可呈现）与 `LyricStageRegistry.isStagePresentable(_:)`。machi 的 `isLocked=true` 保留（锁定语义不变）。自有四式（调频 tuning／深廊 corridor／残光 afterglow／汪汪队 petconcert）注册行与渲染器**一行未动**。
- **运行位收敛**（StageRuntimeStore.swift 整文件收敛）：运行方式自此由注册表 `hasWebRuntime` 唯一决定——17 式恒 `.web`、自有四式恒 `.native`；`setRuntime` 删除（唯一调用点是选择器切换钮、已摘），遗留键 `folia.stage.runtime67.*` **不再被任何代码读取**、留盘无害化，任何残值都不会让已删渲染器复活（注册表 factory 已为 nil）；`styleruntime` 面包屑随之退役。
- **StageStyleStore**：`effectiveStyleId()` 的「已迁」判读由 nativeStyleIds 改为 `isStagePresentable`——**关键防坑**：若直接翻 isNativeAvailable 而不改此处，用户已选的 17 式会被误判未迁、回退 classic；改后 17 式照常成为有效样式、经舞台分流走网页嵌入。`currentStyleIsNative` 改名 `currentStyleIsPresentable`（唯一调用点 StageViewController 的「尚未原生化」提示条同步改判：注册表内样式恒可呈现，提示条只剩未登记 id 的防御情形）。`lastNativeStyleId` 的 nativeStyleIds 校验保留原义（它只记原生挂载过的样式）；style-guard（armStylePending/runLaunchStyleGuard）未动，且 17 式在 StageViewController 的网页路径上原本就经 `armWebStyleProof` 武装同一守卫，不受影响。
- **舞台分流**：StageViewController 的 mountRenderer/swapRenderer 本就先判 `StageRuntimeStore.isWeb` 再走工厂，Store 收敛后 17 式自动全走 (67) 网页嵌入单路，无新增分流代码。选择器与三击轮换、随机池的候选集仍为 20 只（17 网页＋3 原创＋汪汪队，machi 锁定除外），(69) 随机池面板未回改；三击轮换落点分流同步由 isNativeAvailable 改为 isStagePresentable（见 B5）。
- **选择器**（StageStylePickerViewController.swift）：删逐式运行位切换钮（handleRuntimeTap 整段＋onPickRuntime 属性＋StageViewController 两处接线）；徽标改纯展示——锁定「锁」、hasWebRuntime「网页运行」（琥珀）、其余「原生」（绿）；点选分流改 isStagePresentable→统一通路、二者皆无才跳全屏网页舞台；页头说明文案改写为新现实。调参钮机制保留（注册表已无非空 tuningPanelFactory，暂不出现，待自有样式日后挂面板）。

### 审慎项结论：17 式调参面板随渲染器一并删

核查实证：桥 `WebEffectBridge.pushVisual` 只下发 lyricMode/backgroundMode，`WebSnapshotDTO` 无任何调参字段——网页运行不吃原生调参供参；每个 TuningStore 的读者只有自家渲染器与自家面板文件。故 17 式的调参存储＋面板属**原生专属链路**，保留即假生效 UI，随渲染器删除。各 TuningStore 的 UserDefaults 旧键原样留盘、无代码再读、无害；网页侧用其自身参数体系。

### 逐式删/留清单

删文件合计 35：渲染器侧 19＋调参侧 15＋共用 1（ParticleTransition.swift，仅 classic/monet 用）。

| 式（id） | 删·渲染器 | 删·调参 | 留 |
|---|---|---|---|
| 商籁 sonnet | SonnetStageRenderer.swift | SonnetTuning.swift | 注册行（factory=nil）、WebEffect 网页资源 |
| 凝彩 tempera | TemperaStageRenderer.swift | TemperaTuning.swift | 同上 |
| 绘光 lumiere | LumiereStageRenderer.swift | LumiereTuning.swift | 同上 |
| 花火 hanabi | HanabiStageRenderer.swift | HanabiTuning.swift | 同上 |
| 町景 machi | MachiStageRenderer.swift | MachiTuning.swift | 同上＋isLocked=true |
| 雾笺 nebbia | NebbiaStageRenderer.swift | NebbiaTuning.swift | 同上 |
| 流光 classic | ClassicStageRenderer.swift | LegacyTuning62.swift 内 ClassicTuning62（整文件删） | 同上 |
| 心象 cadenza | CadenzaStageRenderer.swift | CadenzaTuning.swift | 同上 |
| 云阶 partita | PartitaStageRenderer.swift | PartitaTuning.swift | 同上 |
| 浮名 fume | FumeStageRenderer.swift＋FumeStageRenderer+Camera.swift＋FumeStageRenderer+Layout.swift | FumeTuning.swift | 同上 |
| 倾诉 tilt | TiltStageRenderer.swift | TiltTuning.swift | 同上 |
| 回环 claddagh | CladdaghStageRenderer.swift | CladdaghTuning.swift | 同上 |
| 莫奈 monet | MonetStageRenderer.swift | LegacyTuning62.swift 内 MonetTuning62（整文件删） | 同上 |
| 时计 pendolo | PendoloStageRenderer.swift | PendoloTuning.swift | 同上 |
| 群唱 cappella | CappellaStageRenderer.swift | CappellaTuning.swift | 同上 |
| 镜台 diorama | DioramaStageRenderer.swift | DioramaTuning.swift | 同上 |
| 静止 still | StillStageRenderer.swift | LegacyTuning62.swift 内 StillTuning62（整文件删） | 同上 |

保留原生（不在删除面）：TuningStageRenderer / CorridorStageRenderer / AfterglowStageRenderer / PetConcert* 全部文件、GlowWordEngine / StageTextKit（保留四式共用引擎）、StagePalette、SyncProbe67（按 styleId 字符串工作、零渲染器类引用，实查）。

删前安全核查：提取待删 35 文件全部 130 个顶层类型名逐个全仓反查，删除面之外**零代码引用**（仅注释提及，已逐处把写成「现行消费者」的注释改口径：SettingsStore 两处、StageEffectSettings 一处）；顶层自由函数仅 fume*（Fume 内部自用）、extension 仅挂被删类自身。

---

## B 组 · 取证修复六条

### B1 封面点动（uitaps A，已定级）— WallPrototypeViewController.swift

- 飞行对象：didSelectItemAt 改采 `WallPosterCell.coverImage`（cell 已加载的 UIImage）＋`coverFrame(in:)`（imageView 实际帧换算到 VC 坐标；imageView 恒占满整卡、展开/收起同式，封面帧即整卡帧）；makeHeroFlight67 以该图新建 UIImageView（.scaleAspectFill＋圆角 8＋不接手触摸）飞行，**不再飞整卡 snapshotView**（标题/控件不再被拉伸放大）。
- 落定：HeroFlight67.finish() 改交叉淡化——真卡 alpha 先复原就位、飞行层 0.12s easeOut 淡出再摘，消灭硬换帧；新增 finishImmediately() 供 animateHeroExpansion 的 stale 抢占路径瞬时收尾（teardown 式摘层＋复原真卡）。收起反向同路（同一 didSelect→animateHeroExpansion 链）。另两处定位落点调用（传 nil）已同步改名 heroImage。
- `wall.hero from=… to=…` 面包屑保留原位。

### B2 白环/宠物召唤（uitaps B）— 按最终档（四度定版）

改档来由（一句）：原定只删视觉（①档），Miller 真机撞到点播台长按与切主题同域打架、圆圈干扰操作后改令整套撤走、召唤另觅落点，中途的舞台长按案与舞台双指下滑案（墙面要拖动）均作废，终定全局角钮双阈值。

**撤除面（点播台）**：
- MiniBarPetOpenGesture 类整删（MiniBarPetStage.swift 文件尾整段）；MiniBarPetStage.attachOpenGesture 方法与 openGestureComponent 属性删；三宿主接线（WallPrototype / HomeWall / StageViewController 的 `petStage.attachOpenGesture(to: bar)`）全摘。
- StageCycleProgressRingView（白环本体）与 StageCyclePressObserver 整类删（StageStyleCycleBag.swift）——二者自 (61) 后唯一消费者就是上述组件。**洗牌袋 StageStyleCycleBag 本体与三击轮换未动**（同文件，pressMoveTolerance/holdDuration 常量保留作沿革口径）。
- 三宿主 0.55s 切主题长按的 (60) 宠物门控（`StickerSettings.miniPetsEnabled` 守卫）同步解除——删后点播台长按只剩切主题一职，关宠态不再被旧门控挡住。自查：台身域再无宠物相关识别器（grep attachOpenGesture/MiniBarPetOpenGesture 全仓零命中）。

**新召唤（全局角钮，新增 PetSummonButton70.swift＋SceneDelegate 安装一行）**：
- 小爪印钮（SF Symbol pawprint.fill）挂主窗口根层（SceneDelegate 在 makeKeyAndVisible 后 install），右下角安全区内：trailing −14、底边距安全区底 88pt——点播台展开态顶边为安全区底 +10+70=80、(68) 全宽条顶边为 +64，两态/两带都不压、留 ≥8pt 间隙；横竖屏同式成立。静置 alpha 0.55 低调；模态设置页盖住它可接受（规格内）。
- 状态双阈值：关态长按 **2.0s** 召唤（双写 on＋当前面 performDropInEntrance＋中震动，`pet.switch on via=corner2s`）；开态长按 **3.0s** 关闭（双写 off＋当前面 performFarewellDismissAll70——本次给 MiniBarPetStage 新增的无演员落点，与长按宠物本体 petPressCloseTriggered 的 dismiss 告别离场同路，`pet.switch off via=corner3s`）。长按宠物本体 3s 关闭老路保留不动。
- 阈值新鲜度：识别器 minimumPressDuration 在安装/每次触发后按开关态设定，且钮的 hitTest（触摸管线最前端、先于识别器计时）每次按下前现读开关刷新——外部路径改过开关后下一次按下恒读现态，不存在 3s 穿过 2s。
- 反馈纪律：只许钮自身——按压中以阈值时长线性渐亮（alpha→1）＋放大（→1.15），触发脉冲 1.22 后系统弹簧回落；**不用圆环**。短按无动作（防误触）；识别器 cancelsTouchesInView=false 不拦页面手势。
- 当前面定位：自钮所在窗口根沿 presented 链到最顶层控制器、只在其视图子树逆序找 MiniBarPetStage（墙在舞台之下时只命中舞台那只）；无宠物层的模态面返回 nil——开关照写、入场/离场由各面自身同步兜底。

### B3 细条点不动（uitaps C①，候选未定案）— WallPrototypeViewController.swift

- 现状实查（先说清）：该宿主 (63) 的 miniBarTapped 内 heal=geom 与 setMiniBarForm 的 `minibar.form host=wallproto … recog=` 三位面包屑**本就都在**；缺口是自愈只挂点按路径——失同步态下点按到不了自愈点。
- 本次新增 `resyncMiniBarFormToGeometry70()`：以 bar 实际高度为真值（≤20＝细条／≥展开高−4＝展开／中间值＝动画中途帧不干预／高=0 首帧跳过），与 miniBarCollapsed 标志不符时落 `minibar.form host=wallproto heal=geom h=… flag=… edge=appear`、纠正标志并经 setMiniBarForm 收口（识别器启停重同步＋minibar.form 面包屑同行落盘）。挂 viewWillAppear 与 viewDidAppear 各一次。**未凭猜改手势链其他部分**；定级仍待下次真机日志一行（minibar.form 的 collapsed 位与 recog 位对账）。

### B4 详情页进度闪帧（uitaps C②，已定级）— StageViewController.swift

- 驱动守卫：viewWillAppear 的 progressDriver.onFraction 接线加 `stageSeekDragging` 守卫（与墙台 !miniSeekDragging 对齐）——拖动中驱动回调只计数不写点，消灭双写轮写闪帧。
- 落点保持窗：stageSeekPanned .ended 先记落点目标秒数＋300ms 截止再 performSeek；保持窗内驱动写点冻结，rawPlayhead（fraction×duration）进入目标 ±0.25s 或超时任一满足即放行，消灭驱动重锚回跳。
- 回归自证：拖动期被挡次数在 .ended 落一行 `seek.guard n=<n>`（无挡下不落、免噪音）；取消/失败路径清零计数。

### B5 三击切特效去提示 — StageViewController.swift

- showStyleCycleToast 整函数、styleCycleToast/styleCycleToastWorkItem 两属性、cycleToNextStyle 内调用与 teardown 内的 toast 收尾全摘。切换链本体（洗牌袋取只、持久化、style.cycle.switch/skip 面包屑、触发震动）不动；落点分流改 isStagePresentable（与 A 组选择器同口径）。

### B6 网页→网页切换一闪黑屏（Miller (70) 追加）— StageViewController.swift

- **定级**（代码实证）：已结算网页态再切网页式时，swapToWebRenderer 的 backing（renderer）为 nil → WebView alpha 恒 1、无任何垫底，页面内自切（旧层拆除到新层首帧之间）全程裸露；网页侧 `index.html` 为 `html,body{background:0 0}` 透明、rendererContainer 无底色（透明）、舞台根视图为黑——清屏帧透出即黑闪。黑来自原生侧底色、空来自页面侧清屏，两头都成立，快照盖对两头同治。
- **盖法**（Miller 口径）：仅网页→网页（webEmbedStyleId 非空且 backing=nil）改走 `installWebSwitchCoverThenPush`——先对当前 WebView 用 WKWebView 官方 takeSnapshot 截图，回图后作不透明覆盖层（容器同帧、autoresizing 跟随）压在 WebView 之上，再下发 pushSnapshot/pushVisual 并 armWebFade；结算与 A 组淡换**同一出口** completeWebFade：首帧回执（ack）或超时（1.8s／冷启 6s、既有口径）任一到，盖与网页层同 0.35s easeOut 交叉淡出后摘除——超时也只淡出不露黑。取图失败（image=nil）无盖直发、退回 (67) 行为；截图在途目标式已被新切换改写则整发作废、不下发陈旧样式。detachWebEmbed 同步清盖。
- **面包屑**：装盖落 `webfx.cover style=<id>`（失败为 `webfx.cover style=<id> miss=1`），结算沿用既有 `webfx.fade via=ack/timeout` 一行对账。
- 未动：原生→网页（有原生垫底）与未结算网页→网页（尚有原生垫底）维持 (67) 直发路径。

---

## C 组 · 问号改灯泡 — WB62HomeWallHooks.swift

- 图标：「?」标题改 SF Symbol `lightbulb` 线框字形（Lucide bulb 同形态；包内无 Lucide 字体资产，以系统同形字形落，底色沿用原蓝紫圆片、40pt 命中面不变）。
- 位置：右下（trailing−14/bottom−96）→ **左上角**安全区内（leading+14／top+10）；右下角自此让给 B2 全局召唤钮，两钮无几何重叠。
- 功能不变：tap 仍走 Ponder62.presentList 导览入口（先 poke 续计时再 present）。
- 显隐状态机：安装即全透明＋起计时；**3 秒无操作自动变淡到 alpha 0.25**（0.5s easeOut；仍可见、仍可点、视图不隐藏不移除）；交互复位＝钮自身点按＋墙面任意点按（新增不消费触摸的 UITapGestureRecognizer 观察器、cancelsTouchesInView=false、与既有手势同时识别放行），每次恢复全透明（0.2s）并重排 3 秒。面包屑沿用 `ponder62.button installed`。

---

## 自检口径

- 删前类型扫描：待删 35 文件的 130 个顶层类型名逐个全仓反查，删除面外零代码引用后才动手（见 A 组）。
- 收口 grep（全仓 Sources）：attachOpenGesture / MiniBarPetOpenGesture / pet.openGesture 零命中；StageCyclePressObserver / StageCycleProgressRingView 仅剩 StageStyleCycleBag 文件头沿革注释；setRuntime / onPickRuntime 零代码命中（仅 StageRuntimeStore 沿革注释）；currentStyleIsNative 仅剩改名说明注释；showStyleCycleToast 仅剩 B5 沿革注释（teardown 残引用已一并摘除，初查时发现并修复）；130 个被删类型名仅剩注释提及（其中写成现行消费者的三处已改口径）。
- 括号平衡：全部改动文件花括号差 = 0；圆括号差与 HEAD 逐文件一致（差值来自注释/字符串，非本次引入）。
- 调用链走查：17 式进台路径（开台 resolveInitialStyle / 选择器 / 三击 / 每曲随机）全部先经 StageRuntimeStore.isWeb 分流网页嵌入，mountRenderer 的 factory 通路只剩自有四式可达；召唤钮双写顺序（先写开关后调入场/离场）与旧组件、petPressCloseTriggered 同序；B6 盖的武装/结算与 handleWebStyleFrame 的 webFadeWorkItem 非空判读兼容（armWebFade 在下发后即武装，回执不可能早于武装）。
- 新面包屑名长度：webfx.cover（11）、seek.guard（10）、pet.switch（10）、minibar.form（12）、ponder62.button（既有）——均 ≤15 字节。
- 未做/本机限制：无 Swift 工具链，**未本地编译**，编译结论以 CI 首轮为准；全部条目未真机验。

## iOS 适配自查

- 横竖屏：召唤钮与灯泡钮均以 safeAreaLayoutGuide 锚定，横屏（点播台居中同宽、台高不变）几何同式成立；B6 快照盖 autoresizing 跟随容器、旋转时帧随容器；B1 飞行帧为点按瞬间实测帧，旋转中途点按与既有 (67) 行为同界（未新增朝向假设）。
- 安全区/灵动岛：灯泡钮左上角在安全区内、避开灵动岛（居中）与状态栏；召唤钮右下角在安全区内上抬 88pt，不压 Home 指示条与台面控件。
- 系统手势：召唤钮长按 cancelsTouchesInView=false、短按无动作，不抢页面手势；灯泡的点按观察器不消费触摸、同时识别放行；B2 撤除后点播台手势面简化（点按链＋0.55s 切主题＋双击），冲突面净减少；B6 盖 isUserInteractionEnabled=false 不拦触摸。
- 深色/字号：两钮均为图标钮（白字形＋深底/蓝紫底），深浅外观下可读性与旧钮同级；无新增文字面。
- 目标机型（iPhone 14 Pro）：几何常量（台高 70／全宽条 64／间隙 8）按现行定版值推导，无小屏溢出新增面。

## 观察项（未在本包范围、未动）

- HomeWall 的 beginPosterTransition（海报卡→曲目墙页面转场）仍以整卡 snapshotView 做共享元素放大——与 B1 是**不同机制**（页面转场＋crossDissolve 衔接、(60)/(62) 另有定版），uitaps A 的定级对象仅为拼贴墙内 HeroFlight67。本包未动；若 Miller 在主页海报点开时也有同感，再立项同法（飞封面图＋交叉淡化）。
- B3 定级仍为候选：下次真机日志看 `minibar.form host=wallproto` 的 collapsed 位与 recog 位是否对齐、以及有无 `edge=appear` 的 heal 行，即可定案或排除形态失同步机制。
