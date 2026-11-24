# (86) 交付报告

- 分支 release-86，施工提交 04f74b4b（基线 release-85 042edaad）。
- CI：run 45447577730 **success**。前两跑均为 GitHub 侧排队事故、非代码：首跑 45442195943 排队约 14 分钟无 runner、我方取消重派；第二跑 45444505439 排队 15 分钟被取消（job 的 runner 名为空、零步骤、从未启机）。第三跑立即启机、约 5 分钟构建成功。
- IPA：`build86/Folia-86.ipa`，**48,775,963 字节**。
- 验包五项全过：①体积 48,775,963B；②入场母带 md5 `8aed0fb4a5e9a0f500184f8a7dae45a9`（包内 EntryVideo/entry-v5-faststart.mp4 实测同值）；③二进制含 /api/netease、/api/qq、/api/kugou；④CFBundleVersion 实读 = 86；⑤本包新符号入二进制（见下注）。
- 注（验包⑤的编码形态说明）：wit86.live、seam86、seam86 avatar、locate86、fm86、rot86 freeze/landed/reveal、toolbar86、webfx.reload、minibar.disp86 均以字面量实查命中；tap86、console86、seam86 theme、pf86 cap= 四条日志字面量未以连续字节存在——其首段长度 ≤15 字节，Swift 小字符串内联进指令立即数、不落 cstring（原始字节 grep 同为 0，非缺失）。已用结构元数据旁证代码入包：onStationaryTap86、SeamBackdrop86、SeamThemeCycle86、expandHitView、refreshTrackWidth86、pfOutstandingKeys84、lastPf86Key、landscapeConstraints85、portraitConstraints85、cardBottom85、stageRotLaidSize86 全部命中。
- 本包未动前端（沿用既有构建产物，包内三 API 基址实查在位）。未上传文叔叔（主聊天统一发）。

## 逐项结论（代码已改，待真机验收）

### 一、缝排版按网页重做（审计三 7 处走样）
逐项对审计表打勾（出处：网页 ponderBravaisSeamGeometry.ts／PonderBravaisWallParts.tsx；原生 Seam85Views.swift）：
1. ✅ 缝纸：黑 0.34 平涂＋0.5pt 白发丝线 → rgba(22,22,27,0.8)＋黑投影（SeamBackdrop86：shadowOpacity 0.55、radius 9、offset 0，对 CSS 0 0 18px/0.55 的近似）；发丝线两条整组撤除。
2. ✅ 书库标题：11pt semibold/white 0.5/无字距 → 12pt heavy（extrabold 近似）＋kern 3.6（0.3em）＋white/85，top 0.028H。
3. ✅ 折叠钮：28×28 白 0.10 芯片 → 裸 chevron、tint white/55、无底衬（主页缝＋歌单书脊同改）。
4. ✅ 页签几何：固定 y=58/步距 60/高 54/宽 44 → top 0.118H 起、步距 0.07H、高 0.062H、宽 0.40×缝宽＝26 居中（相对比例，基准＝内容高 H）。
5. ✅ 页签选中态（配色反转纠正）：白 0.13 方块底＋白字 → **白 0.9 全圆 pill（圆角＝帧高/2）＋深色字（22,22,27）**；未选透明底＋white/62、字重 bold。
6. ✅ 中段直达：单列居中＋分隔线＋只有「我喜欢的音乐」→ **双列**（我喜欢的音乐＋云盘）、top 0.64H、white/55、删分隔线；云盘接 CloudDriveViewController（与命令面板 nav.cloud 同款 fullScreen 呈现，非死钮）。
7. ✅ 账户位与工具格：账户改 top 0.782H 区内 32 圆＋白 0.25 描边；工具格去两行两列芯片底 → 裸图标 white/70、贴底（底距 0.025H、区高 0.08H）。
- 歌单书脊同步改网页比例（BRAVAIS_SPINE_GEOMETRY）：back top 0.024H、fold 0.088H、title top 0.16H 高 0.38H、count top 0.56H 高 0.06H、play top 0.84H、expand top 0.905H；标题不再弹性拉满、计数不再随标题底漂移；play 去白 0.16 底衬改裸钮。
- 两处代偿（报告注明）：网页钮宽 0.6×缝宽≈38pt 且字形框更小，原生触控帧统一取 32 居中（back/fold/头像）；账户圆网页宽 26% 缝宽≈17pt 触控过小，沿 32pt。

### 二、缝背景油画＋长按切换、头像修占位
- ✅ 油画底：新增 SeamBackdrop86（两缝共用）——层序 缝纸→油画→scrim→内容；图源走 MiniPlayerThemeLayer.backgroundImage(for:) 单源映射（该函数由 private 改 internal，缝侧不另抄名单）；跟随 MiniPlayerTheme.effective、订阅 .foliaMiniPlayerThemeChanged 通知。
- **透明度取值**：油画 imageView alpha **0.6**、scrim 黑 **0.30**（点播台 scrim 为 0.18；缝内全是竖排小字、按可读性加深 0.12，油画本身再压 0.6——合成后底图可辨、字面可读，待真机验读感）。主题 none 时油画/scrim 同隐、只剩缝纸。
- ✅ 长按切换：两缝本体挂 UILongPressGestureRecognizer（0.55s），走 SeamThemeCycle86.cycle()——写 MiniPlayerTheme.stored.next＋发同一通知，与点播台长按同一通路、主题单源不分叉；特效总开关关时停用（同台口径）；认领即 cancelsTouchesInView、缝内控件不误触。边界：缝空域按命中纪律穿透给墙（长按落在缝内任一控件区才达识别器），空域长按不触发——与「只认控件本体」的既有纪律一致。
- ✅ 头像修占位：HomeSeam85View.setAccount85 删裸 URLSession 直下（http 明文域被 ATS 拦＋失败静默的定案断点），改 WorkbenchCover.loadAvatar 代理链（工具条同款、带缓存与防串图键）；失败落 `seam86 avatar host=home ok=0 rsn=nologin/nourl/load`、成功 ok=1，不再静默停占位（占位首字保留为未登录/加载中/失败的兜底显示，区别在失败必落痕）。

### 三、歌单页头像定位解挡
- ✅ 工具条双态门修：SeamToolbarView.hitTest 收起分支先放行头像命中区；applyToolbarState 给头像三件（按钮/图/首字）alpha 与交互双豁免——**收起态头像常驻可见可点**，3.5s 自动收回只收其余控件、头像点击不再被吞。展开态路径不变。
- ✅ 歌单缝补常驻头像：PlaylistSeam85View 书脊新增头像位（计数之下、播放之上，0.70H 起 32 圆＋白 0.25 描边，与主页缝同构成），宿主绑 locateCurrentTrack(via:"avatar")；账户数据经 SeamToolbarForwarding.applyAccountState(toSeam:) 与工具条同源回填（装配时＋viewWillAppear 各刷一次），头像图同走 loadAvatar＋seam86 见证（host=wall）。
- ✅ miss 分支对齐主页口径：WallPrototype locate miss 不再 openNativeStageFromWall 冒充定位（(81) fb=stage 改绑退役），改 toast「正在播放的歌曲不在这个歌单里」＋`locate86 result=fail why=miss`。
- ✅ 见证升级：本函数全程 locate85→locate86（via/result=none/fail why=miss/fail why=nilinst（含重飞路）/result=ok）。
- **预登记判别标准**：真机歌单页点头像（工具条收起态或缝上任一处），日志必有 `locate86 via=avatar host=wall` 行且随后 result=ok＋墙真滑（或 fail 行带 why）。

### 四、撤小白线（grabber）
- ✅ SeamToolbarView：36×4 白线 grabberView 整件撤除（装配段、2 条专属约束、layoutSubviews 两组常数改写、applyToolbarState 的 alpha 行全清）；命中垫改名 expandHitView、原位原尺寸（76×28、leading+2、绕岛态岛左近）保留、无任何可见绘制，点按落 `toolbar86 hit=expand`＋既有 seam.toolbar expand 通路。
- 展开入口口径说明：任务字面「点收起态工具条区域任意处展开」未按全带字面落地——全带（104pt 高）吞触摸会吃掉墙面顶部砖的点按与平移起手，与 (75) 起「高带不吞页面点按」的既有纪律冲突；落地为「命中区＝原 grabber 垫原位（不可见）＋头像区」，即原可点区域一分不减、只去可见线。此取舍请真机验收时确认。
- ✅ 全仓核查清单（grep grabber 全仓）：①SeamToolbarView 工具条 grabber（本项撤除，三宿主共用此类、一处清）；②SettingsViewController 设置下拉卡顶部 36×4 sheet 抓手（white 0.18）——同款小白线、纯装饰（该面板无拖动关闭、关闭走「完成」钮），一并撤除；③HomeWall 仅注释提及（已同步注释）。全仓再无其他 grabber 绘制。

### 五、横屏小白条：旋转重写轨宽
- ✅ 三宿主各加 refreshTrackWidth86(portrait:)：旋转 completion 按新 size 朝向重写 miniTrackWidthC/stageTrackWidthC（仅收起态写值），常数 218/140 不动（DeckLayout84 单源）；调用点：HomeWall completion（台宽重断言旁）、WallPrototype completion（landed 旁）、Stage completion（rot84 汇总旁）。
- ✅ fm86 恒落行：`fm86 host=homewall/wallproto/stage orient=port/land col= tw=`——横屏与 host=stage 样本自此必有（补 (84)(85) 两轮 fm84 横屏零样本缺口；fm84 本身已有 orient 字段，缺的是样本不是字段）。
- **预登记判别标准**：横屏收起态 fm86 tw=218（竖屏 140）。

### 六、双时间内收
- ✅ 三宿主双时间距台框 ±16 → **±28**，宽 40 不动：HomeWall miniTimeElapsed/Duration、WallPrototype 同名、Stage currentTimeLabel/totalTimeLabel。进度轨两端原本就锚时间标签 ±8（miniTrackLeadC/TrailC 三宿主同构），自动跟随内收、轨缩短 24pt，无其他连带。

### 七、控制台贴底＋横屏独立布局（并 00:38 追加核查）
- ✅ 贴底：card85 删 centerY、改 bottom＝safeAreaLayoutGuide.bottom −90。账：点播台展开态顶边＝安全区底 −80（台底锚 −10＋台高 70），卡底在其上 **10pt**（任务带 8–12 内）；水平居中、宽高材质功能不变；入场动画（scale 0.94＋y+10 弹簧）不变。
- ✅ 横屏定案（(85) 满宽大空卡）：根因＝内容是自上而下的固定高单列链（总高 ≈424），横屏卡高被 62% 上限压到 ≈243 后整链被 clipsToBounds 裁掉中段（队列/音量/外观/灯光行），只剩链首的清空钮与链中段的功能行露在外面；宽度又按 0.82×屏宽（852）拉成 699 的「满宽」。
- ✅ 横屏修法（独立几何，非缩放凑数）：内容约束分横/竖两套，朝向真变时整组切换并落 `console86 land=` 见证。横屏双列：左列＝队列头（清空钮归队列列右上）＋队列表（宽 0.44×卡宽、高随卡高伸缩、内部滚动）；右列＝功能行/音量行/外观行/灯光行四行竖排（总高 208）。卡宽改代码收口：竖 0.82×屏宽、横 min(0.86×屏宽, 640)；卡高：竖沿 (85) min(424, 62%屏高)、横 min(232, 贴底可用高＝屏高−安全底−90−8)。
- 数字验算（iPhone 14 Pro 横屏 852×393、安全底 21）：卡宽 640、卡高 min(232, 393−21−90−8=274)＝232；卡底 y＝393−21−90＝282、卡顶 50 > 0 不超屏；右列 16+44+16+24+18+24+20+46＝208 ≤ 232−下边距 ✓；左列队列表高＝232−12−28−2−12＝178（约 4 行）✓。
- 说明：本项按 (85) 已定版的控制台形态（毛玻璃卡、内容与功能接线）只重排几何，未引入新视觉设计；Miller 00:33 的控制台改版（模式钮合并/列表钮/烟花钮）与 00:44 样板先行令属样片线，不在本包范围。

### 八、黑屏：主页墙预取转化率
- drp 全部出口逐个查实（NativeCoverLoader.prefetch82）：①在途准入超限（drp 唯一计数出口）；②proxiedURLString 返回 nil 静默 continue（不计数）；③cachedImage 命中静默 continue（不计数）；④键集合进程级累计不分代（分母稀释，非出口但污染口径）。
- **定案缺陷（已证实）**：准入计数器 pfOutstanding84 按「次」计——同一键已在途时重复喂入仍占额度并新起合并 Task（image(for:) 内部合并、不重复取图，但额度被吃）。滚动中每 0.3s 整环重喂，24 额度被重复键迅速占满 → 新键全数 drp（118）。这就是转化率 44–46% 的直接上游；键不一致已由 (84) pixelExtent 单源基本排除（残余仅 cameraScale 时点差，量级小）；作废条件无其他出口。
- ✅ 修法：准入改按**唯一在途键**计数（pfOutstandingKeys84 按优先级分集，Task 完成移除）；重复键记 dup、不占额不起 Task；nourl/cached 出口补计数；scroll 上限 24→**40**（去重后额度只记唯一键；网络 4 槽＋解码闸 4 的硬限不变、风暴面不放大），warm 仍 8；pfDropped84 与新 cap 计数同步递增（pf84 口径不变）。
- ✅ pf86 见证：takePf86() 累计四计数（cap/dup/nourl/cached），在 WallLayout 既有 pf84 冲刷点旁落行（任一变化才落）：`pf86 cap= dup= nourl= cached=`。
- ✅ 双墙 prefetchWall83 喂入前按实例中心到视口中心距离升序排序——上限截断时先丢最远环（旧顺序与滚动方向无关、近环可能被远环挤掉）。
- 口径注记：pf84 转化率分母是进程累计唯一入队键、含跨歌单历史键，天然被稀释——下轮判读以 pf86 原因计数（增量）为主口径、pf84 为辅。
- **预登记判别标准**：真机主页墙猛滑窗 pf86 中 dup 应占大头、cap 应显著低于 (85) 的 drp=118 增量；转化率（pf84 rate）≥80% 或丢弃原因全量可指认，二者居一即达标。
- 主页墙冷砖占位（明度 0.45）未动；解码线（wall.dec84 ww=0 已结案）未动；歌单墙（hit84 已 100%）未动其通路（仅同享 loader 去重与排序）。

### 九、旋转 landed 段＋点按链复查
- 旋转治理（Stage）：✅ landed 收敛——旧法 alongside 首帧即解冻，转场期 viewDidLayoutSubviews 对每个中间 bounds 全量 layoutStage（runs=6 实根）。改：冻结保持到 completion；alongside 在冻结中以最终 bounds **单轮** layoutStage＋pushSnapshot 并记录已排几何（stageRotLaidSize86/Insets86）；completion 解冻后仅当 pending 且几何与已排不一致才补一轮（extra=1 落痕）。纯旋转常态 runs 收敛为 **1**。
- ✅ webfx 并行：nudgeEffectResize81 从 armWebRotReveal81（landed 后）提前到 alongside 转场期发（新尺寸已定）——回执在转场期内到达即由 handleWebStyleFrame 直揭，不再串行等 landed；arm 只留 0.9s 超时兜底。
- ✅ rot86 逐段见证（logSync 落盘）：`rot86 freeze gen/style/web`、`rot86 landed gen f2l= runs= extra=`、`rot86 reveal ms= via=` 三段分开。
- **预登记判别标准**：横→竖 rot86 landed f2l ≤100ms 量级且 runs=1（或 extra=1 注明）、reveal ms 不再比 landed 迟 278ms 级（应与转场时长同量级或更早）。
- ✅ webfx.reload 见证：WebEffectBridge 进程终止处理段加 `webfx.reload cnt= backoff= state=`（只加见证、重载策略一字未改），供下轮判读 gen=1 landed 缺行同源嫌疑。
- 点按链定案（(85) 日志逐行复核＋代码）：已证实——触摸真交付到 MiniBarHitView（mb.tch78 b/e 在场）；台身 collapsedTap 识别器挂在 deckSurface 叶子层，触摸命中轨/钮等其他子视图时不经其子树、永不被喂（结构性断点）；根识别器 MiniBarRootTap78 的 band 守卫与 hidden 守卫是静默 return（日志分不开没触发/静默退出）。146/180ms 干净短点、461ms 一笔、98ms 被取消一笔（救援条件 <0.35s 未覆盖）俱在窗内。
- ✅ 点按链修法：MiniBarHitView 新增静止点兜底——touchesEnded 时收起态＋未被认领＋时长 <0.5s＋位移 <10pt → onStationaryTap86 派发（宿主三家同路接 expandMiniBar/expandStageBar、落 `minibar.disp86 via=stat86`）；阈值 0.5s 覆盖实测 461ms 一笔、与台身 0.55s 长按切主题留 50ms 余量不抢长按；兜底派发后不再走 unclaimed（dead76 不误报）。expand 本身有形态守卫，与识别器/根认领重复触发不双开。
- ✅ tap86 原始落痕：MiniBarHitView 在 end 落 `tap86 host= col=1 x= y= out=claimed/stat86/moved/long`、cancel 落 out=cancel；MiniBarRootTap78 三出口补 out=band/pet/claim（坐标为台内坐标、取按下点）。
- **预登记判别标准**：收起态点细条任意处，日志有 tap86 行且 expand 闭环（minibar expand／disp86／claim78 任一随行）。

## iOS 适配自查（逐项）

- 横竖屏双向独立＋旋转重排：缝相对比例以内容高为基准、横竖同式成立；控制台横屏独立双列布局（见第七项数字验算）、竖屏单列沿 (85)；小白条轨宽旋转落定按朝向重写（第五项）；舞台旋转 runs 收敛不改变横竖几何独立口径（第九项）。控制台两态单独结论：**竖屏**——贴底锚＋单列链，卡高 min(424, 62%屏高)，底距台顶 10pt；**横屏**——贴底锚同式成立，双列全行显示可操作，卡 640×232 不超屏（见证 console86 land= 待真机落行确认）。
- 安全区/灵动岛避让：控制台卡底锚安全区底 −90（台展开顶之上），横屏安全底 21 已入验算；缝头像常驻位于工具条行带内（主页 flatRowTop 30 下移行心 67、头像上沿 51 与岛底 48 拉开 3pt——沿 (78) 既有几何、本包未改行位）；工具条展开垫绕岛态仍落岛左近。
- 系统手势不冲突：缝长按 0.55s 与点播台长按切主题同值同通路，认领取消触摸、不与缝内控件点按/墙面平移冲突（空域穿透不变）；工具条头像放行只加一个 32pt 命中区，不吞带；tap86 兜底阈值与台身长按（0.55s）留 50ms 余量。
- 深色外观与字号下限：缝选中态深字（22,22,27）压白 0.9 pill、对比充足；未选 white/62 于油画＋scrim 之上待真机验读；页签 13pt bold、直达 11pt、计数 11pt 沿既有下限未降。
- 目标机型（iPhone 14 Pro）：全部数字验算按 393×852／852×393、安全底 34/21 核算（控制台横屏、缝比例、轨宽 218/140）。
- 动画口径：本包未新加动画；控制台入场弹簧、工具条双态弹簧、缝开口补间均沿既有系统弹簧，未引入线性/跳变。

## 基线纪律核对
(85) 已过项未动：台弹出通路（仅新增兜底派发、expand 本体未改）、关灯放大、台高 70、竖屏小白条 140（常数未动）、控制台毛玻璃材质与功能接线（仅约束重排）。内存硬线未触（预取上限是准入计数口径、网络/解码双闸 4+4 不变）。新面包屑名均 ≤15 字节（seam86/locate86/fm86/pf86/rot86/tap86/toolbar86/console86/webfx.reload/wit86.live/minibar.disp86）。

## 待真机验收清单（按预登记判别标准）
1. 歌单页点头像（工具条收起态＋缝头像各一次）→ locate86 行＋墙真滑。
2. 横屏收起细条 → fm86 host=stage/wallproto/homewall orient=land tw=218。
3. 主页墙猛滑数窗 → pf86 计数构成＋pf84 rate。
4. 舞台横→竖旋转（网页特效样式）→ rot86 三段毫秒。
5. 收起态点细条多处（轨中央/钮区/边缘）→ tap86 行＋展开闭环。
6. 控制台横/竖各开一次 → console86 land= 行＋横屏双列全行可见可点；卡底距台顶约 10pt。
7. 缝：油画底跟随主题、长按缝 0.55s 循环 4 套＋none、头像真图（seam86 avatar ok=1）、选中 pill 白底深字、工具条无小白线＋原垫位点按展开（toolbar86 hit=expand）。
