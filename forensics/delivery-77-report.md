# 3.7 (77) 交付报告

基线 release-76 → 分支 release-77，包内 CFBundleVersion 76 → 77（app＋widget 双 target）。
范围：Miller (76) 真机初验未过/新报八项＋⑧细则（23:01）＋⑨（23:02）＋⑩（23:12/23:14）＋(76) 会话日志转交三条（⑥改靶/开关审计/tap76 补点）＋⑧录屏触发源（23:18）。无范围外改动。

- CI：run 45207757172（head ab959857）success。注：首跑 45204855283 排队约 13 分钟后 job 被平台取消（零 steps、从未上 runner，非代码问题），二次触发即一次编译通过——「CI 一次过」按编译口径成立、排队取消如实记于此。
- IPA：Folia-3.7-77-unsigned.ipa，48,592,906 字节。
- 验包（已核）：CFBundleVersion=77（app 与 FoliaWidgets.appex 双 target 均 77）、CFBundleShortVersionString=3.7、FoliaWidgets.appex 在位、NSSupportsLiveActivities=true。
- 下载：见交付消息（文叔叔为主通道、muse.ai 备用，按 Miller (76) 后定版口径）。

三档口径：本报告所有「已落」= 代码已改；「验包过」只指包内版本号/appex 核对；功能是否成立一律以 Miller 真机验收为准，未真机验过的不写已修好。

---

## ① 设置台展开面全透明（代码已改，待真机）

- SeamToolbarView：带身三件（毛玻璃 blurView／主题着色 bandTintView／描边 borderView）改为只在收起绕岛态以贴岛薄框存在（alpha 1）；展开态与非绕岛平形态三件恒 alpha 0——头像/分段/搜索/齿轮/灯泡/Lattice/全屏等控件直接浮在墙面上，无面板背景、无边框。Miller 图2 里的大块深色圆角面板即此三件，本版整件摘除其展开态呈现。
- 形变保留 iOS 系统弹簧（0.45s、damping 0.8）；命中纪律不变：展开只认控件本体、收起只认 76×28 抓手垫，控件之外恒穿透（hitTest 既有实现未动）。
- 副作用交代：展开态无底后，控件自带的 0.88 黑底小药丸成为唯一衬托（(74) 既有样式，未动）。

## ② 歌曲条融合与配色（代码已改，待真机）

落位（三宿主同构）：
- 底锚改为存引用、按形态切换：展开 −10（相对 safeArea.bottom，与 (75) 台让位几何不变）；收起 +31.5。几何账：安全区底 34pt；home indicator 134×5、底边距屏底约 8pt、其中心在屏底上方约 10.5pt；收起轨道中心＝台底 −8（台高 16、轨底 −5.5、轨高 5）。C＝34−10.5+8＝+31.5 时轨道中心与 indicator 中心重合、轨道（5pt 高）与 indicator（5pt 高）同带——图4 的「两条白线并存」在本版合成为同一条线。无 indicator 机型（安全区底 0）回落 −10 不切。viewSafeAreaInsetsDidChange 三宿主均重落。宠物层按 bar.frame/presentation frame 跟随（既有跟随链核实），落位自动带宠物。

配色：
- 未填充轨道由「同色 25% 透明」改为同色系实色压暗（新增 UIColor.foliaDarkenedTrack77：HSB 亮度 ×0.42、饱和 ×0.92+0.04、alpha 恒 1）——图4「前暗后橙双截＋浮在砖面上」的观感根源是半透明轨透出封面砖面，本版整条实色、与砖面脱钩。填充段保持现行后半段主题色原值；收起态仅星空主题走强金兜底（miniCollapsedFillColor 既有口径）。
- 圆点恢复：三宿主「收起态隐藏圆点」一行（(74) 删除点）摘除，两形态恒显示；皮肤与 knob 同步挂载本就是 (22)/(23) 旧制（13pt 皮肤压 9pt 钮身溢出显示），与播放台主题特效开关的联动沿旧制（开关关→两台素面、皮肤不挂、回落素色小圆点）。

## ③ 闪屏（设置台点按）——静态证据链闭合、修法已落，定级：待下轮日志对位（未定案）

- 静态审：设置台点按展开路径上，唯一的逐帧重合成操作是 (76) 新增的 applyWrapBandMorph——CASpringAnimation 对带 mask 的 UIVisualEffectView（毛玻璃）逐帧改 mask path，毛玻璃须按帧重采样背景，是该路径上唯一的重绘热点；其余步骤（alpha/约束）均为合成器廉价操作。(76) 日志报障时段落在 22:46–22:54 缺口内，seam.morph76 无对位样本，故不定案。
- 修法：applyWrapBandMorph 整组摘除，改与内容组同一条系统弹簧的 alpha 交叉淡化（带身只在收起薄框与全透明之间淡变，无逐帧几何形变）；平形态 blurView 的 transform 缩放一并摘除。面包屑 seam.morph76 的 tap/exp/col/done/lay 五记保留（语义改注为交叉淡化相位），新增 seam.flash77 path=xfade——下轮日志若闪屏仍在且 morph 对位干净，即可排除形变路径转查他段。

## ④ 「…」菜单整页取消（代码已改，待真机）

摘除：工具条 moreButton＋onMoreTapped、WallMoreMenu 枚举、四宿主页/歌单页/舞台/收藏页的接线、SeamToolbarForwarding 的 "more" 分支、主页 seamMoreTapped 整段落点（留墓碑注释）。分段控件宽 104→137 补回「…」的 33pt（工具条总宽恒 356pt、几何不漂移）。

连带功能去向（逐项核实过入口）：
- 喜欢的音乐：直达落点随页取消；替代在——主页墙「歌」段歌单卡里有「我喜欢的音乐」（与菜单同源的歌单数据 specialType=5），点卡进歌单页。
- 云盘：替代在——点播台命令面板内有云盘入口（CommandPaletteViewController）。菜单直达取消。
- 过滤当前页：无其他入口，随页取消（seamFilterBar 代码 dormant 保留，未删）。
- 管理隐藏：无其他入口，随页取消（HiddenPlaylistsViewController 类 dormant 保留；已隐藏名单数据不动、隐藏效果在各列表照旧生效，只是暂时没有解隐入口）。
- 回到播放页：替代在——点播台双击开台、展开条点封面进播放详情。
- 歌单：主页墙「歌」段即歌单面，替代在。
- 电台：独立电台页（WorkbenchRadioViewController）原仅菜单可达，随页取消（类 dormant 保留）；推荐内容走「推」段。
- 专辑：专辑列表页原仅菜单可达，随页取消（类 dormant 保留）；单张专辑仍可从墙卡/搜索结果进入。
- 本地：替代在——命令面板与主页 nav.local 均可达。

## ⑤ 爪印上台替换随机播放（代码已改，待真机）

- 点播台快速行（MiniBarQuickRowView，三宿主共用同一组件）第三钮位：打乱 → 爪印（pawprint.fill＋「宠物」标签）。随机播放撤下台面，去向：队列面板（QueuePanelViewController）与命令面板（CommandPaletteViewController）内仍有「打乱队列」入口，QueueManager.shuffleQueue 本体保留。
- 爪印语义与退役的窗口爪印完全同路：切换核抽为共享 PetSummonButton70.performPawToggle77（写入收口、告别/掉落/广播兜底、岛民对账全同）；台面入口 src=deck2s/deck3s、act 记 paw.act77（窗口版原 paw.act75 不变）。阈值按现态（(76) 首启恢复后开关现态 on）：开态长按 3.0s 关闭、关态 2.0s 召唤；阈值在 hitTest 落到爪印钮时现读刷新（与窗口爪印同纪律）；按下瞬间先回调宿主续命浮层 5 秒闲置钟（防 3 秒长按被闲置收起打断）；长按触发后吞掉抬手的短按事件（星标同款标记）；短按只给提示 toast（「长按爪印 2 秒，召唤小宠物」/「长按爪印 3 秒，送小宠物回家」）——长按语义靠它可发现。
- 窗口浮动爪印退役：SceneDelegate 摘 install；PetSummonButton70 本体保留为切换核与（入场抑制接口的）空操作宿主，EntryIntro 两处 setEntrySuppressed 调用恒为空操作无副作用。
- 其他爪印语义牵连交代：岛上拖拽换住客（PetIslandLayer 内的拖拽落座）与本钮无关、不受影响；长按宠物本体 3 秒关闭的老路未动；设置页开关未动。

## ⑥ 播放条点击展开（根因已证实，修法已落，待真机＋下轮日志逐环验）

根因（(76) 会话日志坐实）：歌单页 2 次点按全到达、全死于 minibar.dead76 at=cancel recog=001（noRecog 零次）；tap1 与 nowplaying.route settle（reason=user-interaction-cancel）同一毫秒相撞——路由提前 206ms 已启动、带 root-detached 重试在飞，路由的视图重挂把在飞的细条触摸取消。修法三件：
1. 认领先行：MiniBarHitView 收起态 touchesBegan 即 RouteInteractionHold.shared.begin()（引用计数＋1.5s 自动过期兜底），落 minibar.claim77 host=<wallproto|homewall|stage>；SceneDelegate.routeStep 顶部咨询 hold，held 时以 reason=user-hold 短延迟 0.12s 让行、不计 attempts、同原因去重落痕。touchesEnded/Cancelled 配对 end。
2. 取消救援：hitView 记录按下时刻/落点/最大位移；touchesCancelled 时若是静止短点（<0.35s、位移 <10pt）且无识别器认领——先走既有 dead76 见证，再由宿主当作点按展开并落 minibar.disp77 via=rescue。路由 churn 若再取消触摸，展开照样成立（双保险）。
3. churn 收敛：routeRetryOrGiveUp 改退避 0.12/0.25/0.5s、上限 10→6 拍；no-current-track 快速让路分支同步 <6。
自证链：claim77（认领）→ disp77 via=tap|rescue（派发）→ minibar.expand（展开，既有），三宿主同构；主页与舞台本版补齐此前缺失的 dead76 见证（主页新增 miniTapBits 记 recog 三位）。三宿主展开落点各归其位（主页 expandMiniBar、歌单页 expandMiniBar、舞台 expandStageBar）。

## ⑦ 全屏展开软锁（报障时段在日志缺口内、覆盖者未定案；结构性修法已落，待真机）

- 静态审结论：旧退出机制是一块全屏透明热区视图（seamImmersiveTapView），靠 bringSubviewToFront 抢层位——它本身及抢层动作就是「全屏覆盖」构件；PetDockLayer 命中已核实干净、PetHitProxyView 只占顶部 120pt 带，均不是全屏覆盖者。具体是谁在 (76) 时盖死主页，报障时段无日志，不定案。
- 结构性修法：热区视图整件摘除（装配/引用全清）。退出识别器改挂 HomeWall 根视图（祖先识别器与兄弟视图 z 序无关）、cancelsTouchesInView=false、仅沉浸期 isEnabled——新结构里不存在任何全屏覆盖视图，中间态也无可吞触摸的构件。自证：进入落 seam.lock77 in；点按退出落 seam.lock77 out via=tap pass=1（pass=1 即同一下点按穿透续达墙面内容、不被吞）；其他路径退出落 via=other。

## ⑧ 岛内宠物让位（代码已改，待真机）——三态分开写

触发源（逐个列明）：np＝镜像发布面报告播放中（系统正在播放占岛变宽，(76) 图5 实证）；screen＝UIScreen.isCaptured（录屏/投屏指示占岛，Miller 23:18 录屏实证）。任一在场即让位、全清才回位；面包屑 isl.yield77 on/off 带 src=np|screen|np+screen 区分。

- app 内镜像让位：PetIslandLayer 槽位偏移 81→121（系统岛播放中实测宽约 202、半宽约 101；101＋3 缝＋宠物半宽 17＝121），框底两段按有效偏移同派生跟随；让位/回位走 reseatAll 的 iOS 系统弹簧。(76) 日志实证的健康链（la.upd75 8/8 带双 id、isl.mirror76 发声 7 次）未动，只在发布面边沿多读 isPlaying 喂让位源。
- app 外播放中让位（⑧细则）：relevance 收口——播放＋后台＝10（让位值），播放＋前台＝100，暂停＝50（原口径）。退后台边沿当即推一发让位更新（reason=bg），不等切歌。格局：系统正在播放占大格，我方被系统贬到侧边小圆圈时呈 minimal 形态＝左住客图（缺省 cat-live 捂脸猫；该形态 (75) 起即如此定义，本版核实合规、未改），狗暂退；暂停/停播恢复 50 夺回大格、双宠物归位。让位/夺回落 la.yield77 rel=10／la.back77 rel=<值>（与 la.yield76/la.back76 的活动生命周期线分开记）。**如实标注：升降最终由系统仲裁，relevance 只能偏置，不能保证必达。**
- app 外非播放：方案 A 缺省格局不变（双宠物守大格、relevance 50）。
- 录屏在 app 外：系统录屏指示优先占岛，我方无可动面（compact 槽位由系统排布），只能等系统给位——本版让位逻辑只覆盖 app 内镜像层，如实标注。

## ⑨ 设置台贴岛（与①同面施工，逐态实数）

- 收起绕岛带：凹口间隙维持 3pt，即下限——凹口弧（r21.5）与岛胶囊（r18.5）同心、半径差恰 3pt；再小则 1pt 描边（±0.5）＋抗锯齿会与岛黑体视觉相触，且抓手命中垫在左臂不在凹口内，3pt 不损可用性。
- 展开行顶沿（逐宿主实测几何）：主页 54（岛底 48＋6；凹口底 51＋3 同值）；歌单页 115（本页关闭键行自 safeArea.top+8 起、高 44、下沿再 +4——工具条整排 356pt 与关闭键同行装不下，是 (75) 定版几何，非面板留白）；舞台 141（舞台头自 safe.top+6 起、样式钮行至 +74、下沿 +8）。图2 里岛与控件之间的大片空区是面板填充本身，①摘除后不复存在；行位本身已贴各自页面家具，无可再压缩的空转间距。

## ⑩ 岛宠物语言（代码已改，待真机）

- 引擎：新建 IslandDialogue77（app 侧）。轮次编排（Miller 定）：①自嘲定稿链四句逐字入链（猫「哎，我们怎么不能动了」→狗「我也不知道，去问问主人吧」→猫「主人怎么回事，快救救我啊，我想跳舞」→狗「是啊，主人，我被卡着好难受，头都被卡爆了」，每轮开场优先演它）→②聊当前歌两句（3 组模板按推进到该段时的当前曲目填歌名/歌手，换歌即重建本段余句；无曲目跳过）→③关心一句（PetLines.carePool 时段池随机，说话侧按轮号左右轮值）→④通用五人格词库垫场（PetChat.generate 按左右住客人格拼 A 开场→B 回应→A 反应链）→起新轮。
- 内容源变更交代：(75)/(76) 的 islandHome 轮换摘除，makeState 只读引擎当前句——任何合并更新都原样带当前句，不抢拍不跳句。
- 节拍：45 秒一句（几十秒量级、ActivityKit 预算内取下限侧）。仅「活动在场＋app 后台＋播放中＋非汪汪队」时走拍；推进与让位/歌曲信息合并在同一发 contentChanged（reason=say77）出门，不为台词单发更新。暂停/回前台/挂起即停拍，台词停在最后一句、不伪造推进。汪汪队样式生效期间：活动 end＋引擎复位＋停拍，台词线随宠物全撤口径关闭。
- 呈现：ContentState 新增 phraseSide（0 左/1 右）。展开岛：台词移出中央列、入底部区成独立行（歌名/歌手保留在中央、播放态行保留在底部），按说话侧左/右对齐＋爪印小标；锁屏面：台词从信息列移出成独立行、同口径按侧对齐。compact 与 minimal 不放文字（现状即如此，未动）。
- 面包屑：每次推进落 la.say77 ch=<轮号> step=<本轮句序> side=L|R ph=script|song|care|filler；活动开场首句同记。

## 追加审计一：miniPets 开关又被写关（(76) 会话日志新警情）

- 全仓写点核实：StickerSettings.setMiniPetsEnabled(_:src:) 是唯一带留名的收口（双写新旧两键）；裸写只有两处且都在收口内部。**真实旁路定性**：SettingsConfigTransfer.importCode 对白名单键裸 defaults.set——含 miniPets 新键，只写新键、绕 src 留名、且造成双键脱同步；调用方为设置页导入与 SyncService62 同步拉取自动应用。
- 但须如实分级：importCode 写不了旧键，单独不能解释 (76) 覆盖段读到的旧键 false——写关发生在 22:46–22:54 日志缺口内，机制**仍未证实**（候选的 petPress3s/paw3s 两条收口路径在缺口内不可观测，不排除缺口内发生过收口写入而留名行不在本段日志文件中）。
- (77) 处置：①importCode 的 miniPets 键改走 setMiniPetsEnabled(src: "import") 收口（旁路封死、双键恒同值）；②读侧见证 pet.audit77——启动行落双键原始存在性/值（new/legacy 各记），运行中 StickerSettings 读值翻转（去重）落 v＋first，下轮日志可钉翻转时刻与脱同步与否。

## 追加审计二：tap76 落点补全（舞台单击）

(76) 全文仅 1 条 stage.tap76 gate=timer、无 fire/cancel 的定级维持「未定案」。本版补齐缺口落点：守卫失败落 cancel why=window|suppress、重排期取消落 why=resched、离台取消落 why=exit（fire/sched/skip=triple/三击 cancel 既有保留）。下轮真机单击样本可逐环判读。

## iOS 适配自查（逐项）

- 横竖屏双向：②底锚按安全区读值切换、横屏（安全区底 21）同式成立（轨道中心随安全区走）；⑧让位几何为竖屏岛口径（横屏无岛、镜像层 isPortrait 门控既有）；①⑨工具条横屏带底几何既有未动；⑦识别器挂根视图与朝向无关。
- 安全区/灵动岛避让：②收起轨道与 indicator 同带是本项的设计目标（居中重合、非遮挡）；⑧让位专为岛占用变宽而设；⑨凹口间隙 3pt 下限依据见⑨。
- 系统手势不冲突：⑤台面爪印长按 recognizer cancelsTouchesInView=false、allowableMovement 12，不拦页面手势；⑥hitView 既有手势共存协议（require(toFail:) 链）未动，hold 只影响路由层不碰手势；⑦退出识别器仅沉浸期启用、cancelsTouchesInView=false，不与墙面滚动/点按抢占。
- 深色外观与字号下限：②轨道压暗为 HSB 派生色、深浅外观下均实色可辨；⑩台词字号沿既有 caption2（系统下限内），未新增小字。
- 目标机型（iPhone 14 Pro）：⑧让位 121 偏移按本机岛宽实测推导；②+31.5 按本机安全区 34/indicator 几何推导，他机型走同公式（安全区读值驱动、无 indicator 回落）。

## 待真机清单

1. ①设置台展开：控件浮墙面、无框无底；收起薄框贴岛在位；展开/收起弹簧观感。
2. ②收起条与 home indicator 重合为一条线；展开/收起切换落位；四主题圆点在位（逐主题）；轨道压暗后进度可辨。
3. ③点设置台展开/收起是否还闪（带新日志回判 morph 对位）。
4. ④「…」入口消失；分段补位后整排观感；喜欢歌单从墙卡可达。
5. ⑤三宿主台面爪印：短按出提示、长按 2s 召唤/3s 告别（按现态）；随机播放从队列/命令面板可达；右下角窗口爪印消失后无残留遮挡。
6. ⑥三宿主细条点按展开（重点歌单页连点）；日志 claim77→disp77→expand 三环。
7. ⑦全屏沉浸：点外退出且穿透；seam.lock77 三记。
8. ⑧app 内播放/录屏时镜像宠物贴岛外沿、停播/停录回位（isl.yield77 src 对位）；app 外播放中系统大格＋小圆圈呈猫、暂停后双宠物夺回（la.yield77/la.back77 对位；系统仲裁不保证必达）。
9. ⑩后台播放时展开岛/锁屏台词 45 秒一换、自嘲链开场、聊歌句带当前歌名、说话侧对齐正确；暂停停在最后一句。
10. 开关审计：pet.audit77 启动行双键值；若再现自动写关，翻转行时刻对位。

构建与验包结果见报告头（CI 45207757172 success、验包四项已核）。本报告内所有功能项均为「代码已改＋验包过」档，未经 Miller 真机验收，不作已修好宣称。


