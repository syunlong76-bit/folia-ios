# (74) 交付报告 — 2026-11-23

- 分支/构建 HEAD：release-74 / 0b3f6da6（三笔功能提交 632d194d、56f9a817、82b16a97、0b3f6da6）
- CI：GitHub Actions build-ipa.yml run **45169542364**，completed / **success**（前两轮中间 HEAD 的 run 已取消/仅作中间验证）
- IPA：`~/workspace/folia-deploy/Folia-3.7-74-unsigned.ipa`，**47,417,855 字节**
- 下载链接：https://muse.ai/files/1467544983097845/2121853258451337/v8nxjwm090t5k3ie29v8h8h2/Folia-3.7-74-unsigned.ipa
  - 到期：**2026-11-25 20:05 CST**；Muse 链接到期失效、任何人有链接可访问
- 验包：Payload/Folia.app 在位、主二进制 Folia 10,736,696 字节可执行、WebEffect 1949 项含 VisualizerMachi-BdzhlzLO.js 与 createMachiRuntime-7UX9yMX-.js（町景运行时在包内实证）
- 注意：包内 CFBundleVersion 仍为 73（工程版本号未随包号递增，与 (73) 同口径，不影响覆盖安装）
- 口径：以下全部为「代码已改＋CI 验包已过」，**真机结论一律未验**，逐项验收清单在文末

## 第 1 项 设置台重做（撤 (73) 大台、回归缝合工具条）

**图 1 重叠根因（代码路径推定，标注推定）**：(73) 的 WorkbenchOverlayHostView 把原书库侧栏本体改造成顶部整幅面板，面板固定高 334pt 而内容手动排布；三家平台状态行在 refreshAccountUI 中以「平台 · 昵称」长文案横排，宽度溢出后与导播台/头像区挤撞重叠；整块不透明黑板压住照片墙。

**改动执行路径**：
- 整段删除 HomeWall 的 workbench 构建与宿主（HomeWallViewController.swift，原 :412-431 构建段与 workbenchHost 属性、沉浸保存/中和逻辑、filter bar 与 immersive tap 的 host 分支），留面包屑 `workbench74 desk=removed carrier=seam`（:420）
- 缝合工具条加导播台灯泡钮（SeamToolbarView.swift：guideButton :82、configureIcon :169），转发加 "guide"（Ponder62.presentList）与 "lattice" 两 case（SeamToolbarView.swift:538 SeamToolbarForwarding）
- 工具条宽度压缩至内容总宽 356pt（分段 132→104、图标钮 36→33），收起 grabber＋命中垫改左锚（绕岛、贴左上）
- 「…」菜单经 WallMoreMenu.Actions.sections 注入四分区（歌单/电台/专辑/本地），seamOpenSection74（HomeWallViewController.swift:3449）全屏呈现＋dismissToWall，与原侧栏 openSection 同路——workbench 分区功能由工具条承接未丢
- 工具条 leading 改 safeAreaLayoutGuide 左缘（横屏绕岛）；歌单页（WallPrototype）工具条保留在关闭键下方一行（top=safeArea+56），其原浮动齿轮 settingsGear 构建段与 wallSettingsTapped 已删（与第 4 项联动）

## 第 2 项 账户区改版

**图 3 黑头像根因（强证据链）**：旧 AccountCard62 行内头像只走 NativeCoverLoader 单链、无回退，代理给不出图时恒留深灰空盘（深色下近黑）；而工具条/侧栏头像走的 WorkbenchCover.loadAvatar（WorkbenchCommon.swift:44）是「同链优先、失败 URLSession 直下回退」——同机上那条路能真显示，即回退缺失是黑盘成因。

**改动**：AccountCard62.swift 整文件重写——标题＋三头像阵列（54 wrap/48 圆图、选中白环、登录态点、盘下 10pt 平台名、未登录占位首字）、去掉「大皂先生」大字名行与整行登录按钮；选中家一行小字详情（昵称 · ID）＋退出钮；未登录点头像直开扫码面；头像改走 WorkbenchCover.loadAvatar（:188）＋avatarKeys 防串图；preferredContentSize 300×208（:38）；面包屑 `account74.tap provider=…`（:258）。
**扫码后端如实报告**：QQ/酷狗登录是与网页版同源的真实现（QQLoginClient.swift / KugouLoginClient.swift：channels→qr→check 801/802/803/800→login/status；酷狗含 register/dev），LoginViewController 已含平台页签＋220×220 二维码白卡＋轮询，即网页式扫码面，非假界面。**真机扫码能否跑通待 Miller 实扫验收**，本报告只保证代码通路真。

## 第 3 项 爪印钮（入场零帧＋右下角＋三页必达）

**根因**：PetSummonButton70 由 SceneDelegate 装到 window，0.5s frontGuard 恒提最上层——入场油画呈现期间它照样被提到油画之上（图 4 实证）。
**改动**（PetSummonButton70.swift）：bottomClearance 88→10、trailing −8→−10 落右下角本角（:51）；入场抑制三件套——static setEntrySuppressed（:93）、performPresent 呈现前同步置 true、dismissIntro 开头对称置 false（EntryIntroViewController.swift 两处）、frontGuard 每拍再按呈现链有无 EntryIntroViewController 兜底对账；面包屑 `pet.btn74 entryhide`。代价明示：展开点播台时钮叠在台体右端之上，按 Miller 定点执行。三页必达：歌单主页/歌曲主页/播放详情页经 (72) 全局可达＋本项角位，入场页除外。

## 第 4 项 撤独立设置页形态＋工具条铺三页

**改动**：SettingsViewController.swift 卡片改顶部下拉面板（top=safeArea.top+56、左右 12、高度上限 0.88→0.72（:392）、入场自上弹簧落下、close() 镜像上收），12 页签与 Settings62ClusterA–D 内容零改动——撤的是形态不是功能。呈现点保留 HomeWall 齿轮/工具条转发等活入口；WallPrototype 的独立浮动齿轮已随第 1 项删除。
**工具条三页**：歌曲主页（HomeWall，原有）、歌单主页（WallPrototype，原有）、歌曲播放页（Stage 新增 installStageSeamToolbar74（StageViewController.swift:2258），viewDidLoad 在 buildStageBar 后装配（:858），top=safeArea+82 避舞台头，动作全经 StageExitGate 程序化放行后转发，不绕退出闸）。

## 第 5 项 歌单页细条点不动（先查后修）

**截图页定案**：Miller 19:24 截图经裁切核对（右上 × 关闭钮＋左上半透明齿轮）为 **WallPrototype（歌单页/曲目墙）**，非 QueueLatticeViewController（后者无此二件、且自身零迷你台）。细条是 WallPrototype 自己的迷你台收起态。
**真凶（机制定案，产生点未定案——如实标注）**：(67) 取证（forensics-2026-11-21-67-uitaps.md C①）同会话实证：网格墙宿主细条可点通、拼贴墙宿主 8 秒反复点按零展开；病灶在「形态标志与手势识别器启停失同步」层（(63) 同型前科）——识别器被停用/被 require 链挂住时，点按根本不到 expand。静态审计 WallPrototype 全部 setMiniBarForm 调用点均先置标志，**未在现行代码中定位到单一产生行**，故按 (67) 处方②③施工，不谎称找到某一行。
**与 (72) 判断的差异**：(72) 的 MiniBarSingleHost（48 行）只仲裁「同一时刻谁能动形态」（claim/release＋sharedCollapsed），根本不经手命中与识别器启停——治错了层，所以 (73) 真机依旧。
**修法**：三宿主（HomeWall/WallPrototype/Stage）各加一只恒启用、无 require 链的 agnosticTap74 识别器，几何高 ≤20（收起态）才动作：标志未收起先落 `minibar.hit host=… heal=flag74` 纠标志＋barFormChanged，再落 `minibar.hit host=… via=agnostic74`（HomeWall :1579/:1583、WallPrototype :939/:943、Stage :2748/:2752）调既有 expand，与 expand 内既有展开行成对构成「点中→展开」自证。宠物层 MiniBarPetStage.hitTest 只认领宠物/气泡、余皆透传，已排除；backdrop 在台下层，已排除。

## 第 6 项 细条做小（小横线，全页统一）

三宿主同构改法：收起态轨道切换为居中 134×5、圆角 2.5、底距 −5.5、knob 隐藏（HomeWall miniTrackWidthC :1454 起一组约束引用，WallPrototype/Stage 同名组）；展开态还原。**容器宽/高/命中带一字未动**（MiniBarHitView 收起态 hitExpansionY=14、命中带 44pt 不变）——视觉变小、命中不缩。逐页落点：歌单主页（WallPrototype）、歌曲主页（HomeWall）、播放详情页（Stage 点播台，舞台侧共用台同规格）。宠物沉降站位：MiniBarPetStage.walkRange 收起态收窄到中心 ±92，宠物仍在小横线一带嬉戏；展开态整宽不变。

## 第 7 项 进度条单色（全页统一）

三宿主 refresh*ProgressChrome 同改：fill=形态对应主题填充色、track=同色 withAlphaComponent(0.25)（HomeWall :1705 等三处）。截图里的橙段来源是 star 主题收起填充强金 (1,0.80,0.28)——现未播段为同色 25% 透明，不再异色拼接；展开态台内进度条同口径。

## 第 8 项 町景恢复

**落点**：LyricStageProtocol.swift:304 注册表 machi 条目删除 isLocked: true——全部锁定消费者（洗牌袋 selectableStyleIds、样式选择器、StageStyleStore、StageStylePoolStore 计数）都动态读注册表，一处解锁全链生效：可选、可播、三击/长按切换与洗牌袋都会轮到它，走与其他网页特效相同的网页运行嵌入通路。网页资产完好且验包在包内（见文首）。自证：切到时既有 `style.cycle.switch to=machi` 面包屑。注意：已配置过样式池子集的用户，存量选择不含 machi（交集口径），在样式池面板可自行勾入；未配置者默认全集（21 只）自动含 machi。ThemePark62（原生调参园）要求原生 factory，machi 无原生渲染器、在彼处不可选属正确。

## 第 9 项 详情页右上角清干净

StageViewController.refreshStyleButton（:1535）改为恒定标题「样式」——原标题拼串「样式 · {特效名} · 网页运行」（特效名与 (67) A3 的 isWeb 后缀）在同一只胶囊上一并摘除；特效本身与切换逻辑不动；舞台页无第二处同款常驻标注。
**其他页面同款显示（只列不动，等 Miller 定）**：StageStylePickerViewController.swift:215 选择器行内徽标（「 锁 」/「 网页运行 」/「 原生 」三色小标）及 :43 说明文案含同类字样。

## 第 10 项（更正版）详情页手势链

按 Miller 19:48 更正口径（覆盖先前「摘双击」一版的执行口径）：
- **双击绑歌名**：view 级双击识别器与 stageHeaderDoubleTapped 回调整路摘除（原 StageViewController :276-287 区）——双击不再有任何歌名行为
- **单击显示歌名（保留为正道）**：新增 stageHeaderSingleTapped74（:313）→ showStageHeader(source: "tap74")
- **手势互斥**：installStyleCycleRecognizers 装配三击时接线 `stageHeaderSingleTap74?.require(toFail: tripleTap)`（:406），面包屑 `stage.tapchain74 single=req3fail`（:407）——三击序列中单击被压住、三击成功即单击作废，歌名全程不闪（治旧病：三击途中点按被先行识别）；真单击在三击识别失败后触发，延迟约一个多击窗口（≈0.35s，Miller 已认可接受范围）
- 单击观察器（stageHeaderAnyTapped）保留：顶栏可见时即时顺延隐藏计时，不等上述延迟；顶栏其余恢复来源（appear/track-change/设置关自动隐藏）不动；点播台自身双击进详情（stageBarDoubleTap）是迷你台规格，未误伤

## 第 11 项 灵动岛宠物落点（19:52 更正口径：岛框内完整可见）

**根因（数字定案）**：岛框（iPhone 14 Pro）x 133.5–259.5、y 11–48；旧座位 petSize 46、seatFeetY 45、偏移 ±40 算出宠物框 y −1–45、x 与岛框几乎完全重合。而 (44) 旧注释自陈设计就是「宠物坐进岛里、身体藏胶囊后」——应用窗口合成在系统岛层之下，身体必然被盖，只剩头顶一线露在岛上沿外，与 (73) 截图严丝合缝。
**技术路线实查结论**：
- 岛框本体区域**没有应用可绘像素**：该区域由 SpringBoard 的岛渲染＋TrueDepth 硬件切口占据，任何应用窗口都合成在其下层——把宠物坐标放进岛框正下方，数学上必然被盖，这不是层级没提够（岛层 zPosition=10000 已是应用内最高，压不过系统层）
- 岛框周边的真显示像素在左右「角」带（同高 11–48、x 0–133.5 与 259.5–393）；系统自己的 Live Activity 布局（compact leading/trailing、expanded 槽位）放的也是岛剪影向两侧扩展出的黑色区域，**从不把内容压在摄像头胶囊本体上**
- **本版落法（障眼法对位）**：宠物移出岛体正下方死区，落进左右真像素带紧贴岛框边缘（PetIslandLayer.swift：petSize 46→38、slotOffset=85（:148）、脚底与岛框底对齐 48），座位按双人组序号定死（reseatAll :596：cat-live 恒左槽、dog-11 恒右槽，单只在场不串位不居中）；身后垫一块与岛框同高 37、同圆角 18.5 的纯黑框底（syncIslandBackdrop74 :628），横跨双槽＋岛框全宽，把「宠物＋框底＋真岛」接成一整条岛框剪影——宠物在（扩展的）岛框里面、整只可见。落点自证 `isl.perch74 <asset>=<minX>..<maxX> form=pill`（:621）
- **展开形态**：本应用未运行 Live Activity，岛在应用使用期间恒为收起胶囊形态；Face ID/来电/计时器等系统展开事件期间，系统层按平台设计恒压一切应用内容、且应用侧无岛形态观测 API——此期间宠物被系统岛临时覆盖属平台行为，事件结束即恢复，本版无法也不谎称能避让。若 Miller 要宠物由系统亲手渲染进岛 UI（Live Activity compact/expanded 槽位），那是新扩展 target 的独立包（即原 (31) 锁屏包二期重档路线），不在 (74) 尾巴上硬塞

## iOS 适配自查

- 横竖屏：工具条 leading 改安全区左缘、横屏绕岛；Stage 工具条全宽横屏同理；岛层横屏维持既有保守隐藏；设置下拉面板横屏 top/左右约束同口径成立
- 安全区/灵动岛：工具条收起 grabber 左锚避岛；Stage 工具条 top=safeArea+82 避舞台头与岛；爪印钮贴右下安全区（bottomClearance 10＋safeArea 约束）
- 系统手势：设置面板 present 弹簧/下拉关闭沿既有呈现路径；详情页手势链单击 require 三击失败、三击本体不加 require、点播台双击/长按未动；迷你台命中带 44pt 未缩
- 深色外观：账户头像占位与黑框底均为既定深色件；进度单色用主题色＋同色透明，深浅两态同色系
- 字号下限：账户盘下平台名 10pt 为图注级（与原设计同级，真机可读性待验）；其余新增文案无小字
- 目标机型：几何常量按 iPhone 14 Pro（393pt 宽、岛框 126×37@top11）定，其他机型岛框几何不同——岛落点在非 14 Pro 机型上不对位，属已知边界

## 待真机验收清单（全部未验）

1. 三页工具条在位、灯泡导播台可开、齿轮开设置下拉面板、设置项一项不少；横屏工具条绕岛不压状态栏
2. 账户区：三家头像真显示（网易云/QQ/酷狗）、无大字名行；点 QQ/酷狗头像出扫码面并**实扫一次**验后端
3. 爪印钮：入场油画全程零帧、右下角落点、展开点播台时叠压观感、三页可达、长按 2s/3s 语义不变
4. 歌单页细条：点小横线能展开（桥日志对 `minibar.hit host=wallproto` 与展开行成对出现）；墙主页/详情页细条不回归
5. 小横线＋单色：歌单主页/歌曲主页/播放详情页（含舞台侧）逐页核对；命中仍好点；宠物在横线一带嬉戏
6. 町景：样式选择器可选、播得动；三击/长按/洗牌袋轮到 machi（日志 `style.cycle.switch to=machi`）
7. 详情页右上角：无特效名、无「网页运行」字样，只剩「样式」
8. 详情页手势：单击出歌名（延迟可接受）、三击只切特效且全程歌名不闪、双击无反应
9. 灵动岛：双人组整只在岛框剪影内可见（猫左狗右）、不再只露耳朵；日志 `isl.perch74` 坐标与截图对位
