# (98) 定案修复方案 — 代码审计（基于 release-97 / HEAD 23e7e6e1）

审计范围：圣诞树内容为空、排版切换卡、胶囊台尺寸面包屑、封面爱心位置、中缝二维码慢。
证据来源：(97) 真机日志（upload-77419afa.txt）＋ release-97 源码逐行核对＋ (96) 版同文件 diff。
本文件只审计与定方案，未改任何源码。

---

## 1. 圣诞树「什么都没有了」

### 已证实

1. **粒子数学与 (96) 逐字相同，断点必在 (97) 新写的传输层。**
   `ChristmasTreeStageRenderer.swift` 与 (96) 版（edf825df）全量 diff：粒子尺寸/alpha/目标/时序表达式零变化，(97) 只换了三处——画布（UIView.draw → MTKView）、精灵贴图（CG 逐粒 draw → 图集＋实例化）、提交方式（setNeedsDisplay → submit＋canvas.draw()）。
2. **图集字节序与纹理格式不匹配（颜色全错的实锤）。**
   图集位图上下文用 `premultipliedLast | byteOrder32Big`（ChristmasMetal97.swift:197-198）——该组合在内存中产出的是 **R,G,B,A** 字节序（代码注释自称 BGRA，写反了）；而纹理建为 `.bgra8Unorm`（ChristmasMetal97.swift:214），采样时按 B,G,R,A 解释 → **R/B 通道互换**。金星精灵本色 (1, 0.85, 0.47) 互换后即 (0.47, 0.85, 1) 蓝色——与录屏中「金星变蓝星」逐项吻合；红灯 (1, 0.36, 0.28) → 蓝、雪点 → 暖白，全表颜色错位同理。
3. **fps 面包屑证明不了画面内容。**
   fps 统计在 frameTick 内、绘制门之前执行（ChristmasTreeStageRenderer.swift:187 调用 noteFrameInterval，绘制门在 :205）。日志 fps=59.8–59.9 只证明宿主 CADisplayLink 在跳，不证明 draw() 真的画出了精灵。
4. **精灵 pass 有静默跳过门且全链无实例数自证。**
   draw() 里精灵 pass 的条件是 `sprCount > 0, let atlasTexture`（ChristmasMetal97.swift:280）：atlasTexture 为 nil 时整 pass 无声跳过、无任何面包屑。现网没有任何面包屑记录「每帧提交了多少精灵/三角形」——无法从日志区分「实例没喂进来」与「喂了但没画出来」。

### 推测（按可能性排序）

A. **图集行序（v 轴）错位。** buildAtlas 的翻转绘制（ChristmasMetal97.swift:171-226：translate/scale 翻转＋按 `atlasH - y - h` 落图）与 uvRects 的 v 区间（:222-226，按 placement.y/atlasH 直算）之间，若内存行 0 的朝向假设反了，每粒精灵会采样到图集的镜像行：小点（192px 档）多半落到暗衬底/空隙（alpha≈0 或近黑），而星（768px 大图）仍能采到内容——与录屏「只有星可见、其余全空」吻合度最高，但无运行时证据可坐实，须靠 (98) 新增面包屑在真机二分。
B. 通道互换（已证实第 2 条）叠加 A，使即便采到的内容也颜色全错、观感更暗。

### (98) 改法

1. 修字节序（定点一行）：ChristmasMetal97.swift:197-198 的 bitmapInfo 改为平台标准 BGRA 组合 `premultipliedFirst | byteOrder32Little`，与 :214 的 `.bgra8Unorm` 对齐；注释同步改正。
2. buildFrame97 的早退守卫（ChristmasTreeStageRenderer.swift:604）拆成带原因的面包屑再返回（sprites 未就绪 / treePos 空各一行），不许无声返回。
3. draw() 精灵 pass 在 `sprCount > 0` 但 atlasTexture 为 nil 时落一次性面包屑（ChristmasMetal97.swift:280 处）。
4. 若真机新面包屑显示实例数正常（约 1 万/帧）但画面仍空，则只动一个变量：uvRects 的 v 区间翻转（ChristmasMetal97.swift:222-226，v0′=1−v1、v1′=1−v0）验证推测 A，不许同时改其他东西。

### 新增自证面包屑

- `p98 xmas spr`（≤15 字节 ✓）：随现有 5 秒 fps 行同拍，带 `n=<本帧精灵实例数> tri=<三角形数>`——内容是否在喂的唯一判据。
- `p98 xmas uv`：mount 建图集后一行，带 `atlasH=<高> uv13=<星的 uvRect>`，供行序对账。
- `p98 xmas notex`：精灵 pass 被 atlasTexture 缺失跳过时落（一次性闩锁）。

---

## 2. 排版切换卡（apply 恒 vis=0 entries=0）

### 已证实

1. **两条切换路径的可见性守卫都以「entries 非空」为前提，数据未到时整体旁路。**
   - `applyPlaylistLayout91()`（WallPrototypeViewController.swift:6144）：守卫分支只在 `vis == 0 && !entries.isEmpty` 时成立（:6178-6205，含一次重试与守卫返回）；entries 为空时无条件执行视图互换（:6211-6213），把空目标视图亮出来，函数尾还把重验旗 `p96GuardDeferred91` 复位为 false。
   - `switchPlaylistLayout93()`（:5898，缝切换正路）：visible==0 且 entries 非空 → 异步重试一次，仍 0 则**回滚旧版式并改写持久化键** foliaPlaylistLayout91（:5958-5966 区段），用户点选被静默吞掉；visible==0 且 entries 为空 → 直接 crossfade 到空视图（:5977 区段 fallthrough），不设任何待重验旗。
2. **数据到达后的二次 apply 只有一个开关，且恰好在上述情形下永远为关。**
   种子落点（:3160）与分页落点（:3257）的重跑条件都是 `if self.p96GuardDeferred91`；而该旗只在「entries 非空且 vis==0」的守卫分支里被置 true（:6180、:6195 区段）。entries 为空时切的版式，数据到达后只调 `reloadAltPlaylist91()` 刷当前 mode 的数据（:3156、:3253 区段），不重跑 apply/switch 的验证与互换收口。
3. **每次进页的第一条 apply 必然 entries=0。**
   `installPlaylistLayout91()` 在 viewDidLoad（:468）装配末尾（:5872）即调 apply，而 `loadEntries()`（:573 发起，种子赋值在 :3133）是异步网络往返——apply 时 entries 恒空。与日志「每次 apply 都是 entries=0」逐项吻合；apply 本身 ms=4–10 很快，卡的不是耗时，是**切过去的是空布局且没有补切机制**。
4. 数据源本身没问题：杂志表行数（:6349）与书架格数（:3443）都直读 `entries`，seed asm n=283 正常——数据通路断在「切换时序与重验触发」，不在数据。

### 推测

- 用户感知的「点进去就卡、只能杀 App」= 情形组合：加载中切版式 → 亮空黑页（杂志表/书架底色为纯黑，installPlaylistLayout91 内 table/shelf 背景 .black）；或点选被回滚吞掉、再点无反应；切回 mode 0 时墙补刷依赖 p94ReanchorWall 消费 wallReloadPending97（:6062），与 visible 验证叠加后同样可能被回滚挡住。本条为机制推演，具体命中哪一支待 (98) 新面包屑回读。

### (98) 改法

1. 新增待切登记旗 `pendingLayoutMode98: Int?`：两条路径在 entries==0 且目标 mode≠当前可见 mode 时，不互换、不 crossfade、不回滚改键，只登记 pending 并落面包屑，保持当前视图不动。
2. 种子落点（:3156 区段）与分页落点（:3253 区段）在 reloadAltPlaylist91() 之后，把重跑条件由 `p96GuardDeferred91` 扩为 `p96GuardDeferred91 || pendingLayoutMode98 != nil`，命中 pending 时以登记的 mode 重跑 switchPlaylistLayout93 一次并清旗。
3. applyPlaylistLayout91 在 entries==0 时只做装配、不做 isHidden 互换（:6211-6213 整段以 entries 非空为执行条件），并同样登记 pending。
4. switchPlaylistLayout93 的回滚分支（:5958-5966）不得改写持久化键：只回滚视图，键保留用户选择，改走 pending 补切。

### 新增自证面包屑

- `p98 layout pend`（15 字节 ✓）：登记待切时一行，带 `mode=<目标> entries=<当时条数>`。
- `p98 layout redo`（15 字节 ✓）：数据到达补切执行时一行，带 `mode=<目标> vis=<补切后可见数>`。

---

## 3. 胶囊台尺寸：面包屑在撒谎，真高是 72

### 已证实

1. **真实高度是单一出处常量，(97) 已是 72，不是 62。**
   `MiniBarQuickRowView.expandedBarHeight = 72`（MiniBarQuickRowView.swift:89）；git 记录 (97) 提交 11a5cad0 把该常量 62→72（同提交注释：胶囊圆角随高改 36、三宿主共 12 处同步）。
2. **三宿主全部引用同一常量，无第二出处：**
   - 主页墙 HomeWallViewController.swift:1836（高度约束）、:2900（形态回写）
   - 歌单墙 WallPrototypeViewController.swift:1009、:1978
   - 舞台 StageViewController.swift:3638（bar 高度约束）、:1607、:1782、:4289
3. **写死的 "h=62" 面包屑是 (95) 时代的字符串、(97) 改高时漏改：**
   HomeWallViewController.swift:1855、WallPrototypeViewController.swift:1188、StageViewController.swift:3782，三处均为字面量字符串，不读任何变量。
4. **日志里有真话面包屑且与代码互证：** `p95 deck size=<expanded>/<row>`（MiniBarQuickRowView.swift:202，插值打印）。(97) 导出日志中该行出现两种值：`72/43` 共 19 条（(97) 会话）、`62/43` 共 92 条（同一导出里留存的旧会话）——运行实测 (97) 台高就是 72。Miller 仍觉小是尺寸偏好问题，不是没生效。

### (98) 改到 84 的点位清单

1. **唯一必改点**：MiniBarQuickRowView.swift:89 常量 72→84。全部高度约束与形态回写（上列 8 处引用）自动跟随，不许逐宿主改数字。
2. **圆角字面量 9 处**（现 =36 = 72/2）：HomeWallViewController.swift:1481、:1543、:1605；WallPrototypeViewController.swift:650、:717、:771；StageViewController.swift:3297、:3354、:3394。改法：不要再写新字面量 42，统一改为 `MiniBarQuickRowView.expandedBarHeight / 2`，杜绝下次改高再脱节。
3. **三处假面包屑**（上列第 3 条行号）：字符串改为插值实测值（见下）。
4. 不动：收起高 16 与 rowHeight 43（MiniBarQuickRowView.swift:60）与本项无关；钮/封面尺寸（40）与轨道锚点均相对 bar 底/中心锚定，自动跟随。

### 面包屑修正（即新增自证）

- 三处统一改为：`p98 deck cap h=\(Int(MiniBarQuickRowView.expandedBarHeight)) host=<home|wall|stage>`（名段 `p98 deck cap` 12 字节 ✓）。保留 MiniBarQuickRowView.swift:202 的 `p95 deck size=` 作交叉对读，两行同场不一致即视为构建串包。

---

## 4. 封面爱心位置

### 已证实（现行锚点逐处）

1. **墙面（主页墙＋歌单墙共用 WallPosterCell，WallLight82.swift:114 注明两墙共用）：**
   WallPrototypeViewController.swift:5084-5091（layoutSubviews）：爱心圆片 24×24，x = 卡宽−30（右内距 6 ✓），但 **y 不是底锚**：默认（拍立得）档 y = titleY − 30，即悬在标题带上方——有副行时圆片底边距卡底约 39pt，视觉上浮在封面右下区域而非贴角；仅纯图档 y = 卡高−30（底内距 6）。右上 ➕ 日记钮在 (卡宽−30, 6)（:5061-5062），与爱心分居上下，不相撞。
2. **歌单 B 书架（PlaylistShelfCell91）：** WallPrototypeViewController.swift:6621-6622：封面 150×150 在 (0,0)，爱心 18×18 在 (126, 124)——右内距 6、底内距 8，三处里最接近贴角，只差底边 2pt 不齐。
3. **歌单 A 杂志（PlaylistMagazineCell91）：** :6440-6441：爱心 18×18 在行右部（x = 行宽−76，因其右邻 ➕ 钮）、垂直居中——这是**列表行**的爱心，不在封面上（封面是行首 44pt 小图），不属于「封面爱心」范畴。
4. **舞台没有封面爱心。** StageViewController 的爱心是顶栏 chrome 的 likeButton（StageViewController.swift:58 声明，:1750 frame = (屏宽−50, headerTop, 38×38)，:2520 refreshLikeButton），在标题栏右端、不锚任何封面；舞台封面即歌词舞台画布，无固定封面图可锚。

### (98) 改法（统一「最右下角」口径：右/底内距各 6pt）

1. WallPosterCell（WallPrototypeViewController.swift:5084-5091）：heartY 两档统一改为底锚 `bounds.height − 30`（与纯图档现行值一致），即圆片 frame = (卡宽−30, 卡高−30, 24, 24)。配套：标题/副行 label 宽度由卡宽−12 改为卡宽−42（右让 30），防长标题与爱心压字；展开态爱心本就隐藏（heartHidden91 含 controlsVisible），无冲突。
2. PlaylistShelfCell91（:6621-6622）：y 由 124 改 126，凑齐右/底各 6pt。
3. 杂志行爱心（:6440-6441）：不动（非封面爱心，位置由行布局与 ➕ 钮决定）。
4. 舞台：无可移对象，本包不动；若 Miller 指的是顶栏 likeButton 要挪位，属 chrome 改版，须他另行点名落点（舞台无封面锚点可挂）。

### 新增自证面包屑

- `p98 heart pos`（13 字节 ✓）：每类 cell 首次 layout 时一行（类级闩锁防刷屏），带 `host=<wall|shelf> r=<右内距实测> b=<底内距实测>`——验收直接读数，不再靠截图目测。

---

## 5. 中缝二维码登录刷新慢

### 已证实（完整通路与串行点）

通路：点头像 `avatarTapped`（Seam85Views.swift:1412）→ `openQR94()`（:1044）→ `startQRFlow()`（:1066）→ `runQRFlow`（:1085）→ 按平台进 `runOneQQQRCode` / `runOneKugouQRCode`。

1. **QQ 是串行三跳，每跳一整次函数往返：**
   Seam85Views.swift:1129 `fetchChannels()`（QQLoginClient.swift:60，GET /login/channels）→ :1133 `fetchKey(channel:)`（QQLoginClient.swift:76，GET /login/qr/key）→ :1134 `createQR(key:)`（QQLoginClient.swift:87，GET /login/qr/create）。三个 await 严格串行，前一跳不回下一跳不发。
2. **第一跳 fetchChannels 几乎纯浪费：** 它只为决定 channel 参数，而 channel 缺省就是 "qq"、静态回落集 `fallbackChannels = ["qq", "wechat"]` 已在客户端（QQLoginClient.swift:51）；声明结果不缓存，每次开码、每次切平台都重付一整跳（冷启时最贵的一跳）。
3. **酷狗串行两跳：** Seam85Views.swift:1244-1245 `fetchKey()`（KugouLoginClient.swift:72，/login/qr/key）→ `createQR(key:)`（KugouLoginClient.swift:89，/login/qr/create）。
4. **每跳的传输层还有主备串行：** ProviderLoginTransport.getJSON（ProviderLoginTransport.swift:58 起）节点序为 Netlify 同源代理优先（folia-music.netlify.app/api/qq|kugou，:36-47）、EdgeOne 直连为备；主节点失败/超时（timeoutIntervalForRequest=20，:29-33）才换备节点——主节点慢失败时单跳最坏叠加两次往返。session 为共享 default 配置，连接可复用，但函数冷启动与上游（QQ/酷狗接口）往返每跳必付。
5. **切平台 = 从零开始，且开流即毁缓存：**
   `qrTabTapped`（Seam85Views.swift:1424）直接 startQRFlow，后者先把 qrCachedKey95/qrCachedImage95 清空、图清掉、起菊花（:1070-1076）再跑全链。现有的 payload 缓存（showQRImage，:1352）是单槽且只在同一 flow 内按 payload 命中，跨平台/跨 flow 不存活；对另一平台没有任何预取——开 QQ 时不热酷狗，切回 QQ 也不复用。旧会话样本「QQ 开码 → 切酷狗开码间隔约 5.9 秒」与酷狗两跳冷启往返的量级吻合。
6. **全程零计时面包屑：** 只有 qr=open/close 与 login.qq.* / login.kugou.* 结果行，没有任何一跳的耗时字段——慢在哪一跳，现网日志不可判读（与本次审计前提一致）。

### 推测

- 5.9 秒的构成大概率是「每跳各付一次函数冷启（Netlify/EdgeOne）＋上游接口往返」，但无分段计时，不能把秒数拆到具体跳；(98) 先补计时、再按数据决定是否动后端。

### (98) 改法

1. **计时面包屑先行**（判读前提）：startQRFlow 落 T0；每跳完成落分段；出图落总时（见下）。
2. **砍掉 channels 串行跳：** channel 改用会话级缓存——首次成功探测后本次 App 生命周期内复用，冷启首开缺省直接用 "qq" 发 fetchKey，fetchKey 失败才回头探测 channels。QQ 链路由 3 跳变 2 跳。
3. **默认平台预取 key＋函数预热：** 缝首次构建时（Seam85Views.swift:482 既有 `p94 seam host` 落点旁）或主页 viewDidAppear 时，按 openQR94 同判据（第一家未登录、QQ 先）后台预跑该平台 fetchKey，缓存 (key, 生成时刻)；开码时 key 年龄 <120s（QQ unikey TTL 180s、留 60s 余量）直接 createQR，省一跳；同时对另一家发一次 fetchKey 级请求作预热（结果同样入缓存，切过去直接可用）。**不预取整码**：二维码 TTL 自生成起算，预取过早反而缩短可扫窗口；只预取 key。
4. **切平台双槽缓存：** qrCachedKey95/qrCachedImage95 改为按 provider 的双槽 (key, 图, 生成时刻)；startQRFlow 不再无条件清缓存——切回某平台时其槽未过前端有效窗（QQ 175s / 酷狗 300s，各留 15s 余量）则直接复用图、以原 key 续轮询（runOneQQQRCode / runOneKugouQRCode 需加「既有 key 入口」，跳过取码段直入 check 循环）；过期才整链重跑。
5. 后端候选（非 (98) 必做）：key+create 合并为一步出码端点可再省一跳，需 folia-qq / folia-kugou 函数侧改动，待计时数据回来再定。

### 新增自证面包屑

- `p98 qr seg`（10 字节 ✓）：每跳一行，带 `prov=<qq|kugou> stage=<ch|key|create> ms=<该跳耗时> node=<命中节点序>`。
- `p98 qr total`（12 字节 ✓）：二维码图上屏时一行，带 `prov=<…> ms=<点头像到出图总耗时> cache=<0|1>`（cache=1 表示命中预取/双槽缓存）。

---

## 附：(98) 验收口径提醒

- 第 1 项：fps 不再作内容证据，以 `p98 xmas spr` 的实例数为准。
- 第 2 项：以 `p98 layout pend/redo` 是否成对出现验收补切机制。
- 第 3 项：`p98 deck cap` 与 `p95 deck size` 两行数值必须同场一致。
- 第 5 项：以 `p98 qr total` 的 ms 与 cache 标记验收，目标：命中缓存时出图 <1s、冷启全链有分段数据可读。
