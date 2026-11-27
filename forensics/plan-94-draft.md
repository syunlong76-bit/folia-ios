# (94) 施工单草案 — (93) 真机失败判读/审计/DS 对账收口

状态：草案，未落码。依据：(93) 真机日志 `~/workspace/user/files/upload-36ba0fb4.txt`、Miller 五图（2026-11-27 10:36）、release-93 相对 release-92 代码审计、DS 对抗评审（原文 `forensics/ds-review-94-raw.md`，简报 `forensics/ds-review-94-brief.md`）。

## 〇、判读三档（先行结论，施工前提）

**已证实**
- p93 面包屑全量仅 4 条（deck size、deck host=stage、pop gap=762ms、dismiss r=dim）；其余 p93 自证（mem/fw dt/xmas fps/glyph cov·fb/tap own/wallcache）在本日志 0 条——主会话仅约 2 分钟且开头被环形缓冲滚掉，特效在本日志从未开启（fx87 行 0 条），多类自证是「无样本」而非「已判死」。
- 控制台弹出 gap=762ms（同期 wall.scroll max=633.2ms），未达 <50ms 目标；(93) 已把拍立得打印移出弹出路径，gap 仍在 600ms 级。
- 控制台点外关闭本日志 1 实例生效：outside 点按 → dismiss r=dim，间隔 2ms。
- 排版切换黑屏时段（上一会话尾巴 02:29:51–54Z）:wall.scroll 连续 identityChanged=1、reload=15–21、hitch 最高 30.8%、p95 152.9ms;render.audit 连续 visible=0、origin.x 由 −930576 跑到 −1189051、drift=4783（上限 2280）、pkv=410933。
- 旋转 3 次 freeze→landed 各约 330ms；主会话内无 >1.2s 日志行间隔。
- 图四控制台实测：卡宽 ≈292–300pt（音量行宽＋包围盒双锚）、卡高 658pt（屏高 77%）。
- 图三主页墙展开台中央钮为空圆无字形；同工厂字形在图四控制台可见。
- 原生两条缝均无头像/二维码（面包屑自书 port88 seam=avatarless）；歌单缝竖排标题与计数、胶囊叠印（图二）。
- 圣诞原生渲染器四处 UIGraphicsImageRenderer fmt.scale=1（屏幕 scale=3）。

**推测**
- 黑屏机制：identity 切换时 fling/惯性未停＋重锚缺失，旧速度在旧虚拟坐标上把 origin 推出合法域（DS 排序第 1、2 位与我方一致；事件先后顺序日志未给出，机制为强证据组合、非单链实锤）。
- pop gap 构成：crossDissolve 转场约 0.3s＋控制台构建/首次布局约 400ms 级主线程阻塞；「卡点在 viewDidLoad」未经分段计时证实。
- 图四卡宽 ≈296 与 (92) 公式一致、(93) 的 min(620, w−20) 未呈现为 370:机制未定（呈现上下文 bounds 非全屏宽为首要嫌疑），须几何面包屑定案。
- 中央钮丢失环在工厂之后的按钮视图栈/刷新覆盖;pause 字形无兜底是放大因素。
- 「特效黄面」最可能为孔明灯祝福卡（深棕渐变＋琥珀边）经被动识别器反复弹起（DS Q3 结论），未证实。

**未确认**
- 特效页吞点按全案（时段不在日志内）；风 5 秒自关的真机行为（代码删除已证实，风未在日志开启）；烟花流畅度；圣诞样式真机帧率与糊的构成（图五为 sonnet 非圣诞）；特效时段内存峰值（窗口内峰值 359MB 未越线，但特效未开、高水位采样缺失）。

## 一、DS 对账（逐条裁）

| DS 意见 | 裁 | 理由 |
|---|---|---|
| 总判：先修探针可信度，单样本不许归因 | 采纳 | 与我方「优化前先看日志」同向；落为 94-9 基建项 |
| pop gap <50ms 目标定义不成立（含转场）,须分段计时 | 采纳 | 762 含 crossDissolve;94-2 改分段仪器＋目标重定义 |
| 606 vs 762 非受控 A/B、不许判「不降反升」 | 采纳 | 撤回我方判读原措辞，改述「仍在 600ms 级、未达标」 |
| 黑屏：只 clamp 不停惯性会再被推出；crossfade 源必须 visible>0 | 采纳 | 落 94-5 三步序（停→锚→验可见才淡化） |
| origin 负百万本身不必然空区（虚拟坐标） | 部分采纳 | 同意单条不成立；但 visible=0＋drift＋pkv 同窗组合仍是强证据，维持推测级表述 |
| 旋转：freeze 释放绑 content-ready 而非固定 330ms | 采纳 | 落 94-6（native layout＋WebView resize＋JS stage.ready＋2 稳定帧） |
| C4 音量行反推卡宽不可靠，须 bounds 日志 | 部分采纳 | 我方为双锚（音量行＋包围盒）互证 ≈296–300，非单锚；但定案确实须几何面包屑，落 94-1 |
| C4 高度回滚值「不能凭记忆、以样片为准」 | 顶回一半 | 宽/高数值取自 (92) 源码 git 原文（见 94-1），非记忆；但 Miller 所指「原来」是否含 (82) 定版面板高 54.9%，须主聊天向 Miller 确认，草案并列两案 |
| B1：pause 无兜底使「工厂没坏」可疑；探针须装最终渲染层 | 采纳 | 落 94-3（按钮最终渲染快照 cov＋pause 兜底） |
| Q3：黄面＝祝福卡＋hitTest 把容器自身交回＋showBless 无防重入 | 采纳为首要嫌疑 | 与代码核对成立：(93) hitTest 在命中子视图帧时 return super.hitTest 结果，命中普通容器（非控件）即吞；落 94-7 白名单制 |
| Q4：原生 scale 取 min(screen.scale, 2)；WebView 查 dpr/canvas/drawingBuffer/contentsScale | 采纳 | 与样片 setPixelRatio(min(dpr,2)) 同口径；落 94-8 |
| A1 单实例不许宣称全路径通；hitTest 不许一刀切关交互（会误杀祝福卡/写灯钮） | 采纳 | 94-7 用白名单而非全局关交互 |

## 二、施工项（每项带自证面包屑＋iOS 适配自查）

### 94-1 控制台几何回滚 (92)＋几何自证
- 回滚值（取自 release-92 源码 ConsolePanel82.viewDidLayoutSubviews 原文）：宽——竖屏 `min(296, bounds.width − 32)`、横屏 `min(bounds.width × 0.86, 640)`；高——竖屏 `min(658, cap)`、横屏 `min(396, cap)`，cap = 屏高 − safeAreaInsets.bottom − 90 − 56（高公式 (92)/(93) 本相同，本项实际只回滚宽公式并留证）。
- 并列待定案：Miller「原来的」若指 (82) 定版面板高 54.9%（≈468pt），则高度另行回滚至 54.9% 屏高——主聊天确认后再定，本项先按 (92) 数值备工。
- 自证：present 时落 `p94 console geo scr=WxH bounds=WxH calc=W frame=W`（屏幕/呈现上下文 bounds/公式值/卡实际帧宽四数同行），下一份日志直接裁 296/370 之争。
- 适配自查：横竖屏两套公式各自成立、旋转后重算并落 geo 行；卡底锚 −90 与播放条/安全区不叠；深色毛玻璃维持；字号不动。

### 94-2 控制台弹出卡顿：分段仪器＋骨架先行
- 先装分段计时面包屑：`p94 pop seg tap=.. present=.. load=.. layout=.. first=.. inter=..`（点按→present 调用→viewDidLoad 毕→首次布局毕→首帧 commit→可交互，逐段 ms）。
- 修法：控制台首帧只出骨架（卡框＋钮排占位），条带封面/队列表/拍立得备池在转场完成后分段装载，每段 <8ms、段内禁全树 layoutIfNeeded；目标重定义：tap→首帧 commit ≤ 转场时长＋50ms，以 seg 行裁。
- 适配自查：入场动画维持系统弹簧＋crossDissolve，不因分段装载出现闪烁/跳变；横竖屏弹出均走同路；装载中点按不吞（allowUserInteraction 维持）。

### 94-3 播放台中央钮按图三路径真修（主页墙 miniPlayButton）
- 病灶定位面：HomeWallViewController.miniPlayButton（38pt 圆钮、DeckGlyph82 工厂图、钮内 blur 层＋A4 渐变层 insert at 0、refreshMiniBar/refreshDeckIcons82 两处 setImage 刷新）。
- 修法：①cov 自证从工厂出口移到按钮最终渲染层——布局完成后对 miniPlayButton.layer 做离屏渲染快照、测字形 alpha 覆盖率，落 `p94 deck render btn=play cov=.. img=nil? sub=n`；prev/next/控制台钮同测。②pause 字形补兜底：cov 过低当场改填充双条重渲（现 fb 只对 play）。③查 blur/渐变层与 imageView 的 z 序与 A4Chrome91 幂等标记在主题刷新后的存活，定位覆盖者后定向修，不许整台重构。
- 适配自查：三宿主（主页墙/歌单墙/舞台）台钮径与字形点数同源同值，光学尺寸与同行图标一致；横竖屏台高 112 同值；点按热区 ≥38pt 现值不缩。

### 94-4 缝排版单一母版（独立施工项，Miller 10:39 口径）
- 母版＝主页缝构成：缝顶圆形头像＋点头像缝中区原地切登录二维码（QQ/酷狗页签可切、无浮层）→ 页签行 → 四入口图标行（我喜欢/云盘/日记本/Navidrome）→ 排版胶囊 → 缝底图标排（搜索/设置/列表/更多/控制台入口）→ 缝底播放区（上一首/暂停白圆钮/下一首）。
- 实现：抽单一 SeamMaster 组件全页共用，页面只供数据（页签选中态/计数），不许再各写一套缝。
- 逐页现状与母版差异清单：
  - 主页缝（HomeSeam85View）：页签行✓、四入口图标行✓（(93) C2）、横排胶囊✓、缝底图标排✓（(93) C1）；缺：缝顶头像✗、二维码切换✗、缝底播放区✗（缝内无播放行，现只有墙面点播台）。
  - 歌单页缝（PlaylistSeam85View）：整套书脊式（竖排标题＋计数＋竖排胶囊＋大播放三角＋展开档），与母版构成全异；且竖排标题帧高固定 0.38H、标题长时标签溢出与计数/胶囊叠印（图二 bug 随书脊式退役消解）；头像/二维码/四入口行/缝底图标排/缝底播放区全缺。处置：整缝换母版组件，播放全部/返回等歌单语义以母版槽位承载（返回=母版折叠位、播放全部=缝底播放区接歌单全量）。
  - 舞台（StageViewController seam.wrap75）：现为宿主包裹层、无缝构成；是否套母版缝待 Miller 定，本项不擅自扩围，先登记。
  - 歌单墙（QueueLattice）：经主页缝进入、无独立缝，母版统一后自动一致。
- 头像数据源沿 (92) 定案（侧栏三家头像行同源缓存＋自愈链），二维码沿网页版登录流取码；码在窄缝的实际可扫尺寸在真机验收时以 Miller 实扫为准。
- 自证：每页缝落 `p94 seam host=.. avatar=0/1 qr=0/1 ver=master`；头像图到位落 `p94 seam avatar img=ok/nil src=..`。
- 适配自查：缝宽在横竖屏两态同值、旋转重排不丢二维码态；头像 32–36pt 圆与缝内其他图标光学尺寸成比例；缝底播放区钮径与点播台中央钮同值（38）；安全区内避让灵动岛侧边；深色玻璃维持、页签文字 ≥11pt 下限。

### 94-5 排版切换黑屏（Q1）
- 修法三步序：①切版式入口即停墙 fling/减速（取消惯性与 display link 驱动、禁 bounce）;②identity/reload/rebase 前后以当前可见锚点 item 重锚 origin 并按新 contentSize 合法域 clamp;③新版式（含模式 0 照片墙本体）visible>0 验证通过后才交叉淡化，源视图 visible=0 时禁止淡化（宁可留旧版式一帧）。
- 面包屑组：`p94 wall sw begin mode=a->b vel=.. fling=..`、`p94 wall sw stop dt=..`、`p94 wall reanchor anchor=.. before=.. after=.. clamped=0/1`、`p94 wall sw show visible=n`；验收线：切换全程 render.audit visible 不得连续 2 次为 0。
- 适配自查：切换动画 0.25s 交叉淡化维持、加弹簧口径的吸附收尾；横竖屏切换同一路径；切换中手势冻结不吞（结束后首个手势须有 tap/pan 落痕）。

### 94-6 横竖屏旋转（Q2）
- 修法：freeze 释放条件改绑 content-ready——原生布局 landed＋WebView resize 完成＋JS 回 `stage.ready`＋连续 2 个稳定帧，四齐才释放；舞台容器/WebView 帧先行设满可用区，contentInsetAdjustmentBehavior=.never、清 zoom/inset 残留；canvas backing store 按 `round(cssW×renderScale)` 重建并重设 setTransform 后重绘；旋转中冻结墙惯性（与 94-5 共用停机口）。
- 面包屑组：`p94 rot begin from=WxH to=WxH`、`p94 rot native landed dt=..`、`p94 rot web resize css=.. buf=.. dpr=..`、`p94 rot ready dt=.. frames=2`；验收线：ready 总时长与图证（横屏舞台满幅、无顶部带压缩、歌词行不出界）双合。
- 适配自查：横竖屏舞台布局集各自独立成立（本项核心）；歌词行几何按新宽重排、左右各留安全边距并落 `p94 rot lyric x=.. w=..` 一行自证；灵动岛横屏侧置避让复核。

### 94-7 特效覆层吞点按＋黄面（Q3）
- 修法：FxOverlayHost91.hitTest 改白名单制——只交回明确可点控件（祝福卡收起钮/写灯钮/推荐卡播放钮本体），命中宿主自身或任何普通容器一律 nil 穿透；祝福卡背景不接 hit、卡外点关闭且穿透；showBless 防重入（展示中再点灯不重弹、落计数）；被动识别器在卡展示期由 delegate 过滤（命中交互控件不触发）。
- 自证：特效开启期每次主窗点按落 `p94 fx tap own=card|host|ctrl|nil hit=类名 bless=n`（沿 (93) p93 tap own 仪器位、补全触发条件——(93) 该行在本日志 0 条的原因之一是特效未开，(94) 须在任一特效开启时即 arm 落一行 `p94 fx arm` 自证在岗）；黄面定性靠 `p94 fx layers` 在特效开启时落浮层层级账（宿主子视图类名/帧/alpha）。
- 适配自查：白名单不误杀祝福卡/写灯钮本职点按（逐钮自证）；特效覆层不换/不压照片墙背景（站立铁律）；点外关控制台、特效留墙的 (93) A1 成果不回退（dismiss reason 行并存对账）。

### 94-8 歌词糊＋圣诞照样片 1:1（Q4）
- 原生侧：ChristmasTreeStageRenderer 四处 fmt.scale 改 `min(UIScreen.main.scale, 2)`；大图精灵分块/缓存并在样式切出时释放，落 `p94 xmas scale=.. tex=MB` 对舞台纹理 ≤250MB 账。
- WebView 侧：统一在 init＋resize 时执行 setPixelRatio(min(dpr,2)) 并校验 canvas buffer 与 CSS 尺寸一致；注入自证 JS 落 `p94 web dpr=.. canvas=WxH client=WxH buf=WxH`；WKWebView layer contentsScale 不许被改 1。
- 圣诞与样片源码差异清单（逐项消）：①渲染技术 WebGL GPU points vs CG 位图 CPU 合成——本包不换引擎（终局全原生口径），以 scale 2＋精灵图集把清晰度拉到样片观感，帧率以 `p94 xmas fps` 真机裁，未达再议 Metal 化；②像素比 2 vs 1——本项修齐；③粒子账样片歌词 3000＋树 3000 分开 vs 原生 7100 混编——按样片分账重编（歌词 3000 独立池、树 3000、雪/星尘余量另账）；④时序 1.0/4.2/0.8 代码值已对齐、真机对账；⑤歌词暗椭圆衬底＋描边光晕：原生已有 backdrop plate 对应实现，逐帧与样片 v2 视频对账（字宽 97%、行位树前偏下）；⑥相机环绕：原生相位投影 vs 样片相机 orbit，观感对账、不合格再议。
- 适配自查：横竖屏画布均按新宽高重建（与 94-6 共用 resize 口）；scale 2 下单帧栅格耗时落 fps 行，P95 帧 ≤16.7ms 口径对账；深色底衬底对比度维持歌词可读下限。

### 94-9 探针可信度基建（DS 总判，全包地基）
- 内存高水位：周期（5s）＋关键事件（控制台开/旋转/切版式/特效开关/切歌）落 `p94 mem hw=MB now=MB ev=..`，峰值以高水位为准、告别采样猜峰值。
- 每类 p94 面包屑须带 arm 自证（功能开启即落一行在岗记录），杜绝「0 条分不开没触发/没在岗」。
- 风自关全量审计：stopWind/stopFx 全部调用点逐个落 src（(93) 已有 p93 fxauto src 口径，(94) 补齐所有 stop 路径并真机验风常开 ≥60s 不自关）。
- 适配自查：面包屑全走既有环形缓冲口径、名 ≤15 字节；探针开销不入主线程关键路径（异步落盘维持）。

## 三、交付与验收通则（Miller 10:43 口径，全项适用）
- 每项施工在交付报告中带「iOS 适配自查」小节，且报告须有一节逐页结论（主页/歌单页/舞台/控制台/缝各页）：横竖屏双向独立成立＋旋转重排、安全区/灵动岛避让、系统手势不冲突、深色与字号下限、iPhone 14 Pro 尺寸范围，逐页给过/不过。
- 图标光学尺寸一致性：同行/同页图标以光学尺寸对齐（字形点数＋线宽同源），不许忽大忽小；新改图标逐个与同行邻居并排量测后落数。
- UI 交互动画：系统弹簧、自然减速、滚动/切换带惯性与吸附，禁线性匀速与突兀跳变；本包涉及的淡化/入场/收起逐项注明曲线来源。
- 凡「已修」表述须分清代码已改/日志已证/真机已验三档，未验不许称过（特效逐条验收制、圣诞样式标记「待真机验」）。
