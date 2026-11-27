# (95) 适配自查审计 — Miller 14:22 两条真机反馈的自查结论

- 分支：release-95（审计时点 HEAD `4ecb9073`）。**只审计、未落码。**
- 触发：Miller 2026-11-27 14:22 —— ①「适配你自己看看吧」（(95) 适配问题我方自查，不等他逐条点名）；②播放台暂停键明显和其他图标不一样。
- 表述三档：**已证实**＝代码几何/数值可直接复算；**推测**＝机制成立但视觉后果须真机/日志裁决；全部结论均为静态审计，无一条真机已验。
- 审计基线：站立 iOS 适配清单（横竖屏双向独立＋旋转重排、安全区/灵动岛避让、系统手势不冲突、深色与字号下限、iPhone 14 Pro 尺寸）。

---

## 一、暂停键不一致定案（已证实，代码级四断点）

对象：胶囊台四钮（上一曲/播放-暂停/下一曲/控制台入口），三宿主（HomeWallViewController、WallPrototypeViewController、StageViewController）构建代码逐行同构，以下断点三宿主全中。

### 断点 1（主因）：四钮字形不是同一种画法——暂停是全实心，上下曲是细描边

字形工厂 `DeckGlyph82.coreGlyph`（Deck82.swift:117-176，24×24 画布）：

| 字形 | 画法 | 线宽/墨量 |
|---|---|---|
| `.play` | 三角**描边、无填充**（triStroke w=1.7） | cov 约 2–4%（工厂以 2% 为丢失兜底线，常规态在其上） |
| `.pause` | 双圆角矩形**全填充**（2.5×8.4 ×2，r 1.25） | cov ≈ 7.3%（工厂注释自记 ≈73‰） |
| `.prev` / `.next` | 竖条填充（2.2×7.6）＋三角**描边 w=1.4** | 介于两者之间 |
| `.consoleNotes` | notesGlyph91 全**填充**（符头/符干/符尾全.fill()，Deck82.swift:640-682） | 实心 |

即同一行四钮有三种处理：play 三角描边 1.7、prev/next 三角描边 **1.4**（与 play 都不一致）、pause 全实心双条。播放态（常态）下中央是两条粗实心白条、两侧是细描边三角——墨量差约 2–3 倍，「明显不一样」有直接代码成因，不需要真机再证。

### 断点 2（次因）：只有播放/暂停钮有一整块毛玻璃盘底，其余三钮没有

三宿主构建处，播放钮独有 `UIVisualEffectView(UIBlurEffect(style:.systemUltraThinMaterialDark))` 整钮插入（HomeWall:1725-1731、WallPrototype:878-884、Stage:3414-3420，port90 任务 14 旧制）；prev/next/console 三钮只有 A4Chrome91 的渐变层（alpha ≤0.15）＋边框。于是中央钮盘面明显更「 frosted/发白」，与三钮的近透明盘面不同款——此差异在 play/pause 两态恒在，暂停态与断点 1 叠加最显眼。

### 断点 3：与控制台传输行并不同款——播放字形差 2pt，且 (95) 是主动改远的

Miller 12:09 的验收线是「与控制台传输行逐字同款」。控制台口径（ConsolePanel82.swift:1413、1434，port90 注释明文「字号与播放台严格对齐（播放/暂停 21、上下曲 19）」）：传输行播放/暂停字形 **pointSize 21**、上下曲 19。(95) 第 11 条把舞台与歌单墙的播放字形由 21 **改到 19**（StageViewController.swift:2366-2372 注释、WallPrototype:1255-1263 注释均自记「原 21」），主页墙构建/回刷本就是 19（HomeWall:1718、2126-2132）。现行：控制台 21 vs 播放台 19——同款未成立，且方向是 (95) 把原本对齐的两个宿主改远。另：台面控制台入口字形 pointSize 20（HomeWall:1776 等），一行内字号 19/19/19/20 三种。

### 断点 4：刷新路径三宿主不对齐——舞台回刷不重挂字形层、两宿主无最终层自证

- HomeWall、WallPrototype 的回刷路径（refreshDeckIcons82、切歌回刷）setImage 后均调 `A4Chrome91.rehangGlyph`（HomeWall:2139、3102；WallPrototype:1263、2342）——(94) 94-3 的定向修法。
- **Stage 的 refreshPlayButton（StageViewController.swift:2366-2372）只有 setImage、无 rehang**；舞台播放钮同样有 blur＋A4 渐变两层插入子视图，状态切换后 imageView 与插入层的 z 序无人重申（94-3 判读认定的丢失机制在舞台回刷路径上仍然敞口）。
- 最终渲染层 cov 探针（`p94 deck render`）与 (95) 守卫行（`p95 deck guard`）**只存在于 HomeWall**（全仓 grep：两串仅 HomeWallViewController 命中）；WallPrototype、Stage 无探针——(95) 报告第 8 条「探针已按新胶囊台最终渲染层采样」实际只覆盖 1/3 宿主，另两宿主的字形存活在日志上不可判（与 (94) 日志「deck render 0 条」的仪器缺口同型，只是换了宿主）。

### 修法（(96) 候选，验收线＝控制台传输行逐字同款）

1. 字形统一画法：coreGlyph 四字形同语言重定——play/prev/next 三角与 pause 双条同线宽（以控制台现行视觉为准，建议描边统一 1.7 或 pause 改描边双条），消除实心/描边混排；改后工厂 cov 四字形同量级并落痕对账。
2. 盘面统一：播放钮的整钮 blur 子层或撤、或四钮同加（与控制台中央钮同处理——控制台中央钮亦有 blur 子层，若以控制台为母版则四钮中仅中央钮有 blur 属母版原样，此项须与 Miller 的「其他图标一致」口径二选一，审计建议撤 blur、四钮同为 A4 渐变面，与他 14:22 原话「和其他图标不一样」的指向一致）。
3. 字号回对齐：播放台播放/暂停字形回 21（控制台现行值），prev/next 维持 19，consoleNotes 20→19 或随控制台入口字形同值，全行字号收为 21/19 两档。
4. 舞台 refreshPlayButton 补 rehang；cov 探针＋guard 行补齐 WallPrototype、Stage 两宿主，三宿主同仪器。

---

## 二、(95) 全部改动的 iOS 适配自查（逐项）

### 1. 胶囊台（三宿主）——主体成立，三处不成立/存疑

**成立（已证实）**：
- 台高单一出处 `MiniBarQuickRowView.expandedBarHeight = 62`，三宿主同源（MiniBarQuickRowView.swift:80-85；三宿主 `p95 deck capsule h=62` 落痕齐）。
- 横屏不拉伸：三宿主台宽恒 `min(屏宽, 屏高) − 24`（HomeWall:1821-1823、WallPrototype:987-989、Stage:3532-3533 且 Stage 在 viewDidLayoutSubviews 按当前 bounds 更新，Stage:1745-1746；公式对旋转对称，常量无需随朝向改），居中、左右 ≥12 兜底。
- 安全区：三宿主底锚均为 `safeAreaLayoutGuide.bottom − 10`（HomeWall:1852-1853、Stage:3530-3531），收起态底锚 +31.5 与 home indicator 重合的旧口径未动。
- 收起细条态：高 16、圆角 8、纵向命中扩到 44pt（hitExpansionY=14，HomeWall setMiniBarForm），收起态 seek 带禁交互（点中央死的老问题修法保留），三宿主同构。
- 宠物沉降衔接：MiniBarPetStage 层框/地面逐帧读台子演示层帧（MiniBarPetStage.swift:961-973 syncFrame/currentGroundY），与台高数值无关——112→62 后宠物自动跟随新台面，落定延迟 0.55s 钩子（barFormChanged）三宿主调用点齐。**成立**。
- 字号：歌名 15 bold / 歌手 12，三宿主同值（HomeWall:1695、1702 等），≥12 下限成立；双时间标签两形态隐藏（(95) 第 5/6 条）后无 10pt 字在屏。
- 几何不重叠（竖屏 369 宽账）：封面 11+40、钮簇自右 10+40+8+40+8+46+8+40=200，歌名区 61→159 约 98pt 可用，约束为 lessThanOrEqual 不钻钮簇下（HomeWall:1884-1912、Stage:3596-3637 同构）。

**不成立/存疑**：
- **(a) seek 命中带由 27pt 缩到 15pt（已证实几何）**：(95) 第 8 条把命中带改锚「轨顶 −10、底锚 bar.bottom、删高 27 常量」；展开轨高 3、轨底距台底 2 → 轨顶在台底上方 5pt，命中带实高 = 10+3+2 = **15pt**（HomeWall:1940-1943、Stage:3643-3647 同式）。3pt 细轨配 15pt 命中带，远低于 44pt 系统命中下限，拖动 seek 的容错明显变差（旧制 27pt 亦不足、但 (95) 进一步收窄）。视觉细轨是 Miller 定版，命中带可独立放大而不动视觉——(96) 候选：命中带顶改轨顶 −20、底延出台底（台外部分由 bar 的父级命中转发或扩大 hit 区），或至少恢复 27pt。
- **(b) 三钮命中 40pt < 44pt（已证实，属样片定版取舍）**：prev/next/console 钮面 40×40、播放 46×46（HomeWall:1901-1912）；展开态无 hit 扩张（MiniBarHitView 的扩张只在收起态）。Miller 样片定的尺寸，列为取舍项低优先。
- **(c) 字形/盘面不一致**：见第一节（本节不重复）。

### 2. 歌单缝加宽 120 —— 歌单宿主成立；主页缝 64 档被母版改动打出新缺陷（不成立）

**成立（已证实）**：歌单宿主（WallPrototype）缝宽三处同值 120（首规划/重开 seamPlan85(openWidth: 120)，WallPrototype:2166、2189；展开档 120↔300），A/B 避缝起点同步 120（杂志头 x=120/宽 −140、编号 x=120/封面 x=156/textX=212、shelf sectionInset.left=120、架头 leading 120）；横屏下绝对起点 120 仍成立（内容宽随屏宽放大）；胶囊钮圆角改布局时 `min(w,h)/2` 钳制（Seam85Views.swift:1621-1622），尖叶形根治；缝底三钮跨度 `span95 = min(120, contentW − 8)`（Seam85Views.swift:1518），120 档下三钮全界内（contentW=112 时 span=104，prev/next 各 [∓52, ∓14] 不出界）。

**不成立（已证实，(95) 引入）**：**主页缝 64 书脊档下，缝底三钮由「出界」变「互相重叠」**。主页缝宽仍是双档（64/120，SeamState85.narrow120 切换，HomeWall:4331-4333），而 (95) 6d 的新跨度公式在 SeamMaster 共用母版内对主页同源生效（(95) 报告自认 (b)(c)(d) 主页同源）。contentW=64 时 span95 = min(120, 56) = 56、side95 = 56/2 − 19 = 9：prev 帧 [centerX−28, +10]、play [−19, +19]、next [−10, +28]——三只 38pt 钮挤进 56pt 跨度，彼此重叠约 20pt（Seam85Views.swift:1518-1525 几何复算）。旧固定偏移在 64 档是双侧出界 28pt（(94) 判读定案），新公式在 120 档治好、在 64 档换成了重叠——64 档三钮本就放不下（3×38=114 > 64），须窄档专属形态（缩钮或纵排），不能靠跨度公式通吃。(96) 候选高优先。

**存疑（推测）**：歌单名 pill 缩字下限——12pt bold × minimumScaleFactor 0.66 ≈ **7.9pt**（Seam85Views.swift:733-734，代码注释自记「下限 ≈8pt」）。120 档 pill 变宽后触发缩字的概率已低，但极端长名一旦触发即跌破可读下限；更稳妥是下限抬到 0.85（≈10pt）＋尾截断，或长名两行。视觉后果须真机。

### 3. 搜索页设计 A —— 列阵成立，动作钮命中不成立，封面裁切未确认

- **成立**：列数按宽自适应 2/3/4 列（SearchWorkspaceView.swift:331-335，≥560 三列、≥900 四列），横屏（852 宽）三列成立；卡片整卡可点；题注字号 15/12/11 均 ≥11（角标由 9 抬 11，:489 注释自记硬线）；底色双层 ignoresSafeArea、内容在安全区内。
- **不成立（已证实）**：卡内三动作钮（日记本/星标/加号）命中框 **30×30**（:540、554、564，contentShape 即 30 矩形），低于 44pt 系统下限——(95) 报告已自记此取舍，审计维持不成立判定，(96) 候选：视觉字形 14 不变、命中框扩到 44（contentShape 加 padding 或 frame 44＋字形居中）。
- **未确认（推测）**：封面 `.aspectRatio(1.22, contentMode:.fit)`（:485）——封面原图为方形，1.22 横幅框的实际呈现（裁切上下还是留白）取决于 NativeCoverView 内部缩放，静态审计定不了，(95) 报告亦自记为视觉假设；须真机截图裁决。

### 4. 二维码弹簧动画 —— 成立

`applyQRVisibility`（Seam85Views.swift:954-1001）：UIView spring（0.45s / damping 0.86 / velocity 0.6）＋交叉淡化＋4pt 轻位移，options 含.allowUserInteraction 与.beginFromCurrentState（动画中可打断、不锁点按）；码图解码＋tile＋CIContext 出图已移后台队列按 payload 缓存（showQRImage，:1345-1377），主线程只赋值；帧间隔自证 `p95 seam qr anim` 在位。横竖屏共用同一 SeamMaster 矩形原地切换，缝宽两档下 QR 尺寸 `max(40, min(contentW − 12, …))`（:1650）——64 档 52pt、120 档 108pt，均 ≥40 可扫下限（52pt 档的可扫性 (94) 已记为待实扫，非本轮新增）。**成立**。

### 5. 控制台 geo —— 成立

宽：竖 min(296, 屏宽−32)、横 min(0.86 屏宽, 640)；高：竖横同为屏高 ×0.549 取整、横屏再与 cap89（屏高 − 底安全区 − 90 − 56）取 min 防冲顶（ConsolePanel82.swift:830-850）。与 (94) 日志实测（竖 296×468、横 640×216）逐值一致；布局后回写 presentedCardFrame 并同步特效钮/dim 登记帧（:855），旋转后登记帧随 layout 更新。**成立**。

### 6. 舞台旋转第五门 —— 机制成立，但自证是「盖章」不是「实测」（部分成立）

`p94RotMaybeRelease`（StageViewController.swift:1138-1152）：laid!= target 时清 pending、无条件补一轮 layoutStage＋pushSnapshot 后**直接把 stageRotLaidSize86 赋值为 target 再递归**——赋值不回读 layoutStage 实际使用的几何（若此刻 view.bounds 尚不是 target，排的是旧尺寸、记的却是 target）。ready 行落的 laid=/target= 因此恒相等，自证力打折：它证明「补排轮跑过」，不证明「按 target 排过」。真断点（pending 未置位时零补排）已被堵住，故判部分成立。(96) 候选：laid 改为补排后回读实际排版尺寸（如 layoutStage 落点处同 alongside 路径的赋值法，:995 以实测 size 写 laid），ready 行才恢复裁决力。另：3 秒 tmo94 安全网仍在（:1186-1203，门未齐亦揭盖）——(94) 起的存量待决项，去留仍待 Miller 定，本审计不重复立项。

### 7. 其余 (95) 条目

- 第 5 条版式归一：appear 旁路已并轨 `switchPlaylistLayout93(mode, src95: "appear")`（WallPrototype:5641-5652），与缝胶囊同实现同落行；列表直显前可见性验证 `p95 wall bypass` 在位（:5914-5920）。**成立**。
- 第 1/2 条（点按黑洞/dismiss）：属手势链而非排版适配；登记帧随控制台 layout 更新（见 §5），无适配面新增问题。吞点按的具体层仍未定性（(95) 报告自认），不属本审计范围。
- 第 3 条推荐卡：呈现宽读 ConsolePanel82.presentedCardFrame 与控制台同宽（(95) 报告＋代码），控制台 geo 已验（§5），**成立**。
- 第 4 条弹台分段仪器：只补仪器、无 UI 变更，无适配面。

---

## 三、(96) 候选修复清单（按严重度排序）

### 已证实（代码证据在上文标注）

1. **播放台暂停键与四钮不一致**（Miller 点名）：coreGlyph 四字形画法统一（play/prev/next/pause 同线宽同语言）；播放钮整钮 blur 盘面与其余三钮统一（撤或同加，见 §一修法 2 的口径选择）；播放字形 pointSize 19→21 回控制台口径；舞台 refreshPlayButton 补 rehang；cov 探针补齐另两宿主。
2. **主页缝 64 档缝底三钮重叠**（(95) 6d 引入）：窄档（contentW<100）三钮改专属形态（缩至 30pt 并收跨度、或纵排），120 档现行公式不动；主页/歌单双宿主、双档四组合逐个验几何。
3. **舞台旋转第五门 laid 改实测回读**：补排后以实际排版尺寸写 laid，ready 行恢复裁决力；防「排了旧尺寸、记了新尺寸」。
4. **搜索页三动作钮命中 30→44**：字形不动、命中框扩 44。
5. **胶囊台 seek 命中带 15pt 放大**：视觉细轨（3pt）不动，命中带至少恢复 27pt、争取 44pt（顶 −20 起＋台外转发方案二选一，落码前出账）。
6. **歌单名 pill 缩字下限**：minimumScaleFactor 0.66→0.85 或长名两行，极端长名不跌破 ≈10pt。
7. **胶囊台三钮 40pt 命中**：Miller 样片定版尺寸，若 (96) 顺手可加 invisible 命中扩张（视觉不变、命中 44），不改视觉。

### 推测（机制成立、后果须真机/日志裁决，不许按已证实排期）

- 搜索页封面 1.22 横幅的裁切/留白形态（§二.3），真机截图裁决后再定改法。
- 宠物收起态步行域 ±92 与现行收起轨宽 140 的匹配（MiniBarPetStage.swift:984-985，(95) 之前存量、非本轮引入），真机看宠物是否走出线外再定。
- tmo94 3 秒安全网去留：存量待 Miller 定，非缺陷立项。
