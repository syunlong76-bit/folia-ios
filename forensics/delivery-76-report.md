# (76) 热修包交付报告 — 2026-11-23

基线 release-75 → 分支 release-76。范围 = Miller 21:43–22:17 对 (75) 的真机否决与点名九项（①–⑨）+ ③验收补条 + 岛格局方案 A 收口，无夹带。交付口径三档严格分开：本报告所述均为「代码已改」；验包结果见文末交付信息；全部条目均未真机验过。

---

## ① 工具条绕岛：凹型缺口带重做（SeamToolbarView.swift）

**旧实现根因（代码实证）**：(75) 的绕岛带是 CAShapeLayer even-odd 遮罩镂空 + 独立描边层（两条分离的闭合子路径），且 `applyToolbarState` 在收起时把毛玻璃视图 alpha 归零——带身消失、只剩一条横线，即录屏里「孤线浮在封面砖上」的来源：带只有命中几何、没有画出来的面。

**新实现**：单一连续轮廓 `bandOutlinePath(width:bottom:)`——顶边 → r8 凹 fillet 下切 → 沿岛胶囊 +3pt 偏移弧绕底 → 镜像上行 → 右缘 → 底角 r22 → 底边 → 闭合。一条路径三层共用：毛玻璃遮罩、带身填充（黑 0.22 tint)、描边。收起态带底收到 slimBandBottom=60，整带收成贴岛薄框、横线落在凹口左侧带身上（与岛同高），不再是孤线。展开/收起走 CASpringAnimation 路径形变（stiffness 210、damping 24)，wrap 态摘除旧版对带遮罩毛玻璃的 transform 缩放。三宿主带高/内容行顶不变（主页 104/54、歌单页 165/115、舞台 191/141)，凹口区无字无钮。加载页零帧口径未动（背板在场整条隐藏，(75) 已落）。

**凹口几何取值表**

| 项 | 取值 | 依据 |
|---|---|---|
| 岛胶囊（14 Pro) | 126×37pt，半宽 63、顶 y=11、底 y=48、中心 y=29.5、圆角 r18.5 | 系统岛真实几何 |
| 凹口半宽 notchHalf | 66 | 侧间隙 = 66−63 = **3pt** |
| 凹口底 notchBottom | 51 | 底间隙 = 51−48 = **3pt** |
| 凹口弧半径 notchArcR | 21.5，圆心 （±44.5, 29.5) | 与岛同心、半径差 = **3pt**（全周均匀间隙） |
| 凹 fillet | r8 | 顶边切入凹口的平滑过渡 |
| 收起带底 slimBandBottom | 60 | 凹口底 51 + 9pt 底衬，横线中心高 29.5 落左臂带身 |
| 带身填充 | 黑 0.22 + 毛玻璃 + 描边，三层同一路径 | 「包住岛」一眼可读 |
| 形变弹簧 | CASpringAnimation stiffness 210 / damping 24 | iOS 系统弹簧口径、禁跳变 |

**横屏口径**：wrap 形态仅在 bounds 宽<高（竖屏）时启用；横屏维持 (74) 安全区侧锚平形态——横屏岛居左缘（x 11..48；852×393 时 y 约 133.5..259.5)，平带与之不交叉。此为本包的范围判断（横屏不做凹口），待 Miller 复核。

## ② 点击闪屏：审计结论（分层，不糊猜）

- **已排除**：三宿主均不监听工具条展开/收起状态，无外部反应链（无「点条 → 全屏重排/窗口层级切换」的代码路径）。
- **头号嫌疑（静态证据链成立，已随①移除）**：旧 `applyToolbarState` 对带遮罩的 UIVisualEffectView 做 transform 缩放（0.92, 0.55）弹簧动画——遮罩毛玻璃的 transform 缩放是已知的合成伪影源，且它正落在「点按 → 展开」路径上。(76) 的路径形变方案已把这段整体移除，wrap 态不再有任何 transform 缩放。
- **不定案（明确）**：(75) 会话日志只覆盖 21:48 的 18 秒 + 22:01 之后，Miller 报的闪屏时段大半不在文件内；覆盖段内 framedrops 健康。故本条**不定案**：整屏范围静态解释不了（带高 ≤191pt），日志覆盖又不足。可疑现象只留档、不下修法：`island.refront` 全文件 451 次且为入场帧耗时首位；`nowplaying.route` root-detached 重试 7 次、两次 giveup。
- **留证**：新增面包屑 `seam.morph76`（tap/exp/col/done + st=/lay w= h=)，下轮日志按点按时刻对位判读：若闪屏与 morph 同帧 → 带形变合成问题；若与 refront 同帧 → 岛层线；两者皆无 → 回录屏帧级对位。

## ③ 灵动岛前台空岛：前后台互斥 + ContentState 镜像（IslandLiveActivityManager.swift / PetIslandLayer.swift)

**定案**（Miller 21:48 截图实证）:iOS 不渲染自家 App 前台时的自家活动；(75) 互斥不分前后台（活动在跑就全程压制应用内岛层），故 Folia 内空岛、退出后别家 App 里系统岛猫狗真实可见。

**改法**：
- 抑制收口 `applySuppression()`：有效值 = 有活动 && 非前台。认领/start、sceneBecameActive、sceneWillResignActive、concertBegan、request、活动状态边沿全部直写点已替换为收口调用；变化才写入并落 `la.fg76 supp= fg=`。SceneDelegate 原有前后台转发未改线。前台 → 应用内岛层落座（系统此时不渲染、无叠影）；后台 → 岛层撤、系统活动接管。汪汪队撤岛口径不破（活动已 end、抑制恒关）。
- **单一真相源（21:54 口径修正）**：活动全程运行，ContentState 是唯一真相源（名单/台词/播放态）。协调器每次构建新 ContentState（request/contentChanged）先 `publishMirror` 同步给岛层：岛层镜像期只演活动的当前句（左右住客轮流开口、句子逐字一致），自有抽词（islandHome 随机）与自有停聊（PetChat）在镜像期停用（落座/点按回台的台词同走 `islandBubbleLine()` 唯一出口）；名单与登记表同源，镜像名单与已座名单不符才重座。活动结束/不可用（无活动）时镜像置 nil，岛层回落自有逻辑。落痕 `isl.mirror76 on=1/0`、`isl.mirror76 say=<asset>`。
- **正在播放干涉**：切歌/播放态变化即 contentChanged 刷新活动并按播放态保 relevance（播放 100 / 暂停 50)；活动转 stale 落 `la.yield76 why=stale`（播放中立即刷新续命）、ended/dismissed 落 `la.yield76 why=…`，让位后重拉成功落 `la.back76`——让位与回来在下轮日志可逐条对位。
- **岛格局方案 A 定版收口（Miller 22:09 拍板）**：双宠物守主岛大格（compact 左右槽双全）、系统正在播放退侧边小圆圈最小形态共存；方案 B（放歌占大格、单宠物退小格）否决（升降由系统仲裁不可控 + 小格只容一只拆双人组），不施工。B 的合理内核并入 A 的展开形态——逐项核对 (75) 已落的展开面（Widgets/FoliaIslandActivity 呈现层）：leading/trailing 双宠物 44pt 放大 ✓、center 区歌名（headline)+歌手（caption)+一句台词（phrase，caption2)✓、bottom 播放态 ✓，ContentState 字段（songTitle/artist/phrase）与展开面一一对应、无缺项，本包无需补改。compact/minimal 维持现口径：minimal 是本活动被系统仲裁降格时的形态（单只左宠），升降不可控属系统行为，与 A 的分工（我方守大格、正在播放退小圆圈）不冲突。

## ③补 trailing 狗缺席专项（Miller 21:57 验收补条）

静态审结论分三层：

- **已证实：应用侧构造不丢 trailing id。** ContentState 唯一构造点 `makeState()`(request 与 contentChanged 同源共用）;`islandTargetDuo` 结构恒 2 元——持久 override 加载要求 count==2、dragSeat/dragRecall 均按侧替换、缺省 `[cat-live, dog-11]`。切歌/播放态/名单/回前台四条更新路径都经同一 makeState，无任何路径能产出空的或缺失的 rightPetId。本包再加硬保证：右位缺失或与左位同只（同只被先后拖到两侧的唯一同值路径）时回落固定搭档另一只——ContentState 绝不带空 id / 同只双占出门。
- **已证实：资产侧两处缺陷（狗「缺席」的主因），已修。** 扩展包宠物图导出时带了不一致的透明边距：实测 alpha 内容填充率 dog-11 = 0.44、cat-live = 0.84（全 53 只中位 0.70、9 只 <0.60)。compact 槽位图框 22pt、scaledToFit——狗的可见本体只剩约 22×0.44 ≈ **9.7pt**，猫约 18.5pt；展开形态 44pt 时狗约 19pt 还能看清——与两张截图的差（21:48 展开有狗、21:57 紧凑无狗）严丝合缝。修法：53 只 widget 图全量按 alpha 包围盒紧裁 + 5% 边距 + 方形画布居中（布局几何不变），dog-11 填充 0.44 → 0.90（22pt 下可见约 19.8pt)，全量最低宽填充 0.69。第二处更硬：**cat-09 的 widget 图是整张全零废图**——它的贴纸是 86 帧 APNG（横漂淡入、第 0 帧全透明是动画设计），(75) 按「首帧」导出导了个空；`UIImage(named:)` 非 nil 使爪印兜底永不触发，cat-09 在活动全部形态里彻底隐形。已自第 38 帧（最完整帧）重生（填充 0.79、alpha 峰值 255)；全量审计确认 cat-09 是 53 只中唯一首帧全空者。
- **日志佐证已到一半（(75) 会话日志判读）**：登记表侧 `isl.boot` 7 次名单均为 cat-live + dog-11 双全、活动全程存活、update 共 17 次、relevance 播放 100/暂停 50 合规——名单与拉起侧日志实证无缺口。唯一缺环正是 (75) 的 `la.upd75` 不带宠物 id（实锤缺口）：更新的每一发到底带没带 dog-11，旧日志永远判不了。本包已补：`la.upd75` 每发落 `pets=<左>,<右>`，(76) 会话日志可逐发判读。
- **未定案：系统边界。** 双活动共存（正在播放占 minimal 小圆圈）时，compact trailing 槽位的实际分配宽度由系统决定、应用不可 widen；本包已把应用侧能保的全部保住（双 id 恒全 + 内容填充拉满 + upd 逐发落痕）。若本包真机上狗仍缺席且 upd 日志双 id 全程在位，剩余解释即系统在 minimal 共存时压 trailing（渲染/系统侧定案）。

## ④ 左缘滑动返回（EdgeBack76.swift，新文件；三页安装）

系统式实现：UIScreenEdgePanGestureRecognizer（只认最左缘 ~20pt 起手带）+ UIPercentDrivenInteractiveTransition 驱动各页**既有** dismiss 转场（动画器恒走系统默认、本类只供交互控制器），过 0.35 进度或 550pt/s 快甩完成、否则取消回弹。关闭契约不绕行：

| 页 | 安装点 | dismiss 落点 |
|---|---|---|
| 歌单页 WallPrototype | viewDidLoad | closeTapped（背板 requestClose 契约 + dismiss，加载态同路） |
| 播放页 Stage | viewDidLoad | closeTapped → closeStage（StageExitGate 闸门登记；veto 时识别器自废交互、落 `edge.back76 veto`) |
| 歌单详情 Collection host | SearchHostPresenter 呈现前 | dismiss 直达（本页无特殊契约） |

落痕 `edge.back76 install/begin/fin/can/veto`。

**冲突清单（逐项核查）**：
- 墙面横向平移（歌单页 collectionView 滚动 pan)：已接线 `panGestureRecognizer.require(toFail: edgePan)`——左缘起手先判返回、非左缘横滑照旧。
- 点播台条带（细条点按/台上宠物拖拽/舞台高度拖拽）：歌单页与播放页均以 shouldBeginAt 排除条带 frame 内起手——点按为离散手势本与 pan 互斥，排除带防的是「从细条左端起手横拖」被返回偷走。
- 岛上宠物拖拽：命中代理是窗口层、触摸不达本页视图；且宠物命中区不在左缘 20pt 带内。无冲突。
- 舞台 tap 链（单击/三击）:离散手势与 pan 不共存于同一触摸序列，无接线改动。
- 歌单详情（SwiftUI):内部滚动 pan 无法自 UIKit 侧 require-to-fail 接线——左缘起手带与横向货架左端存在残余竞争，列为已知边界（竖向列表滚动为纵向主导、不受影响），待真机判读。

未覆盖：主页墙（根页、非常规呈现页）、拼贴墙 Lattice、搜索页——不在本项点名范围。

## ⑤ 歌单页播放条点按仍不弹台：死因锁定派发段（日志判读 + 静态改靶 + 派发段补埋点）

**(75) 会话日志判读（定案输入，诊断存 log-diagnosis-2026-11-23-75session.md)**：22:06:50–51 歌单页连点 4 次——`minibar.touch75` 全登记（到达环活、触摸真达条），`minibar expand` 与 `minibar.dead75` **双零**；全日志唯一一次展开是切歌自动展开、非点出。结论：**死点不在三守卫覆盖段**（守卫全在识别器回调内，回调根本没被触发，守卫无从拒绝）——(75) 的埋点补错了段。

**静态改靶（派发段逐环核）**：
- 识别器装配（台身 5 件：长按/双击/单击/collapsedTap/agnosticTap74）与启停同步在位：`syncMiniBarTapRecognizers` 收起态 bits=001（仅 collapsedTap 启用）、展开态 110，每次形态切换经 `minibar.form` 落 recog= 位（(63) 起既有）。
- collapsedTap 无 require 链、agnosticTap74 恒启用无链——两者任一认领都会落 hit 或 dead75。双零 ⇒ 4 次触摸序列**在识别器认领之前就死了**：或中途被取消（touchesCancelled 使 tap 类识别器静默作废），或被其他识别器饿死。
- 同毫秒嫌疑（日志同刻）：`nowplaying.route`（StageExitGate 舞台呈现路由守卫）以 user-interaction-cancel 收尾——路由 churn（呈现/消散转场与守卫重试）会取消在飞的触摸序列，与「到达活、认领死、连无链兜底都静默」的证据形态完全吻合，列头号嫌疑；宠物层（bar 前层兄弟视图）/seek pan 的竞争列第二（静态无 failure 关系存在，同样需要取消向量才成立）；bits 失同步列第三（日志自身 minibar.form 行可判读当刻位值）。
- 主页（homewall）本日志 **0 次点按样本**——「主页没事」未证实，本报告不作此断言。

**本包处置（只补埋点、不下修法）**：MiniBarHitView 新增派发段见证——touchesCancelled → `onDispatchCancelled`、触摸正常结束且无任一台身识别器认领 → `onDispatchUnclaimed`（认领旗由 7 个台身识别器回调入口统一置位：单击/双击/收起单击/agnostic/长按/seek 点按/seek 拖动）；歌单页接线落 `minibar.dead76 host=wallproto at=cancel|noRecog recog=<当刻三识别器位>`。下轮日志分环：at=cancel = 中途取消实锤（查 route/拖拽偷点）；at=noRecog + recog=001 = 位对而识别饥饿；at=noRecog + recog≠001 = 位失同步实锤。见证视图为三宿主共用类，本包只在歌单页接线（点名宿主），另两宿主回调为空、无行为变化。

## ⑥ 播放页旋转对齐墙面 (73) 管线（StageViewController.swift）

**diff 定案**：墙面 (73) 管线 = 代际计数 + 旋转冻结（wallLayout.setRotationFrozen + PetIslandLayer.setRefrontSuspended)+ alongsideTransition 首帧解冻单次 invalidate + completion 恢复 refront 补拍。舞台此前只有 applySeamBandOrientation 一职：`layoutStage()`（全量几何：渲染器帧/chrome/贴纸/全员 bringSubviewToFront/applyChromeInsets）在 viewDidLayoutSubviews 被旋转中间 bounds 反复全量触发、且无 refront 暂停——这是转动不流畅的结构来源。

**改法（同构对齐）**：stageRotationGeneration / stageRotationFrozen / stageLayoutPending / stageLayoutRuns 四件套；viewWillTransition 重写——freeze 落 `stage.rotate freeze gen=`、alongside 首帧解冻并单次 layoutStage + pushSnapshot、completion 恢复 refront 并落 `stage.rotate76 landed gen= runs=`（目标 runs=1）;冻结期 viewDidLayoutSubviews 只记待办；layoutStage 入口计数。自证沿用 framedrops/rotate 口径（maxGap、重排实例数），目标与主页同级（P95 16.7ms 量级）。汪汪队舞台几何的双向独立推导未动、不应回归（待真机双向各转一次判读）。

## ⑦ 播放页单击不出歌名/返回键：静态审 + 时序门修法（StageViewController.swift）

**静态所见**：(74) 的链（installStageHeaderAutoHideRecognizers → installStyleCycleRecognizers → installWideBar68）在 viewDidLoad 无条件顺序装配，`stageHeaderSingleTap74?.require(toFail: tripleTap)` 接线完整，Stage VC 无手势 delegate、无 isEnabled 拨动；(75) 对 Stage 的 diff 只有工具条朝向组/装配几何、item7 转发分流、item5 minibar 埋点——**未动本链**。故「(75) 改坏本链」静态不成立。另一事实：(74) 会话日志里 tapchain74 面包屑零出现——本链自 (74) 起从未被真机日志覆盖过，「(74) 时是好的」同样无日志证据。**(75) 会话日志已判读：全程未进播放页、单击零样本**——本条定案待下一份含播放页操作的日志，本节只记静态所见与下述修法。

**修法（已落）**：跨视图 require(toFail:) 的实际啮合取决于两识别器对同一触摸集的跟踪、静态不可证——改显式时序门：单击到达即排期 0.35s 后 showStageHeader（落 `stage.tap76 sched/fire`，fire 前查 window 与抑制窗）;三击识别即取消排期并设 0.4s 抑制窗（落 `stage.tap76 cancel`；单击侧落 `stage.tap76 skip=triple`)——双序（同帧回调谁先谁后）下三击序列里歌名都不出现、不闪。延迟 ≈0.35s 与 (74) 口径同量级、不劣化；装配面包屑改 `stage.tap76 gate=timer`;viewWillDisappear 取消待触发排期。返回键随顶栏（showStageHeader 同路）一并唤出。

## ⑧ 摘除歌单页右上角 ✕（WallPrototypeViewController.swift）

摘除对象经代码定位确认：歌单页（WallPrototype）页级关闭钮 closeChrome 整件（34pt 毛玻璃圆 + 44pt 命中容器）——(75) 曾专门把它提到工具条带之上（展开带毛玻璃会盖住它），即 Miller 所指「与工具条控制区干涉」的实物。整件撤除：视觉、空占位、命中区三者全无；连带撤除其按压反馈 closePressBegan/Ended 与 (75) 的提层行。关闭路径完整性：左缘手势（④，与本项同批落地、落点即原 closeTapped 契约，加载态经背板 requestClose 同路可退）+ 背板 onPendingClose + 展开卡点卡外/下滑等既有路径全部保留——不存在无关闭路径的中间态。**入场动画页关闭钮不在此列，未动**（定版口径）。落痕改 `wall.chrome playlist close=removed76`。

## ⑨ miniPets=false 非用户操作：存储审计 + 一次性修复 + 写入打点（定案等级单列）

Miller 22:17 确认：从没动过设置里的宠物开关。(75) 与更早会话日志均实证 appStart 即 false、全程 petsActive=false。审计三靶逐项结论：

- **已证实：不是 key/默认值/迁移问题（靶①③排除）。** 两存储源同源一致：StickerSettings 读键 `folia.stickers.miniPetsEnabled`，**键不存在 → 默认 true**（getter 显式判空）；SettingsStore 读新键 `settings.general.miniPetsEnabled`、缺失时回落 legacy 键（即同一个 folia.stickers 键）并顺手迁值、再缺失默认 true，写时双写两键。各读取源（pet.settings.read 的 src=appStart / src=barPresentation、台层门控）读的都是这一条链——不存在「某处读到另一个默认 false 的键」。
- **已证实：false 是被持久化写入的值。** 键不存在必读 true，而设备上 appStart 即 false ⇒ 该键在某个历史时刻被写过 false 且跨版本持久（覆盖安装不清 UserDefaults）。现行写 false 的路径只有三条：设置页开关（SettingsViewController，Miller 确认从未用）、爪印长按关（paw3s；(75) 日志 paw 事件 0 次、本会话排除）、**长按宠物静止 3.0s 关（petPressCloseTriggered，(60) 起存在）**。
- **未定案（不可再追、如实分级）：具体哪一次历史写入。** (76) 之前全部写入点无 src 打点、当时日志未留存至今，无法实锤。最可能为长按宠物静止 3 秒：其手势阶梯与「长按拖动」共用起手（0.35s 抓起 / 1.0s 可拖 / 移动 >10pt 转拖 / **静止满 3.0s 触发全局关闭**）——想拖宠物却没及时移动，3 秒一到静默关全局且无二次确认，宠物消失后用户无从知道原因。此为基于手势设计的推断、非实锤；与前科同型（旧 companionEnabled 键当年同样被无提示手势静默写 false 关死宠物系统，(29) 才换键）。
- **处置（已落码）**：①一次性修复（AppDelegate 启动、标记键 `folia.miniPets.restore76Done` 防重复）：当前读为关 → 恢复为开（src=repair76)，置于 appStart 读痕之前使启动行即为修复后值；修复只跑一次、之后开关语义完全归用户、再关不自动恢复。②全写入收口：新增 `StickerSettings.setMiniPetsEnabled(_:src:)`，全部 6 个写入点迁移（settings / paw3s / paw2s / petPress3s / dragSeat / repair76)，每次写入落 `pet.switch76 src= v=`——值再变，日志当场留名。③手势关闭路径本身保留（属既定交互口径），但自此有痕可查。

---

## iOS 适配自查

- 横竖屏双向：①横屏走 (74) 侧锚平形态、与横屏岛位不交叉（几何表已列，待真机横屏一眼）；⑥旋转管线对齐后播放页双向重排单次化，汪汪队几何双向独立未动；④左缘带在横屏为左缘（岛侧）——横屏左缘起手与岛宠物代理的竞争已在冲突清单列明（代理在窗口层、命中区不入 20pt 带）。
- 安全区/灵动岛：①凹口按岛真实几何 + 全周 3pt 间隙、带身钉顶；⑧撤钮后顶区无残留占位；④识别器只占左缘带、不遮系统件。
- 系统手势不冲突：④即系统左缘返回语义本身（边缘起手 + 系统转场节奏）；与墙滚动的 require-to-fail 已接线；舞台/细条的排除带已设；iOS 系统级左缘手势（无全局返回）不冲突。
- 深色外观/字号：①带身毛玻璃 + 黑 0.22 tint 在深浅底上均可读（带身为深色口径、与 (74)/(75) 一致）；本包未动字号。
- 目标机型 iPhone 14 Pro：岛几何、凹口常数均按 14 Pro 实测口径；其余机型（无岛）走 (75) 既有平带逻辑、未改。

## 待真机清单（Miller 验收口径）

1. ① 三页工具条：凹口是否「画出来了」（带身包住岛、间隙均匀、收起横线是带的一部分）；展开/收起形变是否顺滑无跳变；横屏一眼。
2. ② 点横线/工具条：还闪不闪（闪 → 导日志按 seam.morph76 对位）。
3. ③ Folia 前台岛里猫狗在不在、说的是活动同一句词；退后台/锁屏系统岛接管同一名单同一句；来回切无双影无长空窗；播放中正在播放退为右侧小圆圈且**主岛猫狗双全**（③补：狗在 trailing 槽位可见）。
4. ④ 四页（歌单页/播放页/歌单详情，含歌单页加载态）左缘返回跟手度、取消回弹、与墙横滑/宠物拖拽的体感冲突。
5. ⑤ 歌单页细条点按（本包只补派发段埋点、未下修法）：点几次后导日志，按 touch75（到达）/ dead76 at=cancel|noRecog（派发段）/ dead75（守卫段）三环交主聊天定案。
6. ⑥ 播放页横竖屏来回转：跟手度（对照主页）、汪汪队形态下双向各一次。
7. ⑦ 播放页单击：歌名 + 返回键约 0.35s 后出现；三击切特效时歌名不闪。
8. ⑧ 歌单页右上无 ✕、顶区干净；左缘能关、加载中能退。
9. ⑨ (76) 首启后宠物应自动回来（一次性修复生效、appStart 日志 miniPets=true 且有 pet.switch76 src=repair76 一行）；此后在设置里关/开宠物应即时生效且不再自己变回去。

## 交付信息

- 分支/提交：release-76 / 515b63d9（已推送）
- CI：（构建完成后补）
- IPA：（验包后补）
- 下载：（上传后补）
