# (98) 交付报告 — Virelai iOS

- 分支：release-98（自 release-97 切出）
- 代码提交：02325f27（第 7/8 项）＋ 50dee896（注释清理）；第 1–6 项与版本号在更早的 (98) 提交内
- CI：GitHub Actions build-ipa.yml run 46028339900，head 50dee896，结论 success
- IPA：build98/Folia-unsigned.ipa，56,283,529 字节（workspace/folia-deploy/build98/）
- 验包：CFBundleVersion = 98 ✓；CFBundleDisplayName = Virelai ✓；包内 FxMedia/vangogh-fireworks.mp4 md5 = f2d21741f1406434da9b1e34f3ac6d42 ✓（与 v4 原文件定案一致）；包内 WebEffect chunk（assets/providerRegistry-CoF9Kiv0.js）含 /api/netease、/api/qq、/api/kugou 三项 ✓；二进制结构旁证：folia.rot98.mode、p98 rot coal pend=、p98 layout redo mode=、p98 qr seg prov=、p98 search dbl id=、pendingLayoutMode98 等长字面量/符号均在编译产物中命中（短面包屑名因 Swift 小字符串内联 grep 为 0 属已知现象，不作缺失判读）
- 网页 bundle：本包未改 folia-major 源码，Resources/WebEffect 为既有提交产物、未重构建；三项 API base 已在仓库与 IPA 两处验齐（见上）

## 逐项落码对照表

### 1. 圣诞树内容恢复
- 图集字节序定点修正：ChristmasMetal97.swift:192/201 —— 位图上下文改 premultipliedFirst | byteOrder32Little，对齐 .bgra8Unorm（旧 Last|32Big 实产 RGBA、与声明互换 R/B，金星因此呈蓝）
- 自证面包屑：p98 xmas spr（ChristmasTreeStageRenderer.swift:245，随 fps 行带 n=/tri=，数据源 ChristmasMetal97.swift:120-121/284-285）；p98 xmas uv（ChristmasMetal97.swift:225，atlasH＋下标 13 金星 uv）；p98 xmas notex（:288）；buildFrame 早退两条原因 p98 xmas guard sprites=/treePos=0（ChristmasTreeStageRenderer.swift:608/612）
- **未动/未验**：v 轴行序翻转按定案只作真机二分验证步，本包未改；须 Miller 真机看 spr n>0 且画面内容后，再决定是否翻 v

### 2. 烟花主页叠加
- 素材：包内已验 md5 = v4 原文件（见上）
- 根因：AVPlayerLayer 的 screenBlendMode 合成只在同窗内成立，视频层原挂独立 FxPassthroughWindow96（level 1500），黑底在该窗内合成为不透明黑 = 全屏黑页
- 修法：GlobalFx87.swift:662 relocateVg98IfNeeded() 把 VangoghFwView97 迁入主窗层级（frame=主窗 bounds、autoresizing），在挂载（:709）与 setFw 开启路径（:1216）各调一次，落 p98 vgfw host=main
- **未验**：透明叠加效果、关控制台留主页、再点当帧关、覆层点按放行，均须真机验（沙箱无真机）

### 3. 排版切换修通
- WallPrototypeViewController.swift:157 pendingLayoutMode98 登记旗；apply 空 entries 只装配不互换并落 p98 layout pend（:5985）；switch 回滚分支删除改写持久化键 foliaPlaylistLayout91 的代码、改登记 pending；visible==0 且 entries 空时不 crossfade 到空视图
- 落点补切：种子/分页落点 reload 后补切并落 p98 layout redo mode=/vis=（:3166-3173、:3272-3279）

### 4. 胶囊台 72→84
- 唯一常量：MiniBarQuickRowView.swift:89 expandedBarHeight 72→84
- 圆角 9 处（HomeWall 3 / WallPrototype 3 / Stage 3）统一改 expandedBarHeight / 2 派生
- 写死假面包屑 p95 deck capsule h=62 已删尽，三宿主改实测插值 p98 deck cap h=… host=home/wall/stage（HomeWallViewController.swift:1855、WallPrototypeViewController.swift:1190、StageViewController.swift:3739）

### 5. 封面爱心最右下角
- 墙面：WallPrototypeViewController.swift:5112-5117 heartY 两档统一底锚 bounds.height − 30，标题/副行 label 宽 −12→−42（右让 30）
- 书架：爱心 y 124→126 对齐，:6688 落 p98 heart pos host=shelf（实测内距 r=/b=）
- 舞台：本就没有封面爱心（只有顶栏喜欢钮），无对象可移——如实标注

### 6. 二维码加速
- Seam85Views.swift:478 起：channels 会话缓存 qrChannels98（进程内复用）；key 预取缓存 TTL 120s（QQ unikey 本身 180s 有效，留 60s 余量——与任务书 180s 的出入在此如实标注，代码注释 :475 同口径）；双槽 qrSlot98（有效窗 QQ 160s / 酷狗 285s）切回续轮询、不再无条件清缓存
- init 预取默认平台 key＋预热另一家（:499 prefetchQRKeys98）；QQ 链路砍 channels 串行跳：缺省直发 key、缓存缺席后台补探测、fetchKey 失败才探测 channels 换通道重试一次（:1195-1211）
- 计时面包屑：p98 qr seg prov=/stage=/ms=/node=（:487）、p98 qr total prov=/ms=/cache=（:493）；节点序由 ProviderLoginTransport.swift:59/101 lastNodeIndex98 记录

### 7. 搜索页整批
- SearchWorkspaceView.swift：时长单行定宽 46（lineLimit 1，禁竖排）；星标删除，语义统一为爱心=我喜欢（LikesStore 唯一真源，:586）＋＋=收藏到歌单＋便签=进日记本；封面右下毛玻璃播放角标（原 MV/已下架标签移右上让位）
- 单击卡内展开详情（:621，expandedId98 :104）：大播放钮（起播后回墙、由 84 胶囊台承接）＋收藏到歌单/进日记本/我喜欢三动作；双击进详情播放页（:680，起播＋openFullPlayer＋收搜索页）；单击/双击/展开/喜欢面包屑 p98 search exp/dbl/play/like
- 状态行去掉「（D5）」内部代号
- **未验**：双击后全屏播放页与搜索页收起的时序、展开动画手感，须真机验

### 8. 旋转根治第一步（DS 对账定案）
- 删四齐门：p94RotMaybeRelease / p94RotFrameTick / p94RotArmSafety / armWebRotReveal81 全部删除；正常路径唯一释放点 = landed 结算 p98RotReleaseAtLanded（StageViewController.swift:1165，completion :1074 调用）
- 冻结拍并行重建：viewWillTransition 冻结拍即把 WebView 帧设为目标尺寸＋prepareRotationResize94＋nudgeEffectResize81（:1003 起）；桥侧 nudge 0.12s 防抖摘除（即刻派发）；JS 侧 120ms 静默合并窗归零（同拍连发仍合并为一记，下一拍即跑链）
- 盖换全分辨率：快照宽恢复全宽（:1228 落 p98 rot cap w=），摘除 (92) 半宽降采样
- 异常有界兜底：landed 时 stage.ready 未到则进 ≤400ms 有界等待——ready 先到经信号/首帧回执揭（via=hold98）、超时强揭（via=cap98）；ready 已到即揭（via=landed98）；落 p98 rot rel dt=/rdy=
- 死锁判读面包屑：JS 新增 pend/rst/rty/sup 字段；原生落 p98 rot coal pend=/rst=/sup=（WebEffectBridge p94Web 处理）、p98 rot buf exp=/act=/dpr=/rty=（stageResizeDone 处理，exp=clientW×DPR）、p98 rot sig k=/dt=（信号到达时刻）
- 盲测开关：设置页外观组新增「舞台旋转转场」分段二选一（方式一/方式二，不标注优劣；SettingsViewController.swift:106/542/1079，键 folia.rot98.mode，方式一=freeze 全分辨率冻帧、方式二=live 无盖实时渲染）；每次旋转舞台落 p98 rot mode v= 自证实选方式
- petconcert 未做两段式可见几何（按 DS Q8 采纳结论）

## iOS 适配自查

- 横竖屏双向＋旋转重排：本包核心即旋转管线重做（第 8 项）；搜索卡展开、84 胶囊、爱心底锚均为尺寸无关的相对布局；横竖两态的代码路径成立，**真机旋转手感与盲测结论待 Miller 实测**
- 安全区/灵动岛/状态栏：本包未新增全屏覆层；烟花视图迁入主窗后 frame=主窗 bounds（与原独立窗同为全屏口径，不新增遮挡面）；搜索展开区在卡内流式布局、不压系统件
- 系统手势：未新增手势；搜索页单击/双击为 SwiftUI 标准 onTapGesture(count:) 消歧，长按多选与左缘返回（EdgeBack76）未动；舞台三击/长按识别器未动
- 深色外观与字号下限：新增文本最小 11pt（搜索展开动作标签、播放角标）；设置页新行沿用 FoliaUI 既有色板与 15pt 行标题；搜索爱心选中色 #C8102E 与既有口径一致
- 目标机型 iPhone 14 Pro：全分辨率旋转盖的快照内存为单张全屏位图（转场期短命、用后即释），在全应用峰值 ≤450MB 硬线内；其余各项无新增常驻内存

## 未落/未验清单（如实）

- 全部 8 项均为代码落码＋CI 编译通过＋包内静态验包；**真机行为一律未验**（本施工方无真机）：圣诞树内容是否恢复（看 p98 xmas spr）、烟花叠加是否透明贴墙、排版补切是否生效、二维码提速幅度（看 p98 qr seg/total）、搜索展开/双击时序、旋转揭盖时延与盲测两方式差异（看 p98 rot rel/sig/coal/buf）
- v 轴翻转未动（定案的真机二分步）
- 花雨特效（23:47 新定、顶替孔明灯位）不在本包范围：样板未审，按样板先行不进原生
