# (92) 交付报告 — Folia iOS 修复包

- 分支/提交：release-92 / fcc8e1c8（自 release-91 拉出）
- CI：build-ipa.yml run 45869292479 success（首个 run 45866993559 排队被平台取消、非代码失败；详见文末验包节）
- 依据：forensics/audit-92-questions.md（十条审计）、audit-avatar-login.md、avatar-fields-reconcile.md、delivery-91-report.md
- Miller 加码（2026-11-27 01:13）：特效联动与「点了卡住」为本包两条必决项，其余次之——本报告前两节即此两条，篇幅优先。

---

## 一、点按卡住：宿主改挂真主窗 ＋ 全窗清查 ＋ 点按到达探针

### 根因（分已证实/未证实两层）

- **已证实（审计 Q4）**：`GlobalFx87.install` 在 SceneDelegate 建窗前被调用（SceneDelegate 第 19 行调 install、第 105 行才建主窗）。install 内以 `scene.windows.first(isKeyWindow)?? scene.windows.first` 取「主窗」，此时 scene 里只有刚建好的 Fx 窗自身——于是 FxOverlayHost91（祝福卡/写灯钮/推荐卡的宿主）与被动点按识别器双双挂到了 level 1500 的 Fx 窗上。后果：①点灯旁路（handlePassiveTap）挂在 Fx 窗、主窗点按根本不经过它，永不触发；②祝福卡等浮层件活在 Fx 窗内，与主窗点按的相对层级全错位。
- **未证实（审计 Q10）**：「任一特效开着时全屏点按被吞、控制台不消失」在 (91) 代码里找不到能整屏拦截的结构（Fx 根视图已关交互、宿主 hitTest 只认卡/钮帧）。本包不假装定案：除修掉已证实的挂错窗外，再做全窗清查（下表）并装点按到达探针，把下一次判读的证据先备好。

### 修法

1. **宿主与识别器改挂真主窗**：`GlobalFx87.install` 取主窗时排除 Fx 窗自身（`scene.windows.first(where: { $0!== win})`）；新增 `attachOverlay92(to:)`，由 SceneDelegate 在 `window.makeKeyAndVisible()` 之后调用：同一 FxOverlayHost91 实例迁挂真主窗（卡片随迁不重建）、被动点按识别器随迁。自证面包屑：`p92 fxhost win=UIWindow level=0`（类名与 level 逐字落盘，真机日志可直接对账宿主落点）。
2. **全窗清查**（枚举全部 UIWindow 与顶层浮层，逐个核 interaction/hitTest 纪律）：
- 窗口共 **2 扇**：主窗（level 0）与 Fx 窗（level 1500）。Fx 窗根视图 `isUserInteractionEnabled=false`，整窗穿透 ✓。
- **FxOverlayHost91**：(91) 挂错窗（见上）→ (92) 迁真主窗；hitTest 仅当点落在可见子视图（祝福卡/写灯钮/推荐卡）帧内才命中，其余整屏穿透 ✓（纪律不变、落点纠正）。
- **NativePlaybackFailureToast 药丸**：❌ 查到一处无谓拦截——药丸以默认交互态直挂窗口，3.2 秒存续期内白吞其帧内点按（顶部中央小条，非整屏）。已改 `isUserInteractionEnabled=false` 纯显示穿透。
- **PetIslandLayer＋PetHitProxyView**：只认宠物本体/气泡矩形，其余穿透 ✓。
- **PetDockLayer**：只认停靠宠物子视图，其余穿透 ✓。
- **MiniBarPetStage**：只认宠物/对话框/关心气泡子视图，其余穿透 ✓。
- **WorkbenchOverlayHostView（侧栏）**：关闭态只认领极小把手区；展开态为模态语义（面板外落 scrim 点按关闭），属设计行为 ✓。
- **HomeSeam85View / PlaylistSeam85View / SeamToolbarView**：只认控件本体，其余穿透给墙面 ✓。
- **SketchbookDrawerView（日记本抽屉）**：关闭只认边缘热区，打开只认抽屉帧，被盖住时整层不接命中 ✓。
- **MiniBarQuickRowView**：只认其胶囊帧（收起态不命中）✓。
- **ConsolePanel82**：present 出的 VC，根视图压暗层点卡外关闭为设计语义；其呈现层在主窗之上、与已迁回主窗的 Fx 浮层不再同层竞争 ✓。
- **PassthroughWebView**：网页舞台本体（呈现面自身）✓。
- **LoadingBackdropView / WallBackdrop62 / SeamBackdrop86 / 舞台幕布类**：皆为内容之下的装饰背板，不在交互内容之上拦截 ✓。
- **观察类识别器**（route 的 TouchDownObserverRecognizer、本包点按探针、Fx 被动点按）：一律 `cancelsTouchesInView=false`，只观察不消费 ✓。
- 结论：除 toast 药丸一处（已修）外，未查到第二个整屏拦截者；「特效开着点死」若真机仍复现，凭探针面包屑即可判定点按是否到达主窗（见下）。
3. **点按到达探针（运行时自证）**：主窗装被动识别器（不取消他人触摸、可并行），仅在任一特效开启期间启用（四特效全关时 `isEnabled=false`、零落痕）；每次点按落一条节流面包屑 `p92 tap ok zone=<九宫格>`（每秒至多 2 条防刷屏；区域为粗粒度九宫格 l/c/r × t/m/b，如 `zone=cm`）。下次日志判读法：特效开着点控制台/墙面后，日志有 `p92 tap ok` ＝点按已到达主窗，问题在下游控件；无 ＝点按在窗口层被吞，继续向上查。

### 自证面包屑样本

- `p92 fxhost win=UIWindow level=0`（冷启建窗后一条）
- `p92 tap ok zone=lt` / `p92 tap ok zone=cm`（特效开启期间点按，节流每秒 ≤2 条）
- `p91 lamp hit`（点灯旁路触发，既有 (91) 面包屑——本包起应在真机日志中首次可达）

### 真机验证点

1. 冷启日志应有 `p92 fxhost win=UIWindow level=0`；若仍出现 Fx 窗类名/level 1500 即挂错未除。
2. 开任一特效（烟花最易），点墙面/点播台/控制台外区：控制台应消失、点按有反应；同时日志出现 `p92 tap ok zone=..`。
3. 开孔明灯，点一盏灯：应出祝福卡且日志有 `p91 lamp hit`（(91) 从未达成的旁路）。
4. 点烟花期间点任意处补放一发（被动识别器既有行为）应恢复。

---

## 二、特效联动：补覆盖（演唱会/岛/舞台封面）＋ 触发自证

### 根因（审计 Q3 定案）

(91) 联动注册表只覆盖主页墙砖、A/B 砖与迷你台宠物；**舞台/播放页零覆盖**——演唱会宠物（PetConcertRenderer 演员）、灵动岛宠物（IslandPetView）、舞台在播封面从未注册。在播放页/舞台测联动必然看不到，不是联动失效、是没接。

### 修法

1. **FxLinkage91 新增覆层宠物通道** `registerPetOverlay(_:surface:)`：给宿主自有 transform 状态机的宠物（演唱会演员的位置/跑位、岛宠物的落座/闲晃都由宿主状态机独占 transform）只走不碰本体的通道：
- 雪：雪堆子视图附着头顶（与普通宠物共用 growSnowPet；抖落周期只抖雪堆＋飞雪粒，**不摇本体**——普通宠物的本体摇晃分支对覆层宠物跳过）；
- 孔明灯：暖光覆层（填满本体、alpha 随灯距逐趟算）＋**仰头贴纸层**（头顶星贴纸显隐表达仰头，不转本体）；
- 烟花：闪光覆层一拍（花色冲亮淡出），不跳本体；
- 风：覆层宠物不走本体轻晃（transform 冲突，无替代形态）——四特效中唯一例外，见下方清单注。
2. **注册点**：PetConcertRenderer 构建演员时逐只注册（surface=concert）、unmount/重建两处拆台逐只注销；PetIslandLayer.seatPet 落座注册（surface=island）、releasePet 离场注销；StageViewController.buildStageBar 把舞台点播台封面 stageCover82 注册为砖（surface=stage，container=点播台本体）。
3. **在场判据适配**：岛宠物视图不进窗口视图树（靠 layer 嫁接在窗口层上渲染），`window` 恒 nil——覆层宠物的联动更新改判 `layer.superlayer!= nil`，普通宠物仍判 window。
4. **原有覆盖零回归**：墙砖（surface=wall）、A/B 砖（surface=alt）、迷你台宠物（surface=minibar）的注册与全部既有联动行为（风掀/雪檐/仰头/跳跃）未动代码路径，仅加表面标签与自证落点。
5. **触发自证（加码 2）**：`proof92(fx:surface:)`——每种特效在每个表面**首次真触发**时落一条 `p92 link <fx> on <surface>`，同（特效，表面）每会话只落一次防刷屏。触发点均为真实生效点：风＝首砖起掀/首宠起晃、雪＝首砖长檐/首宠长堆、灯＝首砖暖光 alpha>0.02/首宠仰头或覆层亮起、烟花＝首砖被爆点点亮/首宠跳跃或闪光。

### 自证面包屑样本

- `p92 link wind on wall`、`p92 link snow on alt`、`p92 link ln on stage`、`p92 link fw on concert`、`p92 link snow on island` 等（每组合每会话至多一条）。

### 真机验证清单（逐项可对账：动作 → 应看到 → 日志应有）

| # | 动作 | 应看到 | 日志 |
|---|---|---|---|
| 1 | 主页墙开风 | 封面砖轻掀摇摆、迷你台宠物轻晃 | `p92 link wind on wall`、`p92 link wind on minibar` |
| 2 | 主页墙开雪 | 砖顶长雪檐、宠物头顶积雪并周期抖落 | `p92 link snow on wall`、`p92 link snow on minibar` |
| 3 | 主页墙开孔明灯 | 近灯封面暖光提亮、宠物仰头 | `p92 link ln on wall`、`p92 link ln on minibar` |
| 4 | 主页墙开烟花 | 爆点附近封面按花色亮一拍、宠物跳跃欢呼 | `p92 link fw on wall`、`p92 link fw on minibar` |
| 5 | 歌单页 A/B 开风/雪/灯/烟花 | 同 1–4（表面换 alt） | `p92 link <fx> on alt` ×4 |
| 6 | 舞台页开烟花 | 点播台封面随爆点亮一拍 | `p92 link fw on stage` |
| 7 | 舞台页开雪/灯/风 | 点播台封面长雪檐/暖光/轻掀 | `p92 link snow/ln/wind on stage` |
| 8 | 汪汪队开大会样式下开雪 | 演唱会宠物头顶落雪（雪堆附着、本体跑位不受扰） | `p92 link snow on concert` |
| 9 | 演唱会开孔明灯 | 宠物身覆暖光、头顶出星贴纸（仰头代偿） | `p92 link ln on concert` |
| 10 | 演唱会开烟花 | 宠物闪光一拍（不跳、不扰队形） | `p92 link fw on concert` |
| 11 | 岛上有宠物时开雪 | 岛宠物头顶落雪 | `p92 link snow on island` |
| 12 | 岛上有宠物时开灯/烟花 | 岛宠物覆暖光＋星贴纸/闪光一拍 | `p92 link ln on island`、`p92 link fw on island` |
| 注 | 演唱会/岛宠物开风 | 无本体轻晃（设计例外：transform 归宿主状态机） | 无对应行（预期） |

---

## 三、入场下雪默认关（任务 2／审计 Q2）

- 根因：(88) 把工坊存值「下雪 开」写成冷启默认——`applyDefaultSnow88` 每次冷启无条件 startSnow，雪 12 秒自融只是表象，「取消下雪」从未存在。
- 修法：`applyDefaultSnow88` 改为「确保冷启无雪」（方法名保留、SceneDelegate 调用点不动）；四特效冷启默认全关，雪样式值（淡蓝 FxTuning88.snowTint）保留，手动开仍走 startSnow、12 秒自融保留。
- 自证：冷启日志 `p92 snow=default-off`，且不应再出现紧随其后的 `fx87 sn=1`（除非手动开）。
- 真机验证：冷启进墙无雪；控制台手动开雪正常、12 秒自融、再点即关。

## 四、图标补齐（任务 4／审计 Q1）

- 根因：(91) A4 只落了核心字形与部分钮面——MiniBarQuickRowView 整行无 A4 钮面、paw/heart/star/command 仍是 SF 符号；控制台主题/去处/播放器三格仍是 SF89（paintpalette/square.grid.2x2/play.circle）。
- 修法（位置/尺寸/功能零改）：
- DeckGlyph82 新增 A4 手绘 `stateGlyph92`：paw（主垫＋四趾填充）、heart/heartFill（同路径描边/填充）、star/starFill（五角星同路径）、command（四角环＋织线＋中央方）；image() 路由改走手绘，SF 同名符号退役。
- 新增 `utilityGlyph92`：主题＝调色板圆盘＋三色点、去处＝2×2 圆角格、播放器＝圆盘＋实心播三角；控制台三格改走 `configureIconButton(glyph:)`。
- MiniBarQuickRowView 五钮在 buildButtons 末尾统一 `A4Chrome91.apply(cornerRadius: 10)`（与按下态背景圆角对齐）；字形侧 paw/heart/star/command 随工厂自动换 A4、panel 格沿用.sliders。
- 自证：`p92 quickrow chrome=A4`（快速行装配时一条）。
- 真机验证：点播台展开快速行五钮为玻璃钮面＋细线字形；控制台功能行主题/去处/播放器三格为新手绘字形，与其余格同语言。

## 五、宠物召唤钮装回（任务 5／审计 Q5）

- 根因：(89) 提交 669b75b89 把 pawButton 撤出 functionRow（对象/配置/动作俱在、从未入视图），非 (91) 所为；且旧 pawTapped 直写 StickerSettings，跳过共享切换核的收口链（开关双写带 src、告别离场/掉落入场、广播兜底、岛民对账）。
- 修法：pawButton 正式入 functionRow（队列格之后，行变 7 格等分）；pawTapped 改走 `PetSummonButton70.performPawToggle77(window:src:via:actCrumb:)`（src/via=console3s/console2s、actCrumb=paw.act92），召唤成功的卡内烟花点缀保留原 (85) 口径。
- 自证：`p92 paw src=console on=1/0`，及切换核既有 `pet.switch on/off via=console..`、`paw.act92 on=.. stage=..`。
- 真机验证：控制台点爪印——宠物召唤入场/告别离场与台面爪印、窗口爪印行为一致；钮面选中态回刷正常。

## 六、爱心接宠物反应（任务 6／审计 Q8）

- 根因（审计定案）：爱心通路从未接宠物反应——PawFirework81 只挂爪印钮，三处 heartTapped91（墙封面/杂志行/唱片架格）只有心形脉冲＋LikesStore 同步，无任何宠物反馈。
- 修法（选与现行架构最贴的一条：FxLinkage91 注册宠物群＋PawFirework81）：三处 heartTapped91 在**点亮（newState=true）且云端 setLike 成功后**（MainActor）触发——① `FxLinkage91.petHeartReaction92()`：变换宠物跳一拍（与烟花跳同弹簧、同风让位规则）、覆层宠物粉色闪光一拍；② 格子未被复用给别曲时，在爱心处 `PawFirework81.burst` 一发。**取消喜欢不触发；云端失败 catch 回滚时不触发**（反应与回滚互斥，纪律在三处一致）。
- 自证：成功 `p92 heart react=1`；失败回滚 `p92 heart react=0`。
- 真机验证：点封面爱心点亮→台上宠物跳/闪＋爱心处小烟花；取消喜欢→无反应；断网点爱心（回滚）→无反应且爱心恢复未选。

## 七、A/B 点播去全量重刷（任务 7／审计 Q9）

- 根因（定案）：A/B 模式下 `startQueueAt → refreshVisiblePlaybackUI → reloadAltPlaylist91`，一次点播 ≥2 次全量 reloadData＋2 次重建黑底歌单头，空帧露黑即「点封面闪黑」。
- 修法：新增 `refreshAltPlaybackState92` 定点刷新——只对新旧在播行/格 `reloadRows/reloadItems`（基线 altCurrentId92 随每次全量重刷同步），歌单头仅在标题/计数签名变化时重建；refreshVisiblePlaybackUI 在 A/B 下改走定点路。结构变化（种子落地/分页拼接/版式切换）仍走 reloadAltPlaylist91 全量路；现行版式路径零改动。
- 自证：A/B 点播后日志 `p92 alt refresh=targeted n=<定点行数>`，且同段不应出现由点播引发的全量重刷痕迹。
- 真机验证：A/B 两版式逐首点播切换，画面无黑闪、无歌单头重建闪烁，在播标识（杂志强调条/架格角标＋描边）正确迁移到新曲。

## 八、烟花性能（任务 8／审计 Q6）

- 根因（定案三源）：①FxEngine 与 FxLinkage91 两条 CADisplayLink 无帧率上限，120Hz 机型全屏 CPU 软件光栅；②逐粒拖尾 stroke＋火箭逐帧 setShadow(blur:16) 离屏＋halo/灯体每帧新建 CGGradient；③FxLinkage91 第二链常驻、每爆点全表遍历。
- 修法：①两链均设 `preferredFrameRateRange(max 60)`（帧步进本按 dt*60 归一，时序不变）；②渐变改签名缓存复用（fxGradient92：stops 量化签名、容量 96——halo/灯体/雪花全部调用点同享）；火箭辉光改预渲染径向精灵（fxRocketGlow92）绘制、删逐帧 setShadow；③联动爆点 50ms 合并（pendingBurst92 只保留最后一发、到点一趟全表）、孔明灯暖光全表遍历改每 3 拍一趟（≈20Hz）。参数（大小×0.85/密度×1.1/辉光×1.7/金/星粒上限 1400）一字未动。
- 自证：结构旁证（IPA 内 preferredFrameRateRange/fxGradientCache92/fxRocketGlow92 符号，见验包节）；真机以帧感为准。
- 真机验证：开烟花全程（15.5s 脚本）＋连点补放，画面应无可感卡顿/掉帧段；花型、颜色、密度与 (91) 一致。

## 九、旋转卡帧减负（任务 9／审计 Q7）

- 根因（定案）：旋转长帧（日志 dt 295–442ms）三源——beginWebRotCover81 全屏全分辨率 WebView 快照、layoutStage completion 二次全量补排、nudgeEffectResize81 每记 JS resize 重建画布；其中补排判据里的安全区比较是假阳性源（alongside 记录的 insets 转场中未稳）。
- 修法：①快照改 `WKSnapshotConfiguration.snapshotWidth`（max(200, 宽×0.5) 降采样），盖层拉伸显示语义与揭盖时序不动；②completion 补排判据去掉 safeAreaInsets 比较、只认 bounds.size；③nudgeEffectResize81 加 0.12s 防抖合并（连发只派最后一记，揭盖 0.9s 超时兜底不受影响）。
- 自证：`p92 rot snapw=<采样宽>`、`p92 rot extra=0/1`（每次旋转 landed）、`p92 resize dispatch`（每次实际派发，旋转一轮应只 1 条）。
- 真机验证：舞台页（含网页特效样式）横竖互转，冻结→揭盖顺滑、无长卡；旋转后画面与 (91) 一致（特效不错位、盖层揭开时机不变）。

## 十、头像推荐修法（任务 10）

- 根因（两审计定案）：侧栏账号头点按无条件开登录中心并自动出码（无账号页落点）；侧栏头像只读缓存零自愈、只显第一家；QQ 头像病根在落盘/自愈链（解析与网页版逐字一致、不许动）；酷狗原生漏网页版 coverOf 的候选键组且无 URL 后处理（解析到也加载不出）；VIP 三家原生全无字段；(90) 的 enrich 自愈埋在设置页账户卡、日常路径没接上。
- 修法：
1. **侧栏三家头像行**：provider 三行各加一枚 28pt 头像（真头像/昵称首字占位/未登录灰位＋状态点）＋平台名＋VIP 皇冠位，数据走 NativeSessionStore＋ProviderSessionStatusQuery；**侧栏接 enrich 自愈**（与 AccountCard62 同源三路、每家每会话至少一次，缺头像/昵称/VIP 任一即补），不再纯读缓存。
2. **落点改账号页**：点头像/头像行 → AccountCard62 账号页（popover 锚点按处，新增 initialProvider92 预选该家）；已登录家显头像＋昵称＋VIP 皇冠，未登录家在账号页内点头像才进该家扫码（(90) 定版流，卡内既有）；侧栏不再直开登录中心，**全未登录时才直开**（保首次登录短路）。
3. **酷狗 coverOf 整体移植**：9 键候选序（sizable_cover→Image→image→img→pic→picUrl→cover→coverUrl→sizable_avatar）＋avatar 兜底＋URL 后处理（{size}→1024、裸文件名拼 c1.kgimg.com/stdmusic/1024/<前8位>/、//→https:、http→https）；QQ 解析一字未动，仅加命中键面包屑。
4. **VIP 三家接入**：NativeSessionStore 加 vipLevel 合并缓存、ProviderSessionStatus 透传；网易云 fetchLoginStatus 顺手多读 profile.vipType；QQ 新增独立端点 GET /user/vip（vipLevel 字符串映射 free 0/green 1/super 2、unknown 不填）；酷狗资料内 vip_type|vipType|is_vip 初值＋/user/vip/detail 复核（认 busi_vip[]）；写入点在两侧 enrich（侧栏＋账户卡）；呈现＝侧栏行与账户卡详情行昵称旁金色皇冠，vipLevel>0 才显、0/未知不显（网页版同口径）。
- 自证：`p92 qq avatar key=<profile.avatarUrl|info.logo|info.avatarUrl|none>`、`p92 kg avatar key=<命中键> form=<https|http|tpl|bare|proto-rel|other|none>`、`p92 sidebar enrich provider=<家>`、`p92 account page open`。
- 真机验证：①侧栏三行各显自家头像（酷狗重点看：此前恒占位）；②点任一行落账号页且预选该家、已登录家有昵称（VIP 家有皇冠）；③点未登录家头像才出该家扫码；④日志里 qq/kg 两条 avatar 面包屑能定案命中键与形态。

## 十一、A/B 切换入口移主页缝（任务 11）

- 根因/背景：Miller 原话「页面展示ab应该做到主页中间的缝播放台，设计好图标」——(91) 的切换段控在歌单页顶部，与定版口径不符。
- 修法：HomeSeam85View 在原账户空区（直达双列与工具格之间的空带，port88 头像摘除后留空）新增版式开关：玻璃胶囊＋三枚 A4 手绘字形（layoutWall92 不规则拼贴四格／layoutMag92 方图＋文行／layoutShelf92 大方盘＋唱芯＋基线，三态轮廓互不混同），选中态走缝页签同语言（白 pill＋深字形）；窄档横胶囊 58 宽、宽档整行宽，帧位按可用带高自适应；写同一持久化键 foliaPlaylistLayout91（宿主 HomeWall 落键＋`p92 plist mode=<n> src=seam`）。歌单页撤顶部段控（installPlaylistLayout91 删段控装配、layoutSwitch 成员与态回刷退役），viewWillAppear 重读键对齐（`p92 plist mode=<n> src=appear`）；歌单页内 A/B 视图、版式行为与持久化语义不变。
- 真机验证：主页缝内点三态——进歌单页即为所选版式；歌单页顶部不再有段控；横竖屏缝内开关位置正常（横屏见自查注）。

## 十二、iOS 适配自查

- **横竖屏双向**：点按探针/宿主迁挂与朝向无关；联动覆层件随宠物本体 bounds 自适应（autoresizing）；缝开关宽/窄两档各有帧位公式，横屏内容高被压扁、带高 <40 时开关隐藏（与缝内既有元素在横屏的压缩退化同级——横屏缝页签区本身即超高压缩，属既有现状、本包不扩大也不假装修好；版式在横屏经宽档缝或竖屏切换后照常生效，歌单页重读对齐）。舞台封面砖为约束布局、联动覆层按 cover.frame 逐趟对齐，旋转后不错位。
- **安全区/灵动岛**：本包未新增贴边元素；缝开关居缝内空带、不入安全区敏感带；岛宠物覆层件挂在宠物本体上，随岛几何走。
- **系统手势**：新增识别器（探针/Fx 被动点按）一律 cancelsTouchesInView=false 且可并行，不与边缘返回/下拉关闭冲突；缝开关为普通 UIButton。
- **深色外观**：新增字形为模板图随 tint、钮面/胶囊为白色半透玻璃系，与既有深底口径一致；皇冠为金色原图渲染（两外观下可读）。
- **字号下限**：新增可见文字仅面包屑（不可见）与无障碍标签；缝开关为纯字形钮（14pt 字形、36pt 钮高），窄档单钮宽约 17pt 小于 44pt 命中建议——已知取舍：缝宽 64 物理所限、三态横排的代价是单钮窄，误触后果仅为版式切换（可逆、无损），宽档（120）下单钮约 31pt；此点如实记录，待 Miller 手指实测裁决。

## 十三、验包（2026-11-27 凌晨完成，包备好待 11-28 交付）

- **CI**：run 45869292479 **success**（head fcc8e1c8）。注：首个 run 45866993559 排队约 16 分钟后被平台取消（job cancelled、零步骤执行、无日志 blob），非代码失败；重新 dispatch 后新 run 立即被 runner 接走并一次通过。
- **IPA**：`~/workspace/folia-deploy/build92/Folia-unsigned.ipa`，**49,083,443 字节**（(91) 为 49,054,141，增量与本包代码量相符）。
- **版本号**：Info.plist `CFBundleVersion = 92` ✓（Short 3.7 不变）。
- **入场母带**：包内 `entry-v5-faststart.mp4` md5 = **8aed0fb4a5e9a0f500184f8a7dae45a9** ✓ 与定版母带一致。
- **结构旁证**（二进制符号/字面量实查）：
  - 新符号全部命中：attachOverlay92、tapProbe92、proof92、registerPetOverlay、petHeartReaction92、refreshAltPlaybackState92、fxGradientCache92、fxRocketGlow92、stateGlyph92、utilityGlyph92、themePalette92、coverOf92、enrichProfile92、presentAccount92、initialProvider92（×3）、saveVIP、vipLevel（×3）、fetchVIPLevel、performPawToggle77、A4Chrome91、WKSnapshotConfiguration（×2）。
  - ObjC 选择子实查：`setPreferredFrameRateRange:` ✓（双链 60 上限）、`setSnapshotWidth:` ✓（快照降采样）。
  - 面包屑字面量命中：`p92 tap ok zone=`、`p92 snow=default-off`、`p92 alt refresh=targeted n=`、`p92 heart react=0/1`、`p92 paw src=console on=`、`p92 qq avatar key=`、`p92 kg avatar key=`（含 `=none form=none` 全字面量）、`p92 sidebar enrich provider=`、`p92 account page open`、`p92 quickrow chrome=A4`、`p92 resize dispatch`。
  - 4 条字面量未在字符串表出现（`p92 fxhost win=`、`p92 rot snapw=`、`p92 plist mode=`、`p92 link …`）：均为 ≤15 字节的插值前段，Swift 小字符串内联进机器码立即数、不入字符串表——与 (91) 验包时的同类现象一致；其发射函数符号（attachOverlay92/proof92）已命中，不作缺失论。
- **交付节奏**：Miller 2026-11-27 01:39 定「92 的整改内容先优化，明天给我包」——本包已备好，2026-11-28 由主聊天走文叔叔交付；圣诞歌词特效未进本包（先出样片口径，未留口未夹带）。
