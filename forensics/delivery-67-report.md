# (67) 交付报告：网页特效嵌入台面 + §0 同步量测 + 花火钳制 + 封面丝滑放大

分支 release-67（自 release-66 / 35d8c9f 切出），CFBundleVersion 66 → 67。
提交链：faca542（C 组花火，先行）→ eaec321（WebEffect 换包）→ a852c26（A 原生 + B 埋点）→ 4dedb7a（D hero）→ 1b94a80（CI 锚点检查退役 + 摘嵌交互复原）→ 审查修复轮（见文末「独立审查与修复」节）。
CI：run 44900438347 首轮失败于「Check registry patch anchor」（见 §A1 附注，非代码失败）；run 44900516842（待回填结论）。
IPA：`~/workspace/folia-deploy/Folia-3.7-67-unsigned.ipa`（待回填字节数）。**未上传**，待主聊天验包。

---

## A 组·网页特效嵌入台面

### A1 换包（player-visual 纯渲染器）✅
- 构建：folia-major 以 `FOLIA_SURFACE=player-visual` + 前端铁律三项 `VITE_*_API_BASE` 构建（node v24.22.1），产物 25MB（旧 ios-full 包 34MB），整目录替换 `Resources/WebEffect`（旧包备份在 `scratch-67/WebEffect-old-backup`）。
- 纯渲染器收敛（folia-major 侧改动）：`VisualOnlyApp.tsx` 重写——摘除 FloatingPlayerControls（网页自有胶囊条）、UnifiedPanel（玻璃面板）、ThemeQuickEditorHost、usePlayerChromeAutoHide、useBottomLayoutTracking、**useRandomVisualizerMode（随机自选与原生指定样式冲突，必须摘）**、账户 controller 全套；只留 VisualizerRenderer + useThemeController（主题/调色板注入链保留）+ 背景透明口径（native-scene）。`onLyricLineSeek/onBack` 置 noop——手势全归原生（且嵌入态 WebView 在原生侧关交互，见 A2）。
- 组装：dist 的 visual-only.html 更名为 index.html，头部回贴 `<script src="./folia-bridge.js">`（先于 bundle 加载）；folia-bridge.js 为壳侧手工维护文件（本包带 A5 改动，见下），连同 runtime-config.js（与旧包逐字一致）、nebbia-strokes.json（4,485,083 字节，构建插件产出）、folia-cover-sw.js 一并入包。自检：产物 visual 入口 chunk 含 `styleFrame`；全包无 UnifiedPanel chunk（面板已 tree-shake 出局）；桥自检回归路径不变（didFinish 的 `__FOLIA_BRIDGE__` 探活照旧）。
- typecheck：`npm run typecheck` 全过（修 1 处 words 可选收窄）。lint 未跑（隔离环境需单独 install；构建与 typecheck 已过，留报告明示）。
- **附注（CI 首轮失败定案）**：首轮 CI 失败在编译前检查步「Check registry patch anchor」——WallRegistryPatch（3.6(7) P1，钳制网页墙解码登记表）本体自 3.6(8) 起已停用（`LocalServer.swift` isEnabled=false、代码保留备查），其锚点目标是全量前端包的 wall chunk；换 player-visual 后 wall chunk 整体离包，锚点无对象可命中。处置：CI 检查步退役并在 workflow 与 Swift 注释双处留痕（不是放行失效补丁——补丁本体停用已两年，目标代码已离包）。
- **连带变化（须 Miller 知情）**：全屏「网页版播放页」（选择器第 3 段入口）与嵌入面共用同一 WebEffect 包——换包后全屏页同样是纯渲染器（只有特效、无网页胶囊/面板）。嵌入台面是本包定版形态，全屏入口保留为「同特效全屏看」的通道，网页自有播放 UI 不再存在于包内。

### A2 内嵌宿主 ✅
- `StageViewController` 新增网页运行装配路：WebView（桥单例）经 `embedWebView()` 常驻进 `rendererContainer`，与原生渲染器 view 同级；`mountRenderer` 按运行位分流（网页→`mountWebRenderer`，不建原生渲染器）；`swapRenderer` 三路分流（→网页走嵌入淡换、网页→原生走既有转场后摘嵌、原生→原生原链不动）。不走全屏 modal、不跳网页播放页。
- 进出舞台口径与原生一致：关台 teardown 时 `detachWebEmbed()` 摘回桥侧（页面不销毁），嵌入态清零，WebView 交互标志复原（防污染共用同一实例的全屏宿主）。
- 嵌入态 WebView `isUserInteractionEnabled=false`：触摸全穿透到 rendererContainer（三击轮换等原生识别器照常收触）。

### A3 注册表与标注 ✅
- `LyricStageStyleInfo` 新增计算属性 `hasWebRuntime`（网页 17 式为真；原创三稿 tuning/corridor/afterglow 与 petconcert 为假，注册行零改动）。
- 新 `StageRuntimeStore`（StageRuntimeStore.swift）：每式运行位持久化（UserDefaults `folia.stage.runtime67.<id>`），**缺省原生**——原生移植是已验兜底，网页运行逐式由用户切换、验过再定版；切换落面包屑 `styleruntime`（12 字节）。
- 选择器：网页 17 式行徽标按运行位显示「原生」（绿）/「网页运行」（琥珀）；行内新增运行位切换钮（钮面写目标：当前原生显示「网页」、当前网页显示「原生」），调参钮右移让位；锁定样式（machi）无切换钮、徽标仍为「锁」。切到当前样式时经新回调 `onPickRuntime` 让舞台立即按新运行位重呈现（两处选择器接线点——顶栏 styleTapped 与命令面板 presentStylePickerForPalette——均已接）。
- 舞台胶囊：`refreshStyleButton` 标题在网页运行时追加「 · 网页运行」。
- 三击洗牌袋：袋全集不变（全部未锁样式同一袋语义，StageStyleCycleBag 未动）；轮换落点经 applyNativeStyleSelection → swapRenderer 按运行位分流，网页运行样式在台面内嵌切换、不跳全屏；轮换浮签（toast）对网页运行样式同样追加「 · 网页运行」标注。

### A4 无缝编排 ✅（一处口径偏差已注明）
- 指定样式进入：嵌入/换装时桥 `pushSnapshot()` + `pushVisual(lyricMode: styleId)` 双推，页面按原生指定样式走，不落网页上次自选（didFinish 重载后亦补推，见 A6）。
- 首帧回执：网页侧新增——VisualizerRenderer 加可选 prop `onStyleFirstFrame`（观察 styleSwitch 最新层：waits 落定即该层首帧已画出，每层只报一次，其他宿主缺省不报、行为不变）；VisualOnlyApp 经 nativeTransport 新消息 `styleFrame {styleId}` 回原生；桥 `handleNativeMessage` 新 case 落 `webfx.frame style=<id> dt=<ms>`（visual 下发→回执端到端）并转交舞台。
- 淡换纪律：原生→网页换装时旧原生渲染器**留作垫底不先拆**，WebView alpha 0 嵌入；回执到才 0.35s curveEaseOut 淡入、淡入完成才拆垫底渲染器（汪汪队迁移等生命周期随 unmount 在淡换完成后结算）。网页→网页：WebView 已在台面，页面自切，回执只作量测。
- 超时兜底：1.8s 未回执落 `webfx.ackto` 并照样淡换（不黑等）。**偏差注明**：审计稿写 600ms，本包取 1.8s——网页侧慢样式首帧等待上限 FIRST_FRAME_LIMIT_MS=1500ms（源码实测口径，浮名首排可达 1.3–1.6s），600ms 会在慢样式上抢跑露空档；旧帧全程垫底，1.8s 只是最晚放行点、不是等待常态（回执实测 dt 以 webfx.frame 为准）。

### A5 YRC 过桥 ✅
- 桥 DTO 只增字段：`WebSnapshotDTO.wlines: [WordLine]?`（{t,e,text,words:[{s,d,w}]}），快照与 lyrics 事件双路携带。
- 数据来源：桥既有取词路径（LyricRepository.Entry，与墙面/舞台同一张合并表）在 `fetchLyricsIfNeeded` 回填时同步转 DTO 入 `wordLinesCache`，落面包屑 `bridge.wlines n=<行数> w=<有戳行数> src=<yrc|mixed|uniform|none>`（13 字节）。词戳为仓库已 rebase 到 LRC 行界的合并结果——网页与原生舞台同数据同时刻，网页不重解析 YRC（不产生第二套时刻）。行尾口径：下一行行首，末行取词尾/曲长兜底。
- 网页侧：folia-bridge.js 的 setLyrics 增第三参 wlines 并透传进 folia:lyrics detail（快照/歌词两路）；useBridgePlayback 采纳后 `lyricDataFromWordLines` 构造 LyricData（有戳行直用真戳，`isWordByWord` 按实置位；无戳行用网页自家 `buildTimedWords` 合成，与 parseLRC 同口径）。wlines 缺失/为空时完全回退原 LRC 解析路径，行为与旧版一致。
- 边界：lyricsProvider 注入路径（现行生产无人注入，恒走仓库路径）不带逐字载荷——如实标注。

### A6 保温与内存 ⚠️（机制落地，量测待真机）
- 看门狗：既有进程终止退避重载链（[0.6…30]s + 快照遮罩 + 不可见推迟）原样复用；嵌入态新增落屑 `webfx.kill style=<最近指定式>`，与重载链对位判读。
- 重建后状态恢复：didFinish 在 pushSnapshot 之后、嵌入态下补推最近指定样式（`webfx.repush`），页面自持久化样式不得覆盖原生指定。
- 内存：嵌入装配点落 `webfx.mount … ` + StyleOpenTrace.memoryFields()（phys/avail 同口径采样）。**静态不可实测项如实标注**：WKWebView 内容进程足迹不在 App 进程 footprintMB 内，≤450MB 硬线的网页进程份额须真机以 Instruments/系统诊断口径另测；本包只保证 App 进程侧采样点已就位（webfx.mount 与 stage.style.footprint 同表对读）。

### A7 时钟 ✅
- 桥时钟模型未动（200ms 锚点 + rAF 插值 + epochMs 扣投递延迟 + cue 钉锚，与原生 PlaybackAnchor 同构）。
- 端到端量测：`webfx.push`（visual 下发点）→`webfx.frame`（回执，带 dt ms）成对；`webfx.per5` 每 5 秒一行锚点采样（t/seekSeq/墙钟），与 B 组同表判读。

### A8 spectrum
不在本包（单独立项），未动、未阻塞。

---

## B 组·§0 同步量测埋点（纯日志，未动任何 lead/偏移）

新文件 `SyncProbe67.swift`（音频三读数 + wordSrc 分组 + 格式化，单一收口）。落点清单：

| 面包屑 | 字节 | 落点 | 内容 |
|---|---|---|---|
| sync.snd | 8 | StageViewController.logStageLineIfChanged 翻行支 | judge/raw/sndEst(=raw−outLat)/dJudge/dSnd/route/outLat/ioBuf/wordSrc/style/墙钟，与既有 stage flip 同帧 |
| sync.snd0 | 9 | reanchor() 全量（arm 标记区分瞬态/漂移） | raw/route/outLat/ioBuf/墙钟 |
| sync.setl | 9 | performSettle()，与既有 stage settle drift 同点并行一行 | drift/judge/raw/route/outLat |
| sync.per5 | 9 | frameStep 每 5 秒 | judge/raw/dJudge/route/outLat/wordSrc/style |
| tick.pos | 8 | frameStep 每 30 帧（0.5s@60fps） | pos/raw/墙钟/style。**采样口径注明**：§0 原文「每 tick」会以 60 行/秒淹没 2MB 日志环，改 30 帧采样，翻行邻域精度由 sync.snd/flip.cmt 保证 |
| flip.cmt | 8 | 渲染器翻行提交点（见下覆盖表） | style/idx/judge/墙钟 |
| flip.up | 7 | 追赶机构收敛点（见下） | style/idx/judge/墙钟 |
| sweep.ph | 8 | loadLyrics 落定（网络解析路） | r(singingRatio)/wordSrc/行数——相位误差来源点记账，与既有 sync.probe sweep50 实测过线对位 |
| est.src | 7 | mountRenderer 装配点 | 浮名/回环/莫奈=private（私有估算器，plan §0 定性）、其余原生=unified、网页运行=web |
| webfx.push/frame/per5 | ≤10 | 桥（见 A7） | 网页通路端到端延迟一组 |

flip.cmt/flip.up 覆盖（按机制所有者接线，逐帧检查均只在 pending 时执行、无逐帧格式化）：
- 凝彩 tempera：cmt=shot 提交点；up=position 越过本 shot 末字形 reveal 时刻（settle 链终点口径）。
- 倾诉 tilt：cmt=行切换点；up=级联末段亮起帧。
- 莫奈 monet：cmt=active 行变更点；up=焦点行轨道弹簧 presentation 层 y 落回模型位 0.5pt 内。
- 回环 claddagh：cmt=中心行变更点；up=环弹簧 |值−目标|<0.01 rad 首次达成。
- 时计 pendolo：cmt=焦点目标变更点；up=表盘弹簧 |值−目标|<0.01 首次达成。
- 流光 classic / 心象 cadenza：直达型，cmt 与 up 同点落盘作零追赶基线。
- 浮名 fume：cmt 已落；**up 未落**——相机目标在 FumeCameraState.step 内部计算、不对外暴露，收敛 ε 判定须改相机模块接口，本包按「根因/接口未定级先停」纪律标注留待判读轮立项（代码内同注）。
- 其余样式（sonnet/lumiere/hanabi/nebbia/machi/partita/cappella/still/diorama/三稿/petconcert）：本轮未逐式接 cmt/up；判读先行覆盖已报「慢」的全部样式与机制所有者，其余以 sync.snd（宿主翻行同帧，全样式通用）兜底分组。

红线遵守：未动任何样式 lead/偏移/收口逻辑；全部新增代码只读状态、只写日志。

## C 组·花火钳制 ✅（faca542，先行提交）
- `HanabiStageRenderer.hanabiPlanBurst` 内全部 `n−x` 差值钳制：kiku/botan 的 main、ring 的 core、heart/star 的 core（原 trap 点）、willow-ring 的 outer 均改 max(0,…)，palm crumbs 原已钳制；3526 行的另一 switch 无同类减法。
- programKey 括号修复：原 `snapshot.track?.id?? "" + "|"…` 因运算符优先级使歌词行指纹不进 key，现改 `(snapshot.track?.id?? "") + "|"`。

## D 组·封面丝滑放大 ✅
- 落点：WallPrototypeViewController（曲目墙；主页墙歌单卡走 seam 转场、不在本组范围）。
- 采集：didSelectItemAt 在突变（expandedInstanceId 写入）**之前**采被点卡快照（snapshotView，整卡——封面 imageView 本就占满卡面）与源帧（CV 坐标→VC 视图坐标）；压感 transform 先清、从干净态起步（既有行保留）。
- 飞行：`HeroFlight67` 纯叠加层，与布局重排共用同一条 UIViewPropertyAnimator（0.45s / damping 0.86，iOS 系统弹簧口径）——封面从原位长大到展开位、其余卡同曲线让位；收起反向（源/目标恒为同一张卡，飞行期间藏真卡防双影、落定复原 alpha）。
- 目标帧：刷新后目标实例的最终属性帧（layoutAttributesForItem → convert），恒以落定布局为准。
- 围栏核对：①黑页围栏——展开态 rebase＋展开实例钉入已由 (62) 尾波第 2 组落地于 WallLayout.refreshInstances（本包**未改 WallLayout**，飞行层不碰实例集/worldOrigin/contentOffset，飞行中平移不脱节）；②身份变化路径先 reloadData＋layoutIfNeeded 再起飞（无 hero 的旧路径仅多一次强制布局、最终呈现不变），不存在飞向空位；③采集失败/另两处定位落点调用（恒传 nil）走原无飞行路径，展开本体一字不变；④按压 bounce 0.96（applyPressTransform）未动；⑤减动效（FoliaMotion62.reduced(.queueCollage)）时不建飞行层、布局直落位。
- 面包屑：`wall.hero from=<W>x<H> to=<W>x<H>`（9 字节）。

## 硬线自查
- 新面包屑名全数 ≤15 字节：webfx.push(10)/webfx.frame(11)/webfx.ackto(11)/webfx.kill(10)/webfx.repush(12)/webfx.mount(11)/webfx.fade(9)/webfx.per5(9)/webfx.cold(10)/bridge.wlines(13)/styleruntime(12)/sync.snd(8)/sync.snd0(9)/sync.setl(9)/sync.per5(9)/tick.pos(8)/flip.cmt(8)/flip.up(7)/sweep.ph(8)/est.src(7)/wall.hero(9)。
- 未碰取流链；未碰设置线（SettingsViewController 与 (66) 自检分组/重排逻辑零改动——git diff 可验）。
- 未动任何 lead/偏移（B 组纯日志）。

## 自检口径
- 本包不宣称 selfcheck bad=0：真值以 Miller 真机 (67) 首启桥日志 selfcheck.bad 记名行为准（基线重建 key 沿用 (66) 的 folia.selfcheck.baselineReset65）。
- 网页侧自检：typecheck 全过；vite 构建成功；产物静态核验（styleFrame 在入口 chunk、wlines 在桥文件、nebbia-strokes.json 4.3MB 在包、无 UnifiedPanel chunk）。

## iOS 适配自查
- 横竖屏：嵌入 WebView frame=rendererContainer.bounds + flexibleWidth/Height 自适应，舞台横屏时网页面与原生渲染器同容器同几何（网页内 VisualizerRenderer 本就按容器尺寸布局）；旋转时 WebView 随 container 重排，原生样式的旋转冻结口径不涉及网页层（网页层无 lattice）。竖屏同理。
- 安全区/灵动岛：WebView 只占 rendererContainer（与原生渲染器完全同域），不侵安全区；舞台 chrome（顶栏/点播台）为原生层、照旧避让。
- 手势：嵌入态 WebView 关交互，触摸穿透至 container 的原生识别器（三击轮换/点播台手势/系统边缘返回均不被网页吞）；摘嵌时交互标志复原。
- 深色：网页主题由桥 palette 注入（既有链），页面底透明口径不变；选择器新增钮/徽标颜色在深色底（0.09 灰）上为琥珀/绿高对比色。
- 字号：徽标 11pt、钮 12pt 与选择器既有规格一致（沿用 (57) 既有行规格，未新增小字号文本）。
- 基准机型 iPhone 14 Pro：目标帧/淡换均为系统动画 API，无机型特判新增。

## 待真机判读（不预宣通过）
1. 网页运行逐式：切任一网页 17 式到「网页运行」→ 看 webfx.push→webfx.frame 的 dt、台面淡换是否无空档；慢样式（浮名）看 webfx.ackto 是否出现。
2. 网页歌词对齐：YRC 歌看 bridge.wlines src=yrc 且网页扫光与原生舞台同刻；无 YRC 歌 src=uniform 回退行级。
3. §0 一轮数据：同曲分别在原生/网页运行下导出桥日志，按 sync.snd（dJudge vs dSnd）+ flip.cmt/up 分组判读慢在哪段——**量测出数前仍不动任何 lead**。
4. D 组：点封面展开/收起的飞行手感、展开后继续平移不黑页（wall.render.audit 对照）、连点/滚动中点按的竞态。
5. 进程被杀：网页运行中杀后台回前台，看 webfx.kill→重载→webfx.repush 闭环与台面恢复。

## 独立审查与修复（folia-major 工作流：完整功能收尾独立审查一轮）

审查结论「需修后交付」：2 高 4 中 4 低，逐条核实均为实问题，已同包修复（新面包屑仅 webfx.cold 10 字节）：

- 【高·网页】wlines 跨曲不清：切到无逐字源曲目（QQ/酷狗/本地）后网页台面会一直显示上一曲逐字歌词。修：useBridgePlayback 的 onLyrics 中，新曲歌词事件不带 wlines 时清 wordLines（取词落地后原生再发带 wlines 的事件回填）。
- 【高·原生】web→原生延后 detach（0.5s）无代次校验：窗口内切回网页样式会被迟到 detach 误拆新淡换（WebView 被摘、alpha 停 0）。修：调度时捕获 webSwapGeneration，执行前校验未变。
- 【中·网页】首帧回执在 cut 模式是「已提交」非「已画出」：VisualOnlyApp 发送前加双 rAF（至少合成一帧新层）；残留口径如实标注——着色器编译极慢的样式（diorama/machi）回执后仍可能短暂未绘完，旧帧垫底＋0.35s 淡入覆盖大部分，真机以 webfx.frame dt 与肉眼为准。
- 【中·原生】jumpToWebStage 嵌入态不先 detach：关交互标志与宿主视图残留互相污染。修：跳走前先 detachWebEmbed；宿主关闭时若台面无任何呈现层，按返回样式重装（applyNativeStyleSelection，运行位分流）。
- 【中·原生】embedWebView 用 frame+autoresizing 但共享 WebView 的 translatesAutoresizingMaskIntoConstraints 已被置 false：修：embed 时显式置 true、detach 时复原 false。
- 【中·原生】网页样式绕过 style-guard 武装：页面加载失败/JS 崩溃时开台长期空白无回退。修：mount/swap 网页路径同样 armStylePending＋证明状态，ack 回执结算（via=web-frame）、帧＋歌词窗口兜底结算；未 proven 而进程被杀时下次开台按 (44) 回退经典式。
- 【中·原生】冷启页面未 loaded 时 1.8s 超时必迟到、会淡入未就绪页：修：isPageLoaded 为假时放宽 6s 并落 webfx.cold 区分（1.8s 口径只管页面已就绪后的样式首帧）。
- 【低·原生】Monet flip.up 判定读 focusIndex 行而非 pending 行（系统性偏早）：改读 pending 行自身 presentation 层。
- 【低·原生】hero 飞行中再点按/复用竞态：加 activeHeroFlight67 在途引用，新展开先瞬时收尾旧飞行（复原真卡 alpha 再截快照）；飞行落点不跟随滚动的 ≤0.45s 瞬时错位仍在（记账，真机看是否可感）。
- 【低·网页】useBridgePlayback 文件头注释与新版面不符、VisualizerRenderer 首帧 effect 依赖对象身份：注释按实情改写、依赖收窄为 key/waits/value 原始值。

审查核过无问题的点（对账留痕）：wlines 形状/单位与网页 Line 类型兼容、桥链线程与可选值设计、淡换状态机本体（除上述两条）、B 组探针热路径开销、StageRuntimeStore/hasWebRuntime 回退面、摘除项副作用齐备。
