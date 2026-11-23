# Folia iOS 3.7 (81) 交付报告

- 分支：release-81（自 release-80 拉出），头提交为导演类型修复（见 git log）
- CI：run 45254068784 success（前两跑：45248935138 编译错误一处已修；45251268784 平台侧无日志取消、非代码问题，重跑即过）
- IPA：48,659,131 字节，落 ~/workspace/folia-deploy/build81/Folia-81.ipa
- 验包五项全过：①主 app 81/3.7＋widgets 81/3.7 双对齐；②WebEffect chunk 三基址 /api/netease、/api/qq、/api/kugou 各命中；③入场母带 7,848,834 字节、md5 8aed0fb4a5e9a0f500184f8a7dae45a9；④AppIcon 在位；⑤未签名结构（无 _CodeSignature/描述文件）
- 下载：文叔叔由主聊天上传（本报告不含链接）

## 逐项（分级：全部为「代码已改待真机」，无一项冒充已证实）

### 1. 进度条两态 —— 代码已改待真机
口径按 (79) 验收纠正版：展开＝台内全宽长 seek（lead/trail ±20、高 4、圆角 2、单色、花朵把手保留）；收起＝居中 134×5 短轨（圆角 2.5）。
- 三宿主形态函数（HomeWall/WallPrototype 的 setMiniBarForm、Stage 的 setStageBarForm）由 (79) 的「两态恒 134」改回两态分流；三处 minibar.form 面包屑加 tw= 字段（收起 134／展开＝台宽−40）供下轮日志自证。
- 附带定案：(79) 判读的「舞台展开首呈现全宽长轨」本就正确，本版保持装配原值、形态切换时按两态收口，未另加开台补调。
- 第四套轨审计：队列格子 chrome 条（QueueLatticeViewController 的 LatticeChromeView）是页面级长 seek（frame 制全宽、高 14、主题单色填充），非台面两态对象，不改，审计结论如上。

### 2. 点头像＝切换到正在播放的歌曲 —— 代码已改待真机
红线遵守：agnostic74 仲裁与播放条根链结构一字未动，只改绑定目标。
- HomeWall.locateCurrentTrackFromCover：来源歌单不可知的 miss 分支不再静默——有在播曲目时直达舞台呈现（locate81-stage＋tap.dispatch via=cover81），无曲目时 toast 提示。
- WallPrototype.locateCurrentTrack：无曲目加 toast＋落痕；不在本歌单的 miss 分支由只弹 toast 改为落痕＋openNativeStageFromWall()。
- 两宿主命中路径（飞卡定位＋展开）原样；详情页内点头像不定位、双击进详情均保持现状。

### 3. 特效页旋转流畅化 —— 代码已改待真机
定案（(79) 判读）：舞台原生层有冻结管线、WKWebView 特效层不在管线内。本版把特效层纳入同一管线：
- 冻结拍（viewWillTransition、webEmbedStyleId 非空时）对 WebView takeSnapshot 上截图盖（与 (70) B6 切换盖同法，弹性拉伸），转场期网页层藏在盖下，不再被系统旋转快照当刚性平面倾斜/侧躺/翻转。
- 落定后桥侧 nudgeEffectResize81 催网页层按新尺寸重排，等其首帧回执（handleWebStyleFrame 转交）或 0.9s 超时，交叉淡出揭盖。
- 量测三点 webfx.rot81（freeze/landed/ready via=ack|tmo ms=冻结→揭盖毫秒），下轮日志可量化与主页 wall.rotate（约 0.37s）同标准对账。

### 4. 中间岛呈现重做 —— 代码已改待真机
按 02:29 定版：左宠物·中（封面 24×24 圆角 6＋music.note 音符）·右宠物，岛体内呈现。
- PetIslandLayer.syncMirrorSong79（y=52 岛下 11pt 歌名行）整件撤除，换 syncMirrorCenter81 中央簇（47×26），落位岛框中心、layoutSubviews 随旋转重落；横屏不隐藏（无 isPortrait 门）；抑制期（让位/录屏）隐藏簇并停音符。
- 音符动画：CAKeyframeAnimation 纵跳＋轻摆 0.9s 循环（播放时跳、暂停摘动画半透明）。
- publishMirror 增传封面（IslandLiveActivityManager 传 PlaybackEngine.currentArtwork，只走 app 内镜像、不进 Live Activity ContentState）；自证 isl.cov81（签名＝歌名，变化才落）。
- 已知边界：封面靠引擎现成 artwork，切歌瞬间未就位时先占位底色、随后 publishMirror（app 内 10 秒台词拍等）补上。

### 5. 岛带继续收窄 —— 代码已改待真机
- slotOffset 81→75（宠物内缘压岛框 5pt、缝 1→0）、yieldSlotOffset 90→84、框底外延 2→1；总宽平形态 200→186、让位 218→204（真岛 126＋两只 34pt 宠物的物理排布内再收 14）。几何落痕改名 isl.geo81；hitTargets/落座走 effectiveSlotOffset 自动跟随。

### 6. 町景手势 —— 代码已改待真机（断点已代码坐实）
打包侧逐项核对结论：
- 源码（folia-major createMachiRuntime.ts:317）OrbitControls 挂画布、enablePan/damping 全开；打包产物（2026-11-21 构建）createMachiRuntime chunk 与 three chunk 在位、OrbitControls 实体在 three-BNxyZP4b.js 内——网页侧与打包均无缺失，(79) 审计此点无误。
- 真断点在原生：舞台嵌入态 WebView 交互被整体关死（embedWebView 的 isUserInteractionEnabled=false，(67) 穿透纪律），网页层收不到任何触摸，OrbitControls 无从工作。(79) 审计查了「原生无拦截」却漏了交互总开关本身。
- 修法：仅町景嵌入时放行 WebView 交互（syncWebTouch81，mount/swap 两路落位、detach 时连同 scrollView.isScrollEnabled 一并复原），其余网页样式维持穿透纪律、原生手势链零改动；町景时关 WebView 自带滚动防抢拖。原生三击/单击识别器挂 rendererContainer（祖先），点按仍上达、与画布拖拽/捏合分工。落痕 webfx.machi81 touch=1/0。
- 待真机确认点：WKWebView 放行后三击切特效在町景下的识别率（祖先识别器与 WebView 内部手势共存），若真机三击受扰，下轮改走原生识别器转发。

### 7. 详情页宠物不压列表 —— 代码已改待真机
- 舞台 layoutStage 的 chromeInsets 底部在「展开态＋宠物开启」时再加 52（宠物 48＋间隙 4）宠物专属带：歌词列表/下部构图按 inset 在宠物带上方收尾，宠物只在台顶专属带活动、不再骑台沿压列表；收起态（细条嬉戏定版形态）不预留。落痕 deck.pet81 band=52/0。
- 与第 9 条一并落位：舞台台高统一 70 后 controlsTop 全链按新高推导（原 bottomBarHeight 读数一并摘除）。

### 8. 四套图标随主题 —— 代码已改待真机
- 新文件 DeckIconSet81：原生 CoreGraphics 按样板 24 单位坐标系逐个对形绘制四套（A 圆润粗线/B 圆角实心/C 奶油圆托/D 圆点极简），绑定：花海→C、雪景→A、星空→B、海洋→D、无主题→A（Miller 定案四套全用、一主题一套；具体对应由我方按气质分配如上）。样板左上角占位猫贴纸按点名未用。
- 字形集：play/pause/prev/next/四档模式（顺序＝队列＋播放三角、循环＝回环双箭、单曲＝双箭＋一竖、随机＝交叉线，四档各异守 (55) 撞车口径）/list/heart/star/sliders/command/paw。
- 接入面：三宿主主排全钮（模式/上/播/下/列表/爱心）、浮层五钮（喜欢/星标/爪印/面板/命令，QuickRow 自订主题通知刷新）、台面爪印（DeckPawButton79 字形＋明暗随主题/开关态）。长按台身切主题的通路未动、图标随 .foliaMiniPlayerThemeChanged 整套跟随。
- C 套为原色图（奶油盘＋深棕字形、自成一体），其余三套为模板图随宿主 tint。

### 9. 播放台全页统一 —— 代码已改待真机（施工中途按 Miller 新口径收窄，见下）
统一的落点收敛为两件：①尺寸——宽＝min(屏宽,屏高)−24、高展开 70/收起 16，三宿主同值同式，横竖屏同尺寸；②按钮补齐——只补缺、不动模板。
- 尺寸：舞台台高原由 (62) bottomBarHeight 驱动（48–110 可调，即 (79)「详情页播放台又变大了」的漂移源）——装配/形态/设置刷新/layoutStage 四处读数全摘、恒 70；顶缘拖高识别器保留装配、动作退役落痕（deck.size81 drag=retired）。墙台本就 70/同宽公式，未动。
- 墙侧补件（02:38 点名：歌曲页缺列表钮）：两面墙主排右簇插入爱心（LikesStore＋NativeDataClient 同浮层通路，deck.like81）与列表（QueueLattice 通用入口，deck.list81）两钮，原有钮相对顺序与左块/进度一概不动。
- 口径收窄（重要）：施工中途 Miller 下发 (81) 图标样板口径——「现台模板原样不动：封面头像、歌名、歌手名、时间、进度条全保留；四套样板只换图标」。据此，我原先对舞台台面的移植（摘两端时间标签、播放键改右簇、台内加封面块）已整件回退：舞台台面模板与 (80) 完全一致（居中三键＋两端时间标签＋模式/爪印链＋槽位钮原位），只保留高度 70 与图标换套（第 8 条）。舞台页的爱心在顶栏、列表在命令面板/浮层，本版未往台面塞钮——与新口径冲突处以新口径为准，此取舍请 Miller 验收时确认。
- 自证：三宿主形态收口同落 deck.size81（w/h 数字），下轮日志三行对账即知是否同尺寸。

### 10. 爪印单击切换＋烟花 —— 代码已改待真机
失效根因（代码坐实）：(79) 的 2s/3s 长按识别器挂爪印钮上，而三宿主台身都挂 0.55s 长按切主题识别器（祖先视图）——按住满 0.55s 祖先先行认领（handler 对按键区虽早退、认领照常发生），UIKit 手势互斥下本钮识别器收到取消、永不到 .began；(79) 日志窗 paw.face79 init ×6 在位、fire 零样本互证。
- 改版：长按语义整套退役（台面钮与浮层爪印两处识别器全摘），单击 .touchUpInside 切换（走 PetSummonButton70.performPawToggle77 收口，actCrumb=paw.act81，落 paw.tap81）；QuickRow 原 hitTest 覆写（只为动态改长按时长）一并删除。
- 烟花：PawFirework81——CAEmitterLayer 一发即停约 36 颗（白/金/粉/青四色、寿命 ≤0.85s、径向初速＋重力收尾）＋光晕弹簧放大淡出＋钮体弹簧回弹（pop）；粒子量克制、单次发射不常驻。

### 11. AI 歌词导演（双模式） —— 代码已改待真机
- 新文件 LyricDirector81：总开关默认开（SettingsStore.directorEnabled81）；设置页（62D 簇、逐歌记忆同组）加导演开关＋「导演接口」配置行——弹层三字段（接口地址/模型/key），key 只存 Keychain（DirectorKeychain81），地址/模型存 UserDefaults；状态行显示「本地规则／AI 模式（模型名）」。
- 本地模式：关键词情感桶（燃→花火 hanabi／悲→雾笺 nebbia／爱→绘光 lumiere／静→莫奈 monet，桶分 ≥2 才采）＋节奏兜底（行密度 ≥26 行/分→心象 cadenza、≤11→静止 still、其余→流光 classic）；候选池＝注册表全式减 petconcert、减锁定。
- AI 模式：地址＋key 齐备即本地关闭，歌词摘要（歌名/歌手＋前 1500 字）发用户接口（OpenAI 兼容 chat/completions、20s 超时），回答中第一个出现的候选 id 即判定；失败只落 dir81.err 不回退本地、本曲不写。
- 挂预备：NextTrackPrep80 在行表派生后、无手动记忆时调 decide()，结果经 SongStyleMemory80.recordDirector 写入同一存储（新增来源标记：manual 集持久化，record() 落标记、recordDirector 对手动曲整发拒绝 dir81.keep）；网页式判定顺带 prewarm。套用走既有 applySongStyleMemory80（其 style(for:) 对导演来源另受导演开关收口）。三击切特效未动。

## iOS 适配自查
- 横竖屏：统一台宽公式 min(宽,高)−24 两朝向同值；舞台旋转管线新增网页层截图盖（第 3 条）随容器弹性、落定重落；岛中央簇 layoutSubviews 随旋转重落、横屏不隐藏（第 4 条新规）；进度两态横屏按竖屏白条口径（收起恒 134×5 居中）。
- 安全区/灵动岛：岛带收窄后宠物内缘压岛框 5pt 为有意贴合（镜像层自绘、非系统岛本体）；舞台宠物带只改 insets 不动安全区；台面底锚沿用各宿主既有 −10/+31.5 双态。
- 系统手势：町景放行 WebView 交互后，新增冲突面＝WebView 自带滚动（已关）与祖先三击/单击（识别器在祖先、触摸上达，待真机验识别率）；爪印改单击后与台身 0.55s 长按切主题不再互斥（touchUpInside 不经识别器链）；其余手势零改动。
- 深色/字号：图标四套在深底玻璃台上以白 tint（A/B/D）或奶油盘（C）呈现、对比口径与现行白钮一致；新增文字（舞台歌手行 12pt、导演设置行）沿用既有字号下限。
- 机型：基准 iPhone 14 Pro 宽 366 台宽下右簇七钮共 228pt＋封面标题区仍 ≥70pt（标题截断尾行口径不变）；内存：截图盖/烟花/导演均为瞬时或单槽量级，全应用 ≤450MB 硬线不变。

## 未定案清单（待真机/下轮日志）
1. 町景放行后三击切特效识别率（第 6 条）。
2. webfx.rot81 ready 的 via 分布与 ms 量级（第 3 条流畅度对账）。
3. 播放条根链 mb.claim78/disp78——(81) 未动其结构（红线），仍待新日志首响判读。
4. 岛中央簇封面在切歌瞬间的占位时长（第 4 条已知边界）。
5. 导演本地桶阈值（≥2）与兜底行密度线为初版启发式，待真机歌单抽验后调参；AI 模式未在真机联调（无用户接口可测）。
6. (82) 已定案候选（评论面板/歌曲资料面板/听歌统计）不在本包。
