# (68) 交付报告：播放面状态包 A 组＋全宽控制条出样 B 组

- 分支：release-68（基线 release-67/2e42c958）；功能提交 543cc27e。
- 版本：CFBundleVersion=68（project.yml），短版本 3.7。
- CI：run 44902976416，结论 success（首轮一次成功，head 543cc27e）；IPA 48,477,170 字节。
- 范围依据：borrow-plan-2026-11-21.md 与 ds-review-2026-11-21-borrow-reconcile.md 定稿分期——(68) 播放面状态包主体为 P4 状态强可视化；P8 全宽控制条经 Miller 20:08 拍板「出一版对比用」同包出样。
- **范围说明（如实项）**：对账定稿的 (68) 另含 P7 时间轴偏移页内直调与 P9 已在队列角标，本包任务书未点名，未施工，仍挂 (68) 定稿账，待主聊天/Miller 定是否补包。

## A 组·状态强可视化（P4，DS 排序第一）

### A1 喜欢整钮变色填充
已喜欢态由「描边心变色」改为「整钮填充喜欢色（1, 0.35, 0.45）＋白色实心心」，未喜欢态逐项维持现行。落点四处（播放面凡有喜欢钮处）：
- 舞台顶栏喜欢钮（StageViewController.refreshLikeButton）：钮体加圆角 19 成圆钮，已喜欢填色＋白心；未喜欢白描边心、无填充（原状）。
- 迷你台快捷排喜欢钮（MiniBarQuickRowView）：填充由 configurationUpdateHandler 统一裁决（高亮白 14% 优先、其次喜欢填充），refreshLike 先落 likeFilled 标志再写回 configuration，防写回冲掉填充；填充后图标与标签转白保可读。
- SwiftUI 迷你台喜欢钮（MiniPlayerView）：44×44 钮加圆角 12 填充背景，白心；未喜欢维持白 75% 无填充。
- 墙面展开卡喜欢钮（WallPosterCell.setLiked）：已喜欢填充喜欢色（alpha 0.95）＋白心；未喜欢维持黑 45% 底＋白描边心。
口径：只改状态呈现，LikesStore 真源、乐观切换、云端同步、失败回滚等功能语义与落点零改动。

### A2 音量百分比回显
落点：播放面板（PlaybackPanelViewController）控制页签音量行——全仓唯一的原生音量滑杆（AVPlayer 本级音量）。
- 滑杆右侧加百分比标签（等宽数字 13pt、宽 46、右对齐）：拖动时随 .valueChanged 实时刷新；静置显示当前值；外部改量（命令面板 ±10% 等）经既有 engine.$volume 订阅同步滑杆与标签（拖动中订阅不打架的既有 isTracking 守卫保留）。
- 设置面里的 MPVolumeView 为系统音量视图（系统接管、无自有滑杆语义），不在本项范围。

### A3 主题名回显
落点：播放面板控制页签新增「主题」行，直显当前主题名。
- 数据源：ThemeSystem62 新增 currentDisplayName（与 currentSourceLabel 同源解析：歌曲主题生效→「歌曲主题」；其余→所选预设名 午夜紫/深海蓝/余烬橙/森野绿/暮玫瑰 或「自定义」）。
- 刷新：订阅 .foliaTheme62Changed（预设切换/歌曲主题生成/恢复默认都发此通知），面板开着切主题即时刷新；面板每次新开构建时读当前值。
- 落点取舍：未挂舞台顶栏——顶栏是 5 秒自动隐藏组（回显会被藏掉）且与样式胶囊同排拥挤；未动迷你台（定版几何）。播放面板是常开可达的播放面，与 A2 同面成组。

## B 组·舞台全宽控制条出样（P8，Miller 点名对比用）
- 本体：新文件 Sources/Native/Features/Stage/StageWideBar68.swift（单文件自包含）。
- 形态：一行全宽——上一首/播放暂停/下一首＋已播时间＋进度滑杆＋总时长；深色毛玻璃底＋顶发丝线；贴底全宽，内容行高 64pt＋底部安全区填充。
- 唤出/自隐：开关开时，在舞台渲染区点屏唤出（识别器与三击同挂 rendererContainer——点播台/顶栏/提示条是其兄弟视图，从它们起的手势天然不触发，与三击识别区纪律同构；cancelsTouchesInView=false 不拦截渲染器触摸）；已可见时点屏只续命；闲置 5 秒自隐（与顶栏/迷你台 chrome 纪律同值）；条上按钮/滑杆交互均续命。
- 开关：设置「播放页 → 控制栏」组新增「全宽控制条出样」开关＋说明行；键 settings.player.wideBar68Enabled（SettingsStore.wideBar68Enabled，缺省关）。键→消费者→生效路径：开关行 post 通知 → StageVC.settings62AChanged/viewWillAppear 的 syncWideBar68 → 识别器启停＋关时条立即收起。关时：识别器 disabled、条恒隐藏、离台 hideNow，舞台行为与现行逐项一致。
- 并存与摘除：不迁移、不废弃现行点播台/顶栏任何控制；唤出时全宽条浮压底部盖住点播台所在带，自隐后点播台原样露出。命令落点全走既有通路（handleCommand 的 toggle/prev/next、performSeek），进度喂入同源 setStageProgress 的 fraction（不另起进度源、不可见时零开销）。摘除面：删 StageWideBar68.swift＋StageVC 五处钩子（属性/installWideBar68+sync+点屏 action/viewWillAppear+settings62AChanged 各一行/setStageProgress 喂入/layoutStage 定帧/viewWillDisappear 收起）＋SettingsStore62A 一键＋设置面两行。
- 面包屑（均 ≤15 字节）：widebar.set（开关切换，设置面落）、widebar.show（唤出）、widebar.hide（闲置自隐）。
- DS 顾虑「第二套 chrome」的处理：缺省关＋并存可比＋可整体摘除，不达标（Miller 真机对比不选）即整组删除，不留半截。

## 未施工/未确认（如实）
- P7 时间轴偏移页内直调、P9 已在队列角标：对账定稿属 (68)，本包任务书未点名，未做（见卷首范围说明）。
- 本包未碰：取流、歌词呈现、特效链、(67) 网页嵌入面、(66) 设置 IA 分组/顺序（只在既有「控制栏」组内加行）。

## 自检口径
- 代码级：四处喜欢钮填充均走既有 refresh 出口（切歌/外部切换/失败回滚都经同一出口，不存在第二状态源）；音量标签三路刷新（构建初值/拖动/外部订阅）同出口 refreshVolumeLabel；主题名两路刷新（构建初值/通知）同出口 refreshThemeName。
- 设置自检：新开关行走既有 switchRow/addRow 工厂，与邻行同构，纳入设置页逐签量测（零高判死）范围；消费者真实存在（StageVC.syncWideBar68），非假生效。
- 二进制实存校验（验包节回填）：widebar.set / widebar.show / widebar.hide 字面、build=68、贴纸数、入场母带 md5。

## iOS 适配自查
- 横竖屏双向：全宽条帧在 layoutStage 按 bounds 全幅定帧（宽随屏宽、行高恒 64＋安全区），横屏独立成立（横屏安全区 bottom 为 0 时填充自动为 0、内容行不沉底）；A 组均为既有面内呈现变更，无新几何。
- 安全区/灵动岛：条贴底填充吃 safe.bottom，内容行不被 home indicator 压；顶发丝线与毛玻璃为条内元素，不涉灵动岛。
- 系统手势不冲突：点屏识别器 cancelsTouchesInView=false 且只挂 rendererContainer，与三击切样式、双击顶栏恢复、顶栏 tapObserver 并存（点屏唤出与顶栏顺延可同触发生，互不取消）；不新增边缘/下拉手势。
- 深色外观：条与面板行均按舞台深色 chrome 口径（深色毛玻璃、白字），与既有面一致；喜欢填充色在深浅底（墙卡图片底）上以 0.95 不透明度保可读。
- 字号下限：条时间标签 12pt 等宽（辅助读数，与点播台时间标签同级）、主题名 15pt、音量百分比 13pt，均不低于既有同级元素。
- 目标机型 iPhone 14 Pro：条全宽 393pt 时一行元素合计固定宽 266pt＋滑杆弹性，两侧 12 内缩后滑杆仍有正宽；更窄屏（320pt）滑杆约 54pt 仍可拖。

## 验包结果（主聊天复验前为施工方流式自验）
- CI run 44902976416 success；IPA 48,477,170 字节，md5 f0bf8143b18553d8286d67cbe5643b68。
- build=68 / 短版本 3.7 ✓（Info.plist 实读）。
- 贴纸 53 只 ✓（cat/dog/cat-live 去重计数）。
- 入场母带 md5 `8aed0fb4a5e9a0f500184f8a7dae45a9`，与 (59) 重制母带逐位一致 ✓。
- WebEffect 包内文件 1,949 个，与 (67) 同数——(67) 嵌入面未动 ✓。
- B 组宿主符号实存：StageWideBar68 的 show/hide/hideNow/poke/update/playTapped/prevTapped/build/setPlayIcon 等方法符号与源文件路径（Folia/StageWideBar68.swift）均在出厂二进制内；设置键 settings.player.wideBar68Enabled 字面实存。
- **未确认一项（如实标注）**：widebar.set / widebar.show / widebar.hide 三个面包屑字面未能以明文字节在出厂二进制中检出（宿主函数符号全在）。与 (67) 的 sync.snd/sync.snd0/tick.pos 现象同型——三者均为 ≤15 字节短字面，疑为编译器小字符串编码（字节不以连续明文落盘）。真机判读以桥日志是否实际出现这三行为准：设置里拨开关应见 widebar.set、舞台点屏唤出应见 widebar.show、闲置 5 秒应见 widebar.hide；若真机日志不见，再定级处理。
