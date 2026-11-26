# (90) 修复包交付报告（port90）

- 分支：release-90（自 release-89 切出）；提交：`c4ce41b7`（本地，未 push、未触发 CI——按止步线等主聊天复核 diff）。
- CFBundleVersion：89 → 90（project.yml 两 target 已改）。
- 范围：任务 1–24 全部落码。面包屑前缀 port90。
- 验证级别：**代码自查级**（本机无 CI/真机）。每条的真机验证点在 §4 汇总，不冒充真机结论。

---

## §1 逐条根因＋修法＋改动文件

### 任务 1 队列浮动面板封面灰块＋网格形态（图1）
- 根因（两层）：①形态层——(89) B 类把卡内队列落成 CoverModule87 封面网格，与 Miller 20:40 裁定的「浮动面板＋文字行 48」正面冲突；②通路层——`CoverTile87.loadCover` 拿 raw 相对串直接查缓存/建 URL，与墙面 cell 的规范通路（先 `proxiedURLString` 规范化）不一致，恒不命中、恒失败，封面永远灰块。
- 修法：卡内队列改回文字行 48（UITableView，行高 48，当前行 3pt 强调条取 `ThemeSystem62.currentAccent`，34×34 封面缩略，标题 13/歌手 12/时长 12 等宽右对齐——规格镜像独立队列页 `QueueTrackCell`）；`loadCover` 改走 proxy 规范化键查缓存→任意 tier 兜底→`image(for:tier:256)`，保留 trackId 防串图。点行起播＋收面板与旧网格同行为。
- 文件：ConsolePanel82.swift、CoverModule87.swift。

### 任务 2 开灯长条纯黑空条（图2/图3）
- 根因：**尺寸从未被拉长**——图2/图3 像素实测均 ≈200×46，LightSwitch82.swift 自 (82) 提交 `90aa29c1` 后未被任何提交改动。真问题是轨道渐变色标：旧色标把光泽压在顶部 25% 内，其余近黑，在窄卡上整条读作纯黑空条，只剩端钮发光。
- 修法：轨道渐变改全高光泽（白 .08 → 白 .02 → 黑 .22，locations [0, .45, 1]），边框白 .10→.14；控制台侧加显式 200×46 恒约束（旧靠 intrinsicContentSize，现代码可证）。
- 文件：LightSwitch82.swift、ConsolePanel82.swift。

### 任务 3＋追加（20:20）控制台图层双份＋聚焦孤悬（图2/图3）
- 根因：(87) 引入 focusIcon 第二图层图标、(89) B 类又把图层行与聚焦行拆成两行——两行各挂一个图层图标，且竖屏 296 卡宽下分段胶囊与特效钮错行挤压、聚焦开关掉到行尾下方。
- 修法：合并回**一行** `fxRow90`（UIStackView，equalSpacing，行高 30）：[图层图标 20×20, 分段 62×26（钮 27×20), 四特效钮组 30×30×4 间距 4, 聚焦开关 30×18]，合计 244 ≤ 竖屏可用 272；图层图标全控制台只出现一次；灯行锚点改挂合并行底。
- 文件：ConsolePanel82.swift。

### 任务 4 展开卡歌词重叠（图4/图5）→ 被任务 8 修法覆盖
- 根因：b-detail-card 落码把大标题/歌手/♥播放队列按钮排/歌词窗 clip 覆盖（clipTopOverride89）全压在封面同一视觉层，互相重叠。
- 修法：随任务 8 一并处理（见下）——动作排与歌手行撤除后，歌词窗 clip 覆盖失去存在理由、同步退役，歌词区回到默认位置。

### 任务 5 歌单缝倾斜/计数断行/双箭头（图6）
- 根因：(89) B 类给歌单缝加了 tiltContainer89 倾斜容器（视觉远超 −4° 观感且连内容一起歪）；计数 label 帧宽不足被断成两行；顶部 backButton（chevron）与 foldButton（chevron）双箭头并存。
- 修法：倾斜整件删除、缝身摆正（后被任务 16 正式取消 −4°）；计数改横排单行「\(count) 首」（numberOfLines=1、宽 56）；foldButton 字形改 xmark 与返回箭头去重。
- 文件：Seam85Views.swift。

### 任务 6 书库缝 Navidrome 竖拆叠印（图7）
- 根因：窄档竖排逻辑把拉丁词逐字拆竖排，与相邻「本地」签帧重叠叠印。
- 修法：Navidrome 特判横排单行小字（9pt bold、宽 56 横胶囊），build 与 applyDisplayMode89 两处同步；其余 5 签保持；窄档页签区改自适应排版（tabsTop/zoneBottom 按高计算、六等分步内居中，tabH 保底），直达双列与工具格两列对齐同沿。
- 文件：Seam85Views.swift。

### 任务 7 全量排版复查（Miller：「每个地方排版都给我排好了」）
- 做法：对控制台/队列页/舞台页/搜索/日记本（原速记簿）/设置/双墙/双缝做布局代码速览＋本包改动面逐项约束账复核。结论单列 §3 登记表：属实现问题的已随各条修掉；形态级观察项登记待裁，未擅动。

### 任务 8 展开卡瘦身（覆盖 (89) B 类 b-detail-card）
- 口径：本条**覆盖** b-detail-card 的「大标题/歌手/动作排」形态，以 Miller 20:18 为准。
- 修法：封面上只留歌名——detailArtist89/detailLike89/detailPlay89/detailQueue89（创建/configure/layout/点按）全删；卡底重复歌名/歌手/▶/已在队列角标撤（playingBadge 展开态隐、queueBadgeVisible 恒 false）；detailTitle89 改 19pt semibold、行高 1.15、宽＝卡宽−32、numberOfLines=0＋byWordWrapping 不截断、高上限 0.34×卡高；展开态强制隐藏 titleLabel/subtitleLabel（原与 detail 标题叠印）；卡面点按播放/喜欢的手势通路不动。**保留项明示**：进度条 progressTrack 不在点名清单（属播放指示），保留——如 Miller 要撤，一行可翻。
- 文件：WallPrototypeViewController.swift、LyricWindowView.swift（clipTopOverride89 退役）。

### 任务 9 主页缝改毛玻璃（覆盖 (86) 油画缝规格）
- 修法：SeamBackdrop86 删油画 imageView/scrim/主题通知，换 UIVisualEffectView(.systemUltraThinMaterialDark)＋黑 0.18 tint；两缝（主页 HomeSeam＋歌单 PlaylistSeam）共用此背板，**影响面＝两条缝同步**；长按循环 4 套油画的缝侧识别器与 handler 删除（SeamThemeCycle86 枚举保留——控制台功能行仍有一钮调其 cycle() 写台面主题，属台面通路不在退役面，报告在此注明）。
- 文件：Seam85Views.swift。

### 任务 10 控制台特效关不掉（功能性坏死）
- 排查结论：①Fx 窗（level 1500）hitTest 与触摸拦截静态核查无问题，第二次点按能到达钮；②状态写读路径一致。**实测根因在关闭语义**：旧 off 走 soft-stop——烟花/雪/风/灯笼淡出 2–4 秒（雪熔解不清 flakes、风不清数组），按钮已灭、画面还在，用户再点即翻回 ON，表象就是「关不掉、退不出来」。
- 修法：四钮 off 一律 hard stop 当帧清场（粒子数组全清）＋`settleAfterStop90()`（setNeedsDisplay＋停循环），按钮态与引擎态同帧一致；墙面与舞台两宿主共用 GlobalFx87 单例、同受益。雪 12s/风 5s 自动停是样片定版行为，未动。
- 文件：GlobalFx87.swift。

### 任务 11 账户页 QQ/酷狗头像占位（20:23 图）
- 根因：头像回填（enrichProfile）此前只存在于 LoginViewController——且只在打开登录页并选中该家时触发；账户卡只读资料缓存、从不回填。QQ/酷狗登录时若没走完那条路，缓存里 avatarURL/displayName 为空就永远占位；网易云另有墙面主流常刷所以正常。
- 修法：AccountCard62.rebuild() 末尾对「已登录且头像或昵称为空」且未试过的家触发同源 enrich（网易云 fetchLoginStatus / QQ fetchLoginStatus(cookie:) / 酷狗 fetchUserDetail(cookie:userId:)，userId 自 cookie 解析），成功 saveProfile 后回刷＋port90 面包屑；每家每卡只试一次防循环。
- 文件：AccountCard62.swift。

### 任务 12 登录只弹扫码页
- 修法：LoginViewController 加专用模式——凡带 initialProvider 的入口（点某平台登录/切换）进入后隐藏平台列表行/头像/账户状态/动作钮/同步钮，只留平台名标题＋该家扫码区，三家一致（酷狗方式段恒钉扫码法、字段组恒隐）；其余 4 个通用入口保留登录中心全形态。呈现方式不变（pageSheet＋medium/large）。与网页版对应关系：网页点平台直接出该平台二维码页，原生专用模式即同构（一屏一平台、只扫码）。
- 文件：LoginViewController.swift。

### 任务 13 播放台四主题点撤除
- 修法：三宿主（WallPrototype/HomeWall/Stage）删除 dotsStack 构建、点按 handler、回刷函数与 alpha/交互名单中的 dots 项；Deck87.dotThemes/dotColors 零引用后删除。长按台面循环主题手势（MiniPlayerTheme.stored.next）未动。
- 文件：Deck82.swift、WallPrototypeViewController.swift、HomeWallViewController.swift、StageViewController.swift。

### 任务 14 播放/暂停钮改圆形毛玻璃
- 修法：三宿主台面钮＋控制台中央钮（双落点，见任务 20 判读）：去金色实心（bg 清零、tint 回白），钮内垫 UIVisualEffectView(.systemUltraThinMaterialDark) 圆形层（台面 42 钮圆角 21/控制台 54 钮圆角 27、禁交互不挡点按），尺寸/位置/图标不变。
- 文件：ConsolePanel82.swift、WallPrototypeViewController.swift、HomeWallViewController.swift、StageViewController.swift。

### 任务 15 控制台入口图标改双音符
- 修法：DeckGlyph82 新增 `.consoleNotes` 字形——手绘双八分音符（24×24 画布：两倾斜椭圆符头＋右侧符干＋四边形旗面，上下错位排列）；三宿主控制台入口钮字形 `.console`→`.consoleNotes`，位置/尺寸/毛玻璃底不变。
- 文件：Deck82.swift＋三宿主。

### 任务 16 歌单缝改毛玻璃＋摆正（覆盖 (89) B 类 b-seam-tilt −4°）
- 与任务 9 同口径：共用 SeamBackdrop86 已换毛玻璃；倾斜整件删除（任务 5 已落）、计数单行、双箭头去重（任务 5 已落）。两缝背景与排版口径统一：主页缝落点 HomeSeam、歌单缝落点 PlaylistSeam，均在 Seam85Views.swift。

### 任务 17 设置页导航改横向（横竖屏统一，覆盖 (89) B 设置左导航 104 列）
- 更正口径：初版任务书「横屏可保留左列」已被 Miller 20:34 作废——**两态同为顶部横向导航＋全宽内容**，本包按更正后落码。
- 修法：骨架重排单列 [标题行（页名＋完成）, 搜索框（任务 18）, 横向 chips 条（高 36，chip 高 34 圆角 17、字 13）, 内容滚动区全宽]；删 bodyRow89/rightColumn89 与 104 宽约束；选中 chip 自动 scrollRectToVisible；自检链与各页签内容零改动。
- 文件：SettingsViewController.swift。

### 任务 18 设置页搜索
- 修法：数据源＝现有设置项注册表在运行时遍历 tabGroups 顶层组→卡内行、递归收集 UILabel 文本（首个为标题、次个为说明），不另造清单；查询按标题/说明 contains 匹配；有查询时隐藏页签条与内容、显示结果表（行高 52，副行「页签名 · 说明」）；点结果→清查询→切签→滚动到该行→accent 0.30 闪光高亮 1.2s。
- 覆盖项数：索引在运行时构建并落面包屑 `port90 settings search index=N`——**静态不可知，真机首开设置页读桥日志即得**；定位方式＝切签＋scrollRectToVisible＋高亮闪，如上。
- 文件：SettingsViewController.swift。

### 任务 19 开灯/关灯切换没反应（与任务 2 同根、功能链）
- 静态判读（如实）：整条链逐环核查**无断点**——LightSwitch82.tapped→onToggle→ConsolePanel82 接线（:417-421）→WallLight82.setOn（写 UserDefaults＋广播）→两墙观察者→applyToVisibleCells→WallPosterCell.applyLight82→lightDimView82.alpha；configure() 也调 applyLight82（滚动新砖状态正确）；(89) 两笔提交未触灯钮接线；(82)/(83) 历史日志窗内均无切换样本，无从判读。
- 唯一能产生「两向切换零变化」的静态可达路径：`dimAlpha` 被 `focusEnabled82` 门控——聚焦开关关时 dimAlpha 恒 0，开/关灯墙面都零变化，与 20:35 实测逐字吻合（(89) 里聚焦开关孤悬错位、状态极易被误触/误读）。且 (82) 第 8 条旧口径「关时灯钮仅记状态」与 Miller 定版定义（2026-11-24：关灯＝整墙暗下只留点中封面亮）正面冲突。
- 修法：**压暗与聚焦门控解耦**——dimAlpha 不再受 focusEnabled82 门控（关灯必暗，与开关状态无关）；聚焦开关只保留点砖聚焦消费（consumeTapIfNeeded）与焦点放大两项门控。同时在链上加四环 port90 自证面包屑：`port90 light tap`（钮身）→`port90 light toggle`（控制台回调）→`port90 light setOn`（状态落写）→`port90 light apply cells=N`（宿主落砖）——真机点一次，断在哪环日志自明。
- 影响面：主页墙＋歌单墙已接（两墙同受益）；其余封面页未接灯光是已知缺口，本包不扩。
- 文件：WallLight82.swift、LightSwitch82.swift、ConsolePanel82.swift。

### 任务 20 控制台与播放台图标统一
- 核查结论：字形工厂自 (87) 起即单一出处——控制台三钮经 configureTransButton87 取 DeckGlyph82 核心字形（prev/next/play/pause），与三宿主台面同工厂。Miller 截图中「普通三角」的成因判读：旧 transPlay87 金 tint＋金 0.22 底把 M 字形 play 的圆环负空间吞没、只剩深色三角可读。
- 修法：字号严格对齐（play/pause 22→21 与台面同、prev/next 19 本已同）；中央钮外观随任务 14 改圆形毛玻璃（白字形＋透底，负空间恢复可读）。**双落点判读请主聊天复核**：任务 14 的「播放台」我按含控制台中央钮落码（因任务 20 明言中央钮外观跟随 14 条）；若 Miller 本意仅台面，控制台钮可单独回退。
- 文件：ConsolePanel82.swift。

### 任务 21 拍立得照片墙（样片 v2 定版移植）
- 落点：ConsolePanel82 主视图顶部（条带之上），新增独立区 PolaroidZone90View；头部行 40（换一批＋日记本两圆钮 40、日记本钮带收藏数角标）＋舞台区（竖屏 232/横屏 146）。
- 形态（照样片）：打印机（原生图层拼造型：奶油机身＋纸槽＋镜头＋LED 闪烁＋出纸口）居中置顶；10 张拍立得（白框、方封面、题注歌名＋歌手、右上 ➕、题注行日记本小钮）逐张从出纸口弹簧滑出落槽（间隔 0.42s、弹簧 0.72），散布槽位两排错位、旋转 −7°…+8°；打完打印机淡出上移消失。点照片切歌：在播队列内定位 playAtIndex；历史歌曲插队首起播（不清用户队列），随后收控制台。
- 数据源（真实来源、无假数据）：当前队列 ∪ 本机播放历史（PlayHistoryStore.records），id 去重、洗牌取 10；池为空时区内只剩打印机静置（不出假照片）。
- 文件：新增 Polaroid90.swift；ConsolePanel82.swift（接入）。

### 任务 22 日记本（速记簿改名＋联动）
- 改名：全部用户可见「速记簿」字符串改「日记本」（抽屉标题/把手/设置行/命令面板/教程提示等 20 文件，仅显示字符串，ASCII 键与标识符未动）。
- 日记本页 DiaryViewController90（全屏纸面页）：头部（返回＋日记本＋今日日期）、「贴进日记本的歌」列表（封面/歌名/歌手/写日记/移除）、「写今天的日记」（挂歌条＋横线纸文本框＋涂鸦画板：6 色/细粗/撤销/清空、绘画期间锁祖先滚动）、「日记墙」（胶带条＋挂歌行＋文字＋画作图＋时间）。
- 联动入口：拍立得头部日记本钮（无挂歌打开）、拍立得题注行小钮（挂该歌打开）、日记本内歌曲行「写日记」（挂歌并聚焦输入）。
- 数据存法：DiaryStore90 单源——歌曲与日记条目 JSON 存 UserDefaults（diary90.songs / diary90.entries）；涂鸦 PNG 落 Documents/diary90/<条目id>.png；按日以 dateKey（yyyy-MM-dd）标记；变更广播 .foliaDiary90Changed。
- 文件：新增 DiaryStore90.swift、DiaryViewController90.swift；改名面 20 文件（见提交）。

### 任务 23 封面 ➕ 渠道
- 落点：WallPosterCell（主页墙＋歌单墙＋网格共用，封面右上 6pt、24×24）、CoverTile87（控制台条带，右上 5pt）、PolaroidCard90（拍立得封面右上）——三处共用 DiaryAddButton90 工厂：深色半透圆钮＋白 plus；已贴入变琥珀底＋白对勾。状态读 DiaryStore90 单源，configure 时回刷＋变更广播回刷，跨面一致。
- 仲裁口径：➕ 是钮自身触摸，不进宿主选择/点播通路；关灯态「首点点亮」仲裁走宿主 didSelect 通路，两者不串（真机验证点 §4）。歌单形条目（副行「歌单 · N」）不是歌曲、不挂 ➕；曲目封面全挂。
- 文件：WallPrototypeViewController.swift、CoverModule87.swift、Polaroid90.swift、DiaryStore90.swift。

### 任务 24 拍立得装入硬约束（不删下方内容）
- 实现口径：主视图 UIView → UIScrollView（内容锚走 contentLayoutGuide 纵向＋frameLayoutGuide 横向）；拍立得区只占顶部新增高（竖屏 272/横屏 186），下方整链相对锚点与间距逐项与加区前相同，仅首锚改挂区底；卡高走内容生长口径（竖屏内容 658 ≤ 上限 672@14Pro 不滚动；横屏内容 396 > 上限约 247 时区内纵向滚动），各行尺寸不缩。
- 控制台各行保留清单（加墙前 → 加墙后，逐行对账）：
  | 行 | 加墙前 | 加墙后 |
  |---|---|---|
  | 拍立得区 | 无 | **新增**（头行 40＋舞台 232/146） |
  | 封面条带 stripScroll87 | 86（横 82） | 86（横 82）不变 |
  | 清空队列钮 | 条带右上 | 随条带、不变 |
  | 钮排 transRow87（上一曲/播放/下一曲） | 54 | 54 不变 |
  | 功能行 functionRow（6 格） | 40 | 40 不变 |
  | 音量行（speaker＋slider＋值） | 38 | 38 不变 |
  | 图层/特效/聚焦合并行 fxRow90 | 30 | 30 不变（任务 3 合并形态保留） |
  | 灯行（LightSwitch82 200×46＋帮助钮） | 46 | 46 不变 |
  | 队列视图（文字行 48 表） | 卡内切换 | 不变 |
- 文件：ConsolePanel82.swift。

---

## §2 与 Miller 截图逐图对照（验收要点）

| 图 | 内容 | 本包对应 | 真机验收动作 |
|---|---|---|---|
| 图1（队列横屏） | 封面灰块＋两排大空格网格 | 任务 1：文字行 48＋封面通路修复 | 开控制台→切队列视图：每行有封面缩略＋歌名/歌手/时长，当前行有强调条 |
| 图2（控制台横屏） | 灯条纯黑、图层行重叠 | 任务 2/3：全高光泽＋合并一行 | 横屏开控制台：灯条有光泽层次、图层图标只一个、聚焦开关同行对齐 |
| 图3（控制台竖屏） | 同上＋烟花被压一半 | 任务 3/10 | 竖屏开控制台：四特效钮完整不被压；逐个点开再点关，当帧消失 |
| 图4/图5（展开卡） | 歌词压标题/按钮行 | 任务 4/8：只留歌名 19pt、歌词回默认位 | 展开任意卡：封面只有歌名（小字、可换行）、歌词不压字 |
| 图6（歌单缝） | 缝歪、288 断行、双箭头 | 任务 5/16：摆正＋毛玻璃＋单行计数 | 进歌单页：缝竖直、毛玻璃透墙、「288 首」单行、顶部只一个返回箭头 |
| 图7（书库缝） | Navidrome 拆字叠印 | 任务 6/9：横排小字＋毛玻璃 | 主页缝窄档：Navidrome 横排一行、与本地签不叠 |
| 20:18 展开卡新图 | 元素过多、大标题截断 | 任务 8 | 长标题英文歌展开：歌名完整或优雅换行、不出框 |
| 20:23 账户图 | QQ「Q」/酷狗「酷」占位 | 任务 11/12 | 开账户页：QQ/酷狗显真实头像；点未登录平台直接出扫码页无中间页 |
| 20:26–20:37 后续令 | 台面四点/金钮/滑杆图标/拍立得 | 任务 13/14/15/20/21–24 | 台面无四点、播放钮圆形毛玻璃透底、入口钮双音符；控制台上方打印机逐张打印 10 张、点照片切歌、封面 ➕ 贴入变琥珀对勾 |

## §3 任务 7 排版登记表（速览结论）

| 页面 | 现象 | 处置 |
|---|---|---|
| 控制台横屏 | 合并行后右列底 slack 约 63（左列主导高） | 非缺陷（左列链定高），登记说明、不动 |
| 主页缝横屏 | contentH 可能被 insets 压至 ~150，页签公式 tabH 退化 | 已含 min 保底（任务 6 自适应排版覆盖竖屏主场景）；横屏缝列观察项，真机若挤再修 |
| 台面标题 | 单行截断「What Kind of Love Is Lik…」 | 台面定版行为（84 两行版规格内），非缺陷、登记说明 |
| 歌单缝整墙同转 | 原登记为形态级待裁项 | 已随任务 16 去倾斜消解，关闭 |
| 队列页/舞台页/搜索/日记本抽屉 | 速览未见新挤压（队列卡宽有屏宽钳制、舞台帧全 bounds 相对） | 无改动 |

## §4 留给真机的验证点（按优先级）

1. **灯光链**：点长条切换一次，桥日志应依次出现 `port90 light tap/toggle/setOn/apply cells=N` 四行；关灯整墙压暗（聚焦开关开/关两态都要试——修后都应暗）、开灯对角波浪＋闪光。
2. **特效开关**：四钮逐个开→关，关帧粒子全清、无残影；关后点墙面/台面不被隐形层吞触摸；Fx 窗在两宿主（墙/舞台）各验一次。
3. **头像自愈**：冷启开账户页，QQ/酷狗头像应在数秒内由占位变真实头像（面包屑 port90 enrich 落痕）。
4. **扫码专用模式**：三家未登录平台点按，均直接出扫码页、无中间页；已登录平台切换/退出口径不变。
5. **拍立得**：打印时序与打印机消失、点照片切歌、换一批重打；横屏滚动到底不压行；推荐池为空（新装无队列无历史）时区内表现。
6. **➕ 仲裁**：墙面砖 ➕ 点按只贴日记本、不触发点播/展开；关灯态下 ➕ 与首点点亮不串扰；贴后三面（墙/条带/拍立得）对勾态一致。
7. **日记本画板**：涂鸦时页面不跟着滚；保存后日记墙出现条目（文字＋画作）；杀进程重开数据还在。
8. **设置搜索**：读面包屑 `port90 settings search index=N` 记覆盖项数；搜任意项点结果，页签切换＋滚动定位＋高亮闪成立。
9. **设置横向导航**：横竖屏均为顶部 chips 条（任务 17 更正口径），内容全宽可滚、无截断。

## §5 iOS 适配自查（逐项）

- 横竖屏双向独立成立＋旋转重排：控制台两套约束集均含拍立得区（竖 272/横 186）且链完整；设置页两态同构横向导航（任务 17 单列核对 ✅）；双缝毛玻璃两态共用背板；日记本页横屏内容居中限宽由 stack 约束（frameLayoutGuide 宽−32）成立。
- 安全区/灵动岛/状态栏避让：控制台卡沿用既有底锚 90＋顶距 56 上限；日记本页头部挂 safeAreaLayoutGuide；拍立得区在卡内、不触安全区。
- 系统手势不冲突：主视图改滚动后与条带横滚为正交方向嵌套（系统标准形态）；画板绘画锁祖先滚动、松手恢复；➕/小钮均为钮自身触摸不抢卡面手势（验证点 §4.6）。
- 深色外观与字号下限：毛玻璃取系统材质自适应；新增文字最小 8.5pt 仅拍立得题注歌手行（样片同规格、装饰性次级信息），功能文字 ≥11pt；设置 chip 13pt、日记本正文 14.5pt。
- 目标机型（iPhone 14 Pro）：控制台竖屏内容 658 ≤ 上限 672 不滚动、横屏滚动兜底；fxRow90 合并行 244 ≤ 272 可用宽。

## §6 覆盖关系与取舍备忘

- 任务 8 覆盖 (89) B 类 b-detail-card 形态；任务 9＋16 覆盖 (86) 缝油画规格与 (89) B 类 b-seam-tilt；任务 17 覆盖 (89) B 类设置左导航（且按 20:34 更正、横屏不留左列）。
- 4 处定版未推翻：队列封面条带（控制台内仍在、卡内队列视图按裁定回文字行）、上下曲钮排、开灯长条 200×46、播放台 84 两行版——本包只修实现错误。
- CoverGridCell87 类保留（独立队列页注释引用），控制台内已无实例化。
- 任务 14 双落点（控制台中央钮）判读见任务 20 条，待主聊天复核。
