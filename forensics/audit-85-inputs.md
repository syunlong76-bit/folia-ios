# (85) 审计报告 — 2026-11-24

只审计、未改代码。对象：原生 release-84；网页版 ~/workspace/folia-deploy/folia-major。
每项给结论、代码级定位（文件:行）、(85) 施工依据。Miller (84) 验收 8 条里，本报告覆盖第 1（缝侧栏）、2（点播台两问）、5（横屏小白条）、6（关灯放大）、8（点头像）五项；第 3（黑屏）、4（旋转卡）不在本审计范围。

---

## 审计一：网页版「中间窄缝」侧栏的真实实现

**结论**：网页版的缝是**墙面世界的一部分**：缝开在世界坐标里一条「块边界」线上，宽度是世界的开口量，墙砖分列缝两边、砖尺寸不变、两半各自让开；平移时缝随相机同速移动，缝滑出视口会先变窄、完全出界即关闭。(84) 的 HomeSidebar84View 是屏幕左缘固定覆盖条，与此模型完全不同，(85) 须按世界缝重做、左缘条与左上角小白线一并撤除。

### 几何定版（真实实现，非教程示意）

- 开口宽度（`src/library/suites/bravais/bravaisConstants.ts:11-15`）：完整信息条 **300px**、首页窄缝 **120px**、书脊 **64px**；列表面板 420px（`ponderBravaisSeamGeometry.ts` BRAVAIS_PANEL_GEOMETRY 对应档，真实开口走 seamPlan 的 caller width）；歌手海报缝 520–680px（视口 46% 夹取，bravaisConstants.ts:27-29）。
- 横向缝（axis 'y'）高度：完整 212 / 首页 72 / 书脊 52（bravaisConstants.ts:20-22）。原生 (85) 只需竖缝（axis 'x'）。
- 窄视口默认书脊：视口宽 <900px 时默认 level=spine（bravaisConstants.ts:44；bravaisSeamLevel.ts:35）。**Miller 手机上的网页截图正是书脊档**：图三缝宽量测 ≈170px/1179px ≈ 57pt ≈ 64 档；图二同 ≈57pt。即 iPhone 宽度下网页版实际呈现的是 64 书脊形态，首页 120 窄缝是宽屏档——(85) 复刻目标应以**书脊 64 为手机定版**，120 只作宽屏/横屏可选档（此点请主聊天与 Miller 确认，我方判断：照图二图三的实拍形态做 64）。
- 缝的定位（`src/components/wall/seamPlan.ts:3-8` 文件头＋:44-60）：缝只开在**块边界**（12×8 块阵列的块间线）上，没有砖跨过缝被挤窄或切断；开口的世界 x 由 `getSeamBoundaryX(column)` 给出（块左缘往前半个间隙处）；选界规则＝离基准线（视口中线）近、相机让位最小；开口放不下时相机只让最小距离（SEAM_EDGE_MARGIN=14px，缝与视口边至少留 14）。
- 缝与相机（seamPlan.ts:5-6 原文："The split belongs to the world (it rides with the camera) and narrows as it nears a viewport edge, closing completely once it leaves."）：缝有固定世界坐标，平移时随世界一起动；接近视口边缘时收窄、出界关闭；折叠后屏幕侧边留一枚竖排标签（BRAVAIS_EDGE_TAB，ponderBravaisSeamGeometry.ts:EDGE_TAB），点它在当前视口重新裂开。
- 每帧落位（`src/library/suites/bravais/bravaisFrame.ts:293-312`、`BravaisSeam.tsx:20-24`）：缝的屏幕位置由 stage 每帧按相机直接写在轨道层 transform（translate3d）上，缝内容按「当前渲染那一套」的宽度排版居中、被变窄的缝裁掉、翻转不重排。原生对应：缝视图的 frame 每帧由 wallLayout.worldOrigin/cameraScale 换算，与砖实例同一条相机通路。
- 墙砖让位方式（`ponderBravaisSeamGeometry.ts:86-105` bravaisWallTileRect 注释）：缝变宽时两半墙各自往外让，**磁贴本身尺寸不变**，不是把砖挤窄。原生对应：实例布局在缝线两侧各加 seamWidth/2 的世界偏移（WallLayout 实例生成处接入），砖的 rect 尺寸不动。

### 缝内构成（从上到下）

**主页缝**（真实实现 `BravaisSeamHome.tsx` 文件头 fb2/fb3/fb4/fb11 ＋教程几何 `ponderBravaisSeamGeometry.ts:118-142` 相对比例）：
1. 页头：「书库」小字一行（横排，缝顶）→ 折叠钮单独一行 → **五个一级页签竖排**：歌单、电台、专辑、本地、Navidrome（教程 TAB_GLYPHS 与 PonderBravaisHomeSeamSurface.tsx:62-64；真实页签来自层描述 seam.tabs）。页签是真按钮列（writing-mode 竖排），纵向放不下时先藏「书库」行、再缩成一个字（useBravaisSeamTabsFit 三级缩减）。
2. 中段（页头与工具格之间剩余空间里**竖直居中**）：扫描进度（仅扫描时）→ 二级切换（本地：文件夹/专辑/艺术家/歌单；Navidrome 的 section）→ 管理隐藏开关 → 状态行。
3. 直达入口（中段底部、贴账户位）：特殊集合竖排文字并排成列（我喜欢的音乐、私人 FM 等），与二级切换之间一道分隔线；放不下挪进「⋯」菜单。
4. 过滤输入位：仅输入中/有过滤词时出现在导航区与账户入口之间；书脊档只剩一个强调色过滤图标。
5. 账户入口：贴工具格正上方（fb4），已登录＝头像切换钮、未登录＝「连接在线平台」；平台列表从入口往上弹出盖在导航区上。
6. 工具格（底部固定）：两列图标格，常驻四格＝**搜索、设置、队列、「⋯」**（BravaisSeamHomeTools）；「⋯」菜单从工具格上方弹出（本页签项在前：过滤当前页/管理隐藏，一道分隔线，app 级去处在后：回到播放页）。
7. 舞台开着时工具格上方多一行舞台行、账户入口跟着上移（BRAVAIS_HOME_DOCK_STAGE）。

教程几何（相对缝高，PonderBravaisHomeSeamSurface 档）：书库标题 top 0.028、折叠 0.066、页签区 0.112–0.468（每签高 0.062、间隔 0.07）、二级切换 0.482–0.662、直达 0.672–0.772、账户 0.782–0.854、工具格 0.86–底（搜索/设置在上行、队列/⋯在下行，各宽 0.32）。

**选中态样式**（BravaisSeamHome.tsx fb3 注释＋PonderBravaisHomeSeamSurface.tsx:97-105）：一级页签选中＝**填色块**（圆角 10、白色 13% 填充、字不透明度 1，未选 0.5）；二级切换选中＝**强调色文字/图标＋左侧一道强调色细线**，且只有选中项显示竖排文字、其余只剩图标。两套选中态刻意不同形。

**歌单页缝与主页缝的差异**（`PonderBravaisStripSurface.tsx` 文件头＋`BravaisSeamCollection.tsx`； Miller 图二形态）：
- 集合页默认是 **300 完整信息条**：‹＋面包屑（书库 › 当前层）→ 过滤输入位 → 引号夹着的竖排大标题（整块是按钮，点它收成书脊）→ 元数据 → 描述 → 播放全部/加入队列/收藏星 → 列表钮与「⋯ 更多」（菜单末项是「折叠信息条」）。
- **书脊形态（图二实拍，64）**：从上到下＝返回 ‹ → 折叠钮 → **竖排歌单名**（点它展开回完整条）→ **竖排计数**（图二「285 首」）→ 播放钮 ▷ → 展开钮（BRAVAIS_SPINE_GEOMETRY：back 0.024、fold 0.088、title 0.16–0.54、count 0.56–0.62、play 0.84、expand 0.905）。
- 完整条可再加宽成 **420 列表面板**（横排标题＋工具行＋可滚动歌曲列表，悬停行联动墙上对应砖亮起）。
- 主页缝是「导航」（页签/入口/账户/工具），集合缝是「当前集合的身份与动作」（标题/计数/播放/列表）——构成不同、骨架同（缝＋书脊＋折叠标签三档）。

### (85) 原生复刻清单（几何与构成）

- 缝宽：手机竖屏定版 64（书脊档）；缝高贯穿世界可视高度；缝线＝世界块边界（原生墙块阵列的列界，取离视口中线最近、让位最小的一条）。
- 缝随 worldOrigin 平移（与砖同帧换算）；近视口边收窄、出界关闭＋侧边竖排标签（点它在当前视口重裂）。
- 实例让位：缝两侧实例世界 x 各偏移 seamWidth/2，砖尺寸不变；开口/关闭走与网页同量级的补间（缝 0.36s、相机 0.42s，bravaisConstants.ts:59-60）。
- 主页缝构成（书脊档）：书库行＋折叠钮＋竖排五页签（歌单/电台/专辑/本地/Navidrome——原生无 Navidrome 页签则按既有四项，报告须明说）＋中段二级切换＋直达入口（我喜欢的音乐等）＋账户头像＋底部工具格（搜索/设置/队列/⋯）。选中态两套：页签填色块、二级切换强调色＋侧线＋只亮文字。
- 歌单页缝构成（书脊档）：‹＋折叠＋竖排歌单名＋竖排计数＋播放钮＋展开钮；展开档（300 等比）构成按完整条清单。
- 撤除：HomeSidebar84View 左缘固定条、左上角小白线（速记簿把手）及其内容（Miller 第 1 条明令）。

---

## 审计二：关灯点亮无放大

**结论**：放大没作用错层——它写在 WallPosterCell 的 imageView 上，两墙也确实都用 WallPosterCell；真凶在同类的 layoutSubviews：**每次布局都把 imageView.frame 重设为满幅**，与 transform 放大冲突，点亮后任意一次布局（点按本身触发的全墙重刷就会带来）就把放大吃掉；压暗 alpha 是普通属性、不受 frame 重设影响，所以真机只剩「亮」没有「大」。另有一个次因：放大倍率只有 1.1，小砖上本就弱。

### 定位

- 放大实现：`WallPrototypeViewController.swift:4458-4476`（WallPosterCell.applyLightFocusZoom83）：焦点态给 imageView 加 CGAffineTransform(scale 1.1)、layer.zPosition=10，弹簧 0.45/0.86。触发链是通的：宿主点按 → WallLight82.consumeTapIfNeeded 置焦点（WallLight82.swift:99-105）→ playFocusTap 全墙重刷（WallLight82.swift:123 起）→ 每砖 applyLight82 → 焦点砖 applyLightFocusZoom83(focused:true)（WallPrototypeViewController.swift:4431-4449）。
- 冲突点：`WallPrototypeViewController.swift:4238-4244` layoutSubviews 无条件执行 `imageView.frame = shadowView.bounds`。UIKit 下对带非 identity transform 的视图设 frame 行为未定义、实际效果是按新 frame 的 bounds/center 落位、缩放被覆盖。点亮流程里全墙重刷、粒子、焦点转移都会引发可见砖重排；且滚动中 configure→applyLight82(animated:false) 也会反复走布局。结果：transform 即使动画起来，也在下一拍布局被清回 identity——与 Miller「只亮不放大」逐项吻合（压暗走 lightDimView82.alpha，WallPrototypeViewController.swift:4436-4443，不经 frame/transform，所以亮这一半活了下来）。
- 渲染层核对：主页墙与歌单墙的砖**都是 WallPosterCell**（两墙共用同一 cell 类，WallLight82.swift:107 注释与两宿主 applyToVisibleCells 均按 WallPosterCell 取），不存在「主页墙是 lattice 自绘、放大写错层」的问题——(84) 验收里「疑作用错渲染层」的猜测不成立，问题在 frame/transform 之争。
- 次因：scale 1.1（:4463）对 100pt 级小砖只大 10pt，且放大的是 imageView 本体、砖的占位与阴影（shadowView）不动，观感进一步打折；Miller 要的是「与平时点按展开一样的慢慢放大」。

### 修法选项（(85) 三选一，建议 A）

- **A．layoutSubviews 认放大态**：layoutSubviews 里先设 frame、随后按 lightZoomed83 重落 transform（动画中则跳过 frame 重设或在动画结束后以 completion 复核）。改动最小，但动画期间的布局仍会打断弹簧，需要「放大动画进行中」旗标配合。
- **B．放大改走容器**：给 imageView 外加一层容器视图（容器 frame 由 layoutSubviews 管），放大 transform 只作用于 imageView 本体、其 frame 只在容器尺寸变化时设一次。结构最干净，根除 frame/transform 之争；改动面＝cell 子视图层级＋coverFrame(in:) 换算复核（:3907-3910 用 imageView.convert，层级变化后要复测 hero 飞行帧）。
- **C．放大改走 bounds**：焦点态改 imageView.bounds.size×1.1＋center 不动（bounds 与 frame 分离、layoutSubviews 设 frame 时……frame setter 仍会写 bounds，不推荐）。
- 配套：倍率建议与点按展开同量级感（1.1 起步、可到 1.15）；(85) 加一条 light85 见证：焦点落定后 0.6s 读 imageView.transform 是否仍为目标 scale（是＝放大存活），下轮日志可直接判这条生死。

---

## 审计三：点头像不滑到正在播放

**结论**：现行代码里**没有任何一个头像绑了 locate**——工具条头像与 (84) 新加的侧栏头像都打开账户卡 popover；真正绑 locate 的只有点播台的**封面区**（不是头像）。Miller 点头像得到账户卡、「不能滑到正在播放的歌曲」是字面事实。另有一层：就算走封面区通路，主页墙那条也只有「来源歌单可知且在本墙内」时才真滑动，其余情形改开舞台页（不滑）。

### 头像清单与绑定

| 头像 | 位置 | 点按去向 | locate |
|---|---|---|---|
| 工具条头像 | SeamToolbarView.swift:99-103（avatarButton）→ HomeWallViewController.swift:3280 onAvatarTapped | seamAvatarTapped() → AccountCard62 账户卡 popover（HomeWall:3849-3872） | ✗ |
| 侧栏头像 | HomeSidebar84View.swift:26-63 → HomeWall:3906 sidebar.onAvatar | 同上 seamAvatarTapped()（账户卡；锚点仍在工具条头像处） | ✗ |
| 歌单墙工具条头像 | WallPrototype 同款工具条 | 同为账户卡通路 | ✗ |
| 台面封面（非头像） | HomeWall 台面封面区 → :2165 locateCurrentTrackFromCover；歌单墙封面区 → WallPrototype:1332-1335 locateCurrentTrack | 见下 | ✓（仅此） |

### locate 通路与空转点

- 主页墙封面区（HomeWallViewController.swift:2221-2260）：先决条件 `QueueManager.sourcePlaylistId ∈ playlistIds`。不满足（从搜索/队列/舞台起播、来源不是主页歌单等）→ via=stage 分支：打开当前曲舞台详情页（locate82 host=home via=stage），**不滑动**；无在播曲 → via=none＋toast。满足 → 现开一个 WallPrototype 歌单墙、置 locateCurrentTrackWhenReady、present 后由对方定位。
- 歌单墙内（WallPrototypeViewController.swift:1986-2060）：按 id 在 entries 里找当前曲（同 id 全数计数 sameId）；找不到 → miss81 fb=stage 开舞台（不滑）；找到 → locateNearestInstance 选最近实例 → animateWorldOrigin 相机平移 → 落点展开＋verifyLocateLanding 校验纠正。**空转点**：`locateNearestInstance` 返回 nil 时在 :2024 直接 `guard ... else { return }` 静默退出（「locate start」已落、之后无任何行）——这是通路里唯一无声死点。
- locateCurrentTrackWhenReady 消费点有两处（WallPrototype:2355-2357 种子落地、:2597-2599 视图在场），旗标被提前消费/重复置位时序复杂，但两处都有落痕可查。
- 与定版口径的冲突：2026-11-24 01:33 定版「单击头像主页/歌单页＝切换到正在播放的歌曲」，而 (62) 的「墙上头像改 popover 账户卡」绑定从未让位——(82) 第 3 条「点头像下沉」落的其实是台面封面区通路，头像本尊始终是账户卡。(85) 须二选一并明说：头像改绑 locate（账户卡挪到侧栏账户位/长按）或保留账户卡、把「点头像」口径正式改到封面区——这是产品口径冲突，审计不替 Miller 拍板，但代码事实是：**按现行绑定，点头像永远不可能滑到在播歌曲**。

### (84) 日志判读这条的见证名

- `sidebar84 tap dest=avatar` ＋紧随的 `wall.seam.avatar`：出现即证明点的是头像、去的是账户卡（与 locate 无关）。
- `locate82 host=home via=wall/stage/none`、`locate82 host=wall via=self`：封面区通路的分流结果（wall＝真滑、stage＝改开舞台、none＝无在播）。
- `locate start`（带 queueIndex/sameId/entries）与后续落点行、`locate miss81 fb=stage/none`：判歌单墙内定位走到哪一步；只有 start 没有下文＝命中 locateNearestInstance 静默死点。
- `tap84` 判不了这条（tap84 只覆盖台面四钮的 down/up）；`minibar.tap host=homewall zone=cover action=locate` 是封面区分发行的辅助对位。

---

## 审计四：点播台两问

### (a) 收起态点击有时不弹出来

**结论**：(84) 把台身识别器从台身本尊（全台子树的祖先）改挂到一块叶子层 deckSurface84 后，台身上**仍有交互开启的兄弟层压在它上面**，其中 seek 命中带在收起态正好盖住细条中央带、且它的点按回调在收起态直接空转返回——点在细条中央带的触摸进不了展开链；边缘带能进、根级几何认领（mb.claim78）能救一部分，点在宠物身上又被根级认领按设计让行。三者叠加＝「有时弹、有时不弹」。tap84 判不到这条（它只记四钮）。

定位：
- 改挂点：HomeWallViewController.swift:1820-1854（WallPrototype:994 起、Stage:3335 起同构）：longPress/doubleTap/tap/collapsedTap/agnosticTap74 五件全挂 deckSurface84。deckSurface84 是台身的第一个子视图（HomeWall:1475-1484，全台尺寸、透明），其后加的子视图都在它之上。
- 压在它上面且**交互关闭**的层已逐个核实无害：blur（:1459 isUserInteractionEnabled=false）、MiniPlayerThemeLayer（MiniPlayerThemeLayer.swift:89 自身及全部子层关闭）、rimLight、glassTint（均 false）。
- **真盲区**：miniSeekHit（HomeWall:1681-1684 装配 seekTap；约束 :1780-1783：左右贴台边、top=轨道顶−9、高 27）。收起态轨道就是细条本体，seek 命中带＝**整条台宽×27pt 的中央带**；它是普通 UIView（交互默认开）在 deckSurface84 之上，触摸命中它即归 seekTap，而 miniSeekTapped 第一行就是 `guard !miniBarCollapsed else { return }`（HomeWall:2284）——收起态点中中央带，触摸被 seek 链领走后无声丢弃，collapsedTap/agnostic 都在 deckSurface84 上、收不到这一下。同理 progressTrack/fill/knob 等普通 UIView 也在 deckSurface84 之上（面积小，次要）。
- 对照 (83)：识别器挂在台身本尊时，seekHit 是其后代、触摸照样到达台身识别器——此盲区是 (84) 改挂新引入的，不是老毛病复发。
- 为何不是全灭：①细条命中带纵向外扩 44pt（MiniBarHitView hitExpansionY=14，HomeWall:2638），seek 带只占中央 27pt，上下边缘带（约 17/44 的面积）的触摸能落到 deckSurface84 → collapsedTap 正常展开；②根级认领 MiniBarRootTap78（MiniBarHitView.swift:151-225）挂在宿主根视图、按几何认领，不受台内层级影响，落 mb.claim78/mb.disp78 后展开——但它对**宠物落点按设计让行**（bail=pet，:213-218），而宠物正站在细条上（Miller 图一/图四/图五皆然），点中宠物＝不弹（语义上归宠物点按）；③形态旗标与几何失同步时它也认不了（bail=form）。
- (85) 修法方向：收起态禁用 seekHit 交互（setMiniBarForm 两态互斥时同步 seekHit.isUserInteractionEnabled），或把 seekTap 的收起态分支直接转 expandMiniBar；并给展开链补一条与 tap84 同级的见证口径（见下）。
- 见证判读（(84) 日志）：`minibar.touch75 col=1`（触摸到达台身）→ 有 touch75 无 `minibar.hit`/`mb.claim78` ＝死在台内分发（与本条盲区对位）；`mb.root79 bail=pet` ＝点在宠物上；`mb.claim78`+`mb.disp78` 有而台没弹＝ expand 之后形态段的问题。**tap84 对这条无判读力**（只覆盖展开态四钮 down/up）。

### (b) 「时间快超出屏幕外面」

**结论**：按约束逐项算，**没有任何宿主/方向会让时间标签真的出屏**；最接近他这句话的形态在**舞台台**：右时间标签不锚台右缘、而是顶在控制台钮左侧（与墙台不一致），右端时间被挤在钮边、贴着台缘读作「快出去」；墙台的时间标签则是 34pt 定宽装 11pt 的 "%d:%02d"，≥10 分钟的时长字宽约 31–34pt 已贴满定宽，再长（≥100 分钟）会溢出标签框向两侧冒。他的图二/图三（网页版）是双胶囊：上卡（封面＋歌名）＋下条（左时间＋进度＋右时间，时间在条内两端内收），原生墙台与之同构、舞台台是唯一走样的。

定位与数字：
- 台宽公式（三宿主同）：`min(屏宽, 屏高) − 24` 居中（HomeWall:1688-1692 装配、:961-965 每帧按 viewDidLayoutSubviews 复核；Stage:3168-3169 同式）。竖屏 393−24=369、横屏 min(852,393)−24=369——横竖同宽、左右各留 ≥12，台体本身不出屏。
- 墙台（HomeWall:1766-1773、WallPrototype 同构）：左时间 leading=台左+16、定宽 **34**；右时间 trailing=台右−16、定宽 34、右对齐；轨道夹在两标签之间（:1698-1699）。时间格式 StageViewController.formatTime（:4121-4125）`%d:%02d`：11pt medium 下 "9:59"≈25pt、"12:34"≈31pt、"62:23"≈31pt——34 定宽只剩 3pt 余量；UILabel 默认不裁字，超宽时字会冒出标签框（视觉上「往外跑」），≥100 分钟（"102:34"≈37pt）必然冒框，但仍在台内（台外还有 16pt 边距＋12pt 屏边距），不出屏。
- 舞台台（Stage:3228-3233）：左时间 leading=台左+16、定宽 44；**右时间 trailing 不锚台右缘，锚 stageConsoleButton82.leading−8**，而控制台钮在进度行右端（台右−12、宽 30）——右时间右缘落在台右−50 处，与墙台的 −16 不一致；且轨道右界跟着它走（stageTrackTrailC 锚 totalTimeLabel.leading−8，:3179）。视觉上时间＋控制台钮在右端挤成一簇、时间贴着钮边——(84) 报告自认的「舞台与墙台仅此一位差」就是这处。
- 网页参照（图二/图三底部）：下胶囊内左时间 00:09、右时间 02:23 分居条内左右两端、轨在中间，右端另有独立的滑杆钮在胶囊外/边缘——时间不与功能钮同簇。
- (85) 施工口径：舞台台右时间改回与墙台同锚（台右−16、定宽与墙台统一），控制台钮移出进度行（回主排右端，与 (84) 第 1 条墙台形态统一）；墙台时间定宽 34→40 并给轨道让位账（369 台宽内：16+40+8+轨+8+40+16=128＋轨 241，够）。此条的精确所指（舞台右簇 vs 墙台冒框）日志判不了（fm84 的 tw 是台宽非标签宽），以本节两处定位为准、请 Miller 验收时指认。

---

## 审计五：横屏小白条量测

**结论**：任务点名的两份文件实测都是**竖屏**截图、底部亮条同为系统线 140pt；同批真正的横屏图（9CC5…，1179×543）里系统横线量得 **≈218pt 宽**——(84) 用的 209 是上一代机型的惯例值，14 Pro 横屏应取 **218**。(85) 改 collapsedTrackWidth 横屏档 209→218，其余（高 5、底距 8、我方条贴线上方 2pt 净空）公式不变。

### 量测过程

- 任务点名文件核对：`560A144E….jpg` 与 `5FC4DFD6….jpg` 均为 1179×2556（竖屏），底部亮段两份一致：x 380–799＝**420px＝140pt**、y 2517–2531＝高 **15px＝5pt**、底边距屏底 24px＝**8pt**——与 (83) 的系统线量测逐项相同。这两份图判读：该亮条在距底 8–13pt 带内，是**系统横线本人**；(84) 我方条应在其上方 15–20pt 带（y 2496–2511），该带内无整亮段（我方轨是白 0.25–0.35 底＋进度填充，未达整亮阈值，属正常形态，不是缺席）。
- 真横屏图：同批 `9CC5E17A….jpg`（1179×543，系 2556×1179 设备像素按 0.4613 缩放，换算：文件 px ÷0.4613＝设备 px，÷3＝pt）：
  - 底部整亮条：宽 ≈302 文件 px → 655 设备 px → **218.2pt**；厚 7 文件行 → ≈**5.1pt**；底边距底 ≈11 文件 px → **7.9pt**；水平居中（x 439–740，中心 589.5＝图幅中心）。高与底距都与系统线规格（5/8）吻合、只有宽不同 → 这条是**系统横线**，横屏宽 218。
  - 其上方一条（距底约 15–19pt 带）：中亮段宽 ≈152pt（低亮阈值下的下限读数）＋中央整亮芯 ≈66pt——位置与 (84) 公式给出的我方条带（15–20pt）吻合，是**我方条**（轨低透明＋白色进度填充＋把手）；其全宽被低 alpha 吃掉、量不出整宽，但位置证明 (84)「贴线上方、不重合」已成立，差的只是宽与系统线不一致（我方 209 vs 系统 218，短 9pt）。
- 交叉依据：209pt 是 iPhone X/XS/11 Pro 世代横屏 home indicator 的常见量测值；Dynamic Island 世代（14 Pro）横屏更宽，本次真机截图量测 218pt 为一手依据，优先于惯例值。
- (85) 取值建议：横屏档 **218**（DeckLayout84.collapsedTrackWidth 的 portrait=false 分支一处常数）；竖屏 140 不动。若改后 Miller 仍觉「小」，剩余差是亮度（轨白 0.25–0.35 vs 系统线近纯白）而非几何，届时单独议轨底亮度、不再动宽度。

---

## 附：(85) 施工输入汇总（给主聊天定清单用）

1. 缝侧栏：按审计一清单以世界缝重做（手机定版 64 书脊档），撤 HomeSidebar84View 与左上角小白线；缝宽档位/主页构成/歌单构成/两套选中态照清单。
2. 关灯放大：按审计二选项 B（容器层）或 A（layoutSubviews 认态）修 frame/transform 之争，加 light85 存活见证；倍率与点按展开同感。
3. 头像：口径冲突须 Miller 拍板（头像改绑 locate 或口径改封面区）；无论哪样，locateNearestInstance 静默死点要补落痕。
4. 点播台：收起态 seekHit 交互互斥（或 seekTap 收起分支转展开）；舞台台右时间改回墙台同锚、控制台钮移出进度行；墙台时间定宽 34→40。
5. 横屏小白条：209→218 一处常数。
