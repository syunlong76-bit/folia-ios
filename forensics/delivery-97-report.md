# (97) 交付报告 — Virelai/Folia iOS 壳

## 状态

- 分支/提交：`release-97`，代码提交 `11a5cad0`（自 release-96 起点 `edf825df` 切出）。
- CI：workflow_dispatch `build-ipa.yml`，run **45997094139**，`completed success`（head `11a5cad0`）。
- IPA：`~/workspace/folia-deploy/build97/Folia-unsigned.ipa`，**68,054,938 字节**（artifact 15196757151）。较 (96) 的 49,535,222 字节增 18,519,716 字节，其中梵高烟花素材 18,493,988 字节，余 25,728 字节为代码/资源增量，账目对得上。
- **文叔叔（主通道）**：https://c.wss.ink/f/swj5n7gwni7 — 游客上传、无取件码；API 侧复核通过（任务内文件 `Folia-unsigned.ipa`、总大小 68,054,938 字节精确一致）；上传完成于 2026-11-27 约 20:41 CST，**约 2026-11-28 20:41 CST 自动销毁，请立即取件**。
- muse.ai 备用链：https://muse.ai/files/1467544983097845/1003752679468406/gdzqxvpon3utucksl27k75ml/Folia-unsigned.ipa（2026-11-29 12:30 UTC 过期；Miller 的 Safari 有断流前科，只作备用）。

## 验包（逐项实测）

- `CFBundleVersion=97` ✓；`CFBundleDisplayName=Virelai` ✓（CFBundleName 仍为 Folia，与 (96) 口径一致）；`CFBundleShortVersionString=3.7`。
- 入场母带 `EntryVideo/entry-v5-faststart.mp4` md5 = `8aed0fb4a5e9a0f500184f8a7dae45a9` ✓。
- 三项 API base 在位：主二进制 `/api/netease`×6、`/api/qq`×2、`/api/kugou`×2；`songPreviewPlaying` 在 WebEffect 束 `providerRegistry-*.js` 内 ✓。
- `FxMedia/vangogh-fireworks.mp4` 已入包（18,493,988 字节），与源文件 md5 一致（`cfc33510a64b1b68c931be2a4a8073b6`）。
- 本包新面包屑在位（结构旁证，非单次字面量 grep 下判）：长字面量实测命中 `p97 knob home dy=`、`p97 knob wall dy=`、`p97 knob stage dy=`、`p97 deck stage r=`、`p97 locate tap host=home`、`p97 locate tap host=wall`、`p97 layout begin from=`、`p97 layout end from=`、`p97 layout apply mode=`、`p97 seed asm ms=`、`prev-session-full`；类型/符号实测命中 `VangoghFwView97`（含 `start97`/`stop97` 符号）、`XmasMetalRenderer97`、`XmasMetalCanvas97`、`LyricBlurRow97`、`bandLuminance97`、`updateCoverMode97`、`applyCoverMode97`、`prevSessionFullText`、`fxEventsText`、注入脚本 `runResizeChain97`/`coal97`。短字面量（`p97 vgfw burst`、`p97 xmas gpu=`、`p97 hind=`、`p97 lrc mode=`、`fx events: none`、`FxMedia`、`screenBlendMode` 等，均为 ≤15 字符段）二进制字节级为 0，系 Swift 小字符串内联存储的已知现象（与 (96) 同判例），其宿主类型/方法符号均在位，不作缺失论。

## 逐项落点（11 项）

1. **修取证 — 已落码待真机验**。`WebEffectBridge.swift` 新增 `prevSessionFullText()`、`fxEventsText()`（拼 `.old.log`＋`.log`）；设置页导出（`SettingsViewController` 的 BridgeLogViewController 与 `Panels62` 两处）拼接顺序定死：旧尾巴 →「—— 上一会话全量 ——」（缺席标注 `prev-session-full: empty`）→「—— 特效事件 ——」（缺席标注 `fx events: none`）→ 本会话；cap 由 1000 提到 100_000。验收硬标准：真机导出物能搜到 `p96 session begin` 类会话见证行（本包会话见证行为 `p97 session begin` 同族）——待真机导出验证。
2. **圣诞树 GPU 化 — 已落码待真机验**。新文件 `ChristmasMetal97.swift`（`XmasMetalCanvas97: MTKView`＋`XmasMetalRenderer97`，图集＋实例化绘制，精灵实例 stride 48B、`.bgra8Unorm`、混合 `.one/.oneMinusSourceAlpha`）；`ChristmasTreeStageRenderer` 删除逐帧全量重画的 P93CanvasView 路径，改 MTKView 原生 drawable 分辨率手动 `draw()`，帧构建走 `buildFrame97` 实例缓冲。粒子分账未动（lyric 3000/tree 3000/garland 340/snow 760＝7100）。fps 面包屑加记 `fp=`（`Breadcrumbs.footprintMB97()`）；mount 落 `p97 xmas atlas=`、init 落 `p97 xmas gpu=`。进入约 1.1s 冻结的旧因（3 倍渲染＋全量重画）已随路径替换去除，稳态 60fps 与内存不涨待真机日志验。
3. **旋转卡画面 — 已落码待真机验**。靶点为 WebEffectBridge 注入脚本的 resize 风暴（约 34 条/秒）：`onResize` 改合并——外部 resize 只计数 `coal97`，静默 120ms 后只跑最后一记 `runResizeChain97(true)`；自派发 resize 直通 `runResizeChain97(false)` 不重跑 verifyBuffer；`report()` 附 `coal` 字段并清零，原生 `p94Web` 行尾加 `coal=`。判定：真机旋转时看 `p94Web` 行的 `coal=` 是否显著 >0 且 stage.rotate 冻结消失。
4. **三处 deck 统一 — 已落码待真机验**。实根（代码坐实）：舞台 prev/next 两钮从未设 `layer.cornerRadius`，A4Chrome91 画在 button.layer 上的 1pt 边框呈方形；主页/歌单页同钮均有 20。修：`StageViewController` 两钮补 `cornerRadius=20`，装配后落自证 `p97 deck stage r=prev/play/next/console`（应 20/23/20/20）。底板栈三宿主同构（blur→themeLayer→rimLight→glassTint 同序同参）未动；录屏所见「碎纹」判定为当前迷你台主题画作 monet-snow 本身（三处同源），非 deck 缺陷——此判定待 Miller 真机目视确认。详情页 deck 即舞台 deck，随之统一。
5. **台面加大＋圆点归位＋圣诞双轨 — 已落码待真机验**。
   - 胶囊高 `MiniBarQuickRowView.expandedBarHeight` 62→**72**（唯一出处，三宿主同源跟随），圆角 31→36 共 12 处同步。
   - 圆点实根：三宿主 knob.centerY 均锚 `bar.bottomAnchor − 8`（收起态轨心），展开态轨心在 bottom−3.5，恒高出 4.5pt。修：三宿主改锚 `progressTrack.centerYAnchor`（收起态几何不变、展开态归位）；各宿主落自证 `p97 knob home/wall/stage dy=`（应 ≈0）。
   - 圣诞双轨实根（录屏 t=22.5 抽帧量测）：下轨为**系统小白条**（距屏底约 11pt，与台轨间隙 2.2pt，即 (84) 设计账 gap=2），在圣诞深色场景显形、亮地板场景不可见。修：`StageViewController.prefersHomeIndicatorAutoHidden = (activeStyleId == "christmas" && stageBarCollapsed)`，刷新点在 `setStageBarForm`（落 `p97 hind=`）与样式切换处。
6. **取消特效推荐歌曲 — 已落码**。`GlobalFx87` 整条拆除：provider/onPlay 回调、recCard 属性组、推荐卡构建段、`layoutRecCard93/maybeShowRec95/showRecCard/startRecRotate93/hideRecCard` 函数组、开启边沿与烟花时间轴两处触发点；`SceneDelegate` 接线与 `fxRecommended87` 同步删除；全仓 grep 残留仅注释。注意：`ConsolePanel82` 内的拍立得推荐卡池是控制台自有功能，按 Miller 定版口径未动。
7. **封面爱心改右下角 — 已落码待真机验**。`WallPrototypeViewController` 两处 tile：拍立得/纯图 tile 的 heartDisc91 x: 6→`bounds.width−30`（右上角 diaryButton90 在 y=6 顶行、不相撞）；150×150 封面 tile (6,124)→(126,124)。行式 cell 爱心本就在右侧（w−76）未动；展开卡无爱心口径不变。
8. **点播台头像定位 — 已落码待真机验**。实根：两面墙台的 `miniBarTapped` 定位区只认 miniTitle 文字帧，点封面（miniCover）落空走控制台开面板，定位从未触发（旧旁证 `wall.q83 fly=` 是封面加载在途数、非定位飞行，一并更正）。修（Home＋WallPrototype 两宿主同构）：定位区扩为身份簇（miniCover＋miniTitle＋miniArtist 三帧任一命中）并前置于 seekband 判定，命中落 `p97 locate tap host=home/wall`，下游走既有 locate82/locate86 链；seek/双击/pan 三处豁免同步扩到身份簇。舞台台本身即详情页、无定位语义，未动。
9. **梵高烟花 — 已落码待真机验**。新文件 `VangoghFw97.swift`：AVPlayerLayer＋`compositingFilter="screenBlendMode"` 滤色叠加、`resizeAspectFill` 原生分辨率渲染、播完回主线程循环、点火回调在起播＋1.2s；`GlobalFx87.setFw` 唯一挂钩（on 时 `start97` 决定 `vgFwActive97` 并落 `p97 vgfw on=`，素材缺失落 `p97 vgfw miss` 并回落原生粒子）；视频在场时原生粒子停算停画、只保留 15.5s 自动收尾；点按走 `restart97`（落 `p97 vgfw tap`）；点火联动既有 `onFwBurst91`（金色 (1, 186/255, 92/255) @ (0.5W, 0.32H)，落 `p97 vgfw burst`）。素材按 v4 路线以源片 3840×2160 满高竖裁重制：1216×2160（无放大）、30fps、5.5s、H.264、18,493,988 字节；抽帧目检：0.6s 金色火花轨迹纯黑底、2.5s 主漩涡在场、夜空/积云/城市灯火已抠除，与过审 v4 一致。
10. **封面歌词新样式 — 已落码待真机验**。数据通路审计先行（`forensics/lyric-word-timing-audit-97.md`）：**网易云 YRC 逐字戳全链现成**（`/lyric/new`→`parseYRC`→`LyricLineData.words`→`wordSweepProgress` 已在消费）；**QQ 无逐字**（函数端 `/lyric` 501 未实装、仅 LRC 假设）、**酷狗无逐字**（写死 fmt=lrc、无 KRC 解析）——无戳行走既有均分降级（行时长 clamp(行距, 0.8, 10)×singingRatio），不假装逐字。呈现按样板 `design-samples-97/cover-lyric-apple-style.html` 移植：`SweepLyricLineView` 改三段（未唱/已唱/前锋＋双 mask、左对齐）；新增 `LyricBlurRow97` 邻行离屏渲染＋按距 CIGaussianBlur；横带罩改整卡幅 6 档羽化渐变；衰减表 |d|=0: op1/scale1.12、1: .66/blur.7、2: .40/1.8/.97、≥3: .26/3/.95；行迁移 0.62s cubic-bezier(.32,.72,.24,1)；字重当前 .heavy/邻行 .semibold、kern=字号×0.02。**自适应明暗**：宿主 `updateCoverMode97` 用引擎当前封面图后台采样（`bandLuminance97`：300×400 cover-fit、position 50%/68%、纵向 30%–80% 横带、sRGB 线性化加权平均，每曲一次＋缓存，落 `p97 lrc mode=light/dark L=%.3f`）；L≥0.35 浅封面→深炭字＋已唱 #C8102E＋前锋 #FF7847；否则白字＋已唱纯白＋前锋 #FFE9AD。未移植项如实记：样板 2.15 倍行高未采用（保留现行窗口几何，行高=字号×1.65）。
11. **排版 mode=1/2 慢与卡退 — 只补证＋不改变行为的优化，未宣称修复**。面包屑：`switchPlaylistLayout93` 入口落 `p97 layout begin from=/to=/src=/entries=`，收口 `p94EndWallSwitch` 落 `p97 layout end … ms=`；`applyPlaylistLayout91` 落 `p97 layout apply mode=/vis=/entries=/ms=`；种子装配主线程段落 `p97 seed asm ms=/n=/mode=`。优化（不改变行为）：①种子/分页数据落地时若当前为 A/B 版式（墙隐藏），跳过隐藏墙的 `reloadData`、置 `wallReloadPending97`，切回 mode 0 时由 `p94ReanchorWall` 补刷（实例集数据侧照常刷新，定位/切换读数不受影响）；②封面预热 `prefetchWall83` 推迟一轮 runloop，不与装配同帧抢主线程/解码并发。**闪退仍无现场样本，结论：待 (97) 真机日志定案。**

## iOS 适配自查

- 横竖屏：胶囊台 72 高与圆角 36 为三宿主同源常量，横竖屏同尺寸口径不变；圣诞 Metal 画布走 drawable 原生分辨率、旋转时按新 bounds 重建实例缓冲；歌词罩与行帧均以 bounds 计算，旋转重排成立。
- 安全区/灵动岛：本包未新增贴边元素；圣诞收起态隐藏小白条（`prefersHomeIndicatorAutoHidden`）仅在 christmas＋收起两条件同时成立时生效，展开即恢复系统口径。
- 系统手势：定位身份簇扩围未新增手势、未改既有手势优先级；seek pan/双击豁免与身份簇一致，不与边缘返回/下拉关闭冲突；特效层点按在视频在场时走 restart，未截留系统手势。
- 深色外观与字号：封面歌词双模式（浅/深封面）均带柔光晕保证可读下限；deck 边框修复不改变字号；新面包屑仅日志、无上屏文案（守样板先行令：不加他没要的文字）。
- 目标机型 iPhone 14 Pro：梵高素材 1216×2160 按设备原生分辨率渲染不降清；圣诞 GPU 路径去掉 3 倍渲染，纹理账在舞台 200–250MB 硬线内（图集单张）；全应用峰值 ≤450MB 硬线未新增大头（视频 18.5MB 为磁盘占用、播放内存为单层 AVPlayerLayer）。

## 面包屑判定清单（真机验收时对读）

- 导出：搜 `p96 session begin`/`p97 session begin` 应在「上一会话全量」段出现；`prev-session-full: empty`/`fx events: none` 只在对应日志真缺席时出现。
- 圣诞：`p97 xmas gpu=`、`p97 xmas atlas=` 在位；`p94 xmas fps=` 行带 `fp=`，卡顿时对读 footprint（卡会话 311–345MB vs 流畅 155–197MB 为 (96) 基线）。
- 旋转：`p94Web` 行尾 `coal=` >0 说明合并生效；stage.rotate 不再连冻三轮。
- deck：`p97 deck stage r=` 应为 20/23/20/20。
- 圆点：`p97 knob home/wall/stage dy=` 应 ≈0。
- 圣诞双轨：`p97 hind=` 在圣诞＋收起时为 1、下轨（小白条）消失。
- 定位：点头像/封面/歌名/歌手任一处出现 `p97 locate tap host=`，随后既有 locate 链落行。
- 梵高：`p97 vgfw on=1`、`p97 vgfw burst`、`p97 vgfw dur=`；素材异常时 `p97 vgfw miss`＋回落原生粒子。
- 歌词明暗：`p97 lrc mode=light/dark L=` 与封面实际明暗一致（基线：《想》0.792 判 light、DOUDOU 蓝封面 0.054 判 dark）。
- 排版：`p97 layout begin/end`、`p97 layout apply`、`p97 seed asm` 三组对读耗时与 entries/vis。

## 未定案项（明示）

- 第 11 项闪退：无现场样本，本包只补证＋装配优化，**未宣称已修**，待 (97) 真机日志定案。
- 第 2/3 项：稳态 fps、旋转冻结是否消失、圣诞内存协变量，均待真机日志验，本报告只称已落码。
- 第 10 项逐字填充：仅网易云有真逐字戳；QQ/酷狗为均分降级（审计文件在案），函数端补逐字属后端工作、不在本包。
- 第 4 项底板「碎纹」：判定为主题画作本身（monet-snow），待 Miller 目视确认。
- 施工自检中发现并已修复一处：拆推荐卡时误删 `buildCards91` 收尾括号（括号平衡自检拦截、提交前已补回，CI 编译通过为最终凭据）。

## 文叔叔上传方式备注（供后续包复用）

游客上传走 www.wenshushu.cn 的 Web API（匿名登录→addsend→getupid→fast→分片 psurl PUT→complete→copysend）。关键坑：addsend 的 A-code 密码输入必须是**实际发送的请求体原文**＋token 的 MD5（服务端按原文校验）——密码输入与请求体序列化不一致即报 `user-agent error:-8`（无 A-code 为 -4）。本次以 orjson 序列化原文同时作请求体与密码输入，一次通过；33 分片（2MB/片）约 75 秒传完。
