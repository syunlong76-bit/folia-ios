# Folia (82) 修复包交付报告

- 分支：release-82（头提交 43073b74）
- CI：首跑 45386084186 failure（MiniBarQuickRowView 5 处 UIImage 可选解包，已修）；二跑 45386398063 success
- IPA：build82/Folia-82.ipa，48,705,317 字节

## 逐条落点

### A. 修复
1. 墙面黑屏：NativeCoverLoader 缓存 totalCostLimit 96MB→160MB（成本取解码像素字节与压缩字节大者，守 120–180MB 硬线）；新增 placeholderImage（哈希色对角渐变＋居中半透明 ♪，NSCache ≤64）与 prefetch82（.prefetch 低优先级）；WallPosterCell 无图与无 URL 两分支均先画占位，wall.tile78 的 blank 只剩 pic 本身为空；网格 prefetch 的 tier 改与 cell 同式计算（旧固定 360 是命中率低的一条实根）；WallScrollMetrics.flush 在同窗加落 wall.ph82（loader hit/miss 增量＋tile blank）。Breadcrumbs wit82 已登记 ph/tap/loc/cov/fm/rot/light 全项。
2. 按钮命中：三宿主台身识别器组（tap/doubleTap/longPress/agnostic）统一 delaysTouchesEnded=false 并挂 delegate；各宿主新增 UIGestureRecognizerDelegate 扩展，台身识别器对 UIControl 落点拒收（shouldReceive 返回 false），按钮触摸直达 .touchUpInside。逐钮 tap82（host/zone/窗口坐标）：三宿主 play/prev/next/console/body，控制台 qclear/qrow/mode/shuffle/fx/paw/like/sketch/seg/focus/light/help。
3. 点头像下沉：HomeWall locateCurrentTrackFromCover 落 locate82（via=wall 本墙有卡／via=stage 本墙无卡直达舞台／via=none 无曲）；WallPrototype 封面单击落 locate82 via=self 并走本墙 locateCurrentTrack（此前该墙根本没绑）；详情页（舞台）内不触发，语义统一为「切换到正在播放的歌曲」。
4. 竖屏岛在播簇：PetIslandLayer 中央簇签名加页态＋抑制态两字段（isl.cov82）；新增 lastCenterInput82 存根与 forceResendCenter82(page:)，主页墙/歌单墙/舞台三宿主 viewDidAppear 强制重发（home/wall/stage）。
5. 小白条形态：三宿主 setBarForm 落 minibar.fm82（tw 收起 134／展开为各台轨道实宽，th 收起 5／展开 4，orient 横竖屏）；收起态花朵把手 scaleY 0.25 收平不凸起、填充纯白＋轨道白 35% 系统白系；贴底锚（收起 +31.5 与 home indicator 重合）沿用 (77) 口径未动。
6. 特效旋转落痕：Stage viewWillTransition 去掉 webEmbedStyleId 门控，全样式落 rot82 三点（freeze 于旋转开始含 style/web 字段、landed 于转场 completion、ready 于 alongside 布局＋快照落定，ms 同源计时）；webfx.rot81 网页样式路径保留对位。本包只落码＋自证，不宣称真机达标。

### B. 新台＋控制台
7. 极简台 E 毛玻璃（Miller 19:30 点选定版）：DeckGlyph82 字形工厂（prev/next/pause/play 手绘路径，prev＝左竖条＋左指三角、next＝右指三角＋右竖条，绘制后回读核对方向无误；其余 SF 模板图）；展开高单一出处 MiniBarQuickRowView.expandedBarHeight 70→132（DeckLayout82 同值）；三宿主同几何：封面 46×46 圆角 23、歌名/歌手、进度轨夹双时间标签（11pt）、花朵把手 20pt、控制行中心 +30（播放 44／上下曲 40 居中 ±26）、控制台纯图标圆钮 38 右端；主题油画图层恒隐藏（毛玻璃本底）；5 秒闲置收细条旧规不变；旧 DeckIconSet81.swift 已删除，MiniBarQuickRowView 字形改走 DeckGlyph82，不留双轨。舞台宿主补齐台内封面/歌名/歌手（此前舞台台无封面行），模式钮/爪印/槽位钮不上台（对象保留、回刷无副作用，职能进控制台）。
8. 控制台面板 G3 紧凑版：ConsolePanel82（.pageSheet、custom detent 55% 屏高、grabber、圆角 28、深色毛玻璃）：播放队列露 3.5 行＋底部渐隐、当前行琥珀高亮、垃圾桶清空、点行 playAtIndex 即播；纯图标功能行 6 钮真接通——播放模式（UIMenu 四档写 QueueManager.playMode）、随机（shuffle toggle）、特效（舞台走 openStylePicker82 原选择器通路；墙宿主走通用 StageStylePickerViewController 写 StageStyleStore 同源）、宠物（StickerSettings.miniPetsEnabled 单击切换＋PawFirework81 闪光烟花，即原爪印职能）、喜欢（LikesStore＋NativeDataClient.setLike 失败回滚，与旧台同通路）、速记簿（主页墙 toggleSketchbook82 抽屉钩子；其余宿主无抽屉本体，点按 toast 提示）；音量滑杆与 PlaybackEngine.volume 双向同步；墙面外观图标分段（透光/实色，无文字）映射 SettingsStore.gridCardMinOpacity 0.55/1.0 并发 .foliaSettings62AChanged 即时重读；海报聚焦叠色开关接 WallLight82.focusEnabled82 门控；帮助钮呈内置说明。逐钮 tap82 已落。
9. 开灯/关灯：LightSwitch82（200×46、玻璃方钮 36、像素月亮/太阳逐格绘制、光晕随钮、spring 0.55/0.72、粒子 morph＋闪光带）＋Particles82（burst/ring/trail 像素方点）＋WallLight82（状态 UserDefaults 持久化、跨页广播 .foliaWallLight82Changed、焦点按墙分存）；开灯＝全部封面亮起（可见砖按对角序 45ms 错峰点亮、每张白闪＋8 颗星尘）；关灯＝整墙压暗 0.78、点砖首点只点亮（粒子环），点已亮砖放行原动作，焦点转移带粒子拖尾。已接入主页墙（双 collection，wall=home）与歌单墙（wall=tracks）；落 light82（on/off/focus/mv/focusgate）。
10. 衔接不回退：迷你台宠物沉降/进度条宠物、岛台词、AI 导演、下一首预备、三击切特效、逐歌记忆代码未动；汪汪队样式期间台/岛宠物撤除规则未动。

### 图标追加令（Miller 19:20）
上一曲/下一曲/播放/暂停/播放列表/队列字形全部经 DeckGlyph82 独立绘制函数出图，未焊死进布局；J/K/L/M 四套样板未定版，本包按现字形出包，定版后只换字形函数即可替换。

## 未定案清单
- 全部条目均为代码已改＋CI 出包，真机结论（黑屏 blank 趋零、tap82 逐钮计数、岛竖屏簇在场、fm82 观感、rot82 三点量测、灯光波浪/聚光手感）待 Miller 真机验收＋下一份会话日志判读，本报告不宣称真机达标。
- 全新档案实测登录：本包未改 WebEffect bundle（仓库内 bundle 已验三 API base 在位），登录实测未在本包重跑，沿用 (81) 档案实测结论。
- B9 其余封面页（QueueLattice 队列格、搜索结果等非 WallPosterCell 页面）未接入灯光，待后续包。
- 舞台槽位钮（(66) barSlotLeft/Right）随 E 极简台不上台，设置键保留无副作用；如需恢复另议。
- 控制台特效钮在墙宿主走通用选择器（写 StageStyleStore），舞台不在场时选定样式于下次开台生效，非即时呈现。
- 图标 J/K/L/M 待 Miller 定版后替换字形。

## iOS 适配自查
- 横竖屏双向：台宽 min(屏宽,屏高)−24 居中、展开高 132 三宿主同值，旋转经既有冻结管线重排；控制台 detent 按屏高 55% 自适应；岛中央簇横竖屏同位不隐藏。
- 安全区/灵动岛：台底锚 safeArea（展开 −10／收起与 indicator 重合）沿用既有口径；控制台为系统 sheet 天然避让；封面行 top 14 在台内、不触岛。
- 系统手势：控制台升起/下拉关闭走系统 sheet 弹簧；台身 delegate 豁免只作用于 UIControl 落点，非按钮落点的既有 require 链（单击等双击裁定等）不变；seek 命中带锚进度行上下 9/18pt。
- 深色外观：E 台与控制台按定版图为深色毛玻璃，白系文字/字形对比达标；收起细条改系统白系。
- 目标机型（iPhone 14 Pro）：台宽 369、控制台高 55%≈469pt、内容实测约 446pt 不裁切；字号下限 11pt（时间标签，与既有口径一致）。

## 验包五项
1. 体积：48,705,317 字节 ✓
2. 入口母带 md5：8aed0fb4a5e9a0f500184f8a7dae45a9（与定版母带一致）✓
3. 三 API base：包内 WebEffect/assets/providerRegistry-Bupbawyu.js 含 /api/netease、/api/qq、/api/kugou 三项 ✓
4. 版本号：CFBundleVersion 82（ShortVersion 3.7，com.miller.folia）✓
5. 签名结构：Payload/Folia.app（Mach-O arm64）＋ PlugIns/FoliaWidgets.appex，未签名（设计如此，安装时由 SideStore/开发者证书签名）✓
附：二进制自证——wit82.live 名册行（ph/tap/loc/cov/fm/rot/light 全 1）与 locate82/minibar.fm82/rot82/light82/console82 字面量、ConsolePanel82/WallLight82/LightSwitch82 类型名均在包内二进制中检出；tap82/wall.ph82/isl.cov82 三条为短字面量（≤15 字节，Swift 内联编码、二进制不留整串），源码与名册双在。
