# (99) 交付报告 — Folia/Virelai

- 分支 release-99（自 release-98 切出），提交 724da5b5；CI run 46044814960 success（build 3m8s）。
- IPA：`~/workspace/folia-deploy/build99/Folia-unsigned.ipa`，**61,424,833 字节**。
- 验包（解包实测）：CFBundleVersion=**99**、CFBundleDisplayName=**Virelai**、CFBundleShortVersionString=3.7；WebEffect chunk（providerRegistry）含 `/api/netease`、`/api/qq`、`/api/kugou` 三项；烟花素材 md5=`f2d21741f1406434da9b1e34f3ac6d42`（v4 原文件，本包未动烟花素材与呈现路径）；Diary 资源入包（diary-opening.mp4 3,507,739 字节、md5 与 design-samples-98 v4 一致；贴纸 37 张）；二进制内 p99 面包屑字符串在位（`folia.xmas99.vflip` 键亦在位；`p99 xmas vfl v=`、`p99 xmas fp mb=` 两条字面恰 15 字节、走 Swift 小字符串内联存储、不出现在字符串表，源码与键已双证）。
- 文叔叔（主链，接收侧验收通过）：**https://c.wss.ink/f/rvkay1m05bd** — 脚本全新会话复核 file_count=1、file_size=61,424,833 精确一致；**2026-11-29 01:54:04 CST 自动销毁**，须提醒 Miller 立即取件。
- muse.ai 备用链：**未完成** — remote-storage 上传的出口审批超时（approval_expired），按规矩未重试；IPA 已在本地 build99/ 备好，父代理/Miller 点一次审批即可补传。
- 真机行为一律未验：以下每项的「效果」都须 Miller 装机后按 p99 面包屑判读，本报告只证代码与包体。

## 逐项

### 1. 圣诞树（二分开关＋分池＋内存）
- v 翻转二分：`XmasMetalRenderer97.vflip99` 读键 `folia.xmas99.vflip`（默认关）；开启时在 UV 矩形生成处做 v′=1−v（minY′=1−maxY），采样层其余不动。设置页新增「圣诞树纹理 v 翻转」开关（关/开），切换即写键并落痕。自证：装配时 `p99 xmas vfl v=<0|1>`、设置切换 `p99 xmas vfl v=<0|1> src=set`。
- 分池计数：buildFrame 每帧按池统计实际 append 成功数（非分配数），随 spr 节奏落 `p99 xmas pool lyric= tree= garland= snow= tot= rgba=<歌词粒0号CPU侧tint>`——rgba 只证 CPU 侧给色（GPU 读回无通路），用来与真机画面区分 v 错位 vs 颜色错。
- 内存（目标 ≤450MB）：①图集改逐精灵分块上传，取消整幅 CPU 暂存（旧 ≈15.7MB 与纹理本体同量级、装配峰值翻倍）；②歌词采样离屏图 scale 3→1（13.0MB→1.4MB/行，归一化采样网格逐点等价、点数不变）；③退出走 `releaseAll99()`（图集＋实例/三角缓冲＋管线＋命令队列全释放，旧 unmount 只放图集）＋帧数组真清空。自证：`p99 xmas fp mb=<footprint> ev=on|off`。
- 未验/保留：(98) 日志里关圣诞树后 footprint 仍 ≈650MB，残留层未定位；本轮三项措施压的是装配峰值与退出残留，**是否回到 ≤450MB 须看 (99) 日志的 fp on/off 读数**，未达再按读数追下一层。不许关特效内容的约束已守（池规模未降）。

### 2. 排版黑屏
- 施工中坐实更上游的根因（代码实证）：`magazineTable91.delegate = self` 且宿主 `scrollViewDidScroll` 不分 scrollView——滚歌单杂志表时，表的 offset 增量被折进墙 worldOrigin 并回弹成反馈环（与 (98) 日志的 rebase 环＋origin 单向飞出同构）。已加 scrollView 身份守卫（didScroll＋WillBeginDragging 两处，非墙面滚动面直接 return）。
- 原子对齐：`WallLayout.settleAnchor99()`——补切落点在同一同步点先把 worldOrigin 钳回当前布局包围盒、再提交布局（p94EndWallSwitch 头部 src=switch、apply 互换路径 src=apply、两处 redo 落点 src=redo），落 `p99 lay settle src=`。
- 熔断双保险：单事件 |delta|>400pt 钳制（`p99 lay fuse ev=delta`）；|origin| 任一轴 >1e6 硬钳回包围盒（`p99 lay fuse ev=origin`）。
- 进页空窗：两处 redo 落点落 `p99 lay wait ms=<登记→补切毫秒>`，pend 登记时刻在 switch/apply 两入口即写——补切实际耗时下版日志可判。
- 未验：真机滚动是否还黑屏、wait 毫秒数，待 (99) 日志。

### 3. 播放台
- ①单实例：新增 `MiniBarArbiter99`（Player/）：三宿主 viewDidAppear 时 claim、各自形态收口尾 enforce 复断言；任一时刻只许最后 claim 的宿主台可见，其余整台 isHidden（只恢复仲裁自己隐藏过的台，不干预舞台 hideBottomBar 设置）。自证：状态真变化时 `p99 deck vis act=<host> hid=<清单>`。
- ②收起条几何：核查实证三宿主收起宽已共用 DeckLayout84（竖 140/横 218）；本轮把三宿主收起高/圆角的字面量（5/2.5）收敛为 DeckLayout82 单一常量（collapsedTrackHeight/collapsedCornerRadius），杜绝再分叉。(98) 日志里的「两种几何」实为同台的收起形态（140×5）与展开台内轨道两条 fm84 记录；屏底第二条的成因是跨宿主同屏可见，由①消除。附带发现：fm84 面包屑展开态叙述 th=4/r=2 与实际常量（高 3）不符，属旧写死文本、本轮未动（不影响几何）。
- ③圆点恢复：回退真凶坐实＝(95) 的 `miniKnobFlower95/stageKnobFlower95`（DeckGlyph82.flowerImage 白瓣琥珀心）——恒在场、且 refresh 时被 bringSubviewToFront/守卫重挂压住逐主题皮肤。三宿主整套摘除（创建＋属性＋守卫/提顶共 9 处，摘后全仓 KnobFlower95 引用为 0）；皮肤工厂 `MiniPlayerThemeLayer.knobSkinView`（meadow 雏菊/snow 雪花/star 金星点/ocean 波纹/none 白发光点兜底）原本完好，摘除后逐主题圆点即恢复。
- 未验：三宿主切换时是否只剩一份台、圆点逐主题观感，待真机。

### 4. 旋转交接帧
- 冻结版：盖建立时落自证 `p99 rot cov w=<px> h=<px> dt=<抓拍延时ms>`；网页 buffer 到目标尺寸（resized 信号）且盖仍在场时，`p99SwapRotCover()` 按目标 bounds 重抓一帧换盖图（`p99 rot cov sw=1 w= h= dt=`）——揭盖前盖面即目标构图，不再是旋转前构图的拉伸。
- 活版：注入 harness 的 verifyBuffer 自派发 resize 加尺寸稳定性门（视口尺寸连续 ≥2 帧不变才许派发）——旋转中途的混合尺寸拍（新宽×旧高，如 852×852→2556×2556）不再催渲染器按中间尺寸重建；回执新增 sq 标记（buffer 方形而视口非方形），`p94 web … sq=` 与 `p98 rot buf … sq=` 同步落盘。
- 未验/保留：若方形帧是网页渲染器响应原生 resize 事件自发产生（而非 harness 自派发催出来的），稳定性门不能全灭——(99) 日志看 sq 是否还出现即可定性，两种方式都保留、未做选型删除（遵任务书）。

### 5. 搜索页（SearchWorkspaceView.swift）
- 平台 pills 整行删除；平台切换收进搜索框旁紧凑菜单 `providerMenu99`（切换落 `p99 search prov`，恰 15 字节；p98 search 五处自证保留）。
- 背景改毛玻璃：ultraThinMaterial 上纸色层不透明度 0.94→0.55。
- 展开压卡：根因＝LazyVStack 展开时不重排；songColumns/collectionColumns 改普通 VStack，展开卡倾斜角回正、布局让位不压邻卡。
- 横屏顶部占用 ≈260pt→162pt。
- 未验：VStack 长列表滚动性能、毛玻璃 0.55 观感，待真机。

### 6. 二维码（Seam85Views.swift；ProviderLoginTransport 零改动）
- 预生成：沿用最早触发点（SeamMaster 构建时）把默认平台整码提前备好（不止 key），命中落 `p99 qr pre prov= hit=1 ms=0`、未命中 `hit=0 ms=<实测>`。
- 静默续期：15 秒 tick 的续期计时器在码到期前主动重生成，落 `p99 qr ren prov= age=<旧码龄>`；60 秒尝试间隔防打爆服务端 create。
- 未验：进缝开码是否秒开、续期是否无感，待真机＋(99) 日志。

### 7. 日记本 P0 试用版（新模块 Sources/Native/Features/Diary/＋Resources/Diary/）
- 入口：主页中缝日记钮改指新版 DiaryBookViewController99（旧 DiaryViewController90 保留供控制台/拍立得旧入口）。
- 开场：包内 diary-opening.mp4（与已交付 v4 逐字节一致），播完/点按跳过进日记。
- 隐私锁：LocalAuthentication 解锁面（`p99 diary lock`）；今日听歌自动草稿（待确认式，`p99 diary confirm`）；记一笔自动带入当前播放歌名/歌手/封面/时间；时间轴＋日历视图；按歌曲聚合；Fluent 3D 贴纸 37 张（样板同批素材，folder reference 入包）；打印机打印动画＋导出图片（`p99 diary export`）；本地持久化 Documents/folia-diary99.json（整表 JSON 原子写）＋回收站＋编辑器自动保存（`p99 diary save`）。
- 形态：竖屏单页/横屏双页书形态（按已审样板）。
- 未验：全部交互真机未验（试用版口径）；人脸锁失败回退、草稿数据口径待 Miller 试用反馈。

## iOS 适配自查（代码级；真机行为未验）
- 横竖屏双向：搜索页横屏顶高已压（260→162pt）；日记本竖单页/横双页双形态在码；仲裁与宿主朝向无关；圣诞树/旋转改动不挑朝向。
- 安全区/灵动岛：本包未新增全屏覆层与常驻浮层（日记本为既有 present 全屏模式、沿用宿主安全区口径）；播放台几何常量未动（高 84/收起 16、底距口径不变）。
- 系统手势：未新增与边缘返回/下拉关闭冲突的手势；仲裁只切 isHidden、不拦触摸；搜索页菜单为系统 Menu。
- 深色外观：搜索页背景走 ultraThinMaterial（自适应材质）＋纸色层降不透明；日记本书页配色按样板暖纸系、非系统深色面（样板已审口径）。
- 目标机型（iPhone 14 Pro）：收起条宽 140/218、胶囊 84 等既有常量未改；方形中间态治理正是针对 852pt 级混合尺寸拍。
- 结论：清单逐项在代码层成立；横竖屏观感、毛玻璃、书页翻页手感须真机复核，未验不算过。

## 交付物
- IPA：~/workspace/folia-deploy/build99/Folia-unsigned.ipa（61,424,833 字节，CFBundleVersion=99）
- 文叔叔：https://c.wss.ink/f/rvkay1m05bd（2026-11-29 01:54:04 CST 销毁，接收侧已验收）
- muse.ai 备用链：未生成（审批超时，待补传）
- 本报告：~/workspace/folia-deploy/forensics/delivery-99-report.md（按任务书路径；(98) 报告存于 ios-shell/forensics/，两处口径不同，特此注明）
