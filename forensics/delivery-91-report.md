# (91) 交付报告 — Folia iOS

- 分支：release-91（自 release-90 拉）；CFBundleVersion 90 → 91（project.yml 两 target 已改）。
- 范围：Miller 2026-11-26 23:16 令「前面所有问题一起改打包」，任务书十条全量落码。
- 样板依据：Space `folia-91-yang-ban`（七视图已审）＋ A4 图标定版（design-samples-91/icons/icon-set-a4.png，字形源 /tmp/iconbuild/gen2.py、gen3.py）。
- 本报告口径：以下均为**代码落位＋静态自查**结论，未经真机验证；真机验证点在文末逐项列明。

## 成员深度差分对账（构建铁律）

对全部 11 个删改文件与 release-90 同名文件逐成员比对嵌套深度：**全部文件终深度 0、无既有成员深度位移**。移除成员均为预定替换并逐项核对：Deck82 的旧 M 字形局部量与 notesGlyph90（→notesGlyph91 改名）、GlobalFx87 的 Fx87RootView.touchesEnded（纯显示层退役）/buildOverlayUI（拆为 buildFlash91＋buildCards91）/UIAlert 旧码局部量、Polaroid90 的 imgSide 局部量。新增成员同名同深度（如 WebEffectBridge 的 message 局部量为新增行）。另对新文件与全部改动段做了悬空引用 grep（loggedIconM88/notesGlyph90/buildOverlayUI 等零残留）。

## 逐条

### 1. 特效窗点按根治（最高优先）
- **根因（已定案）**：GlobalFx87 的 UIWindow（level 1500）显示期间全屏点按被吞。(90) 真机日志实证：雪开 sn=1（22:31:22）后至切后台（22:31:32）间点按面包屑一条不留；sn=0（22:31:34）为回前台生命周期自重置、非点关；Fx 窗隐藏后点外关闭立即恢复（22:31:39）。旧 Fx87RootView.hitTest 纸面放行与真机行为不符，(87) 起未验透；(90) hard-stop 只修了状态清场层、没修点按层。
- **修法（换架构）**：Fx 窗改纯显示层——install() 置根视图 `isUserInteractionEnabled=false`，删除 Fx87RootView 的 hitTest/touchesEnded 覆写。原靠 Fx 窗子视图接点按的三件（祝福卡/写灯钮/推荐卡）迁主窗浮层 `FxOverlayHost91`（钉满主 window；hitTest 仅当点落在可见子视图帧内才交回系统命中，其余整屏穿透）；闪光层为纯视觉件、仍留 Fx 窗。孔明灯点按看祝福改走主窗旁路：既有旁观型 tap recognizer（cancelsTouchesInView=false）重写为——先 `lantern(at:)` 命中，再 `tapHitsInteractive91` 沿主窗 hitTest 祖先链查 UIControl/集合格/表格式/三张浮层卡，未命中任何可交互目标才 `showBless` 并落 `p91 lamp hit`；灯区不补放烟花（旧口径保留）。控制台侧自证：ConsoleFX85.tap 落 `p91 tap zone=<el>`、点外关闭落 `p91 tap zone=outside`；装机落 `p91 fxwin=pure`。
- **文件**：GlobalFx87.swift、ConsolePanel82.swift。

### 2. 四特效联动（封面＋宠物、全页面）
- **新建协调器** `FxLinkage91.swift`：单例，CADisplayLink tick 轮询引擎状态迁移（不用 onStateChanged——该单回调已被 ConsolePanel82 占用）；烟花爆点经引擎新回调 `onFwBurst91`（burstStar 内 flashWall 后触发）接入。各宿主注册：墙砖/条目封面经 WallPosterCell.configure 与两只新 cell 的 configure 注册（cover＋container），prepareForReuse 注销；宠物经 MiniBarPetStage.makeActor/removeActor 注册/注销。只动 transform/opacity/亮度，不改布局；动画全走合成器属性；无注册时停链。
- **形态（逐项照样板联动视图实测值）**：风砖主倾角 1.5–3.5°（逐砖伪随机、方向交替、i%3 dy −3、延迟 (i%4)*110+(i/4)*70+(i*29)%60 ms），阵风 1.5s 后转无限摇摆（幅 0.45–0.85°、周期 2.3–3.7s、repeat+autoreverse）；关风弹簧 0.62 回正（保留砖基础 scale）。风宠 lean 两态（rotate −1.4°/skew −2.4°/tx 0 ↔ 0.9°/−4.4°/2.5，skew 经 transform.c=tan 实现）2.6s 交替。雪砖檐高 11（白 .95、底部圆角 6、anchor (0.5,0)）7s curveEaseOut 长满、延迟 i×0.16s；关雪 0.5s 淡出移除。雪宠堆 27×12（anchor (0.5,1)）4.6s 长成，开雪 +5.3s 首抖：±5° keyframe 0.48s＋5 颗雪粒 520ms 外飞淡出＋雪堆缩回 .25 后 4.6s 重长，周期 +7s。灯暖光逐帧算：砖心 window 坐标到各灯距离，glow（暖橙 255,170,70、插 cover 之上、frame/圆角跟 cover）alpha＝max(0,1−d/155)×0.62；宠物仰头：任一灯灯程 progress=1−y/屏高 ∈ (0.16,0.86) 且距宠物 <220pt → rotate −5.5°＋ty −2（弹簧 .35）。烟花：280pt 内砖 glow 换爆点色，alpha 0→.34（0.12s）→0（0.76s）；宠物跳跃 ty −9（弹簧两段各 0.28s、逐只延迟 60ms、0.5s 节流）。
- **覆盖面**：主页墙/歌单墙（WallPosterCell 两墙共用，含展开卡即详情页封面——同一 cell 展开态）、歌单 A/B 版式条目、迷你台宠物池。
- **取舍（须知）**：①舞台演唱会宠物（PetConcertRenderer 独立渲染系）**未接联动**——其 transform 由演唱会状态机独占，与联动 transform 冲突风险高，留待单独口径；②风开时宠物 transform 由轻晃独占，仰头/跳跃/抖雪让位（样板未定义叠加口径）；③灯开时 tick 每帧覆写 glow alpha，会盖过同砖的烟花闪光（次要）；④宠物联动变换落 actor 本体，与 actor 自有入场缩放（0.5→1）/抓握缩放（1.07）存在瞬时覆盖面，状态切换后自愈。
- **文件**：FxLinkage91.swift（新）、GlobalFx87.swift（lanternFrames91/onFwBurst91）、WallPrototypeViewController.swift、MiniBarPetStage.swift。

### 3. 图标全套换 A4（只改图标）
- **修法**：单一字形工厂 Deck82 整段换 A4 语言（gen2 48 画布坐标 ÷2 落 24 画布）：play 三角描边（(10,8.1)(17.3,12)(10,15.9)、线宽 1.7、round join、无填充）；pause 双圆角矩形填充（x 8.85/12.65、y 7.8、w 2.5、h 8.4、rx 1.25）；prev 竖条（x 6.8、w 2.2、rx 1.1）＋三角描边 1.4（(16.9,8.2)(10.6,12)(16.9,15.8)），next 镜像；list 无 A4 原定义、按同语言补形（三横细线 1.4＋三实心圆点 r1.5）。新增 `slidersGlyph91`（三横线 y 8.75/12/15.25 白 .85 线宽 1.4；三圆 r2 于 (13.5,8.75)/(10,12)/(13,15.25)、填充白 .30＋描边 1.15），`.console/.sliders` 路由至此（控制台内部设置图标同步换，SF sliders 退役）。`notesGlyph91` 按 gen3 note_solid ÷2 绘制后整体绕 (12,12) rotate π 复制成 180° 中心对称——控制台入口即双音符上下对称。fxGlyph 线宽 1.7→1.4 归 A4 细线口径。钮面 chrome 新增 `A4Chrome91.apply`（幂等）：160° 高光渐变层（白 .15→.04）钉满＋边框白 .38/1pt＋imageView 柔光晕（白 .30、radius 6、offset (0,2)）；已应用于控制台 configureIconButton/configureIconButtonSF89/configureTransButton87/fx 四钮/help 钮、三宿主台面播放钮与控制台入口钮（圆角 21）。首绘落 `p91 icon=A4` 自证。
- **不动**：任何按钮位置/尺寸/布局/功能零改动（本条仅字形绘制与钮面层）。
- **文件**：Deck82.swift、ConsolePanel82.swift、三宿主（见任务 4）。

### 4. 点播台构成（23:11 口径）
- **修法**：展开高单一出处 `MiniBarQuickRowView.expandedBarHeight` 84→124（账：顶留 11＋顶行 42＋间 8＋中行 42＋进度行约 21）。三宿主（WallPrototypeViewController/HomeWallViewController/StageViewController）同构改造：主行 centerY 拆分——封面 −30（顶行：封面＋歌名＋歌手名）、其余钮 ＋20（中行）；setMiniBarForm/setStageBarForm 回写逐项同步；miniTrackTopC −9→−7（轨道随台高下沉至最下沿）；标题 trailing 改 bar.trailing −14（原挂 next 钮链）；播放钮改 centerX 居中、next 钮 trailing 改挂播放钮 leading −2。
- **注明（冲突/取舍逐处）**：①prev/next 仍恒隐藏——(87)「撤下台面藏控制台」定版未被本条点名推翻，中行可见钮＝播放（居中）＋控制台入口（居右），prev/next 以原链挂播放钮左侧（宽 0 不占位）；②进度把手**不动本体**：现行把手＝9pt 圆点＋MiniPlayerThemeLayer.knobSkinView 17pt 主题皮肤（代码自注「样片花朵把手 17pt」），与站立定版「进度条花朵小圆点把手保留」（2026-11-25 13:17）一致，判为已达标；③两端时间标签 ±28 不动——(86) 已按 (85)④「往内收保持框内」定版，轨道占满两标签之间即样板「全宽」形态；④油画底与四主题保留未动；收起态/5 秒收细条口径（DeckLayout82/84）未动。
- **文件**：MiniBarQuickRowView.swift、三宿主 VC。

### 5. 控制台排版（模仿网页版）
- **修法**：卡圆角 24→20、内距 16→12 一批（竖屏拍立得区左右/clear 钮/条带/speaker/音量值/开灯长条/help 钮；横屏拍立得区/条带/功能行左）。新增两条发丝线（白 .08、0.5pt、inset 12）：线 A 悬挂于拍立得区下＋5、线 B 悬挂于特效行上 −7（相对锚、不入主约束链，避免与 (89) 约束链冲突）。内容一件不少（拍立得区、封面条带、钮排、功能行、音量行、图层/特效/聚焦行、开灯长条 200×46、队列文字行均未动）。开灯链在新点按架构下全链复核：lightSwitch.onToggle→WallLight82.setOn 的 (90) 四环面包屑（port90 light tap/toggle/setOn/apply cells=N）保留未动。
- **注明**：圆角 20 覆盖 (89) 曾对齐网页的 24——本轮以 (91) 样板控制台视图（圆角 20）为准。
- **文件**：ConsolePanel82.swift。

### 6. 孔明灯许愿页重设计
- **修法**：新建 `WishLanternViewController91`（overFullScreen＋crossDissolve），替换 UIAlertController 形态；入口仍是原写灯钮（GlobalFx87.wishButtonTapped 转呈本页、自 MiniPlayerPanelPresenter.topViewController() 呈现，onRelease 回调引擎 releaseWishLantern——该方法已去 private）。整页黑 .55 压暗（透出原页面、守「特效不换背景」口径）；floatGroup 居中偏上（centerY −52、边长＝灯宽 ×1.9）；径向暖光晕；灯体宽 216（横屏 172、viewDidLayoutSubviews 按朝向切）、高＝宽 ×1.4；bodyGradient 四段暖色（照引擎纸面色）＋bodyMask 灯体轮廓（与引擎 drawLantern 同比例：顶半宽 .37w、底半宽 .30w）＋灯口亮椭圆；文字实时落在灯纸上：UITextView 楷体（Kaiti SC→STKaiti→KaiTi→系统 medium 兜底）20pt 深棕 (74,26,4,.85)、宽 .58 灯宽、高 .42 灯高、60 字截断、placeholder「把秘密写在这盏灯上…」；取消（描边）/放飞（暖渐变）钮各 104×44 圆角 22 位于灯组下方；viewDidAppear 起 floaty 5.2s 上下漂 ±7＋自动聚焦；键盘 frame 变化整页上移 overlap×0.35；放飞 2.6s 弹簧（damping .82）上移 −46% 屏高＋scale .24＋淡出，完成回调（空文案默认「愿心想事成」）后 dismiss。面包屑 `p91 wish open`/`p91 wish view`/`p91 wish fly`。
- **文件**：WishLanternViewController91.swift（新）、GlobalFx87.swift。

### 7. 拍立得题注收进卡内
- **修法**：PolaroidCard90.layoutSubviews 重写：题注固定带 captionH=30（歌名 y=H−27 高 13、歌手 y=+14 高 11，字号 11/9.5pt 等比——歌手 8.5→9.5）；照片顶边下移至 pad+12 给 ➕ 留卡纸边缘位、照片高＝H−imgTop−30（题注带不再被照片压）；➕ 帧改 (W−26, 2, 24, 24) 钉卡纸右上角、不压照片。卡间距沿用既有排布（旋转后题注恒在各自卡内、不再外溢叠字）。
- **文件**：Polaroid90.swift。

### 8. 歌单三版式可切换
- **修法**：WallPrototypeViewController（歌单页宿主）同文件 extension 新增整套：顶部分段钮（毛玻璃胶囊 166×30、top=safeArea+8、centerX；三钮 现行/A/B 各 52×24，选中白底黑字），选择持久化 UserDefaults `foliaPlaylistLayout91`，切换落 `p91 plist mode=<n>`。现行版＝既有照片墙零改动。A 杂志式：黑底 UITableView（rowHeight 56、无分隔、contentInset top 46/bottom 120），歌单头走 tableHeaderView（高 118：大标题 26 bold、计数「N 首 · 歌单」12.5、发丝线）；行＝编号 %02d（monospaced 12.5 白 .35）＋封面 44×44 圆角 6＋标题 14（在播 semibold）＋歌手 12＋爱心（18 disc＋11 心）＋➕ 24＋在播 3pt 琥珀条。B 唱片架式：头行（标题 17 semibold＋计数 12.5）＋横滑 UICollectionView（itemSize 150×198、lineSpacing 14、inset left 64/right 24、高 214）；格＝封面 150×150 圆角 10（在播描边 2 琥珀＋左上 speaker 角标）＋➕ (120,6)＋爱心 (6,124)＋标题 13＋歌手 11。三套数据源共用 entries/startQueueAt 起播通路；种子落地、分页拼接、refreshVisiblePlaybackUI 三处均同步 reloadAltPlaylist91。z 序自查修复：applyPlaylistLayout91 每次把切换钮、左侧缝、缝工具条 bringSubviewToFront（A/B 全屏黑底视图装配在后，不许盖住导航；点播台 buildMiniBar 在 viewDidLoad 中晚于本装配、天然在上层）。无头像（三套均无头像位）。
- **注明**：杂志行/架格内容 leading 64 为避开左侧缝（书脊）的近似值，真机按缝实际宽度复核。
- **文件**：WallPrototypeViewController.swift。

### 9. 封面爱心接通
- **修法**：真源＝既有 LikesStore（UserDefaults `folia.likedTrackIds`），零新状态；LikesStore.toggle 内新增发 NotificationCenter `foliaLikesChanged91`（userInfo 带 trackId），各面订阅回刷、跨面同源。墙砖（WallPosterCell）：左下 24pt 毛玻璃圆片（systemThinMaterialDark＋边白 .16/0.5）＋15pt 心；落位 x6、y＝纯图档 H−30/普通档 titleY−30；歌单形条目不挂；controlsVisible 或非歌曲时同隐。条目（杂志行/架格）：18pt disc（黑 .45＋边白 .16）＋11pt 心。未选 .heart 白描边空心、已选 .heartFill 实心红 #FF5973。点按动效按 Pulse Heart 时序：0.135s 收缩 disc＋钮至 .3 → completion 内 toggle＋回刷 → 0.315s 弹簧（damping .45）回 identity（过冲段即弹簧过冲）；toast 已喜欢/已取消喜欢＋面包屑 `p91 heart on=<0/1>`；云端 NativeDataClient.setLike 同步、失败回滚 toggle（各面既有模式）。与右上 ➕（x=W−30,y=6）对角错开、不挡封面主体。
- **注明**：QueueLatticeViewController（歌单格墙）有自有 cell、条目是歌单非歌曲，不挂爱心（与墙砖「歌单形条目不挂」同口径）。
- **文件**：LikesStore.swift、WallPrototypeViewController.swift。

### 10. status.songPreview\* 泄漏修复
- **定案（分级）**：已证实——`status.songPreviewPlaying` 为上游 Folia 同源键：上游语言包有正式译文「当前账号仅可试听，正在播放 {{seconds}} 秒片段」（community-3.0.5 解包 payload 的 config 束内四语言齐全），上游代码以 `t('status.songPreviewPlaying', {seconds})` 请求；本 fork 的四语言包（folia-major/src/i18n/locales/*.ts）**缺失此键**，fork 的 previewNotice 已改走 songPreviewOnly，但线上 Web 更新通道/旧束请求该键时回退显键、经状态 toast 上屏。未确认——`status.songPreviewLoading` 全仓（含上游 payload、原生 Sources、folia-major、已发 WebEffect 束）无字面量，疑同族动态拼接键，无法定点定位，按同族一并兜底（不冒充已定案）。原生侧已全查：NativePlaybackFailureToast 全部 call site 均为字面中文或本地拼装文案，无原始键直出点。
- **修法（双保险）**：①语言包补键：folia-major 四语言 status 段在 songPreviewOnly 后新增 songPreviewPlaying（上游原文译法、带 {{seconds}}）＋songPreviewLoading（同族补齐：zh「当前账号仅可试听，正在加载试听片段」等四语言）；②原生兜底拦截：NativePlaybackFailureToast.show(message:) 入口加 sanitized91——形如 `status.*` 的无空格串一律映射正式文案（songPreview→「当前账号仅可试听此歌曲」、loadingSong→「正在获取歌曲链接…」、songRetrying→「连接失败，正在重试…」、songVip→「第三方播放器暂时无法获取完整 VIP 歌曲」、loginExpired→「登录状态已失效，请重新登录」、其他→「操作未完成，请稍后再试」）并落 `p91 toast key=<key>` 自证，原始键永不上屏。同类排查：fork 代码实际请求的 status.* 键与 zh-CN 语言包逐项比对（zh ⊇ en 的 90 个 status 键、缺失 0），除本键外无其他缺失。
- **文件**：WebEffectBridge.swift（原生兜底，随本分支提交）；folia-major 四语言包（独立仓库工作树改动，**不在本分支提交内**，需随下一次网页构建生效——见文末待办）。

## iOS 适配自查（逐项）

- **横竖屏双向**：点播台展开高为全应用单一出处、三宿主同改，横竖屏共用；许愿页灯宽按朝向切 216/172、floatGroup 约束居中；控制台内距/圆角两态同值；歌单 A/B 视图全幅钉边、横屏头行/架层约束同立；联动 glow/cap 按 cover.frame 逐帧/注册时落位、旋转后随 cell 重排重新注册刷新。结论：两态独立成立（代码级），旋转重排列入真机验证点。
- **安全区/灵动岛**：歌单切换钮 top=safeArea+8；许愿页钮排/灯组居中无贴边件；控制台/点播台既有安全区口径未动；Fx 浮层宿主钉满主窗但仅卡片区接点按、无新增贴边交互件。
- **系统手势不冲突**：主窗旁观 recognizer cancelsTouchesInView=false 且 shouldRecognizeSimultaneouslyWith 恒 true，不拦截、不取消任何既有手势；FxOverlayHost91 穿透式 hitTest 不吞触摸；歌单 B 架横滑与墙面纵滑方向正交。
- **深色外观**：新增面（杂志表/唱片架/许愿页/切换钮）均为深色底＋白字，与 App 既有深色口径一致；A4 chrome 渐变/边框为半透明白、深浅底均可读。
- **字号下限**：新增最小字号为拍立得歌手 9.5pt（样板等比口径、题注辅助信息）、歌单架格歌手 11pt、爱心钮字形 11pt（图形非文字）；正文类均 ≥12.5pt。
- **目标机型**：iPhone 14 Pro 基准；新增全屏视图均用约束钉边、无写死屏宽（杂志头宽取 view.bounds 实时值）。

## 与样板逐项对账（Space folia-91-yang-ban）

- 控制台视图：圆角 20 ✓、内距 12 ✓、发丝线分组 ✓（两线相对锚悬挂）、内容八项一件不少 ✓、开灯长条 200×46 沿用未动 ✓；横屏双列为样板形态——原生控制台横屏既有双列约束本轮仅同步内距，未重构（差异注明）。
- 图标视图（A4）：字形几何逐项照 gen2/gen3 ✓、双音符 180° 中心对称 ✓、钮面渐变/边框/光晕参数 ✓。
- 许愿灯视图：灯宽 216/横屏 172 ✓、floaty 5.2s ✓、fly −46% 屏高＋scale .24＋2.6s ✓、楷体落字 ✓、取消/放飞齐全 ✓。
- 拍立得视图：题注固定带 ✓、字号 11/9.5 等比 ✓、➕ 卡纸右上边缘 ✓。
- 歌单视图：顶部分段钮 ✓、A 大标题＋计数＋发丝线＋编号列表 ✓、B 头行＋横滑大封面 ✓、三套歌单头/计数/在播/➕/爱心齐全 ✓、无头像 ✓。
- 联动视图：风/雪/灯/烟花四形态数值逐项 ✓（见任务 2）；样板未定义项（风与仰头/跳跃叠加、演唱会宠物）已在取舍注明。
- 爱心视图：墙砖 24 disc/15 心 ✓、条目 18/11 ✓、#FF5973 ✓、Pulse Heart 收缩→翻色→弹簧过冲时序 ✓（收缩 .135s 至 .3、回弹 .315s 弹簧 damping .45）。

## 真机验证点清单

1. **点按根治（任务 1）**：任一特效开着 → 点控制台开关须有反应且日志有 `p91 tap zone=*`；点主页空白处控制台须消失；点孔明灯须出祝福卡且有 `p91 lamp hit`；写灯钮/推荐卡在特效开着时可点。装机首启日志应有 `p91 fxwin=pure`。
2. **联动（任务 2）**：逐个开/关风/雪/灯/烟花——砖掀动相位不一、雪檐渐厚封顶、宠物积雪抖落、灯近砖暖光衰减、宠物仰头、烟花砖闪光＋宠物跳；关后全部干净复位（无残留雪檐/暖光/倾斜）；日志有 `p91 link wind/snow/ln` 迁移行。横竖屏各验一轮。
3. **图标（任务 3）**：台面/控制台/控制台内部设置图标全为 A4 观感；控制台入口为双音符上下对称；日志有 `p91 icon=A4`。
4. **点播台（任务 4）**：展开态三行构成、进度条压最下沿、时间在框内；收起/5 秒细条行为与 (90) 一致无回归。
5. **控制台（任务 5）**：排版与样板对齐；开灯/关灯点按后墙面亮/暗切换，日志四环 `port90 light tap/toggle/setOn/apply cells=N` 齐全。
6. **许愿页（任务 6）**：写灯钮打开新页、打字实时上灯纸、键盘不挡钮、放飞升空后引擎真放飞愿望灯；横屏灯宽 172 观感。长文案（60 字）在灯纸上的溢出观感重点看。
7. **拍立得（任务 7）**：题注不溢出卡外、旋转相邻卡不叠字、➕ 不压照片。
8. **歌单三版式（任务 8）**：切换钮在三态下恒可点（z 序）；A/B 起播、在播标识、计数正确；杀 App 重进保持上次版式（持久化）；左侧缝在 A/B 下仍可点（leading 64 避缝是否够宽重点看）。
9. **爱心（任务 9）**：墙砖/杂志行/架格三处点按均翻色＋动效＋toast；与控制台/详情页喜欢状态互通（同一 LikesStore）；歌单形条目无爱心。
10. **任务 10**：试听歌（无 VIP 账号点 VIP 歌）顶部 toast 应为正式中文文案、不再露原始键；若再现原始键，日志应有 `p91 toast key=` 行可凭此定位来源键。

## 待办/移交

- folia-major 四语言包补键为独立仓库工作树改动，未随本分支提交；需主聊天决定提交/构建时机（随下一次网页构建进束后，语言包侧保险生效；原生兜底本包即生效）。
- 本分支止步线：本地提交后停手，不 push、不触发 CI（主聊天复核后统一走）。
- forensics/log-diagnosis-2026-11-24-83session.md 为既有未跟踪文件，非本包产物，未纳入提交。
