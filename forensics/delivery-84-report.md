# (84) 交付报告 — 播放台复原 (80)／按键结构修法／黑屏两修＋分墙量测／旋转落盘／主页竖条侧栏

- 分支：release-84（自 release-83 拉出）
- CI：首跑 45406582739 **failure**（唯一编译错误：WallTileStats78.take84 返回 tuple 标签 ph/phImg 不一致，已修一行）；次跑 **45406997162 success**
- IPA：`~/workspace/folia-deploy/build84/Folia-84.ipa`，**48,738,693 字节**
- 状态口径：以下全部为「代码已改＋CI 编译通过＋验包通过」，功能结论一律**待真机**，不自宣通过。

## 验包五项

1. 体积：48,738,693 字节 ✓
2. 入场母带：包内 `EntryVideo/entry-v5-faststart.mp4` md5 = `8aed0fb4a5e9a0f500184f8a7dae45a9` ✓（与母带一致，历包同口径）
3. 三 API base：WebEffect chunk（providerRegistry）含 `/api/netease` ×2、`/api/qq` ×3、`/api/kugou` ×2 ✓
4. 版本号：主 App CFBundleVersion = 84、FoliaWidgets.appex = 84 ✓
5. 新符号入二进制：`wall.hit84`、`wall.dec84`、`rot84`（含 `rot84 freeze`、`folia.rot84.last`）、`minibar.fm84`、`HomeSidebar84View`（53 处）、`sidebar84`（含 `sidebar84 tap`）、`wit84.live`、`Tap84`（符号名）、`noteConfigure84`、`edgeHandleSuppressed84` 均检出 ✓。三处检不出系机制性原因、非缺失：`tap84`/`pf84` 日志前缀与 `f2r=` 均为 ≤15 字节的 Swift 小字符串、被内联进指令不入字符串表；`wallPixelExtent` 为静态函数、已在 9 个调用点内联。以上均已用源码调用点 grep 复核在位（Tap84 三宿主各 4 钮 down/up、pf84 在 WallScrollMetrics.flush、wallPixelExtent 两墙 9 处）。

## 逐条落点与预登记判别标准

### 1. 播放台改回 (80) 版为底（三宿主：主页墙／歌单墙／舞台）
- 台高单源改回 70：`DeckLayout82.expandedHeight` 106→70，`MiniBarQuickRowView.expandedBarHeight` 同步 70（三宿主台高都引后者，一处改全台齐）。
- 三宿主同式还原：主题层复原在场（展开显示／收起隐藏，(82) E 毛玻璃恒隐藏退役）；封面 44×44 圆角 22 回主排左置、标题贴封面右（leading=封面+12、top=封面+5）、歌手回台面；播放钮白字形无圆底（(83) 白圆＋深色字形退役）；把手复原 9pt 白色发光圆点＋主题皮肤叠层（(82) 花朵图退役），主排纵向恒 −5，展开轨底锚复原 −7、轨夹双时间标签之间。
- 台面只留四钮：播放/暂停、上一曲、下一曲、控制台入口。墙台四钮在主排右端簇（控制台最右）；**舞台一处位差注明**：舞台 (80) 主排为居中三键、无右端簇，控制台入口保留其 (82)/(83) 进度行右端现位——四钮齐全、仅控制台位置与墙台不同。
- 移除项去向（逐项核实 ConsolePanel82 在位）：模式→控制台模式钮（四档菜单）；列表/队列→控制台顶部队列表（可点播、可清空）；喜欢→控制台喜欢钮；随机→控制台随机钮；爪印（宠物召唤）→控制台宠物钮（爪印字形）。浮层 quickRow、顶栏红心等其余入口未动。
- **与任务书一处出入（如实记）**：任务书称双时间属 (80) 底本一部分——核对 release-80 源码，(80) 墙台**没有**双时间标签（只有舞台有），双时间是 (82) 引入。本包按任务书口径保留双时间，未按 (80) 原样删。
- 判别标准（待真机）：三宿主台面目检与 (80) 版式一致；`minibar.fm84` 落行；四钮点按见第 3 条 tap84。

### 2. 小白条改回 (80) 形态
- 三宿主收起底锚公式统一改 `DeckLayout84.collapsedBottomConstant`：**C = inset − 9.5**。竖屏 inset 34 → C=24.5，与 (80) 常数逐点复原：我方轨带落在屏底上方 15–20pt、系统小白线带 8–13pt，轨底与线顶相接、留 2pt 净空、不重叠（(83) 的 inset−2.5 使轨带落回 8–13 与线重合，即 Miller ⑥点名的实根，本版盖过）。
- 收起轨宽按朝向：竖屏 **140×5**（Miller 截图像素实测）；横屏宽 **209pt**——取值依据：notched 机型横屏 home indicator 的公开实测惯例值（横屏 inset 21 对应更宽的线），**此值为惯例值、未量测，待 Miller 横屏截图复核**（列入未定案）。
- 见证：`minibar.fm84`（三宿主同式：col/tw/th/gap=2/r=2.5/orient，收起时按朝向实赋轨宽约束）。
- 判别标准（待真机）：竖屏截图我方条贴系统线之上不重叠；fm84 收起行 tw=140（竖）/209（横）、gap=2。

### 3. 按键结构修法（DS 定案）
- 三宿主同构改造：毛玻璃层与进度轨道置 `isUserInteractionEnabled=false`（毛玻璃默认可交互、是命中链上的隐形祖先，此前未禁）；台内插入全幅透明背景手势层（`deckSurface84`，blur 之上、主题层之下、按钮的兄弟层），台身识别器组（长按/双击/单击/收起单击/agnostic 兜底）全部改挂此层；(82) 的 delegate 接线循环与三宿主各自的 `UIGestureRecognizerDelegate` 祖先链豁免扩展**整套删除**（全仓 grep 无残留）。保留的祖先侧识别器（agnostic）`cancelsTouchesInView=false` 不变。
- 机制：按钮不再是任何台身识别器的后代，按钮触摸直达自身 `.touchDown/.touchUpInside`，不进 require 链、不存在被取消路径；台身点按落在背景层→冒泡回台身 `touchesBegan`（mb.tch78 见证保留）与各 handler，分域逻辑不动。
- 新见证 `tap84`（`Deck82.swift` 的 Tap84）：三宿主四钮各挂 `.touchDown`＋`.touchUpInside` 双落痕，行内带点按当下对钮中心现做 hitTest 的命中视图类名链（截断 6 层）。
- **预登记判别标准：真机点任一台面钮，tap84 出现对应 down/up 两行**（down 有 up 无＝触摸被取消；两行皆无＝触摸未抵达）。

### 4. 黑屏：量测先行＋两修
- 量测：`WallTileStats78` 新增分墙桶（note84 与全局 note 同拍记账、take84 按墙取），`WallScrollMetrics.flush` 新增 `wall.hit84`（字段 wall 名＋sync/tot＋**pkv 滚动速度峰值＋fling 标记（峰值 >1500pt/s）**，速度按相邻滚动回调位移/间隔采样）。(83) 判读的「全局计数被先冲刷的墙领走、主页墙零窗」就此堵死——两墙各自成窗。
- 修 a（公式单源化）：新增 `NativeCoverLoader.wallPixelExtent(worldExtent:cameraScale:)`（= 世界边长 × cameraScale × 屏幕 scale），两墙的预取入队键与 cell 配置请求键全部改走同一表达式（共 9 个调用点替换；此前预取带 cameraScale、cell 侧不带，同砖两键永不相等）。新增转化率见证 `pf84`：预取入队时登记缓存键（prefetch82 内）、cell configure 时记转化（noteConfigure84，WallPosterCell 内调用），flush 落 `pf84 enq/conv/rate/drp`。
- 修 b（限流）：新增解码并发闸 DecodeGate84（上限 4、按优先级出队），解码段全程过闸；预取在途准入上限（滚动预取 ≤24／入墙预热 ≤8，超限丢弃计入 pf84 的 drp）；LoadPriority 新增最低档 `.warm`（预热只在可见/预取无等待时出队）。新增 `wall.dec84` 见证（各优先级网络槽等待最大值＋解码闸峰值队列），与 (83) 的 dec78 wait 最大 1922ms 对照。
- **预登记判别标准：主页墙 fling 窗的 hit84 率、pf84 转化率 ≥80%，或由日志明确证伪**（证伪即本修法不成立、下轮换路）。

### 5. 旋转：量测必落盘
- 舞台 viewWillTransition 三点（freeze/ready/landed）新增 `Breadcrumbs.logSync` 同步落盘（原 rot82 异步行保留不断链）；landed 时把摘要（gen/f2l/f2r/style/web、emitted=false）存 UserDefaults 键 `folia.rot84.last` 并同步落 `rot84 gen=… f2l=… f2r=…` 汇总行；网页样式 ready 在揭盖点回填 f2r 并补落 `rot84 ready` 行；下次启动 witnessBoot 时若摘要未 emitted，补发 `rot84 prev …` 一行并置 emitted。
- 冻结管线本包不换架构（按任务书：无数字不动）。
- **预登记判别标准：真机旋转一次后，日志必有该次 rot84 汇总行（含 freeze→ready 毫秒 f2r）**——当场没有、下次启动必有 prev 补行。

### 6. 主页左缘竖条侧栏
- 撤把手：`SketchbookDrawerView` 新增抑制旗标 `edgeHandleSuppressed84`，主页装配侧栏后置 true——左缘把手簇（热区钮/静息条/展开把手）整簇隐藏，抽屉本体与全部逻辑保留（控制台「速记簿」钮仍可开合，hitTest 随 isHidden 自然穿透）。
- 新文件 `HomeSidebar84View`（宽 48 命中／视觉条 44）：自上而下＝头像登录区（32 圆，昵称首字/头像图/人形占位，与工具条 setAccount 同口径回显，seamRefreshAccount 两处同步刷新）→「书库」竖排标题→分区入口竖排文字钮（歌单/电台/专辑/本地）→搜索/设置图标钮。装配落 `sidebar84 on`，逐钮点按落 `sidebar84 tap dest=…`。
- 去向（全部已有原生面）：歌单→WorkbenchPlaylistListViewController、 电台→WorkbenchRadioViewController、专辑→WorkbenchAlbumListViewController、本地→WorkbenchLocalViewController（均 fullScreen＋dismissToWall 回墙，与工作台 presentSectionVC 同式）；搜索→SearchHostPresenter.presentSearch；设置→SettingsViewController（overFullScreen）；头像→既有 seamAvatarTapped（账户卡 popover，**锚点仍指工具条头像钮**，点侧栏头像时卡片自工具条头像处弹出——位置待真机观感定）。
- **未接一项（如实）**：「书库」无独立可达原生面（工作台桌已于 (74) 自主页撤下），只作竖排标题呈现、**不做按钮**，不假生效。
- 不吞墙面手势的方案：侧栏 hitTest 只认按钮本体（命中点向上找到 UIControl 才认领），视觉条/间隔/标题一律返回 nil 穿透给墙面；侧栏 z 序在速记簿宿主与工具条之下。
- 适配：leading 锚左缘安全区（横屏岛在侧边时安全区自动让位）、top 112（顶部工具条之下）、bottom 避台与宠物停靠区（安全区底 −130）、横屏同在左缘成立。

### 7. 衔接不回退
- 控制台、开灯关灯、宠物沉降、岛台词/声波、AI 导演、下一首预备、三击、逐歌记忆、汪汪队规则：逻辑零改动（本包 diff 未触其实现文件；台面/命中改造不改其状态机）。(83) 的 present.done/dbltap83 见证保留——歌单墙双击开台尾巴（(83) 日志 TAIL 段记录终止于 present.done 前、结局未确认）下轮日志继续盯，本包未动该路径。

## iOS 适配自查（常设清单逐项）

- **横竖屏双向**：台面三宿主同构、横竖屏同尺寸（70 高、宽 min(宽,高)−24 既有口径未动）；小白条横竖屏分别公式化（宽 140/209、底锚随 inset）；侧栏横屏锚左缘安全区成立；旋转重排走既有管线＋rot84 量测。结论：成立（横屏小白条宽 209 为惯例值待截图复核，见未定案）。
- **安全区/灵动岛避让**：侧栏 leading 锚 safeAreaLayoutGuide、top 112 在工具条（绕岛带 104）之下、bottom 锚安全区 −130；台面底锚沿既有安全区口径。结论：成立。
- **系统手势不冲突**：侧栏 hitTest 只认按钮、背景穿透，墙面平移/边缘返回（EdgeBack76）不被吞；台身识别器改挂背景层后 require 链与启停收口未变，按钮触摸不再经识别器。结论：成立（待真机复核点按/平移互斥）。
- **深色外观/字号下限**：台面与侧栏均为深色玻璃面上的白色系控件（与既有定版一致）；侧栏入口文字 13pt、标题 12pt，为竖排装饰性导航的下限取值，已配 accessibilityLabel 全称。结论：成立，字号待 Miller 真机观感定。
- **目标机型（iPhone 14 Pro）**：全部尺寸公式随 safeAreaInsets／min(宽,高) 公式化，无写死机型常数（横屏线宽 209 除外、已注明依据）。结论：成立。

## 未定案清单（全部待真机/下轮日志）

1. tap84 判别（第 3 条）：真机逐钮 down/up 两行是否齐——按键是否真治好，以此为准。
2. 黑屏三量测：主页墙 fling 窗 hit84 率、pf84 转化率（≥80% 或证伪）、wall.dec84 与 1922ms 的对照。
3. rot84：旋转一次后汇总行（含 f2r）是否必达（含 prev 补发兜底）。
4. 横屏小白条宽 209pt 为惯例值，待 Miller 横屏截图量测复核；不合则改 DeckLayout84 一处常数。
5. 歌单墙双击开台尾巴（(83) 遗留）：本轮日志继续盯 present.done/dbltap83；若再现记录终止，需 .ips 定案。
6. 侧栏头像 popover 锚点仍在工具条头像处，观感待真机定；侧栏仅主页有（歌单墙无，任务书只点名主页）。
7. 图标字形仍为 DeckGlyph82 临时套（J/K/L/M 未定版），定版后只换字形函数。
8. fm84 展开态 tw 字段沿 (83) 的减项估算式（非量测值），只作形态对照、勿当实测读。
9. 本包全部功能结论待 Miller 真机验收；(85) 功能三件（评论/资料/统计）仍排队在本包验收之后。
