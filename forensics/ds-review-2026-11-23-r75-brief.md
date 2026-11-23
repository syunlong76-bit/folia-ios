# DS 对抗评审简报：Folia iOS (75) 真 Live Activity 灵动岛宠物

你是对抗评审员。任务：攻击下面这个实现计划，找漏洞、质疑假设、给出更强的替代方案，每条发现给出依据。不要写代码，不要假设你能访问仓库——简报里的事实即全部事实。

## 背景与已定案事实（不许推翻，只能在此基础上评审）

- Folia 是 iOS 17+ 音乐播放器（Swift/UIKit，XcodeGen 生成工程，GitHub Actions macos-15 云构建出**未签名** IPA，用户用 SideStore/个人开发者证书在安装时重签侧载）。目标机 iPhone 14 Pro（有灵动岛），iOS 18.2。
- 产品负责人已拍板做「真 Live Activity 灵动岛宠物」，并已知情两个平台折扣：单次活动 8 小时上限、来电/Face ID/他方活动抢占时让位。
- 现状（(74) 已交付）：应用内障眼法——PetIslandLayer 把宠物层（CALayer）graft 到 window.layer（zPosition=10000），宠物落在灵动岛框左右两侧的真像素带（左槽中心 x≈111.5、右槽对称，宠物 38pt，脚底与岛框底 y=48 对齐），身后垫同高同圆角黑框底，把剪影接成一整条岛框。实查定案：岛框本体（x 133.5–259.5, y 11–48）没有任何应用可绘像素（硬件切口+系统渲染），所以障眼法只能贴两侧。
- 岛上居民恒为固定双人组：cat-live（捂脸小猫）恒左、dog-11（爱心小狗）恒右。去向由 PetHomeRegistry（会话级登记表）裁决，reconcileIsland(reason:) 在稳定事件（入场完成/scene 激活/演唱会结束/告别完成）上确定性落座，岛层只执行落座/撤下。
- 汪汪队口径（硬约束）：歌词样式 petconcert（汪汪队开大会）生效且舞台呈现中，岛宠物全撤——PetConcertRelocation.beginConcert() 置 PetHomeRegistry.islandSuspended=true 并把岛民登记回池，endConcert() 清旗并 reconcile 回填。
- 宠物词库已有：PetLines.islandHome（岛上语料，10 条）等；岛上冒泡/停聊由 PetIslandLayer 1s 心跳驱动。
- 播放内核：PlaybackEngine（ObservableObject，@Published currentTrack/isPlaying/playbackState，Combine 可订阅）；NowPlayingController 是锁屏信息唯一写入点，只在离散事件（切歌/toggle/seek/中断）同步。FoliaTrack 有 title/artist/album/id。
- 工程现状：project.yml 只有一个 app target（com.miller.folia）；XcodeGen 在 generate 时按 project.yml 的 info.properties 重写 Info.plist（定制键必须写进 properties 否则丢失）；当前无任何 .entitlements 文件；CI 用 CODE_SIGNING_ALLOWED=NO 出未签名包，zip .app 成 IPA。
- 贴纸素材：Resources/Stickers/cat-live.png 与 dog-11.png 是 APNG 动图（cat-live 60 帧），应用内由自研 APNG 解码器逐帧播。Live Activity 的 SwiftUI 视图不能播 APNG 动画。

## 待评审的计划（(75) 施工案）

1. **新 target**：在 project.yml 加 Widget Extension target `FoliaWidgets`（bundle id com.miller.folia.widgets，type app-extension，NSExtensionPointIdentifier=com.apple.widgetkit-extension），由 app target embed 依赖。共享文件 `FoliaIslandActivity.swift`（ActivityAttributes + ContentState 定义）同时编入 app 与 extension 两边。
2. **属性设计**：Attributes 静态字段为空（或仅放一个固定标识）；ContentState 含：songTitle、artist、isPlaying、phrase（当前宠物词）、petsHidden（演唱会撤下旗）。图片不进 ContentState（4KB 上限），宠物图静态打进 extension 包内（从 APNG 抽第一帧 PNG，约 120×120，命名 cat-live/dog-11，SwiftUI Image 直接引用 extension 内资源）。
3. **呈现**：ActivityConfiguration 三形态：
   - compact leading = 猫图、trailing = 狗图（整只可见、等比缩放）；
   - minimal = 猫图；
   - expanded = 猫+狗放大居两端，中间歌名+词一行；
   - 锁屏横幅 = 同 expanded 的横排版（两图+歌名+词）。
   petsHidden=true 时三形态渲染为空（EmptyView），作为演唱会期间的兜底（主路径是结束活动，见 5）。
4. **生命周期管理器**（app 侧单例 IslandLiveActivityManager）：
   - 拉起时机：App 启动后首次 scene 激活且 ActivityAuthorizationInfo.areActivitiesEnabled 时，若无在跑活动则 request 拉起；开始播放（isPlaying 变 true 且有 currentTrack）时若未拉起也拉起。
   - 更新：Combine 订阅 PlaybackEngine 的 currentTrack/isPlaying——变化时组装新 ContentState 并 activity.update（词在切歌/播放暂停事件时从 PetLines.islandHome 随机换一条）。
   - 8 小时处置：拉起时设 staleDate = now + 8h；scene 回前台（sceneDidBecomeActive）时检查 Activity.activities：为空且应运行→重拉（面包屑 la.restart）；状态 .stale/.ended/dismissed→先 end 再按条件重拉。
   - 系统关实时活动（areActivitiesEnabled=false）：不拉起/结束已有，自动回落 (74) 应用内障眼法。
5. **与障眼法互斥**：活动在跑（Activity.activities 非空且 state==.active）→ 抑制 PetIslandLayer 渲染（perch 层隐藏宠物但登记表座位不动，落座/撤下裁决照常）；活动不在跑→perch 照常。二者切换点都落面包屑（la.mutex perch=off/on），防双开叠影。
6. **汪汪队**：PetConcertRelocation.beginConcert() 里加一行调 manager.endForConcert()（结束活动，岛真清空）；endConcert() 里调 manager.resumeAfterConcert()（按拉起条件重拉）。与 islandSuspended 冻结闸同进同出。
7. **App Group**：app 与 extension 都声明 com.apple.security.application-groups = group.com.miller.folia（写进各自 entitlements），共享容器只作机会性用途（如日后动态图），v1 渲染不依赖它（图已打进 extension）；容器取不到时静默降级不崩。
8. **Info.plist**：app 侧 NSSupportsLiveActivities=true 写进 project.yml info.properties（防 XcodeGen 重写丢失）。
9. **验包**：CI 出包后解 IPA 验：Payload/Folia.app/PlugIns/FoliaWidgets.appex 存在；appex 内含两张宠物图与 Info.plist 的 NSExtension 点；app Info.plist 含 NSSupportsLiveActivities；两边 entitlements（如有签名信息可查则查）。

## 请你重点攻击的问题

A. 未签名侧载链路：CODE_SIGNING_ALLOWED=NO 出的包里，extension 的 entitlements/App Group 在用户用 SideStore+个人团队重签后还能成立吗？App Group group.com.miller.folia 这种自选 id 在个人团队下会不会注册失败导致装不上或活动拉不起？有没有更稳的 id 策略或干脆不声明 App Group 的理由？
B. ActivityKit 频次与配额：切歌/播放暂停每次 update、演唱会 end+request、回前台 restart——会不会撞 ActivityKit 的更新预算/活动数上限/频繁启停限制？staleDate=8h 的设法对不对（stale 之后系统如何呈现、用户观感）？
C. 互斥设计：用 Activity.activities 状态判 perch 抑制是否可靠（活动被系统结束但 app 在后台无感知、回前台才发现——这段时间锁屏/岛上是什么状态、perch 在 app 内不可见所以无叠影，但回前台瞬间会不会闪）？有没有竞态：reconcile 落座与 manager 拉起同帧发生？
D. 呈现合规：compact 槽位尺寸很小（leading/trailing 各约几十 pt），38pt 级宠物图放进去「整只可见」是否现实？expanded/锁屏的布局有没有系统尺寸上限会裁切？petsHidden 渲染空视图是否合规（会不会被系统判定异常）？
E. 属性/状态设计：phrase 放 ContentState 由 app 随机换词——app 挂起（后台音频播放）时切歌靠远程命令/自动连播，update 还能不能发出（后台执行窗口）？如果 update 发不出，岛上词/歌名滞后于锁屏 Now Playing，会不会穿帮？
F. 还有什么是这个计划完全没想到的（授权弹窗时机、首次拉起的系统确认、iOS 版本差异、与既有 Now Playing 锁屏卡的关系、用户在岛上长按进到的管理页等）？

输出格式：按「致命/重要/次要」分级列发现，每条给依据与建议；最后给一句总评：按此计划施工 / 改哪几处后施工 / 推倒重来。

---

# 补充材料（第二轮追加，2026-11-23 20:26，与第一轮同一评审）

第一轮你的回复因推理占满 token、正文为空，本轮重发全量简报＋以下新事实，请直接产出分级结论，推理从简。

## 新实锤：(74) 真机日志诊断（岛上无人落座的新断点）

- (74) 会话冷启动行：`pet.settings.read src=appStart miniPets=false`；`island.install ... residents=0`；其后 `isl.gate why=intro r=active` ×3，isl.seat.ok/isl.seat.no/island.resident/isl.perch74/isl.drive 全部 0 次——障眼法岛上整场无人。
- 对照 (73) 会话尾巴：岛上双人组在聊天（pet.chat surface=island a=cat-live b=dog-11）。即同一功能在 (73) 活、(74) 死，差异在会话状态而非代码路径变更（(74) 未动落座链）。
- 历史教训（同一坑第二次）：(72) 版 reconcile 曾以 miniPetsEnabled 为落座闸，该开关被手势关闭语义持久化写 false 后，落座裁决被静默压制整场（日志只有 isl.boot off 一行）；(73) 已把落座与该开关解耦。但 (74) 又出现 intro 闸（reason=active 且 introDone 未置位即 isl.gate 挡下 ×3）—— introDone 只由 reconcileIsland(reason:"intro") 置位，该会话该触发似乎从未到达。结论：这条链上存在多个「陈旧状态静默压制功能」的点，Live Activity 的拉起条件设计必须正面处理，不许再添一个新的。

## miniPetsEnabled 全部写入点清单（已全仓核完）

存储：双键同写——SettingsStore 新键 settings.general.miniPetsEnabled（legacy 回退键即 StickerSettings 的 folia.stickers.miniPetsEnabled，两读者同源同值），默认 true（键不存在→true）。

写 false 的共三处：
1. **设置页开关** SettingsViewController.companionSwitchChanged（「迷你台小宠物」开关，用户在设置页明确拨动）——真·用户设置决定。
2. **爪印钮关闭** PetSummonButton70.handleLongPress 的 off 分支（宠物开启态长按钮 3 秒=全员告别）——手势关闭语义：用户意图是「让宠物散场」，却被持久化成全局 off。
3. **长按宠物关闭** MiniBarPetStage.petPressCloseTriggered（在迷你台上长按某只宠物静止满 3.0s）——同上，手势关闭语义误写持久 off。

写 true 两处：设置页开关拨开；爪印钮召唤分支（off 态长按 2 秒）。

读者：MiniBarPetStage 的 cast 生成/维持（台上宠物总开关，语义本名「迷你台小宠物」）；(73) 后 PetHomeRegistry 落座已不读它。

## 请你裁决的问题 G（与第一轮 A–F 并列）

Live Activity 拉起条件与 miniPetsEnabled 的关系，三案：
- 甲案：完全解耦（同 (73) 对落座的处置）——LA 拉起只看：系统实时活动可用＋App 激活/播放事件＋非演唱会期；miniPets 开关只辖迷你台 cast。岛双人组在 Miller 定版里是常驻独立功能，不归迷你台开关管。
- 乙案：只认设置页写入的 off（给写入打来源标记，手势写不算数）——LA 遇「设置页 off」不拉起，手势 off 照常拉起。
- 丙案：LA 读开关、off 即不拉起，但每次被挡必须落 la.gate 面包屑写明原因（不静默）。
另：无论哪案，拉起是否应绕开 introDone 闸（LA 不依赖入场完成事件，只依赖 scene 激活/播放）？被任何条件挡下时是否都应落一行 la.gate 自证？请裁决并给依据；若你认为还有第四案更优，直接提出。
