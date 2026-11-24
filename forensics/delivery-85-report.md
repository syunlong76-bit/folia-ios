# (85) 交付报告

- 分支：release-85（自 release-84 拉出），提交 e9101085
- CI run：45423494008 **success**（首跑 45420857245 排队约 15 分钟无 runner 接单、已取消，与 (80) 首跑同症、非代码问题；重触发后立即接单，Build/Package/Upload 全步 success）
- IPA：~/workspace/folia-deploy/build85/Folia-85.ipa，**48,763,036 字节**
- CFBundleVersion：85（project.yml 两处）
- 施工依据：forensics/audit-85-inputs.md（五项审计结论）
- 前端：本包未动前端，沿用既有产物（构建铁律三 API base 在验包环节复核）

## 一、侧栏重做：网页版中间窄缝（书脊档 64）

- 撤除：(84) HomeSidebar84View 左缘固定条整件删除（文件已删、全仓无引用）；主页左上角小白线（缝合把手）在速记簿装配点即落 `edgeHandleSuppressed84 = true` 退役，不再依赖装配顺序；抽屉本体与控制台入口保留原通路未断。
- 世界缝本体（WallLayout）：缝锚＝块边界中线世界 x（`seamBoundaryX85`：column×12×pitch − gap/2，与网页 getSeamBoundaryX 同式）；开口规划 `seamPlan85` 与网页 blockSeamPlan 同式（近三界选「相机让位最小＋离中线近」，相机只让到整缝入屏、距边 ≥14）；渲染几何 `seamGeometry85` 与网页 getSeamGeometry 同式（room＝离近边距离 −14，渲染宽＝min(目标开口, room×2)，出界即 0）；实例帧在 rebuildAttributes 按网页 getSeamSplitOffsets 同式分裂让位（pad＝(gap/2)×scale×min(1,width/16)，只动帧不动世界坐标，定位/预取零感知）。开合补间 CADisplayLink（开口 0.36s／相机 0.42s，easeInOut）。
- 主页缝（HomeSeam85View，书脊 64）：书库行 → 折叠钮 → 竖排页签（歌单/电台/专辑/本地，歌单默认选中＝填色块，网页一级选中态）→ 中段直达入口「我喜欢的音乐」→ 账户头像 → 底部工具格（搜索/设置/队列/⋯）。去向与 (84) 侧栏同一张表，逐钮真接：歌单＝回呈现集顶部、电台/专辑/本地＝既有原生面、搜索＝主页既有搜索、设置＝SettingsViewController、队列＝QueueLatticeViewController、⋯＝恢复已隐藏歌单/回到播放页/折叠缝（无原生面的项不列、不做假按钮）。逐钮落 `sidebar85 tap dest=…`。
- 歌单页缝（PlaylistSeam85View）：书脊档＝返回 ‹ → 折叠 → 竖排歌单名（点它展开）→ 竖排计数（种子落地回填 detail.trackCount）→ 播放钮（startQueueAt 0）→ 展开钮；展开档 300＝返回＋横排标题/计数＋播放全部/加入队列（QueueManager.appendToQueue）＋收起。
- 等级存储：折叠态存 UserDefaults `folia.seam85.hidden`、跨面沿用（网页全局等级同式）；展开档（300）为歌单面内状态不入存储。
- 取舍（任务书要求写明）：①手机只做书脊 64＋hidden 两级，网页的 pinned 300 完整条只在歌单页作面内展开档，主页不做 300（屏宽账：300 开口在 390pt 屏上挤压墙面过半）；②「近边收窄/出界关闭」按网页原式实现（渲染宽随近边距离收窄、内容按 (w/c−0.35)/0.65 淡出、出界渲染宽归 0）；③缝折叠或被平移挤出视口时出侧边竖标签「书库」（网页 BRAVAIS_EDGE_TAB），点它在当前视口重新规划裂开；④缝背景 hitTest 只认按钮本体、其余穿透——缝随墙走、不是拖动把手，墙面平移手势不被吞。
- 见证：`seam85 on/plan/reopen/fold/expand`、`sidebar85 tap dest=…`、总表 `wit85.live seam=1 …`。

## 二、点头像＝定位正在播放

- 主页墙：工具条头像与缝内账户头像单击改绑 `avatarLocate85()`——来源歌单可知（QueueManager.sourcePlaylistId 在主页呈现集内）→ 开其曲目墙并置 `locateCurrentTrackWhenReady` 真定位（`locate85 result=wallopen`）；来源不可知 → `locate85 result=nosrc`＋toast「正在播放的歌曲不在主页歌单里」，**不再开舞台页冒充定位**（审计三死点一）；无在播 → `locate85 result=none`＋toast。
- 歌单墙：工具条头像改绑本墙 `locateCurrentTrack(via: "avatar")`（本墙内真相机移动）；`locateNearestInstance` 返回 nil 的两处静默 return 已补 `locate85 fail why=nilinst`＋可见反馈（审计三死点二）；定位全程 `locate85 via/result` 落痕，落定校验处补 `locate85 result=ok`。
- 账户卡去向：AccountCard62ViewController 不删，改由设置页账户组新增「查看账户卡（三平台）」钮以 popover 呈现（锚该钮，onLoginSuccess/onSessionChanged 回刷设置页账户段），落 `locate85 acct src=settings`。
- 残留标注：浏览页（专辑/歌手）工具条头像仍走全局转发开账户卡（activateGlobal 既有设计，不在审计与本包任务书范围），如需统一为定位口径请排下一包。

## 三、点播台 seek 带堵漏

- 三宿主（主页墙/歌单墙/舞台）形态切换处统一：收起态 `miniSeekHit/stageSeekHit.isUserInteractionEnabled = false`，展开态恢复；逐形态落 `seek85 host=home|wall|stage hit=0|1`。收起态细条任意位置（含中央）点按从此直达台身识别器组进展开链（touch75→claim→expand 既有见证链可查）；展开态 seek 拖动/点按行为不变。
- 判读路径：真机收起态点细条中央 → 日志应有 `touch75`（点按到达）→ claim → expand 展开动画，且同形态切换行 `seek85 host=… hit=0` 在前。

## 四、关灯点亮放大修复

- WallPosterCell 加容器层 `coverContainer85`（审计二选项 B）：layoutSubviews 只布容器 frame（容器恒 identity），imageView frame 仅在容器尺寸变化时设（且先摘 transform 设帧再原样挂回，绕开对带 transform 视图设 frame 的未定义行为）；放大 transform 挂 imageView 本体，从此每拍布局不再吃掉放大。闪光层改插容器之上；prepareForReuse 既有 transform 复位不动。
- 倍率 1.1→1.15（与点按展开同量级感，任务书允许范围内）；弹簧参数（0.45s/damping 0.86）不变。
- 见证：点亮后 0.6s 落 `light85 zoom wall=… id=… sx=… alive=1|0`——sx≈1.15 且 alive=1＝放大存活；两墙（主页/歌单）共用同一 cell 类、天然都成立。

## 五、横屏小白条 209 → 218

- DeckLayout84.collapsedTrackWidth 横屏档 209→218（审计五真机横屏图逐像素量测：系统线 ≈218pt、高 5.1、底距 7.9）。高 5、底距、竖屏 140、锚位公式 C＝inset−9.5 全不动，仅此一处常数（三宿主共用单源）。

## 六、舞台台时间锚统一

- 舞台右时间改锚台右端内侧（bar.trailing −16），与墙台同构；左右时间定宽 44→40（与两墙统一，≥10 分钟曲目「10:00」级宽度不冒框）；track 右端随之锚 totalTimeLabel.leading −8（既有约束自动跟随）。
- 控制台钮移出进度行：回主排右端（trailing −12、centerY＝bar.centerY −5，与墙台同位同纵），进度行右端让给右时间，消除「时间挤在控制台钮旁一簇」。
- 墙台既有锚位未动。

## 七、控制台紧凑悬浮毛玻璃卡＋点击特效

- 形态：pageSheet 55% detent 整件退役，改 `.overFullScreen`＋crossDissolve：根视图压暗（黑 0.45），卡居中悬浮——宽＝屏宽 82%、高＝min(424, 62% 屏高) 布局时收口、圆角 28、毛玻璃（systemUltraThinMaterialDark＋0.25 黑 tint，与 (82) 同材质）＋0.16 白描边；入场卡弹簧缩放淡入（0.5s、damping 0.82，iOS 系统弹簧）；点卡外压暗区关闭（落 `console85 tap el=outside`）。
- 内容与接线核对（与 (82) 逐项对照，一项未丢）：队列（露 3.5 行＋渐隐、当前行琥珀高亮、点行即播并关闭、右上清空钮）✓；功能行六钮（模式菜单/随机/特效/宠物/喜欢/速记簿，宿主钩子 onEffects/onSketchbook 原样）✓；音量滑杆（PlaybackEngine.volume 同源）✓；外观行（透光/实色分段写 gridCardMinOpacity＋发 .foliaSettings62AChanged、海报聚焦开关 WallLight82.focusEnabled82）✓；灯钮 LightSwitch82（WallLight82.setOn）✓；帮助钮（说明 alert）✓。内容全部迁入卡内约束（锚卡边），爪印烟花宿主坐标同步改卡内。
- 点击特效：新建 ConsoleFX85——按下缩放回弹（0.45s 系统弹簧 damping 0.5）＋闪光环扩散＋6 颗 3pt 像素方点外迸（v2 定版语言克制版）；覆盖队列行/清空/模式/随机/特效/宠物/喜欢/速记簿/外观分段/聚焦开关/灯钮/帮助，滑杆只走闪光环不缩放（免拖动抖动）。逐元素落 `console85 tap el=…`；呈现落 `console85 present form=card`。

## iOS 适配自查

- 横竖屏双向：缝几何全走世界坐标＋屏幕换算，横屏相机/视口宽自动跟随；控制台卡宽 82% 乘数约束＋高 ≤62% 屏高收口，横屏矮屏不超屏、居中不变；小白条横屏 218 为本包量测修正项。
- 旋转重排：缝帧在 viewDidLayoutSubviews 与 scrollViewDidScroll 双路逐帧收口，旋转后按新视口重算渲染宽；卡在布局回调内重算高度上限。
- 安全区/灵动岛：缝内容 topInset＝safeArea.top＋56（避工具条/岛）、bottomInset＝safeArea.bottom＋116（避点播台）；卡居中无贴边元素。
- 系统手势不冲突：缝 hitTest 只认按钮本体、背景穿透，墙面 pan/左缘返回（EdgeBack76）不被缝吞；侧边标签为点按（tap）不与左缘返回 pan 抢手势；控制台点卡外关闭为根视图 tap、与卡内滚动/滑杆不冲突。
- 深色外观：缝/卡均为深色毛玻璃＋白字（与墙面深色底同语境）；设置页新钮走 FoliaUI 既有色板随页主题。
- 字号下限：缝内最小字号 11pt（书库行/计数，与网页书脊同级、属装饰性标识）；控制台沿用 (82) 字号未改。

## 预登记判别标准（真机/日志）

1. 缝：主页进墙即见中央附近 64pt 竖缝随墙平移（拖墙缝同速移动、砖在缝两侧让开）；日志 `seam85 plan host=home`；点缝内任一钮有 `sidebar85 tap dest=…` 且真达目标面；折叠后侧边出「书库」标签、点它缝重开（`seam85 reopen`）。
2. 头像：播放中点主页工具条/缝头像 → 打开在播歌所在歌单墙并飞到该曲（`locate85 via=avatar`→`result=wallopen`→墙内 `locate ok`/`locate85 result=ok`）；在播曲不在主页歌单时只 toast、不开舞台（`result=nosrc`）。
3. seek 带：收起态点细条正中央 → 展开（`seek85 host=… hit=0` 在前、touch75→claim→expand 全程在日志）；展开态拖进度照常。
4. 关灯放大：关灯后点一张封面 → 该砖亮起且肉眼可见变大；日志 `light85 zoom … sx=1.15 alive=1`；再点别张，放大转移不丢。
5. 横屏小白条：横屏收起态细条与系统 home indicator 等宽（218）；竖屏仍 140 不变。
6. 舞台时间：舞台展开态左右时间分贴两端、右时间不再挨控制台钮；控制台钮在主排右端；放 ≥10 分钟曲目时间不冒框。
7. 控制台：点控制台钮 → 悬浮小卡居中出现（非半屏 sheet）、点卡外关闭；逐个点卡内元素均有缩放回弹＋闪光，日志逐条 `console85 tap el=…`；队列/模式/音量/外观/灯钮功能与 (82) 一致。

## 验包（五项全过）

- 体积：48,763,036 字节。
- 入场母带：Payload/Folia.app/EntryVideo/entry-v5-faststart.mp4 的 md5 = 8aed0fb4a5e9a0f500184f8a7dae45a9，与定版母带值逐字一致。
- 三 API base：WebEffect chunk（providerRegistry）中 /api/netease、/api/qq、/api/kugou 三项俱在（本包未动前端、沿用既有产物，复核通过）。
- CFBundleVersion：Info.plist 实读 = 85。
- 新符号入二进制：主可执行 strings 实查 wit85.live、seam85、sidebar85、locate85、seek85、light85、console85、ConsoleFX85、coverContainer85 全部命中。

## 未在本包范围

- 黑屏（主页墙 fling 窗）与特效旋转两条仍等 (84) 日志数字定案（tap84/hit84·pf84/rot84 见证已在 (84) 包内），未动。
- 浏览页工具条头像仍开账户卡（见第二节残留标注）。
- 图标 J/K/L/M 仍待 Miller 点选，本包沿用临时字形。
