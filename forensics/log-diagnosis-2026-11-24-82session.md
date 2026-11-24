# (82) 真机会话日志判读（2026-11-24）

日志：`~/workspace/user/files/upload-ed0082d9.txt`，148,366 B / 1201 行，全 [INFO]，ERROR/WARN/fatal **0 条**。
代码：release-82（判读时工作树 release-83 与 release-82 同点 dd942f2c、干净，所引代码即 (82) 代码）。

## 窗口与会话结构（先说清，后面每条都受它约束）

文件含**三段进程生命**（时间 UTC，CST = +8）：

| 段 | 起 | 止 | 说明 |
|---|---|---|---|
| S1 | 12:11:12.069（body 首行） | **12:13:12.854 死亡** | 导出自会话中段开始，本段启动点不在文件内（无 app.build） |
| S2 | 12:13:14.237 启动（prevtail.save＋app.build build=82） | **12:14:14.351 死亡** | 与 S1 死亡间隔 1.383s |
| S3 | 12:14:55.005 启动 | 12:23:23.632（导出时仍活着） | 与 S2 死亡间隔 40.654s |

文件头「上一会话尾巴」（2–201 行）是 S2 的最后 200 条面包屑，与 body 内 778–977 行**整段重复**（prevtail 机制），下文所有计数均已去重。wit82.live 在 S2/S3 启动各落一次（ph/tap/loc/cov/fm/rot/light 全 =1），本轮面包屑通道与名册在册先行声明。

Miller 的验收动作（19:56 装包起）有一部分在 S1 起点之前，不在本文件内；本文件覆盖 20:11:12–20:23:23 CST，含他报的双击闪退**两次复现**与多段快滑。

---

## 一、快速拖动还是黑

**结论（已证实）**：(82) 的三修里，**帧尖峰已治、字面 blank 已清零，但「黑」的本体没动**——快滑时段约七成砖在配置瞬间拿不到真图、只能显示底色明度 0.23 的深色占位图，真图要等滚动停下才追上；Miller 眼里的黑砖就是这些深色占位砖。另有两处 (82) 交付与报告不符：**方向预取 prefetch82 全仓零调用、从未运行**；ph82/cvr.stat 的命中率口径结构性失真（见下）。

### 数字（去重后 10 个 wall.ph82 冲刷窗，home 7 窗＋tracks 3 窗）

- ph82 合计 **hit=4 / miss=118（3.3%）**。对照 (81)：hit7/miss320 ≈ 2%。**基本没动。**
- wall.tile78 合计 **img=34 / phimg=83 / blank=0**（总配置 117）；wall.req79 合计 **cfg=117 / req=83 / nourl=0**——三组数互洽（cfg = img+phimg；req = phimg）。
- cvr.stat：S2 窗 hit=4 miss=40（12:13:25.581Z）、S3 窗 hit=0 miss=40（12:23:10.738Z），slow(>800ms)=0 两窗皆是。
- wall.dec78 两窗：S2 wait=3/16ms、dec=3/15ms、qpk=7、starve=0；S3 wait=12/45ms、dec=10/36ms、qpk=11、starve=0。**取图队列不堵、解码不慢、单图端到端延迟在几十毫秒量级。**
- wall.scroll 18 窗：p99 区间 16.7–59.2ms（最大 59.2ms @12:14:03 home），didScrollMax ≤3.2ms，hitch ≤6.6%，lattice 在 17/18 窗 =0（仅 12:14:11 tracks =1），rebase=0、reload=0 全窗。对照 (81) 的 p99 尖峰 209.4ms——**帧尖峰这一项 (82) 真治了（−72%）**，黑砖与帧耗时脱钩。
- 快滑实况（tracks 墙）：12:14:07/08/09 连续三秒 **img=0**（phimg 9/5/2），滚动停下的 12:14:11 立刻 img=9。home 墙 12:14:01 img=0、12:13:21 img=0（phimg 14）。真图只在停滑后到达，与 dec78 的几十毫秒延迟并读，机制见下。

### 机制（日志＋代码互证）

1. **同步命中才是砖的第一印象**：cell 配置时先同步查缓存（WallPrototypeViewController cell configure：cachedImage 命中直接上图），未命中垫 any-tier 图或占位图、再异步 `image(for:)`。tile78 口径下真实「配置瞬间有真图」比例 = img/(img+phimg) = **34/117 ≈ 29%**。
2. **ph82/cvr.stat 的 hit 是假口径**：`noteStat(hit:)` 只在 `NativeCoverLoader.image(for:)`/`loadFromNetwork` 内部调用（NativeCoverLoader.swift），而 image() 只在同步查已落空后才被调——loader 层 hit 结构性 ≈0（仅竞速窗口偶中，本轮 4 次）。**拿 ph82 hit% 判缓存疗效必然得出「没治」的假结论；真口径是 tile78 的 img 占比。** 这是 (82) 报告与本次判读都必须纠正的量测设计错误。
3. **blank=0 有一半是改口径**：WallPrototypeViewController.swift:4225-4226 注释自明——(82) 起占位图在场即计 phimg，blank 只剩 pic 为空的分支。所以 blank 8→2→1（(81)）→ 0（(82)）不能直接读作「黑消失」，phimg 里混着真低档图与占位图两种东西，tile78 本身分不开（靠 req79 对读：req=phimg 说明每个 phimg 配置都发了请求，即当时无同步图）。
4. **占位图本身就是深色**：`NativeCoverLoader.placeholderColor` 哈希色 brightness=**0.23**、saturation 0.28；(82) 新占位图（placeholderImage82）以此为底色、对角渐变到 ×1.5+0.06、叠 alpha 0.28 的 ♪。静止细看是「深色音乐占位」，快滑时整墙连片即读作黑砖——与 Miller 两轮截图/口述一致（此条中「读作黑」属感知推断，标**推测**；占位色值与快滑时段 phimg 占比为**已证实**）。
5. **真图追不上不是慢，是被复用周期丢弃**：单图延迟几十毫秒（dec78 已证实），但快滑时 cell 存活时间短于完成延迟，configure 的 loadTask 完成回调以 `currentUrl == urlString` 守卫（cell 已复用即丢弃显示，图只入缓存）。停滑后 cell 稳定，图才落位（12:14:11 img=9 与此吻合）。此条机制由代码守卫＋时序对读支撑，定**已证实（机制级）**。
6. **prefetch82 从未运行（已证实）**：`NativeCoverLoader.prefetch82` 全仓 grep 除定义外**零调用点**——(82) 报告所称「方向预取」没有接线到任一墙宿主的滚动回调。快滑时新入视砖没有任何提前量。
7. 缓存键含本机端口（`proxiedURLString` 拼 `127.0.0.1:\(port)`）＋NSCache 纯内存 → **每次启动全冷**（S3 启动窗 miss=36、S2 12:13:21 miss=33 均为冷窗）；160MB 上限（NativeCoverLoader.swift:109 按像素字节计成本）本身无从在本日志验效，因为会话内复访砖太少。另：S3 尾段 12:23:12.922 有 **memwarn=1 一次**，触发 `cache.removeAllObjects()` 全清——发生在主要测试之后，单独记录，下轮注意它与黑窗时刻的对位。

**定案等级**：根因（同步未命中→深色占位成片＋完成显示被复用丢弃＋预取未接线）＝**已证实**；「占位在真机读作黑」的感知环节＝推测（有色值与两轮图证旁证）。证据已足，(83) 可按下方修法直接修，不需再取证。

---

## 二、双击播放台闪退

**结论（已证实到区间／未确认到行）**：本文件内有**两次同构进程终止**，都发生在歌单墙（wallproto）迷你台双击开台的呈现途中，终止点被夹在 `StageViewController` viewDidLoad 内部、`buildStageBar()` 执行过 attach 落痕之后、viewWillAppear 之前；`stage.present.done` 两次都没出现。**具体 fault 行日志定不了，缺 .ips 崩溃日志**（取法见文末）。

### 两次死亡序列（面包屑逐字同构，相差仅时间戳）

S1（body 633–648 行）／S2（body 959–977 行，尾巴段 183–201 行同内容）：

```
minibar.touch75 host=wallproto col=0 h=132 ×2
mb.tch78 b / e
minibar.touch75 ×2 → mb.tch78 b
minibar.doubletap host=wallproto action=stage        S1 12:13:12.795 / S2 12:14:14.328
tap.dispatch host=wallproto            （logSync）
guard.decision host=wallproto go=1 pvc=nil gate=idle （logSync）
stage open (native) from playlist wall
stage.present.begin host=wallproto     （logSync）
paw.face81 init mode=tap
stage protocol v=2 hostWordSync=1
mb.root79 on host=stage
minibar.webrow stage overlay attached h=132          S1 12:13:12.854 / S2 12:14:14.351 ← 最后一行
（此后无任何行，下一次启动 prevtail.save）
```

- 双击→最后落痕：S1 59ms、S2 23ms。present.begin→attach：49ms / 16ms。
- **缺席对位（全文件计数）**：`stage.present.done`=0、`stage gate enter`=0（viewWillAppear 首行，StageViewController.swift:775）、`stage62.install`=0（install62Chrome 首行）、`webstage host loaded`=0。本文件内**舞台从未成功打开过一次**（stage open 仅此两次、皆死）。
- 守卫自证清白：两次 guard.decision 都是 go=1、pvc=nil、gate=idle——(62)/(63) 防的「呈现竞态/第二台覆盖」不在场，`openNativeStageFromWall`（WallPrototypeViewController.swift:2763）的守卫逻辑排除。
- 内存排除：死亡时 footprint 131MB（S1）/ 87MB（S2）、availMB ≈ 3964/4008——不是 jetsam 形态；且同点位两次定点死亡与内存压力无关。
- 面包屑异步丢失的可能已评估：普通 log 为异步（Breadcrumbs.swift:16），但 tap.dispatch/stage.present.begin 两条边界行走 logSync 同步落盘（Breadcrumbs.swift:31），且 begin 与 attach 之间的 3 条异步行两次都完整存活——异步队列当时滞后 <50ms，死亡点判在 attach 之后成立。

### 嫌疑区间（文件:行号，按位置排序）

死亡区间 ＝ `StageViewController.viewDidLoad`（:671）内、`buildLayout`（:1087）→ `buildStageBar()`（调用 :1172、定义 :2778）执行到 **:2891 attach 落痕之后**、viewWillAppear（:764）之前：

1. **buildStageBar 余段（:2892 → 函数尾）**：进度轨/fill、(82) 新入的花朵把手 `DeckGlyph82.flowerImage(size: 20)`（约 :2918）、时间标签、play/prev/next 钮装配、模式/控制台钮、约束激活。本案自 (63) 起存在，(82) 新件（花朵把手）时间上不符，优先级低，但同段的长存代码（钮装配/约束）在区间内。
2. **buildLayout 余段（:1173–1197）**：`installStageSeamToolbar74()`、`refreshPlayButton()`、`refreshLikeButton()`——后两者在加载期就触碰播放引擎/喜欢态真源，是本区间内最「有状态」的三步，嫌疑优先。
3. viewDidLoad 在 buildLayout 之后、install62Chrome 首行落痕之前的收尾（通知订阅等）。

**定案等级**：终止区间＝**已证实**；fault 具体行＝**未确认**。日志侧已到极限，下轮取证二选一（或并行）：① Miller 在 设置 → 隐私与安全性 → 分析与改进 → 分析数据 里找 `Folia-2026-11-24*.ips` 发来，异常类型＋崩溃线程栈直接给行；② (83) 在上述区间插 logSync 相位行（attach 后／进度段后／钮段后／buildLayout 返回／refreshPlay·Like 前后／install62Chrome 前），下次复现即夹到单段。

---

## 三、附带核对

3. **tap82 ＝ 0 行（未确认：无样本，非哑火）**。与 (81) 不同：本轮调用点代码核实齐全——WallPrototypeViewController.swift:1197-1218（play/prev/next/console 四个 @objc 动作首行）、HomeWallViewController.swift:1955-1977、ConsolePanel82.swift:171-544（12 处）、StageViewController.swift:2432-2452；wit82.live tap=1 两启动在册。但本窗内**找不到一次可归因的台面按钮点按**：窗内切歌（12:11:42 queue push 等）无 tap82 也无 minibar.tap 相伴，两次双击按 require-to-fail 设计本就绕过单击见证，灯开关动作发生在 S1 起点之前（窗内 12:14:01 已是关灯态 focus）。Miller「控制没问题」的实测时段大半在本文件之前。结论：见证已接线、本窗无样本，不许判过也不许判死。
4. **isl.cov82 ＝ 13 行（去重），全 on=1**：page=wall ×5、page=home ×5、page=- ×3；sup=1 ×3（均为启动瞬间）、stub=1 ×3。竖屏下 home/wall 两页中央簇发布路径都有点亮落痕——日志只能证发布、不能证真机渲染（Miller 本轮已改口径要声波竖条＋横屏去掉，属下一包规格问题）。**横屏无样本**（本窗两次旋转均为 home 入场旋转，见下条）。
5. **rot82 ＝ 0 行（未确认：无样本）**。调用点在 StageViewController.swift:858/889/900（freeze/ready/landed，舞台专用）。本窗仅有两次 home 墙入场旋转（12:13:14.850 wall.rotate freeze gen=1 →852x393；12:13:25.542 gen=2 landed instances=252），舞台两次打开皆死、无从旋转。rot82 是否活着要等闪退修好后真机转一次舞台才能判。
6. **light82：focus ×2（关灯点单张有样本）**——12:14:01.860 home id=428645537 mv=0、12:14:09.363 tracks id=3417735195 mv=0，均为首点点亮；**转移（mv=1）无样本**。`light82 on=` 与 focusgate **0 行**：开关切换发生在 S1 起点之前（窗内首次 focus 时已是关灯态），开灯波浪本窗**未确认**。代码侧 setOn/setFocus 落痕点在 WallLight82.swift:59/69，核实在位。
7. **minibar.fm82 ＝ 6 行**，全 host=wall、orient=port：收起 tw=134 th=5 ×3（与 DeckLayout82 定版 134×5 一致，Deck82.swift:139-140）、展开 tw=253 th=4 ×3（墙宿主展开 seek 轨）。home/stage 两宿主调用点在位（HomeWallViewController.swift:2513、StageViewController.swift:3656）但本窗无行；**横屏无样本**。
8. **(80) 预备与导演**：prep.arm80 ×5、prep.done80 ×5（held=1 ×3 / held=0 ×2）；**prep.hit80/prep.ms80 ＝ 0 行**——落点在舞台落定路径（StageViewController.swift:2114），舞台全程未落定，无样本（同 rot82 的连带缺席）。dir81 三条完整本地链：1455485876 fire score=2 → hanabi、1467972215 tempo lpm=10 → still、458356832 love score=7 → lumiere，全 via=local；AI 模式无样本。
9. 额外：**locate82 ＝ 0 行**——本窗无迷你台封面单击样本（窗内台面交互只有双击），未确认，无从判 (82) 第 3 条疗效。

---

## 四、给 (83) 的修法结论

### 黑屏（证据已足，直接修）

1. **占位提亮止血**：`NativeCoverLoader.placeholderColor` 明度 0.23 → 提到可读量级（≥0.45），占位图渐变与 ♪ 对比同步加强——快滑时砖面先不再成片「黑」。（NativeCoverLoader.swift placeholderColor/placeholderImage82）
2. **预取接线**：把 `prefetch82` 真正挂上两墙宿主的滚动回调（方向＋速度前瞻、tier 与 cell 同式）——(82) 漏接的这件是快滑无提前量的直接原因。（NativeCoverLoader.swift: prefet
...[truncated 2087 chars]