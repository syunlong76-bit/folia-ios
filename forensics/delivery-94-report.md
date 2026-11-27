# (94) 交付报告

- 施工依据：forensics/plan-94-draft.md（(93) 真机日志判读＋release-93 代码审计＋DS 对抗评审对账），加 Miller 2026-11-27 三条拍板修正：①94-1 控制台高回 (82) 定版 54.9%（10:56 点选）；②94-8 分辨率动态读设备原生 scale、不写死不封顶（10:55，作废 DS 的 min(scale,2)）；③94-7 覆层点按覆盖四特效全部＋任一特效开启时退出路径恒可用（10:56/10:58，他在 (93) 真机被特效困住、杀 App 才退出）。
- 分支/提交：release-94，代码提交 7d54d040＋CI 修复 ec45e723（缝二维码 Task 闭包类型推断，见未决项）。
- CI：首跑 45932633231 failure（单个 Swift 类型推断错误）→ 修复后 45932921491 **success**。
- IPA：Folia-unsigned.ipa **49,186,021 字节**，存 ~/workspace/folia-deploy/build94/。
- 包内核验：CFBundleVersion=**94** ✓；入场母带 entry-v5-faststart.mp4 md5=**8aed0fb4a5e9a0f500184f8a7dae45a9** ✓；结构旁证齐（SeamMaster、ChristmasTreeStageRenderer、probeDeckRender94、openLikedFromSeam94、noteHW/hwMaxMB、p94Web、p94RotMaybeRelease、startQRFlow/runQRFlow 及 p94 console geo / pop seg / deck render / wall sw / rot ready / fx sw / seam / xmas 面包屑字面量均在二进制中；个别短字面量如 `p94 mem hw=`、`p94 web dpr=` 因 Swift 小字符串内联 grep 为 0，其符号元数据在位，非缺失）；包内 WebEffect 束含 /api/netease、/api/qq、/api/kugou 三项与 songPreviewPlaying 键 ✓。
- **文叔叔上传未由本施工线执行**：IPA 已备好在 build94/，请主聊天上传后交付 Miller（约 24h 销毁、传完立刻发并提醒马上取）。
- 表述纪律：以下每项分「代码已改／日志已证／真机已验」三档；本线无真机，凡未经 Miller 真机日志对账的一律只写到「代码已改＋自证面包屑已备」，不称已解决。

## 94-1 控制台几何回滚＋几何自证（代码已改）

- 宽回滚 (92) 源码公式：竖屏 `min(296, bounds.width − 32)`、横屏 `min(bounds.width × 0.86, 640)`；(93) 的 `min(620, bounds.width−20)` 退役。
- 高按 Miller 点选回 (82) 定版：竖屏 `(bounds.height × 0.549).rounded()` 直取、不套 cap；**横屏取值口径（本线定，报告在此注明）**：`min((bounds.height × 0.549).rounded(), cap89)`，cap89 沿现行口径＝屏高 − safeAreaInsets.bottom − 90（卡底锚）− 56（顶距），防横屏矮高时卡顶冲出可用区。(89)B 的内容生长高（竖 658/横 396）退役，内容超高走卡内纵向滚动。
- 几何自证：`p94 console geo scr=WxH bounds=WxH calc=WxH frame=WxH` 四数同行（布局变化去重落盘、viewDidAppear 补一行定值），下一份日志可直接裁卡宽/卡高实测值。
- (93) A1 的 dismiss 全链与 reason 面包屑、在播路由穿透零改动。

## 94-2 控制台弹出卡顿：分段仪器＋骨架先行（代码已改）

- 分段计时：`p94 pop seg tap=0 present=.. load=.. layout=.. first=.. inter=..`（相对点按的累计 ms 一行；first 取 CADisplayLink 首回调）。目标口径已按 DS 对账重定义并写入代码注释：tap→首帧 commit ≤ 转场时长＋50ms，达标与否以真机 seg 行裁，本线未实测不宣称。
- 骨架先行：viewDidLoad 只建卡框＋毛玻璃＋钮排占位骨架（占位层不接点按）；重内容（条带封面/队列表/拍立得备池）转场完成后分段装载——条带 6 张/片异步分片、队列表 reload 独立成段、拍立得备池段 B 启动；装载期间保持 allowUserInteraction。
- 诚实注记：段 A（buildFullContent94 建全树）仍是单段执行、未再细切，其实际耗时靠真机 seg 行的 inter−layout 差值判读；若超标需再拆段。骨架期点卡外关闭链正常，但已排队的装载段会在已消失的面板上跑完段 A（weak self 只防释放）——无可见副作用，登记备查。

## 94-3 播放台中央钮按图三路径真修（代码已改；覆盖者为代码层定案、真机终裁靠 ivtop 位）

- 覆盖者定位（差分证据链）：构建时 z 序本对（渐变＜blur＜imageView）；miniPlayButton 是台面四钮中唯一同时带「钉满钮面的 blur 层＋A4 渐变层」且走两处 setImage 刷新的钮——refreshMiniBar/refreshDeckIcons82 只换图、从不重申 imageView 与插入层的 z 序，A4Chrome91 的幂等标记又使 chrome 永不重挂，blur 层最终盖住字形。对照组：控制台同工厂字形可见（其 blur 不走此刷新链）。
- 修法：①cov 自证从工厂出口移到按钮最终渲染层——布局稳定后对钮 layer 离屏快照测中心 60% 区字形覆盖率，四钮各落 `p94 deck render btn=play/prev/next/console cov=<‰> img=.. sub=.. ivtop=0/1 fb=0/1`（ivtop 在自修复之前取值，记录探针进场时 imageView 是否已在最上层，供真机终裁）；②play 与 pause 的 cov<0.5% 兜底都补齐（原 fb 只管 play），当场以填充字形（三角/双条）替换；③两处 setImage 刷新后各加 rehangGlyph 把 imageView 提回最上，A4Chrome91.apply 的幂等早退分支也先 rehang 再返回。台尺寸未动（台高 112、钮径 38 维持 (93) 值）。
- 波及面：Deck82 工厂 pause 兜底与 A4Chrome91.rehang 对三宿主（主页墙/歌单墙/舞台/控制台）同源生效，均为纯增益（只改钮内 z 序与缺字兜底，不改尺寸/布局/图源）；cov 探针只装主页墙一条路径。

## 94-4 缝排版单一母版（代码已改；宿主接线由集成阶段补齐）

- 实现：Seam85Views.swift 内新增单一 `SeamMaster` 组件（构成/布局/状态只有一份），HomeSeam85View/PlaylistSeam85View 类名与全部既有对外接口保留、只做数据适配与语义转发。母版构成自上而下：缝顶圆形头像 34pt → 头部语义行 → 页签行 → 四入口图标行 → 横排三段排版胶囊（两页同一组件、读同一持久化键 foliaPlaylistLayout91）→ 缝底图标排 → 缝底播放区（上一首/中央白圆钮 38pt/下一首，走 QueueManager/PlaybackEngine 全局单例）。
- 主页缝补齐三件：缝顶头像（数据源沿 (92) 定案：ProviderSessionStatusQuery 侧栏同源资料缓存＋WorkbenchCover.loadAvatar 加载链＋三家自愈复刻）；点头像缝中区原地切登录二维码（与主区共用同一矩形、无浮层/遮罩，QQ/酷狗页签可切，取码/轮询/落存逐项同构 LoginViewController 网页版登录流，未新造端点；展开态存共享静态、旋转/重建不丢）；缝底播放区。
- 歌单页缝：整套书脊式（竖排标题＋计数＋竖排胶囊＋大播放三角）退役换母版；语义映射——返回→头部行左钮、折叠→头部行右钮、播放全部→缝底播放区中央钮、计数→页签行附注、歌单名→页签行横排标题（单行尾截断）、加入队列→缝底图标排 list 槽、展开/收起→expandCorners 槽。竖排标题溢出叠印（图二）随书脊退役消解。
- 宿主接线（集成阶段在 WallPrototypeViewController.installPlaylistSeam85 补齐，草案原列「只列未改」）：onLiked（登录态→specialType=5 喜欢歌单→全屏开墙，未登录/未找到/失败均 toast＋落 `p94 seam liked miss`）、onCloud、onDiary93、onNavidrome（空态页）、onSearch94（SearchHostPresenter）、onSettings94，逐项与主页缝同款落点。
- 自证：每页缝构建落 `p94 seam host=home/wall avatar=1 qr=1 ver=master`；头像到位落 `p94 seam avatar img=ok/nil src=..`；二维码开/关/登录成功另有 p94 seam qr 行。原 port88 seam=avatarless 两行已从 Seam85Views 删净；SeamToolbarView 的 port88 bar=avatarless 属另一组件、不在本项文件范围，未动。
- 舞台 wrap75 是否套母版缝按草案登记未扩围，待 Miller 定。
- 已知取舍：64pt 窄缝下二维码码图约 52pt，实际可扫性以 Miller 真机实扫为准（样片阶段已声明的口径）。

## 94-5 排版切换黑屏三步序（代码已改）

- switchPlaylistLayout93 重构为三步序：①入口停机——新增全仓共用静态停机口 p94StopScrollMomentum（同值 setContentOffset 取消减速＋bounce 回弹），停墙本体＋杂志表＋唱片架三滚动面、取消 locateLink/seamTween85 两条 CADisplayLink、暂关 bounce；②重锚——以视口中心命中的实例为锚点，reload 后把 worldOrigin 移到「锚点中心＝视口中心」并按实例覆盖矩形 clamp 合法域；③验可见——新版式 visible>0 才 0.25s 交叉淡化（.allowUserInteraction 维持、无拦截层），验证不过延一帧重试、仍为 0 整单回滚旧版式（状态/UserDefaults/胶囊态全回滚）。
- 自证：`p94 wall sw begin mode=a->b vel=.. fling=0/1`、`p94 wall sw stop dt=..`、`p94 wall reanchor anchor=.. before=x,y after=x,y clamped=0/1`、`p94 wall sw show visible=n`（回滚另落 `p94 wall sw abort`）。验收线已写入代码注释：切换全程 render.audit 的 visible 不得连续 2 次为 0——是否达线以真机日志裁。

## 94-6 横竖屏旋转 content-ready（代码已改；一处兜底口径在此明示）

- freeze 释放改绑四齐门：原生布局 landed＋WebView resize 完成＋JS 回 stage.ready＋连续 2 个稳定帧，四齐才解冻。现行固定口径（armWebRotReveal81 的 0.9s 超时揭盖）已废除；日志里的约 330ms 本是实测时长、非计时常量。stage.ready 现行无通道，本包新建：桥注入脚本（documentStart）以 rAF 数稳定帧回 stageResizeDone/stageReady，门在岗时既有 styleFrame 首帧回执同作 ready 证据。
- 旋转配套：舞台容器/WebView 帧先行设满可用区；contentInsetAdjustmentBehavior=.never（创建时亦设）；清 zoom scale/inset 残留；canvas backing store 按 round(css×renderScale) 重建并重设 setTransform 后重绘；旋转中经 94-5 共用停机口停内嵌 WebView 滚动面（舞台层级内无墙滚动面，歌单墙 VC 自身旋转的既有冻结代际未跨 VC 改动）。
- 自证：`p94 rot begin from=WxH to=WxH`、`p94 rot native landed dt=..`、`p94 rot web resize css=WxH buf=WxH dpr=..`、`p94 rot ready dt=.. frames=2`、`p94 rot lyric x=.. w=..`（歌词行新几何）。
- **明示口径**：另保留 3 秒防死锁安全网——四齐门若永不齐，3 秒后强制释放并落 `p94 rot ready ... via=tmo94` 自证。它不是释放条件、只防「永远冻住」（与 94-7 退出路径同理：不许再出现只能杀 App 的结构），触发即在日志留痕可裁。若 Miller 要求连此兜底也撤，下一包删。

## 94-7 特效覆层吞点按＋退出路径恒可用（代码已改；Miller 10:58 硬要求单列）

- 覆层核查结论：fw/ln/sn/wd 四特效全部由单例 GlobalFx87 驱动，渲染在独立 Fx 窗（level 1500）的纯显示根视图上（整窗不接点按）；可交互件（祝福卡/写灯钮/推荐卡）全仓只有一个宿主 FxOverlayHost91（挂真主窗）。四特效没有各自的覆层。联动覆层 FxLinkage91 只加不可交互的雪檐/暖光/雪堆视图、不构成第二宿主，未改。
- 白名单 hitTest：FxOverlayHost91.hitTest 改为——super.hitTest 命中后，命中视图本身或其祖先链（含止于宿主）含 UIControl 才交回；命中宿主自身、卡背景、标签、封面图等普通容器一律 return nil 穿透。现网交回全集：祝福卡收起钮、写灯钮、推荐卡播放钮（及同为 UIControl 的「下次吧」钮）。
- **退出路径验收线（本项硬要求，逐条落码）**：任一特效开启状态下——①控制台可打开（覆层无整屏拦截点）；②控制台内四个特效钮再点即关且当帧清场（ln/sn hard 清场、fw 清粒子、wd 清 streaks/leaves），开关经 toggle→setX 单点变更、按钮态与引擎态同源同帧；③点外关台通路不被覆层截走，(93) A1 的 dismiss 链＋reason 面包屑未动。结构上不存在「困住用户只能杀 App」的路径。
- 关特效同行自证：全部状态变更统一经 setFw/setLantern/setSnow/setWind(_:src:)，每次落 `p94 fx sw fx=fw/ln/sn/wd on=0/1 src=.. state=..`（来源与变更后引擎态同行）。src 清单：控制台钮=consolebtn、互斥连带关=mutex、烟花时间轴自终=auto、雪 12 秒自融=auto（样片既定行为保留）、冷启默认关雪=auto、点亮孔明灯开 ln=link。另落 `p94 fx arm fx=<开启集>`（任一特效开启边沿）、`p94 fx layers`（arm 时浮层层级账）、`p94 fx tap own=.. hit=<类名> bless=0/1`（特效开启期主窗点按归属，与既有探针同节流）。
- 祝福卡：showBless 防重入（展示中不重弹、不重置计时，落 `p94 fx bless dup n=`）；卡背景经白名单天然不接 hit；卡外点关卡落 `p94 fx bless outclose` 且点按本身穿透；被动识别器加 shouldReceive 过滤，卡展示期命中交互控件不收。
- 风停全量审计（94-9 分项）：全仓 setX 调用点 20 处逐个显式传 src、无无来源关特效路径残留；stepWind 内确无任何 stop 调用（(93) 删的 5 秒硬编码未回潮）；FxLinkage91 的 stopWindTile/stopWindPet 只是联动 transform 复位、不改引擎态。下一份日志可直接验「风开 ≥60s 无 `p94 fx sw fx=wd on=0` 行」。

## 94-8 歌词糊＋圣诞照样片 1:1（代码已改；帧率未实测不宣称）

- 原生侧（ChristmasTreeStageRenderer）：四处 fmt.scale=1 全改渲染时动态读 UIScreen.main.scale——不写死、不封顶（按 Miller 铁令，未采 DS 的 min(scale,2)）；烘焙记录 bakedScale，draw 首帧比对、漂移整表重烘；采样步长随 scale 等比缩放（scale=3 时 step 6），归一化坐标与 scale=1 逐点等价。
- 与样片差异逐项消解：①粒子账——原 7100 混编拆三账并落常量/注释：歌词池 3000 独立、树池 3000（金链 340 为树装饰子账）、雪/星尘余量 760（650＋110），总数仍 7100、行为不变；mount 落 `p94 xmas pools lyric=3000 tree=3000 garland=340 snow=760 total=7100`。②时序汇聚 1.0s/停留至 4.2s/碎散 0.8s 已对齐未动（长短行按行长泛化为既有口径）。③歌词暗椭圆衬底、描边光晕、字宽 min(7.4, 可见宽×0.97)、行位（LYRIC_CENTER y=1.45）逐项核对与样片一致、未动。④纹理账已补：mount/重烘落 `p94 xmas scale=.. tex=<MB>MB`、切出释放落 tex=0 行；16 张精灵按 scale=3 估算约 10MB 量级（估算值，真机行裁），对舞台纹理 ≤250MB 口径在线内。⑤fps 自证改 p94 前缀 `p94 xmas fps=.. avgMs=..`。⑥渲染引擎按终局全原生口径不换（CG 位图维持）；已知近似登记：歌词雪→金以精灵二分近似连续混色、树绿明暗离散四档、金链 twinkle 为静态相位——均既有近似、本包范围外。
- WebView 侧：folia-major 7 文件撤 DPR 封顶（machi quality.ts 的 MAX_DEVICE_RATIO=2、diorama DPR_RANGE、hanabi/lumiere 分辨率钳、nebbia min(2,dpr)、fume 两处 clamp(dpr,1,2)），全改 Math.max(1, devicePixelRatio) 动态原生值；原生注入脚本在 init＋resize 实测 DPR 并校验主画布 buf==round(client×dpr)、不一致派发 resize 催重建，WKWebView contentsScale 非屏幕 scale 即复原并落痕；自证 `p94 web dpr=.. canvas=WxH client=WxH buf=WxH kind=init|resize`。WebEffect 束已按铁律重打（FOLIA_SURFACE=player-visual＋三项 VITE base），产物 chunk 含三项字符串、已替换入包并在 IPA 内复验；新入口 chunk visual-d6wKeEZs.js。TS tsc --noEmit 对 7 个改动文件零报错。
- 性能账待真机裁：iPhone 14 Pro DPR=3 后各 WebGL 样式 backing store 像素量约为 DPR 2 时的 2.25 倍，帧率/纹理以真机 p94 web＋各 fps 面包屑对账。范围外留记：TouchGlowLayer 的 min(dpr,2,像素总量) 是内存守卫未动；全量 App 墙 lattice 歌词 runtime 的 min(2,…) 不在 WebEffect 束内、未动；machi 的 MAX_LYRIC_PIXEL_RATIO=3 是 SSAA 超采样顶、非设备 DPR 钳制，保留。

## 94-9 探针可信度基建（代码已改）

- 内存高水位：Breadcrumbs 新增高水位跟踪——每次 log/logSync 采样顺带更新进程内 footprint 历史最大值，高水位每抬升 ≥8MB 直写一行 `p94 mem hw=<MB> now=<MB> ev=<触发事件首词>`（直写日志仓防递归）；3 秒周期采样 tick 同喂高水位（ev=tick）；关键事件（控制台开/旋转/切版式/特效开关/切歌）均经 log 采样覆盖。峰值判读从本包起以高水位为准；本包无真机数据，≤450MB 是否达线待下一份日志的 hw 行裁，本线不估算宣称。
- arm 自证总册：witnessBoot94 启动登记 `p94 wit geo=1 seg=1 deck=1 seam=1 wall=1 rot=1 fx=1 xmas=1 web=1 mem=1`——某见证在真机日志缺席即判「站点没跑」，不再拿 0 条含糊判读。各功能开启另有各自 arm 行（fx arm、seam 构建行、xmas pools 行等）。

## iOS 适配自查（逐页，Miller 10:43 口径；均为代码级结论、未真机验）

- **主页**：缝母版与歌单页同一实现，缝宽由宿主帧给、横竖屏同值，旋转只重排且二维码展开态存共享静态不丢；头像 34pt 与缝内 16px 字形光学成比例；缝底播放区三钮热区 38pt；切版式三步序横竖屏同一路径、淡化 0.25s 维持、切换中手势不冻结吞没。
- **歌单页**：缝整套换母版（书脊退役），构成与主页逐项同构；新接线六个落点与主页缝同款；计数走页签附注、歌单名横排单行，无竖排叠印结构残留。
- **舞台**：旋转四齐门为本页核心——横竖屏布局集各自成立，容器帧先行设满可用区，歌词行新几何落 p94 rot lyric 自证（左右安全边距）；灵动岛横屏侧置避让沿既有口径未动；圣诞样式 scale 动态读取对旋转自动跟随、布局几何与安全区不因像素比变化而变。
- **控制台**：横竖屏两套公式各自成立（宽 (92) 公式、高 54.9% 口径，横屏高加 cap89 防冲顶），旋转后重算并落 geo 行；卡底锚 −90 与播放条/安全区不叠（沿既有）；骨架/分段装载不改入场曲线（crossDissolve＋系统弹簧），装载期点按不吞；深色毛玻璃维持、字号未动。
- **缝（两页共用母版）**：页签文字 12pt、附注/二维码文字 11pt，均 ≥11pt 下限；深色系统毛玻璃（SeamBackdrop86）维持、缝身摆正；安全区/灵动岛避让仍由宿主 contentTop/BottomInset 承担、母版透传未改；横屏矮高时主区纵滚兜底、胶囊/入口不重叠。
- **图标光学尺寸**：本包新涉及图标均走既有字形工厂同源（DeckGlyph82/SeamGlyph93），缝底播放区中央钮 38pt 与点播台中央钮同值、字形点数 19/20 与台面同源；未新增异规格图标。
- **交互动画**：本包涉及的淡化（切版式 0.25s 交叉淡化、骨架 0.2s 淡出）均沿既有系统曲线口径，无线性匀速新引入；滚动停机为切版式/旋转的瞬时结算、无动画跳变新增。

## 真机验证清单（每条对面包屑）

1. 控制台几何：开控制台看卡宽高观感；日志 `p94 console geo` 四数对账（竖屏宽应 ≈296、高 ≈屏高×0.549）。
2. 弹出卡顿：`p94 pop seg` 逐段看 inter 前各段，tap→first 对「转场＋50ms」口径。
3. 中央钮：播/停各看一次字形；日志 `p94 deck render btn=play ... ivtop= fb=`——ivtop=0 即坐实刷新后 z 序曾被压，fb=1 是兜底接住。
4. 缝：主页缝点头像出二维码（QQ/酷狗可切、实扫一张验可扫性）；歌单页缝与主页逐项对样；`p94 seam host=` 两行＋`p94 seam avatar img=`。
5. 切版式：主页/歌单页各切三段胶囊一轮，切换中盯黑屏；日志 `p94 wall sw/reanchor/show`＋render.audit 的 visible 不得连续 2 次为 0。
6. 旋转：舞台横竖各转 3 次，看满幅与歌词行不出界；日志 `p94 rot ready dt=`（出现 via=tmo94 即四齐门有条件未达，需回判）。
7. 特效退出路径：逐个开四特效——开后点控制台外（台关、特效留）、再开控制台点同一特效钮（当帧关、画面清）；日志 `p94 fx sw ... src=consolebtn` 同行对账；任一特效下点歌单封面应能切歌（覆层穿透）。
8. 风常开 ≥60 秒：日志不应出现 `p94 fx sw fx=wd on=0`（src=auto 的更不许）。
9. 圣诞：选「圣诞树」样式，看歌词清晰度对样片 v2；日志 `p94 xmas scale=3.0 tex= fps=`。
10. 内存：四特效轮开＋切版式＋旋转一轮后导出日志，看 `p94 mem hw=` 峰值对 ≤450MB 硬线。

## 未决项

- CI 首跑失败已定案修复：Seam85Views 缝二维码 startQRFlow 的 Task 闭包因 `self?.` 可选链被推断为 Task<()?, Never>、与 PollingCoordinator.attach 期望的 Task<Void, Never> 不符，ec45e723 改 guard-let 显式 Void 后 success。属本线静态核查漏网（无本地 Swift 编译面），已认。
- 文叔叔上传待主聊天浏览器执行（见文首）。
- 94-6 的 3 秒防死锁安全网为本线明示保留口径（见 94-6 节），是否连兜底也撤待 Miller 定。
- folia-major 工作树有此前遗留的未提交改动，本线只改其中 7 个 DPR 相关文件并据其工作树重打束；folia-major 本仓提交未在本线处理（与 (93) 口径同）。
- 圣诞帧率、弹出 seg 各段、旋转 ready 时长、内存高水位、四特效退出路径均为「已落自证面包屑、待真机日志对账」，未实测不宣称达标。
- 歌单缝窄档（64pt）二维码约 52pt 的可扫性、控制台 54.9% 高下各行观感，待 Miller 真机拍板。
