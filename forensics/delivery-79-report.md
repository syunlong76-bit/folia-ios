# 3.7 (79) 交付报告

基线 release-78 → 分支 release-79，包内 CFBundleVersion 78 → 79（app＋widget 双 target，project.yml 两处）。
范围：Miller (78) 真机验收 8 条＋01:19 拖拽三连＋01:20 全量审计令＋01:21 台词节拍问＋01:22 拖拽细化＋01:28 横屏进度条补全＋01:31 头像当机新日志（判读 log-diagnosis-2026-11-24-avatarhang.md 已转发施工）＋01:33 头像口径澄清定版。清单 13 项一次做完，中途无加项。

- CI：run 45231424676（head 6eb46fad）success（另有一轮 45230599635 亦 success、因砖重试复用守卫补丁重跑，本包以本轮为准）。
- IPA：Folia-3.7-79-unsigned.ipa，48,609,505 字节，存 ~/workspace/folia-deploy/build79/。
- 验包（已核）：CFBundleVersion=79（app 与 FoliaWidgets.appex 双 target 均 79）、CFBundleShortVersionString=3.7、NSSupportsLiveActivities=true、FoliaWidgets.appex 在位（binary＋Info.plist）；包内 WebEffect chunk（providerRegistry）含 /api/netease、/api/qq、/api/kugou 三基址；入场母带 Payload/Folia.app/EntryVideo/entry-v5-faststart.mp4 的 md5=8aed0fb4a5e9a0f500184f8a7dae45a9 与定版一致；AppIcon 图标集在位（60x60@2x 120×120 实测）；未签名结构与 (78) 同规（Payload 布局＋appex 嵌入，安装时由 SideStore/开发者账号签名）。新面包屑长串段（paw.face79/mb.root79/wall.req79/wit79.live）在二进制内实测在位；短串段（pet.fin79/isl.drop79/isl.geo79/isl.song79/la.say79/paw.act79，≤15 字节）经 Swift 小字符串立即数编码、二进制不连续，源内逐行核对在位（16 处）。
- 下载：由主聊天统一交付（文叔叔），本报告不带链接。

三档口径：本报告「已落」= 代码已改；功能是否成立一律以 Miller 真机验收为准，未真机验过的不写已修好。定案等级逐项标注（已证实/推测/未确认）。

---

## 1. 爪印上台面明处（代码已改，待真机）

- 新件 DeckPawButton79（与快速行浮层爪印同核：短按只给长按提示、长按按开关态 2s 召唤/3s 告别、走 PetSummonButton70.performPawToggle77 收口、阈值 hitTest 现读刷新；自证 paw.face79/paw.act79）。
- 新位置：三宿主点播台主排右端簇——主页墙/歌单页在下一曲与模式钮之间（30×40）；舞台主排已满，落在模式钮右侧、总时长标签左侧的唯一空隙（24×40）。展开台面恒可见，随形态淡出/禁用名单与主排其他键同规；台身点按守卫名单三宿主均已把爪印落点排除（不误触浮层呼出/收起）。
- 呼出方式：无需呼出——展开点播台即在台面上；收起细条态随主排淡出（细条上召唤仍走原浮层/长按宠物等既有路）。
- 随机播放去向维持 (77) 口径：队列面板与命令面板内可达，台面不回。浮层爪印保留不动（两处同核、开关态恒一致）。

## 2. 进度条（代码已改，待真机）

- **全条单色（已证实病根）**：删 foliaDarkenedTrack77 压暗（×0.42）整条——三宿主轨道与填充同色直用，helper 本体删除并留退役注。进度辨识靠主题小圆点把手位置。
- **尺寸同白条（横竖屏同规）**：收起轨与展开轨统一为居中 134×5、圆角 2.5（照 home indicator：长 134pt、厚 5pt、半圆角）；形态切换不再换全宽轨（lead/trail 约束两形态恒关、center/width 恒开），轨道高度两形态恒 5。横屏：轨道居中 134 不变、不拉长——与横屏白条（居中短横）同形态；台体宽度口径（min(宽,高)−24）未动。
- **小圆点把手保留原方案**：四主题圆点皮肤/发光/9pt 尺寸一字未动。
- 规格后果如实记：展开轨收窄到 134 后，seek 点按/拖动的映射区间随轨道帧走（轨道外落点按既有 clamp 归 0/1），seek 命中带仍是台底 20pt 全宽带。

## 3. 拖墙黑屏（量测补链＋一处已证实触发条件已修，本体待下轮日志定案）

- 按判读矩阵：解码侧已排除（队列浅/starve 0），本包只动「未请求/未绘制」侧，不碰解码管线。
- **新发现的触发条件（代码级已证实）**：WallPosterCell.configure 的 URL 早退分支——picUrl 换算 proxiedURLString 为 nil（本地服务 port=0 掉线、或地址形态不识别）时，原代码渲染 image=nil＋clear 底＝纯黑砖，且不计任何 tile78 量测（黑砖在量测外）。拖动中本地服务掉线即整片新砖纯黑，与 (78) 窗「blank 高、dec78 缺席」形态吻合（归因等级：触发条件已证实、是否为当晚主因＝推测，待 req79 对位）。
- 修法三件：①早退分支垫主色/哈希色（沿 (72)「不许露纯黑」口径）；②port=0 时异步 ensureAlive 拉活本地服务后以同 entry 重配置（上限 2 次、cell 复用守卫防覆盖新内容）；③请求链量测 wall.req79（cfg/req/nourl 与 tile78/dec78 同秒冲刷）：下轮判读——cfg−req 大且 nourl 高＝早退链坐实；cfg 本身远低于可见砖数＝cell 配置/实例集缺口，转查可见集差集。
- 保留量测：wall.dec78/wall.tile78/wall.req79 三件套齐在，wit79.live 名册含 req=1。

## 4. 岛带收窄（代码已改，待真机）

- 让位几何重算：yieldSlotOffset 121→90；框底段外延 6→2pt（内缘 tuck 6 不变，剪影接续靠它）。总宽账：让位态 288→218pt、平形态 208→200pt（真岛 126；余量是两只 34pt 宠物本体＋2pt 外延的物理下限，再收只能缩小宠物或让宠物压岛缘）。
- 展开形态（方案 A 格局：双宠物守主岛、歌曲信息＋台词）未动；让位触发/回位状态机未动（(78) 判读证实没卡死）。几何自证 isl.geo79（w/y 变化才落）。

## 5. 镜像岛补歌名（代码已改，待真机）

- publishMirror 增传 songTitle/artist；PetIslandLayer 新增歌名渲染位：岛框下方居中一行（y=52 起、11pt medium、白 92%＋阴影、宽 ≤260 居中截断），文本「歌名 · 歌手」（无歌手只歌名）。与宠物（底 48）纵向错开、与台词气泡（宠物上方）不打架；镜像撤除/横屏/抑制期隐藏。变化落 isl.song79（只记 on 位、不落歌名文本）。
- app 外展开岛/锁屏的歌名走 ContentState 原路，未动。

## 6. 舞台状态栏（根因已证实，修法已落，待真机）

- 纠正 (78) 报告记错类：StageViewController 本体补 prefersStatusBarHidden=true（＋preferredStatusBarUpdateAnimation=.fade），与同文件 WebStageHostViewController 的既有 override 分开记账。
- 全页复查（逐页自证，源码逐行核）：主页 HomeWallViewController:261 ✓、歌单页 WallPrototypeViewController:279 ✓、拼贴页 QueueLatticeViewController:74 ✓、舞台 StageViewController:24（本版新增）✓、入场 EntryIntroViewController:762 ✓——五页恒隐藏；MainViewController（网页舞台兜底宿主）:28 亦隐藏。设置/搜索等 overFullScreen 页随宿主外观、不捕获状态栏（沿 (78) 口径）。启动名册 wit79.live 含 sb=1。

## 7. 头像单击＋「当机」（断点已证实，仲裁改造已落，待真机）

- 按 avatarhang 判读施工（与第 13 项合并）：三宿主 agnostic74 兜底识别器改两件——①cancelsTouchesInView=false（不再整手取消台身触摸）；②require(toFail: doubleTap)（等双击裁定落空才认领；收起态双击识别器禁用、require 立即满足，细条展开不迟滞）。几何兜底语义（≤20 先纠标志再展开）不变。
- 双击链一字未动（判读：健康、无交叉无抢占）；主页 locateCurrentTrackFromCover 与歌单页 locateCurrentTrack 本体未动（断点在仲裁不在本体）；详情页头像本无 locate 绑定，与 01:33 口径现状一致，未动。
- 「当机」定性（判读已证实）：无进程级当机/崩溃——是单击被逐拍取消造成的交互假死（连点 9 下全无响应＋两对误成双击被掀进舞台页）。本版修的是交互假死，不宣称修过「崩溃」；另一处硬冻死若存在、在留存窗外，未确认。

## 8. 町景手势（审计已证实：打包与源码一致；真机断点未确认）

- 对位结果：壳内 WebEffect 打包于 2026-11-21（commit 8abead99），町景源码（folia-major/src/components/visualizer/machi）最后改动 2026-11-13——打包新于源码，无版本脱节，不重打包。
- 链路核对：打包 three chunk 含 OrbitControls（enablePan/enableZoom/enableDamping 均在），camera.ts 源码 attach 于 canvas、非 previewMode 才挂，播放页不传 previewMode；OrbitControls 运行时给 canvas 置 touch-action:none，打包 CSS 侧亦有 touch-action:none 在位；原生舞台根视图只有 tap 类识别器、pan 只在点播台把手/seek 带，无触摸拦截层盖特效区，(78) 未碰此链。
- 真机验证点（待 Miller）：町景里单指拖动应旋转、双指捏合应缩放、双指拖动应平移。若仍不动，下一锤证据在 webfx 侧（需网页控制台/桥日志看 OrbitControls 是否 attach），本包不盲改。

## 9. 系统手势（代码已改，待真机）

- 三宿主（主页/歌单/舞台）补 preferredScreenEdgesDeferringSystemGestures=[.top, .bottom]：顶缘（岛宠框 y=11..48）与底缘（收起宠 30pt 坐 Home/后台手势区）的系统手势改二段式，app 内拖动优先。代价如实：这三页里系统下拉/回主屏第一下只露小把手、第二下才生效——与 Miller 00:31 拍板的宠物登顶口径同向。
- 落痕补盲：宠物拖动 finishPress 恒落 pet.fin79（a/ph/c——grab 态被取消不再静默）；落座未命中（放手点指向岛带 y≤140 却没进落座条件）落 isl.drop79（坐标＋r=landscape/outx）。名册 wit79.live 含 fin/drop。

## 10. 拖动链（代码已改，待真机）

- grab 后 pan 断点：按判读——长按环活着（震动=enterGrabbed），断点在 grab 后触摸被取消；MiniBarRootTap78 与台内 pan 已代码级排除、未误伤。本版处置＝第 9 条系统手势延迟（首要嫌疑的源头治理）＋pet.fin79 落痕（下轮定案取消者）；状态机本体未重构。
- 小目标命中放大：MiniPetActor.point(inside:) 对 <44pt 形态对称放大命中到 44pt（收起 30→44，视觉帧不变）；岛侧 hitTargets 宠物矩形 34→44 对称放大（气泡矩形不动）。展开 48pt 不受影响。

## 11. 换住（代码复验通过，未重构）

- 起手侧修好（第 9/10 条）后复验整条落座链：dropActor 窗口坐标判定（竖屏 && y≤100 && |x−cx|≤120）与 PetIslandLayer/dropActor 本体未动、未重构；(78) 判读的成功样本链（seat→resident→seat.ok）代码原样。新增的只有未命中落痕 isl.drop79（第 9 条）——他的失败若死在起手层，本版治源；若真走到落座没命中，下轮日志可见坐标定案。

## 12. 岛台词节拍（代码已改，待真机）

- app 内：管理器新增独立 10 秒拍（sayTimer79）——仅 sceneActive＋活动在场＋播放中＋非汪汪队时走拍，推进对话后只 publishMirror 喂前台镜像、不发 Live Activity 更新，落 la.say79；镜像层呈现节拍同步改固定 10 秒（停聊/冒泡两路原随机 20–32/16–30 只对镜像期改，非镜像期自有停聊节拍不动）。
- app 外：45 秒拍（sayTimer＋contentChanged）一字未动。两拍以 sceneActive 互斥分工、状态不串（in-app 推进的当前句在回后台后被 45 秒拍原样接续，不跳句不抢拍——makeState 只读当前句的既有口径）。

## 13. 播放条自证链（仲裁改造与第 7 项合并，代码已改，待真机＋下轮日志逐环验）

- 与第 7 项同一改造点：agnostic74 的逐拍取消同样压在播放条点按路径上（mb.tch78 c 率 100% 的窗里 claim78/disp78 亦全 0）；取消源拆掉后，根级认领 MiniBarRootTap78 的触摸环境恢复。
- 根链自身补证：装配即落 mb.root79 on（先分清「没装上」与「装上没响」）；收起态落点在带内却让行时落 mb.root79 bail=pet（宠物认领优先的既有口径留痕）；展开态带内点按落 bail=form。下轮日志逐环验：mb.root79 on →（点细条）mb.claim78 → mb.disp78 → minibar expand，缺哪环查哪环。

---

## iOS 适配自查（逐项）

- 横竖屏双向独立：②轨道两形态两朝向恒居中 134×5（横屏台宽按 min(宽,高)−24、轨道不拉长，与横屏白条同形态）；④岛带横屏本就整件撤下（isPortrait 门未动），收窄只作用竖屏；⑤歌名位横屏隐藏；⑥状态栏隐藏与朝向无关、旋转重排不经状态栏取值；⑨手势延迟顶/底缘在横屏转为左/右缘由系统按当前朝向解释（UIRectEdge 语义随设备方向），拖动区（岛带横屏不在场、细条在短边）仍覆盖。
- 安全区/灵动岛避让：④剪影总宽 218/200 仍以真岛 126 为基准居中、宠物不压岛体；⑤歌名位 y=52 在岛底 48 之下 4pt、不遮岛与宠物；①爪印在台面内、不涉安全区；②轨道位置（底锚）未动、与小白线关系沿 (78)① 的 2pt 净空。
- 系统手势不冲突：⑨是本版正面处置（延迟系统缘手势、app 内拖动优先，代价已注）；⑦/⑬仲裁改造不新增识别器、不改 require 关系之外的链，双击裁定窗保留；①爪印长按 2s/3s 与台身 0.55s 长按切主题不同视图不同落点，守卫名单已排除爪印落点。
- 深色外观与字号下限：⑤歌名 11pt medium 白 92%＋阴影（深色舞台/墙面皆可读，与岛台词行同级）；②单色轨道在深浅封面砖面上沿主题色口径（收起态强金兜底等既有兜底未动）；①爪印 glyph 白 90% 与主排其他键同级。
- 目标机型（iPhone 14 Pro）：④⑥几何账全按本机口径（岛 126×37、顶 11/底 48、安全区 59/34、白条 134×5）；②134×5 即本机白条渲染尺寸；他机型同公式（安全区/屏宽驱动）。

## 待真机清单

1. ①三宿主展开台：右端簇见爪印（墙台在下一曲与模式之间、舞台在模式右侧）；长按 2s/3s 召唤/告别成立、短按只出提示；浮层爪印仍在、两处开关态一致。
2. ②收起/展开两形态、横竖屏：轨道全条一色、居中 134×5 与白条同形；小圆点在位随进度走；展开态 seek 在 134 区间内可拖。
3. ③快速拖墙：黑屏是否减轻；回传日志对 wall.req79（cfg/req/nourl）＋tile78＋dec78 判读。
4. ④岛带：平形态与播放让位态剪影明显收窄、不再横贯大半屏；宠物不压岛、不掉座。
5. ⑤播放中主页/歌单页：岛框下方见「歌名 · 歌手」一行，切歌跟随、暂停不乱跳；与台词气泡不重叠。
6. ⑥播放页（含町景）：顶部时钟不再出现；主页/歌单/拼贴/入场维持无时钟；各页布局无跳位。
7. ⑦主页/歌单页单击头像/封面：定位飞向正在播放歌曲（约一个双击窗延迟属规格内）；双击仍进详情；连点不再「当机」。
8. ⑧町景：单指拖旋转、捏合缩放、双指拖平移——逐项报。
9. ⑨⑩⑪：右侧岛宠下拖不再拉出系统下拉（或只露小把手）；台上/条上宠物长按可拖起；拖到岛下换住成立；系统下拉/回主屏二段式手感可接受否。
10. ⑫app 内岛上台词约 10 秒一句、左右轮流；锁屏/app 外仍 45 秒一拍。
11. ⑬三宿主细条点按一次展开；回传日志逐环验 mb.root79 on/claim78/disp78/expand。

构建与验包结果见报告头。本报告内功能项均为「代码已改＋验包过」档，未经 Miller 真机验收，不作已修好宣称；第 3 条黑屏本体、第 7 条硬冻死存疑、第 8 条町景真机断点均按未定案标注，未假装修好。
