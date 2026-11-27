# (94) 真机日志判读报告 — log-94-verdict

判读对象：`~/workspace/user/files/upload-7c23c768.txt`（Miller 2026-11-27 11:41 CST 发来）
判读人：日志判读子代理（只判读，未改任何业务代码）
对照材料：forensics/delivery-94-report.md（(94) 九项施工与 p94 面包屑设计）、release-94 代码（7d54d040/ec45e723/e7bda386）、Miller 录屏转述（控制台开＋风开、点上一首/播放/下一首有高亮但台不关风不停、退桌面重进仍在、推荐卡始终没出现）、追加图证三张（11:44 列表胶囊截图、11:45 歌单页缝截图、11:47 横屏舞台截图）与 11:40/11:44/11:45/11:47/11:48/11:49 六条口径。
时间口径：日志为 UTC（Z），北京时间 = UTC+8，下文双记。

---

## 〇、会话结构（问题 1）

**已证实**

- 文件 145,880 字节、共 1201 行，分两段：
  - L1–L201「上一会话尾巴」：会话 B 的末 200 行留存（03:37:01.378Z–03:40:47.735Z），由会话 B 被杀时的 `prevtail.save n=200`（03:40:49.093Z）落盘，与本会话段内同一时段的行重复，不是独立会话。
  - L202–1201「本会话」段内含三段会话：
    - **会话 A**（L203 起，02:42:36Z＝10:42 CST 至约 02:43 后）：(93) 构建（02:42:36 首行即 `seam.wrap75 host=stage`，启动行已滚出文件头）。内容为舞台进出（02:42:38 `stage exit.request source=userCloseTap`）＋歌单墙（`mb.root79 on host=wallproto`），与 (94) 无关，仅作对照。
    - **会话 B**（L516 起）：`app.build short=3.7 build=94`（03:36:18.213Z＝11:36:18 CST 启动）→ 03:40:49.093Z `prevtail.save n=200` 收尾（被杀）。**录屏那段完整落在本会话内**（见下）。
    - **会话 C**（L981 起）：03:40:49.097Z 再次 `app.build build=94` 启动 → 03:41:06.112Z 止。内容为入场关闭（03:40:59 `entry dismiss reason=closed`）后进设置页（`settings.tab`、`port90 settings=chips-h/search`）导出本日志。
- 录屏时段定位（会话 B）：控制台呈现 03:37:15.264（11:37:15），风开启 03:37:22.130（11:37:22）；其后 5 次 background 往返（`nowplaying.route armed via=background` 于 03:37:51.541 / 03:39:20.707 / 03:39:23.184 / 03:39:52.804 / 03:40:37.612 / 03:40:47.732，每次均记 `top=ConsolePanel82`），与录屏「退到桌面再重进、控制台仍开着、风仍在飘」逐点吻合；B 以被杀收尾、紧接 C 冷启，与 Miller 11:40:03「直接给 app 后台划掉重新进 app」吻合。
- 环形缓冲滚掉的部分：会话 A 的启动段（文件自 A 中途起）；会话 B 开头完整（launch 在位）。**11:41 导出之后的操作全部不在本日志内**——11:44 列表切换、11:45 歌单缝截图、11:47 旋转截图均发生在导出后（见第八/九/十节）。

---

## 一、风为什么没停（问题 2）

**已证实**

- fx 状态变更行全文件只有一条事件（尾巴与本会话段各存一份）：L863/L88 `2026-11-27T03:37:22.130Z p94 fx sw fx=wd on=1 src=consolebtn state=1`，同簇有 `fx87 wd=1`、`p94 fx arm fx=wd`、`p93 probe arm fx=wd`、`p92 link wind on wall`、`p91 link wind=1`。自此至会话 B 被杀（03:40:49，风共开 3 分 27 秒），**再无任何一条 fx sw**：没有 on=0、没有 src=mutex、没有 src=auto。94-7 设计的 20 处 src 调用点在本日志只出现 1 处（consolebtn，开）。
- 关指令从未发出（不是发了没执行）：控制台钮的 handler 执行时必先经 `ConsoleFX85.tap` 落 `console85 tap el=<元素>`（ConsolePanel82.swift:1753 的 ConsoleFX85.tap；fx 钮 :1476、prev :1452、next :1459、play :1466）。会话 B 内 `console85 tap el=fx87` 仅 03:37:22.123 一条（开风那次），el=prev/play/next 全 0 条。即 Miller 录屏中的后续点按**没有到达控制台任何按钮的 handler**。
- 不存在「执行了又被复开」：`setWind`（GlobalFx87.swift:888）是纯内存状态变更＋落痕，无定时器、无 UserDefaults 持久化、无恢复通路；唯一手动关入口是 `toggleWind()`（:822，src=consolebtn）；互斥关（mutex）只发生在 startFw/startLantern 内（:909/:960 附近），B 内 fw/ln 从未开启。link 通道（p92/p91 link）只在开启边沿落行，不是状态变更源。stepWind 内无 stop 调用（(93) 删的 5 秒硬编码未回潮，与 94-9 审计一致）。
- Fx 窗不是吞点者（代码）：Fx 窗 level 1500 的根视图 `isUserInteractionEnabled=false`（GlobalFx87.swift:553），结构上不接点按；FxOverlayHost91.hitTest 白名单（:410-428）对非 UIControl 命中一律 return nil 穿透。

**推测**

- 点按断在「touch-down 到达按钮（录屏有高亮）」与「handler 执行（落痕）」之间：touch-up 未以 up-inside 完成（被取消或被识别器夺走）。嫌疑面按代码收敛为：控制台呈现层自身的识别器/卡内滚动容器对 touch-up 的取消、以及点外 dim 的两路识别器（ConsoleDimRoot93.onDimTouch93＋手势识别器，ConsolePanel82.swift:230-235）在特效在场时的状态——两路在 B 内均无落痕，日志分不开是哪一层。
- 主窗级探针同沉默（见第三节）提示断点可能在更上层：点按没有到达主窗的识别器层（若曾到达，tapProbe92 的手势回调与控制台 handler 至少应有一处落痕）。但录屏高亮又证明 touch-down 曾到达按钮——两条证据的交集是「touch-down 到达、touch-up 被取消/夺走」，具体夺走者未定。

**未确认**

- Miller 是否点过风钮本身再关：录屏转述只点名点了上一首/播放/下一首；日志内第二次 fx87 点按落痕为 0，与「点过但没到达 handler」和「没点过风钮」两解分不开。但无论哪解，控制台点外不关、播放钮无反应已独立成立（见第二节）。

---

## 二、控制台为何全程未关（问题 3）

**已证实**

- 会话 B 内控制台呈现仅 1 次：L646-647 `03:37:15.264 console82 present host=HomeWallViewController`＋`console85 present form=card`。此后**无任何 dismiss 落痕**（dismissConsole93 的 console85 dismiss 行、(93) 的 p93 dismiss reason 行全 0 条）；`console85 tap el=outside` 0 条（对照 (93) 日志有 2 条且均生效）。
- 控制台存活有独立旁证链：`nowplaying.route begin` 在 03:39:04.148 / 03:39:21.206 / 03:39:41.784 / 03:40:37.612 四次均记 `origin=HomeWallViewController>ConsolePanel82 bgTop=ConsolePanel82`（截断处原文 `bgTop=ConsolePane` 为行宽截断），03:40:47.732 `armed gen=5 ... top=ConsolePanel82`——被杀前 2 秒控制台仍在最上层。
- **「重进仍在」定性纠正**：录屏中的退桌面再进是同一会话 B 内的 background 往返，控制台从未被 dismiss、自然仍在，不涉及状态恢复。真正的杀后重启（会话 C）内**无 console present、无 fx arm、无 fx sw**——控制台与风都没有跨启动恢复，与代码无持久化恢复通路互证。「状态持久化恢复」一说不成立。

**推测**

- 与第一节同根：dismiss 的全部入口（点外 dim 两路、卡内动作钮的 dismissConsole93(reason:"action")）都在 handler 层，点按未到达 handler 层，故 dismiss 从未被调用——不是 dismiss 执行失败或被覆层挡回。

---

## 三、点按归属（问题 4）

**已证实**

- 三代归属探针在 (94) 会话全灭：`p94 fx tap` 0 条、`p92 tap ok` 0 条、`p93 tap own` 0 条。而探针在岗有自证：L865 `03:37:22.132 p93 probe arm fx=wd`（refreshTapProbe92 的 arm 边沿落痕，GlobalFx87.swift:646-665），且探针识别器 `cancelsTouchesInView=false`、delegate 允许共存识别（:632-638、:747-750）。**在岗探针对 3 分 27 秒内的全部点按沉默**——与 (93) 日志同一病象复发（(93) 判读第三节：探针无自证、沉默不可判；(94) 补了自证，结果是在岗仍沉默）。
- 会话 B 全部点按落痕只有 4 簇：`sidebar85 tap dest=navidrome`（03:37:04.854）、`dest=cloud`（03:37:08.891）、`dest=console`（03:37:15.245）、`tap82 host=console zone=fx87`＋`console85 tap el=fx87`（03:37:22.121/123）。03:37:22 之后至被杀，点按类面包屑 0 条；同期 mem tick、nowplaying.route、isl.*、pet.chat 等自动事件照常落盘——日志通道本身没断，沉默只发生在点按链。
- FxOverlayHost91 的层级账（arm 时落盘，L867）：宿主子视图 3 件全 `hid=1`（UIView[178,652,36x82]、UIButton[333,792,46x46]、UIView[120,645,153x161]，即祝福卡/写灯钮/推荐卡当时均隐藏），fxwin 根 UIView[0,0,393x852 a=0.00 hid=0]——arm 时刻无可见覆层卡在场，「黄面」类可见卡盖屏在本时段无对应物（本时段开的是风、无祝福卡触发记录）。

**未确认**

- 点按究竟落在哪一层：本日志判不了。所有归属仪器同沉默，缺的证据是识别器级的原始落痕（shouldReceive/回调进入）——这是 (95) 必须先补的证据位（定案清单第 1 条），补齐前不许再按「覆层吞点」单一假说换实现。

---

## 四、推荐卡（问题 5）

**已证实**

- 呈现落痕 `fx87 rec`（showRecCard 唯一落痕，GlobalFx87.swift:2174）全文件 0 条；卡在整个 (94) 会话从未呈现，与录屏一致。
- **断点定位（代码级定案）**：`showRecCard()` 全仓唯一调用点在烟花时间轴步进内——GlobalFx87.swift:1229 `if t > 12600 && !recShown { recShown = true; showRecCard() }`。wd/ln/sn 的开启路径（startWind/startLantern/startSnow）没有任何呈现调用。即：**只开风时，推荐卡在结构上不可能出现**——不是触发了没呈现，是根本没有触发点。这与 (93) C4/(94) 的设计口径（特效开启期间卡在控制台下方出现、四特效区分入场，showRecCard 内的 fx 入场分支本身就为四特效写了 case）直接矛盾，属移植时触发点漏接。
- 次级门槛（同窗叠加）：recommendationProvider（SceneDelegate.swift:25-45）在队列为空时返回 nil 即静默退出；会话 B 全程队列为空（`nowplaying.route giveup reason=no-queue` 多次、engineTrack=nil 全程），即便当时开的是烟花并满 12.6 秒，也会被 provider 挡下且无任何落痕。
- 宽度对账：`layoutRecCard93`（GlobalFx87.swift:2139-2167）在控制台呈现时以 `ConsolePanel82.presentedCardFrame` 的 minX 与 width 落位（同宽对齐的代码在位）；无控制台时回退 recDefaultPos93。本日志内无 presentedCardFrame 数值行、卡未呈现，宽度无实测可对——同宽只到「代码已改」档。Miller 11:40「推荐歌曲需要适配上面的设置台宽」的口径与该实现方向一致，(95) 随触发修复一并实测。

**推测**

- 无（断点已由代码定案，不需要推测）。

---

## 五、p94 其余自证逐项（问题 6）

**已证实**

- **94-1 几何 geo（14 条，在位且公式落地）**：竖屏 `calc=296x468`——宽 min(296, 393−32)=296 ✓（(92) 公式）；高 852×0.549=467.7→468 ✓（(82) 定版 54.9%）。横屏 `calc=640x216`——宽 min(852×0.86, 640)=640 ✓；高 min(393×0.549→216, cap89)=216 ✓。frame 字段在呈现/旋转动画中有中间值（303x619、278x440、横屏初帧 296x468），落定后均回 calc 值（03:37:15.841 frame=296x468、03:37:39.121 frame=640x216），属转场中间帧、非稳态偏差。
- **94-9 内存高水位（18 条，在位）**：会话 B 峰值 hw=117MB（03:37:39.171，ev=wall.render.audit，旋转时）；会话 C 峰值 104MB（设置页）。均远低于 450MB 硬线。本窗未进舞台/未开圣诞，覆盖面有限，只裁本窗。
- **94-4 主页缝（在位且可用）**：B/C 各 1 条 `p94 seam host=home avatar=1 qr=1 ver=master`；`p94 seam avatar img=ok src=netease` 两会话各 1 条；B 内二维码 open/close 共 8 条（qq/kugou 页签可切、src=button/avatar 关闭均落痕，03:36:37–03:36:47），`p94 seam enrich provider=netease` 1 条。主页缝头像/二维码/自愈链已证实在岗。
- **94-2 pop seg（2 条，数值在位但卡顿无归属）**：`p94 pop seg tap=0 present=6 load=3 layout=9 first=10 inter=576`。已埋点分段全 ≤10ms，first=10ms 在「转场+50ms」口径内；但 inter=576ms 与分段合计（≈10ms）之间有 **566ms 无任何分段归属**。同期 `port90 polaroid print n=10` 在 present 后 11ms 落行（03:37:15.851），仍在 inter 窗内执行。对比 (93) 的 762ms：非受控 A/B，不下「已改善」结论（沿 DS 对账口径）。定案：94-2 的仪器没盖住真正的耗时段，卡顿构成判不了。

**未确认**

- **94-3 deck cov**：`p94 deck render` 全文件 0 条。探针挂在 HomeWallViewController.viewDidLayoutSubviews（:1016 → probeDeckRender94 :2104），守卫为 `miniBarPresented && !miniBarCollapsed && miniPlayButton.window != nil`；B/C 内无 minibar.form 类行可证台的呈现/收起态，守卫是否满足无从对账——探针未触发、无样本，中央钮字形本日志终裁不了。旁证仅有会话 C 启动时旧 (93) 探针的 `p93 deck glyph=play cov=87 fb=0`（03:40:49.263，工厂出口 cov 口径），非 94-3 的最终渲染层口径，不作终裁依据。
- **94-6 旋转四齐门**：`p94 rot` 全文件 0 条。B 内 2 次旋转都在主页、走旧 wall.rotate 管线（freeze gen=3 03:37:39.104 → landed 03:37:39.492，388ms；gen=4 03:37:48.992 → 03:37:49.337，345ms），四齐门只装在 StageViewController、B/C 从未进舞台。via 是 ready 还是 tmo94——无样本，判不了（舞台旋转的专项判读见第十节）。
- **94-5 排版切换 visible**：`p94 wall sw/reanchor/show/abort` 全 0 条；全文件 wall.scroll 的 identityChanged 全为 0、reload 全为 0；render.audit visible=0 仅 4 处且全是会话初始化帧（02:42:47 会话 A 舞台入场、03:36:26 与 03:36:56 会话 B 入场期、03:40:54 会话 C 入场期），无「连续 2 次为 0」的切换序列。B/C 内没有发生任何版式切换（详见第八节），94-5 验收线未被触发。
- **94-4 歌单缝**：`p94 seam host=wall` 0 条（B/C 未进歌单页），日志侧无样本（截图＋代码定案见第九节）。
- **94-7 fx layers / bless**：fx layers 落 1 条（arm 时，见第三节）；`p94 fx bless` 0 条（B 内未开孔明灯、无祝福卡事件），祝福卡防重入未被触发，无样本。
- **94-8 圣诞/web dpr**：`p94 xmas`、`p94 web` 均 0 条（未进舞台），无样本。

---

## 六、追加项 A：排版胶囊「列表」模式黑屏（Miller 11:44）

**已证实（日志侧）**

- 本日志 (94) 两会话内**没有任何版式切换事件**：`p93 layout sw` 0 条、`p94 wall sw` 0 条、`p92 plist mode`（键变更落痕）0 条，wall.scroll 的 identityChanged/reload 全 0。Miller 11:44 的列表切换发生在日志导出（11:41:06）之后，**不在本日志覆盖内**——黑屏本身、origin/drift 数值、三步序执行与否，本日志无样本、无从对账。
- 对照基线：(93) 日志里黑屏时段的实锤组合是 identityChanged=1＋reload 15–21＋render.audit visible=0 连续＋origin −930576→−1189051；本日志全文件无此组合（visible=0 仅初始化帧，见第五节）。

**已证实（代码侧）**

- 三步序的挂载面：歌单页内胶囊回调是唯一入口——PlaylistSeam85View.onLayoutMode93 → WallPrototypeViewController.switchPlaylistLayout93（装配 :1978-1980、本体 :5590）。函数内对模式 0/1/2（collectionView / magazineTable91 / shelfView91）统一换视图，三步序（p94BeginWallSwitch 停惯性 → p94ReanchorWall 重锚 → p94VisibleCount94 验可见 → p94CrossfadeWallSwitch）对三模式共用；**列表模式（mode 1）没有第二条渲染路径，94-5 不是「只盖模式 0」**。且 p94VisibleCount94（:5781-5787）对 mode 1 数 magazineTable91.visibleCells、mode 2 数 shelfCollection91.visibleCells，可见验证口径三模式齐备。
- **旁路存在（定案）**：另有一条不经三步序的路径——主页缝胶囊 onLayoutMode92（HomeWallViewController.swift:4182）只写 UserDefaults 键 foliaPlaylistLayout91、主页自身无模式视图；歌单页下次出现时 viewWillAppear → refreshPlaylistLayoutFromDefaults92（WallPrototypeViewController.swift:5574）→ applyPlaylistLayout91（:5810）直接 isHidden 互换＋reloadAltPlaylist91：**无停惯性、无重锚、无 visible 验证、无交叉淡化、无 p94 面包屑**。若 Miller 是在主页点了「列表」再进歌单（或歌单页在他进入前键已变更），走的是这条旁路，三步序根本不在场。另外 mode 1 的 magazineTable91 背景为纯黑（installPlaylistLayout91 内 `table.backgroundColor = .black`、歌单头 makeMagazineHeader91 亦黑底），旁路直切后若首帧数据/封面未就位，呈现即整屏黑底，与「点进去黑屏」形态相容。

**未确认**

- Miller 11:44 那次切换走的是页内路径还是 appear 旁路（截图只见胶囊列表档选中，两条路都长这样），以及黑屏时 table 是「未呈现」还是「呈现了但无内容」——需含该时段的新日志（切一次列表立刻导出）才能终裁。

---

## 七、追加项 B：歌单页缝与主页母版差异（Miller 11:45 截图＋放行口径）

截图事实（11:45，歌单页，10 首歌单）：头像已在位（94-4 落地）；歌单名胶囊只剩一个点；排版胶囊选中高亮是尖叶形白块压住第一档图标；缝底工具排成 3+2 两排（搜索/齿轮/列表一行、全屏/控制台一行），其下孤置一个大白圆播放钮，prev/next 字形各有一半露在缝界之外；右侧墙面砖块为超宽大矩形，与主页墙比例明显不同。

**已证实（代码逐项对账）**

- **缝宽来源不同**：歌单宿主缝宽由 WallLayout.seamPlan85 以 openWidth=64 规划（WallPrototypeViewController.swift:2103-2106 `seamPlan85(openWidth: 64)`、seamOpenWidth85=64）；主页缝有 64/120 两档（(89)B b-seam-narrow，点标题切换）。母版内部布局按 contentW<100 走窄档分支——歌单缝恒窄档，主页缝当时多在宽档/展开态，这是多项差异的总源头。
- **名胶囊只剩点**：页签行帧 = (x:4, width: contentW−8, height:28)（Seam85Views.swift layoutMainContent 页签行），字 12pt bold、byTruncatingTail（setTabs :710-730）。64pt 缝下胶囊宽 ≈56pt，12pt 粗体 CJK 每字 ≈12pt，4 字即满，长歌单名必然截断。回填本身在位：setPlaylist85 在种子落地时被宿主调用（WallPrototypeViewController.swift:2974，标题与计数同源同行回填），截图中计数附注「10 首」正常呈现——**不是没回填，是 56pt 装不下**；只剩一个点与「长名被截断至只余省略号级残余」的形态一致（该歌单名具体字数日志/截图均未给出，精确截断点未确认）。
- **高亮异形（代码级定案）**：胶囊钮创建时写死 `button.layer.cornerRadius = 15`（Seam85Views.swift:603）；窄档钮宽 =(62−6−4)/3 ≈ 17.3pt、高 30（layoutMainContent :1500-1510）。半径 15 > 钮宽/2（8.65），CALayer 把白底渲染成两端收尖的叶形——与截图逐点吻合。宽档钮宽 ≈40.7 时半径合法、无此象，这就是主页看着正常、歌单缝变形的分界。
- **工具排两排**：窄档（contentW<100）layoutTools 按 rows=2、cols=3 排布（Seam85Views.swift:1404-1408、:1436-1445），歌单宿主工具 5 枚（search/settings/append/expand/console）→ 3+2 两排，与截图一致——是窄档既定折法而非错位，但与播放区叠加后整体显散。
- **播放区出界（代码级定案）**：缝底播放区三钮帧为固定中心偏移——prev (centerX−60, 38)、play (centerX−19, 38)、next (centerX+22, 38)（Seam85Views.swift:1410-1415），总跨 120pt、不随缝宽缩放。64pt 缝下 prev 左界 = 32−60 = **−28（出界 28pt）**、next 右界 = 32+60 = **92（出界 28pt）**——与截图 prev/next 各露半个字形逐点吻合。中央钮 38pt 占缝宽 59%，「孤零零大白圆」的观感同源。
- **墙砖超宽**：两页同引擎（WallLayout，pitch=136）同 cameraScale 公式（WallPrototypeViewController.cameraScale(forWidth:)，宽<640→0.52，HomeWallViewController.swift:967 同调此函数）。差异在落位模式：主页为周期平铺；歌单为 finiteQueueMode 有限场（WallLayout.finitePlacements :247 起）——按 WallTables.templates[0] 跨度序落位、行宽 = max(6, ⌈√(总面积×视口宽高比)⌉)。10 首小歌单场小、单砖跨度大（4–6 格级），屏幕砖宽达约 300pt 级，与截图一致。属模式级设计差异，非宿主个案故障。

**未确认（日志侧）**

- (94) 两会话未进歌单页，`p94 seam host=wall` 0 条，歌单缝在日志内无任何面包屑（正常行与异常行都没有）——本节定案依据为截图＋代码，日志侧无可对账项。

**已批准的设计自由度（Miller 11:45 放行，记入定案）**

- 歌单页这条缝**可以做宽一点**，不必与主页缝等宽硬对齐；优先保证母版排版成形（歌单名完整显示、胶囊高亮规整、缝底成行、播放区不散），不许为了塞进窄缝把排版挤变形。

---

## 八、追加项 C：舞台旋转横屏只剩顶部一条（Miller 11:47 截图）

截图事实：横屏（852×393 级）下汪汪队开大会（petconcert，原生样式）的气泡歌词区只占顶部一条带（气泡被横向拉宽、纵向压扁，宠物头在带下缘露出），下半屏纯黑，只有迷你台浮在黑区中央（中央钮字形在位）；舞台本体没有按新尺寸重排重渲。

**已证实（日志侧）**

- 本日志 (94) 两会话从未进入舞台，`p94 rot begin / native landed / ready / lyric` 全 0 条；截图拍摄于 11:47、在日志导出（11:41:06）之后——**四齐门各自到达时间、揭盖 via 是 ready 还是 tmo94，本日志无样本**。主页旋转的两笔旧管线数据（wall.rotate 388/345ms）与舞台四齐门无关、不作数。

**推测（代码侧，强证据组合）**

- 四齐门的释放条件与「新尺寸已重排」脱钩：p94RotMaybeRelease（StageViewController.swift:1132）的门只验 native landed＋稳定帧≥2（帧计数 p94RotFrameTick :1087 只比 view.bounds 与目标尺寸，网页样式另比 WebView 帧），**不验 layoutStage 是否已按新尺寸执行**；释放时的补轮 p94RotCatchUpLayout（:1168）与转场 completion 的补轮（:1030-1045）都以 stageLayoutPending 为唯一触发，而 pending 只在冻结期有布局请求到达时置位（:1355 单点）。若本次转场 pending 未置位（或已在 alongside 被消费但 stageRotLaidSize86 未更新到目标尺寸），旋转全程可以零重排揭盖。原生样式（petconcert 属此类）的 web 两门在 freeze 起点即预置为真（:952-953），揭盖最早——与截图「内容停在旧几何、压成顶部一条带、下半黑」形态吻合。此为机制级推测，终裁需含旋转时段的新日志（p94 rot ready 的 dt 与同窗 rot84 runs/extra 对账）。

---

## 九、追加项 D：点头像切二维码的动画不流畅（Miller 11:49）

**已证实**

- 功能本身已到达（Miller 图证＋日志互证，见第五节主页缝）：本项只剩动画质量。
- 代码：切换是**无动画硬切**——applyQRVisibility（Seam85Views.swift:939-944）同步互换 `qrPanel.isHidden / mainScroll.isHidden`，无 crossfade、无弹簧、无位移，点开点关均为瞬时跳变。且 openQR94 在同一点同步启动 startQRFlow（网络取码）；showQRImage（:1261-1273）在图到达时于主线程同步做 base64 解码＋UIImage(data:)＋tileQR94 的 240×240 UIGraphicsImageRenderer 重绘（:1275-1289），缺图时 makeQR94 的 CIContext.createCGImage 亦同步出图（:1291-1301）——图像合成全在切换后的关键路径上。

**未确认**

- 掉帧量级：QR 切换窗（03:36:37–03:36:47）在日志内无任何帧间隔面包屑（wall.scroll 汇总只覆盖滚动时段；entry framedrops 只覆盖入场 03:36:20–23 且全干净，maxGap≤18.3ms、gaps50=0）。Miller 的「不流畅」与「根本无动画＋图到达时一次主线程同步合成」的代码事实相容，但帧率数值无数据可裁，不拿无数据冒充结论。

---

## 十、(95) 定案清单

1. **点按断点先取证、再修（风关不掉/控制台关不掉总根）**：断点已收敛到 ConsolePanel82 呈现层 handler 之前（GlobalFx87.swift 的 tapProbe92 在岗沉默＋ConsoleFX85.tap 落痕缺失双证）。(95) 第一步给 tapProbe92 加识别器级原始落痕（shouldReceive/回调进入各一条、arm 时自检落 view 与共存识别器清单），把断点切到具体一层后按层修；同时加结构兜底：特效开启时 fx 钮的关闭通路不许只依赖呈现层 handler 链（Miller 10:58 硬要求：退出路径恒可用，不许再出现只能杀 App）。
2. **推荐卡触发点漏接**：GlobalFx87.showRecCard 唯一调用点在烟花时间轴 t>12.6s（:1229）。修法：呈现触发移到四特效统一开启边沿（任一 setX on=1 的 arm 点调用），入场分支沿用 showRecCard 内既有四特效 case；provider 返回 nil 时落一条 `fx87 rec miss` 自证行，不再静默。宽度随 layoutRecCard93 的 presentedCardFrame 同宽口径实测验收（Miller 11:40 口径）。
3. **pop seg 仪器扩面**：inter 的 566ms 无归属段在 ConsolePanel82 present 路径内（polaroid print n=10 仍在窗内）。修法：seg 分段扩到覆盖拍立得打印与首轮内容装载，inter 做减法归属后再定拆段点；目标口径不变（tap→first ≤ 转场+50ms 已达，inter 须全程可归属）。
4. **deck cov 探针守卫自证**：probeDeckRender94（HomeWallViewController.swift:2104）守卫未命中时每会话落一条低频自证（带 miniBarPresented/collapsed/window 三值），下份日志能分开「台没展开」与「探针没跑」；中央钮字形终裁等该探针真机样本。
5. **列表模式黑屏（旁路并轨）**：appear 旁路 refreshPlaylistLayoutFromDefaults92 → applyPlaylistLayout91（WallPrototypeViewController.swift:5574/:5810）并入 switchPlaylistLayout93 的三步序（或至少补停惯性＋visible 验证＋p94 面包屑全套），不许再有无自证的直切路径；mode 1 黑底 table 的首帧数据就位时机一并核（reloadAltPlaylist91 与 isHidden 的先后）。修后须请 Miller 切一次列表并导出含该时段日志终裁。
6. **歌单页缝（按 11:45 放行口径）**：歌单缝适度加宽（seamPlan85 openWidth 64 上调，具体值以「歌单名完整显示＋工具排一行＋播放区 120pt 跨度不出界」三条同时成立为准）；胶囊钮 cornerRadius 改随帧钳制（min(15, min(w,h)/2)，Seam85Views.swift:603）；名胶囊在加宽后仍装不下时改缩字号下限保护，不许截断到只剩点；播放区三钮跨度改随缝宽缩放（窄档等比收分或改纵排，Seam85Views.swift:1410-1415）。
7. **舞台旋转第五门**：p94RotMaybeRelease 加「已按目标尺寸重排」条件（stageRotLaidSize86 == 本次 targetSize，未满足则释放前无条件补一轮 layoutStage＋pushSnapshot 再揭盖，StageViewController.swift:1132/:1168）；`p94 rot ready` 行加 laid=WxH 字段自证。修后须请 Miller 舞台横竖各转一次并导出日志，看 via 与 laid 对账。
8. **二维码切换动画**：applyQRVisibility 改 iOS 系统弹簧动画（主区/码区交叉淡化＋轻位移，系统曲线）；二维码图预生成——取码完成即在后台线程完成 base64 解码＋tileQR94 合成并缓存，动画关键路径只做视图切换；补 `p94 seam qr anim` 帧间隔自证行，下份日志对账 60fps（Miller 11:49 口径）。
9. **搜索页换设计 A（新增项，Miller 11:48 点选）**：搜索页换成 design-samples-92/search-design-a.png（拍立得版）的构成与排版落原生，替掉现行网页原样搬来的搜索页；功能通路保持现行行为不变（三平台勾选、单曲/专辑/歌单页签、结果打开不收窄当前墙），只换设计与排版。
10. **证据缺口总注**：本日志判不了的四处（点按断点层、列表黑屏、舞台旋转 via、歌单缝日志侧），根源都是「操作时段不在日志内」或「仪器在岗沉默」。(95) 验收时请 Miller 对每处各留一段操作再导出日志，判读侧才有样本终裁——不要再用无样本的包反复试错。

---

## 十一、结论速览

**已证实**
- 录屏时段＝会话 B（11:36:18–11:40:49 CST，build=94），B 被杀、C 为导出日志会话；「重进仍在」是同会话未 dismiss 的结果，无跨启动恢复。
- 风全程只开未关：fx sw 仅 on=1（src=consolebtn）一条；关指令从未发出——后续点按没到达控制台任何按钮的 handler（ConsoleFX85.tap 落痕为据）；setWind 无定时器/持久化/复开通路。
- 控制台呈现后从未 dismiss（dismiss 落痕 0 条），route 四次 begin 记 bgTop=ConsolePanel82 为存活旁证。
- 三代点按归属探针在岗（p93 probe arm 在位）却全沉默，与 (93) 同病复发；03:37:22 后点按类面包屑全灭而自动事件照常。
- 推荐卡从未呈现，断点在代码：showRecCard 唯一调用点在烟花时间轴 t>12.6s，风/灯/雪开启路径无触发；同宽落位代码在位、无实测。
- geo 公式双向落地（296×468 / 640×216 与 (92) 宽＋54.9% 高逐项对上）；mem hw 在位、B 峰值 117MB 未越线；主页缝头像/二维码在岗可用（qr 开关 8 条）。
- pop seg：first=10ms 达标口径内，但 inter=576ms 中 566ms 无分段归属。
- 列表黑屏不在本日志内（(94) 两会话零切换事件）；三步序对三模式共用、列表无第二路径，但 appear 旁路（refreshPlaylistLayoutFromDefaults92→applyPlaylistLayout91）不经三步序且无面包屑。
- 歌单缝四处变形全部代码对上：名胶囊 56pt 装不下长名（回填在位）、高亮 cornerRadius=15 > 钮宽/2 成叶形、工具排窄档 2 行折法、播放区固定 120pt 跨度在 64pt 缝下双侧各出界 28pt；墙砖超宽是 finite 有限场模式的设计差异。
- 二维码切换为无动画硬切（applyQRVisibility 同步 isHidden 互换），图像解码/合成在主线程关键路径。

**推测**
- 点按断点在 touch-down 与 handler 之间（touch-up 被取消/夺走），嫌疑在控制台呈现层识别器/滚动容器与 dim 两路识别器，日志分不开具体一层。
- 舞台旋转顶条：四齐门释放不验「已按新尺寸重排」，pending 未置位时可零重排揭盖，与截图形态吻合；终裁待含旋转时段日志。

**未确认**
- 点按落在哪一层（归属仪器同沉默）；Miller 是否点过风钮再关。
- deck cov 中央钮字形（探针未触发、无样本）；94-6 四齐门 via（无舞台样本）；94-5 验收线（无切换样本）；圣诞/web dpr（未进舞台）；祝福卡防重入（未开孔明灯）。
- 列表黑屏的路径归属（页内三步序 vs appear 旁路）与黑屏时 table 状态；歌单名精确截断点；二维码切换掉帧量级。
