# (73) 交付报告 — 三项 (72) 回归修复 ＋ workbench 顶部台/导播台

基线 release-72（ee377195），分支 release-73，提交 f78b36df。
交付口径三档分开：本文「代码已改」＝已落地并经 CI 编译；「验包过」＝IPA 解包核对；真机行为一律待 Miller 装机验收，不冒充已验。

## 第 1 项LocalServer 死透（歌单加载不出来）

**根因（已证实）**：(72) 真机会话中 App 挂起约 8 分钟（面包屑 10:02:23→10:10:10 UTC 断档），系统静默收走监听 socket，NWListener 的 `.failed` 从未触发，`listenerAlive` 恒 true、`start()` 被 `startRequested` 幂等锁空转——(72) 的自愈链（failed→清零→重启）在这种「静默死亡」下结构性失效；数据层 -1004 后 `data.retry` 只重发不重启，服务器永不复活，歌单页永远加载不出来。

**执行路径与改动**（Sources/LocalServer.swift）：
- 新增 `restart()`（:115，落 `srv.restart`:134）：绕开幂等锁强制拆旧监听重建，2 秒退避防抖＋延后重试。
- 新增 `probeLoopback(timeout:)`（:149）：NWConnection 真连接探活（不信标志位，实测端口）。
- 新增 `ensureAlive(timeout:)`（:173）：探针判死 → 落 `srv.dead why=probe`（:179）→ restart → 等就绪；`.ready` 后落 `srv.back port=`（:216）。
- 状态回调补死亡通道：`.failed` 落 `srv.dead why=fail`（:234）＋ hadDied 旗、`.waiting` 3 秒守望判死落 `srv.dead why=wait`（:294）、`.cancelled` 在 listenerAlive 已清零（非自愿取消）时落 `srv.dead why=cancel`（:307）。
- 新面包屑均 ≤15 字节：srv.dead / srv.restart / srv.back。
- 调用点改走 ensureAlive：NativeDataClient.swift:204（-1004 重发前，超时 4s）、NativeCoverLoader.swift:324（-1004 路径，3s）、SceneDelegate.swift:211（sceneDidBecomeActive 回前台即探活）。

**自证法**：真机复现挂起杀 socket 后，桥日志应出现 srv.dead → srv.restart → srv.back 三行且歌单恢复加载；三行缺任何一行即此修未落到执行路径。

## 第 2 项 旋转闪一下再放大 ＋ 入场大帧

**证据（已证实部分）**：(72) 入场 framedrops maxGap=185.4ms（(71) 仅 52.4ms），topcallers 含 island.refront=3.0ms；三面墙（HomeWall/WallPrototype/QueueLattice）的旋转重排原本全压在 coordinator completion（落定后一帧才 snap），QueueLattice 的 cameraScale 换档也在 completion——与肉眼「先闪一帧旧尺度、再放大补偿」时序吻合。
**未证实部分（如实标注）**：呈现层 snap 的因果属代码路径推定，无真机逐帧证据；本项以改后真机 maxGap 与观感验收为准。

**改动**：
- PetIslandLayer.swift:176-179 新增静态 `refrontSuspendCount`＋`setRefrontSuspended(_:)`；`refrontIfNeeded` 在暂停计数 >0 时整拍跳过（:304）——refront 移出入场/旋转关键路径。
- 三面墙把解冻＋invalidate＋reload（Lattice 含 cameraScale/原点钳制）从 completion 提前到 alongsideTransition 首帧以最终 bounds 执行，completion 只做恢复 refront＋即时补拍＋记账：HomeWallViewController.swift:708/712/738、WallPrototypeViewController.swift:1931/1935/1948、QueueLatticeViewController.swift:679/681/702。

## 第 3 项 灵动岛 reconcile 没走到落座步

**根因（已证实）**：`StickerSettings.miniPetsEnabled` 在 Miller 设备上被持久化写 false（写入点 PetSummonButton70.swift 的爪印钮 3 秒关、MiniBarPetStage.swift 的长按宠物关；(72) 日志实证 miniPets=false ×5）。PetHomeRegistry.runReconcile 的 off 分支每次提前返回并把岛民 depart，落座裁决永不执行——isl.gate/isl.seat.*/isl.drive 在 (72) 日志全程 0 次。

**改动**（PetHomeRegistry.swift）：runReconcile（:155）删除 off 分支提前返回与 depart；开关态只记入 isl.boot 的 `bar=on/off` 字段（:196）。依据：Miller (53) 定版岛民为常驻固定双人组，唯一认可的撤岛口径是汪汪队样式——`islandSuspended` 闸保留未动（isl.gate why=concert:171 仍在）。两个关闭写入点的 (72) 注释已同步改 (73) 口径。

**自证法**：正常启动路径上 isl.boot 必出现且带落座裁决（isl.seat.*），不再只有 off 一行。

## 第 4 项 workbench 形态改造 ＋ 导播台（Miller 18:39/18:40/18:41/18:48 四次定版）

主文件 Sources/Native/Features/Workbench/WorkbenchOverlayHostView.swift（状态机 SidebarState/代次/500ms 看门狗原样保留，几何轴向 tx→ty）：

- **收起态**：左上角白色横线把手（buildHandle:499；44×5 白线为 handleLineView 子视图，handleView 本体 60×36 透明命中盒，frame 在 layoutSubviews 按 safeAreaInsets.left+8 / safeAreaInsets.top 落位）。点按展开、在把手上竖拖跟手（dragSidebar:1068 改 y 轴）。
- **展开态**：顶部整幅宽控制设置台。panelHeight（:194）＝ contentTopPad（:203）＋内容行高合计 334；panelFrame（:572）竖屏整幅贴顶、横屏右让 52pt 避岛（岛在左侧边中段，不压岛）。
- **绕岛凹口**：updatePanelShape（:585）构建剪影——底两角圆角 24，竖屏顶缘正中切凹口（islandNotchRect:225：宽 142、高 54，iPhone 14 Pro 岛几何 ≈126×37、顶距 ≈11、底 ≈48，左右各让 8、底让 6，even-odd 切口、顶边开口）；hitTest 对凹口区返回 scrim（点按关闭），岛不被面板命中区覆盖。
- **半透明毛玻璃（18:48）**：背景三层——UIVisualEffectView（.systemThickMaterialDark）＋主题底色 45% 暗调层，两层各挂剪影 mask；panelEdgeLayer 白 14% 描边保凹口/底角边缘干净；内容层（contentView）在模糊层之上，文字控件不参与模糊、保持清晰。收起白线不变（不透明纯白）。
- **动画**：展开/收起仍走原弹簧 animator（UISpringTimingParameters dampingRatio 0.86、duration 0.55），updateGeometry（:791）改 ty 写入；面板自顶部垂下、把手随 progress 淡出，视觉上自左上角白线位置生长/收回。audit 字段随轴改名 modelTy/presTy/modelBottom/presBottom（auditChrome:726），geomOK 恒等式改 panelHeight + modelTy。
- **功能保留**：账户头（书库＋头像＋账号名＋点按管理登录）、三家登录状态行、分区（改 3×2 格：歌单/电台/搜索/专辑/本地/设置，行高 50→46 紧凑行）、设置入口——一个不少，只换容器排布。
- **灯泡＝导播台**：外部独立浮灯泡撤除（WB62HomeWallHooks.swift 删除 installPonderButtonIfNeeded/poke 变淡机制与安装调用，文件头注明去向）；台内底行新增「导播台」行（:448，金色灯泡＋「功能导览」尾标），经 openSection 的.guide 分支（:1242；WorkbenchSection.guide:1282）调 Ponder62.presentList。设置页「通用→思索」组同步：删已无对应物的「触屏思索按钮」假开关行、列表钮改名「打开导播台（教程列表）」、说明文案改指新入口（Settings62ClusterB.swift）。

**导播台内容**（Sources/Native/WB62/Ponder62.swift）：参照网页版 Ponder 的分章讲法重组（网页源：folia-major/src/components/ponder/——PagePonderTouchButton.tsx 为灯泡入口、PonderChrome.tsx＋surfaces/{basics,library,player,panel,command,settings,studio}/ 为分章讲解面；UserGuideModal.tsx 只教入口）。原生导播台 6 章（chapters:27）：入门/照片墙/播放与舞台/宠物/工作台/设置；条目 17 条（tips:37），原 10 条保留（island 条按 (73) 常驻口径改写），新增 7 条原生独有/此前缺失：login（三家登录）、wall（照片墙漫游）、lattice（Lattice 拼贴墙）、paw（爪印召唤）、pets-care（宠物陪伴互动）、desk（工作台本身）、settings-tour（12 页签导览）。列表面 PonderListViewController62 改分章呈现（章题金色小题＋已读/未读标记＋重置已读保留），标题改「导播台」。

每条导览的原生功能落点：login→WorkbenchOverlayHostView 账户头＋LoginViewController；wall→HomeWallViewController；lattice→QueueLatticeViewController；sketchbook→SketchbookDrawerView；seam→HomeWall 缝合工具条；queue/command→点播台播放/命令面板；stage-style→舞台样式选择器＋三击/长按切换通路；minibar→迷你台（MiniBarPetStage）；paw→PetSummonButton70；pets-care→MiniBarPetStage 关心气泡系统；island→PetHomeRegistry/PetIslandLayer；concert→汪汪队开大会样式；desk→WorkbenchOverlayHostView 本体；settings-tour→SettingsViewController 12 页签；theme-park→设置→外观；local-cache→WorkbenchLocalViewController＋设置→存储与备份。

## iOS 适配自查

- 横竖屏双向：竖屏凹口绕岛、横屏面板右让 52pt 避岛，panelFrame/contentTopPad 均按朝向分支；旋转经 layoutSubviews 尺寸变化点位重申 ty 与剪影（原 (58) 机制保留）。
- 安全区/灵动岛：把手贴安全区左上；内容顶距竖屏 max(安全区+6, 凹口底+8)、横屏安全区+10；状态栏时间/电量区由凹口＋顶距让行，面板底色（毛玻璃）可延展到顶但内容不入系统件区。
- 系统手势：把手竖拖与面板上拖收起为面板自有手势（原抽屉手势轴向平移），不占左缘边缘返回区（旧左抽屉把手已撤，反而消除了与边缘手势的潜在冲突面）。
- 深色外观：毛玻璃取 dark material＋暗调层，与全 App 深色口径一致；字号下限：格内行 15pt、导播台正文 13pt、章题 15pt。
- 目标机型 iPhone 14 Pro：凹口几何按其真机岛位（126×37、顶距 11）＋余量取值；无岛机型（safeAreaInsets.top < 44）不切凹口、顶距走安全区+6。

## CI / 验包 / 上传

- CI：workflow_dispatch build-ipa.yml @ release-73，run 45159913828，**success 一次过**。
- 验包（workspace 内解包）：CFBundleVersion = **73**、CFBundleShortVersionString = 3.7；二进制核对——LocalServer.restart 符号在、四条新死亡字面量 srv.dead why={probe,fail,wait,cancel} 在、isl.seat.ok/no 在、「导播台」字面量 4 处、workbench.chrome.audit 在。（注：srv.restart/srv.back/isl.boot/modelTy 等 ≤15 字符字面量走 Swift 小字符串内联存储、strings 不可见，与 (72) 二进制同模式——(72) 的 isl.boot 已在真机日志实证出现过，故不作缺失判读。）
- IPA：~/workspace/folia-deploy/Folia-3.7-73-unsigned.ipa，**47,425,098 字节**。
- 上传：remote-storage 成功，链接 https://muse.ai/files/1467544983097845/28910084315359529/ggyg0iaxktoo94ugurmcjher/Folia-3.7-73-unsigned.ipa ，到期 2026-11-25 18:58 CST。

## 待真机验收（不冒充已验）

1. 挂起 ≥8 分钟回前台/进歌单：日志应有 srv.dead → srv.restart → srv.back 且歌单恢复。
2. 旋转横竖屏：无先闪后放大；入场 framedrops maxGap 应回落至 (71) 52.4ms 水平以下。
3. 正常启动：isl.boot 带落座裁决、isl.seat.ok 出现，岛民上岛（bar=off 也不拦）。
4. 工作台：左上角白线点开 → 顶部毛玻璃台垂下、灵动岛嵌在凹口露出、横屏面板右让不压岛；导播台行点开分章导览；浮灯泡已消失；台内功能（登录/三家状态/六分区/设置）逐项可达。
