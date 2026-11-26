# 审计：账号头像与登录状态（(91) 真机反馈，只读审计）

对象：release-91（commit 1682268f）。Miller 原话：「我登陆的头像呢？点开头像跳出其他登陆二维码」。
先说总裁决：**他的描述在代码里完全对得上号，且是两个独立问题叠在一起**——
① (88) 按他自己的令摘掉墙面全部常驻头像后，全 App 还能看到账号头像的地方只剩侧栏账户头一处，
而那一处只读本地资料缓存、无任何网络自愈，缓存缺头像就恒显占位；
② 现行唯一「点头像」的落点是整页登录中心（LoginViewController），它打开即对未登录平台
自动出扫码——他已登录的账号信息被压成登录页里一行小字，点开看到的自然先是别人的二维码。

另先定案一条：(91) 提交 1682268f 的文件清单不含任何账户/登录/会话/侧栏文件
（`git show --stat 1682268f` 过滤 account/login/session/workbench 为空），
**头像通路在 (91) 与 (90) 逐字相同**，(90) 的修法就是现行行为。

---

## 1. 现行头像都长在哪

### 1.1 (88) 摘掉的：墙面常驻定位头像（与账号头像不是一回事）

- 摘除提交 89126281「(88) 工坊蓝本移植第一步：头像全部去掉（工具条/主页缝/歌单缝
  书脊头像位全摘，点头像定位与账户卡转发链随之退役……）」——这是 Miller 2026-11-25
  令摘的**墙面常驻圆形头像**（原功能是点头像定位正在播放＋开账户卡），不是账号头像本体。
- 现行代码只剩退役注释与无头像见证面包屑：
  - 工具条：`Sources/Native/Features/Wall/SeamToolbarView.swift:331`
    `port88 bar=avatarless`；同文件 :783 起「avatar」（账户卡）动作已退役，
    `isGlobalAction` 只剩 settings/search/guide。
  - 主页缝/歌单缝：`Sources/Native/Features/Wall/Seam85Views.swift:295`
    （host=home）、`:667`（host=wall）均落 `port88 seam=avatarless`。
  - 宿主侧：`Sources/Native/Features/Wall/HomeWallViewController.swift:3413-3415`
    注释明言「工具条头像已摘除……账户卡入口只剩设置页账户组」；同文件 :3982、
    :4301 为 seamAvatarTapped / avatarLocate85 整组退役注释；
    `WallPrototypeViewController.swift:2253-2255` 为 via=avatar 定位入口退役注释。

### 1.2 现行还存在的账号头像（共三处，全部不在墙面上）

| # | 位置 | 显示什么 | 数据来源 |
|---|------|----------|----------|
| A | 侧栏（顶部控制设置台）账户头 `sidebarAvatar` | **只显一家**：第一家「已登录且有头像」的真头像图；无图时显昵称首字；再无则人形图标占位（person.crop.circle.fill）；右下登录态点 | `ProviderSessionStatusQuery` 同步读资料缓存，零网络（见下） |
| B | 账户卡 AccountCard62（三平台头像阵列） | 三家各一 54pt 圆盘：真头像图／图未到时透出盘下平台首字（网/Q/酷）＋登录态点＋盘下平台名；点选已登录家下方出「昵称 · ID」＋退出钮 | 同上缓存；呈现时带 (90) 自愈回填（见 §3） |
| C | 登录页 LoginViewController 账号区 `avatarView` | 56pt 圆盘，**只显当前选中平台一家**的头像；无占位字、无回退链（见 §3.4） | 同上缓存；头像图走 URLSession 直下 |

证据：
- A 的装配：`Sources/Native/Features/Workbench/WorkbenchOverlayHostView.swift:180`
  （`private let sidebarAvatar = WorkbenchAvatarView()`）、`:330-356`（装进侧栏账户头，
  48×48）；刷新逻辑 `:1198-1216`——头像取 `loggedIn.first { $0.avatarURL != nil }`，
  加载走 `WorkbenchCover.loadAvatar`；占位规则在同文件 `WorkbenchAvatarView`
  （:1287 起）：`setFallback(name:hasImage:)`（:1349-1364）有图隐占位、无图有昵称显
  首字、无图无昵称显人形图标。**关键：refreshAccountUI 是纯同步读缓存、没有任何
  enrich/网络回填调用**（:1170-1216 全段无网络）——缓存里没有头像 URL，这只头像
  永远是首字/人形占位，不会自愈。
- A 旁边的文字区：同文件 :1176-1181，账户名只显第一家已登录的昵称（无则「未登录」/
  「已登录」），提示行「点按扫码登录」/「点按管理登录」；三家状态行（:1183-1196）
  只有「平台 · 昵称/未登录」文字＋状态点，**没有头像、没有 ID、没有 VIP**。
- B 的装配与占位：`Sources/Native/Features/Wall/AccountCard62.swift:167-258`
  （avatarCell：圆盘＋首字占位在图下层 :190-196、真图盖上 :198-205、登录态点
  :207-214、头像加载 :247 走 WorkbenchCover.loadAvatar）；详情行 :261-311。
  入口只剩一处：设置页「查看账户卡（三平台）」钮
  （`Sources/SettingsViewController.swift:664-672` 装配、`:1017-1031`
  accountCardTapped85 以 popover 呈现）。
- C 的装配：`Sources/Native/Features/Auth/LoginViewController.swift:74`
  （avatarView 声明）、`:175-179`（56pt 圆盘样式）、`:345-346`（尺寸约束）；
  渲染在 refreshAccountUI（:473-481，见 §3.4）。
- 资料缓存本体：`Sources/Native/Core/Network/NativeSessionStore.swift:341-361`
  ——saveProfile 合并语义存 UserDefaults 键 `session.profile.<provider>`，
  字段只有 accountId / displayName / avatarURL 三项；`:226` 为退出/失效时全清。
  状态快照统一出口 `Sources/Native/Features/Auth/ProviderSessionStatus.swift:24-41`：
  isLoggedIn 以 Keychain 会话存在为准，其余全读上述缓存，「拿不到就不给，
  不在此发网络请求」（文件头 :3-7 自陈）。

### 1.3 不是账号头像的头像（避免混淆）

- 评论区头像：`Sources/Native/Features/Player/Comments87.swift:327`，是评论者头像，
  与登录账号无关。
- 歌单创建者头像：`Sources/Native/Core/Network/EdgeOneAPIClient.swift:1068-1084`
  （creator.avatarUrl），是歌单元数据，不进账号缓存。
- Miller 截图里缝顶部的两个圆钮是**宠物贴纸**（捂脸猫/抱心狗），不是头像位；
  (88) 后缝上根本没有头像位（§1.1 见证面包屑为实）。

---

## 2. 点头像的行为链

### 2.1 他实际能点到的「头像」只有侧栏账户头，落点是整页登录中心

- 侧栏账户头整块（头像＋昵称＋提示行）挂同一个点按手势：
  `WorkbenchOverlayHostView.swift:327-328`（header 加 UITapGestureRecognizer
  → accountTapped），处理在 `:1218-1220`：accountTapped → presentLogin()；
  presentLogin 在 `:1222-1235`——**不分登录状态，无条件** present 整页
  LoginViewController（.overFullScreen，不带 initialProvider）。
- 也就是说：哪怕三家全已登录，点头像/账户头也永远打开「登录中心」，
  不存在一个「我的账号页」落点。注释（:325）自陈设计意图是「未登录去登录、
  已登录去管理」，但实现上管理与登录是同一页，账号信息只是该页的一行状态字。

### 2.2 打开登录中心后发生什么——「跳出其他登陆二维码」的代码出处

- `LoginViewController.swift:119-122`（viewDidLoad）：入口平台 = initialProvider
  ?? .netease；**该平台未登录就立即 startFlow() 出扫码**。侧栏入口不带
  initialProvider，所以默认落在网易云页签：他若网易云未登录（或会话被判未登录），
  打开瞬间就是网易云二维码全屏。
- 即使网易云已登录，页面构成仍是登录中心形态：平台行组（三家可切，:320-328
  装配）、当前平台账号区（头像＋状态行）、扫码区。切到任一未登录平台，
  providerChanged（:410-435）同样 setQRVisible/startFlow 出该家二维码。
  **他描述的「点开头像跳出其他登陆二维码」即此**：头像点开的不是账号页，
  而是登录页；未登录平台的二维码是这页的主内容。
- 已登录平台的账号信息在这页能看到多少：refreshAccountUI
  （`LoginViewController.swift:456-472`）——nameLabel 只显**平台名**
  （「网易云/QQ 音乐/酷狗」，:446-453、:460），昵称与 ID 只在
  accountStatusLabel 一行 13pt 小字里：「已登录 · <昵称> · ID <accountId>」，
  且只有**当前选中平台**一家；切走即换。**VIP 信息全仓无此字段**：
  三家 LoginStatus/LoginProfile 结构与资料缓存均无 VIP 字段（Auth 目录、
  AccountCard62、NativeSessionStore 全文 grep vip/VIP 为空）——已登录账号的
  VIP 状态在 App 里任何地方都看不到，定案。
- 账户卡（B）内的点按分工是另一套且符合 (90) 定版：未登录点头像 →
  openLogin(provider:) 直接开该家专用扫码页（`AccountCard62.swift:313-327`
  avatarCellTapped、:334-349 openLogin，pageSheet＋预选平台）；专用模式下
  LoginVC 只剩平台名＋二维码（`LoginViewController.swift:39-43` dedicated90
  定义、:355-364 装配即隐平台行/头像/状态/动作钮）。已登录点头像 → 仅选中
  并在下方出详情行（昵称 · ID＋退出），不出码。**所以「点头像出二维码」若发生在
  账户卡内，点的是未登录的那家，属 (90) 他本人定的流程；若发生在侧栏账户头，
  则是 §2.1 的无条件登录中心。** 他截图语境（找不到已登录头像）指向后者为主。

---

## 3. 三家头像数据通路

统一落盘口径：三家都经 saveProfile 写同一 UserDefaults 资料缓存
（NativeSessionStore.swift:341-361），渲染端统一读 ProviderSessionStatusQuery
（ProviderSessionStatus.swift:24-41）。差异只在「取数解析」与「触发回填的时机」。

### 3.1 网易云（通路最全，与他「网易云正常」的实测一致）

- 取数：`Sources/Native/Core/Network/NativeDataClient.swift:253-271`
  fetchLoginStatus → /api/netease/login/status → `profile["avatarUrl"]`
  （同 profile 的 userId/nickname）。
- 落盘触发点最多：扫码成功即补（`LoginViewController.swift:920-925`）、
  冷启墙面主线顺手回填（`HomeWallViewController.swift:895-899`）、
  缝刷新 seamRefreshAccount（同文件 :4525-4529）、登录页 enrich
  （LoginViewController.swift:499-501）、同步钮（:723）、账户卡自愈
  （AccountCard62.swift:127-130）。
- 定性：字段单一来源、回填点覆盖冷启主线，**结构上不会恒占位**。

### 3.2 QQ（头像单点依赖一个接口的字段猜测，无第二来源）

- 取数：`Sources/Native/Features/Auth/QQLoginClient.swift:136-157`
  fetchLoginStatus(cookie:) → EdgeOne /login/status → data.profile，
  头像候选字段：`profile["avatarUrl"]`，次选 `info["logo"]` / `info["avatarUrl"]`
  （:154-155）；昵称候选 nickname/nick/name/userName（:151-153）。
- 落盘触发：扫码成功复核（`LoginViewController.swift:1044-1048`）、
  enrich（:506-509）、同步钮（:737）、账户卡自愈（AccountCard62.swift:134-138）。
- **缺口定案一**：QQ 的第二资料来源（会话 envelope）只带 accountId/displayName、
  **不带头像**——ProviderSessionStatus.swift:26-30 回填分支只补这两项，
  envelope 结构本身无 avatar 字段（NativeSessionStore.swift:62、:265-272）。
  即 fetchLoginStatus 的头像字段一旦没命中，任何路径都补不回来。
- **缺口定案二（机制）**：saveProfile 是合并语义，avatarURLString 传 nil =
  不改此字段（NativeSessionStore.swift:341-353）——解析不到头像时落盘的是
  「昵称有、头像键仍缺」，状态层 avatarURL 恒 nil，所有自愈重试走的是同一个
  fetchLoginStatus 同一套字段候选，**重试多少次结果都一样，恒占位**。
- 字段候选与后端实回是否对不上：**推测，未定案**。候选集（avatarUrl/logo）
  是 (53) 期按注释里的后端形态写的（QQLoginClient.swift:19），本审计无后端
  实回包可对；要定案需抓一次 /login/status 的 QQ 实回 JSON 看头像真字段名
  （也可能是图 URL 为 http 或带防盗链，直下失败——同为推测，见 §3.4）。

### 3.3 酷狗（登录时资料复核失败即恒缺，且先清后存放大了窗口）

- 取数：`Sources/Native/Features/Auth/KugouLoginClient.swift:265-289`
  fetchUserDetail(cookie:userId:) → /user/detail → profile 取
  data.user_info / userinfo / profile / data 四选一（:277-279），
  头像候选字段 avatar / pic / sizable_avatar / picUrl（:281-282），
  昵称候选 nickname / nick_name / username / name（:279-280）。
- 落盘触发：扫码成功复核（`LoginViewController.swift:1158-1176`）、
  enrich（:514-517）、同步钮（:747）、账户卡自愈（AccountCard62.swift:139-147，
  userId 自 cookie 解析 :153-164）。
- **缺口定案**：登录成功路径先显式全清旧资料、只存 accountId，再调
  fetchUserDetail 补资料（LoginViewController.swift:1162-1176）；该复核若抛
  非失效类错误（网络/5xx/malformed），代码只在 sessionInvalid 时清会话，
  其余情况**保留会话但资料就停在「只有 accountId」**——昵称与头像双缺，
  账户卡显「酷」字占位、详情行显平台名兜底。此后回填只剩打开登录页选中
  酷狗（enrich）或打开账户卡（自愈）两个手动时机，日常使用不会触发。
- 字段候选与后端实回是否对不上：同 QQ，**推测未定案**，需 /user/detail 实回包。

### 3.4 (89)「QQ/酷狗只剩占位」在 (90)/(91) 修没修

- (89) 的报法与 (90) 的修法记录在 `forensics/delivery-90-report.md:58-60`
  （任务 11）：根因定为「enrich 只在 LoginViewController 且只对选中家触发，
  账户卡只读缓存从不回填」；修法为账户卡呈现时自愈回填。
- **落码核实：修法真实落码且 (91) 未动**——AccountCard62.swift:109-152：
  rebuild() 末尾对「已登录且 avatarURL 或 displayName 为 nil 且本卡未试过」
  的家触发 enrichProfile90（:109-116 触发条件、:121-152 三家分路），
  成功 saveProfile 后 rebuild 回刷；LoginVC 侧 enrich 门控放宽为「昵称或
  头像任一缺失都补」（LoginViewController.swift:485-488）。
- **为什么 (91) 真机仍可能只剩占位（逐项定性）**：
  1. 自愈入口太深：账户卡现行唯一入口是设置页里的一个文字钮
     （SettingsViewController.swift:664-672），日常路径（侧栏头像）**没有
     自愈**（§1.2 A）——他找不到头像的地方恰好是最不会被修的一处。定案。
  2. 自愈每家每卡只试一次（AccountCard62.swift:35 声明、:113-114
     enrichAttempted90 门控），失败静默；且如 §3.2/§3.3，若失败原因是字段
     没命中，试多少次都同结果。定案（机制）＋推测（字段）。
  3. 渲染链不一致：账户卡/侧栏走 WorkbenchCover.loadAvatar（同链代理优先、
     失败 URLSession 直下兜底，`WorkbenchCommon.swift:48-95`）；登录页
     avatarView 却走裸 URLSession 直下、无兜底、无占位字
     （LoginViewController.swift:473-481）——直下失败（http 被 ATS 拦、
     CDN 防盗链等）时登录页头像是**空白盘**，比占位更像「头像不见了」。
     代码事实定案；是否命中取决于各家 URL 形态，推测。

---

## 4. 结论与最小修法选项（不写代码）

### 4.1 结论（对 Miller 三问的直接回答）

1. 「我登陆的头像呢」——账号头像数据在（资料缓存＋三家取数通路都在），
   但 (88) 摘掉墙面头像后，**日常能看到头像的只剩侧栏账户头一只，且只显
   一家、只读缓存、无自愈**；QQ/酷狗缓存缺头像时它恒显首字/人形占位，
   看起来就是「头像没了」。
2. 「点开头像跳出其他登陆二维码」——现行点头像（侧栏账户头）的落点是
   整页登录中心，不分登录状态；打开即对默认平台（网易云）判未登录出码，
   切未登录平台也出码。**全 App 不存在一个「已登录账号页」**：昵称/ID
   只能在登录页状态行和账户卡详情行各看一行，VIP 更是全仓无字段、无处可看。
3. (89) 的 QQ/酷狗占位问题 (90) 修了自愈机制并真实落码，但自愈挂在
   最深的账户卡入口上、且对「字段没命中」型失败无效，所以真机仍可复现。

### 4.2 最小修法选项（按动处从少到多）

- **选项一（最小，只补自愈与落点分工）**：侧栏账户头刷新时对「已登录但
  缓存缺头像/昵称」的家补一次与账户卡同源的 enrich（复用
  AccountCard62.enrichProfile90 的三家分路）；账户头点按分工改为：
  已有任一家登录 → 开账户卡（AccountCard62，现成）；全未登录 → 才开
  登录中心。动两处：WorkbenchOverlayHostView（refreshAccountUI/
  presentLogin 一带）、复用现成回填函数，不新增页面。
- **选项二（在选项一上加「头像行」）**：侧栏账户头下方的三家状态行升级为
  三家头像行（各家小圆盘＝真头像/首字占位＋昵称＋状态点，即把账户卡的
  avatarCell 形态搬到侧栏），点某家已登录 → 账户卡定位该家详情；
  点未登录 → 该家专用扫码页（现行 dedicated90 通路）。动三处：
  WorkbenchOverlayHostView 状态行装配、AccountCard62 增加预选 provider
  入参（现已有 selectedProvider 初值逻辑可复用）、侧栏点按分工同选项一。
- **选项三（补 VIP 与字段定案，非排版）**：先抓 QQ /login/status 与酷狗
  /user/detail 的实回包各一份，核头像真字段名（及是否含 VIP 字段），
  再决定是改字段候选还是加第二来源；这是 §3.2/§3.3 两处「推测」转定案
  的前置，不抓包不许改解析。动：QQLoginClient/KugouLoginClient 字段候选
  （抓包后）、（三家 LoginProfile 若加 VIP）NativeSessionStore 资料缓存
  字段与账户卡/侧栏展示行。

### 4.3 未定案清单

1. QQ 头像真字段名、酷狗头像真字段名与后端实回的对应关系——需两份实回
   JSON 才能定案（本审计为纯代码侧，标注推测）。
2. 登录页头像空白盘是否由 http/防盗链引起——需一条真实头像 URL 实测
   直下结果。
3. 他真机当前三家资料缓存的实际内容（哪家缺 avatarURL 键）——需故障
   时段日志或下个包在 refreshAccountUI 面包屑里带上各家 avatar 有无
   （现行 `workbench.account.refresh` 只落登录家列表，不落头像有无）。
