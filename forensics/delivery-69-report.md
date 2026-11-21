# (69) 交付报告：控制页签扩容包——随机池可见可配＋时间轴偏移页内直调＋已在队列角标

- 分支：release-69（基线 release-68/a11716a0）；版本 CFBundleVersion=69（project.yml），短版本 3.7。
- 范围依据：borrow-plan-2026-11-21.md 与 ds-review-2026-11-21-borrow-reconcile.md；本包任务书点名三项（P3 随机池、P7 时间轴偏移、P9 已在队列角标——后两项为对账定稿 (68) 账、(68) 任务书未点名顺延至本包，见 delivery-68-report 卷首范围说明）。
- **本包特殊口径：按任务书要求，代码＋报告完成、分支 push 后停手，未触发 CI**——主聊天有一项待 Miller 确认的小改动可能并入本包同出，CI 由主聊天发令后再触发。故本报告无 CI/IPA/验包节，代码级自检为人工逐 diff 复核（本机无 Swift 工具链，类型检查随 CI 首轮验证）。

## 逐项落地

### 1. 随机池可见可配（P3）
- 本体：新文件 `Sources/Native/Features/Stage/StageStylePoolPanel.swift`，含 `StageStylePoolStore`（存储＋派生）与 `StageStylePoolViewController`（多选面板）。
- 入口：样式选择器（StageStylePickerViewController）新增第 1 段「随机池」行（原背景段/网页版播放页段顺延为 2/3 段，段内行与回调逐项对位未动），副文案实时派生计数；点行以导航包裹＋「完成」呈现池面板（与调参面板同形态），关回时选择器 viewWillAppear 刷新入口行。
- 面板形态：页头口径文案「每首歌从选中的样式里换一种，各样式用自己保存的参数。」＋状态行＋全选/全不选钮＋逐只列表（SF Symbol 图标＋中文名＋id＋勾选），点行即切换落存储。
- 语义（DS 对账 Q5 全条）：池只过滤候选集，轮换仍走洗牌袋原语义（一轮不重复、过完重洗、开新轮剔除当前样式即首只≠上轮末只）；袋的 `next()` 候选集改读 `StageStylePoolStore.effectiveCandidates`；池变更经通知 `FoliaStageStylePoolChanged` 只清袋余量，下次取样按新候选开新轮，**当前在播样式不跳变**；计数三处（面板状态行/选择器入口行/面包屑 pool.set）同读 `displaySelection` 一处真源、实时派生。
- 边界态明示：空池/全关＝未启用过滤、回退全集（状态行明写「不会无样式可换」，袋侧 effectiveCandidates 回退全集，无死局）；全选＝未启用过滤（明示）；只选 1 只＝退化明示（「轮换没有可换的样式」，袋侧候选不足 2 只返回 nil、舞台保持当前样式）。
- 键→消费者→生效路径：键 `folia.stage.pool69.selectedIds`（UserDefaults 字符串数组，未配置＝全选）→ 消费者 StageStyleCycleBag.next()（经 effectiveCandidates）＋两处 UI 计数 → 写点仅 StageStylePoolStore.setSelection（面板点行/全选/全不选三路同出口），非假生效。
- 面包屑（均 ≤15 字节）：pool.open（开面板）、pool.set（每次落存储，带 n/总数与 active 旗）。

### 2. 时间轴偏移页内直调（P7）
- 落点：播放面板（PlaybackPanelViewController）控制页签，主题行之后新增「歌词偏移」行——UIStepper＋当前值标签＋归零钮。
- 同键同源：写 `SettingsStore.globalLyricTimelineOffsetMs` 本键，与设置页步进器、命令面板 ±100 三处共用同一存储与同一钳制（读写都钳 ±2000ms）；步进 50ms、范围 ±2000 与设置页步进器逐项一致，不另立第二套数值。消费端不变（墙链 LyricTiming.lead、舞台 positionNow 同读 `lyricTimelineOffsetSeconds`），改完即时生效。
- 双向一致落点：面板回显走统一出口 refreshLyricOffsetRow（回读本键、不靠构建初值），构建时与 viewDidAppear（从设置页改完返回面板）各刷一次；设置页自身 refresh() 本就回读本键。
- 面包屑：panel.offset（12 字节，带 ms 值）。

### 3. 已在队列角标（P9）
- 判定唯一口径：QueueManager 新增 `containsTrack(id:)`，按 track id 查 $queue 当前值，不缓存。
- 落点一·墙面展开卡：WallPosterCell 新增「✓ 已在队列」覆层小片（黑 55% 底、11pt），居展开卡控件行中央（播放/红心钮之间、高 22 定尺），只在展开态且该曲在队列时出；未展开卡面、卡高、标题带、宠物/贴纸落点全未动（DS Q1 护栏：不增卡高不挡宠物）。当前曲必然在队列内、同样出角标，与右上「正在播放」角标并存不互斥。
- 落点二·歌曲行：WorkbenchTrackCell（工作台通用曲目行）行尾加同名角标（主题色描边小片、高 20），出角标时时长标签改靠角标左侧（两条互斥约束切换）；集合行（歌单/专辑的 configure(title:) 路）恒不出。WorkbenchTrackListViewController 的 cellForRowAt 传入 inQueue。
- 即时刷新（不许陈旧）：墙 VC 新增 $queue 订阅 → refreshVisiblePlaybackUI 重配可见 cell；曲目列表页新增 $queue 订阅 → 整表 reloadData（列表量级小）。装载/追加/删减/清空任一队列变更都触发。

## 如实标注（偏差与未确认）
- **池全集为 20 只，非任务书/方案稿写的 17 只**：注册表代码实证——网页 17 式之外还有原创三稿（调频/深廊/残光）与汪汪队开大会同在洗牌袋候选集内，锁定町景除外后可选全集＝20。池子必须覆盖袋的全部候选集，否则 3 只自有样式永远过滤不掉、计数与行为不符。故面板按真实全集 20 只出、计数口径 n/20；社区版的 17 只只是其自家全集。**此偏差请主聊天转 Miller 知情**——若他只要 17 只网页式入池，自有 4 只（实为 3+1，减锁定外共 20 中含 petconcert）将恒在袋内不可过滤，需他明确点头才改。
- 图标为 SF Symbol 按样式映射（注册表条目无图标字段，映射表在 StageStylePoolStore.iconName 一处），非社区版图标资源（借鉴口径：不搬资源）。
- 未做（不在本包范围）：P5 样式页内轮播、P2 调节聚合分组（对账 (69) 原含此两项，本包任务书未点名，未施工，仍挂账）；(68) 全宽条出样零改动（开关缺省关保持）；未碰取流/歌词呈现/特效渲染链与 (67) 嵌入面。

## 自检口径
- 代码级逐 diff 复核：选择器段索引重映射四处（numberOfSections/titleForHeader/numberOfRows/cellForRow/didSelect）逐项对位，背景段三行与网页页行行为不变；袋 next() 除候选来源外逻辑未动（对账剔除/开新轮/面包屑原样）；偏移行写点与设置页同为 SettingsStore 本键 setter（钳制在 setter 内）；角标两落点的 configure 均有默认参数兜底，旧调用方（墙占位 cell、集合行、其余 WorkbenchTrackCell 使用方）编译与行为不变。
- 设置自检：本包未新增设置页行；池键消费者真实存在（袋＋两处 UI），已在上文登记键→消费者→生效路径。
- 待 CI 首轮验证项：全仓类型检查、新文件入包（project.yml 为 Sources 整目录包含，自动纳入）、build=69。

## iOS 适配自查
- 横竖屏双向：池面板/选择器/播放面板均为既有容器内的列表与行，无新几何；展开卡角标帧在 layoutSubviews 按 bounds 居中定尺，横竖屏同式成立；歌曲行角标走 Auto Layout 约束，行宽变化自动跟随。
- 安全区/灵动岛：池面板列表与页头走 safeAreaLayoutGuide（页头 top 锚安全区），无新增全屏覆层，不涉灵动岛。
- 系统手势不冲突：未新增任何手势；池面板点行切换走 UITableView 既有选择通路，呈现/关闭与调参面板同形态（导航＋完成）。
- 深色外观：新面沿用舞台/选择器深色 chrome 口径（深底白字、琥珀色状态行与选择器运行位徽标同色系）；歌曲行角标用 WorkbenchTheme.accent 描边，随工作台主题。
- 字号下限：池面板状态行 13pt、说明 12pt、行主文案系统默认；角标 11pt（展开卡）/10pt（歌曲行）为辅助标记，与既有同级角标（播放角标/选择器徽标 11pt）同级。
- 目标机型 iPhone 14 Pro：池面板页头＋按钮行固定高约 130pt，余量全给列表滚动，20 行无需分页；展开卡角标宽 76 在最窄展开卡（>200pt）中央与两侧 30pt 钮不重叠。
