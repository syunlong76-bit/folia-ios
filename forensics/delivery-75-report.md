# (75) 交付报告 — 真 Live Activity 灵动岛宠物＋六项追加

- 分支 release-75（基线 release-74），7 个独立提交（见文末清单）。
- CI：GitHub Actions run 45178031232，一次通过。
- IPA：`~/workspace/folia-deploy/Folia-3.7-75-unsigned.ipa`，48,655,588 字节。
- 下载链接：https://muse.ai/files/1467544983097845/1159291256477001/zozc1tdn9fwhmiph5oym4ijk/Folia-3.7-75-unsigned.ipa（到期 2026-11-25 20:57 CST）
- 口径声明：本报告全部条目为「代码已改＋我验包过」；真机行为一律未验，清单在文末。

## 第 1 项：真 Live Activity 灵动岛宠物

### DS 对抗评审（施工前置，已走完）
简报 `forensics/ds-review-2026-11-23-r75-brief.md`（含第二轮补充材料：(74) 岛落法现状、PetIslandLayer 结构、固定双人组与汪汪队撤岛口径、miniPets=false 全部写入点清单、签名与 CI 出包方式）。第一轮回复空答（推理占满 16000 token），第二轮以 deepseek-v4-pro＋32000 token 全量重发取回。对账定案存 `forensics/ds-review-2026-11-23-r75-reconcile.md`，施工按对账走。要点：
- **删除 App Group（偏离原任务书，明示）**：任务书要求「App Group 共享容器供图片」，DS 判为致命点并采纳删除——v1 渲染不依赖共享容器，个人团队/SideStore 重签时自选 group id 大概率注册失败（装不上/活动拉不起）；53 只图打进扩展包即够。动态图需求出现时再以团队前缀 id 引入。
- **甲案（致命）**：LA 拉起与 miniPetsEnabled、introDone 完全解耦；拉起条件＝areActivitiesEnabled && currentTrack≠nil && 非演唱会 && (scene 已激活 || 正在播放)；任何被挡落 `la.gate reason=`（disabled/noTrack/concert/background），不许静默。此条直接针对 (74) 实锤的「陈旧 off 态静默压死新功能」——miniPets=false 全部写入点已清单化（见第 6 项），LA 不读该开关。
- 互斥归单一协调器 IslandLiveActivityManager 独占抑制状态、监听 activityStateUpdates 清抑制；PetIslandLayer 不自查 Activity.activities。
- staleDate 分态：播放中 now+8h、暂停 now+15min；切歌/播放态/换词同源合并一次 update；phrase 只作 best-effort 不单独发 update；request 只在前台发；演唱会 resume 加 1s 防抖。
- ContentState 不设 petsHidden，演唱会只走 end 活动路径；扩展 Info.plist 在 project.yml 显式配置并验包；锁屏呈现独立成版。
- 顶回 DS 两点：演唱会 end+request 限频不构成阻塞（低频显式行为＋防抖）；设置页 LA 说明 v1 不做。

### 实现
- `Widgets/FoliaIslandActivity.swift`（共享属性，双 target 同编）：ContentState = leftPetId/rightPetId/songTitle/artist/isPlaying/phrase。
- `Widgets/FoliaWidgets.swift`：@main WidgetBundle＋ActivityConfiguration。紧凑 leading=左宠物、trailing=右宠物（首帧静态图 scaledToFit 22pt 小框，整只可见）、minimal=左宠物；展开 leading/trailing 44pt＋center 歌名/歌手/一句词（PetLines.islandHome 口径）＋bottom 播放态；锁屏横幅独立成版（双宠物 40pt＋歌名/歌手/词＋播放态）。
- `Sources/Native/Features/Stickers/IslandLiveActivityManager.swift`（app 侧单例协调器）：Combine 订阅 PlaybackEngine 的 currentTrack（按 id 去重）/isPlaying；登记表 onIslandLineupChanged 同源更新；SceneDelegate 三钩子（willConnect 装配 start()、sceneDidBecomeActive 对账＋按闸拉起、sceneWillResignActive 清 sceneActive）；PetConcertRelocation begin/end 各一行 end/resume 调用。
- 生命周期状态机：无活动 ──闸全过──▶ request ──▶ .active（抑制开）──切歌/播放态/名单──▶ update（stale 按播放态刷新、relevance 播放 100/暂停 50）──▶ .ended/.dismissed（系统收走：8h 上限/抢占/用户关）──▶ 清抑制回落障眼法＋按闸重拉；汪汪队 begin ──▶ end(.immediate)，end ──▶ 1s 防抖 evaluate。进程重启/回前台发现系统侧已有活动 → adopt/readopt 并接抑制，防双开叠影。
- 互斥自证：活动在跑 → `PetIslandLayer.setLiveActivitySuppressed(true)`（宠物隐藏、proxy 停用、框底撤下、tick 封口，落 `isl.perch75 supp=1`）；活动结束 → supp=0 本层按名单自愈。用户在系统设置关了实时活动 → request 恒被闸挡（`la.gate reason=disabled`），抑制恒关，障眼法为唯一呈现——自动回落成立。
- project.yml：新增 FoliaWidgets app-extension target（bundle id com.miller.folia.widgets，NSExtensionPointIdentifier=com.apple.widgetkit-extension），app target embed 依赖；app Info.plist 加 NSSupportsLiveActivities=true；CFBundleVersion 两侧升 "75"（(73)/(74) 都停在 73 的已知疣，本版升号助日志归因）。

### 验包证据（我验包过）
- Payload/Folia.app/PlugIns/FoliaWidgets.appex 存在，含可执行文件 FoliaWidgets（186,824 字节）与 Assets.car（1,209,247 字节）。
- 扩展 Assets.car 内 53 只宠物 imageset 名全命中（cat-01…25、cat-live、dog-01…27，缺失 0）；源图逐只抽 APNG 首帧、最大边 240px，53 只共约 1.5MB。
- App Info.plist：CFBundleVersion=75、NSSupportsLiveActivities=true。扩展 Info.plist：CFBundleIdentifier=com.miller.folia.widgets、CFBundleVersion=75、NSExtensionPointIdentifier=com.apple.widgetkit-extension。
- 未签名包无 entitlements 文件属预期（签名在 SideStore 安装时完成）；LA 呈现依赖 Info.plist 键（已验在位），不依赖 entitlement。

### 两条路的区别（Miller 20:31 问，写清）
- 障眼法（应用内 perch）：应用自己的窗口图层画在岛框两侧真像素带，系统层（状态栏字形、系统「正在播放」展开形态）在其之上——时间/信号遮不住（系统画在最上层），但系统活动展开时会把宠物压到只剩边（层级差，无解，不修）。本版只做了视觉挤占优化（第 3 项③）。
- 真 LA：呈现由系统排版，紧凑/展开/最小/锁屏槽位与时间、信号共存是苹果设计内行为，不存在互相遮挡；代价是平台规则（8 小时上限、他方活动抢占让位、系统设置总开关）。

## 第 2 项：主页左滑误弹命令面板（已交付口径，提交 b17e9bd0）
根因实锤（(74) 日志）：WB62HomeWallHooks 在 gestureShortcutsEnabled（默认 true）时给整面 HomeWall 装 UISwipeGestureRecognizer(.left)，handleSwipeLeft 按 swipeLeftTarget（默认 commandPalette）present 命令面板、其 viewDidAppear 又自动聚焦搜索框拉键盘。修法：整段摘除识别器＋handleSwipeLeft＋独占的 findDrawer；设置页「向左滑动打开」分段行同步摘除防假生效；自证面包屑 `swipe75.off host=homewall`。命令面板合法入口不变：工具条「…」/命令键、长按工具条、S 键。

## 第 3 项：工具条绕岛＋加载页零帧＋障眼法挤占优化（提交 63eea42e）
- ①加载页零帧：歌单加载页的工具条装在拍立得背板之上（(74) 注释明言「加载态亦可见可点」）即 Miller 截图的白线来源。改：LoadingBackdropView 加 onFadedOut 回调（dismiss 全路径汇入 fadeOutNow 的 completion 触发）；WallPrototype 装配时背板在场则整条隐藏（`seam.wrap75 loading bar=hidden`），淡出完成恢复（`seam.wrap75 loading=done bar=back`）。
- ②绕岛形态（竖屏）：三宿主（主页/歌单页/详情页）工具条改钉屏幕顶边全宽的高带——带顶沿按岛几何（半宽 63、顶 11、底 48，与 PetIslandLayer 同源）切凹口（凹口半宽 71、底 56、底角 r18），CAShapeLayer even-odd mask 镂空＋独立描边层；内容行落凹口下方，各页行顶与 (74) 绝对位置同位（主页 54/歌单页 115/详情页 141），带高 104/165/191。收起横线落岛左近与岛同高：线身右缘距岛左缘 14pt、命中垫再外扩 20pt。**新锚位坐标口径**：条体 top=屏幕顶边 0；横线 centerY=29.5（岛中心高）、leading=屏宽/2−63−50。横屏各宿主回 (74) 安全区侧锚组（岛在侧边、贴安全区左缘即避岛），install/viewWillTransition/viewDidAppear 三点同步朝向。命中纪律新规：SeamToolbarView 重写 hitTest——收起态只认横线垫、展开态空域穿透，高带绝不整带吞页面点按；主页 ✕ 与详情页舞台头控件在带下照常可点（✕ 容器提至带上层）。
- ③障眼法挤占优化（PetIslandLayer）：黑框底改两段短底（只罩本侧宠物、外缘出框 6pt、内缘向岛缘 tuck 6pt），不再横跨全宽（旧跨度 ±114 → 单段约 47pt）；槽位收紧（缝 3→1pt、slotOffset 85→81）、个头 38→34；气泡仍挂宠物下沿（y≈52，状态栏带之下，未动）。

## 第 4 项：任意宠物拖进灵动岛换住（提交 bf83785a）
- 登记表：新增持久化 override（UserDefaults `folia.island.residents75`，[左,右]），`islandTargetDuo = override ?? islandFixedDuo`；setHome 双人组闸、reconcile 遍历、岛层 seatPet 闸、reseatAll 站位、框底左右判定、告别分流 divert 全部改认 target duo——固定双人组门自此只辖自动路径。
- `dragSeat(asset:side:)`：名单按侧替换并持久化、被换下在岛者回池（departure 撤演员）、拖入者 arrival 落座；拖拽即开启——顺带双写 miniPetsEnabled=true＋`isl.drag75 pets=on`；汪汪队期间拒收（`isl.drag75 … deny=concert`）。落座/换住面包屑 `isl.drag75 seat=<asset> side=<0/1> out=<displaced>`。
- 拖入接线：MiniBarPetStage.dropActor 在算出 windowPoint 后加岛区判定（竖屏、y≤100、x 在屏中 ±120）：命中先 removeActor 回池再 dragSeat（顺序防 sendToPool 冲掉 .island），拒收落 `host=island-denied`。
- 拖出召回：PetHitProxyView 加 pan 转发 → PetIslandLayer.proxyDragBegan/Changed/Ended：宠物跟手、松手中心 y>130 判召回——名单该侧回落缺省（dragRecall，全同缺省则撤 override）、本体走既有回台路（有台 receiveReturningPet、无台回池）；未出区弹簧弹回（`isl.drag75 back`）。tick 闲晃与 reseatAll 跳过拖拽中的那只防抢位。
- LA 同步：名单变更经 onIslandLineupChanged 通知 manager 更新 ContentState 左右 id（第 1 项同源合并 update）。
- 与自动落座链的关系：reconcile 只按当前名单裁决落座，拖拽改名单后自动链随之维护新名单；缺省（从未拖过）行为与 (74) 完全一致。

## 第 5 项：爪印钮让位＋细条点按日志定案（提交 3d94569e）
- ①爪印钮改规（Miller 20:39 更正口径）：钮位置恒定不动（窗口右下、底 −10、36pt，原样）；三宿主点播台底锚 −10→−54，台身下缘恒在钮带（顶 −46）之上 8pt——展开/细条两态都不盖钮（上下邻居），细条态钮在细条下方原地。长按 2s/3s 语义不变。
- ②细条点按（日志定案，不再静态猜修）：本轮日志实锤——歌单页链路是通的（minibar.hit via=agnostic74 → expand ×3），主页全程零 minibar.hit、(74) 日志同。静态全查主页命中链（识别器装配 ✓、几何守卫 h=16 ✓、宠物层/抽屉/dock/filter 条/沉浸层逐个排除吞点）未找到单一静态凶手，故本版按定案要求把链路分环埋点，下轮日志一次判清：
  - 到达环：MiniBarHitView.onHitLanded → `minibar.touch75 host=<三宿主> col= h=`（触摸真落到台身才有；无此行＝点按没进门、上层吞点）。
  - 死点环：三个既有静默守卫全部改落痕 `minibar.dead75 host= at=geom/flag/arb`（agnostic 几何守卫、collapsedTap 标志守卫、expandMiniBar 单宿主仲裁守卫）——(74) 修法为何未生效的定案解释：(74) 的 agnosticTap74 只解决了「标志与识别器启停失同步」一层，其上游（触摸是否到达台身）与下游（仲裁/几何守卫的静默 return）全是无痕黑箱，主页的病若在任一黑箱内都不可见；且 agnostic 在 wallproto 被验证过即被默认全宿主同效，实际三宿主的 bar 是三套独立实现。本版三宿主同构埋点后，主页的病落在哪一环下轮日志直接可读。

## 第 6 项：爪印召唤不出宠物（提交 3d94569e，与第 5 项同批）
- 定案（日志实锤）：缺的是台面宠物不是岛上宠物——`pet.settings.read src=barPresentation miniPets=false` 整轮、heartbeat cast=0，台面宠物被持久化 false 关死；岛侧因 (73) 删了 reconcile 提前返回能自愈，台侧 barPresentation 读到 false 即整层关死、无后门。爪印按压本身整轮零面包屑（touchesBegan 无留痕、短按无语义无痕迹）。
- miniPets=false 全部写入点（与第 1 项联动清单）：①设置页 companion 开关（唯一真·用户设置决定）；②爪印钮开态长按 3s 告别（手势关闭语义）；③长按宠物本体静止 3s（MiniBarPetStage.petPressCloseTriggered，手势关闭语义）。无任何代码路径「反复自动写关」——持久化 false 是历史关闭动作的留存态，病在台侧读到 false 后无就地开启路＋召唤钮不可达/无反馈。
- 修法：①召唤全链埋点——`paw.touch75 dn en=`（到达）/`paw.touch75 up trig=`（抬手对位短按与已触发）/`paw.touch75 cancel`、`paw.act75 on= stage=`（触发时当前面层定位结果）；②召唤 nil 兜底：currentFacePetStage() 找不到层时改走广播 `.foliaPawSummon75`，各 MiniBarPetStage 自查在场＋开关已开＋非迁移中自行 performDropInEntrance（`paw.act75 recv=stage`），不再静默；③召唤写 on 在入场之前（原序保留）＋performDropInEntrance 内 skip 原因本有留痕（pet.dropin skip reason=），全链自此无静默环。按下视觉反馈本已有（渐亮＋放大，touchesBegan 驱动）——本版 dn 面包屑可证触摸是否到达：下轮若 Miller 短按，日志会出现 dn＋up trig=0，即可判「短按无语义」而非「按不到」。

## 第 7 项：设置等全局面本页就地展开（提交 3c078f6a）
- 根因：三宿主工具条全部动作统一走 SeamToolbarForwarding.forward（先 dismiss 本页回主页再执行），设置在歌单页被 `seam.forward action=settings from=WallPrototype` 弹回主页才开（日志 20:41:58 实锤）。
- 改：转发器新增全局面集合 {settings, avatar, search, guide} 与 performInPlace（呈现参数与主页同款：设置=SettingsViewController overFullScreen；账户卡=popover 锚本面工具条头像位、扫码登录在卡内自有弹层；搜索/导播台=各自呈现器从本面发出）。歌单页四回调改就地、详情页 stageSeamForward74 对全局面分流就地（不关台、不经 StageExitGate）、歌单详情 SwiftUI 桥四动作改 activateGlobal。就地自证 `seam.inplace75 action= host=`。
- 仍许转发（主页墙状态动作）：segment-*/lattice/layout/fullscreen/more，关页回主页执行的语义不变。关掉就地面后回到本面原位（呈现栈压在本面之上、dismiss 即回）。

## iOS 适配自查（本包）
- 横竖屏双向：工具条双向约束组三宿主同构（竖屏绕岛带/横屏侧锚）、旋转转场首帧切换＋viewDidAppear 兜底；点播台让位底锚与朝向无关恒成立；LA 四形态由系统排版、横竖屏系统自理；障眼法横屏隐藏口径未动。
- 安全区/灵动岛避让：绕岛凹口几何与岛实测值同源（半宽 63/顶 11/底 48）；爪印带与点播台新底锚都以 safeArea 为锚。
- 系统手势不冲突：摘除的左滑识别器即冲突源；岛上 pan 只在 proxy 命中宠物本体时起手、点按识别器对真实拖动自落空；工具条 hitTest 穿透不新增全屏手势。
- 深色外观与字号下限：绕岛带沿用 systemUltraThinMaterialDark 毛玻璃与既有描边口径；LA 文案字号走系统 Dynamic Island 规范字阶（headline/caption），无自设小字。
- 目标机型（iPhone 14 Pro）：岛几何、凹口、槽位均按该机型实测口径；其余机型岛几何不同（无岛机型绕岛带凹口会悬空）——已知限制，无岛机型不在当前验收范围。

## 待真机验收清单（全部未验）
1. 第 1 项 LA：首次拉起的授权弹窗；紧凑（左猫右狗整只）/展开（放大＋歌名＋词）/最小/锁屏横幅四形态；切歌/暂停更新跟随；系统设置关实时活动后自动回落障眼法、无双开叠影；汪汪队期间活动撤下、切走恢复。
2. 第 1 项追加三条（Miller 20:35）：①播放中紧凑形态是我们的宠物活动、不被系统「正在播放」长期挤掉（relevance 播放 100/暂停 50＋切歌/播放态 update 保活已落代码，效果待验）；②他方活动在场时整齐让位（最小形态/暂退）、不出现半遮丑态；③他方活动结束后宠物活动能回来。8 小时上限与抢占属平台行为，只记不验。
3. 第 2 项：主页左滑只平移；工具条「…」/命令键/长按工具条开命令面板不回归（日志对位 swipe75.off 与 wall.menu.panel present）。
4. 第 3 项：加载页全程零白线/零工具条；三页竖屏工具条绕岛（岛被条包住、横线在岛左近与岛同高）、展开/收起衔接；横屏侧锚不压岛；障眼法框底变短段、宠物贴近岛缘、时间/信号视觉挤占减轻。
5. 第 4 项：台上宠物长按拖到岛框松手换住（左右侧对位、原住客换下、冷启动按名单恢复）；岛上住客下拖出区召回回台；汪汪队期间拖拽不落座；isl.drag75 系列面包屑对位。
6. 第 5 项：爪印钮三页三态（展开/收起/细条）恒可见可点、位置不动；主页细条点按——若仍不开，导出日志按 minibar.touch75/dead75 分环对位（没进门/进门死守卫/仲裁）。
7. 第 6 项：爪印长按 2 秒召唤（先做一次刻意长按实测）——paw.touch75 dn → paw.act75 on=1 → 台面宠物掉落入场；短按应有渐亮反馈且日志 dn＋up trig=0。
8. 第 7 项：歌单页/详情页/歌单详情页点设置、头像（账户卡＋扫码登录）、搜索、导播台都在本页开、关掉回到本页原位；切段/布局/沉浸/Lattice 仍回主页执行。

## 提交清单（release-75）
- b17e9bd0 第 2 项（左滑摘除）
- 63eea42e 第 3 项（绕岛/零帧/挤占优化；同批含 DS 评审档与扩展素材首两图，为装配顺带纳入）
- 3d94569e 第 5＋6 项（让位/命中链埋点/召唤全链）
- 3c078f6a 第 7 项（全局面就地展开）
- bf83785a 第 4 项（拖拽换住）
- fb60f6e5 第 1 项（Live Activity 全套＋53 图）
