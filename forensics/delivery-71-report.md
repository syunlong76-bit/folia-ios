# (71) 交付报告 — Lattice 队列拼贴（原生新写 MVP）

基线 release-70（d69524bf）→ 分支 release-71，CFBundleVersion=71。
路线：评估 `lattice-route-eval-2026-11-21.md` 第九节，A 技术路线＋C2 交付范围。
规格源：`port-spec-lattice-collection.md` 第一节（Lattice）＋网页版
`PlaybackEntryViewOptions.tsx` / `playbackEntryViewArt.tsx` / zh-CN i18n 逐项对齐。

## 逐项落地（评估第九节 1–10）

1. **QueueLatticeViewController 新文件**（`Sources/Native/Features/Wall/QueueLatticeViewController.swift`，含 tile cell 与 lattice-chrome 两构件）：
   - 打开快照语义：viewDidLoad 取 `QueueManager.shared.queue` 定死为本页快照，cell 只读快照不直读管理器；
   - 订阅 `$queue`（内容变更→整表替换＋dataVersion 显式刷新，id 序列比对防同批重复刷新）与 `$currentIndex`（只刷牌，见第 2 项硬约束）；
   - 空态：居中两行「队列是空的」（17pt/字距）＋「开始播放任意歌曲后，队列会在这里铺开。」（12pt/50%），与 port-spec 文案逐字一致；空队列打开后队列后到自动补定心入墙。
2. **WallLayout 有限队列模式**（`WallLayout.finiteQueueMode` 新模式位，主页墙/曲目墙恒 false、其指纹与 rebase 纪律一字未动）：
   - 有限有序网格：内容 i → 行主序第 i 格（128 方块、pitch 136），一曲一实例、无周期拷贝；列数按视口世界宽高比取 ceil(sqrt(计数×比))；
   - 内容↔窗口映射：枚举按格索引行列裁剪＋overscan 500（port-spec 值；触顶 400 降档 300/150），千首队列枚举成本只随窗口不随总量；
   - **硬约束成立**：currentIndex 不进 WallLayout 任何位置——VC 的 `applyCurrentIndex` 只遍历可见 cell 按新播放头复算段位/当前态逐个重配，不调 refreshInstances、不 reloadData、不递增 dataVersion；队列内容变更才走 dataVersion；
   - rebase 钉展开实例的分支按模式分流：有限模式走原位放大矩形，不误入周期块让位表。
3. **队列 tile cell**（QueueLatticeCell）：封面全幅直角＋底部渐变罩（黑 0→55%）＋左上序号牌（1 起、tabular 数字、底 shade 62%/当前 78%、当前文字变 ThemeSystem62 accent）＋底部歌名/歌手。几何按 port-spec：CELL 128/GAP 8/OVERSCAN 500；字号等比换算（÷128 比值×帧宽）：歌名比 0.21（规格 clamp 22–36px）、≤3 行；歌手比 0.10（规格 13px）单行——等比值在手机帧宽下约 6.7pt 低于可读下限，钳 10pt（见 iOS 自查）。段标记：played 封面压暗 38%、now accent 牌、upcoming 原样。
4. **展开态＋lattice-chrome**：点块原位放大（2 pitch−gap 方块、钳进场内、大阴影语义由 zIndex=1＋渐变罩承担；网页 Lattice 展开即原位放大，不做邻块让位）不直播放；底部 chrome：播放/暂停（展开块是当前曲=切暂停、否则播该块）→上一首→下一首→时间（当前/时长；非当前块显示 0:00/该曲时长）→「打开播放器」（present StageViewController 全屏，与主页墙开台同形态）；整宽直角进度条仅展开块是当前曲时可拖 seek，拖动态守卫＋0.6s 落点保持窗（(70) B4 同款，防驱动覆写闪帧）；双击块＝直接播放，双击当前曲块只落面包屑永不暂停（port-spec 原文）。
5. **定位当前曲**：右上工具钮按当前曲格世界坐标平移相机——复用墙相机模型＋曲目墙同式弹簧（ζ=0.85/ω=6 欠阻尼阶跃、飞行中段钟形微缩放、Reduce Motion 免缩放）；落点自证面包屑 `lattice.focus idx=N ok=0/1`（目标格实例在实例集内=1）。
6. **补档**：`PlaybackEntry62` 加 `.lattice`；`SettingsStore.playbackEntryView` range 0...2→0...3（值位只追加：0 可视化/1 播放详情/2 留在原处/3 Lattice，既有语义不变、无迁移）；`HomeWallViewController.routeAfterPlayback62` 加 `.lattice` 分支（present 队列墙，面包屑 `entry62 route=lattice`，token 沿用既有 entry62）。
7. **设置图卡化四选**（Settings62ClusterA「进入视图」组）：原分段行替换为 2×2 图卡（示意图＋标题＋说明，选中 accent 描边），写盘口径与原分段行一致（同键＋.foliaSettings62AChanged）。示意图照网页版 SVG 构图以色块复刻（160×100 viewBox 等比）。**四档映射（施工前对齐网页版口径）**：

   | 原生值 | 原生卡名 | 网页版 PlaybackEntryView | 落点 |
   |---|---|---|---|
   | 0 | 可视化 | `player`「可视化」 | 舞台 StageViewController（既有） |
   | 1 | 播放详情 | 无此值——原生对 player 的细分页 | 舞台＋播放面板（既有，不删既有能力） |
   | 3 | Lattice（队列拼贴） | `lattice`「Lattice（队列拼贴）」 | QueueLatticeViewController（本包新增） |
   | 2 | 留在原处 | `stay`「留在原处」 | 只起播不跳转（既有） |

   卡序按网页版 OPTIONS 序（player→lattice→stay）把 detail 插在 player 之后：可视化/播放详情/Lattice/留在原处。说明文案：可视化、Lattice、留在原处用网页版 i18n 原文（略缩），播放详情为原生行为实述「打开播放器并直接展开播放面板」。
8. **入口**：缝合工具条数据段尾加「拼」动作格（UISegmentedControl 第四格；非数据段——点按回弹选中态到当前段、只分发回调，SeamSegment 三段状态一字不动；段宽 108→132，工具条总宽 366pt ≤ 竖屏可用 369pt）；HomeWall 接线 present 队列墙。命令面板「导航」组加 `navigate-lattice` 命令（与网页版 command-palette 同名；原生既有命令为 nav.* 前缀，此条按任务书与网页版同名登记），落点同一 present。
9. **砍掉/后置（本包未做）**：暗角、海报灯光、染色、只标当前序号、块右上速记簿/收藏快捷钮、展开条两可配槽——均未接线（设置里 (66) 已迁的暗角/叠色/只标当前等行保持原状、不与本墙联动），后续按 Miller 点名再补。
10. **纪律**：新面包屑名全部 ≤15 字节（见下）；内存共用 NativeCoverLoader 单例（96MB cap），无第二缓存；滚动守 (59) 纪律（缓存键剔除 worldOrigin、同键 invalidateLayout 只换帧、身份变才 reloadData），wall.scroll/wall.pan 逐秒量测以 wall=lattice 在场（判读口径同 (59)：滚动窗 lattice=0/reload ≤1 次每 10s）；相机为有限场钳制（可见窗不出场、每边一格余量、场小轴居中），到边硬停不回弹——有限语义与周期墙无限平移的差别点，真机重点验。

## 新面包屑（token 字节数）

`lattice.open`(12) / `lattice.snap`(12) / `lattice.tile`(12) / `lattice.seek`(12) / `lattice.focus`(13) / `lattice.chrome`(14) / `lattice.rotate`(14) / `seam.lattice`(12)；复用既有 `entry62`、`wall.scroll`、`wall.pan`、`wall.cache`。无新 UserDefaults 键（playbackEntryView 既有键扩值域）。

## iOS 适配自查（iPhone 14 Pro 基准）

- **横竖屏双向独立成立**：网格列数由视口宽高比推导，竖屏（393pt，scale 0.52）与横屏（852pt，scale 0.64）各成一局；工具钮/chrome/空态全约束驱动无写死帧。
- **旋转重排**：走墙旋转冻结纪律（viewWillTransition 置冻结、动画期间零重算，落地一代收尾：重定缩放档、偏移重钉中心单元、原点按新场钳制、尺寸类别变则重算网格），代际守卫防中途反转叠收尾；面包屑 lattice.rotate freeze/land 自证。
- **安全区/灵动岛避让**：返回/定位钮锚 safeAreaLayoutGuide（14/10pt 内缩、44pt 命中）；chrome 底部条高度含 safeAreaInsets.bottom、控件行在其上；墙面本体全屏出血与主页墙同口径（海报墙设计即满幅，工具面已避让）。
- **系统手势不冲突**：墙拖动是 UICollectionView 既有 pan（与主页墙同）；点/双击识别器互 require(toFail:) 分流，不拦滚动；本页为全屏 present，左缘返回手势由系统对模态页的既有口径处理（与舞台页同），返回钮两段式（先收展开再退出）是页内语义非手势劫持。
- **深色可读**：墙底 #090909 近黑、序号牌 shade 62%/78% 底＋白字（当前 accent 字）、歌名白字带阴影＋底部渐变罩，亮/暗外观下均为深底海报面（与网页版 Lattice 实色底一致），无浅底黑字面。
- **字号下限**：歌名等比 11–19pt（展开 20–44pt）；歌手等比 6.7pt 低于下限→钳 10pt、展开 12pt；序号牌等比 5.7pt→钳 9pt；时间 12pt 等宽数字；空态 17/12pt。钳制项在此明记，不冒充规格原值。
- **动画口径**：chrome 显隐与定位飞行均系统弹簧（0.88/0.85 阻尼），无线性匀速；展开帧变经布局弹簧外既有属性呈现（与墙展开同路）。

## 未确认项（如实标注）

- 本地曲目封面：NativeCoverLoader 走 URLSession（http(s)），本地文件 artwork（file://）可能落占位——与主页墙对同类条目的现行表现一致，未在本包改管线，真机以本地曲目验一次。
- >400 首队列：窗口映射为索引算术（设计成立），千首级未真机实测；真机验收按评估第九节第 9 项清单（288 首与千首各一轮、滚动 fps 对照 (59) 判据、切歌刷牌不整墙重算）执行。
- 相机到边为硬停（无橡皮回弹）：有限场语义取舍，若 Miller 真机觉得生硬，后续可加边缘回弹包单独处理。
- 展开块文案底距以帧高 10% 近似 port-spec 的 bottom 152px（那是桌面 CSS 语境值），手机帧下按比例取，未逐字对齐。
- 设置自检：本包无新键、无删行（分段行换图卡行、同键），自检记名行集合不变；真机首启 settings.selfcheck 以 Miller 日志为准。
